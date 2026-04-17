"""Tests for the Phase 4 AI layer (disabled / fake / real paths + grounding)."""
from __future__ import annotations

import os
from datetime import date, timedelta
from uuid import UUID

import pytest
from pydantic import ValidationError

from goat import runner as runner_mod
from goat import supabase_io as sb
from goat.ai import run_ai_layer
from goat.ai import client as ai_client
from goat.ai.fallbacks import build_fallback_envelope
from goat.ai.prompts import build_ai_input_bundle, build_prompt
from goat.ai.renderer import AI_LAYER_VERSION
from goat.ai.validator import validate_envelope
from goat.contracts import (
    AILayer,
    CoverageSummary,
    CoverageBreakdown,
    GoatAIEnvelopeOut,
    MissingInput,
    RecommendationOut,
    RunRequest,
    ScopePayload,
)


# ─── helpers ─────────────────────────────────────────────────────────────────


def _zero_coverage() -> CoverageSummary:
    return CoverageSummary(
        coverage_score=0.2,
        readiness_level="L1",
        breakdown=CoverageBreakdown(
            transactions=0.5,
            accounts=0.0,
            budgets=0.0,
            recurring=0.0,
            income_declared=0.0,
            goals=0.0,
            obligations=0.0,
        ),
        inputs_used=["transactions.recent"],
        missing_inputs=[
            MissingInput(
                key="accounts.any",
                label="Add an account",
                why="We need balances to compute liquidity.",
                unlocks=["overview", "cashflow"],
            )
        ],
    )


def _payload() -> ScopePayload:
    return ScopePayload(
        scope="full",
        status="partial",
        readiness_level="L1",
        confidence="low",
        metrics=[],
    )


def _rec(fp: str = "rec-1", kind: str = "missing_input") -> RecommendationOut:
    return RecommendationOut(
        kind=kind,  # type: ignore[arg-type]
        severity="info",
        priority=40,
        confidence=0.6,
        rec_fingerprint=fp,
        observation={"title": "Add accounts"},
        recommendation={"title": "Add accounts", "body": "Link one bank account."},
    )


@pytest.fixture(autouse=True)
def _clean_ai_env(monkeypatch):
    for k in ("GOAT_AI_ENABLED", "GOAT_AI_FAKE_MODE", "GEMINI_API_KEY", "GOAT_AI_MODEL"):
        monkeypatch.delenv(k, raising=False)
    yield


# ─── mode resolution ────────────────────────────────────────────────────────


def test_resolve_mode_disabled_by_default():
    assert ai_client.resolve_mode() == "disabled"


def test_resolve_mode_fake(monkeypatch):
    monkeypatch.setenv("GOAT_AI_ENABLED", "1")
    monkeypatch.setenv("GOAT_AI_FAKE_MODE", "1")
    assert ai_client.resolve_mode() == "fake"


def test_resolve_mode_real_requires_key(monkeypatch):
    monkeypatch.setenv("GOAT_AI_ENABLED", "1")
    monkeypatch.setenv("GOAT_AI_FAKE_MODE", "0")
    # no key → degrades to disabled
    assert ai_client.resolve_mode() == "disabled"
    monkeypatch.setenv("GEMINI_API_KEY", "dummy")
    # with key → real (assuming google-genai is importable; if not, disabled
    # is still a valid, safe answer — the runner handles it).
    assert ai_client.resolve_mode() in {"real", "disabled"}


# ─── contract schema ────────────────────────────────────────────────────────


def test_envelope_rejects_oversized_narrative():
    with pytest.raises(ValidationError):
        GoatAIEnvelopeOut(narrative_summary="x" * 1000)


def test_envelope_min_valid():
    env = GoatAIEnvelopeOut(narrative_summary="short and tidy")
    assert env.pillars == []
    assert env.recommendation_phrasings == []


# ─── validator grounding ────────────────────────────────────────────────────


def _bundle_for_validator() -> dict:
    return build_ai_input_bundle(
        scope="full",
        payload=_payload(),
        coverage=_zero_coverage(),
        recs=[_rec("rec-1"), _rec("rec-2")],
        forecast=None,
        anomalies=None,
        risk=None,
        layer_errors={},
        currency="INR",
    )


