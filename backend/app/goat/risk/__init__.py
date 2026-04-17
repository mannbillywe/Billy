"""Goat Mode risk layer (Phase 3).

Public entry point: ``run_risk_layer(bundle, payload, forecast) -> RiskLayer``.
"""
from __future__ import annotations

from .scorer import run_risk_layer

__all__ = ["run_risk_layer"]
