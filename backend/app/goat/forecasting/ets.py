"""ExponentialSmoothing / Holt-Winters via statsmodels.

Strictly guarded — if statsmodels/numpy aren't installed, this module returns
``None`` and the policy falls back to a stdlib baseline. That means Goat Mode
boots correctly on a minimal install.
"""
from __future__ import annotations

import logging
from typing import Sequence

log = logging.getLogger(__name__)


def is_available() -> bool:
    try:
        import numpy  # noqa: F401
        from statsmodels.tsa.holtwinters import ExponentialSmoothing  # noqa: F401

        return True
    except ImportError:
        return False


def fit_and_forecast(
    history: Sequence[float],
    horizon: int,
    seasonal_period: int = 7,
) -> dict[str, list[float]] | None:
    if not is_available():
        return None
    try:
        import numpy as np
        from statsmodels.tsa.holtwinters import ExponentialSmoothing

        y = np.asarray(history, dtype=float)
        if len(y) < max(2 * seasonal_period, 14):
            return None
        use_seasonal = len(y) >= 2 * seasonal_period
        fit = ExponentialSmoothing(
            y,
            trend="add",
            seasonal="add" if use_seasonal else None,
            seasonal_periods=seasonal_period if use_seasonal else None,
            initialization_method="estimated",
        ).fit(disp=False)
        f = np.asarray(fit.forecast(horizon), dtype=float)
        resid = y - np.asarray(fit.fittedvalues, dtype=float)
        sd = float(np.std(resid, ddof=1)) if len(resid) > 1 else 0.0
        p50 = [float(v) for v in f]
        return {
            "p10": [max(0.0, v - 1.2816 * sd) for v in p50],
            "p50": [max(0.0, v) for v in p50],
            "p90": [max(0.0, v + 1.2816 * sd) for v in p50],
        }
    except Exception as exc:  # noqa: BLE001
        log.info("ETS fit/forecast failed, returning None: %s", exc)
        return None
