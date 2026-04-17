"""Orchestrator for the Goat Mode AI layer.

Combines:
  prompts.build_ai_input_bundle  → flat dict (auth source for validator)
  prompts.build_prompt           → string prompt for Gemini
  client.call_ai                 → routes to disabled/fake/real
  validator.validate_envelope    → grounded-or-bust
  fallbacks.build_fallback_envelope → deterministic stand-in

The returned ``AILayer`` is always typed and always contains a valid envelope,
so the runner can persist it unconditionally.
"""
from __future__ import annotations

import logging
from typing import Any

from ..contracts import (
    AILayer,
    AIValidationReport,
    AnomalyLayer,
    CoverageSummary,
    ForecastLayer,
    RecommendationOut,
    RiskLayer,
    Scope,
    ScopePayload,
)
from ..scoring import utcnow_iso
from ..versions import MODEL_VERSIONS
from . import client as ai_client
from .fallbacks import build_fallback_envelope
from .prompts import build_ai_input_bundle, build_prompt
from .validator import validate_envelope

log = logging.getLogger(__name__)

AI_LAYER_VERSION = MODEL_VERSIONS.get("ai", "0.1.0")


def run_ai_layer(
    *,
    scope: Scope,
    payload: ScopePayload,
    coverage: CoverageSummary,
    recs: list[RecommendationOut],
    forecast: ForecastLayer | None,
    anomalies: AnomalyLayer | None,
    risk: RiskLayer | None,
    layer_errors: dict[str, str],
    currency: str | None = None,
) -> AILayer:
    """Entry point called from runner.run_job()."""
    ai_bundle = build_ai_input_bundle(
        scope=scope,
        payload=payload,
        coverage=coverage,
        recs=recs,
        forecast=forecast,
        anomalies=anomalies,
        risk=risk,
        layer_errors=layer_errors,
        currency=currency,
    )
    prompt = build_prompt(ai_bundle)
    raw = ai_client.call_ai(ai_bundle, prompt)

    layer_statuses = _layer_status_snapshot(
        forecast=forecast,
        anomalies=anomalies,
        risk=risk,
        layer_errors=layer_errors,
    )

    # Mode resolution: disabled → fallback immediately. No API call happens.
    if raw.mode == "disabled":
        return _fallback_layer(
            ai_bundle,
            reason_codes=list(raw.reason_codes or ["ai_disabled"]),
            mode="disabled",
            model=None,
            layer_statuses=layer_statuses,
        )

    # Real/fake returned raw JSON OR an error. Either way: try to validate.
    if raw.parsed is None:
        return _fallback_layer(
            ai_bundle,
            reason_codes=list(raw.reason_codes or [])
            + ([raw.error] if raw.error else []),
            mode=raw.mode,
            model=raw.model,
            layer_statuses=layer_statuses,
        )

    env, report = validate_envelope(raw.parsed, ai_bundle=ai_bundle)
    if env is None:
        # Grounding check failed → fallback but record the errors for audit.
        fallback = _fallback_layer(
            ai_bundle,
            reason_codes=["validation_failed"] + list(raw.reason_codes or []),
            mode=raw.mode,
            model=raw.model,
            layer_statuses=layer_statuses,
        )
        # Preserve the real validation report instead of the fallback stub.
        fallback.validation = report
        return fallback

    return AILayer(
        version=AI_LAYER_VERSION,
        generated_at=utcnow_iso(),
        mode=raw.mode,  # type: ignore[arg-type]
        model=raw.model,
        ai_validated=True,
        fallback_used=False,
        reason_codes=list(raw.reason_codes or []),
        envelope=env,
        validation=report,
        layer_statuses=layer_statuses,
        model_versions=MODEL_VERSIONS,
    )


# ─── helpers ────────────────────────────────────────────────────────────────


def _fallback_layer(
    ai_bundle: dict[str, Any],
    *,
    reason_codes: list[str],
    mode: str,
    model: str | None,
    layer_statuses: dict[str, str],
) -> AILayer:
    env = build_fallback_envelope(ai_bundle)
    return AILayer(
        version=AI_LAYER_VERSION,
        generated_at=utcnow_iso(),
        mode=mode,  # type: ignore[arg-type]
        model=model,
        ai_validated=False,
        fallback_used=True,
        reason_codes=list(reason_codes or []),
        envelope=env,
        validation=AIValidationReport(passed=False, errors=[], warnings=["fallback_used"]),
        layer_statuses=dict(layer_statuses),
        model_versions=MODEL_VERSIONS,
    )


def _layer_status_snapshot(
    *,
    forecast: ForecastLayer | None,
    anomalies: AnomalyLayer | None,
    risk: RiskLayer | None,
    layer_errors: dict[str, str],
) -> dict[str, str]:
    def _st(name: str, obj: Any) -> str:
        if name in layer_errors:
            return f"error:{layer_errors[name][:60]}"
        if obj is None:
            return "missing"
        disabled = getattr(obj, "disabled", False)
        return "disabled" if disabled else "ok"

    return {
        "forecast": _st("forecast", forecast),
        "anomaly": _st("anomaly", anomalies),
        "risk": _st("risk", risk),
    }
