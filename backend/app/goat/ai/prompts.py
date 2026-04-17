"""Prompt builders for the Goat Mode AI layer.

We send Gemini a tight, scope-aware input bundle assembled from already-computed
outputs. The prompt hard-constrains the model to:

  1. Produce valid JSON matching ``GoatAIEnvelopeOut``.
  2. Reference only entities/numbers/fingerprints that appear in the bundle.
  3. Separate observation / inference / recommendation.
  4. Stay conservative when confidence is low or inputs are missing.

``build_ai_input_bundle`` is a dict, NOT a Pydantic model — it's deliberately
flat and easy to validate later against Gemini's output.
"""
from __future__ import annotations

import json
from typing import Any

from ..contracts import (
    AnomalyLayer,
    CoverageSummary,
    ForecastLayer,
    RecommendationOut,
    RiskLayer,
    Scope,
    ScopePayload,
)

MAX_RECS_TO_PHRASE = 12
MAX_ANOMALIES_TO_SHOW = 8
MAX_FORECAST_TARGETS_TO_SHOW = 6
MAX_RISK_TARGETS_TO_SHOW = 5


# ─── input assembly ────────────────────────────────────────────────────────


def _clip_metrics(payload: ScopePayload) -> list[dict[str, Any]]:
    # Snip large details — we just want key/value/confidence/reason_codes.
    out: list[dict[str, Any]] = []
    for m in payload.metrics:
        out.append(
            {
                "key": m.key,
                "value": m.value,
                "unit": m.unit,
                "confidence_bucket": m.confidence_bucket,
                "reason_codes": list(m.reason_codes or []),
                "inputs_missing": list(m.inputs_missing or []),
            }
        )
    return out


def _clip_forecast(forecast: ForecastLayer | None) -> list[dict[str, Any]]:
    if not forecast or forecast.disabled:
        return []
    out: list[dict[str, Any]] = []
    for t in forecast.targets[:MAX_FORECAST_TARGETS_TO_SHOW]:
        out.append(
            {
                "target": t.target,
                "status": t.status,
                "model_used": t.model_used,
                "confidence_bucket": t.confidence_bucket,
                "horizon_days": t.horizon_days,
                "reason_codes": list(t.reason_codes or []),
                "insufficient_data_fields": list(t.insufficient_data_fields or []),
                # Pass only aggregated values — not the full series.
                "value_keys": sorted(list((t.value or {}).keys())),
                "value": {
                    k: t.value[k]
                    for k in ("p10_total", "p50_total", "p90_total", "runway_months")
                    if isinstance(t.value, dict) and k in t.value
                },
            }
        )
    return out


def _clip_anomalies(anomalies: AnomalyLayer | None) -> list[dict[str, Any]]:
    if not anomalies or anomalies.disabled:
        return []
    # Rank by score desc, cap to avoid flooding the prompt.
    items = sorted(
        anomalies.items,
        key=lambda a: (a.severity != "info", a.score or 0),
        reverse=True,
    )[:MAX_ANOMALIES_TO_SHOW]
    return [
        {
            "anomaly_type": a.anomaly_type,
            "method": a.method,
            "severity": a.severity,
            "score": a.score,
            "confidence_bucket": a.confidence_bucket,
            "entity_id": a.entity_id,
            "entity_type": a.entity_type,
            "reason_codes": list(a.reason_codes or []),
            "explanation": a.explanation,
        }
        for a in items
    ]


def _clip_risk(risk: RiskLayer | None) -> list[dict[str, Any]]:
    if not risk or risk.disabled:
        return []
    return [
        {
            "target": s.target,
            "method_used": s.method_used,
            "severity": s.severity,
            "probability": s.probability,
            "confidence_bucket": s.confidence_bucket,
            "data_sufficient": s.data_sufficient,
            "reason_codes": list(s.reason_codes or []),
            "insufficient_data_fields": list(s.insufficient_data_fields or []),
        }
        for s in risk.scores[:MAX_RISK_TARGETS_TO_SHOW]
    ]


def _clip_recs(recs: list[RecommendationOut]) -> list[dict[str, Any]]:
    return [
        {
            "rec_fingerprint": r.rec_fingerprint,
            "kind": r.kind,
            "severity": r.severity,
            "priority": r.priority,
            "confidence": r.confidence,
            "entity_type": r.entity_type,
            "entity_id": r.entity_id,
            "title": (r.recommendation or {}).get("title") or (r.observation or {}).get("title"),
            "observation_keys": sorted(list((r.observation or {}).keys())),
            "recommendation_keys": sorted(list((r.recommendation or {}).keys())),
        }
        for r in recs[:MAX_RECS_TO_PHRASE]
    ]


