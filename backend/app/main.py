"""Billy AI backend entrypoint."""
from __future__ import annotations

import os
from pathlib import Path

try:
    from dotenv import load_dotenv

    # Explicit path so we never accidentally inherit the repo-root `.env`
    # (which carries the Flutter anon key, NOT the service-role JWT).
    _here = Path(__file__).resolve().parent
    load_dotenv(_here / ".env", override=False)
except ImportError:  # dotenv is optional; env vars can come from the runtime
    pass

from fastapi import FastAPI

from goat.api import router as goat_router

app = FastAPI(title="Billy AI Backend")
app.include_router(goat_router)


@app.get("/health")
def health() -> dict[str, object]:
    return {
        "ok": True,
        "goat_mode": True,
        "supabase_url_present": bool(os.getenv("SUPABASE_URL")),
        "supabase_service_role_present": bool(os.getenv("SUPABASE_SERVICE_ROLE_KEY")),
        "goat_dev_endpoints_enabled": os.getenv("GOAT_ALLOW_DEV_ENDPOINTS") == "1",
        "shared_secret_enforced": bool(
            (os.getenv("GOAT_BACKEND_SHARED_SECRET") or "").strip()
        ),
        "shared_secret_required": os.getenv("GOAT_REQUIRE_SHARED_SECRET", "").strip()
        in {"1", "true", "True"},
        "ai_enabled": os.getenv("GOAT_AI_ENABLED", "0").strip() in {"1", "true", "True"},
    }


@app.get("/")
def root() -> dict[str, object]:
    return {
        "service": "billy-ai",
        "gemini_key_present": bool(os.getenv("GEMINI_API_KEY")),
        "supabase_url_present": bool(os.getenv("SUPABASE_URL")),
        "supabase_service_role_present": bool(os.getenv("SUPABASE_SERVICE_ROLE_KEY")),
    }
