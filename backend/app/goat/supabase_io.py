"""Trusted server-side Supabase access for Goat Mode compute.

This module is the single place that talks to Supabase. All reads are
user_id-scoped and paginated to handle users with thousands of transactions.
All writes target the Goat Mode v1 tables only.
"""
from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from functools import lru_cache
from typing import TYPE_CHECKING, Any, Iterable

if TYPE_CHECKING:
    from supabase import Client

log = logging.getLogger(__name__)

PAGE_SIZE = 1000


def _utcnow_iso() -> str:
    """Build a PostgREST-safe ISO-8601 timestamp.

    Sending the literal string ``"now()"`` to PostgREST does NOT invoke
    Postgres' ``now()`` function — it's handed to the column cast, which
    rejects the parentheses. Use a real ISO stamp so writes succeed against
    the real stack.
    """
    return datetime.now(timezone.utc).isoformat()


class SupabaseConfigError(RuntimeError):
    pass


@lru_cache(maxsize=1)
def get_client() -> "Client":
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise SupabaseConfigError(
            "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set"
        )
    try:
        from supabase import create_client  # local import keeps tests lightweight
    except ImportError as exc:  # pragma: no cover - production always has it
        raise SupabaseConfigError(
            "supabase package not installed; run pip install -r requirements.txt"
        ) from exc
    return create_client(url, key)


def reset_client_cache() -> None:
    """Used by tests that re-point env vars between cases."""
    get_client.cache_clear()


# ─── Paginated reads ─────────────────────────────────────────────────────────


def _paginate(builder_factory, page_size: int = PAGE_SIZE) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    start = 0
    while True:
        builder = builder_factory().range(start, start + page_size - 1)
        result = builder.execute()
        chunk = result.data or []
        rows.extend(chunk)
        if len(chunk) < page_size:
            break
        start += page_size
    return rows


def _table(client: Client, name: str):
    return client.table(name)


# ─── Read: profiles & setup ──────────────────────────────────────────────────


def fetch_profile(user_id: str, *, client: Client | None = None) -> dict[str, Any] | None:
    c = client or get_client()
    res = (
        _table(c, "profiles")
        .select("id, display_name, preferred_currency, goat_mode, trust_score, updated_at")
        .eq("id", user_id)
        .limit(1)
        .execute()
    )
    return (res.data or [None])[0]


