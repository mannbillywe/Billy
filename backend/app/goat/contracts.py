"""Pydantic contracts for the Goat Mode API + internal payloads.

Keep response shapes stable — the Flutter client will bind against these in
Phase 3, and goat_mode_snapshots.*_json columns store a subset of them.
"""
from __future__ import annotations

from datetime import date
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field

# ─── Enums (mirror the schema check constraints verbatim) ───────────────────
Scope = Literal["overview", "cashflow", "budgets", "recurring", "debt", "goals", "full"]
TriggerSource = Literal["manual", "scheduled", "post_event", "system"]
JobStatus = Literal["queued", "running", "succeeded", "partial", "failed", "cancelled"]
SnapshotStatus = Literal["completed", "partial", "failed"]
ReadinessLevel = Literal["L1", "L2", "L3"]
ConfidenceBucket = Literal["unknown", "very_low", "low", "medium", "high"]
RecKind = Literal[
    "budget_overrun",
    "anomaly_review",
    "liquidity_warning",
    "goal_shortfall",
    "missed_payment_risk",
    "recurring_drift",
    "duplicate_cluster",
    "missing_input",
    "uncategorized_cleanup",
    "recovery_iou",
    "other",
]
RecSeverity = Literal["info", "watch", "warn", "critical"]

# Forecasting / anomaly / risk types (Phase 3)
ForecastTargetKey = Literal[
    "end_of_month_liquidity",
    "short_horizon_spend_7d",
    "short_horizon_spend_30d",
    "budget_overrun_trajectory",
    "emergency_fund_depletion_horizon",
    "goal_completion_trajectory",
]
ForecastModel = Literal[
    "seasonal_naive",
    "rolling_median",
    "naive_mean",
    "ets",
    "prophet",
    "heuristic",
    "none",
]
AnomalyKind = Literal[
    "amount_spike_category",
    "recurring_bill_jump",
    "budget_pace_acceleration",
    "low_liquidity_pattern",
    "duplicate_like_pattern",
    "noisy_import_cluster",
    "isolation_outlier",
]
AnomalyMethod = Literal["robust_mad", "residual_check", "isolation_forest", "rule"]
RiskTargetKey = Literal[
    "budget_overrun_risk",
    "missed_payment_risk",
    "short_term_liquidity_stress_risk",
    "emergency_fund_breach_risk",
    "goal_shortfall_risk",
]
RiskMethod = Literal["heuristic", "logreg", "logreg_calibrated", "suppressed"]

# ─── Metrics ────────────────────────────────────────────────────────────────


class Metric(BaseModel):
    """A single deterministic metric with full provenance."""

    key: str
    value: float | int | str | None = None
    unit: str | None = None
    confidence: float | None = Field(default=None, ge=0, le=1)
    confidence_bucket: ConfidenceBucket = "unknown"
    reason_codes: list[str] = Field(default_factory=list)
    inputs_used: list[str] = Field(default_factory=list)
    inputs_missing: list[str] = Field(default_factory=list)
    detail: dict[str, Any] = Field(default_factory=dict)


# ─── Missing inputs / coverage ──────────────────────────────────────────────


class MissingInput(BaseModel):
    key: str
    label: str
    why: str
    unlocks: list[str] = Field(default_factory=list)
    severity: Literal["info", "watch", "warn"] = "info"


class CoverageBreakdown(BaseModel):
    transactions: float = Field(ge=0, le=1)
    accounts: float = Field(ge=0, le=1)
    budgets: float = Field(ge=0, le=1)
    recurring: float = Field(ge=0, le=1)
    income_declared: float = Field(ge=0, le=1)
    goals: float = Field(ge=0, le=1)
    obligations: float = Field(ge=0, le=1)


class CoverageSummary(BaseModel):
    coverage_score: float = Field(ge=0, le=1)
    readiness_level: ReadinessLevel
    breakdown: CoverageBreakdown
    inputs_used: list[str] = Field(default_factory=list)
    missing_inputs: list[MissingInput] = Field(default_factory=list)
    unlockable_scopes: list[Scope] = Field(default_factory=list)


# ─── Scope payloads ─────────────────────────────────────────────────────────


class ScopePayload(BaseModel):
    scope: Scope
    status: SnapshotStatus
    readiness_level: ReadinessLevel
    confidence: ConfidenceBucket
    metrics: list[Metric] = Field(default_factory=list)
    narrative: dict[str, Any] = Field(
        default_factory=dict,
        description="Deterministic narrative slots (NOT Gemini). Filled by recommendations phase.",
    )


# ─── Recommendations ────────────────────────────────────────────────────────


