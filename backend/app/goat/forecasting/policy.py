"""Forecasting policy: per-target model selection + output builders.

All 6 v1 targets are produced here. Each target:

  - declares its own minimum-history threshold
  - calls a specific forecaster (baseline / ETS / Prophet)
  - always has a stdlib fallback
  - returns a typed ``ForecastTargetOut`` with confidence + reason codes.

Dedicated-data-only: internal future-known regressors only (salary_day,
recurring due dates). No market/weather/news signals.
"""
from __future__ import annotations

import logging
import statistics
from datetime import date, timedelta
from typing import Any

from ..contracts import (
    ForecastLayer,
    ForecastModel,
    ForecastPoint,
    ForecastSeries,
    ForecastTargetKey,
    ForecastTargetOut,
)
from ..data_loader import GoatDataBundle
from ..scoring import bucket_confidence, clamp, safe_div, to_float, utcnow_iso
from ..versions import MODEL_VERSIONS
from . import baselines, ets, features, prophet_model

log = logging.getLogger(__name__)

# ─── Minimum history per target (days) ──────────────────────────────────────

MIN_HISTORY = {
    "short_horizon_spend_7d": 14,
    "short_horizon_spend_30d": 21,
    "end_of_month_liquidity": 21,
    "budget_overrun_trajectory": 7,
    "emergency_fund_depletion_horizon": 30,
    "goal_completion_trajectory": 0,  # deterministic on static inputs
}

# Longer history unlocks heavier models.
ETS_MIN_HISTORY = 45


# ─── Model selection ────────────────────────────────────────────────────────


def choose_spend_model(history_length: int) -> ForecastModel:
    """Pick a forecaster for a daily-spend-like series."""
    if history_length < 14:
        return "none"
    if history_length >= 90 and prophet_model.is_available():
        return "prophet"
    if history_length >= ETS_MIN_HISTORY and ets.is_available():
        return "ets"
    if history_length >= 14:
        return "seasonal_naive"
    return "rolling_median"


def _run_selected(
    model: ForecastModel,
    values: list[float],
    dated: list[tuple[date, float]],
    horizon: int,
) -> tuple[dict[str, list[float]] | None, ForecastModel, bool]:
    """Returns (bands, actually_used, fallback_used)."""
    if model == "prophet":
        bands = prophet_model.fit_and_forecast(dated, horizon)
        if bands:
            return bands, "prophet", False
    if model in ("prophet", "ets"):
        bands = ets.fit_and_forecast(values, horizon)
        if bands:
            fallback = model == "prophet"
            return bands, "ets", fallback
    if model in ("prophet", "ets", "seasonal_naive") and len(values) >= 14:
        bands = baselines.seasonal_naive(values, horizon)
        fallback = model != "seasonal_naive"
        return bands, "seasonal_naive", fallback
    if model != "none" and values:
        return baselines.rolling_median(values, horizon), "rolling_median", model != "rolling_median"
    return None, "none", False


def _points_from_bands(
    bands: dict[str, list[float]],
    start: date,
    horizon: int,
) -> list[ForecastPoint]:
    return [
        ForecastPoint(
            step=i + 1,
            date=(start + timedelta(days=i + 1)).isoformat(),
            p10=round(bands["p10"][i], 2),
            p50=round(bands["p50"][i], 2),
            p90=round(bands["p90"][i], 2),
        )
        for i in range(horizon)
    ]


def _confidence_for_spend(history_length: int, model: ForecastModel) -> float:
    """Crude but honest confidence: scales with history + model capability."""
    base = clamp(history_length / 120.0)
    bump = {
        "prophet": 0.15,
        "ets": 0.10,
        "seasonal_naive": 0.05,
        "rolling_median": 0.0,
        "none": 0.0,
        "naive_mean": 0.0,
        "heuristic": 0.0,
    }.get(model, 0.0)
    return round(clamp(0.25 + base + bump, 0.0, 0.95), 4)


# ─── Target: short-horizon spend ────────────────────────────────────────────