def test_validator_accepts_grounded_payload():
    ai_bundle = _bundle_for_validator()
    raw = {
        "narrative_summary": "Short deterministic summary.",
        "pillars": [],
        "recommendation_phrasings": [
            {
                "rec_fingerprint": "rec-1",
                "title": "Add accounts",
                "body": "Linking a bank account unlocks liquidity analysis.",
                "why_shown": "Computed from your profile inputs.",
                "urgency_label": "info",
            }
        ],
        "missing_input_prompts": [
            {
                "input_key": "accounts.any",
                "title": "Add an account",
                "body": "We need balances to compute liquidity.",
                "unlocks": ["overview"],
            }
        ],
        "coaching": [],
        "follow_up_questions": [],
    }
    env, report = validate_envelope(raw, ai_bundle=ai_bundle)
    assert report.passed, report.errors
    assert env is not None
    assert env.recommendation_phrasings[0].rec_fingerprint == "rec-1"


def test_validator_rejects_unknown_fingerprint():
    ai_bundle = _bundle_for_validator()
    raw = {
        "narrative_summary": "ok",
        "recommendation_phrasings": [
            {
                "rec_fingerprint": "ghost-fp",
                "title": "Invented rec",
                "body": "This was not in the input.",
                "why_shown": "because the AI invented it",
                "urgency_label": "info",
            }
        ],
    }
    env, report = validate_envelope(raw, ai_bundle=ai_bundle)
    assert env is None
    assert any("rec_fingerprint_not_in_input" in e for e in report.errors)


def test_validator_rejects_ungrounded_numbers():
    ai_bundle = _bundle_for_validator()
    # 77777 is not anywhere in the input bundle.
    raw = {
        "narrative_summary": "Your spending was 77777 this month.",
    }
    env, report = validate_envelope(raw, ai_bundle=ai_bundle)
    assert env is None
    assert any("ungrounded_digits" in e for e in report.errors)


def test_validator_rejects_prohibited_advice():
    ai_bundle = _bundle_for_validator()
    raw = {
        "narrative_summary": "You should buy stock ABC immediately for risk-free returns.",
    }
    env, report = validate_envelope(raw, ai_bundle=ai_bundle)
    assert env is None
    assert any("prohibited_advice" in e for e in report.errors)


def test_validator_rejects_unknown_missing_input_key():
    ai_bundle = _bundle_for_validator()
    raw = {
        "narrative_summary": "ok",
        "missing_input_prompts": [
            {
                "input_key": "not.a.real.key",
                "title": "Add something",
                "body": "Some body",
                "unlocks": [],
            }
        ],
    }
    env, report = validate_envelope(raw, ai_bundle=ai_bundle)
    assert env is None
    assert any("missing_input_key_not_in_input" in e for e in report.errors)


# ─── fallback ───────────────────────────────────────────────────────────────


def test_fallback_envelope_shape():
    ai_bundle = _bundle_for_validator()
    env = build_fallback_envelope(ai_bundle)
    assert isinstance(env, GoatAIEnvelopeOut)
    assert env.missing_input_prompts
    assert env.recommendation_phrasings
    assert env.missing_input_prompts[0].input_key == "accounts.any"


# ─── renderer orchestrator ─────────────────────────────────────────────────


def test_renderer_disabled_path_uses_fallback():
    ai = run_ai_layer(
        scope="full",
        payload=_payload(),
        coverage=_zero_coverage(),
        recs=[_rec("rec-1")],
        forecast=None,
        anomalies=None,
        risk=None,
        layer_errors={},
    )
    assert isinstance(ai, AILayer)
    assert ai.mode == "disabled"
    assert ai.ai_validated is False
    assert ai.fallback_used is True
    assert ai.version == AI_LAYER_VERSION


def test_renderer_fake_path_validates(monkeypatch):
    monkeypatch.setenv("GOAT_AI_ENABLED", "1")
    monkeypatch.setenv("GOAT_AI_FAKE_MODE", "1")
    ai = run_ai_layer(
        scope="full",
        payload=_payload(),
        coverage=_zero_coverage(),
        recs=[_rec("rec-1")],
        forecast=None,
        anomalies=None,
        risk=None,
        layer_errors={},
    )
    assert ai.mode == "fake"
    assert ai.ai_validated is True
    assert ai.fallback_used is False
    # fake envelope references the same fingerprint we fed in
    fps = {p.rec_fingerprint for p in ai.envelope.recommendation_phrasings}
    assert "rec-1" in fps


