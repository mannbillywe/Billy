"""Missing-input detection + readiness classification.

Principles:
- inspect existing Billy operational tables FIRST; only then Goat declarations
- never demand a field Billy can derive from operational data
- always be able to produce SOMETHING (L1) if there is any transaction at all
- emit structured MissingInput rows so the UI can show "ask only what's missing"

Readiness tiers follow GOAT_MODE_ANALYTICS_ARCHITECTURE.md:
  L1 — operational data only (transactions / accounts if any)
  L2 — + declared goat_user_inputs (income, salary_day, emergency-fund target)
  L3 — + richer operational signal (budgets / recurring / accounts / statements)
"""
from __future__ import annotations

from typing import Any

from .contracts import (
    CoverageBreakdown,
    CoverageSummary,
    MissingInput,
    ReadinessLevel,
    Scope,
)
from .data_loader import GoatDataBundle
from .scoring import clamp, to_float


# ─── tiny helpers ────────────────────────────────────────────────────────────


def _has_any_tx(bundle: GoatDataBundle) -> bool:
    return bool(bundle.transactions_in_range or bundle.transactions_prior_range)


def _declared_income(bundle: GoatDataBundle) -> float | None:
    inputs = bundle.goat_user_inputs or {}
    return to_float(inputs.get("monthly_income"))


def _declared_salary_day(bundle: GoatDataBundle) -> int | None:
    inputs = bundle.goat_user_inputs or {}
    v = inputs.get("salary_day")
    try:
        return int(v) if v is not None else None
    except (TypeError, ValueError):
        return None


def _declared_ef_target(bundle: GoatDataBundle) -> float | None:
    inputs = bundle.goat_user_inputs or {}
    return to_float(inputs.get("emergency_fund_target_months"))


# ─── coverage pillars (each 0..1) ────────────────────────────────────────────


def _pillar_transactions(bundle: GoatDataBundle) -> float:
    n = len(bundle.transactions_in_range) + len(bundle.transactions_prior_range)
    # Saturates at 60 transactions over 6 months — enough to do deterministic work.
    return clamp(n / 60.0)


def _pillar_accounts(bundle: GoatDataBundle) -> float:
    active = [a for a in bundle.accounts if a.get("is_active", True)]
    if not active:
        return 0.0
    # Saturates at 2 active accounts (bank + card covers most users).
    return clamp(len(active) / 2.0)


def _pillar_budgets(bundle: GoatDataBundle) -> float:
    active = [b for b in bundle.budgets if b.get("is_active", True)]
    if not active:
        return 0.0
    return clamp(len(active) / 3.0)


def _pillar_recurring(bundle: GoatDataBundle) -> float:
    active = [s for s in bundle.recurring_series if s.get("is_active", True)]
    if not active:
        return 0.0
    return clamp(len(active) / 3.0)


def _pillar_income_declared(bundle: GoatDataBundle) -> float:
    inc = _declared_income(bundle)
    sal = _declared_salary_day(bundle)
    if inc is None and sal is None:
        return 0.0
    if inc is None or sal is None:
        return 0.4
    return 1.0


def _pillar_goals(bundle: GoatDataBundle) -> float:
    active = [g for g in bundle.goat_goals if g.get("status") == "active"]
    return 1.0 if active else 0.0


def _pillar_obligations(bundle: GoatDataBundle) -> float:
    active = [o for o in bundle.goat_obligations if o.get("status") == "active"]
    # Not having obligations is valid → treat as full coverage unless there is
    # lend_borrow or EMI-looking recurring without a matching obligation row.
    if active:
        return 1.0
    pending_lb = [
        e for e in bundle.lend_borrow_entries if e.get("status") == "pending"
    ]
    return 0.5 if pending_lb else 0.8


# ─── public API ──────────────────────────────────────────────────────────────


PILLAR_WEIGHTS: dict[str, float] = {
    "transactions": 0.25,
    "accounts": 0.15,
    "budgets": 0.12,
    "recurring": 0.10,
    "income_declared": 0.20,
    "goals": 0.08,
    "obligations": 0.10,
}


def compute_coverage(bundle: GoatDataBundle, scope: Scope) -> CoverageSummary:
    breakdown = CoverageBreakdown(
        transactions=_pillar_transactions(bundle),
        accounts=_pillar_accounts(bundle),
        budgets=_pillar_budgets(bundle),
        recurring=_pillar_recurring(bundle),
        income_declared=_pillar_income_declared(bundle),
        goals=_pillar_goals(bundle),
        obligations=_pillar_obligations(bundle),
    )
    score = sum(getattr(breakdown, k) * w for k, w in PILLAR_WEIGHTS.items())

    readiness: ReadinessLevel = classify_readiness(bundle)
    missing = list(_collect_missing(bundle))
    inputs_used = _collect_inputs_used(bundle)
    unlockable = _unlockable_scopes(bundle)

    return CoverageSummary(
        coverage_score=round(score, 4),
        readiness_level=readiness,
        breakdown=breakdown,
        inputs_used=inputs_used,
        missing_inputs=missing,
        unlockable_scopes=unlockable,
    )


