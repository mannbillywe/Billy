"""Anomaly detection pipeline.

Two-stage strategy:

  1. Robust/deterministic checks first (MAD-based spikes, bill jumps, budget
     pace acceleration, liquidity floor, duplicate patterns).
  2. IsolationForest second, ONLY when ≥ 60 days of spend history exist AND
     sklearn is installed.

We suppress ML-only anomalies when deterministic evidence is weak and data is
sparse — avoids noisy false positives on users who just started with Billy.
"""
from __future__ import annotations

import logging
import statistics
from datetime import date, timedelta
from typing import Any

from ..contracts import AnomalyItem, AnomalyLayer, ScopePayload
from ..data_loader import GoatDataBundle
from ..scoring import bucket_confidence, clamp, to_float, utcnow_iso
from ..versions import MODEL_VERSIONS
from . import isoforest, robust

log = logging.getLogger(__name__)

# ─── Thresholds ──────────────────────────────────────────────────────────────

MIN_HIST_DAYS = 14          # below this, the whole layer is suppressed
AMOUNT_SPIKE_Z = 3.5
RECURRING_JUMP_PCT = 0.3    # 30% above trailing median triggers
BUDGET_PACE_MULT = 1.6      # 1.6x pace considered acceleration
LOW_LIQUIDITY_MONTHS = 1.0
DUPLICATE_WINDOW_DAYS = 2


# ─── Deterministic detectors ────────────────────────────────────────────────


def _parse_date(v: Any) -> date | None:
    try:
        return date.fromisoformat(str(v)[:10])
    except (TypeError, ValueError):
        return None


def _amount_spike_category(bundle: GoatDataBundle) -> list[AnomalyItem]:
    """Per category, MAD-z-score today's transactions vs trailing history."""
    # Group historical amounts by category from prior window.
    from collections import defaultdict

    hist_by_cat: dict[str, list[float]] = defaultdict(list)
    for r in bundle.transactions_prior_range:
        if r.get("type") not in ("expense", "settlement_out"):
            continue
        cat = r.get("category_id") or "uncategorized"
        hist_by_cat[cat].append(abs(to_float(r.get("amount")) or 0.0))

    items: list[AnomalyItem] = []
    for r in bundle.transactions_in_range:
        if r.get("type") not in ("expense", "settlement_out"):
            continue
        amt = abs(to_float(r.get("amount")) or 0.0)
        if amt <= 0:
            continue
        cat = r.get("category_id") or "uncategorized"
        hist = hist_by_cat.get(cat, [])
        if len(hist) < 6:
            continue
        z = robust.robust_z(amt, hist)
        if z < AMOUNT_SPIKE_Z:
            continue
        med = statistics.median(hist)
        items.append(
            AnomalyItem(
                anomaly_type="amount_spike_category",
                method="robust_mad",
                severity="watch" if z < 5 else "warn",
                score=round(z, 2),
                confidence=round(clamp(0.5 + min(len(hist), 60) / 200.0), 4),
                confidence_bucket=bucket_confidence(
                    clamp(0.5 + min(len(hist), 60) / 200.0)
                ),
                reason_codes=[f"mad_z:{round(z, 2)}"],
                entity_type="transaction",
                entity_id=str(r.get("id")),
                window_start=str(bundle.transactions_prior_range[0].get("date"))
                if bundle.transactions_prior_range
                else None,
                window_end=str(r.get("date")),
                baseline={
                    "median": round(med, 2),
                    "sample_size": len(hist),
                    "category_id": cat,
                },
                observation={
                    "amount": round(amt, 2),
                    "date": str(r.get("date")),
                    "title": r.get("title"),
                    "category_id": cat,
                },
                explanation=(
                    f"This {cat} charge is ~{round(amt/med, 1)}x the category's "
                    f"historical median ({round(med, 2)} over {len(hist)} samples)."
                ),
            )
        )
    return items


