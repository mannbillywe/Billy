"""Strict grounding validator for Gemini output.

Gemini (or the fake path) hands us a dict. Before it can land on the snapshot
we check:

  A) Schema shape via Pydantic (``GoatAIEnvelopeOut``).
  B) Every `rec_fingerprint` in `recommendation_phrasings` exists in the
     input bundle.
  C) Every `input_key` in `missing_input_prompts` exists in the input.
  D) Every pillar's `reason_codes` is a subset of the reason codes that
     actually appear in the input bundle.
  E) No hallucinated numerics — any digit run ≥ 3 chars in the pillar /
     narrative / phrasing text must exist in the input bundle's stringified
     JSON (so "5,000" has to be grounded; "a few" is fine).
  F) No prohibited advice patterns ("buy stock X", "invest in ...", etc.).

If ANY check fails, the envelope is rejected and the runner falls back to
deterministic phrasing. The validator never raises — it returns a report.
"""
from __future__ import annotations

import json
import re
from typing import Any

from pydantic import ValidationError

from ..contracts import AIValidationReport, GoatAIEnvelopeOut

# Compiled digit pattern. We tolerate 1- and 2-digit integers because those
# are usually harmless (e.g. "a 7-day outlook", "1 month"). Anything bigger
# must be grounded in the input bundle.
DIGIT_RE = re.compile(r"\d[\d,\.]*\d|\d{3,}")
PROHIBITED_PATTERNS = [
    re.compile(p, re.IGNORECASE)
    for p in (
        r"\bbuy\s+(stock|shares?|crypto|bitcoin|ether(?:eum)?)\b",
        r"\binvest\s+in\s+\w",
        r"\btax\s+deduction\s+under\s+section",
        r"\bguaranteed\s+returns?\b",
        r"\brisk[-\s]?free\b",
    )
]


def _collect_input_reason_codes(ai_bundle: dict[str, Any]) -> set[str]:
    codes: set[str] = set()
    for bucket in ("metrics", "forecast_targets", "anomaly_items", "risk_scores"):
        for item in ai_bundle.get(bucket) or []:
            for c in item.get("reason_codes") or []:
                codes.add(str(c))
            # `inputs_missing` on metrics are also valid codes
            # (pillars often want to reference them explicitly).
            for c in item.get("inputs_missing") or []:
                codes.add(str(c))
                codes.add(f"missing:{c}")
    # Missing-input keys + unlocks are both valid reason-code strings.
    for m in ai_bundle.get("missing_inputs") or []:
        if m.get("key"):
            codes.add(str(m["key"]))
            codes.add(f"missing:{m['key']}")
        for u in m.get("unlocks") or []:
            codes.add(str(u))
    # Framework-level codes the bundle header exposes.
    if (r := ai_bundle.get("readiness_level")):
        codes.add(f"readiness:{r}")
    if (s := ai_bundle.get("scope")):
        codes.add(f"scope:{s}")
    # Layer-error names are acceptable codes too (e.g. "layer_error:forecast").
    for k in (ai_bundle.get("layer_errors") or {}).keys():
        codes.add(f"layer_error:{k}")
    # inputs_used list values are valid identifiers too.
    for u in ai_bundle.get("inputs_used") or []:
        codes.add(str(u))
    return codes


def _collect_input_fingerprints(ai_bundle: dict[str, Any]) -> set[str]:
    return {r.get("rec_fingerprint") for r in ai_bundle.get("recommendations") or []}


def _collect_input_missing_keys(ai_bundle: dict[str, Any]) -> set[str]:
    return {m.get("key") for m in ai_bundle.get("missing_inputs") or []}


def _normalise_num(raw: str) -> set[str]:
    """Produce all equivalent string representations of a digit token.

    Accepts "13,239.0", "13239.0", "13239", "13239.00", ".5", "05", etc.
    Returns a set of canonical strings we can compare across input and output.

    Also normalises ratios (|x| <= 1) to their percent equivalent with 0-2
    decimals, so that ``0.5186`` in the bundle matches ``51.86`` in the
    narrative. This is still tight grounding — we only allow exact ratio→%
    conversions, not arbitrary arithmetic.
    """
    out: set[str] = {raw}
    cleaned = raw.strip().rstrip(".").replace(",", "")
    out.add(cleaned)
    try:
        f = float(cleaned)
    except (ValueError, TypeError):
        return out
    out.add(str(f))
    if f.is_integer():
        out.add(str(int(f)))
    out.add(f"{f:.2f}")

    # Ratio ↔ percent equivalence (only for |f| <= 1, safe domain).
    if -1.0 <= f <= 1.0:
        pct = f * 100
        out.add(f"{pct:.0f}")
        out.add(f"{pct:.1f}")
        out.add(f"{pct:.2f}")
        out.add(str(round(pct, 2)))
        out.add(str(abs(pct)))
        out.add(f"{abs(pct):.2f}")
    # Rounded integer fallback (common when models summarise large counts).
    if abs(f) >= 100:
        out.add(str(int(round(f))))
        out.add(f"{int(round(f)):,}")
    return out


