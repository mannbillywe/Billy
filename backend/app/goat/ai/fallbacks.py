"""Deterministic fallback envelope — used when Gemini is off, errors, or fails validation.

The fallback MUST mirror the shape of ``GoatAIEnvelopeOut`` so downstream
renderers/UI don't care whether Gemini or the fallback produced it.

Everything here is sourced from the input bundle only. No templated numbers
that aren't already in the bundle.
"""
from __future__ import annotations

from typing import Any

from ..contracts import (
    AICoachingNudge,
    AIFollowUpQuestion,
    AIMissingInputPrompt,
    AIPillar,
    AIRecommendationPhrasing,
    GoatAIEnvelopeOut,
)

SEVERITY_TO_URGENCY: dict[str, str] = {
    "info": "info",
    "watch": "watch",
    "warn": "warn",
    "critical": "critical",
}


def _summarise_pillars(ai_bundle: dict[str, Any]) -> list[AIPillar]:
    readiness = ai_bundle.get("readiness_level", "L1")
    pillars: list[AIPillar] = [
        AIPillar(
            pillar="overview",
            observation=(
                f"Snapshot generated at readiness {readiness} "
                f"covering scope {ai_bundle.get('scope')}."
            ),
            inference=(
                "Add the missing inputs below to unlock deeper, higher-confidence analysis."
                if ai_bundle.get("missing_inputs")
                else "Coverage is healthy for this scope."
            ),
            confidence="medium",
            reason_codes=[f"readiness:{readiness}"],
        )
    ]

    # Forecast pillar — summarise first OK target, if any.
    ok_fc = next(
        (
            t
            for t in ai_bundle.get("forecast_targets") or []
            if t.get("status") == "ok"
        ),
        None,
    )
    if ok_fc:
        pillars.append(
            AIPillar(
                pillar="forecast",
                observation=(
                    f"Forecast {ok_fc.get('target')} ran via {ok_fc.get('model_used')} "
                    f"over a {ok_fc.get('horizon_days')}-day horizon."
                ),
                inference=(
                    "Forecast is directional. Treat the range (p10–p90) as the primary signal."
                ),
                confidence=ok_fc.get("confidence_bucket", "unknown"),
                reason_codes=list(ok_fc.get("reason_codes") or [])[:3],
            )
        )

    # Anomaly pillar — surface the top one.
    top_an = next(iter(ai_bundle.get("anomaly_items") or []), None)
    if top_an:
        pillars.append(
            AIPillar(
                pillar="anomaly",
                observation=(
                    top_an.get("explanation")
                    or f"{top_an.get('anomaly_type')} flagged via {top_an.get('method')}."
                )[:400],
                inference=(
                    "Consider whether this is a category-tagging quirk or a real shift "
                    "before acting on it."
                ),
                confidence=top_an.get("confidence_bucket", "unknown"),
                reason_codes=list(top_an.get("reason_codes") or [])[:3],
            )
        )

    # Risk pillar — surface highest-severity risk with data_sufficient=True.
    risks = ai_bundle.get("risk_scores") or []
    risk = next((r for r in risks if r.get("data_sufficient")), None)
    if risk:
        pillars.append(
            AIPillar(
                pillar="risk",
                observation=(
                    f"Risk target {risk.get('target')} scored via {risk.get('method_used')}."
                ),
                inference=(
                    "This score is heuristic; treat the severity label as the primary call."
                ),
                confidence=risk.get("confidence_bucket", "unknown"),
                reason_codes=list(risk.get("reason_codes") or [])[:3],
            )
        )
    return pillars


def _phrase_recs(ai_bundle: dict[str, Any]) -> list[AIRecommendationPhrasing]:
    out: list[AIRecommendationPhrasing] = []
    for r in ai_bundle.get("recommendations") or []:
        title = r.get("title") or (r.get("kind") or "Recommendation").replace("_", " ").title()
        out.append(
            AIRecommendationPhrasing(
                rec_fingerprint=r.get("rec_fingerprint") or "",
                title=title[:120],
                body=(
                    f"Deterministic phrasing based on your computed data "
                    f"({r.get('kind')})."
                )[:600],
                why_shown=(
                    "Derived from your transactions, budgets, and recurring series without AI."
                )[:400],
                urgency_label=SEVERITY_TO_URGENCY.get(  # type: ignore[arg-type]
                    r.get("severity", "info"), "info"
                ),
            )
        )
    return out


def _prompts_from_missing(ai_bundle: dict[str, Any]) -> list[AIMissingInputPrompt]:
    out: list[AIMissingInputPrompt] = []
    for m in ai_bundle.get("missing_inputs") or []:
        out.append(
            AIMissingInputPrompt(
                input_key=m.get("key", "unknown"),
                title=(m.get("label") or m.get("key") or "Add input")[:120],
                body=(m.get("why") or "Provide this to unlock richer analysis.")[:400],
                unlocks=list(m.get("unlocks") or []),
            )
        )
    return out


def build_fallback_envelope(ai_bundle: dict[str, Any]) -> GoatAIEnvelopeOut:
    scope = ai_bundle.get("scope", "full")
    readiness = ai_bundle.get("readiness_level", "L1")
    n_recs = len(ai_bundle.get("recommendations") or [])
    n_missing = len(ai_bundle.get("missing_inputs") or [])
    summary = (
        f"Goat Mode ran scope={scope} at readiness {readiness}. "
        f"{n_recs} recommendations produced; {n_missing} input(s) still missing. "
        "This summary is deterministic fallback phrasing."
    )
    return GoatAIEnvelopeOut(
        narrative_summary=summary[:600],
        pillars=_summarise_pillars(ai_bundle),
        recommendation_phrasings=_phrase_recs(ai_bundle),
        missing_input_prompts=_prompts_from_missing(ai_bundle),
        coaching=[
            AICoachingNudge(
                topic="keep_going",
                body=(
                    "Check the recommendations tab for the highest-impact items first."
                )[:400],
            )
        ],
        follow_up_questions=[
            AIFollowUpQuestion(
                question="Would you like to see details for a specific recommendation?",
                pillar="overview",
            )
        ]
        if n_recs
        else [],
    )
