"""Goat Mode forecasting layer (Phase 3).

Public entry point: ``run_forecasting_layer(bundle) -> ForecastLayer``.

Stays lean: stdlib-only baselines always work, statsmodels/Prophet are
optional and guarded. The caller NEVER has to install heavy wheels just to
boot the backend.
"""
from __future__ import annotations

from .policy import run_forecasting_layer

__all__ = ["run_forecasting_layer"]