# ─── Forecast layer ─────────────────────────────────────────────────────────


class ForecastPoint(BaseModel):
    step: int
    date: str | None = None
    p10: float | None = None
    p50: float | None = None
    p90: float | None = None


class ForecastSeries(BaseModel):
    horizon_days: int
    unit: str
    points: list[ForecastPoint] = Field(default_factory=list)
    summary: dict[str, Any] = Field(default_factory=dict)


class ForecastTargetOut(BaseModel):
    target: ForecastTargetKey
    status: Literal["ok", "insufficient_history", "skipped", "error"]
    model_used: ForecastModel
    fallback_used: bool = False
    history_length: int
    horizon_days: int
    confidence: float | None = Field(default=None, ge=0, le=1)
    confidence_bucket: ConfidenceBucket = "unknown"
    reason_codes: list[str] = Field(default_factory=list)
    insufficient_data_fields: list[str] = Field(default_factory=list)
    entity_id: str | None = None
    entity_label: str | None = None
    value: dict[str, Any] = Field(default_factory=dict)
    series: ForecastSeries | None = None


class ForecastLayer(BaseModel):
    version: str
    generated_at: str
    disabled: bool = False
    disabled_reason: str | None = None
    models_available: dict[str, bool] = Field(default_factory=dict)
    targets: list[ForecastTargetOut] = Field(default_factory=list)


# ─── Anomaly layer ──────────────────────────────────────────────────────────


class AnomalyItem(BaseModel):
    anomaly_type: AnomalyKind
    method: AnomalyMethod
    severity: RecSeverity = "info"
    score: float | None = None
    confidence: float | None = Field(default=None, ge=0, le=1)
    confidence_bucket: ConfidenceBucket = "unknown"
    reason_codes: list[str] = Field(default_factory=list)
    entity_type: str | None = None
    entity_id: str | None = None
    window_start: str | None = None
    window_end: str | None = None
    baseline: dict[str, Any] = Field(default_factory=dict)
    observation: dict[str, Any] = Field(default_factory=dict)
    explanation: str | None = None


class AnomalyLayer(BaseModel):
    version: str
    generated_at: str
    disabled: bool = False
    disabled_reason: str | None = None
    methods_available: dict[str, bool] = Field(default_factory=dict)
    items: list[AnomalyItem] = Field(default_factory=list)


# ─── Risk layer ─────────────────────────────────────────────────────────────


class RiskScore(BaseModel):
    target: RiskTargetKey
    method_used: RiskMethod
    probability: float | None = Field(default=None, ge=0, le=1)
    severity: RecSeverity = "info"
    confidence: float | None = Field(default=None, ge=0, le=1)
    confidence_bucket: ConfidenceBucket = "unknown"
    data_sufficient: bool = True
    calibration_applied: bool = False
    reason_codes: list[str] = Field(default_factory=list)
    insufficient_data_fields: list[str] = Field(default_factory=list)
    entity_type: str | None = None
    entity_id: str | None = None
    features_used: list[str] = Field(default_factory=list)
    detail: dict[str, Any] = Field(default_factory=dict)


class RiskLayer(BaseModel):
    version: str
    generated_at: str
    disabled: bool = False
    disabled_reason: str | None = None
    model_enabled: bool = False
    scores: list[RiskScore] = Field(default_factory=list)


# ─── AI layer (Phase 4) ─────────────────────────────────────────────────────
# Gemini is restricted to explanation/phrasing. Every field must be grounded
# in the deterministic/statistical bundle — no invented numbers, dates, or
# entities. Validation enforces this before the payload lands on the snapshot.

AIMode = Literal["disabled", "fake", "real"]
AIUrgency = Literal["info", "watch", "warn", "critical"]


class AIPillar(BaseModel):
    """A single observation/inference/recommendation triad grounded in the bundle."""

    pillar: Literal[
        "overview",
        "cashflow",
        "budgets",
        "recurring",
        "debt",
        "goals",
        "forecast",
        "anomaly",
        "risk",
    ]
    observation: str = Field(max_length=400)
    inference: str = Field(max_length=400)
    confidence: ConfidenceBucket = "unknown"
    reason_codes: list[str] = Field(default_factory=list)


class AIRecommendationPhrasing(BaseModel):
    """Gemini-phrased wrapper around an EXISTING deterministic recommendation."""

    rec_fingerprint: str
    title: str = Field(max_length=120)
    body: str = Field(max_length=600)
    why_shown: str = Field(max_length=400)
    urgency_label: AIUrgency = "info"


