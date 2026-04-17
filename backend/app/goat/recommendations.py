"""Deterministic recommendation engine.

Reads deterministic metrics + coverage summary and emits grounded
recommendations. Phrasing is template-based; no Gemini yet. Every rec carries a
stable fingerprint so re-running the job against the same underlying facts
won't duplicate an already-open row.
"""
from __future__ import annotations

from typing import Any

from .contracts import (
    AnomalyLayer,
    CoverageSummary,
    ForecastLayer,
    RecKind,
    RecommendationOut,
    RecSeverity,
    RiskLayer,
    Scope,
    ScopePayload,
)
from .data_loader import GoatDataBundle
from .fingerprints import rec_fingerprint
from .scoring import to_float


# ─── template helpers ────────────────────────────────────────────────────────


def _rec(
    *,
    kind: RecKind,
    severity: RecSeverity,
    priority: int,
    fingerprint_keys: list[Any],
    observation: dict[str, Any],
    recommendation: dict[str, Any],
    impact: float | None = None,
    effort: float | None = None,
    confidence: float | None = None,
    entity_type: str | None = None,
    entity_id: str | None = None,
) -> RecommendationOut:
    return RecommendationOut(
        kind=kind,
        severity=severity,
        priority=max(0, min(100, int(priority))),
        impact_score=impact,
        effort_score=effort,
        confidence=confidence,
        rec_fingerprint=rec_fingerprint(kind, *fingerprint_keys),
        entity_type=entity_type,
        entity_id=entity_id,
        observation=observation,
        recommendation=recommendation,
    )


# ─── generators ──────────────────────────────────────────────────────────────


def _missing_input_recs(coverage: CoverageSummary) -> list[RecommendationOut]:
    """One 'missing_input' rec per *high-leverage* missing field."""
    priority_map = {
        "goat_user_inputs.monthly_income": 80,
        "goat_user_inputs.salary_day": 60,
        "goat_user_inputs.emergency_fund_target_months": 55,
        "accounts.any": 65,
        "budgets.any_active": 45,
        "goat_goals.any_active": 40,
    }
    sev_map: dict[str, RecSeverity] = {
        "info": "info",
        "watch": "watch",
        "warn": "warn",
    }
    recs: list[RecommendationOut] = []
    for mi in coverage.missing_inputs:
        priority = priority_map.get(mi.key, 30)
        recs.append(
            _rec(
                kind="missing_input",
                severity=sev_map.get(mi.severity, "info"),
                priority=priority,
                fingerprint_keys=["missing_input", mi.key],
                observation={
                    "field": mi.key,
                    "label": mi.label,
                    "why": mi.why,
                    "unlocks": mi.unlocks,
                },
                recommendation={
                    "action": "provide_input",
                    "field": mi.key,
                    "prompt": f"Tell Billy your {mi.label.lower()} to improve this analysis.",
                    "unlocks": mi.unlocks,
                },
                impact=0.6 if priority >= 60 else 0.3,
                effort=0.1,
                confidence=0.95,
            )
        )
    return recs


def _budget_overrun_recs(payload: ScopePayload) -> list[RecommendationOut]:
    recs: list[RecommendationOut] = []
    for m in payload.metrics:
        if not m.key.startswith("budget_") or not m.key.endswith("_utilization"):
            continue
        detail = m.detail or {}
        if not detail.get("overrun"):
            continue
        bid = m.key[len("budget_") : -len("_utilization")]
        spent = detail.get("spent")
        limit = detail.get("limit")
        pct = to_float(m.value) or 0.0
        pace = detail.get("pace_fraction") or 0.0
        recs.append(
            _rec(
                kind="budget_overrun",
                severity="warn" if pct > 1.0 else "watch",
                priority=85 if pct > 1.0 else 65,
                fingerprint_keys=["budget_overrun", bid, payload.scope],
                entity_type="budget",
                entity_id=bid,
                observation={
                    "budget_id": bid,
                    "name": detail.get("budget_name"),
                    "spent": spent,
                    "limit": limit,
                    "utilization": pct,
                    "pace_fraction": pace,
                },
                recommendation={
                    "action": "review_budget",
                    "headline": (
                        f"{detail.get('budget_name', 'This budget')} is "
                        f"{round(pct * 100)}% used at {round(pace * 100)}% of the period."
                    ),
                    "suggestion": (
                        "Pull up the most recent transactions in this category and "
                        "decide whether to cap the remaining days or raise the budget."
                    ),
                },
                impact=0.5,
                effort=0.2,
                confidence=m.confidence,
            )
        )
    return recs


