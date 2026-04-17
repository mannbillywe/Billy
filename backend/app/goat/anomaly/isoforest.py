"""Optional IsolationForest wrapper, guarded import.

Activates only when sklearn is installed AND history has 60+ daily spend
points (otherwise a single outlier dominates and we get noisy alerts).
"""
from __future__ import annotations

import logging
from typing import Sequence

log = logging.getLogger(__name__)


def is_available() -> bool:
    try:
        from sklearn.ensemble import IsolationForest  # noqa: F401

        return True
    except ImportError:
        return False


def score_daily(values: Sequence[float], *, contamination: float = 0.05) -> list[float] | None:
    """Return one anomaly score per observation, or None if sklearn missing."""
    if not is_available() or len(values) < 60:
        return None
    try:
        import numpy as np
        from sklearn.ensemble import IsolationForest

        x = np.asarray(values, dtype=float).reshape(-1, 1)
        model = IsolationForest(
            n_estimators=100,
            contamination=contamination,
            random_state=42,
        )
        model.fit(x)
        # Higher score → more anomalous. Negate so larger is worse.
        raw = -model.score_samples(x)
        return [float(v) for v in raw]
    except Exception as exc:  # noqa: BLE001
        log.info("IsolationForest scoring failed: %s", exc)
        return None