def test_renderer_real_mode_malformed_json_falls_back(monkeypatch):
    monkeypatch.setenv("GOAT_AI_ENABLED", "1")
    monkeypatch.setenv("GEMINI_API_KEY", "dummy")

    def _fake_call(model, prompt):
        return ai_client.RawAIResult(
            mode="real",
            model=model,
            parsed=None,
            error="simulated",
            reason_codes=["malformed_json"],
        )

    monkeypatch.setattr(ai_client, "_call_gemini_real", _fake_call)
    ai = run_ai_layer(
        scope="full",
        payload=_payload(),
        coverage=_zero_coverage(),
        recs=[_rec("rec-1")],
        forecast=None,
        anomalies=None,
        risk=None,
        layer_errors={},
    )
    assert ai.mode == "real"
    assert ai.ai_validated is False
    assert ai.fallback_used is True
    assert "malformed_json" in ai.reason_codes


def test_renderer_real_mode_validation_failure_falls_back(monkeypatch):
    monkeypatch.setenv("GOAT_AI_ENABLED", "1")
    monkeypatch.setenv("GEMINI_API_KEY", "dummy")

    def _fake_call(model, prompt):
        # Ungrounded number → must fail validation.
        return ai_client.RawAIResult(
            mode="real",
            model=model,
            parsed={"narrative_summary": "Your spend was 123456 last week."},
        )

    monkeypatch.setattr(ai_client, "_call_gemini_real", _fake_call)
    ai = run_ai_layer(
        scope="full",
        payload=_payload(),
        coverage=_zero_coverage(),
        recs=[_rec("rec-1")],
        forecast=None,
        anomalies=None,
        risk=None,
        layer_errors={},
    )
    assert ai.ai_validated is False
    assert ai.fallback_used is True
    # The real validation errors must surface, not be overwritten by fallback.
    assert any("ungrounded_digits" in e for e in ai.validation.errors)


# ─── runner integration ────────────────────────────────────────────────────

USER = "00000000-0000-0000-0000-0000000000aa"


def _seed_minimal(store):
    store.tables["profiles"].append(
        {"id": USER, "display_name": "Test", "preferred_currency": "INR"}
    )
    end = date(2026, 4, 1)
    for i in range(12):
        d = end - timedelta(days=i)
        store.tables["transactions"].append(
            {
                "id": f"tx-{i}",
                "user_id": USER,
                "amount": 300 + i,
                "date": d.isoformat(),
                "type": "expense",
                "status": "confirmed",
                "updated_at": f"{d.isoformat()}T00:00:00+00:00",
            }
        )


@pytest.fixture
def wired(monkeypatch, fake_client):
    monkeypatch.setattr(sb, "get_client", lambda: fake_client)
    return fake_client


def test_runner_returns_ai_layer_in_disabled_mode(wired, fake_store):
    _seed_minimal(fake_store)
    resp = runner_mod.run_job(RunRequest(user_id=UUID(USER), scope="full", dry_run=True))
    assert resp.ai is not None
    assert resp.ai.mode == "disabled"
    assert resp.ai.fallback_used is True


def test_runner_ai_layer_soft_fails_without_crashing(monkeypatch, wired, fake_store):
    _seed_minimal(fake_store)

    def _boom(**_kwargs):
        raise RuntimeError("synthetic ai layer failure")

    monkeypatch.setattr(runner_mod, "run_ai_layer", _boom)
    resp = runner_mod.run_job(RunRequest(user_id=UUID(USER), scope="full", dry_run=True))
    assert resp.ai is None
    assert "ai" in resp.layer_errors
    # The job must still complete (not fail), regardless of payload.status.
    assert resp.snapshot_status in {"completed", "partial"}
    # And importantly: the AI error alone did not push a non-AI-error entry.
    assert set(resp.layer_errors) == {"ai"}


def test_runner_persists_ai_layer_on_wet_run(wired, fake_store):
    _seed_minimal(fake_store)
    resp = runner_mod.run_job(RunRequest(user_id=UUID(USER), scope="full", dry_run=False))
    snaps = fake_store.tables["goat_mode_snapshots"]
    assert len(snaps) == 1
    snap = snaps[0]
    assert snap["ai_validated"] is False  # disabled mode → fallback
    assert snap["ai_layer"]["mode"] == "disabled"
    assert snap["ai_layer"]["fallback_used"] is True
    # Envelope is persisted and inspectable.
    assert "envelope" in snap["ai_layer"]
