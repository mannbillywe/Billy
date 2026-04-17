"""Shared-secret verification for the Goat Mode backend.

Phase 5 rationale:
-------------------
Cloud Run may run allow-unauthenticated so the Supabase Edge Function can
invoke it over plain HTTPS without needing GCP service-account plumbing. To
prevent unauthenticated strangers from triggering jobs, every privileged
endpoint (``/goat-mode/*``) must carry a shared secret header that is only
known to the Edge Function and the backend.

Behaviour:
    * If ``GOAT_BACKEND_SHARED_SECRET`` is set, the backend requires the
      ``X-Goat-Backend-Secret`` header on protected routes and rejects any
      mismatch or absence with HTTP 401.
    * If the env var is UNSET, the backend behaves as "local-dev mode" — no
      enforcement. Health/CLI/local curl still work. This is the current
      default so existing local tests keep passing.
    * To make the backend fail-closed (recommended for production), set
      ``GOAT_REQUIRE_SHARED_SECRET=1``; the backend will refuse to serve
      protected routes without the secret header, even if the env var is
      missing (returns 503 ``backend_misconfigured``).

Never log the secret value. Only log whether enforcement is enabled.
"""
from __future__ import annotations

import hmac
import logging
import os

from fastapi import Header, HTTPException

log = logging.getLogger(__name__)

SECRET_HEADER = "X-Goat-Backend-Secret"


def _configured_secret() -> str | None:
    raw = os.getenv("GOAT_BACKEND_SHARED_SECRET")
    if raw is None:
        return None
    raw = raw.strip()
    return raw or None


def _enforce_required() -> bool:
    return os.getenv("GOAT_REQUIRE_SHARED_SECRET", "").strip() in {"1", "true", "True"}


def verify_backend_secret(
    x_goat_backend_secret: str | None = Header(default=None, alias=SECRET_HEADER),
) -> None:
    """FastAPI dependency that enforces the Edge Function ↔ backend shared secret.

    The function returns None on success and raises ``HTTPException`` on any
    failure. Apply it to protected route handlers via ``Depends``.
    """
    expected = _configured_secret()
    if expected is None:
        if _enforce_required():
            log.error(
                "goat.auth: GOAT_REQUIRE_SHARED_SECRET=1 but no "
                "GOAT_BACKEND_SHARED_SECRET configured; refusing request."
            )
            raise HTTPException(
                status_code=503,
                detail="backend_misconfigured: shared secret not set",
            )
        return  # local-dev mode

    provided = (x_goat_backend_secret or "").strip()
    if not provided or not hmac.compare_digest(provided, expected):
        log.warning(
            "goat.auth: rejected request — header_present=%s",
            bool(provided),
        )
        raise HTTPException(status_code=401, detail="invalid backend secret")
