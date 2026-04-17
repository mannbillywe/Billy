"""Local dev CLI for Goat Mode.

Run from backend/app/ with the Python env that has requirements installed:

    python -m goat.cli run --user-id <uuid> --scope overview --dry-run
    python -m goat.cli run --scope full                       # uses GOAT_TEST_USER_ID

Output is the full RunResponse as JSON on stdout, or written to --out.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from pathlib import Path
from uuid import UUID

try:
    from dotenv import load_dotenv as _raw_load_dotenv

    def load_dotenv() -> None:
        # Force backend/app/.env (the service-role key) to win over any
        # higher-up `.env` a caller might have inherited.
        _raw_load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=False)
except ImportError:  # dotenv is optional for local dev
    def load_dotenv() -> None:  # type: ignore[misc]
        return None

from .contracts import RunRequest, Scope  # noqa: F401 (Scope re-exported for typing)
from .runner import run_job


def _parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(prog="goat.cli", description="Local Goat Mode runner")
    sub = p.add_subparsers(dest="cmd", required=True)

    run_p = sub.add_parser("run", help="Run Goat Mode compute for a user")
    run_p.add_argument("--user-id", dest="user_id", default=os.getenv("GOAT_TEST_USER_ID"))
    run_p.add_argument("--scope", choices=[
        "overview", "cashflow", "budgets", "recurring", "debt", "goals", "full",
    ], default="overview")
    run_p.add_argument("--range-start", dest="range_start", default=None)
    run_p.add_argument("--range-end", dest="range_end", default=None)
    run_p.add_argument("--dry-run", dest="dry_run", action="store_true")
    run_p.add_argument("--out", dest="out", default=None, help="Write JSON response to this file")
    run_p.add_argument("--pretty", action="store_true", help="Pretty-print JSON")
    run_p.add_argument(
        "--print-layer",
        dest="print_layer",
        choices=[
            "forecast",
            "anomaly",
            "risk",
            "coverage",
            "recommendations",
            "ai",
            "ai_envelope",
            "ai_validation",
        ],
        default=None,
        help="Print only the chosen layer from the response (useful for inspection).",
    )
    run_p.add_argument(
        "--ai-mode",
        dest="ai_mode",
        choices=["disabled", "fake", "real"],
        default=None,
        help=(
            "Override GOAT_AI_ENABLED/GOAT_AI_FAKE_MODE for this run. "
            "'disabled' forces fallback, 'fake' uses a deterministic stub, "
            "'real' uses GEMINI_API_KEY."
        ),
    )

    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    load_dotenv()
    args = _parse_args(argv if argv is not None else sys.argv[1:])

    if args.cmd != "run":
        print(f"unknown command: {args.cmd}", file=sys.stderr)
        return 2

    # --ai-mode overrides env flags for this process only.
    if args.ai_mode == "disabled":
        os.environ["GOAT_AI_ENABLED"] = "0"
    elif args.ai_mode == "fake":
        os.environ["GOAT_AI_ENABLED"] = "1"
        os.environ["GOAT_AI_FAKE_MODE"] = "1"
    elif args.ai_mode == "real":
        os.environ["GOAT_AI_ENABLED"] = "1"
        os.environ["GOAT_AI_FAKE_MODE"] = "0"

    if not args.user_id:
        print(
            "No user_id supplied. Pass --user-id <uuid> or set GOAT_TEST_USER_ID.",
            file=sys.stderr,
        )
        return 2

    try:
        uid = UUID(str(args.user_id))
    except ValueError:
        print(f"Invalid user UUID: {args.user_id}", file=sys.stderr)
        return 2

    req = RunRequest(
        user_id=uid,
        scope=args.scope,  # type: ignore[arg-type]
        range_start=date.fromisoformat(args.range_start) if args.range_start else None,
        range_end=date.fromisoformat(args.range_end) if args.range_end else None,
        trigger_source="manual",
        dry_run=bool(args.dry_run),
    )

    resp = run_job(req)
    payload = resp.model_dump(mode="json")

    if args.print_layer:
        ai = payload.get("ai") or {}
        layer_map = {
            "forecast": payload.get("forecast"),
            "anomaly": payload.get("anomalies"),
            "risk": payload.get("risk"),
            "coverage": payload.get("coverage"),
            "recommendations": payload.get("recommendations"),
            "ai": ai,
            "ai_envelope": ai.get("envelope") if isinstance(ai, dict) else None,
            "ai_validation": ai.get("validation") if isinstance(ai, dict) else None,
        }
        payload = layer_map[args.print_layer] or {}

    text = json.dumps(payload, indent=2 if args.pretty else None, default=str)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"wrote {args.out}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
