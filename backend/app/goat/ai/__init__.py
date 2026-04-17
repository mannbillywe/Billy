"""Goat Mode — Phase 4 AI layer.

Gemini is a *phrasing/explanation* layer over already-computed deterministic
and statistical outputs. It must never decide which recommendations exist,
invent numbers, or make causal claims beyond the input bundle.

Public entry point:

    from goat.ai import run_ai_layer
    ai = run_ai_layer(bundle=..., payload=..., coverage=..., recs=..., forecast=..., anomalies=..., risk=..., layer_errors=...)

`run_ai_layer` always returns a typed ``AILayer`` — it will fall back to a
deterministic envelope whenever Gemini is disabled, fails, or produces an
ungrounded payload.
"""
from __future__ import annotations

from .renderer import run_ai_layer

__all__ = ["run_ai_layer"]