def _recurring_bill_jump(bundle: GoatDataBundle) -> list[AnomalyItem]:
    from collections import defaultdict

    by_series: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for o in bundle.recurring_occurrences:
        sid = o.get("series_id")
        if not sid:
            continue
        by_series[sid].append(o)

    items: list[AnomalyItem] = []
    for sid, occurrences in by_series.items():
        paid = [o for o in occurrences if o.get("status") in ("paid", "confirmed")]
        if len(paid) < 4:
            continue
        paid.sort(key=lambda o: str(o.get("due_date") or ""))
        latest = paid[-1]
        history = [
            to_float(o.get("actual_amount")) or to_float(o.get("expected_amount")) or 0.0
            for o in paid[:-1]
        ]
        history = [h for h in history if h > 0]
        if len(history) < 3:
            continue
        latest_amt = (
            to_float(latest.get("actual_amount"))
            or to_float(latest.get("expected_amount"))
            or 0.0
        )
        if latest_amt <= 0:
            continue
        med = statistics.median(history)
        if med <= 0:
            continue
        jump = (latest_amt - med) / med
        if jump < RECURRING_JUMP_PCT:
            continue
        items.append(
            AnomalyItem(
                anomaly_type="recurring_bill_jump",
                method="residual_check",
                severity="watch" if jump < 0.75 else "warn",
                score=round(jump, 2),
                confidence=0.8,
                confidence_bucket="medium",
                reason_codes=[f"jump_pct:{round(jump * 100, 1)}"],
                entity_type="recurring_series",
                entity_id=str(sid),
                window_end=str(latest.get("due_date")),
                baseline={"median": round(med, 2), "sample_size": len(history)},
                observation={
                    "latest_amount": round(latest_amt, 2),
                    "due_date": str(latest.get("due_date")),
                },
                explanation=(
                    f"Latest bill {round(latest_amt, 2)} is {round(jump * 100)}% "
                    f"above its trailing median ({round(med, 2)})."
                ),
            )
        )
    return items


def _budget_pace_acceleration(bundle: GoatDataBundle) -> list[AnomalyItem]:
    today = date.today()
    items: list[AnomalyItem] = []
    # Most recent period per budget.
    latest_period: dict[str, dict[str, Any]] = {}
    for p in bundle.budget_periods:
        bid = p.get("budget_id")
        if not bid:
            continue
        cur = latest_period.get(bid)
        if cur is None or str(p.get("period_start")) > str(cur.get("period_start")):
            latest_period[bid] = p
    for b in bundle.budgets:
        if not b.get("is_active", True):
            continue
        bid = b["id"]
        p = latest_period.get(bid)
        if not p:
            continue
        spent = to_float(p.get("spent")) or 0.0
        limit = to_float(b.get("amount")) or 0.0
        if limit <= 0:
            continue
        try:
            p_start = date.fromisoformat(str(p["period_start"]))
            p_end = date.fromisoformat(str(p["period_end"]))
        except (ValueError, TypeError):
            continue
        total_days = max(1, (p_end - p_start).days + 1)
        elapsed = min(total_days, max(1, (today - p_start).days + 1))
        pace = elapsed / total_days
        pct_spent = spent / limit if limit else 0.0
        if pace <= 0:
            continue
        accel_ratio = pct_spent / pace
        if accel_ratio < BUDGET_PACE_MULT:
            continue
        items.append(
            AnomalyItem(
                anomaly_type="budget_pace_acceleration",
                method="rule",
                severity="warn" if accel_ratio >= 2 else "watch",
                score=round(accel_ratio, 2),
                confidence=0.8,
                confidence_bucket="medium",
                reason_codes=[
                    f"pace:{round(pace, 2)}",
                    f"pct_spent:{round(pct_spent, 2)}",
                ],
                entity_type="budget",
                entity_id=str(bid),
                window_start=p_start.isoformat(),
                window_end=p_end.isoformat(),
                baseline={"pace_fraction": round(pace, 4)},
                observation={
                    "budget_name": b.get("name"),
                    "spent": round(spent, 2),
                    "limit": round(limit, 2),
                    "pct_spent": round(pct_spent, 4),
                    "accel_ratio": round(accel_ratio, 2),
                },
                explanation=(
                    f"{b.get('name')} is {round(pct_spent * 100)}% used at "
                    f"{round(pace * 100)}% of the period — {round(accel_ratio, 2)}× pace."
                ),
            )
        )
    return items


