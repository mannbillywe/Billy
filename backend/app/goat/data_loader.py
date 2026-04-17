"""Load every Billy + Goat row needed for a compute run into one typed bundle.

Keeps the rest of the compute pipeline independent of Supabase so deterministic
code and tests stay pure-Python with plain dicts.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any

from . import supabase_io as sb
from .scoring import max_updated_at


@dataclass
class GoatDataBundle:
    user_id: str
    scope: str
    range_start: date
    range_end: date

    profile: dict[str, Any] | None = None
    goat_user_inputs: dict[str, Any] | None = None
    goat_goals: list[dict[str, Any]] = field(default_factory=list)
    goat_obligations: list[dict[str, Any]] = field(default_factory=list)

    accounts: list[dict[str, Any]] = field(default_factory=list)
    transactions_in_range: list[dict[str, Any]] = field(default_factory=list)
    transactions_prior_range: list[dict[str, Any]] = field(default_factory=list)
    budgets: list[dict[str, Any]] = field(default_factory=list)
    budget_periods: list[dict[str, Any]] = field(default_factory=list)
    recurring_series: list[dict[str, Any]] = field(default_factory=list)
    recurring_occurrences: list[dict[str, Any]] = field(default_factory=list)
    lend_borrow_entries: list[dict[str, Any]] = field(default_factory=list)
    statement_imports: list[dict[str, Any]] = field(default_factory=list)

    # ─── derived helpers used by fingerprints.py ─────────────────────────────
    def counts(self) -> dict[str, int]:
        return {
            "tx_in": len(self.transactions_in_range),
            "tx_prev": len(self.transactions_prior_range),
            "accounts": len(self.accounts),
            "budgets": len(self.budgets),
            "budget_periods": len(self.budget_periods),
            "recurring_series": len(self.recurring_series),
            "recurring_occ": len(self.recurring_occurrences),
            "lend_borrow": len(self.lend_borrow_entries),
            "goals": len(self.goat_goals),
            "obligations": len(self.goat_obligations),
            "goat_inputs": 1 if self.goat_user_inputs else 0,
            "statement_imports": len(self.statement_imports),
        }

    def stamps(self) -> dict[str, str | None]:
        return {
            "tx": max_updated_at(self.transactions_in_range),
            "ac": max_updated_at(self.accounts),
            "bd": max_updated_at(self.budgets),
            "bp": max_updated_at(self.budget_periods),
            "rs": max_updated_at(self.recurring_series),
            "gi": (self.goat_user_inputs or {}).get("updated_at") if self.goat_user_inputs else None,
            "gg": max_updated_at(self.goat_goals),
            "go": max_updated_at(self.goat_obligations),
        }


def _resolve_range(
    range_start: date | None, range_end: date | None
) -> tuple[date, date]:
    end = range_end or date.today()
    start = range_start or (end - timedelta(days=90))
    if start > end:
        start, end = end, start
    return start, end


def load_bundle(
    *,
    user_id: str,
    scope: str,
    range_start: date | None = None,
    range_end: date | None = None,
    client=None,
) -> GoatDataBundle:
    start, end = _resolve_range(range_start, range_end)
    prev_end = start - timedelta(days=1)
    prev_start = prev_end - (end - start)

    return GoatDataBundle(
        user_id=user_id,
        scope=scope,
        range_start=start,
        range_end=end,
        profile=sb.fetch_profile(user_id, client=client),
        goat_user_inputs=sb.fetch_goat_user_inputs(user_id, client=client),
        goat_goals=sb.fetch_goat_goals(user_id, client=client),
        goat_obligations=sb.fetch_goat_obligations(user_id, client=client),
        accounts=sb.fetch_accounts(user_id, client=client),
        transactions_in_range=sb.fetch_transactions(
            user_id,
            range_start=start.isoformat(),
            range_end=end.isoformat(),
            client=client,
        ),
        transactions_prior_range=sb.fetch_transactions(
            user_id,
            range_start=prev_start.isoformat(),
            range_end=prev_end.isoformat(),
            client=client,
        ),
        budgets=sb.fetch_budgets(user_id, client=client),
        budget_periods=sb.fetch_budget_periods(
            user_id, since=(start - timedelta(days=60)).isoformat(), client=client
        ),
        recurring_series=sb.fetch_recurring_series(user_id, client=client),
        recurring_occurrences=sb.fetch_recurring_occurrences(
            user_id,
            since=start.isoformat(),
            until=(end + timedelta(days=45)).isoformat(),
            client=client,
        ),
        lend_borrow_entries=sb.fetch_lend_borrow_entries(user_id, client=client),
        statement_imports=sb.fetch_statement_imports(user_id, client=client),
    )
