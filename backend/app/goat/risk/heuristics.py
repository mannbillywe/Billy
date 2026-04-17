"""Deterministic risk heuristics.

These are the always-available fallback scores. They're conservative,
interpretable, and never claim model-level confidence.
"""
from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from ..contracts import ForecastLayer, RiskScore, ScopePayload
from ..data_loader import GoatDataBundle
from ..scoring import bucket_confidence, clamp, safe_div, to_float


def _severity_from_p(p: float) -> str:
    if p >= 0.75:
        return "warn"
    if p >= 0.5:
        return "watch"
    return "info"


# ─── Budget overrun risk ─────────────────────────────────────────────────────


def budget_overrun_heuristic(
    bundle: GoatDataBundle, forecast: ForecastLayer | None
) -> list[RiskScore]:
    out: list[RiskScore] = []
    budgets = {b["id"]: b for b in bundle.budgets if b.get("is_active", True)}
    if not budgets:
        return out
    # Prefer forecast trajectory if we have it.
    fc_by_budget: dict[str, Any] = {}
    if forecast:
        for t in forecast.targets:
            if t.target == "budget_overrun_trajectory" and t.entity_id:
                fc_by_budget[str(t.entity_id)] = t
    today = date.today()
    latest_period: dict[str, dict[str, Any]] = {}
    for p in bundle.budget_periods:
        bid = p.get("budget_id")
        if not bid:
            continue
        cur = latest_period.get(bid)
        if cur is None or str(p.get("period_start")) > str(cur.get("period_start")):
            latest_period[bid] = p

    for bid, b in budgets.items():
        fc = fc_by_budget.get(str(bid))
        period = latest_period.get(bid)
        limit = to_float(b.get("amount")) or 0.0
        if not period or not limit:
            out.append(
                RiskScore(
                    target="budget_overrun_risk",
                    method_used="heuristic",
                    probability=None,
                    severity="info",
                    confidence=0.3,
                    data_sufficient=False,
                    reason_codes=["no_current_period_or_limit"],
                    insufficient_data_fields=["budget_periods.current"],
                    entity_type="budget",
                    entity_id=str(bid),
                )
            )
            continue
        spent = to_float(period.get("spent")) or 0.0
        try:
            p_start = date.fromisoformat(str(period["period_start"]))
            p_end = date.fromisoformat(str(period["period_end"]))
        except (ValueError, TypeError):
            continue
        total_days = max(1, (p_end - p_start).days + 1)
        elapsed = min(total_days, max(1, (today - p_start).days + 1))
        pace = elapsed / total_days
        pct = spent / limit if limit else 0.0
        # Base probability from pace-adjusted consumption.
        excess = pct - pace
        # Shift so excess=0 → 0.2, excess=0.5 → ~0.95.
        prob = clamp(0.2 + 1.6 * excess, 0.0, 0.98)
        if fc and fc.value.get("overrun_p50"):
            prob = clamp(max(prob, 0.7), 0.0, 0.98)
        if fc and fc.value.get("overrun_p10"):
            prob = clamp(max(prob, 0.9), 0.0, 0.99)
        conf = round(clamp(0.4 + pace * 0.4, 0.0, 0.9), 4)
        out.append(
            RiskScore(
                target="budget_overrun_risk",
                method_used="heuristic",
                probability=round(prob, 4),
                severity=_severity_from_p(prob),  # type: ignore[arg-type]
                confidence=conf,
                confidence_bucket=bucket_confidence(conf),
                data_sufficient=True,
                reason_codes=[
                    f"pace:{round(pace, 2)}",
                    f"pct_spent:{round(pct, 2)}",
                ],
                entity_type="budget",
                entity_id=str(bid),
                features_used=["budgets.active", "budget_periods.current"],
                detail={
                    "spent": round(spent, 2),
                    "limit": round(limit, 2),
                    "pace_fraction": round(pace, 4),
                    "utilisation": round(pct, 4),
                    "forecast_overrun_p50": bool(fc.value.get("overrun_p50")) if fc else None,
                },
            )
        )
    return out


