"""Public entry for the risk layer — orchestrates heuristics + gated model."""
from __future__ import annotations

import logging

from ..contracts import ForecastLayer, RiskLayer, RiskScore, ScopePayload
from ..data_loader import GoatDataBundle
from ..scoring import utcnow_iso
from ..versions import MODEL_VERSIONS
from . import heuristics, model

log = logging.getLogger(__name__)


def run_risk_layer(
    bundle: GoatDataBundle,
    payload: ScopePayload | None = None,
    forecast: ForecastLayer | None = None,
) -> RiskLayer:
    layer = RiskLayer(
        version=MODEL_VERSIONS.get("risk", "0.1.0"),
        generated_at=utcnow_iso(),
        model_enabled=model.is_enabled(),
    )
    scores: list[RiskScore] = []
    scores.extend(heuristics.budget_overrun_heuristic(bundle, forecast))
    scores.extend(heuristics.missed_payment_heuristic(bundle))
    scores.extend(heuristics.liquidity_stress_heuristic(bundle, forecast))
    scores.extend(heuristics.emergency_fund_breach_heuristic(bundle))
    scores.extend(heuristics.goal_shortfall_heuristic(bundle, forecast))

    # Model path: upgrade heuristic budget_overrun scores to calibrated if gated.
    if layer.model_enabled:
        for idx, s in enumerate(scores):
            if s.target != "budget_overrun_risk" or not s.entity_id:
                continue
            out = model.run_calibrated(bundle, s.entity_id)
            if not out:
                continue
            # Replace with a calibrated RiskScore, keeping heuristic detail for audit.
            scores[idx] = RiskScore(
                target=s.target,
                method_used="logreg_calibrated",
                probability=round(out["probability"], 4),
                severity=_sev(out["probability"]),
                confidence=out["confidence"],
                confidence_bucket="high",
                data_sufficient=True,
                calibration_applied=bool(out.get("calibration_applied")),
                reason_codes=[*s.reason_codes, "logreg_calibrated"],
                entity_type=s.entity_type,
                entity_id=s.entity_id,
                features_used=out["features_used"],
                detail={**s.detail, "heuristic_probability": s.probability},
            )
    layer.scores = scores
    return layer


def _sev(p: float) -> str:
    if p >= 0.75:
        return "warn"
    if p >= 0.5:
        return "watch"
    return "info"
