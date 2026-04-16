from fastapi import FastAPI
import os

app = FastAPI(title="Billy AI Backend")


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/")
def root():
    return {
        "service": "billy-ai",
        "gemini_key_present": bool(os.getenv("GEMINI_API_KEY")),
        "supabase_url_present": bool(os.getenv("SUPABASE_URL")),
        "supabase_service_role_present": bool(os.getenv("SUPABASE_SERVICE_ROLE_KEY")),
    }