def fetch_goat_user_inputs(user_id: str, *, client: Client | None = None) -> dict[str, Any] | None:
    c = client or get_client()
    res = (
        _table(c, "goat_user_inputs")
        .select("*")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    return (res.data or [None])[0]


def fetch_goat_goals(user_id: str, *, client: Client | None = None) -> list[dict[str, Any]]:
    c = client or get_client()
    return _paginate(
        lambda: _table(c, "goat_goals").select("*").eq("user_id", user_id)
    )


def fetch_goat_obligations(user_id: str, *, client: Client | None = None) -> list[dict[str, Any]]:
    c = client or get_client()
    return _paginate(
        lambda: _table(c, "goat_obligations").select("*").eq("user_id", user_id)
    )


# ─── Read: operational data ──────────────────────────────────────────────────


def fetch_accounts(user_id: str, *, client: Client | None = None) -> list[dict[str, Any]]:
    c = client or get_client()
    return _paginate(
        lambda: _table(c, "accounts").select("*").eq("user_id", user_id)
    )


def fetch_transactions(
    user_id: str,
    *,
    range_start: str | None = None,
    range_end: str | None = None,
    client: Client | None = None,
) -> list[dict[str, Any]]:
    c = client or get_client()

    def builder():
        q = (
            _table(c, "transactions")
            .select(
                "id, user_id, amount, currency, date, type, title, category_id, "
                "payment_method, source_type, status, is_recurring, recurring_series_id, "
                "account_id, counter_account_id, updated_at"
            )
            .eq("user_id", user_id)
            .neq("status", "voided")
            .order("date")
        )
        if range_start:
            q = q.gte("date", range_start)
        if range_end:
            q = q.lte("date", range_end)
        return q

    return _paginate(builder)


def fetch_budgets(user_id: str, *, client: Client | None = None) -> list[dict[str, Any]]:
    c = client or get_client()
    return _paginate(
        lambda: _table(c, "budgets").select("*").eq("user_id", user_id)
    )


def fetch_budget_periods(
    user_id: str,
    *,
    since: str | None = None,
    client: Client | None = None,
) -> list[dict[str, Any]]:
    c = client or get_client()

    def builder():
        q = (
            _table(c, "budget_periods")
            .select("*")
            .eq("user_id", user_id)
            .order("period_start", desc=True)
        )
        if since:
            q = q.gte("period_start", since)
        return q

    return _paginate(builder)


def fetch_recurring_series(user_id: str, *, client: Client | None = None) -> list[dict[str, Any]]:
    c = client or get_client()
    return _paginate(
        lambda: _table(c, "recurring_series").select("*").eq("user_id", user_id)
    )


def fetch_recurring_occurrences(
    user_id: str,
    *,
    since: str | None = None,
    until: str | None = None,
    client: Client | None = None,
) -> list[dict[str, Any]]:
    c = client or get_client()

    def builder():
        q = (
            _table(c, "recurring_occurrences")
            .select("*")
            .eq("user_id", user_id)
            .order("due_date")
        )
        if since:
            q = q.gte("due_date", since)
        if until:
            q = q.lte("due_date", until)
        return q

    return _paginate(builder)


def fetch_lend_borrow_entries(user_id: str, *, client: Client | None = None) -> list[dict[str, Any]]:
    c = client or get_client()
    return _paginate(
        lambda: _table(c, "lend_borrow_entries").select("*").eq("user_id", user_id)
    )


def fetch_statement_imports(user_id: str, *, client: Client | None = None) -> list[dict[str, Any]]:
    c = client or get_client()
    # Table is optional in some envs — swallow not-found errors gracefully.
    try:
        return _paginate(
            lambda: _table(c, "statement_imports").select("*").eq("user_id", user_id)
        )
    except Exception as exc:  # noqa: BLE001
        log.debug("fetch_statement_imports unavailable: %s", exc)
        return []


# ─── Write: goat_mode_* ──────────────────────────────────────────────────────


def create_job(
    *,
    user_id: str,
    scope: str,
    trigger_source: str,
    range_start: str | None,
    range_end: str | None,
    request_payload: dict[str, Any],
    client: Client | None = None,
) -> dict[str, Any]:
    c = client or get_client()
    res = (
        _table(c, "goat_mode_jobs")
        .insert(
            {
                "user_id": user_id,
                "scope": scope,
                "trigger_source": trigger_source,
                "status": "running",
                "range_start": range_start,
                "range_end": range_end,
                "request_payload": request_payload,
                "started_at": _utcnow_iso(),
            }
        )
        .execute()
    )
    return (res.data or [{}])[0]


def update_job(
    job_id: str,
    patch: dict[str, Any],
    *,
    client: Client | None = None,
) -> None:
    patch = {**patch}
    # Accept the legacy "now()" sentinel from old call-sites but rewrite it
    # to a real ISO timestamp before sending it to PostgREST.
    for col in ("finished_at", "started_at"):
        if patch.get(col) == "now()":
            patch[col] = _utcnow_iso()
    c = client or get_client()
    _table(c, "goat_mode_jobs").update(patch).eq("id", job_id).execute()


def insert_job_events(
    events: Iterable[dict[str, Any]],
    *,
    client: Client | None = None,
) -> None:
    events = [e for e in events]
    if not events:
        return
    c = client or get_client()
    _table(c, "goat_mode_job_events").insert(events).execute()


def upsert_snapshot(row: dict[str, Any], *, client: Client | None = None) -> dict[str, Any]:
    """Idempotent on (user_id, scope, data_fingerprint)."""
    c = client or get_client()
    res = (
        _table(c, "goat_mode_snapshots")
        .upsert(row, on_conflict="user_id,scope,data_fingerprint")
        .execute()
    )
    return (res.data or [{}])[0]


def list_open_recommendation_fingerprints(
    user_id: str, *, client: Client | None = None
) -> set[str]:
    c = client or get_client()
    res = (
        _table(c, "goat_mode_recommendations")
        .select("rec_fingerprint")
        .eq("user_id", user_id)
        .eq("status", "open")
        .execute()
    )
    return {r["rec_fingerprint"] for r in (res.data or []) if r.get("rec_fingerprint")}


def insert_recommendations(
    rows: Iterable[dict[str, Any]],
    *,
    client: Client | None = None,
) -> list[dict[str, Any]]:
    rows = list(rows)
    if not rows:
        return []
    c = client or get_client()
    res = _table(c, "goat_mode_recommendations").insert(rows).execute()
    return res.data or []


def fetch_job(job_id: str, *, client: Client | None = None) -> dict[str, Any] | None:
    c = client or get_client()
    res = _table(c, "goat_mode_jobs").select("*").eq("id", job_id).limit(1).execute()
    return (res.data or [None])[0]


def fetch_latest_snapshot(
    user_id: str, scope: str, *, client: Client | None = None
) -> dict[str, Any] | None:
    c = client or get_client()
    res = (
        _table(c, "goat_mode_snapshots")
        .select("*")
        .eq("user_id", user_id)
        .eq("scope", scope)
        .order("generated_at", desc=True)
        .limit(1)
        .execute()
    )
    return (res.data or [None])[0]
