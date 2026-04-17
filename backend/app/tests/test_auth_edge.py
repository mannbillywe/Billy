"""Phase 5: backend shared-secret enforcement tests.

We use FastAPI's TestClient so we exercise the real dependency chain
(``Depends(verify_backend_secret)``) rather than calling ``run_job`` directly.
The supabase_io client is still fake — we never hit real Supabase.
"""
from __future__ import annotations

import os
from datetime import date, timedelta
from typing import Iterator
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from goat import supabase_io as sb


USER = "00000000-0000-0000-0000-000000000055"


def _seed_store(store) -> None:
    store.tables["profiles"].append(
        {"id": USER, "preferred_currency": "INR", "goat_mode": True}
    )
    end = date(2026, 4, 1)
    for i in range(6):
        d = end - timedelta(days=5 * i)
        store.tables["transactions"].append(
            {
                "id": f"tx-secret-{i}",
                "user_id": USER,
                "amount": 350 + i * 10,
                "date": d.isoformat(),
                "type": "expense",
                "status": "confirmed",
                "updated_at": f"{d.isoformat()}T00:00:00+00:00",
            }
        )


@pytest.fixture
def client_with_fake_sb(monkeypatch, fake_client, fake_store) -> Iterator[tuple]:
    """A FastAPI TestClient backed by our in-memory fake Supabase store.

    Also clears shared-secret env vars between tests so each test controls
    its own enforcement mode.
    """
    from main import app

    _seed_store(fake_store)
    monkeypatch.setattr(sb, "get_client", lambda: fake_client)

    for key in (
        "GOAT_BACKEND_SHARED_SECRET",
        "GOAT_REQUIRE_SHARED_SECRET",
    ):
        monkeypatch.delenv(key, raising=False)

    with TestClient(app) as client:
        yield client, fake_store


def _valid_body(dry_run: bool = True) -> dict:
    return {
        "user_id": USER,
        "scope": "overview",
        "range_start": "2026-01-01",
        "range_end": "2026-04-01",
        "dry_run": dry_run,
    }


def test_no_secret_configured_allows_request(client_with_fake_sb):
    client, _ = client_with_fake_sb
    resp = client.post("/goat-mode/run", json=_valid_body())
    assert resp.status_code == 200, resp.text
    assert resp.json()["dry_run"] is True


def test_secret_configured_requires_header(monkeypatch, client_with_fake_sb):
    client, _ = client_with_fake_sb
    monkeypatch.setenv("GOAT_BACKEND_SHARED_SECRET", "shhh-42")

    resp = client.post("/goat-mode/run", json=_valid_body())
    assert resp.status_code == 401
    assert "invalid backend secret" in resp.json()["detail"].lower()


def test_secret_wrong_value_rejected(monkeypatch, client_with_fake_sb):
    client, _ = client_with_fake_sb
    monkeypatch.setenv("GOAT_BACKEND_SHARED_SECRET", "shhh-42")

    resp = client.post(
        "/goat-mode/run",
        json=_valid_body(),
        headers={"X-Goat-Backend-Secret": "wrong"},
    )
    assert resp.status_code == 401


def test_secret_right_value_accepted(monkeypatch, client_with_fake_sb):
    client, _ = client_with_fake_sb
    monkeypatch.setenv("GOAT_BACKEND_SHARED_SECRET", "shhh-42")

    resp = client.post(
        "/goat-mode/run",
        json=_valid_body(),
        headers={"X-Goat-Backend-Secret": "shhh-42"},
    )
    assert resp.status_code == 200, resp.text


def test_fail_closed_when_required_but_unset(monkeypatch, client_with_fake_sb):
    """GOAT_REQUIRE_SHARED_SECRET=1 + missing secret → 503 backend_misconfigured."""
    client, _ = client_with_fake_sb
    monkeypatch.setenv("GOAT_REQUIRE_SHARED_SECRET", "1")

    resp = client.post("/goat-mode/run", json=_valid_body())
    assert resp.status_code == 503
    assert "backend_misconfigured" in resp.json()["detail"].lower()


def test_health_is_unprotected(client_with_fake_sb, monkeypatch):
    """Cloud Run health probe must work without the secret header."""
    client, _ = client_with_fake_sb
    monkeypatch.setenv("GOAT_BACKEND_SHARED_SECRET", "shhh-42")

    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["shared_secret_enforced"] is True


def test_jobs_endpoint_also_requires_secret(monkeypatch, client_with_fake_sb):
    client, store = client_with_fake_sb
    monkeypatch.setenv("GOAT_BACKEND_SHARED_SECRET", "shhh-42")
    # Seed a fake job to fetch.
    job_id = "11111111-2222-3333-4444-555555555555"
    store.tables["goat_mode_jobs"].append(
        {
            "id": job_id,
            "user_id": USER,
            "status": "succeeded",
            "scope": "overview",
            "trigger_source": "manual",
            "created_at": "2026-04-10T00:00:00+00:00",
            "started_at": "2026-04-10T00:00:00+00:00",
            "finished_at": "2026-04-10T00:00:01+00:00",
            "data_fingerprint": "abc",
            "error_code": None,
            "error_message": None,
        }
    )

    r_nohdr = client.get(f"/goat-mode/jobs/{job_id}")
    assert r_nohdr.status_code == 401

    r_ok = client.get(
        f"/goat-mode/jobs/{job_id}",
        headers={"X-Goat-Backend-Secret": "shhh-42"},
    )
    assert r_ok.status_code == 200, r_ok.text