# ─── Missed payment risk ─────────────────────────────────────────────────────


def missed_payment_heuristic(bundle: GoatDataBundle) -> list[RiskScore]:
    today = date.today()
    horizon_start = today - timedelta(days=90)
    past = [
        o
        for o in bundle.recurring_occurrences
        if o.get("due_date")
        and str(o["due_date"]) <= today.isoformat()
        and str(o["due_date"]) >= horizon_start.isoformat()
    ]
    if not past:
        return [
            RiskScore(
                target="missed_payment_risk",
                method_used="heuristic",
                probability=None,
                severity="info",
                confidence=0.2,
                data_sufficient=False,
                reason_codes=["no_past_occurrences_90d"],
                insufficient_data_fields=["recurring_occurrences.past_90d"],
            )
        ]
    paid = [o for o in past if o.get("status") in ("paid", "confirmed")]
    missed = [o for o in past if o.get("status") in ("missed", "overdue")]
    prob = len(missed) / len(past)
    conf = clamp(0.4 + min(30, len(past)) / 80.0, 0.0, 0.9)
    return [
        RiskScore(
            target="missed_payment_risk",
            method_used="heuristic",
            probability=round(prob, 4),
            severity=_severity_from_p(prob),  # type: ignore[arg-type]
            confidence=round(conf, 4),
            confidence_bucket=bucket_confidence(conf),
            data_sufficient=len(past) >= 4,
            reason_codes=[
                f"missed:{len(missed)}",
                f"paid:{len(paid)}",
                f"total:{len(past)}",
            ],
            features_used=["recurring_occurrences.past_90d"],
            detail={
                "past_occurrences": len(past),
                "missed_occurrences": len(missed),
                "window_start": horizon_start.isoformat(),
                "window_end": today.isoformat(),
            },
        )
    ]


# ─── Short-term liquidity stress ─────────────────────────────────────────────


def liquidity_stress_heuristic(
    bundle: GoatDataBundle, forecast: ForecastLayer | None
) -> list[RiskScore]:
    eom = None
    if forecast:
        for t in forecast.targets:
            if t.target == "end_of_month_liquidity":
                eom = t
                break
    if not eom or eom.status != "ok":
        return [
            RiskScore(
                target="short_term_liquidity_stress_risk",
                method_used="heuristic",
                probability=None,
                severity="info",
                confidence=0.2,
                data_sufficient=False,
                reason_codes=[f"eom_forecast_status:{eom.status if eom else 'missing'}"],
                insufficient_data_fields=["accounts.any", "transactions.daily_coverage"],
            )
        ]
    p10 = float(eom.value.get("p10", 0.0))
    p50 = float(eom.value.get("p50", 0.0))
    starting = float(eom.value.get("starting_liquid", 1.0))
    # Probability spikes when the p10 dips toward / below zero.
    if p10 <= 0:
        prob = 0.9
    elif p50 <= 0:
        prob = 0.7
    else:
        # Convert "fraction of current liquid" into a crude probability.
        ratio = p10 / starting if starting > 0 else 1.0
        prob = clamp(1.0 - ratio, 0.0, 0.9) * 0.6
    conf = eom.confidence or 0.3
    return [
        RiskScore(
            target="short_term_liquidity_stress_risk",
            method_used="heuristic",
            probability=round(prob, 4),
            severity=_severity_from_p(prob),  # type: ignore[arg-type]
            confidence=round(conf, 4),
            confidence_bucket=bucket_confidence(conf),
            data_sufficient=True,
            reason_codes=[f"eom_p10:{round(p10, 2)}", f"eom_p50:{round(p50, 2)}"],
            features_used=["forecast.end_of_month_liquidity"],
            detail={"eom_p10": p10, "eom_p50": p50, "starting_liquid": starting},
        )
    ]


# ─── Emergency-fund breach risk ─────────────────────────────────────────────