def _goal_shortfall_recs(
    payload: ScopePayload, bundle: GoatDataBundle
) -> list[RecommendationOut]:
    recs: list[RecommendationOut] = []
    for m in payload.metrics:
        if not (m.key.startswith("goal_") and m.key.endswith("_gap")):
            continue
        gid = m.key[len("goal_") : -len("_gap")]
        detail = m.detail or {}
        req_monthly = detail.get("required_monthly")
        title = detail.get("title") or "Goal"
        if req_monthly is None:
            severity: RecSeverity = "info"
            priority = 35
            headline = f"{title} has no target date yet — add one to see required monthly pace."
            action = "add_target_date"
        else:
            req_monthly = float(req_monthly)
            severity = "watch" if req_monthly > 0 else "info"
            priority = 50
            headline = (
                f"To hit {title}, set aside about {round(req_monthly):,} per month until the target date."
            )
            action = "plan_monthly_contribution"
        recs.append(
            _rec(
                kind="goal_shortfall",
                severity=severity,
                priority=priority,
                fingerprint_keys=["goal_shortfall", gid],
                entity_type="goat_goal",
                entity_id=gid,
                observation={
                    "goal_id": gid,
                    "title": title,
                    "gap": m.value,
                    "required_monthly": req_monthly,
                    "months_remaining": detail.get("months_remaining"),
                },
                recommendation={
                    "action": action,
                    "headline": headline,
                },
                impact=0.45,
                effort=0.35,
                confidence=m.confidence,
            )
        )
    return recs


def _liquidity_warning_recs(
    payload: ScopePayload, bundle: GoatDataBundle
) -> list[RecommendationOut]:
    """Fires only if user declared a liquidity_floor *and* it is breached."""
    inputs = bundle.goat_user_inputs or {}
    floor = to_float(inputs.get("liquidity_floor"))
    if floor is None:
        return []
    liquid = 0.0
    for a in bundle.accounts:
        if not a.get("is_active", True):
            continue
        if (a.get("type") or "") in ("savings", "checking", "cash"):
            liquid += to_float(a.get("current_balance")) or 0.0
    if liquid >= floor:
        return []
    return [
        _rec(
            kind="liquidity_warning",
            severity="warn",
            priority=90,
            fingerprint_keys=["liquidity_warning", bundle.user_id],
            observation={"liquid_total": round(liquid, 2), "floor": floor},
            recommendation={
                "action": "review_liquidity",
                "headline": (
                    f"Liquid balances ({round(liquid):,}) are below your declared "
                    f"floor ({round(floor):,})."
                ),
            },
            impact=0.7,
            effort=0.4,
            confidence=0.9,
        )
    ]


def _uncategorized_cleanup_rec(
    payload: ScopePayload, bundle: GoatDataBundle
) -> list[RecommendationOut]:
    uncat = [t for t in bundle.transactions_in_range if not t.get("category_id")]
    if len(uncat) < 10:
        return []
    return [
        _rec(
            kind="uncategorized_cleanup",
            severity="info",
            priority=30,
            fingerprint_keys=[
                "uncategorized_cleanup",
                bundle.user_id,
                bundle.range_start.isoformat(),
            ],
            observation={
                "uncategorized_count": len(uncat),
                "range_start": bundle.range_start.isoformat(),
                "range_end": bundle.range_end.isoformat(),
            },
            recommendation={
                "action": "categorize_transactions",
                "headline": f"{len(uncat)} transactions in this period are uncategorized.",
            },
            impact=0.25,
            effort=0.3,
            confidence=0.8,
        )
    ]


def _recovery_iou_recs(bundle: GoatDataBundle) -> list[RecommendationOut]:
    overdue: list[dict[str, Any]] = []
    from datetime import date

    today = date.today()
    for e in bundle.lend_borrow_entries:
        if e.get("status") != "pending" or e.get("type") != "lent":
            continue
        due = e.get("due_date")
        if not due:
            continue
        try:
            if date.fromisoformat(str(due)) < today:
                overdue.append(e)
        except ValueError:
            continue
    if not overdue:
        return []
    amt = sum(to_float(e.get("amount")) or 0.0 for e in overdue)
    return [
        _rec(
            kind="recovery_iou",
            severity="watch",
            priority=55,
            fingerprint_keys=[
                "recovery_iou",
                bundle.user_id,
                str(len(overdue)),
            ],
            observation={"overdue_count": len(overdue), "overdue_total": round(amt, 2)},
            recommendation={
                "action": "follow_up_lent",
                "headline": (
                    f"{len(overdue)} lent amount(s) totalling {round(amt):,} are past due."
                ),
            },
            impact=0.4,
            effort=0.3,
            confidence=0.85,
        )
    ]