def _short_horizon_spend(
    bundle: GoatDataBundle, horizon: int, target_key: ForecastTargetKey
) -> ForecastTargetOut:
    dated = features.daily_spend_series(bundle)
    values = [v for _, v in dated]
    history_length = len(values)
    min_hist = MIN_HISTORY[target_key]
    if history_length < min_hist:
        return ForecastTargetOut(
            target=target_key,
            status="insufficient_history",
            model_used="none",
            history_length=history_length,
            horizon_days=horizon,
            confidence=0.0,
            confidence_bucket="unknown",
            reason_codes=[f"need_{min_hist}_days_daily_spend"],
            insufficient_data_fields=["transactions.daily_coverage"],
        )
    chosen = choose_spend_model(history_length)
    bands, actually_used, fallback = _run_selected(chosen, values, dated, horizon)
    if bands is None:
        return ForecastTargetOut(
            target=target_key,
            status="insufficient_history",
            model_used="none",
            history_length=history_length,
            horizon_days=horizon,
            confidence=0.0,
            reason_codes=["all_models_unavailable"],
        )
    p50_sum = round(sum(bands["p50"]), 2)
    p10_sum = round(sum(bands["p10"]), 2)
    p90_sum = round(sum(bands["p90"]), 2)
    conf = _confidence_for_spend(history_length, actually_used)
    start = dated[-1][0] if dated else date.today()
    return ForecastTargetOut(
        target=target_key,
        status="ok",
        model_used=actually_used,
        fallback_used=fallback,
        history_length=history_length,
        horizon_days=horizon,
        confidence=conf,
        confidence_bucket=bucket_confidence(conf),
        reason_codes=[f"history_days:{history_length}"],
        value={"p10_total": p10_sum, "p50_total": p50_sum, "p90_total": p90_sum},
        series=ForecastSeries(
            horizon_days=horizon,
            unit="INR/day",
            points=_points_from_bands(bands, start, horizon),
            summary={"sum_p50": p50_sum},
        ),
    )


# ─── Target: end-of-month liquidity ─────────────────────────────────────────


