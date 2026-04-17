"""Robust-statistics primitives used by the anomaly detector.

Pure stdlib — small data, no numpy needed. Exposes:

- ``mad`` — Median Absolute Deviation
- ``robust_z`` — modified z-score (Iglewicz & Hoaglin 1993, MADe)
- ``iqr_bounds`` — Tukey fences
"""
from __future__ import annotations

import math
import statistics
from typing import Sequence


def mad(values: Sequence[float], center: float | None = None) -> float:
    if not values:
        return 0.0
    c = center if center is not None else statistics.median(values)
    abs_dev = [abs(v - c) for v in values]
    return statistics.median(abs_dev)


def robust_z(value: float, history: Sequence[float]) -> float:
    """Modified z-score using MAD; returns 0 if history too flat."""
    if len(history) < 3:
        return 0.0
    med = statistics.median(history)
    m = mad(history, center=med)
    if m <= 0:
        # Fallback to IQR-based scale; prevents divide-by-zero spikes on flat data.
        try:
            q1, q3 = _quantiles(history, [0.25, 0.75])
            iqr = q3 - q1
            if iqr <= 0:
                return 0.0
            return 0.6745 * (value - med) / (iqr / 1.35)
        except Exception:  # noqa: BLE001
            return 0.0
    return 0.6745 * (value - med) / m


def iqr_bounds(values: Sequence[float], k: float = 1.5) -> tuple[float, float]:
    if len(values) < 4:
        return (-math.inf, math.inf)
    q1, q3 = _quantiles(values, [0.25, 0.75])
    iqr = q3 - q1
    return (q1 - k * iqr, q3 + k * iqr)


def _quantiles(values: Sequence[float], probs: Sequence[float]) -> list[float]:
    if not values:
        return [0.0 for _ in probs]
    s = sorted(values)
    out: list[float] = []
    for p in probs:
        if len(s) == 1:
            out.append(float(s[0]))
            continue
        k = (len(s) - 1) * p
        lo = math.floor(k)
        hi = math.ceil(k)
        if lo == hi:
            out.append(float(s[lo]))
        else:
            out.append(float(s[lo]) * (hi - k) + float(s[hi]) * (k - lo))
    return out