def _low_liquidity_pattern(bundle: GoatDataBundle) -> list[AnomalyItem]:
    # Rough runway: liquid / monthly_expense_avg.
    liquid = 0.0
    for a in bundle.accounts:
        if not a.get("is_active", True):
            continue
        if (a.get("type") or "") in ("savings", "checking", "cash"):
            liquid += to_float(a.get("current_balance")) or 0.0
    if liquid <= 0:
        return []
    rows = bundle.transactions_in_range
    spend = sum(
        to_float(r.get("amount")) or 0.0
        for r in rows
        if r.get("type") in ("expense", "settlement_out")
    )
    span_days = max(1, (bundle.range_end - bundle.range_start).days + 1)
    monthly_spend = spend * (30.4375 / span_days)
    if monthly_spend <= 0:
        return []
    runway = liquid / monthly_spend
    if runway >= LOW_LIQUIDITY_MONTHS:
        return []
    return [
        AnomalyItem(
            anomaly_type="low_liquidity_pattern",
            method="rule",
            severity="warn" if runway < 0.5 else "watch",
            score=round(runway, 3),
            confidence=0.75,
            confidence_bucket="medium",
            reason_codes=[f"runway_months:{round(runway, 2)}"],
            baseline={"monthly_spend_avg": round(monthly_spend, 2)},
            observation={
                "liquid_total": round(liquid, 2),
                "monthly_spend_avg": round(monthly_spend, 2),
                "runway_months": round(runway, 2),
            },
            explanation=(
                f"Liquid balances ({round(liquid):,}) only cover about "
                f"{round(runway, 2)} month(s) at current spend."
            ),
        )
    ]


def _duplicate_like_pattern(bundle: GoatDataBundle) -> list[AnomalyItem]:
    from collections import defaultdict

    groups: dict[tuple, list[dict[str, Any]]] = defaultdict(list)
    for r in bundle.transactions_in_range:
        if r.get("type") not in ("expense", "settlement_out"):
            continue
        d = _parse_date(r.get("date"))
        amt = to_float(r.get("amount"))
        if d is None or amt is None:
            continue
        # Bucket by (amount rounded, category, week-key).
        key = (
            round(abs(amt), 2),
            r.get("category_id") or "uncategorized",
            d.toordinal() // DUPLICATE_WINDOW_DAYS,
        )
        groups[key].append(r)
    items: list[AnomalyItem] = []
    for key, rows in groups.items():
        if len(rows) < 3:
            continue
        rows.sort(key=lambda r: str(r.get("date") or ""))
        items.append(
            AnomalyItem(
                anomaly_type="duplicate_like_pattern",
                method="rule",
                severity="watch",
                score=float(len(rows)),
                confidence=0.7,
                confidence_bucket="medium",
                reason_codes=[f"count:{len(rows)}", f"amount:{key[0]}"],
                window_start=str(rows[0].get("date")),
                window_end=str(rows[-1].get("date")),
                baseline={"category_id": key[1]},
                observation={
                    "repeat_count": len(rows),
                    "amount": key[0],
                    "transaction_ids": [r.get("id") for r in rows],
                },
                explanation=(
                    f"{len(rows)} near-identical charges of {key[0]} in "
                    f"{DUPLICATE_WINDOW_DAYS}-day windows — possible duplicate."
                ),
            )
        )
    return items


