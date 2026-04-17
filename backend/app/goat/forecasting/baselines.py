"""Stdlib-only baseline forecasters.

Volumes here (≤ ~365 daily points) are tiny, so pure-Python quantile math is
plenty fast and keeps the backend import graph lean. Every baseline returns a
``{"p10": [...], "p50": [...], "p90": [...]}`` dict so downstream policy
code can handle every model uniformly.
"""
from __future__ import annotations

import math
import statistics
from typing import Sequence


ForecastBands = dict[str, list[float]]


def _percentile(values: Sequence[float], pct: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    if len(s) == 1:
        return float(s[0])
    k = (len(s) - 1) * pct
    lo = math.floor(k)
    hi = math.ceil(k)
    if lo == hi:
        return float(s[lo])
    return float(s[lo]) * (hi - k) + float(s[hi]) * (k - lo)


def _pos(x: float) -> float:
    return max(0.0, x)


def rolling_median(
    history: Sequence[float], horizon: int, window: int = 14
) -> ForecastBands:
    """Forecast = rolling median of trailing ``window``.

    Bands are built from the 10/90 percentiles of the trailing residuals
    (daily value minus median). For daily-spend we clamp p10 at zero so we
    don't emit negative spend.
    """
    window = max(1, window)
    tail = list(history[-window:]) if history else []
    med = statistics.median(tail) if tail else 0.0
    residuals = [h - med for h in tail]
    p10_off = _percentile(residuals, 0.1) if residuals else 0.0
    p90_off = _percentile(residuals, 0.9) if residuals else 0.0
    return {
        "p10": [_pos(med + p10_off)] * horizon,
        "p50": [_pos(med)] * horizon,
        "p90": [_pos(med + p90_off)] * horizon,
    }


def seasonal_naive(
    history: Sequence[float], horizon: int, period: int = 7
) -> ForecastBands:
    """Weekly seasonal naive with residual-based bands."""
    if not history or len(history) < period + 1:
        return rolling_median(history, horizon)
    hist = list(history)
    resid = [hist[i] - hist[i - period] for i in range(period, len(hist))]
    p10_off = _percentile(resid, 0.1) if resid else 0.0
    p90_off = _percentile(resid, 0.9) if resid else 0.0
    # cycle last period
    last_cycle = hist[-period:]
    p50 = [last_cycle[i % period] for i in range(horizon)]
    return {
        "p10": [_pos(v + p10_off) for v in p50],
        "p50": [_pos(v) for v in p50],
        "p90": [_pos(v + p90_off) for v in p50],
    }


def naive_mean(history: Sequence[float], horizon: int) -> ForecastBands:
    if not history:
        return {"p10": [0.0] * horizon, "p50": [0.0] * horizon, "p90": [0.0] * horizon}
    mu = statistics.mean(history)
    sd = statistics.pstdev(history) if len(history) >= 2 else 0.0
    # 1.2816 ~ z at 0.9 (matches 80% PI band)
    return {
        "p10": [_pos(mu - 1.2816 * sd)] * horizon,
        "p50": [_pos(mu)] * horizon,
        "p90": [_pos(mu + 1.2816 * sd)] * horizon,
    }
