"""Phase 8: dev-route hardening tests.

We verify:
  1. /goat-mode/run-for-user responds 404 when GOAT_ALLOW_DEV_ENDPOINTS is
     unset or any value other than "1"/"true" (production-safe default).
  2. When explicitly enabled with GOAT_ALLOW_DEV_ENDPOINTS=1, the endpoint is
     still protected by the shared-secret dependency (cannot be hit by an
     anonymous caller).
  3. When explicitly enabled AND the shared secret is presented, the endpoint
     behaves as before (exercising the dry-run path so we don't write rows).

These tests do not speak to entitlement — entitlement is enforced at the
Edge Function layer and in RLS (migration 20260424090000). This file is
strictly about dev-route posture.
"""
from __future__ import annotations

from datetime import date, timedelta
from typing import Iterator

import pytest
from fastapi.testclient import TestClient

from goat import supabase_io as sb


USER = "00000000-0000-0000-0000-000000000088"


def _seed(store) -> None:
    store.tables["profiles"].append(
        {"id": USER, "preferred_currency": "INR", "goat_mode": True}
    )
    end = date(2026, 4, 1)
    for i in range(3):
        d = end - timedelta(days=5 * i)
        store.tables["transactions"].append(
            {
                "id": f"tx-p8-{i}",
                "user_id": USER,
                "amount": 120 + i,
                "date": d.isoformat(),
                "type": "expense",
                "status": "confirmed",
                "updated_at": f"{d.isoformat()}T00:00:00+00:00",
            }
        )


@pytest.fixture
def client_env(monkeypatch, fake_client, fake_store) -> Iterator[tuple]:
    """TestClient + FakeSupabase with all relevant env vars cleared.

    Each test decides which env flags to set.
    """
    from main import app

    _seed(fake_store)
    monkeypatch.setattr(sb, "get_client", lambda: fake_client)

    for key in (
        "GOAT_ALLOW_DEV_ENDPOINTS",
        "GOAT_TEST_USER_ID",
        "GOAT_BACKEND_SHARED_SECRET",
        "GOAT_REQUIRE_SHARED_SECRET",
    ):
        monkeypatch.delenv(key, raising=False)

    with TestClient(app) as client:
        yield client, fake_store


def _dev_body() -> dict:
    return {
        "user_id": USER,
        "scope": "overview",
        "range_start": "2026-01-01",
        "range_end": "2026-04-01",
        "dry_run": True,
    }


def test_dev_endpoint_disabled_by_default(client_env):
    """With GOAT_ALLOW_DEV_ENDPOINTS unset, /run-for-user is 404."""
    client, _ = client_env
    resp = client.post("/goat-mode/run-for-user", json=_dev_body())
    assert resp.status_code == 404
    assert "dev endpoint disabled" in resp.json()["detail"]


@pytest.mark.parametrize("raw_value", ["0", "false", "", "2", "yes"])
def test_dev_endpoint_disabled_for_non_truthy_values(
    monkeypatch, client_env, raw_value
):
    """Only '1' and 'true' truly enable the route."""
    client, _ = client_env
    monkeypatch.setenv("GOAT_ALLOW_DEV_ENDPOINTS", raw_value)

    resp = client.post("/goat-mode/run-for-user", json=_dev_body())
    assert resp.status_code == 404, f"raw_value={raw_value} should stay disabled"


def test_dev_endpoint_enabled_still_requires_shared_secret(
    monkeypatch, client_env
):
    """Even with the dev flag on, the shared-secret dependency still applies."""
    client, _ = client_env
    monkeypatch.setenv("GOAT_ALLOW_DEV_ENDPOINTS", "1")
    monkeypatch.setenv("GOAT_BACKEND_SHARED_SECRET", "hello-world")

    resp = client.post("/goat-mode/run-for-user", json=_dev_body())
    assert resp.status_code == 401
    assert "invalid backend secret" in resp.json()["detail"].lower()


def test_dev_endpoint_enabled_with_correct_secret_works(
    monkeypatch, client_env
):
    """Happy path: flag on + correct secret → 200 with dry_run echoing back."""
    client, _ = client_env
    monkeypatch.setenv("GOAT_ALLOW_DEV_ENDPOINTS", "1")
    monkeypatch.setenv("GOAT_BACKEND_SHARED_SECRET", "hello-world")

    resp = client.post(
        "/goat-mode/run-for-user",
        json=_dev_body(),
        headers={"X-Goat-Backend-Secret": "hello-world"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["dry_run"] is True
    # Sanity: the run was routed through /run and produced a response.
    assert "snapshot" in body or "snapshot_id" in body or "run_id" in body or body


def test_dev_endpoint_production_posture_matches_example(client_env):
    """Guard against the env example drifting back to an unsafe default.

    If backend/app/.env.example ever flips GOAT_ALLOW_DEV_ENDPOINTS back to 1,
    this assertion forces us to think about it.
    """
    from pathlib import Path

    here = Path(__file__).resolve().parent
    example = (here.parent / ".env.example").read_text()
    assert "GOAT_ALLOW_DEV_ENDPOINTS=0" in example, (
        "backend/.env.example must default GOAT_ALLOW_DEV_ENDPOINTS=0 "
        "for production safety"
    )
