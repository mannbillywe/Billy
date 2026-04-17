"""Small shared helpers: safe math, confidence buckets, tolerant coercion."""
from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any, Iterable


def safe_div(num: float | None, denom: float | None) -> float | None:
    try:
        if num is None or denom is None:
            return None
        d = float(denom)
        if d == 0:
            return None
        return float(num) / d
    except (TypeError, ValueError):
        return None


def to_float(value: Any, default: float | None = None) -> float | None:
    if value is None:
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def to_date(value: Any) -> date | None:
    if value is None:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def bucket_confidence(score: float | None) -> str:
    """Map a [0,1] score to Goat's 4 confidence buckets."""
    if score is None:
        return "unknown"
    if score >= 0.85:
        return "high"
    if score >= 0.6:
        return "medium"
    if score >= 0.35:
        return "low"
    return "very_low"


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    if value < lo:
        return lo
    if value > hi:
        return hi
    return value


def max_updated_at(rows: Iterable[dict], key: str = "updated_at") -> str | None:
    """Returns the max ISO timestamp found in rows, or None if rows are empty."""
    best: str | None = None
    for r in rows:
        v = r.get(key) if isinstance(r, dict) else None
        if v is None:
            continue
        s = str(v)
        if best is None or s > best:
            best = s
    return best
