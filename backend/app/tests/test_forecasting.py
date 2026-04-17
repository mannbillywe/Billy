"""Tests for the forecasting layer.

Exercises:
- model-selection policy (enough data chooses baseline; none chooses "none")
- insufficient-history fallback behaviour
- forecast JSON shape
- short-horizon, EoM liquidity, budget trajectory, EF depletion targets
- stdlib baselines (numpy/statsmodels-free)
"""
from __future__ import annotations

from datetime import date, timedelta

import pytest

from goat.data_loader import GoatDataBundle
from goat.forecasting import run_forecasting_layer
from goat.forecasting.baselines import naive_mean, rolling_median, seasonal_naive
from goat.forecasting.policy import choose_spend_model


# ─── Helpers ─────────────────────────────────────────────────────────────────


def _tx(d: date, amt: float, t: str = "expense", cat: str | None = None):
    return {
        "id": f"tx-{d.isoformat()}-{amt}-{t}",
        "amount": amt,
        "date": d.isoformat(),
        "type": t,
        "category_id": cat,
        "status": "confirmed",
        "updated_at": f"{d.isoformat()}T00:00:00+00:00",
    }


def _long_spend_bundle(days: int = 120) -> GoatDataBundle:
    end = date(2026, 4, 1)
    start = end - timedelta(days=days - 1)
    tx_in: list = []
    tx_prior: list = []
    for i in range(days):
        d = start + timedelta(days=i)
        tx_in.append(_tx(d, 200 + (i % 7) * 30, "expense", cat="food"))
    # Prior window — a bit different spend level
    for i in range(60):
        d = start - timedelta(days=60 - i)
        tx_prior.append(_tx(d, 180, "expense", cat="food"))
    return GoatDataBundle(
        user_id="u1",
        scope="full",
        range_start=start,
        range_end=end,
        accounts=[
            {
                "id": "a1",
                "type": "savings",
                "current_balance": 50000,
                "is_asset": True,
                "is_active": True,
            }
        ],
        transactions_in_range=tx_in,
        transactions_prior_range=tx_prior,
    )


# ─── Baselines ──────────────────────────────────────────────────────────────


def test_rolling_median_emits_non_negative_bands():
    hist = [10, 12, 11, 15, 9, 10, 8, 12, 10]
    out = rolling_median(hist, horizon=3)
    assert len(out["p50"]) == 3
    assert all(v >= 0 for v in out["p10"])
    assert all(p10 <= p50 <= p90 for p10, p50, p90 in zip(out["p10"], out["p50"], out["p90"]))


def test_seasonal_naive_falls_back_on_short_history():
    # Fewer than period+1 points → rolling_median fallback.
    hist = [5, 6, 7]
    out = seasonal_naive(hist, horizon=7, period=7)
    assert len(out["p50"]) == 7


def test_naive_mean_empty_history():
    out = naive_mean([], horizon=5)
    assert out["p50"] == [0.0] * 5


def test_choose_spend_model_insufficient():
    assert choose_spend_model(0) == "none"
    assert choose_spend_model(10) == "none"


def test_choose_spend_model_medium():
    # 20 days of history → seasonal_naive (ETS needs 45+).
    assert choose_spend_model(20) == "seasonal_naive"


# ─── Layer-level shape ──────────────────────────────────────────────────────


def test_layer_shape_on_rich_bundle():
    b = _long_spend_bundle()
    layer = run_forecasting_layer(b)
    assert layer.version
    assert layer.generated_at
    targets = {t.target for t in layer.targets}
    assert "short_horizon_spend_7d" in targets
    assert "short_horizon_spend_30d" in targets
    assert "end_of_month_liquidity" in targets
    assert "emergency_fund_depletion_horizon" in targets
    s7 = next(t for t in layer.targets if t.target == "short_horizon_spend_7d")
    assert s7.status == "ok"
    assert s7.series and s7.series.horizon_days == 7
    assert s7.value["p50_total"] > 0


def test_insufficient_history_surfaces_cleanly():
    end = date(2026, 4, 1)
    b = GoatDataBundle(
        user_id="u2",
        scope="overview",
        range_start=end - timedelta(days=60),
        range_end=end,
        transactions_in_range=[_tx(end - timedelta(days=2), 100)],
    )
    layer = run_forecasting_layer(b)
    s7 = next(t for t in layer.targets if t.target == "short_horizon_spend_7d")
    assert s7.status == "insufficient_history"
    assert s7.model_used == "none"
    assert "transactions.daily_coverage" in s7.insufficient_data_fields


def test_budget_trajectory_uses_category_spend():
    b = _long_spend_bundle(days=45)
    b.budgets = [
        {
            "id": "bud-food",
            "name": "Food",
            "amount": 6000,
            "is_active": True,
            "category_id": "food",
        }
    ]
    today = date.today()
    period_start = today.replace(day=1)
    period_end = (period_start + timedelta(days=32)).replace(day=1) - timedelta(days=1)
    b.budget_periods = [
        {
            "id": "bp",
            "budget_id": "bud-food",
            "period_start": period_start.isoformat(),
            "period_end": period_end.isoformat(),
            "spent": 3200,
        }
    ]
    layer = run_forecasting_layer(b)
    trajectories = [t for t in layer.targets if t.target == "budget_overrun_trajectory"]
    assert len(trajectories) == 1
    assert trajectories[0].entity_id == "bud-food"
    assert "end_of_period_p50" in trajectories[0].value


def test_layer_models_available_flags():
    b = _long_spend_bundle(days=30)
    layer = run_forecasting_layer(b)
    # baselines is always available; ets/prophet depend on optional installs.
    assert layer.models_available["baselines"] is True
    assert isinstance(layer.models_available["ets"], bool)
    assert isinstance(layer.models_available["prophet"], bool)
