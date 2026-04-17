"""Gated interpretable risk model (LogReg + CalibratedClassifierCV).

v1 is conservative:

  - Requires ``GOAT_RISK_MODEL_ENABLED=1`` env flag (double opt-in).
  - Requires sklearn installed.
  - Requires enough pooled labelled data (≥ 6 completed budget_periods with a
    clear overrun/no-overrun label) before it will emit anything.

Until all three conditions hold, ``run_calibrated`` returns ``None`` and the
caller keeps emitting heuristic-only risk scores.
"""
from __future__ import annotations

import logging
import os
from typing import Any

from ..data_loader import GoatDataBundle
from ..scoring import to_float

log = logging.getLogger(__name__)


def is_enabled() -> bool:
    if os.getenv("GOAT_RISK_MODEL_ENABLED") != "1":
        return False
    try:
        from sklearn.linear_model import LogisticRegression  # noqa: F401

        return True
    except ImportError:
        return False


def _extract_budget_training_set(
    bundle: GoatDataBundle,
) -> tuple[list[list[float]], list[int]]:
    """Return (X, y) for the pooled budget-overrun classifier.

    Features per completed period:
      - pct_spent at period end
      - pace_fraction at (period_end - 7 days)
      - limit (log-scaled)
      - days_in_period
    Label:
      - 1 if spent > 1.0 * limit at period end, else 0
    """
    X: list[list[float]] = []
    y: list[int] = []
    by_budget: dict[str, dict[str, Any]] = {b["id"]: b for b in bundle.budgets}
    for p in bundle.budget_periods:
        bid = p.get("budget_id")
        b = by_budget.get(bid)
        if not b:
            continue
        limit = to_float(b.get("amount"))
        spent = to_float(p.get("spent"))
        if not limit or spent is None:
            continue
        import math
        from datetime import date as _date

        try:
            ps = _date.fromisoformat(str(p["period_start"]))
            pe = _date.fromisoformat(str(p["period_end"]))
        except (ValueError, TypeError, KeyError):
            continue
        today = _date.today()
        if pe >= today:  # still ongoing, skip labelling
            continue
        total_days = max(1, (pe - ps).days + 1)
        X.append(
            [
                spent / limit,
                min(1.0, (total_days - 7) / total_days) if total_days > 7 else 0.9,
                math.log1p(limit),
                float(total_days),
            ]
        )
        y.append(1 if spent > limit else 0)
    return X, y


def run_calibrated(
    bundle: GoatDataBundle, active_budget_id: str
) -> dict[str, Any] | None:
    """Score a single active budget using a calibrated LogReg, if gated on.

    Returns a dict ``{probability, confidence, features_used}`` or ``None`` when
    the gate is closed / data is insufficient.
    """
    if not is_enabled():
        return None
    X, y = _extract_budget_training_set(bundle)
    if len(X) < 6 or len(set(y)) < 2:
        return None
    try:
        from sklearn.calibration import CalibratedClassifierCV
        from sklearn.linear_model import LogisticRegression

        base = LogisticRegression(max_iter=500)
        calibrated = CalibratedClassifierCV(
            base, method="sigmoid", cv=min(3, len(X) // 2 or 2)
        )
        calibrated.fit(X, y)
    except Exception as exc:  # noqa: BLE001
        log.info("Risk model fit failed: %s", exc)
        return None

    b = next((b for b in bundle.budgets if b["id"] == active_budget_id), None)
    if not b:
        return None
    limit = to_float(b.get("amount")) or 0.0
    # Most recent period for this budget.
    latest = None
    for p in bundle.budget_periods:
        if p.get("budget_id") != active_budget_id:
            continue
        if latest is None or str(p.get("period_start")) > str(latest.get("period_start")):
            latest = p
    if not latest or not limit:
        return None
    spent = to_float(latest.get("spent")) or 0.0
    try:
        import math
        from datetime import date as _date

        ps = _date.fromisoformat(str(latest["period_start"]))
        pe = _date.fromisoformat(str(latest["period_end"]))
        total_days = max(1, (pe - ps).days + 1)
        pace_row = [
            spent / limit,
            min(1.0, max(0.0, (_date.today() - ps).days / total_days)),
            math.log1p(limit),
            float(total_days),
        ]
        prob = float(calibrated.predict_proba([pace_row])[0][1])
    except Exception as exc:  # noqa: BLE001
        log.info("Risk scoring failed: %s", exc)
        return None
    return {
        "probability": prob,
        "confidence": 0.75,
        "features_used": [
            "budgets.limit",
            "budget_periods.pace",
            "budget_periods.spent_ratio",
        ],
        "calibration_applied": True,
    }
