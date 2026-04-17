"""Glue layer: orchestrate the full job → snapshot → recs lifecycle.

Phase 3: orchestrates deterministic + forecast + anomaly + risk layers with
soft-fail semantics. A broken statistical layer annotates the snapshot rather
than taking the whole run down.

Kept separate from api.py so it can be exercised from tests, the CLI, and
(eventually) an Edge-Function-triggered worker without FastAPI involvement.
"""
from __future__ import annotations

import logging
from datetime import date
from typing import Any
from uuid import UUID

from . import recommendations as rec_engine
from . import supabase_io as sb
from .ai import run_ai_layer
from .anomaly import run_anomaly_layer
from .contracts import (
    AILayer,
    AnomalyLayer,
    CoverageSummary,
    ForecastLayer,
    RecommendationOut,
    RiskLayer,
    RunRequest,
    RunResponse,
    Scope,
    ScopePayload,
)
from .data_loader import GoatDataBundle, load_bundle
from .deterministic import compute_scope
from .fingerprints import data_fingerprint
from .forecasting import run_forecasting_layer
from .missing_inputs import compute_coverage
from .risk import run_risk_layer
from .scoring import utcnow_iso
from .versions import MODEL_VERSIONS

log = logging.getLogger(__name__)


# ─── pure compute (no writes) ───────────────────────────────────────────────


def compute(
    *,
    user_id: str,
    scope: Scope,
    range_start: date | None,
    range_end: date | None,
    client=None,
) -> tuple[GoatDataBundle, ScopePayload, CoverageSummary, str]:
    bundle = load_bundle(
        user_id=user_id,
        scope=scope,
        range_start=range_start,
        range_end=range_end,
        client=client,
    )
    payload = compute_scope(bundle, scope)
    coverage = compute_coverage(bundle, scope)
    fp = data_fingerprint(
        user_id=user_id,
        scope=scope,
        range_start=bundle.range_start.isoformat(),
        range_end=bundle.range_end.isoformat(),
        counts=bundle.counts(),
        stamps=bundle.stamps(),
    )
    return bundle, payload, coverage, fp


def _soft_run(name: str, fn, *args, **kwargs):
    """Invoke a statistical layer; return (result, error_msg).

    Exceptions are caught so one broken layer cannot take the whole job down —
    they surface as a ``layer_errors`` entry on the response + a job_event.
    """
    try:
        return fn(*args, **kwargs), None
    except Exception as exc:  # noqa: BLE001
        log.exception("Goat layer %s failed", name)
        return None, f"{type(exc).__name__}: {str(exc)[:200]}"


# ─── full job lifecycle (reads + writes Supabase) ────────────────────────────


