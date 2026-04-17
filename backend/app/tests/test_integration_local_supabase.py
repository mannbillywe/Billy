"""Real local Supabase stack validation (opt-in).

Skipped unless:
  - ``GOAT_INTEGRATION=1`` env is set, AND
  - ``SUPABASE_URL`` + ``SUPABASE_SERVICE_ROLE_KEY`` are both present, AND
  - ``GOAT_TEST_USER_ID`` points to a real user UUID.

Run locally:

    set GOAT_INTEGRATION=1
    set GOAT_TEST_USER_ID=3d8238ac-...
    pytest -q tests/test_integration_local_supabase.py -s
"""
from __future__ import annotations

import os
from uuid import UUID

import pytest

from goat import runner as runner_mod
from goat import supabase_io as sb
from goat.contracts import RunRequest


def _should_run() -> bool:
    if os.getenv("GOAT_INTEGRATION") != "1":
        return False
    return all(
        os.getenv(k) for k in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "GOAT_TEST_USER_ID")
    )


pytestmark = pytest.mark.skipif(
    not _should_run(),
    reason="Integration test: set GOAT_INTEGRATION=1 + SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY + GOAT_TEST_USER_ID",
)


@pytest.fixture
def user_id() -> UUID:
    return UUID(os.environ["GOAT_TEST_USER_ID"])


def test_dry_run_reads_real_data(user_id):
    req = RunRequest(user_id=user_id, scope="full", dry_run=True)
    resp = runner_mod.run_job(req)
    assert resp.dry_run is True
    assert resp.payload is not None
    assert resp.forecast is not None or "forecast" in resp.layer_errors


def test_wet_run_then_rerun_is_idempotent(user_id):
    req = RunRequest(user_id=user_id, scope="full", dry_run=False)
    r1 = runner_mod.run_job(req)
    r2 = runner_mod.run_job(req)
    # Fingerprint may change if real data moves, but the snapshot upsert
    # should not double-insert for the same fingerprint.
    latest = sb.fetch_latest_snapshot(str(user_id), "full")
    assert latest is not None
    assert latest["data_fingerprint"] in (r1.data_fingerprint, r2.data_fingerprint)
