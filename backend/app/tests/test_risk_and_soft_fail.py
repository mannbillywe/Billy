"""Tests for the risk layer + soft-fail orchestration in the runner."""
from __future__ import annotations

from datetime import date, timedelta
from uuid import UUID

import pytest

from goat import runner as runner_mod
from goat import supabase_io as sb
from goat.contracts import RunRequest
from goat.data_loader import GoatDataBundle
from goat.risk import run_risk_layer


# ─── Helpers ─────────────────────────────────────────────────────────────────


def _base_bundle_with_budget(spent: float, limit: float, pace: float) -> GoatDataBundle:
    """Build a bundle where current pace implies configurable overrun risk."""
    end = date.today()
    start = end - timedelta(days=60)
    period_start = end - timedelta(days=int(30 * pace))
    period_end = period_start + timedelta(days=30)
    return GoatDataBundle(
        user_id="u1",
        scope="budgets",
        range_start=start,
        range_end=end,
        budgets=[{"id": "b1", "name": "Food", "amount": limit, "is_active": True}],
        budget_periods=[
            {
                "id": "p1",
                "budget_id": "b1",
                "period_start": period_start.isoformat(),
                "period_end": period_end.isoformat(),
                "spent": spent,
            }
        ],
        recurring_occurrences=[],
    )


# ─── Heuristic behaviour ────────────────────────────────────────────────────


def test_budget_overrun_heuristic_high_when_ahead_of_pace():
    b = _base_bundle_with_budget(spent=900, limit=1000, pace=0.5)  # 90% at halfway
    layer = run_risk_layer(b, forecast=None)
    overrun = [s for s in layer.scores if s.target == "budget_overrun_risk"]
    assert overrun and overrun[0].probability is not None
    assert overrun[0].probability >= 0.75


def test_budget_overrun_heuristic_low_when_on_pace():
    b = _base_bundle_with_budget(spent=500, limit=1000, pace=0.5)  # 50% at halfway
    layer = run_risk_layer(b, forecast=None)
    overrun = [s for s in layer.scores if s.target == "budget_overrun_risk"]
    assert overrun[0].probability is not None
    assert overrun[0].probability < 0.5


def test_missed_payment_suppressed_on_empty_history():
    b = _base_bundle_with_budget(spent=100, limit=1000, pace=0.1)
    layer = run_risk_layer(b)
    mp = [s for s in layer.scores if s.target == "missed_payment_risk"]
    assert mp and mp[0].data_sufficient is False
    assert mp[0].probability is None


def test_emergency_fund_breach_needs_declared_target():
    b = _base_bundle_with_budget(spent=100, limit=1000, pace=0.1)
    layer = run_risk_layer(b)
    ef = [s for s in layer.scores if s.target == "emergency_fund_breach_risk"]
    assert ef and ef[0].data_sufficient is False
    assert "goat_user_inputs.emergency_fund_target_months" in ef[0].insufficient_data_fields


def test_risk_model_gate_closed_by_default():
    # No env flag, no sklearn fit → heuristic only.
    b = _base_bundle_with_budget(spent=900, limit=1000, pace=0.5)
    layer = run_risk_layer(b)
    assert layer.model_enabled is False
    for s in layer.scores:
        assert s.method_used in ("heuristic", "suppressed")


# ─── Runner soft-fail ───────────────────────────────────────────────────────


USER = "00000000-0000-0000-0000-0000000000aa"


def _seed_minimal(store):
    store.tables["profiles"].append(
        {"id": USER, "display_name": "Test", "preferred_currency": "INR"}
    )
    end = date(2026, 4, 1)
    for i in range(15):
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


def test_runner_emits_forecast_anomaly_risk_layers(wired, fake_store):
    _seed_minimal(fake_store)
    req = RunRequest(user_id=UUID(USER), scope="full", dry_run=True)
    resp = runner_mod.run_job(req)
    assert resp.forecast is not None
    assert resp.anomalies is not None
    assert resp.risk is not None
    # versions stamp the layer value so snapshot downstream can audit.
    assert resp.model_versions["forecast"] == "0.1.0"


def test_runner_soft_fail_does_not_crash(monkeypatch, wired, fake_store):
    _seed_minimal(fake_store)

    # Force the anomaly layer to blow up mid-run.
    def _boom(*_args, **_kwargs):
        raise RuntimeError("synthetic anomaly failure")

    monkeypatch.setattr(runner_mod, "run_anomaly_layer", _boom)
    req = RunRequest(user_id=UUID(USER), scope="full", dry_run=True)
    resp = runner_mod.run_job(req)
    assert resp.anomalies is None
    assert "anomaly" in resp.layer_errors
    # Other layers still ran.
    assert resp.forecast is not None
    assert resp.risk is not None
    # Snapshot status must degrade to partial.
    assert resp.snapshot_status == "partial"


def test_wet_run_persists_layered_snapshot(wired, fake_store):
    _seed_minimal(fake_store)
    req = RunRequest(user_id=UUID(USER), scope="full", dry_run=False)
    resp = runner_mod.run_job(req)
    snaps = fake_store.tables["goat_mode_snapshots"]
    assert len(snaps) == 1
    snap = snaps[0]
    # Each layer must be persisted (possibly as empty dict) into its own column.
    assert "targets" in snap["forecast_json"]
    assert "items" in snap["anomalies_json"] or snap["anomalies_json"].get("disabled")
    assert "scores" in snap["risk_json"]
    # Phase 4 replaces the lightweight "ai_layer.layers" stub with the full
    # AILayer dump. Layer statuses now live under layer_statuses.
    assert snap["ai_layer"]["layer_statuses"]["forecast"] == "ok"