def run_job(req: RunRequest, *, client=None) -> RunResponse:
    user_id = str(req.user_id)
    scope: Scope = req.scope
    job_row: dict[str, Any] = {}
    events: list[dict[str, Any]] = []
    layer_errors: dict[str, str] = {}

    def _event(
        step: str,
        status: str,
        severity: str = "info",
        message: str | None = None,
        detail: dict[str, Any] | None = None,
    ) -> None:
        events.append(
            {
                "user_id": user_id,
                "step": step,
                "status": status,
                "severity": severity,
                "message": message,
                "detail": detail or {},
            }
        )

    # Create job row FIRST so failures still leave a breadcrumb. Skip on dry_run.
    if not req.dry_run:
        try:
            job_row = sb.create_job(
                user_id=user_id,
                scope=scope,
                trigger_source=req.trigger_source,
                range_start=req.range_start.isoformat() if req.range_start else None,
                range_end=req.range_end.isoformat() if req.range_end else None,
                request_payload=req.model_dump(mode="json", exclude={"user_id"}),
                client=client,
            )
        except Exception:  # noqa: BLE001
            log.exception("create_job failed")
            raise

    job_id = job_row.get("id")

    try:
        _event("dispatch", "started")
        _event("input_load", "started")
        bundle, payload, coverage, fp = compute(
            user_id=user_id,
            scope=scope,
            range_start=req.range_start,
            range_end=req.range_end,
            client=client,
        )
        _event("input_load", "finished", detail={"counts": bundle.counts()})

        _event(
            "deterministic",
            "finished",
            detail={"metrics_emitted": len(payload.metrics), "status": payload.status},
        )

        # ─── Statistical layers (soft-fail) ──────────────────────────────────
        _event("forecast", "started")
        forecast_layer: ForecastLayer | None
        forecast_layer, err = _soft_run("forecast", run_forecasting_layer, bundle)
        if err:
            layer_errors["forecast"] = err
            _event("forecast", "error", severity="error", message=err)
        else:
            _event(
                "forecast",
                "finished",
                detail={
                    "targets": len(forecast_layer.targets) if forecast_layer else 0,
                    "models_available": forecast_layer.models_available
                    if forecast_layer
                    else {},
                },
            )

        _event("anomaly", "started")
        anomaly_layer: AnomalyLayer | None
        anomaly_layer, err = _soft_run("anomaly", run_anomaly_layer, bundle, payload)
        if err:
            layer_errors["anomaly"] = err
            _event("anomaly", "error", severity="error", message=err)
        else:
            _event(
                "anomaly",
                "finished",
                detail={
                    "items": len(anomaly_layer.items) if anomaly_layer else 0,
                    "disabled": anomaly_layer.disabled if anomaly_layer else True,
                },
            )

        _event("risk", "started")
        risk_layer: RiskLayer | None
        risk_layer, err = _soft_run(
            "risk", run_risk_layer, bundle, payload, forecast_layer
        )
        if err:
            layer_errors["risk"] = err
            _event("risk", "error", severity="error", message=err)
        else:
            _event(
                "risk",
                "finished",
                detail={
                    "scores": len(risk_layer.scores) if risk_layer else 0,
                    "model_enabled": risk_layer.model_enabled if risk_layer else False,
                },
            )

        # ─── Recommendations ─────────────────────────────────────────────────
        existing_open: set[str] = set()
        if not req.dry_run:
            existing_open = sb.list_open_recommendation_fingerprints(
                user_id, client=client
            )

        _event("recommendation", "started")
        recs: list[RecommendationOut] = rec_engine.generate(
            scope=scope,
            bundle=bundle,
            payload=payload,
            coverage=coverage,
            existing_open_fingerprints=existing_open,
            anomalies=anomaly_layer,
            risk=risk_layer,
            forecast=forecast_layer,
        )
        _event(
            "recommendation",
            "finished",
            detail={
                "new_count": len(recs),
                "existing_open_skipped": len(existing_open),
            },
        )

        # ─── AI layer (soft-fail) ────────────────────────────────────────────
        _event("ai", "started")
        ai_layer: AILayer | None
        ai_layer, err = _soft_run(
            "ai",
            run_ai_layer,
            scope=scope,
            payload=payload,
            coverage=coverage,
            recs=recs,
            forecast=forecast_layer,
            anomalies=anomaly_layer,
            risk=risk_layer,
            layer_errors=layer_errors,
            currency=(bundle.profile or {}).get("preferred_currency")
            if bundle.profile
            else None,
        )
        if err:
            layer_errors["ai"] = err
            _event("ai", "error", severity="error", message=err)
        else:
            _event(
                "ai",
                "finished",
                detail={
                    "mode": ai_layer.mode if ai_layer else "disabled",
                    "ai_validated": ai_layer.ai_validated if ai_layer else False,
                    "fallback_used": ai_layer.fallback_used if ai_layer else True,
                },
            )

        # Snapshot status degrades to "partial" if any NON-ai layer soft-failed.
        # AI fallback alone does not degrade status (that's by design — the
        # deterministic layers are the source of truth).
        snapshot_status = payload.status
        non_ai_errors = {k: v for k, v in layer_errors.items() if k != "ai"}
        if non_ai_errors and snapshot_status == "completed":
            snapshot_status = "partial"

        snapshot_row: dict[str, Any] = {}
        if not req.dry_run:
            _event("persist", "started")
            snapshot_row = sb.upsert_snapshot(
                _snapshot_row(
                    job_id=job_id,
                    user_id=user_id,
                    bundle=bundle,
                    payload=payload,
                    coverage=coverage,
                    fingerprint=fp,
                    recs=recs,
                    forecast=forecast_layer,
                    anomalies=anomaly_layer,
                    risk=risk_layer,
                    ai=ai_layer,
                    snapshot_status=snapshot_status,
                    layer_errors=layer_errors,
                ),
                client=client,
            )
            snap_id = snapshot_row.get("id")
            if recs:
                sb.insert_recommendations(
                    [
                        _rec_row(
                            user_id=user_id,
                            job_id=job_id,
                            snapshot_id=snap_id,
                            rec=r,
                        )
                        for r in recs
                    ],
                    client=client,
                )
            _event(
                "persist",
                "finished",
                detail={"snapshot_id": snap_id, "rec_count": len(recs)},
            )

            sb.update_job(
                job_id,
                {
                    "status": "succeeded"
                    if snapshot_status == "completed"
                    else "partial",
                    "readiness_level": coverage.readiness_level,
                    "data_fingerprint": fp,
                    "model_versions": MODEL_VERSIONS,
                    "finished_at": utcnow_iso(),
                },
                client=client,
            )
            sb.insert_job_events(
                [{"job_id": job_id, **e} for e in events], client=client
            )

        return RunResponse(
            job_id=UUID(job_id) if job_id else None,
            snapshot_id=UUID(snapshot_row["id"]) if snapshot_row.get("id") else None,
            scope=scope,
            readiness_level=coverage.readiness_level,
            snapshot_status=snapshot_status,
            data_fingerprint=fp,
            coverage=coverage,
            payload=payload,
            recommendation_count=len(recs),
            recommendations=recs,
            forecast=forecast_layer,
            anomalies=anomaly_layer,
            risk=risk_layer,
            ai=ai_layer,
            layer_errors=layer_errors,
            dry_run=req.dry_run,
            model_versions=MODEL_VERSIONS,
        )

    except Exception as exc:  # noqa: BLE001
        log.exception("Goat run failed")
        if not req.dry_run and job_id:
            try:
                sb.update_job(
                    job_id,
                    {
                        "status": "failed",
                        "error_message": str(exc)[:500],
                        "finished_at": utcnow_iso(),
                    },
                    client=client,
                )
                sb.insert_job_events(
                    [{"job_id": job_id, **e} for e in events]
                    + [
                        {
                            "job_id": job_id,
                            "user_id": user_id,
                            "step": "teardown",
                            "status": "error",
                            "severity": "error",
                            "message": str(exc)[:500],
                            "detail": {},
                        }
                    ],
                    client=client,
                )
            except Exception:  # noqa: BLE001
                log.exception("Failed to record job failure")
        raise


