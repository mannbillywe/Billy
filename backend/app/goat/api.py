"""FastAPI router for Goat Mode.

Mounted by main.py as `app.include_router(goat.api.router)`. Route handlers
are intentionally thin — all business logic lives in runner.py and the
deterministic/recommendations modules.
"""
from __future__ import annotations

import logging
import os
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from . import supabase_io as sb
from .auth import verify_backend_secret
from .contracts import (
    JobSummary,
    RunForUserRequest,
    RunRequest,
    RunResponse,
    Scope,
    SnapshotOut,
)
from .runner import run_job

log = logging.getLogger(__name__)

router = APIRouter(prefix="/goat-mode", tags=["goat-mode"])


def _dev_endpoints_enabled() -> bool:
    """Truthy only for explicit opt-in. Defaults to disabled — production safe."""
    raw = os.getenv("GOAT_ALLOW_DEV_ENDPOINTS", "").strip()
    return raw in {"1", "true", "True"}


@router.post(
    "/run",
    response_model=RunResponse,
    dependencies=[Depends(verify_backend_secret)],
)
def run(req: RunRequest) -> RunResponse:
    """Create a job, compute, persist, and return the full response.

    Pass dry_run=true to skip all writes and just inspect the computed payload.
    """
    try:
        return run_job(req)
    except sb.SupabaseConfigError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@router.post(
    "/run-for-user",
    response_model=RunResponse,
    dependencies=[Depends(verify_backend_secret)],
)
def run_for_user(req: RunForUserRequest) -> RunResponse:
    """Dev-only convenience: uses GOAT_TEST_USER_ID if user_id is omitted.

    Guarded by env var GOAT_ALLOW_DEV_ENDPOINTS=1 so this cannot accidentally
    be hit in a deployed Cloud Run environment. Production deployments must
    leave GOAT_ALLOW_DEV_ENDPOINTS unset (or 0).

    Security invariants:
      - Protected by the shared-secret dependency (same as /run) so unknown
        callers still can't reach it even when the flag is on.
      - Additionally bypasses entitlement checks by intent — any operator
        using this MUST ensure the target user_id is already entitled.
    """
    if not _dev_endpoints_enabled():
        # Return 404 (not 403) to avoid advertising the route's existence.
        raise HTTPException(status_code=404, detail="dev endpoint disabled")

    # Log on every dev-endpoint hit so accidental prod enablement is visible.
    log.warning(
        "goat.api: /run-for-user invoked (dev-only endpoint) user=%s dry_run=%s",
        req.user_id,
        req.dry_run,
    )

    user_id = req.user_id
    if user_id is None:
        fallback = os.getenv("GOAT_TEST_USER_ID")
        if not fallback:
            raise HTTPException(
                status_code=400,
                detail="user_id is required (or set GOAT_TEST_USER_ID)",
            )
        try:
            user_id = UUID(fallback)
        except ValueError as exc:
            raise HTTPException(
                status_code=400, detail=f"Invalid GOAT_TEST_USER_ID: {fallback}"
            ) from exc

    full_req = RunRequest(
        user_id=user_id,
        scope=req.scope,
        range_start=req.range_start,
        range_end=req.range_end,
        trigger_source="manual",
        dry_run=req.dry_run,
    )
    return run(full_req)


@router.get(
    "/jobs/{job_id}",
    response_model=JobSummary,
    dependencies=[Depends(verify_backend_secret)],
)
def get_job(job_id: UUID) -> JobSummary:
    row = sb.fetch_job(str(job_id))
    if not row:
        raise HTTPException(status_code=404, detail="job not found")
    return JobSummary(**row)


@router.get(
    "/latest/{user_id}",
    response_model=SnapshotOut,
    dependencies=[Depends(verify_backend_secret)],
)
def latest(user_id: UUID, scope: Scope = Query(default="overview")) -> SnapshotOut:
    row = sb.fetch_latest_snapshot(str(user_id), scope)
    if not row:
        raise HTTPException(status_code=404, detail="no snapshot found")
    return SnapshotOut(**row)
