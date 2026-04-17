"""Test fixtures.

We DO NOT hit a real Supabase. Instead we build a `GoatDataBundle` in memory
and exercise deterministic.py / recommendations.py / runner.compute() directly.
For runner.run_job() tests we monkey-patch supabase_io with an in-memory fake.
"""
from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Any

import pytest

# Make `goat` importable from this tests folder without installing the package.
ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


# ─── Bundle builders ─────────────────────────────────────────────────────────


def _tx(
    *,
    date_: date,
    amount: float,
    type_: str = "expense",
    category_id: str | None = None,
    tx_id: str | None = None,
) -> dict[str, Any]:
    return {
        "id": tx_id or f"tx-{date_.isoformat()}-{amount}-{type_}",
        "amount": amount,
        "date": date_.isoformat(),
        "type": type_,
        "category_id": category_id,
        "status": "confirmed",
        "updated_at": f"{date_.isoformat()}T00:00:00+00:00",
        "currency": "INR",
    }


@pytest.fixture
def empty_bundle():
    from goat.data_loader import GoatDataBundle

    end = date(2026, 4, 1)
    return GoatDataBundle(
        user_id="00000000-0000-0000-0000-000000000001",
        scope="overview",
        range_start=end - timedelta(days=90),
        range_end=end,
    )


@pytest.fixture
def sparse_bundle():
    """L1 persona: a few transactions, nothing else."""
    from goat.data_loader import GoatDataBundle

    end = date(2026, 4, 1)
    start = end - timedelta(days=60)
    tx = [
        _tx(date_=start + timedelta(days=i * 4), amount=250 + i * 10, type_="expense")
        for i in range(12)
    ]
    return GoatDataBundle(
        user_id="00000000-0000-0000-0000-000000000002",
        scope="overview",
        range_start=start,
        range_end=end,
        transactions_in_range=tx,
        transactions_prior_range=[],
    )


@pytest.fixture
def medium_bundle():
    """L2 persona: tx + accounts + 1 budget + 1 recurring + declared income + goal."""
    from goat.data_loader import GoatDataBundle

    end = date(2026, 4, 1)
    start = end - timedelta(days=180)
    income_rows = [
        _tx(date_=start + timedelta(days=30 * m), amount=65000, type_="income")
        for m in range(6)
    ]
    spend_rows: list[dict[str, Any]] = []
    for i in range(60):
        d = start + timedelta(days=i * 3)
        spend_rows.append(
            _tx(
                date_=d,
                amount=300 + (i % 7) * 80,
                type_="expense",
                category_id="cat-food",
            )
        )
    prior_rows = [
        _tx(
            date_=start - timedelta(days=30 + i * 3),
            amount=350 + (i % 5) * 60,
            type_="expense",
        )
        for i in range(50)
    ]

    return GoatDataBundle(
        user_id="00000000-0000-0000-0000-000000000003",
        scope="overview",
        range_start=start,
        range_end=end,
        profile={
            "id": "00000000-0000-0000-0000-000000000003",
            "preferred_currency": "INR",
            "goat_mode": True,
        },
        goat_user_inputs={
            "user_id": "00000000-0000-0000-0000-000000000003",
            "monthly_income": 65000,
            "salary_day": 1,
            "emergency_fund_target_months": 3,
            "liquidity_floor": 5000,
            "updated_at": "2026-03-01T00:00:00+00:00",
        },
        goat_goals=[
            {
                "id": "goal-1",
                "user_id": "00000000-0000-0000-0000-000000000003",
                "goal_type": "emergency_fund",
                "title": "Emergency fund",
                "target_amount": 150000,
                "current_amount": 45000,
                "target_date": (end + timedelta(days=300)).isoformat(),
                "priority": 1,
                "status": "active",
            }
        ],
        goat_obligations=[],
        accounts=[
            {
                "id": "acc-1",
                "type": "savings",
                "current_balance": 120000,
                "is_asset": True,
                "is_active": True,
                "currency": "INR",
                "updated_at": "2026-03-20T00:00:00+00:00",
            },
            {
                "id": "acc-2",
                "type": "credit_card",
                "current_balance": 8500,
                "is_asset": False,
                "is_active": True,
                "currency": "INR",
                "updated_at": "2026-03-20T00:00:00+00:00",
            },
        ],
        transactions_in_range=income_rows + spend_rows,
        transactions_prior_range=prior_rows,
        budgets=[
            {
                "id": "bud-food",
                "name": "Food",
                "amount": 8000,
                "period": "monthly",
                "is_active": True,
                "category_id": "cat-food",
            }
        ],
        budget_periods=[
            {
                "id": "bp-food-cur",
                "budget_id": "bud-food",
                "user_id": "00000000-0000-0000-0000-000000000003",
                "period_start": (end.replace(day=1)).isoformat(),
                "period_end": (
                    (end.replace(day=1) + timedelta(days=32)).replace(day=1)
                    - timedelta(days=1)
                ).isoformat(),
                "spent": 6800,
                "updated_at": "2026-04-01T00:00:00+00:00",
            }
        ],
        recurring_series=[
            {
                "id": "rs-ott",
                "title": "Netflix",
                "amount": 499,
                "cadence": "monthly",
                "is_active": True,
            }
        ],
        recurring_occurrences=[
            {
                "id": "ro-ott-next",
                "series_id": "rs-ott",
                "user_id": "00000000-0000-0000-0000-000000000003",
                "due_date": (date.today() + timedelta(days=10)).isoformat(),
                "actual_amount": 499,
                "status": "upcoming",
            }
        ],
        lend_borrow_entries=[],
    )


