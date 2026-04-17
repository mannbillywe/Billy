"""Prophet wrapper — optional, heavily guarded.

Prophet's Windows install story is historically painful (pystan/cmdstanpy),
so v1 keeps it strictly optional. Enabled only when:

  - Prophet + pandas import successfully, and
  - env var ``GOAT_USE_PROPHET=1`` is set, and
  - the history is long enough (90+ days).

Everything else falls back to ETS or the stdlib baselines.
"""
from __future__ import annotations

import logging
import os
from datetime import date
from typing import Sequence

log = logging.getLogger(__name__)


def is_available() -> bool:
    if os.getenv("GOAT_USE_PROPHET") != "1":
        return False
    try:
        import pandas  # noqa: F401
        from prophet import Prophet  # noqa: F401

        return True
    except ImportError:
        return False


def fit_and_forecast(
    history: Sequence[tuple[date, float]], horizon: int
) -> dict[str, list[float]] | None:
    if not is_available():
        return None
    if len(history) < 90:
        return None
    try:
        import pandas as pd
        from prophet import Prophet

        df = pd.DataFrame(
            [{"ds": d.isoformat(), "y": float(y)} for d, y in history]
        )
        m = Prophet(
            weekly_seasonality=True,
            yearly_seasonality=False,
            daily_seasonality=False,
            interval_width=0.8,
        )
        m.fit(df)
        future = m.make_future_dataframe(periods=horizon)
        fc = m.predict(future).tail(horizon)
        return {
            "p10": [max(0.0, float(v)) for v in fc["yhat_lower"]],
            "p50": [max(0.0, float(v)) for v in fc["yhat"]],
            "p90": [max(0.0, float(v)) for v in fc["yhat_upper"]],
        }
    except Exception as exc:  # noqa: BLE001
        log.info("Prophet fit/forecast failed: %s", exc)
        return None