def emergency_fund_breach_heuristic(bundle: GoatDataBundle) -> list[RiskScore]:
    inputs = bundle.goat_user_inputs or {}
    target_months = to_float(inputs.get("emergency_fund_target_months"))
    if target_months is None:
        return [
            RiskScore(
                target="emergency_fund_breach_risk",
                method_used="heuristic",
                probability=None,
                severity="info",
                confidence=0.2,
                data_sufficient=False,
                reason_codes=["no_emergency_fund_target_declared"],
                insufficient_data_fields=["goat_user_inputs.emergency_fund_target_months"],
            )
        ]
    liquid = 0.0
    for a in bundle.accounts:
        if not a.get("is_active", True):
            continue
        if (a.get("type") or "") in ("savings", "checking", "cash"):
            liquid += to_float(a.get("current_balance")) or 0.0
    spend = sum(
        to_float(r.get("amount")) or 0.0
        for r in bundle.transactions_in_range
        if r.get("type") in ("expense", "settlement_out")
    )
    span_days = max(1, (bundle.range_end - bundle.range_start).days + 1)
    monthly_spend = spend * (30.4375 / span_days)
    if monthly_spend <= 0:
        return [
            RiskScore(
                target="emergency_fund_breach_risk",
                method_used="heuristic",
                probability=None,
                confidence=0.2,
                data_sufficient=False,
                reason_codes=["no_spend_in_range"],
            )
        ]
    runway = liquid / monthly_spend
    deficit = max(0.0, target_months - runway)
    prob = clamp(deficit / max(1.0, target_months), 0.0, 1.0)
    conf = 0.7
    return [
        RiskScore(
            target="emergency_fund_breach_risk",
            method_used="heuristic",
            probability=round(prob, 4),
            severity=_severity_from_p(prob),  # type: ignore[arg-type]
            confidence=conf,
            confidence_bucket=bucket_confidence(conf),
            data_sufficient=True,
            reason_codes=[
                f"runway:{round(runway, 2)}",
                f"target:{target_months}",
            ],
            features_used=[
                "accounts.active",
                "transactions.in_range",
                "goat_user_inputs.emergency_fund_target_months",
            ],
            detail={
                "runway_months": round(runway, 2),
                "target_months": target_months,
                "gap_months": round(deficit, 2),
            },
        )
    ]


# ─── Goal shortfall risk ─────────────────────────────────────────────────────


def goal_shortfall_heuristic(
    bundle: GoatDataBundle, forecast: ForecastLayer | None
) -> list[RiskScore]:
    if not forecast:
        return []
    out: list[RiskScore] = []
    for t in forecast.targets:
        if t.target != "goal_completion_trajectory":
            continue
        if t.status != "ok":
            continue
        v = t.value
        months = float(v.get("months_remaining") or 0.0)
        required = v.get("required_monthly")
        gap = float(v.get("gap") or 0.0)
        if required is None or gap <= 0 or months <= 0:
            prob = 0.1
        else:
            # No contribution history yet; assume neutral prior.
            # Probability ramps with required/month relative to reasonable % of income.
            inputs = bundle.goat_user_inputs or {}
            income = to_float(inputs.get("monthly_income"))
            if income and income > 0:
                share = float(required) / income
                prob = clamp(share, 0.0, 0.9)
            else:
                prob = 0.3
        conf = 0.4
        out.append(
            RiskScore(
                target="goal_shortfall_risk",
                method_used="heuristic",
                probability=round(prob, 4),
                severity=_severity_from_p(prob),  # type: ignore[arg-type]
                confidence=conf,
                confidence_bucket=bucket_confidence(conf),
                data_sufficient=required is not None,
                reason_codes=[f"required_monthly:{required}"],
                entity_type="goat_goal",
                entity_id=str(t.entity_id) if t.entity_id else None,
                features_used=["goat_goals", "goat_user_inputs.monthly_income"],
                detail={
                    "required_monthly": required,
                    "months_remaining": months,
                    "gap": gap,
                },
            )
        )
    return out
