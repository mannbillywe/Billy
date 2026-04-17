"""Deterministic analytics for Goat Mode v1.

Strictly math + stats of existing data. No forecasting, no ML, no Gemini.
Every metric carries its own confidence, reason codes, and input provenance so
the UI can explain *why* a number is what it is even at L1.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from typing import Any

from .contracts import (
    ConfidenceBucket,
    Metric,
    ReadinessLevel,
    Scope,
    ScopePayload,
    SnapshotStatus,
)
from .data_loader import GoatDataBundle
from .missing_inputs import requirements_met
from .scoring import bucket_confidence, clamp, safe_div, to_float

# ─── aggregation primitives ──────────────────────────────────────────────────


def _sum_by_type(rows: list[dict[str, Any]]) -> dict[str, float]:
    acc: dict[str, float] = defaultdict(float)
    for r in rows:
        amt = to_float(r.get("amount")) or 0.0
        acc[r.get("type") or "unknown"] += amt
    return dict(acc)


def _income_total(rows: list[dict[str, Any]]) -> float:
    totals = _sum_by_type(rows)
    # Treat refunds as negative expense, settlement_in as inflow, income as inflow.
    return totals.get("income", 0.0) + totals.get("settlement_in", 0.0) + totals.get("refund", 0.0)


def _expense_total(rows: list[dict[str, Any]]) -> float:
    totals = _sum_by_type(rows)
    return totals.get("expense", 0.0) + totals.get("settlement_out", 0.0)


def _span_days(start: date, end: date) -> int:
    return max(1, (end - start).days + 1)


# ─── Overview ────────────────────────────────────────────────────────────────


def _metric_net_worth(bundle: GoatDataBundle) -> Metric:
    active = [a for a in bundle.accounts if a.get("is_active", True)]
    if not active:
        return Metric(
            key="net_worth",
            value=None,
            unit=bundle.profile.get("preferred_currency") if bundle.profile else "INR",
            confidence=0.0,
            confidence_bucket="unknown",
            reason_codes=["no_accounts"],
            inputs_missing=["accounts.any"],
        )
    total = 0.0
    for a in active:
        bal = to_float(a.get("current_balance")) or 0.0
        total += bal if a.get("is_asset", True) else -bal
    conf = 0.9 if len(active) >= 2 else 0.6
    return Metric(
        key="net_worth",
        value=round(total, 2),
        unit=active[0].get("currency") or "INR",
        confidence=conf,
        confidence_bucket=bucket_confidence(conf),
        reason_codes=["from_account_balances"],
        inputs_used=["accounts.active"],
        detail={"account_count": len(active)},
    )


def _metric_income_expense(
    bundle: GoatDataBundle, req: dict[str, Any]
) -> tuple[Metric, Metric, Metric]:
    rows = bundle.transactions_in_range
    income_obs = _income_total(rows)
    expense = _expense_total(rows)
    income_declared = req.get("income")

    # Prefer declared income * months for savings-rate if user declared it.
    span = _span_days(bundle.range_start, bundle.range_end)
    months_in_range = max(1.0, span / 30.4375)

    if income_declared is not None:
        income_used = income_declared * months_in_range
        income_source = "declared"
        income_conf = 0.85
    else:
        income_used = income_obs
        income_source = "transactions_inferred"
        income_conf = 0.55 if income_obs > 0 else 0.1

    savings_rate = safe_div(income_used - expense, income_used)
    sr_conf = clamp((0.5 if income_source == "declared" else 0.35) + (0.3 if expense > 0 else 0))
    if savings_rate is None:
        sr_missing = [] if income_used > 0 else ["goat_user_inputs.monthly_income"]
    else:
        sr_missing = []

    return (
        Metric(
            key="income_total",
            value=round(income_used, 2),
            unit="INR",
            confidence=income_conf,
            confidence_bucket=bucket_confidence(income_conf),
            reason_codes=[f"source:{income_source}"],
            inputs_used=(
                ["goat_user_inputs.monthly_income"]
                if income_source == "declared"
                else ["transactions.in_range"]
            ),
            inputs_missing=(
                ["goat_user_inputs.monthly_income"] if income_source == "transactions_inferred" else []
            ),
            detail={"observed_income": round(income_obs, 2), "months_in_range": round(months_in_range, 2)},
        ),
        Metric(
            key="expense_total",
            value=round(expense, 2),
            unit="INR",
            confidence=0.8 if expense > 0 else 0.1,
            confidence_bucket=bucket_confidence(0.8 if expense > 0 else 0.1),
            reason_codes=[f"tx_count:{len(rows)}"],
            inputs_used=["transactions.in_range"],
        ),
        Metric(
            key="savings_rate",
            value=round(savings_rate, 4) if savings_rate is not None else None,
            unit="ratio",
            confidence=sr_conf if savings_rate is not None else 0.0,
            confidence_bucket=bucket_confidence(sr_conf if savings_rate is not None else 0.0),
            reason_codes=[f"income_source:{income_source}"],
            inputs_used=(
                ["goat_user_inputs.monthly_income", "transactions.in_range"]
                if income_source == "declared"
                else ["transactions.in_range"]
            ),
            inputs_missing=sr_missing,
        ),
    )


def _metric_trend_delta(bundle: GoatDataBundle) -> Metric:
    now_exp = _expense_total(bundle.transactions_in_range)
    prev_exp = _expense_total(bundle.transactions_prior_range)
    if prev_exp <= 0 and now_exp <= 0:
        return Metric(
            key="spend_trend_delta",
            value=None,
            unit="ratio",
            confidence=0.0,
            confidence_bucket="unknown",
            reason_codes=["no_prior_period_data"],
        )
    if prev_exp <= 0:
        return Metric(
            key="spend_trend_delta",
            value=None,
            unit="ratio",
            confidence=0.2,
            confidence_bucket=bucket_confidence(0.2),
            reason_codes=["no_prior_baseline"],
            detail={"current_expense": round(now_exp, 2)},
        )
    delta = (now_exp - prev_exp) / prev_exp
    conf = clamp(
        0.4
        + min(len(bundle.transactions_in_range), 30) / 100
        + min(len(bundle.transactions_prior_range), 30) / 100
    )
    return Metric(
        key="spend_trend_delta",
        value=round(delta, 4),
        unit="ratio",
        confidence=conf,
        confidence_bucket=bucket_confidence(conf),
        reason_codes=["from_paired_windows"],
        inputs_used=["transactions.in_range", "transactions.prior_range"],
    )


def _metric_emergency_runway(bundle: GoatDataBundle, req: dict[str, Any]) -> Metric:
    ef_target = req.get("ef_target")
    # Current liquid = sum of active savings/checking/cash accounts.
    liquid = 0.0
    liquid_count = 0
    for a in bundle.accounts:
        if not a.get("is_active", True):
            continue
        if (a.get("type") or "") in ("savings", "checking", "cash"):
            liquid += to_float(a.get("current_balance")) or 0.0
            liquid_count += 1

    monthly_expense = _expense_total(bundle.transactions_in_range)
    span = _span_days(bundle.range_start, bundle.range_end)
    monthly_expense_avg = monthly_expense / max(1.0, span / 30.4375)

    runway = safe_div(liquid, monthly_expense_avg)
    missing: list[str] = []
    if liquid_count == 0:
        missing.append("accounts.any")
    if ef_target is None:
        missing.append("goat_user_inputs.emergency_fund_target_months")

    conf = 0.0
    if liquid_count > 0 and monthly_expense_avg > 0:
        conf = 0.65 if ef_target is None else 0.85

    return Metric(
        key="emergency_fund_runway_months",
        value=round(runway, 2) if runway is not None else None,
        unit="months",
        confidence=conf,
        confidence_bucket=bucket_confidence(conf),
        reason_codes=[
            f"liquid_accounts:{liquid_count}",
            f"declared_target:{ef_target is not None}",
        ],
        inputs_used=["accounts.active", "transactions.in_range"]
        + (["goat_user_inputs.emergency_fund_target_months"] if ef_target is not None else []),
        inputs_missing=missing,
        detail={
            "liquid_total": round(liquid, 2),
            "monthly_expense_avg": round(monthly_expense_avg, 2),
            "target_months": ef_target,
            "gap_months": round(ef_target - runway, 2)
            if (ef_target is not None and runway is not None)
            else None,
        },
    )


def compute_overview(bundle: GoatDataBundle) -> ScopePayload:
    req = requirements_met(bundle, "overview")
    income, expense, savings = _metric_income_expense(bundle, req)
    metrics: list[Metric] = [
        _metric_net_worth(bundle),
        income,
        expense,
        savings,
        _metric_trend_delta(bundle),
        _metric_emergency_runway(bundle, req),
    ]
    return _finalize("overview", bundle, metrics)


# ─── Cashflow ────────────────────────────────────────────────────────────────


def _monthly_buckets(
    rows: list[dict[str, Any]],
) -> dict[str, dict[str, float]]:
    out: dict[str, dict[str, float]] = defaultdict(lambda: {"in": 0.0, "out": 0.0})
    for r in rows:
        d = r.get("date")
        if not d:
            continue
        key = str(d)[:7]
        amt = to_float(r.get("amount")) or 0.0
        t = r.get("type")
        if t in ("income", "settlement_in", "refund"):
            out[key]["in"] += amt
        elif t in ("expense", "settlement_out"):
            out[key]["out"] += amt
    return dict(out)


def compute_cashflow(bundle: GoatDataBundle) -> ScopePayload:
    req = requirements_met(bundle, "cashflow")
    rows = bundle.transactions_in_range
    buckets = _monthly_buckets(rows)
    span = _span_days(bundle.range_start, bundle.range_end)

    inflow = sum(b["in"] for b in buckets.values())
    outflow = sum(b["out"] for b in buckets.values())
    net = inflow - outflow
    daily_avg_spend = outflow / span

    # Simple stability: std of daily expense / mean (coefficient of variation).
    daily: dict[str, float] = defaultdict(float)
    for r in rows:
        if r.get("type") in ("expense", "settlement_out"):
            daily[str(r.get("date"))] += to_float(r.get("amount")) or 0.0
    if len(daily) >= 7:
        vals = list(daily.values())
        mean = sum(vals) / len(vals)
        var = sum((v - mean) ** 2 for v in vals) / len(vals)
        std = var**0.5
        cov = safe_div(std, mean)
        cov_conf = clamp(0.3 + len(vals) / 120)
    else:
        cov = None
        cov_conf = 0.0

    metrics: list[Metric] = [
        Metric(
            key="cashflow_inflow",
            value=round(inflow, 2),
            unit="INR",
            confidence=0.8 if inflow > 0 else 0.1,
            confidence_bucket=bucket_confidence(0.8 if inflow > 0 else 0.1),
            reason_codes=[f"months:{len(buckets)}"],
            inputs_used=["transactions.in_range"],
        ),
        Metric(
            key="cashflow_outflow",
            value=round(outflow, 2),
            unit="INR",
            confidence=0.8 if outflow > 0 else 0.1,
            confidence_bucket=bucket_confidence(0.8 if outflow > 0 else 0.1),
            reason_codes=[f"tx_count:{len(rows)}"],
            inputs_used=["transactions.in_range"],
        ),
        Metric(
            key="cashflow_net",
            value=round(net, 2),
            unit="INR",
            confidence=0.75 if (inflow > 0 and outflow > 0) else 0.2,
            confidence_bucket=bucket_confidence(0.75 if (inflow > 0 and outflow > 0) else 0.2),
            reason_codes=["inflow_minus_outflow"],
            inputs_used=["transactions.in_range"],
        ),
        Metric(
            key="daily_avg_spend",
            value=round(daily_avg_spend, 2),
            unit="INR/day",
            confidence=clamp(0.3 + len(rows) / 200),
            confidence_bucket=bucket_confidence(clamp(0.3 + len(rows) / 200)),
            reason_codes=[f"span_days:{span}"],
            inputs_used=["transactions.in_range"],
        ),
        Metric(
            key="spend_volatility_cv",
            value=round(cov, 4) if cov is not None else None,
            unit="ratio",
            confidence=cov_conf,
            confidence_bucket=bucket_confidence(cov_conf),
            reason_codes=[f"distinct_spend_days:{len(daily)}"],
            inputs_used=["transactions.in_range"],
            inputs_missing=[] if cov is not None else ["transactions.more_spend_days"],
        ),
    ]

    # EoM directional estimate — only if we actually have salary_day + accounts.
    if req.get("salary_day") and req.get("has_accounts"):
        eom_today = date.today()
        month_end = (eom_today.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(
            days=1
        )
        days_left = max(0, (month_end - eom_today).days)
        directional = daily_avg_spend * days_left
        metrics.append(
            Metric(
                key="end_of_month_spend_forecast_directional",
                value=round(directional, 2),
                unit="INR",
                confidence=0.5,
                confidence_bucket=bucket_confidence(0.5),
                reason_codes=["directional_only_no_model"],
                inputs_used=["transactions.in_range", "goat_user_inputs.salary_day"],
                detail={"days_left": days_left},
            )
        )
    else:
        metrics.append(
            Metric(
                key="end_of_month_spend_forecast_directional",
                value=None,
                unit="INR",
                confidence=0.0,
                confidence_bucket="unknown",
                reason_codes=["requires_salary_day_and_accounts"],
                inputs_missing=[
                    k
                    for k, v in [
                        ("goat_user_inputs.salary_day", req.get("salary_day")),
                        ("accounts.any", req.get("has_accounts")),
                    ]
                    if not v
                ],
            )
        )

    return _finalize("cashflow", bundle, metrics)


# ─── Budgets ─────────────────────────────────────────────────────────────────


def compute_budgets(bundle: GoatDataBundle) -> ScopePayload:
    req = requirements_met(bundle, "budgets")
    budgets = req["active_budgets"]
    if not budgets:
        return _finalize(
            "budgets",
            bundle,
            [
                Metric(
                    key="budgets_tracked",
                    value=0,
                    unit="count",
                    confidence=1.0,
                    confidence_bucket="high",
                    reason_codes=["no_active_budgets"],
                    inputs_missing=["budgets.any_active"],
                )
            ],
        )

    today = date.today()
    # Map budget_id → most recent period whose range includes today OR is most recent overall.
    latest_by_budget: dict[str, dict[str, Any]] = {}
    for p in bundle.budget_periods:
        bid = p.get("budget_id")
        if not bid:
            continue
        cur = latest_by_budget.get(bid)
        if cur is None or str(p.get("period_start")) > str(cur.get("period_start")):
            latest_by_budget[bid] = p

    metrics: list[Metric] = [
        Metric(
            key="budgets_tracked",
            value=len(budgets),
            unit="count",
            confidence=1.0,
            confidence_bucket="high",
            reason_codes=[],
            inputs_used=["budgets.active"],
        )
    ]
    overrun_flags = 0

    for b in budgets:
        bid = b["id"]
        limit = to_float(b.get("amount")) or 0.0
        period = latest_by_budget.get(bid)
        if not period or not limit:
            metrics.append(
                Metric(
                    key=f"budget_{bid}_utilization",
                    value=None,
                    unit="ratio",
                    confidence=0.0,
                    confidence_bucket="unknown",
                    reason_codes=["no_current_period"],
                    inputs_missing=["budget_periods.current"],
                )
            )
            continue
        spent = to_float(period.get("spent")) or 0.0
        p_start = date.fromisoformat(str(period["period_start"]))
        p_end = date.fromisoformat(str(period["period_end"]))
        total = max(1, (p_end - p_start).days + 1)
        elapsed = min(total, max(1, (today - p_start).days + 1))
        pct = safe_div(spent, limit) or 0.0
        pace = elapsed / total
        overrun_flag = pct > (pace + 0.15)
        overrun_flags += int(overrun_flag)
        metrics.append(
            Metric(
                key=f"budget_{bid}_utilization",
                value=round(pct, 4),
                unit="ratio",
                confidence=0.9 if spent > 0 else 0.4,
                confidence_bucket=bucket_confidence(0.9 if spent > 0 else 0.4),
                reason_codes=[f"overrun:{overrun_flag}", f"pace:{round(pace,2)}"],
                inputs_used=["budgets.active", "budget_periods"],
                detail={
                    "budget_name": b.get("name"),
                    "category_id": b.get("category_id"),
                    "spent": round(spent, 2),
                    "limit": round(limit, 2),
                    "pace_fraction": round(pace, 4),
                    "overrun": overrun_flag,
                },
            )
        )

    metrics.append(
        Metric(
            key="budgets_overrun_count",
            value=overrun_flags,
            unit="count",
            confidence=0.85,
            confidence_bucket="high",
            reason_codes=["pace_adjusted_threshold"],
            inputs_used=["budgets.active", "budget_periods"],
        )
    )
    return _finalize("budgets", bundle, metrics)


# ─── Recurring ───────────────────────────────────────────────────────────────


_MONTHLY_SCALE = {
    "daily": 30.4375,
    "weekly": 4.33,
    "biweekly": 2.17,
    "monthly": 1.0,
    "quarterly": 1 / 3,
    "yearly": 1 / 12,
}


def compute_recurring(bundle: GoatDataBundle) -> ScopePayload:
    req = requirements_met(bundle, "recurring")
    series = req["active_recurring"]
    if not series:
        return _finalize(
            "recurring",
            bundle,
            [
                Metric(
                    key="recurring_active_count",
                    value=0,
                    unit="count",
                    confidence=1.0,
                    confidence_bucket="high",
                    reason_codes=["no_active_recurring_series"],
                )
            ],
        )

    monthly_total = 0.0
    for s in series:
        amt = to_float(s.get("amount")) or 0.0
        scale = _MONTHLY_SCALE.get(s.get("cadence") or "monthly", 1.0)
        monthly_total += amt * scale

    today = date.today()
    horizon = today + timedelta(days=30)
    upcoming = [
        o
        for o in bundle.recurring_occurrences
        if o.get("status") == "upcoming"
        and o.get("due_date") is not None
        and today.isoformat() <= str(o["due_date"]) <= horizon.isoformat()
    ]
    upcoming_amount = sum(to_float(o.get("actual_amount")) or 0.0 for o in upcoming)

    metrics: list[Metric] = [
        Metric(
            key="recurring_active_count",
            value=len(series),
            unit="count",
            confidence=1.0,
            confidence_bucket="high",
            inputs_used=["recurring_series.active"],
        ),
        Metric(
            key="recurring_monthly_burden",
            value=round(monthly_total, 2),
            unit="INR",
            confidence=0.8,
            confidence_bucket="high",
            reason_codes=["cadence_normalized_to_monthly"],
            inputs_used=["recurring_series.active"],
        ),
        Metric(
            key="recurring_upcoming_30d_count",
            value=len(upcoming),
            unit="count",
            confidence=0.8 if bundle.recurring_occurrences else 0.4,
            confidence_bucket=bucket_confidence(
                0.8 if bundle.recurring_occurrences else 0.4
            ),
            reason_codes=["from_recurring_occurrences"],
            inputs_used=["recurring_occurrences"],
        ),
        Metric(
            key="recurring_upcoming_30d_amount",
            value=round(upcoming_amount, 2),
            unit="INR",
            confidence=0.7 if upcoming_amount > 0 else 0.4,
            confidence_bucket=bucket_confidence(0.7 if upcoming_amount > 0 else 0.4),
            inputs_used=["recurring_occurrences"],
        ),
    ]

    income = req.get("income")
    if income:
        pct = safe_div(monthly_total, income) or 0.0
        metrics.append(
            Metric(
                key="recurring_share_of_income",
                value=round(pct, 4),
                unit="ratio",
                confidence=0.85,
                confidence_bucket="high",
                inputs_used=[
                    "recurring_series.active",
                    "goat_user_inputs.monthly_income",
                ],
            )
        )
    else:
        metrics.append(
            Metric(
                key="recurring_share_of_income",
                value=None,
                unit="ratio",
                confidence=0.0,
                confidence_bucket="unknown",
                reason_codes=["requires_declared_income"],
                inputs_missing=["goat_user_inputs.monthly_income"],
            )
        )
    return _finalize("recurring", bundle, metrics)


# ─── Debt ────────────────────────────────────────────────────────────────────


def compute_debt(bundle: GoatDataBundle) -> ScopePayload:
    req = requirements_met(bundle, "debt")
    lent_total = sum(
        to_float(e.get("amount")) or 0.0
        for e in req["open_lend_borrow"]
        if e.get("type") == "lent"
    )
    borrowed_total = sum(
        to_float(e.get("amount")) or 0.0
        for e in req["open_lend_borrow"]
        if e.get("type") == "borrowed"
    )
    obligation_total = sum(
        to_float(o.get("current_outstanding")) or 0.0
        for o in req["active_obligations"]
    )
    monthly_due = sum(
        to_float(o.get("monthly_due")) or 0.0 for o in req["active_obligations"]
    )

    income = req.get("income")
    dti = safe_div(monthly_due, income) if income else None

    metrics: list[Metric] = [
        Metric(
            key="lend_open_total",
            value=round(lent_total, 2),
            unit="INR",
            confidence=0.9,
            confidence_bucket="high",
            inputs_used=["lend_borrow_entries"],
        ),
        Metric(
            key="borrow_open_total",
            value=round(borrowed_total, 2),
            unit="INR",
            confidence=0.9,
            confidence_bucket="high",
            inputs_used=["lend_borrow_entries"],
        ),
        Metric(
            key="obligation_outstanding_total",
            value=round(obligation_total, 2),
            unit="INR",
            confidence=0.9 if req["active_obligations"] else 0.3,
            confidence_bucket=bucket_confidence(
                0.9 if req["active_obligations"] else 0.3
            ),
            inputs_used=["goat_obligations"] if req["active_obligations"] else [],
            inputs_missing=[] if req["active_obligations"] else ["goat_obligations.any_active"],
        ),
        Metric(
            key="obligation_monthly_due_total",
            value=round(monthly_due, 2),
            unit="INR",
            confidence=0.85 if monthly_due > 0 else 0.3,
            confidence_bucket=bucket_confidence(0.85 if monthly_due > 0 else 0.3),
            inputs_used=["goat_obligations"] if req["active_obligations"] else [],
        ),
        Metric(
            key="debt_to_income_ratio",
            value=round(dti, 4) if dti is not None else None,
            unit="ratio",
            confidence=0.85 if dti is not None else 0.0,
            confidence_bucket=bucket_confidence(0.85 if dti is not None else 0.0),
            inputs_used=(
                ["goat_obligations", "goat_user_inputs.monthly_income"] if dti is not None else []
            ),
            inputs_missing=([] if dti is not None else ["goat_user_inputs.monthly_income"]),
        ),
    ]
    return _finalize("debt", bundle, metrics)


# ─── Goals ───────────────────────────────────────────────────────────────────


def compute_goals(bundle: GoatDataBundle) -> ScopePayload:
    req = requirements_met(bundle, "goals")
    active = req["active_goals"]
    if not active:
        return _finalize(
            "goals",
            bundle,
            [
                Metric(
                    key="goals_active_count",
                    value=0,
                    unit="count",
                    confidence=1.0,
                    confidence_bucket="high",
                    reason_codes=["no_active_goals"],
                    inputs_missing=["goat_goals.any_active"],
                )
            ],
        )

    today = date.today()
    metrics: list[Metric] = [
        Metric(
            key="goals_active_count",
            value=len(active),
            unit="count",
            confidence=1.0,
            confidence_bucket="high",
            inputs_used=["goat_goals"],
        )
    ]
    for g in active:
        gid = g["id"]
        target = to_float(g.get("target_amount")) or 0.0
        current = to_float(g.get("current_amount")) or 0.0
        gap = max(0.0, target - current)
        target_date = g.get("target_date")
        months_remaining = None
        required_monthly = None
        reason_codes: list[str] = []
        if target_date:
            try:
                td = date.fromisoformat(str(target_date))
                months_remaining = max(0.0, (td - today).days / 30.4375)
                required_monthly = safe_div(gap, months_remaining) if months_remaining else None
                if months_remaining == 0:
                    reason_codes.append("target_date_passed")
            except ValueError:
                reason_codes.append("invalid_target_date")
        else:
            reason_codes.append("no_target_date")
        metrics.append(
            Metric(
                key=f"goal_{gid}_gap",
                value=round(gap, 2),
                unit="INR",
                confidence=0.95,
                confidence_bucket="high",
                reason_codes=reason_codes,
                inputs_used=["goat_goals"],
                detail={
                    "title": g.get("title"),
                    "target_amount": round(target, 2),
                    "current_amount": round(current, 2),
                    "months_remaining": round(months_remaining, 2)
                    if months_remaining is not None
                    else None,
                    "required_monthly": round(required_monthly, 2)
                    if required_monthly is not None
                    else None,
                },
            )
        )
    return _finalize("goals", bundle, metrics)


# ─── Full (aggregate) ────────────────────────────────────────────────────────


def compute_full(bundle: GoatDataBundle) -> ScopePayload:
    parts = [
        compute_overview(bundle),
        compute_cashflow(bundle),
        compute_budgets(bundle),
        compute_recurring(bundle),
        compute_debt(bundle),
        compute_goals(bundle),
    ]
    metrics: list[Metric] = []
    for p in parts:
        metrics.extend(p.metrics)
    return _finalize("full", bundle, metrics)


# ─── Dispatch + finalization ─────────────────────────────────────────────────


SCOPE_DISPATCH: dict[Scope, Any] = {
    "overview": compute_overview,
    "cashflow": compute_cashflow,
    "budgets": compute_budgets,
    "recurring": compute_recurring,
    "debt": compute_debt,
    "goals": compute_goals,
    "full": compute_full,
}


def _aggregate_status(metrics: list[Metric]) -> SnapshotStatus:
    if not metrics:
        return "partial"
    valued = [m for m in metrics if m.value is not None]
    if not valued:
        return "partial"
    # Partial if any metric is missing required inputs it explicitly names.
    if any(m.inputs_missing for m in valued):
        return "partial"
    return "completed"


def _aggregate_confidence(metrics: list[Metric]) -> ConfidenceBucket:
    scored = [m.confidence for m in metrics if m.confidence is not None]
    if not scored:
        return "unknown"
    avg = sum(scored) / len(scored)
    return bucket_confidence(avg)


def _finalize(scope: Scope, bundle: GoatDataBundle, metrics: list[Metric]) -> ScopePayload:
    from .missing_inputs import classify_readiness

    readiness: ReadinessLevel = classify_readiness(bundle)
    return ScopePayload(
        scope=scope,
        status=_aggregate_status(metrics),
        readiness_level=readiness,
        confidence=_aggregate_confidence(metrics),
        metrics=metrics,
        narrative={},
    )


def compute_scope(bundle: GoatDataBundle, scope: Scope) -> ScopePayload:
    return SCOPE_DISPATCH[scope](bundle)
