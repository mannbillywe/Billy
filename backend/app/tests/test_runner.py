"""End-to-end runner tests against the in-memory fake Supabase.

Exercises the job lifecycle: job row creation, snapshot upsert idempotency,
recommendation inserts, and job events write path.
"""
from __future__ import annotations

from datetime import date, timedelta
from uuid import UUID

import pytest

from goat import runner as runner_mod
from goat import supabase_io as sb
from goat.contracts import RunRequest


USER = "00000000-0000-0000-0000-000000000099"


def _seed(store, *, with_income: bool = False):
    store.tables["profiles"].append(
        {"id": USER, "display_name": "Test", "preferred_currency": "INR", "goat_mode": True}
    )
    if with_income:
        store.tables["goat_user_inputs"].append(
            {
                "user_id": USER,
                "monthly_income": 50000,
                "income_currency": "INR",
                "salary_day": 1,
                "updated_at": "2026-03-01T00:00:00+00:00",
            }
        )
    end = date(2026, 4, 1)
    for i in range(20):
        d = end - timedelta(days=3 * i)
        store.tables["transactions"].append(
            {
                "id": f"tx-{i}",
                "user_id": USER,
                "amount": 400 + i,
                "date": d.isoformat(),
                "type": "expense" if i % 6 else "income",
                "status": "confirmed",
                "updated_at": f"{d.isoformat()}T00:00:00+00:00",
            }
        )


@pytest.fixture
def wired_sb(monkeypatch, fake_client):
    """Point every supabase_io function at the in-memory fake client."""
    monkeypatch.setattr(sb, "get_client", lambda: fake_client)
    return fake_client


def test_dry_run_writes_nothing(wired_sb, fake_store):
    _seed(fake_store)
    req = RunRequest(
        user_id=UUID(USER),
        scope="overview",
        range_start=date(2026, 1, 1),
        range_end=date(2026, 4, 1),
        dry_run=True,
    )
    resp = runner_mod.run_job(req)
    assert resp.dry_run is True
    assert resp.job_id is None
    assert resp.snapshot_id is None
    assert fake_store.tables["goat_mode_jobs"] == []
    assert fake_store.tables["goat_mode_snapshots"] == []
    assert fake_store.tables["goat_mode_recommendations"] == []


def test_wet_run_persists_job_snapshot_and_recs(wired_sb, fake_store):
    _seed(fake_store, with_income=True)
    req = RunRequest(
        user_id=UUID(USER),
        scope="overview",
        range_start=date(2026, 1, 1),
        range_end=date(2026, 4, 1),
        dry_run=False,
    )
    resp = runner_mod.run_job(req)
    assert resp.job_id is not None
    assert resp.snapshot_id is not None
    assert resp.readiness_level in ("L2", "L3")
    jobs = fake_store.tables["goat_mode_jobs"]
    snaps = fake_store.tables["goat_mode_snapshots"]
    assert len(jobs) == 1
    assert len(snaps) == 1
    assert jobs[0]["status"] in ("succeeded", "partial")
    assert jobs[0]["data_fingerprint"] == snaps[0]["data_fingerprint"]


def test_snapshot_is_idempotent_on_same_fingerprint(wired_sb, fake_store):
    _seed(fake_store, with_income=True)
    req = RunRequest(
        user_id=UUID(USER),
        scope="overview",
        range_start=date(2026, 1, 1),
        range_end=date(2026, 4, 1),
        dry_run=False,
    )
    r1 = runner_mod.run_job(req)
    r2 = runner_mod.run_job(req)
    assert r1.data_fingerprint == r2.data_fingerprint
    # Snapshot upserts in-place, so still exactly one row.
    assert len(fake_store.tables["goat_mode_snapshots"]) == 1


def test_open_recs_are_not_duplicated_on_rerun(wired_sb, fake_store):
    _seed(fake_store)  # no income → guaranteed missing_input recs
    req = RunRequest(
        user_id=UUID(USER),
        scope="overview",
        range_start=date(2026, 1, 1),
        range_end=date(2026, 4, 1),
        dry_run=False,
    )
    r1 = runner_mod.run_job(req)
    count_after_first = len(fake_store.tables["goat_mode_recommendations"])
    assert count_after_first >= 1
    r2 = runner_mod.run_job(req)
    # Second run detects existing open fingerprints and emits zero NEW rows.
    assert r2.recommendation_count == 0
    assert len(fake_store.tables["goat_mode_recommendations"]) == count_after_first


def test_job_events_are_written(wired_sb, fake_store):
    _seed(fake_store, with_income=True)
    req = RunRequest(user_id=UUID(USER), scope="overview", dry_run=False)
    runner_mod.run_job(req)
    events = fake_store.tables["goat_mode_job_events"]
    steps = {e["step"] for e in events}
    assert {"dispatch", "input_load", "deterministic", "recommendation", "persist"} <= steps