# ─── Fake Supabase for runner tests ──────────────────────────────────────────


class FakeTable:
    def __init__(self, store: "FakeStore", name: str):
        self._store = store
        self._name = name
        self._op = "select"
        self._payload: Any = None
        self._filters: list[tuple[str, str, Any]] = []
        self._select_cols = "*"
        self._range: tuple[int, int] | None = None
        self._order: tuple[str, bool] | None = None
        self._on_conflict: str | None = None
        self._limit: int | None = None

    def select(self, cols: str = "*"):
        self._op = "select"
        self._select_cols = cols
        return self

    def insert(self, payload):
        self._op = "insert"
        self._payload = payload
        return self

    def upsert(self, payload, *, on_conflict: str | None = None):
        self._op = "upsert"
        self._payload = payload
        self._on_conflict = on_conflict
        return self

    def update(self, payload):
        self._op = "update"
        self._payload = payload
        return self

    def eq(self, col, val):
        self._filters.append(("eq", col, val))
        return self

    def neq(self, col, val):
        self._filters.append(("neq", col, val))
        return self

    def gte(self, col, val):
        self._filters.append(("gte", col, val))
        return self

    def lte(self, col, val):
        self._filters.append(("lte", col, val))
        return self

    def order(self, col, *, desc: bool = False):
        self._order = (col, desc)
        return self

    def range(self, start, end):
        self._range = (start, end)
        return self

    def limit(self, n):
        self._limit = n
        return self

    def execute(self):
        rows = self._store.tables.setdefault(self._name, [])
        if self._op == "select":
            result = [r for r in rows if self._match(r)]
            if self._order:
                col, desc = self._order
                result.sort(key=lambda r: (r.get(col) is None, r.get(col)), reverse=desc)
            if self._range is not None:
                s, e = self._range
                result = result[s : e + 1]
            if self._limit is not None:
                result = result[: self._limit]
            return _Result(result)
        if self._op in ("insert", "upsert"):
            to_write = self._payload if isinstance(self._payload, list) else [self._payload]
            inserted: list[dict] = []
            for r in to_write:
                r = {**r}
                if "now()" in str(r.get("started_at", "")):
                    from datetime import datetime, timezone

                    r["started_at"] = datetime.now(timezone.utc).isoformat()
                if "now()" in str(r.get("finished_at", "")):
                    from datetime import datetime, timezone

                    r["finished_at"] = datetime.now(timezone.utc).isoformat()
                if self._op == "upsert" and self._on_conflict:
                    keys = [k.strip() for k in self._on_conflict.split(",")]
                    existing = next(
                        (x for x in rows if all(x.get(k) == r.get(k) for k in keys)),
                        None,
                    )
                    if existing:
                        existing.update(r)
                        inserted.append(existing)
                        continue
                if "id" not in r or r["id"] is None:
                    import uuid as _uuid

                    r["id"] = str(_uuid.uuid4())
                if "created_at" not in r:
                    from datetime import datetime, timezone

                    r["created_at"] = datetime.now(timezone.utc).isoformat()
                if "generated_at" not in r and self._name == "goat_mode_snapshots":
                    from datetime import datetime, timezone

                    r["generated_at"] = datetime.now(timezone.utc).isoformat()
                rows.append(r)
                inserted.append(r)
            return _Result(inserted)
        if self._op == "update":
            result = []
            for r in rows:
                if self._match(r):
                    patch = {**self._payload}
                    if "now()" in str(patch.get("finished_at", "")):
                        from datetime import datetime, timezone

                        patch["finished_at"] = datetime.now(timezone.utc).isoformat()
                    r.update(patch)
                    result.append(r)
            return _Result(result)
        raise RuntimeError(f"unknown op: {self._op}")

    def _match(self, row) -> bool:
        for op, col, val in self._filters:
            rv = row.get(col)
            if op == "eq" and rv != val:
                return False
            if op == "neq" and rv == val:
                return False
            if op == "gte" and (rv is None or str(rv) < str(val)):
                return False
            if op == "lte" and (rv is None or str(rv) > str(val)):
                return False
        return True


class _Result:
    def __init__(self, data):
        self.data = data


class FakeStore:
    def __init__(self):
        self.tables: dict[str, list[dict]] = {
            "profiles": [],
            "goat_user_inputs": [],
            "goat_goals": [],
            "goat_obligations": [],
            "accounts": [],
            "transactions": [],
            "budgets": [],
            "budget_periods": [],
            "recurring_series": [],
            "recurring_occurrences": [],
            "lend_borrow_entries": [],
            "statement_imports": [],
            "goat_mode_jobs": [],
            "goat_mode_snapshots": [],
            "goat_mode_job_events": [],
            "goat_mode_recommendations": [],
        }

    def table(self, name: str) -> FakeTable:
        return FakeTable(self, name)


@pytest.fixture
def fake_store() -> FakeStore:
    return FakeStore()


@pytest.fixture
def fake_client(fake_store):
    class _Client:
        def __init__(self, store):
            self._store = store

        def table(self, name):
            return self._store.table(name)

    return _Client(fake_store)
