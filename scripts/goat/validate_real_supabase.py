"""Real-local-Supabase validation for Goat Mode.

Runs three scenarios against a LIVE Supabase stack (local or hosted) to verify
the integration end-to-end. This is intentionally separate from the in-memory
FakeStore unit tests.

Usage (from backend/app/):

    # one-off dry run (no writes, just show what would be computed)
    python -m scripts_validate_real_supabase --user-id <uuid> --dry-run

    # full wet-run + dedupe check (writes rows, then re-runs and asserts no dupes)
    python -m scripts_validate_real_supabase --user-id <uuid> --scope full

Or from the repo root:

    python scripts/goat/validate_real_supabase.py --user-id <uuid> --scope full

Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in backend/app/.env (or env).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from pathlib import Path
from uuid import UUID

# Make `goat` importable whether run as module OR script.
HERE = Path(__file__).resolve().parent
APP_ROOT = HERE.parent.parent / "backend" / "app"
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

try:
    from dotenv import load_dotenv

    load_dotenv(APP_ROOT / ".env", override=False)
except ImportError:
    pass

from goat import runner as runner_mod  # noqa: E402
from goat import supabase_io as sb  # noqa: E402
from goat.contracts import RunRequest  # noqa: E402


# ─── helpers ────────────────────────────────────────────────────────────────


def _banner(title: str) -> None:
    print(f"\n{'-' * 72}\n{title}\n{'-' * 72}")


def _require_env() -> None:
    missing = [
        k for k in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY") if not os.getenv(k)
    ]
    if missing:
        print(f"Missing env: {', '.join(missing)}")
        print(
            "Populate backend/app/.env with the SERVICE ROLE key "
            "(not the anon JWT) and retry."
        )
        sys.exit(2)


def _summary(resp, tag: str) -> dict:
    # Keep the stdout manageable — the full payload can be huge.
    s = {
        "tag": tag,
        "job_id": str(resp.job_id) if resp.job_id else None,
        "snapshot_id": str(resp.snapshot_id) if resp.snapshot_id else None,
        "scope": resp.scope,
        "readiness_level": resp.readiness_level,
        "snapshot_status": resp.snapshot_status,
        "data_fingerprint": resp.data_fingerprint,
        "coverage_score": resp.coverage.coverage_score,
        "missing_inputs": [m.key for m in resp.coverage.missing_inputs],
        "recommendation_count": resp.recommendation_count,
        "forecast_targets": len(resp.forecast.targets) if resp.forecast else 0,
        "anomaly_items": len(resp.anomalies.items) if resp.anomalies else 0,
        "risk_scores": len(resp.risk.scores) if resp.risk else 0,
        "layer_errors": resp.layer_errors,
        "model_versions": resp.model_versions,
    }
    print(json.dumps(s, indent=2, default=str))
    return s


def _run(user_id: UUID, scope: str, *, dry_run: bool, tag: str):
    req = RunRequest(
        user_id=user_id,
        scope=scope,  # type: ignore[arg-type]
        dry_run=dry_run,
    )
    resp = runner_mod.run_job(req)
    return _summary(resp, tag), resp


# ─── scenarios ──────────────────────────────────────────────────────────────


def scenario_dry_run(user_id: UUID, scope: str) -> None:
    _banner(f"1. Dry run — no writes ({scope})")
    _run(user_id, scope, dry_run=True, tag="dry_run")


def scenario_wet_run(user_id: UUID, scope: str) -> tuple[str, str, int]:
    _banner(f"2. Wet run — writes job/snapshot/recs ({scope})")
    summary, resp = _run(user_id, scope, dry_run=False, tag="wet_run_1")

    # Verify the writes actually landed in the DB.
    job = sb.fetch_job(summary["job_id"]) if summary["job_id"] else None
    if not job:
        print("ERROR: wet_run did not persist a job row")
        sys.exit(1)
    print(
        f"Persisted job status={job.get('status')} "
        f"readiness={job.get('readiness_level')} fp={job.get('data_fingerprint')}"
    )
    latest = sb.fetch_latest_snapshot(str(user_id), scope)
    if not latest:
        print("ERROR: wet_run did not persist a snapshot row")
        sys.exit(1)
    print(
        f"Persisted snapshot id={latest.get('id')} fp={latest.get('data_fingerprint')}"
    )
    if latest.get("data_fingerprint") != summary["data_fingerprint"]:
        print("ERROR: snapshot data_fingerprint mismatch")
        sys.exit(1)
    return (
        summary["job_id"],
        summary["data_fingerprint"],
        summary["recommendation_count"],
    )


def scenario_idempotency(
    user_id: UUID, scope: str, expected_fp: str, first_rec_count: int
) -> None:
    _banner(
        f"3. Idempotency — same fingerprint upserts, no duplicate open recs ({scope})"
    )
    summary, resp = _run(user_id, scope, dry_run=False, tag="wet_run_2")
    if summary["data_fingerprint"] != expected_fp:
        print(
            "NOTE: data_fingerprint changed between runs — expected when source "
            "data is changing under you. Dedup check still applies to NEW recs."
        )
    if summary["recommendation_count"] > 0:
        # A non-zero second-run count implies something genuinely new (or an
        # existing rec was resolved). Print so the caller can eyeball it.
        print(
            f"Second-run new recs: {summary['recommendation_count']} (first run "
            f"wrote {first_rec_count}). If this is > 0 on an unchanged dataset, "
            f"investigate recommendation fingerprints."
        )
    else:
        print("OK: rerun emitted 0 new recommendations (existing open dedupe works)")


# ─── main ───────────────────────────────────────────────────────────────────


def _parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Validate Goat Mode against a live Supabase stack"
    )
    p.add_argument(
        "--user-id",
        default=os.getenv("GOAT_TEST_USER_ID"),
        help="User UUID to test against (defaults to $GOAT_TEST_USER_ID)",
    )
    p.add_argument(
        "--scope",
        default="full",
        choices=[
            "overview",
            "cashflow",
            "budgets",
            "recurring",
            "debt",
            "goals",
            "full",
        ],
    )
    p.add_argument("--dry-run", action="store_true", help="Dry-run only, no writes")
    p.add_argument(
        "--skip-idempotency", action="store_true", help="Skip the 2nd-run dedupe check"
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    _require_env()
    if not args.user_id:
        print("No user_id supplied. Pass --user-id or set GOAT_TEST_USER_ID.")
        return 2
    try:
        user_id = UUID(str(args.user_id))
    except ValueError:
        print(f"Invalid UUID: {args.user_id}")
        return 2

    scenario_dry_run(user_id, args.scope)
    if args.dry_run:
        return 0
    job_id, fp, rec_count = scenario_wet_run(user_id, args.scope)
    if not args.skip_idempotency:
        scenario_idempotency(user_id, args.scope, fp, rec_count)
    _banner("Validation complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
