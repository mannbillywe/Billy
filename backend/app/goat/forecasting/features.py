"""Feature builders for the forecasting layer.

All builders operate on a GoatDataBundle + plain dicts — no pandas dependency
at this stage so the stdlib path stays fast and test-friendly.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from typing import Any

from ..data_loader import GoatDataBundle
from ..scoring import to_float

# ─── Helpers ─────────────────────────────────────────────────────────────────


def _parse_date(v: Any) -> date | None:
    if not v:
        return None
    try:
        return date.fromisoformat(str(v)[:10])
    except (ValueError, TypeError):
        return None


def _all_spend_tx(bundle: GoatDataBundle) -> list[dict[str, Any]]:
    """All expense-like transactions across the bundle's history windows."""
    rows = list(bundle.transactions_in_range) + list(bundle.transactions_prior_range)
    return [r for r in rows if r.get("type") in ("expense", "settlement_out")]


def _zero_fill(
    bucket: dict[date, float], start: date | None = None, end: date | None = None
) -> list[tuple[date, float]]:
    if not bucket:
        return []
    s = start or min(bucket.keys())
    e = end or max(bucket.keys())
    out: list[tuple[date, float]] = []
    d = s
    while d <= e:
        out.append((d, round(bucket.get(d, 0.0), 2)))
        d += timedelta(days=1)
    return out


# ─── Daily spend (global) ────────────────────────────────────────────────────


def daily_spend_series(bundle: GoatDataBundle) -> list[tuple[date, float]]:
    """Dense daily expense totals across in-range + prior-range (zero-filled)."""
    by_day: dict[date, float] = defaultdict(float)
    for r in _all_spend_tx(bundle):
        d = _parse_date(r.get("date"))
        if d is None:
            continue
        by_day[d] += to_float(r.get("amount")) or 0.0
    return _zero_fill(by_day)


def daily_category_spend(
    bundle: GoatDataBundle, category_id: str
) -> list[tuple[date, float]]:
    by_day: dict[date, float] = defaultdict(float)
    for r in _all_spend_tx(bundle):
        if r.get("category_id") != category_id:
            continue
        d = _parse_date(r.get("date"))
        if d is None:
            continue
        by_day[d] += to_float(r.get("amount")) or 0.0
    return _zero_fill(by_day)


# ─── Monthly net cashflow ────────────────────────────────────────────────────


def monthly_net_cashflow(bundle: GoatDataBundle) -> list[tuple[str, float]]:
    by_mo: dict[str, float] = defaultdict(float)
    for r in bundle.transactions_in_range + bundle.transactions_prior_range:
        d = str(r.get("date") or "")[:7]
        if not d:
            continue
        amt = to_float(r.get("amount")) or 0.0
        t = r.get("type")
        if t in ("income", "settlement_in", "refund"):
            by_mo[d] += amt
        elif t in ("expense", "settlement_out"):
            by_mo[d] -= amt
    return sorted(by_mo.items())


# ─── Liquid balance + monthly income estimate ────────────────────────────────


def liquid_balance(bundle: GoatDataBundle) -> tuple[float, int]:
    """(liquid_total, liquid_account_count) over active cash-like accounts."""
    total = 0.0
    count = 0
    for a in bundle.accounts:
        if not a.get("is_active", True):
            continue
        if (a.get("type") or "") in ("savings", "checking", "cash"):
            total += to_float(a.get("current_balance")) or 0.0
            count += 1
    return round(total, 2), count


def declared_monthly_income(bundle: GoatDataBundle) -> float | None:
    inputs = bundle.goat_user_inputs or {}
    return to_float(inputs.get("monthly_income"))


def declared_salary_day(bundle: GoatDataBundle) -> int | None:
    inputs = bundle.goat_user_inputs or {}
    try:
        v = inputs.get("salary_day")
        return int(v) if v is not None else None
    except (TypeError, ValueError):
        return None


def observed_monthly_income(bundle: GoatDataBundle) -> float:
    """Fallback when the user hasn't declared monthly income."""
    total = 0.0
    months: set[str] = set()
    for r in bundle.transactions_in_range + bundle.transactions_prior_range:
        if r.get("type") not in ("income", "settlement_in"):
            continue
        total += to_float(r.get("amount")) or 0.0
        key = str(r.get("date") or "")[:7]
        if key:
            months.add(key)
    if not months:
        return 0.0
    return round(total / max(1, len(months)), 2)