def build_ai_input_bundle(
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
) -> dict[str, Any]:
    """Produce the flat dict that both the prompt and the validator use."""
    return {
        "scope": scope,
        "readiness_level": coverage.readiness_level,
        "coverage_score": coverage.coverage_score,
        "currency": currency,
        "missing_inputs": [m.model_dump(mode="json") for m in coverage.missing_inputs],
        "inputs_used": list(coverage.inputs_used),
        "metrics": _clip_metrics(payload),
        "forecast_targets": _clip_forecast(forecast),
        "anomaly_items": _clip_anomalies(anomalies),
        "risk_scores": _clip_risk(risk),
        "recommendations": _clip_recs(recs),
        "layer_errors": layer_errors,
    }


# ─── prompt rendering ───────────────────────────────────────────────────────


SYSTEM_RULES = """You are a conservative financial analytics assistant embedded in
an app called Billy. You ONLY explain and phrase outputs that have already
been computed deterministically. Follow these rules without exception:

1. The INPUT JSON is the single source of truth. You may not invent numbers,
   dates, amounts, merchants, categories, account names, or fingerprints that
   are not present in the INPUT.
2. DO NOT compute, derive, sum, average, or transform numbers. Do NOT produce
   percentages, ratios, totals, deltas, or growth rates unless the exact same
   number already appears in the INPUT. If you want to describe magnitude,
   use words ("small", "large", "roughly in line with prior months") rather
   than invented figures. Quoting a raw number from the INPUT is fine;
   computing a new one is not.
3. You may not create recommendations. You may only produce
   `recommendation_phrasings` items whose `rec_fingerprint` EXACTLY matches a
   `rec_fingerprint` in `input.recommendations`. Any phrasing referring to a
   non-existent fingerprint will be rejected.
4. You may not give tax, legal, or investment advice. No causal claims
   beyond what the reason_codes already imply.
5. Separate observation vs inference. Observations describe what the data
   shows; inferences are cautious interpretations. Never promise outcomes.
6. When confidence is low or data is missing, say so plainly. Prefer phrases
   like "directional only", "pending more data", "based on a short history".
7. Each pillar item must include at least one `reason_code` that appears
   VERBATIM somewhere in `input.metrics[*].reason_codes`,
   `input.forecast_targets[*].reason_codes`, `input.anomaly_items[*].reason_codes`,
   `input.risk_scores[*].reason_codes`, or one of the framework codes
   `readiness:<L1|L2|L3>` / `scope:<scope>`. Do not invent new reason code
   strings; copy from the input.
8. Missing-input prompts must reference `input_key` values that appear in
   `input.missing_inputs[*].key`.
9. Keep copy short, calm, and actionable. No emoji. No marketing tone.
10. RESPOND WITH VALID JSON that matches the OUTPUT SCHEMA exactly. No
    prose outside the JSON. No markdown fences.
"""


OUTPUT_SCHEMA_HINT = """OUTPUT SCHEMA (JSON shape, not a validator):

{
  "narrative_summary": string (<=600 chars),
  "pillars": [
    {
      "pillar": one of ["overview","cashflow","budgets","recurring","debt","goals","forecast","anomaly","risk"],
      "observation": string (<=400 chars),
      "inference": string (<=400 chars),
      "confidence": one of ["unknown","very_low","low","medium","high"],
      "reason_codes": [string, ...]  // MUST exist in INPUT
    }
  ],
  "recommendation_phrasings": [
    {
      "rec_fingerprint": string (MUST match an input.recommendations[*].rec_fingerprint),
      "title": string (<=120 chars),
      "body": string (<=600 chars),
      "why_shown": string (<=400 chars),
      "urgency_label": one of ["info","watch","warn","critical"]
    }
  ],
  "missing_input_prompts": [
    {
      "input_key": string (MUST match input.missing_inputs[*].key),
      "title": string (<=120 chars),
      "body": string (<=400 chars),
      "unlocks": [string, ...]
    }
  ],
  "coaching": [
    { "topic": string (<=80), "body": string (<=400) }
  ],
  "follow_up_questions": [
    { "question": string (<=200), "pillar": string }
  ]
}
"""


def build_prompt(ai_bundle: dict[str, Any]) -> str:
    """Render the full Gemini prompt for a given input bundle."""
    # json.dumps so the model sees a concrete, parseable payload.
    as_json = json.dumps(ai_bundle, indent=2, default=str, sort_keys=True)
    scope = ai_bundle.get("scope", "full")
    readiness = ai_bundle.get("readiness_level", "L1")
    return (
        SYSTEM_RULES
        + "\n\n"
        + OUTPUT_SCHEMA_HINT
        + "\n\nINPUT (authoritative):\n"
        + as_json
        + f"\n\nSCOPE: {scope}\nREADINESS: {readiness}\n"
        + "\nProduce the JSON now. Return nothing else.\n"
    )