class AIMissingInputPrompt(BaseModel):
    input_key: str
    title: str = Field(max_length=120)
    body: str = Field(max_length=400)
    unlocks: list[str] = Field(default_factory=list)


class AICoachingNudge(BaseModel):
    topic: str = Field(max_length=80)
    body: str = Field(max_length=400)


class AIFollowUpQuestion(BaseModel):
    question: str = Field(max_length=200)
    pillar: str


class GoatAIEnvelopeOut(BaseModel):
    """The structured-output contract Gemini (or fallback) must produce."""

    narrative_summary: str = Field(max_length=600)
    pillars: list[AIPillar] = Field(default_factory=list)
    recommendation_phrasings: list[AIRecommendationPhrasing] = Field(default_factory=list)
    missing_input_prompts: list[AIMissingInputPrompt] = Field(default_factory=list)
    coaching: list[AICoachingNudge] = Field(default_factory=list)
    follow_up_questions: list[AIFollowUpQuestion] = Field(default_factory=list)


class AIValidationReport(BaseModel):
    passed: bool
    errors: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class AILayer(BaseModel):
    """Persisted AI layer output — written into goat_mode_snapshots.ai_layer."""

    version: str
    generated_at: str
    mode: AIMode
    model: str | None = None
    ai_validated: bool = False
    fallback_used: bool = False
    reason_codes: list[str] = Field(default_factory=list)
    envelope: GoatAIEnvelopeOut
    validation: AIValidationReport
    layer_statuses: dict[str, str] = Field(default_factory=dict)
    model_versions: dict[str, str] = Field(default_factory=dict)


# ─── Recommendations ────────────────────────────────────────────────────────


class RecommendationOut(BaseModel):
    kind: RecKind
    severity: RecSeverity
    priority: int = Field(ge=0, le=100)
    impact_score: float | None = Field(default=None, ge=0, le=1)
    effort_score: float | None = Field(default=None, ge=0, le=1)
    confidence: float | None = Field(default=None, ge=0, le=1)
    rec_fingerprint: str
    entity_type: str | None = None
    # entity_id is a free-form string in the Python model (DB column is uuid);
    # the runner casts real UUIDs back at persistence time.
    entity_id: str | None = None
    observation: dict[str, Any] = Field(default_factory=dict)
    recommendation: dict[str, Any] = Field(default_factory=dict)


# ─── Job / snapshot wire shapes ─────────────────────────────────────────────


class RunRequest(BaseModel):
    user_id: UUID
    scope: Scope = "overview"
    range_start: date | None = None
    range_end: date | None = None
    trigger_source: TriggerSource = "manual"
    dry_run: bool = False


class RunForUserRequest(BaseModel):
    """Dev-only convenience: defaults user_id to GOAT_TEST_USER_ID."""

    user_id: UUID | None = None
    scope: Scope = "overview"
    range_start: date | None = None
    range_end: date | None = None
    dry_run: bool = True  # safer default on the dev endpoint


class RunResponse(BaseModel):
    job_id: UUID | None = None
    snapshot_id: UUID | None = None
    scope: Scope
    readiness_level: ReadinessLevel
    snapshot_status: SnapshotStatus
    data_fingerprint: str
    coverage: CoverageSummary
    payload: ScopePayload
    recommendation_count: int
    recommendations: list[RecommendationOut] = Field(default_factory=list)
    forecast: ForecastLayer | None = None
    anomalies: AnomalyLayer | None = None
    risk: RiskLayer | None = None
    ai: AILayer | None = None
    layer_errors: dict[str, str] = Field(
        default_factory=dict,
        description="Per-layer soft-fail messages ({layer_name: short_message}).",
    )
    dry_run: bool = False
    model_versions: dict[str, str] = Field(default_factory=dict)


class JobSummary(BaseModel):
    id: UUID
    user_id: UUID
    scope: Scope
    status: JobStatus
    readiness_level: ReadinessLevel | None = None
    data_fingerprint: str | None = None
    error_message: str | None = None
    started_at: str | None = None
    finished_at: str | None = None
    created_at: str


class SnapshotOut(BaseModel):
    id: UUID
    user_id: UUID
    scope: Scope
    readiness_level: ReadinessLevel
    snapshot_status: SnapshotStatus
    data_fingerprint: str
    generated_at: str
    coverage_json: dict[str, Any]
    summary_json: dict[str, Any]
    metrics_json: dict[str, Any]
    forecast_json: dict[str, Any]
    anomalies_json: dict[str, Any]
    risk_json: dict[str, Any]
    recommendations_summary_json: dict[str, Any]
    ai_layer: dict[str, Any]
