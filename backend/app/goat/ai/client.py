"""Gemini client wrapper with disabled / fake / real modes.

The runner must never crash if:
  - GOAT_AI_ENABLED=0
  - GEMINI_API_KEY is missing
  - google-genai is not installed
  - the Gemini API is unreachable or errors out
  - Gemini returns malformed JSON

In all these cases we return a deterministic fallback envelope and surface a
clear reason code. The validator is the gatekeeper for "did we accept the
Gemini output?" — this client just returns raw JSON + a mode tag.
"""
from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from typing import Any

log = logging.getLogger(__name__)

# ─── env flags ──────────────────────────────────────────────────────────────

ENV_ENABLED = "GOAT_AI_ENABLED"
ENV_FAKE = "GOAT_AI_FAKE_MODE"
ENV_MODEL = "GOAT_AI_MODEL"
ENV_KEY = "GEMINI_API_KEY"

DEFAULT_MODEL = "gemini-3-flash-preview"
# Gemini per-call deadlines. We stay well under the default client timeouts
# so a slow run can still fall back to deterministic phrasing quickly.
REQUEST_TIMEOUT_S = 25


# ─── resolution ─────────────────────────────────────────────────────────────


def _flag(name: str, default: str = "0") -> bool:
    return os.getenv(name, default).strip().lower() in {"1", "true", "yes", "on"}


def resolve_mode() -> str:
    """Return the effective AI mode: ``"real"`` | ``"fake"`` | ``"disabled"``."""
    if not _flag(ENV_ENABLED, default="0"):
        return "disabled"
    if _flag(ENV_FAKE, default="0"):
        return "fake"
    if not os.getenv(ENV_KEY):
        return "disabled"
    try:
        import google.genai  # noqa: F401
    except ImportError:
        return "disabled"
    return "real"


def resolve_model() -> str:
    return os.getenv(ENV_MODEL, DEFAULT_MODEL)


# ─── result type ────────────────────────────────────────────────────────────


@dataclass
class RawAIResult:
    mode: str  # disabled | fake | real
    model: str | None
    parsed: dict[str, Any] | None  # raw JSON dict from the model or None
    error: str | None = None
    reason_codes: list[str] | None = None

    def with_reason(self, code: str) -> "RawAIResult":
        codes = list(self.reason_codes or [])
        codes.append(code)
        return RawAIResult(
            mode=self.mode,
            model=self.model,
            parsed=self.parsed,
            error=self.error,
            reason_codes=codes,
        )


# ─── fake-mode deterministic stand-in ───────────────────────────────────────


def _fake_envelope(bundle_input: dict[str, Any]) -> dict[str, Any]:
    """Deterministic stand-in for Gemini — produces a shape-valid envelope.

    Used when ``GOAT_AI_FAKE_MODE=1`` so local tests exercise the full
    validation/rendering path without requiring network access.
    """
    recs = bundle_input.get("recommendations") or []
    missing = bundle_input.get("missing_inputs") or []
    readiness = bundle_input.get("readiness_level", "L1")
    return {
        "narrative_summary": (
            f"Goat Mode ran at readiness {readiness} with "
            f"{len(recs)} recommendations and {len(missing)} missing inputs. "
            "This summary is generated in fake AI mode and is intentionally neutral."
        ),
        "pillars": [
            {
                "pillar": "overview",
                "observation": f"Snapshot readiness is {readiness}.",
                "inference": "Further setup unlocks deeper analysis.",
                "confidence": "medium",
                "reason_codes": [f"readiness:{readiness}"],
            }
        ],
        "recommendation_phrasings": [
            {
                "rec_fingerprint": r.get("rec_fingerprint", ""),
                "title": r.get("title") or r.get("kind", "Recommendation").replace("_", " ").title(),
                "body": "Deterministic fallback phrasing (fake AI mode).",
                "why_shown": "Computed directly from your data in fake AI mode.",
                "urgency_label": r.get("severity", "info"),
            }
            for r in recs[:5]
        ],
        "missing_input_prompts": [
            {
                "input_key": m.get("key", "unknown"),
                "title": m.get("label") or m.get("key", "Add input"),
                "body": m.get("why") or "Provide this to unlock richer analysis.",
                "unlocks": m.get("unlocks", []),
            }
            for m in missing[:5]
        ],
        "coaching": [],
        "follow_up_questions": [],
    }


# ─── real Gemini call ───────────────────────────────────────────────────────


def _call_gemini_real(model: str, prompt: str) -> RawAIResult:
    """Call Gemini with strict structured-JSON output.

    We use ``response_mime_type="application/json"`` so the model returns valid
    JSON and we don't have to strip code fences.
    """
    try:
        from google import genai
        from google.genai import types as gtypes
    except ImportError as exc:
        return RawAIResult(
            mode="disabled",
            model=None,
            parsed=None,
            error=f"google-genai unavailable: {exc}",
            reason_codes=["sdk_missing"],
        )

    try:
        client = genai.Client()
        config = gtypes.GenerateContentConfig(
            response_mime_type="application/json",
            # Conservative sampling — phrasing, not creative writing.
            temperature=0.2,
            top_p=0.9,
        )
        response = client.models.generate_content(
            model=model,
            contents=prompt,
            config=config,
        )
    except Exception as exc:  # noqa: BLE001
        log.exception("gemini call failed")
        return RawAIResult(
            mode="real",
            model=model,
            parsed=None,
            error=f"{type(exc).__name__}: {str(exc)[:240]}",
            reason_codes=["gemini_call_failed"],
        )

    text = (getattr(response, "text", None) or "").strip()
    if not text:
        return RawAIResult(
            mode="real",
            model=model,
            parsed=None,
            error="empty_response_text",
            reason_codes=["empty_response"],
        )

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        return RawAIResult(
            mode="real",
            model=model,
            parsed=None,
            error=f"json_decode_error: {exc}",
            reason_codes=["malformed_json"],
        )
    if not isinstance(parsed, dict):
        return RawAIResult(
            mode="real",
            model=model,
            parsed=None,
            error="response_not_object",
            reason_codes=["not_object"],
        )
    return RawAIResult(mode="real", model=model, parsed=parsed)


# ─── public dispatcher ──────────────────────────────────────────────────────


def call_ai(bundle_input: dict[str, Any], prompt: str) -> RawAIResult:
    """Route to real / fake / disabled based on env flags."""
    mode = resolve_mode()
    if mode == "disabled":
        return RawAIResult(
            mode="disabled",
            model=None,
            parsed=None,
            reason_codes=["ai_disabled_or_key_missing"],
        )
    if mode == "fake":
        return RawAIResult(
            mode="fake",
            model="fake-deterministic",
            parsed=_fake_envelope(bundle_input),
            reason_codes=["fake_mode"],
        )
    return _call_gemini_real(resolve_model(), prompt)