# ─── row builders ────────────────────────────────────────────────────────────


def _snapshot_row(
    *,
    job_id: str | None,
    user_id: str,
    bundle: GoatDataBundle,
    payload: ScopePayload,
    coverage: CoverageSummary,
    fingerprint: str,
    recs: list[RecommendationOut],
    forecast: ForecastLayer | None,
    anomalies: AnomalyLayer | None,
    risk: RiskLayer | None,
    ai: AILayer | None,
    snapshot_status: str,
    layer_errors: dict[str, str],
) -> dict[str, Any]:
    if ai is not None:
        ai_layer_payload = ai.model_dump(mode="json")
        ai_validated = bool(ai.ai_validated)
    else:
        # AI run itself blew up inside _soft_run — record that in the snapshot.
        ai_layer_payload = {
            "model_versions": MODEL_VERSIONS,
            "mode": "disabled",
            "ai_validated": False,
            "fallback_used": True,
            "reason_codes": ["ai_layer_crashed"],
            "layers": {
                "forecast": "ok" if forecast and "forecast" not in layer_errors else "error_or_disabled",
                "anomaly": "ok" if anomalies and "anomaly" not in layer_errors else "error_or_disabled",
                "risk": "ok" if risk and "risk" not in layer_errors else "error_or_disabled",
            },
        }
        ai_validated = False

    return {
        "job_id": job_id,
        "user_id": user_id,
        "scope": payload.scope,
        "range_start": bundle.range_start.isoformat(),
        "range_end": bundle.range_end.isoformat(),
        "data_fingerprint": fingerprint,
        "snapshot_status": snapshot_status,
        "readiness_level": coverage.readiness_level,
        "confidence_summary": {"overall": payload.confidence},
        "coverage_json": coverage.model_dump(mode="json"),
        "summary_json": {
            "scope": payload.scope,
            "readiness_level": coverage.readiness_level,
            "snapshot_status": snapshot_status,
            "metric_count": len(payload.metrics),
            "layer_errors": layer_errors,
            "generated_at": utcnow_iso(),
        },
        "metrics_json": {"metrics": [m.model_dump(mode="json") for m in payload.metrics]},
        "forecast_json": forecast.model_dump(mode="json") if forecast else {},
        "anomalies_json": anomalies.model_dump(mode="json") if anomalies else {},
        "risk_json": risk.model_dump(mode="json") if risk else {},
        "recommendations_summary_json": {
            "count": len(recs),
            "by_kind": _count_by(recs, "kind"),
            "by_severity": _count_by(recs, "severity"),
        },
        "ai_layer": ai_layer_payload,
        "ai_validated": ai_validated,
    }


def _rec_row(
    *,
    user_id: str,
    job_id: str | None,
    snapshot_id: str | None,
    rec: RecommendationOut,
) -> dict[str, Any]:
    return {
        "user_id": user_id,
        "job_id": job_id,
        "snapshot_id": snapshot_id,
        "recommendation_kind": rec.kind,
        "severity": rec.severity,
        "priority": rec.priority,
        "impact_score": rec.impact_score,
        "effort_score": rec.effort_score,
        "confidence": rec.confidence,
        "rec_fingerprint": rec.rec_fingerprint,
        "entity_type": rec.entity_type,
        "entity_id": rec.entity_id,
        "observation_json": rec.observation,
        "recommendation_json": rec.recommendation,
        "status": "open",
    }


def _count_by(rows: list[RecommendationOut], attr: str) -> dict[str, int]:
    out: dict[str, int] = {}
    for r in rows:
        key = str(getattr(r, attr))
        out[key] = out.get(key, 0) + 1
    return out
