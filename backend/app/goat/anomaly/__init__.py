"""Goat Mode anomaly layer (Phase 3).

Public entry point: ``run_anomaly_layer(bundle, payload) -> AnomalyLayer``.
"""
from __future__ import annotations

from .detector import run_anomaly_layer

__all__ = ["run_anomaly_layer"]