# ─── Phase 3 generators (anomaly / risk) ─────────────────────────────────────


def _anomaly_recs(anomalies: AnomalyLayer | None) -> list[RecommendationOut]:
    if not anomalies or anomalies.disabled:
        return []
    out: list[RecommendationOut] = []
    sev_rank = {"info": 35, "watch": 60, "warn": 75, "critical": 90}
    for a in anomalies.items:
        # Only the top-flag severities generate recs — `info` items stay as
        # read-only UI chips so we don't flood the recommendation list.
        if a.severity == "info":
            continue
        priority = sev_rank.get(a.severity, 40)
        fp_keys = ["anomaly_review", a.anomaly_type, a.entity_id or a.window_end or ""]
        out.append(
            _rec(
                kind="anomaly_review",
                severity=a.severity,
                priority=priority,
                fingerprint_keys=fp_keys,
                entity_type=a.entity_type,
                entity_id=a.entity_id,
                observation={
                    "anomaly_type": a.anomaly_type,
                    "method": a.method,
                    "score": a.score,
                    "baseline": a.baseline,
                    "window_start": a.window_start,
                    "window_end": a.window_end,
                    **a.observation,
                },
                recommendation={
                    "action": "review_anomaly",
                    "headline": a.explanation
                    or f"Unusual {a.anomaly_type.replace('_', ' ')} detected — worth a look.",
                },
                impact=0.4,
                effort=0.2,
                confidence=a.confidence,
            )
        )
    return out


def _risk_recs(risk: RiskLayer | None) -> list[RecommendationOut]:
    if not risk or risk.disabled:
        return []
    out: list[RecommendationOut] = []
    for s in risk.scores:
        if s.target != "missed_payment_risk":
            continue
        if s.probability is None or s.probability < 0.5:
            continue
        out.append(
            _rec(
                kind="missed_payment_risk",
                severity=s.severity,
                priority=75 if s.probability >= 0.75 else 60,
                fingerprint_keys=[
                    "missed_payment_risk",
                    str(s.detail.get("window_start", "")),
                    str(round((s.probability or 0) * 10)),
                ],
                observation={
                    "probability": s.probability,
                    "method_used": s.method_used,
                    "reason_codes": s.reason_codes,
                    **s.detail,
                },
                recommendation={
                    "action": "review_recurring_payments",
                    "headline": (
                        "Your recent recurring-bill history shows misses. "
                        "Consider enabling reminders or auto-pay for critical bills."
                    ),
                },
                impact=0.5,
                effort=0.2,
                confidence=s.confidence,
            )
        )
    return out


# ─── public entry point ─────────────────────────────────────────────────────


def generate(
    *,
    scope: Scope,
    bundle: GoatDataBundle,
    payload: ScopePayload,
    coverage: CoverageSummary,
    existing_open_fingerprints: set[str] | None = None,
    anomalies: AnomalyLayer | None = None,
    risk: RiskLayer | None = None,
    forecast: ForecastLayer | None = None,  # reserved for Phase 4 narrative gen
) -> list[RecommendationOut]:
    existing = existing_open_fingerprints or set()
    candidates: list[RecommendationOut] = []

    candidates.extend(_missing_input_recs(coverage))

    if scope in ("budgets", "full"):
        candidates.extend(_budget_overrun_recs(payload))
    if scope in ("goals", "full"):
        candidates.extend(_goal_shortfall_recs(payload, bundle))
    if scope in ("overview", "cashflow", "full"):
        candidates.extend(_liquidity_warning_recs(payload, bundle))
    if scope in ("overview", "cashflow", "full"):
        candidates.extend(_uncategorized_cleanup_rec(payload, bundle))
    if scope in ("debt", "full"):
        candidates.extend(_recovery_iou_recs(bundle))

    # Phase 3: statistical-layer derived recommendations.
    candidates.extend(_anomaly_recs(anomalies))
    candidates.extend(_risk_recs(risk))

    # Dedupe within this run, then vs already-open rows in DB.
    seen: set[str] = set()
    deduped: list[RecommendationOut] = []
    for r in candidates:
        if r.rec_fingerprint in seen or r.rec_fingerprint in existing:
            continue
        seen.add(r.rec_fingerprint)
        deduped.append(r)

    deduped.sort(key=lambda r: (-r.priority, r.kind))
    return deduped