def _noisy_import_cluster(bundle: GoatDataBundle) -> list[AnomalyItem]:
    if not bundle.statement_imports:
        return []
    items: list[AnomalyItem] = []
    for imp in bundle.statement_imports:
        total = to_float(imp.get("rows_total")) or to_float(imp.get("row_count")) or 0
        uncat = to_float(imp.get("rows_uncategorized")) or 0
        if not total or total < 10:
            continue
        ratio = uncat / total if total else 0
        if ratio < 0.5:
            continue
        items.append(
            AnomalyItem(
                anomaly_type="noisy_import_cluster",
                method="rule",
                severity="info",
                score=round(ratio, 2),
                confidence=0.7,
                confidence_bucket="medium",
                reason_codes=[f"uncategorized_ratio:{round(ratio, 2)}"],
                entity_type="statement_import",
                entity_id=str(imp.get("id")),
                observation={
                    "rows_total": total,
                    "rows_uncategorized": uncat,
                    "ratio": round(ratio, 2),
                },
                explanation=(
                    f"Statement import had {round(ratio * 100)}% uncategorized rows — "
                    f"categorization may need a review before analytics trust them."
                ),
            )
        )
    return items


# ─── ML path (optional) ─────────────────────────────────────────────────────


def _isolation_forest_outliers(bundle: GoatDataBundle) -> list[AnomalyItem]:
    """Run IF on daily-spend when enough history exists."""
    from .isoforest import score_daily

    from ..forecasting.features import daily_spend_series  # lazy to keep imports light

    dated = daily_spend_series(bundle)
    values = [v for _, v in dated]
    if len(values) < 60:
        return []
    scores = score_daily(values)
    if not scores:
        return []
    # Flag only the top 2 scored days above a hard floor.
    ranked = sorted(enumerate(scores), key=lambda kv: kv[1], reverse=True)
    out: list[AnomalyItem] = []
    for idx, s in ranked[:2]:
        if s < 0.55:  # contamination=0.05 → scores float around 0.4; >0.55 is notable
            break
        d, amt = dated[idx]
        out.append(
            AnomalyItem(
                anomaly_type="isolation_outlier",
                method="isolation_forest",
                severity="info",
                score=round(float(s), 3),
                confidence=0.5,
                confidence_bucket="low",
                reason_codes=[f"isoforest_score:{round(s, 3)}"],
                window_start=str(dated[0][0]),
                window_end=str(dated[-1][0]),
                observation={"date": d.isoformat(), "day_total": amt},
                explanation=(
                    "IsolationForest flagged this day's total as unusual vs the "
                    "broader spend distribution."
                ),
            )
        )
    return out


# ─── Public entry point ─────────────────────────────────────────────────────


def run_anomaly_layer(
    bundle: GoatDataBundle, _payload: ScopePayload | None = None
) -> AnomalyLayer:
    layer = AnomalyLayer(
        version=MODEL_VERSIONS.get("anomaly", "0.1.0"),
        generated_at=utcnow_iso(),
        methods_available={
            "robust_mad": True,
            "rule": True,
            "isolation_forest": isoforest.is_available(),
        },
    )

    span_days = (bundle.range_end - bundle.range_start).days + 1
    if span_days < MIN_HIST_DAYS:
        layer.disabled = True
        layer.disabled_reason = f"history_window_too_small:{span_days}_days"
        return layer

    items: list[AnomalyItem] = []
    items.extend(_amount_spike_category(bundle))
    items.extend(_recurring_bill_jump(bundle))
    items.extend(_budget_pace_acceleration(bundle))
    items.extend(_low_liquidity_pattern(bundle))
    items.extend(_duplicate_like_pattern(bundle))
    items.extend(_noisy_import_cluster(bundle))
    # ML second — only if deterministic signal is non-trivial OR history is deep.
    if len(bundle.transactions_in_range) + len(bundle.transactions_prior_range) >= 120:
        items.extend(_isolation_forest_outliers(bundle))
    # Sort by severity × score desc.
    sev_weight = {"critical": 4, "warn": 3, "watch": 2, "info": 1}
    items.sort(key=lambda i: (-sev_weight.get(i.severity, 0), -(i.score or 0)))
    layer.items = items
    return layer