def _collect_input_digit_tokens(ai_bundle: dict[str, Any]) -> set[str]:
    """Every meaningful digit run that appears in the authoritative bundle text.

    We normalise thousand separators, trailing decimal zeros, and int/float
    representation so that "55,554", "55554", "55554.0", "55554.00" all match.
    """
    as_text = json.dumps(ai_bundle, default=str)
    tokens: set[str] = set()
    for m in DIGIT_RE.findall(as_text):
        tokens.update(_normalise_num(m))
    return tokens


def _ungrounded_digits(text: str, grounded: set[str]) -> list[str]:
    out: list[str] = []
    for m in DIGIT_RE.findall(text or ""):
        variants = _normalise_num(m)
        if variants & grounded:
            continue
        # Also suppress if this is a date-like fragment whose pieces are
        # grounded (e.g. "2026-04-17" → "2026", "04", "17" all fine).
        parts = re.split(r"[-/:T ]", m)
        if parts and all(
            (not p) or (_normalise_num(p) & grounded) or len(p) <= 2
            for p in parts
        ):
            continue
        out.append(m)
    return out


def _prohibited_hits(text: str) -> list[str]:
    hits: list[str] = []
    for pat in PROHIBITED_PATTERNS:
        m = pat.search(text or "")
        if m:
            hits.append(m.group(0))
    return hits


def validate_envelope(
    raw_parsed: dict[str, Any],
    *,
    ai_bundle: dict[str, Any],
) -> tuple[GoatAIEnvelopeOut | None, AIValidationReport]:
    """Run all grounding checks. Returns (envelope_or_None, report)."""
    errors: list[str] = []
    warnings: list[str] = []

    # A) Schema shape
    try:
        env = GoatAIEnvelopeOut.model_validate(raw_parsed)
    except ValidationError as e:
        # Keep error text tight so it survives the snapshot column.
        errors.append(f"schema:{str(e)[:220]}")
        return None, AIValidationReport(passed=False, errors=errors, warnings=warnings)

    # B) rec_fingerprint references
    valid_fps = _collect_input_fingerprints(ai_bundle)
    for p in env.recommendation_phrasings:
        if p.rec_fingerprint not in valid_fps:
            errors.append(f"rec_fingerprint_not_in_input:{p.rec_fingerprint}")

    # C) missing-input key references
    valid_mi = _collect_input_missing_keys(ai_bundle)
    for mip in env.missing_input_prompts:
        if mip.input_key not in valid_mi:
            errors.append(f"missing_input_key_not_in_input:{mip.input_key}")

    # D) reason code grounding for pillars
    valid_codes = _collect_input_reason_codes(ai_bundle)
    if valid_codes:  # if input has no codes at all, skip this check
        for pl in env.pillars:
            if not pl.reason_codes:
                warnings.append(f"pillar_no_reason_codes:{pl.pillar}")
                continue
            for c in pl.reason_codes:
                if c not in valid_codes:
                    errors.append(f"pillar_reason_code_not_in_input:{pl.pillar}:{c}")

    # E) numeric grounding across narrative / pillars / phrasings / coaching
    grounded_nums = _collect_input_digit_tokens(ai_bundle)
    texts_to_check: list[tuple[str, str]] = [("narrative", env.narrative_summary)]
    for pl in env.pillars:
        texts_to_check.append((f"pillar:{pl.pillar}:observation", pl.observation))
        texts_to_check.append((f"pillar:{pl.pillar}:inference", pl.inference))
    for p in env.recommendation_phrasings:
        texts_to_check.append((f"rec:{p.rec_fingerprint}:title", p.title))
        texts_to_check.append((f"rec:{p.rec_fingerprint}:body", p.body))
        texts_to_check.append((f"rec:{p.rec_fingerprint}:why", p.why_shown))
    for mip in env.missing_input_prompts:
        texts_to_check.append((f"missing:{mip.input_key}:body", mip.body))
    for c in env.coaching:
        texts_to_check.append((f"coach:{c.topic}", c.body))
    for f in env.follow_up_questions:
        texts_to_check.append((f"followup:{f.pillar}", f.question))

    for tag, t in texts_to_check:
        ungrounded = _ungrounded_digits(t, grounded_nums)
        if ungrounded:
            errors.append(f"ungrounded_digits:{tag}:{','.join(ungrounded[:3])}")

    # F) Prohibited advice
    for tag, t in texts_to_check:
        hits = _prohibited_hits(t)
        if hits:
            errors.append(f"prohibited_advice:{tag}:{hits[0]}")

    passed = not errors
    return (env if passed else None), AIValidationReport(
        passed=passed, errors=errors, warnings=warnings
    )