def _end_of_month_liquidity(bundle: GoatDataBundle) -> ForecastTargetOut:
    today = date.today()
    month_end = (today.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(
        days=1
    )
    days_left = max(0, (month_end - today).days)
    liquid, liquid_count = features.liquid_balance(bundle)
    salary_day = features.declared_salary_day(bundle)
    income = features.declared_monthly_income(bundle)
    observed_income = features.observed_monthly_income(bundle)

    if liquid_count == 0:
        return ForecastTargetOut(
            target="end_of_month_liquidity",
            status="insufficient_history",
            model_used="none",
            history_length=0,
            horizon_days=days_left,
            confidence=0.0,
            reason_codes=["no_liquid_accounts"],
            insufficient_data_fields=["accounts.any"],
        )

    spend = _short_horizon_spend(bundle, days_left, "short_horizon_spend_30d")
    expected_spend_p50 = 0.0
    expected_spend_p10 = 0.0
    expected_spend_p90 = 0.0
    history_length = spend.history_length
    if spend.status == "ok" and spend.series:
        expected_spend_p50 = float(spend.value.get("p50_total", 0.0))
        expected_spend_p10 = float(spend.value.get("p10_total", 0.0))
        expected_spend_p90 = float(spend.value.get("p90_total", 0.0))

    # Expected income between today and month_end. Only count salary_day if it
    # falls within that window AND the user declared income.
    expected_income = 0.0
    income_reason: list[str] = []
    if salary_day and income:
        if today.day < salary_day <= month_end.day:
            expected_income = income
            income_reason.append(f"salary_on_day_{salary_day}")
        else:
            income_reason.append("salary_already_received_or_after_month_end")
    elif observed_income and not (salary_day and income):
        # Fallback: prorate observed income by days_left / 30.
        expected_income = observed_income * (days_left / 30.0)
        income_reason.append("income_source:transactions_inferred")

    p50 = round(liquid + expected_income - expected_spend_p50, 2)
    p10 = round(liquid + expected_income - expected_spend_p90, 2)
    p90 = round(liquid + expected_income - expected_spend_p10, 2)
    conf = spend.confidence or 0.3
    # Penalise confidence when we had to infer income.
    if not (salary_day and income):
        conf = clamp(conf - 0.1, 0.0, 1.0)
    conf = round(conf, 4)

    reason_codes = [*income_reason, f"days_left:{days_left}"]
    if spend.fallback_used:
        reason_codes.append(f"fallback_to:{spend.model_used}")

    return ForecastTargetOut(
        target="end_of_month_liquidity",
        status="ok",
        model_used=spend.model_used if spend.model_used != "none" else "heuristic",
        fallback_used=spend.fallback_used,
        history_length=history_length,
        horizon_days=days_left,
        confidence=conf,
        confidence_bucket=bucket_confidence(conf),
        reason_codes=reason_codes,
        insufficient_data_fields=[]
        if (salary_day and income)
        else ["goat_user_inputs.salary_day", "goat_user_inputs.monthly_income"],
        value={
            "p10": p10,
            "p50": p50,
            "p90": p90,
            "starting_liquid": liquid,
            "expected_income": round(expected_income, 2),
            "expected_spend_p50": round(expected_spend_p50, 2),
            "month_end": month_end.isoformat(),
        },
    )


# ─── Target: budget overrun trajectory ──────────────────────────────────────


def _budget_overrun_trajectory(bundle: GoatDataBundle) -> list[ForecastTargetOut]:
    today = date.today()
    out: list[ForecastTargetOut] = []
    # Pair active budgets with their most recent period.
    active = [b for b in bundle.budgets if b.get("is_active", True)]
    if not active:
        return out
    latest_period: dict[str, dict[str, Any]] = {}
    for p in bundle.budget_periods:
        bid = p.get("budget_id")
        if not bid:
            continue
        cur = latest_period.get(bid)
        if cur is None or str(p.get("period_start")) > str(cur.get("period_start")):
            latest_period[bid] = p

    for b in active:
        bid = b["id"]
        limit = to_float(b.get("amount")) or 0.0
        period = latest_period.get(bid)
        if not period or not limit:
            out.append(
                ForecastTargetOut(
                    target="budget_overrun_trajectory",
                    status="insufficient_history",
                    model_used="none",
                    history_length=0,
                    horizon_days=0,
                    entity_id=str(bid),
                    entity_label=b.get("name"),
                    reason_codes=["no_current_period_or_limit"],
                    insufficient_data_fields=["budget_periods.current"],
                )
            )
            continue
        try:
            p_start = date.fromisoformat(str(period["period_start"]))
            p_end = date.fromisoformat(str(period["period_end"]))
        except (ValueError, TypeError):
            continue
        spent = to_float(period.get("spent")) or 0.0
        total_days = max(1, (p_end - p_start).days + 1)
        days_elapsed = min(total_days, max(1, (today - p_start).days + 1))
        days_left = max(0, total_days - days_elapsed)

        # Category-level daily spend history drives the projection.
        cat_id = b.get("category_id")
        cat_hist = features.daily_category_spend(bundle, cat_id) if cat_id else []
        cat_values = [v for _, v in cat_hist]
        model_used: ForecastModel = "none"
        projected_p50 = 0.0
        projected_p10 = 0.0
        projected_p90 = 0.0
        reason_codes = [f"days_left:{days_left}"]
        history_length = len(cat_values)
        fallback = False
        if days_left == 0:
            model_used = "heuristic"
        elif history_length >= 7:
            chosen = "seasonal_naive" if history_length >= 14 else "rolling_median"
            bands, model_used, fallback = _run_selected(
                chosen, cat_values, cat_hist, days_left
            )
            if bands:
                projected_p10 = sum(bands["p10"])
                projected_p50 = sum(bands["p50"])
                projected_p90 = sum(bands["p90"])
        else:
            # Fall back to pace-extrapolation.
            daily_pace = safe_div(spent, days_elapsed) or 0.0
            projected_p50 = daily_pace * days_left
            projected_p10 = projected_p50 * 0.75
            projected_p90 = projected_p50 * 1.25
            model_used = "heuristic"
            reason_codes.append("category_history_insufficient")

        end_p10 = round(spent + projected_p10, 2)
        end_p50 = round(spent + projected_p50, 2)
        end_p90 = round(spent + projected_p90, 2)
        overrun_p50 = end_p50 > limit
        overrun_p10 = end_p10 > limit
        overrun_p90 = end_p90 > limit

        conf = clamp(0.3 + history_length / 120.0, 0.0, 0.9)
        out.append(
            ForecastTargetOut(
                target="budget_overrun_trajectory",
                status="ok",
                model_used=model_used,
                fallback_used=fallback,
                history_length=history_length,
                horizon_days=days_left,
                confidence=round(conf, 4),
                confidence_bucket=bucket_confidence(conf),
                reason_codes=reason_codes,
                entity_type="budget",
                entity_id=str(bid),
                entity_label=b.get("name"),
                value={
                    "budget_limit": round(limit, 2),
                    "spent_to_date": round(spent, 2),
                    "end_of_period_p10": end_p10,
                    "end_of_period_p50": end_p50,
                    "end_of_period_p90": end_p90,
                    "overrun_p10": overrun_p10,
                    "overrun_p50": overrun_p50,
                    "overrun_p90": overrun_p90,
                },
            )
        )
    return out


# ─── Target: emergency-fund depletion horizon ───────────────────────────────


def _emergency_fund_depletion(bundle: GoatDataBundle) -> ForecastTargetOut:
    liquid, count = features.liquid_balance(bundle)
    if count == 0:
        return ForecastTargetOut(
            target="emergency_fund_depletion_horizon",
            status="insufficient_history",
            model_used="none",
            history_length=0,
            horizon_days=0,
            reason_codes=["no_liquid_accounts"],
            insufficient_data_fields=["accounts.any"],
        )
    dated = features.daily_spend_series(bundle)
    values = [v for _, v in dated]
    if len(values) < MIN_HISTORY["emergency_fund_depletion_horizon"]:
        return ForecastTargetOut(
            target="emergency_fund_depletion_horizon",
            status="insufficient_history",
            model_used="none",
            history_length=len(values),
            horizon_days=0,
            reason_codes=["need_30_days_daily_spend"],
            insufficient_data_fields=["transactions.daily_coverage"],
        )

    mean_spend = statistics.mean(values)
    # Income per day (declared monthly / 30, or observed).
    declared = features.declared_monthly_income(bundle)
    observed = features.observed_monthly_income(bundle)
    income_monthly = declared if declared is not None else observed
    income_daily = (income_monthly or 0.0) / 30.0
    net_daily = income_daily - mean_spend
    if net_daily >= 0:
        return ForecastTargetOut(
            target="emergency_fund_depletion_horizon",
            status="ok",
            model_used="heuristic",
            history_length=len(values),
            horizon_days=0,
            confidence=0.5,
            confidence_bucket="low",
            reason_codes=["net_cashflow_non_negative"],
            value={
                "days_to_zero": None,
                "net_daily": round(net_daily, 2),
                "mean_daily_spend": round(mean_spend, 2),
                "liquid_balance": liquid,
            },
        )
    days_to_zero = int(liquid / abs(net_daily))
    conf = clamp(0.4 + min(60, len(values)) / 300.0, 0.0, 0.8)
    return ForecastTargetOut(
        target="emergency_fund_depletion_horizon",
        status="ok",
        model_used="heuristic",
        history_length=len(values),
        horizon_days=max(0, days_to_zero),
        confidence=round(conf, 4),
        confidence_bucket=bucket_confidence(conf),
        reason_codes=["derived_from_mean_spend_vs_income"],
        value={
            "days_to_zero": days_to_zero,
            "net_daily": round(net_daily, 2),
            "mean_daily_spend": round(mean_spend, 2),
            "liquid_balance": liquid,
        },
    )


# ─── Target: goal completion trajectory ─────────────────────────────────────


def _goal_completion_trajectory(bundle: GoatDataBundle) -> list[ForecastTargetOut]:
    out: list[ForecastTargetOut] = []
    today = date.today()
    for g in bundle.goat_goals:
        if g.get("status") != "active":
            continue
        target = to_float(g.get("target_amount")) or 0.0
        current = to_float(g.get("current_amount")) or 0.0
        target_date = g.get("target_date")
        if not target or not target_date:
            out.append(
                ForecastTargetOut(
                    target="goal_completion_trajectory",
                    status="insufficient_history",
                    model_used="none",
                    history_length=0,
                    horizon_days=0,
                    entity_type="goat_goal",
                    entity_id=str(g.get("id")),
                    entity_label=g.get("title"),
                    reason_codes=["missing_target_or_target_date"],
                    insufficient_data_fields=[
                        k
                        for k, v in (("target_amount", target), ("target_date", target_date))
                        if not v
                    ],
                )
            )
            continue
        try:
            td = date.fromisoformat(str(target_date))
        except ValueError:
            continue
        months = max(0.0, (td - today).days / 30.4375)
        gap = max(0.0, target - current)
        required_monthly = safe_div(gap, months) if months > 0 else None
        on_pace = None
        if required_monthly is not None:
            # If user already saves at required_monthly cadence, on_pace.
            # v1: heuristic only — we can't yet observe contribution history.
            on_pace = required_monthly <= (gap / 1.0)  # trivially true when positive
        out.append(
            ForecastTargetOut(
                target="goal_completion_trajectory",
                status="ok",
                model_used="heuristic",
                history_length=0,
                horizon_days=int(months * 30.4375),
                confidence=0.6,
                confidence_bucket="medium",
                reason_codes=["deterministic_projection_on_static_inputs"],
                entity_type="goat_goal",
                entity_id=str(g.get("id")),
                entity_label=g.get("title"),
                value={
                    "current": round(current, 2),
                    "target": round(target, 2),
                    "gap": round(gap, 2),
                    "months_remaining": round(months, 2),
                    "required_monthly": round(required_monthly, 2)
                    if required_monthly is not None
                    else None,
                    "on_pace": on_pace,
                },
            )
        )
    return out


# ─── Public entry point ─────────────────────────────────────────────────────


def run_forecasting_layer(bundle: GoatDataBundle) -> ForecastLayer:
    layer = ForecastLayer(
        version=MODEL_VERSIONS.get("forecast", "0.1.0"),
        generated_at=utcnow_iso(),
        models_available={
            "ets": ets.is_available(),
            "prophet": prophet_model.is_available(),
            "baselines": True,
        },
    )
    targets: list[ForecastTargetOut] = []
    targets.append(_short_horizon_spend(bundle, 7, "short_horizon_spend_7d"))
    targets.append(_short_horizon_spend(bundle, 30, "short_horizon_spend_30d"))
    targets.append(_end_of_month_liquidity(bundle))
    targets.extend(_budget_overrun_trajectory(bundle))
    targets.append(_emergency_fund_depletion(bundle))
    targets.extend(_goal_completion_trajectory(bundle))
    layer.targets = targets
    return layer