def classify_readiness(bundle: GoatDataBundle) -> ReadinessLevel:
    has_tx = _has_any_tx(bundle)
    has_income = _declared_income(bundle) is not None
    has_salary_day = _declared_salary_day(bundle) is not None
    has_accounts = any(a.get("is_active", True) for a in bundle.accounts)
    has_budgets = any(b.get("is_active", True) for b in bundle.budgets)
    has_recurring = any(s.get("is_active", True) for s in bundle.recurring_series)

    if has_tx and has_income and has_salary_day and (has_accounts or has_budgets or has_recurring):
        return "L3"
    if has_tx and (has_income or has_salary_day):
        return "L2"
    return "L1"


def _collect_inputs_used(bundle: GoatDataBundle) -> list[str]:
    used: list[str] = []
    if bundle.transactions_in_range:
        used.append("transactions.in_range")
    if bundle.transactions_prior_range:
        used.append("transactions.prior_range")
    if any(a.get("is_active", True) for a in bundle.accounts):
        used.append("accounts.active")
    if any(b.get("is_active", True) for b in bundle.budgets):
        used.append("budgets.active")
    if bundle.budget_periods:
        used.append("budget_periods")
    if any(s.get("is_active", True) for s in bundle.recurring_series):
        used.append("recurring_series.active")
    if bundle.recurring_occurrences:
        used.append("recurring_occurrences")
    if bundle.lend_borrow_entries:
        used.append("lend_borrow_entries")
    if _declared_income(bundle) is not None:
        used.append("goat_user_inputs.monthly_income")
    if _declared_salary_day(bundle) is not None:
        used.append("goat_user_inputs.salary_day")
    if _declared_ef_target(bundle) is not None:
        used.append("goat_user_inputs.emergency_fund_target_months")
    if bundle.goat_goals:
        used.append("goat_goals")
    if bundle.goat_obligations:
        used.append("goat_obligations")
    return used


def _collect_missing(bundle: GoatDataBundle) -> list[MissingInput]:
    out: list[MissingInput] = []

    if _declared_income(bundle) is None:
        out.append(
            MissingInput(
                key="goat_user_inputs.monthly_income",
                label="Monthly income",
                why="Unlocks savings-rate, income vs expense, and runway math.",
                unlocks=["overview.savings_rate", "cashflow.runway", "debt.debt_to_income"],
                severity="watch",
            )
        )
    if _declared_salary_day(bundle) is None:
        out.append(
            MissingInput(
                key="goat_user_inputs.salary_day",
                label="Salary day",
                why="Needed to estimate end-of-month liquidity between pay cycles.",
                unlocks=["cashflow.end_of_month_liquidity"],
                severity="info",
            )
        )
    if _declared_ef_target(bundle) is None:
        out.append(
            MissingInput(
                key="goat_user_inputs.emergency_fund_target_months",
                label="Emergency-fund target (in months)",
                why="Without a target we can't tell you the size of the gap.",
                unlocks=["overview.emergency_fund_runway"],
                severity="info",
            )
        )
    if not any(a.get("is_active", True) for a in bundle.accounts):
        out.append(
            MissingInput(
                key="accounts.any",
                label="At least one account",
                why="Net worth and liquidity analytics need account balances.",
                unlocks=["overview.net_worth", "cashflow.liquidity"],
                severity="info",
            )
        )
    if not any(b.get("is_active", True) for b in bundle.budgets):
        out.append(
            MissingInput(
                key="budgets.any_active",
                label="An active budget",
                why="Budget utilization and overrun signals need at least one budget.",
                unlocks=["budgets.*"],
                severity="info",
            )
        )
    if not any(g.get("status") == "active" for g in bundle.goat_goals):
        out.append(
            MissingInput(
                key="goat_goals.any_active",
                label="A savings or purchase goal",
                why="Goal-coverage and shortfall analytics need at least one active goal.",
                unlocks=["goals.*"],
                severity="info",
            )
        )
    return out


def _unlockable_scopes(bundle: GoatDataBundle) -> list[Scope]:
    """Scopes that would have meaningful output if their missing inputs were added."""
    out: list[Scope] = []
    if _declared_income(bundle) is None and _has_any_tx(bundle):
        out.append("cashflow")
    if not any(b.get("is_active", True) for b in bundle.budgets):
        out.append("budgets")
    if not any(g.get("status") == "active" for g in bundle.goat_goals):
        out.append("goals")
    if not bundle.goat_obligations and not bundle.lend_borrow_entries:
        out.append("debt")
    return out


def requirements_met(bundle: GoatDataBundle, scope: Scope) -> dict[str, Any]:
    """What each scope's deterministic layer needs; consumed by deterministic.py."""
    return {
        "has_tx": _has_any_tx(bundle),
        "income": _declared_income(bundle),
        "salary_day": _declared_salary_day(bundle),
        "ef_target": _declared_ef_target(bundle),
        "has_accounts": any(a.get("is_active", True) for a in bundle.accounts),
        "active_budgets": [b for b in bundle.budgets if b.get("is_active", True)],
        "active_recurring": [s for s in bundle.recurring_series if s.get("is_active", True)],
        "active_goals": [g for g in bundle.goat_goals if g.get("status") == "active"],
        "active_obligations": [o for o in bundle.goat_obligations if o.get("status") == "active"],
        "open_lend_borrow": [e for e in bundle.lend_borrow_entries if e.get("status") == "pending"],
    }
