"""
Full reset + 12-month daily seed for user Nitin
  UUID: f308f807-00eb-46ce-9468-63cd7c8d3c0f

Run from inside the billy-ai-local container (which has SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY wired up):
    docker cp scripts/seed_nitin_via_api.py billy-ai-local:/tmp/seed_nitin.py
    docker exec billy-ai-local python /tmp/seed_nitin.py

Does exactly what scripts/seed_manng_data.sql does, but via PostgREST so we
don't need psql or the SQL editor. Idempotent: wipes the target user's rows
every run, then reseeds.
"""

from __future__ import annotations

import os
import random
import sys
import uuid
from datetime import date, timedelta
from typing import Any, Dict, List

from supabase import create_client

UID = "f308f807-00eb-46ce-9468-63cd7c8d3c0f"
TODAY = date.today()
START = TODAY - timedelta(days=364)  # inclusive -> 365 days

# Deterministic "fake" IDs so reruns map predictably.
ACCT_HDFC = "a0f30880-0000-4001-a001-000000000001"
ACCT_SBI = "a0f30880-0000-4001-a002-000000000002"
ACCT_CC = "a0f30880-0000-4001-a003-000000000003"
ACCT_CASH = "a0f30880-0000-4001-a004-000000000004"
ACCT_MF = "a0f30880-0000-4001-a005-000000000005"


def build_client():
    url = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return create_client(url, key)


def wipe(sb) -> None:
    """Delete every row belonging to UID, in FK-safe order."""
    order = [
        "goat_mode_recommendations",
        "goat_mode_job_events",
        "goat_mode_snapshots",
        "goat_mode_jobs",
        "goat_obligations",
        "goat_goals",
        "goat_user_inputs",
        "activity_events",
        "transactions",
        "documents",
        "budgets",
        "recurring_series",
        "lend_borrow_entries",
        "accounts",
    ]
    for tbl in order:
        try:
            sb.table(tbl).delete().eq("user_id", UID).execute()
            print(f"  wiped {tbl}")
        except Exception as exc:  # noqa: BLE001
            # Non-fatal: table may not exist on this deploy, skip.
            print(f"  skip  {tbl}: {exc}")


def ensure_default_categories(sb) -> Dict[str, str]:
    """Make sure default categories exist (user_id NULL); return name -> id map."""
    wanted = [
        ("Food & Beverage", "\U0001F354", "#F97316"),
        ("Dining", "\U0001F37D", "#EF4444"),
        ("Groceries", "\U0001F6D2", "#22C55E"),
        ("Transportation", "\U0001F695", "#3B82F6"),
        ("Shopping", "\U0001F6CD", "#EC4899"),
        ("Utilities", "\u26A1", "#F59E0B"),
        ("Entertainment", "\U0001F3AC", "#8B5CF6"),
        ("Healthcare", "\U0001F3E5", "#EF4444"),
        ("Education", "\U0001F4DA", "#06B6D4"),
        ("Housing", "\U0001F3E0", "#8B5CF6"),
        ("Subscriptions", "\U0001F4F1", "#10B981"),
        ("Maintenance", "\U0001F527", "#6B7280"),
        ("Stationery", "\u270F\uFE0F", "#A855F7"),
        ("Equipment", "\U0001F4BB", "#0EA5E9"),
        ("Borrow", "\U0001F4E5", "#EF4444"),
        ("Lend", "\U0001F4E4", "#06B6D4"),
        ("Other", "\U0001F4E6", "#6B7280"),
    ]
    existing = (
        sb.table("categories")
        .select("id,name")
        .is_("user_id", "null")
        .execute()
        .data
        or []
    )
    have = {r["name"]: r["id"] for r in existing}
    to_insert: List[Dict[str, Any]] = []
    for name, icon, color in wanted:
        if name not in have:
            to_insert.append(
                {
                    "id": str(uuid.uuid4()),
                    "user_id": None,
                    "name": name,
                    "icon": icon,
                    "color": color,
                    "is_default": True,
                }
            )
    if to_insert:
        sb.table("categories").insert(to_insert).execute()
    rows = (
        sb.table("categories")
        .select("id,name")
        .is_("user_id", "null")
        .execute()
        .data
        or []
    )
    return {r["name"]: r["id"] for r in rows}


def seed_accounts(sb) -> None:
    rows = [
        {
            "id": ACCT_HDFC,
            "user_id": UID,
            "name": "HDFC Savings",
            "type": "savings",
            "institution": "HDFC Bank",
            "currency": "INR",
            "current_balance": 245800.00,
            "is_asset": True,
        },
        {
            "id": ACCT_SBI,
            "user_id": UID,
            "name": "SBI Salary",
            "type": "checking",
            "institution": "SBI",
            "currency": "INR",
            "current_balance": 58320.00,
            "is_asset": True,
        },
        {
            "id": ACCT_CC,
            "user_id": UID,
            "name": "ICICI Amazon Pay",
            "type": "credit_card",
            "institution": "ICICI Bank",
            "currency": "INR",
            "current_balance": -12450.00,
            "is_asset": False,
        },
        {
            "id": ACCT_CASH,
            "user_id": UID,
            "name": "Cash",
            "type": "cash",
            "institution": None,
            "currency": "INR",
            "current_balance": 3200.00,
            "is_asset": True,
        },
        {
            "id": ACCT_MF,
            "user_id": UID,
            "name": "Groww MF",
            "type": "investment",
            "institution": "Groww",
            "currency": "INR",
            "current_balance": 125000.00,
            "is_asset": True,
        },
    ]
    sb.table("accounts").insert(rows).execute()


# vendor, category, payment, account, lo, hi
VENDORS: List[tuple] = [
    ("BigBasket", "Groceries", "UPI", ACCT_HDFC, 800, 3800),
    ("DMart", "Groceries", "Cash", ACCT_CASH, 500, 3200),
    ("Reliance Fresh", "Groceries", "UPI", ACCT_HDFC, 600, 3500),
    ("Spencer's", "Groceries", "Cash", ACCT_CASH, 500, 2800),
    ("More Supermarket", "Groceries", "UPI", ACCT_HDFC, 700, 3200),
    ("Swiggy", "Dining", "UPI", ACCT_HDFC, 150, 1100),
    ("Zomato", "Dining", "UPI", ACCT_HDFC, 180, 1200),
    ("Dominos", "Dining", "UPI", ACCT_HDFC, 250, 1400),
    ("KFC", "Dining", "UPI", ACCT_HDFC, 300, 1000),
    ("McDonald's", "Dining", "Cash", ACCT_CASH, 200, 800),
    ("Haldiram", "Dining", "Cash", ACCT_CASH, 400, 2200),
    ("Uber", "Transportation", "UPI", ACCT_HDFC, 80, 550),
    ("Ola", "Transportation", "UPI", ACCT_HDFC, 70, 500),
    ("Rapido", "Transportation", "UPI", ACCT_HDFC, 50, 350),
    ("Petrol Pump - HP", "Transportation", "UPI", ACCT_HDFC, 1800, 3500),
    ("Indian Oil", "Transportation", "UPI", ACCT_HDFC, 1700, 3200),
    ("Metro Card", "Transportation", "UPI", ACCT_HDFC, 100, 600),
    ("Airtel Fiber", "Utilities", "Auto-debit", ACCT_HDFC, 1499, 1499),
    ("Jio Fiber", "Utilities", "Auto-debit", ACCT_HDFC, 999, 999),
    ("Electricity Board", "Utilities", "UPI", ACCT_HDFC, 1500, 2600),
    ("BESCOM", "Utilities", "UPI", ACCT_HDFC, 1400, 2500),
    ("Gas Bill", "Utilities", "Cash", ACCT_CASH, 600, 1200),
    ("Amazon", "Shopping", "Credit Card", ACCT_CC, 500, 4500),
    ("Flipkart", "Shopping", "Credit Card", ACCT_CC, 400, 3800),
    ("Myntra", "Shopping", "Credit Card", ACCT_CC, 600, 3500),
    ("Ajio", "Shopping", "Credit Card", ACCT_CC, 400, 3000),
    ("Decathlon", "Shopping", "Credit Card", ACCT_CC, 800, 4500),
    ("Netflix", "Subscriptions", "Credit Card", ACCT_CC, 649, 649),
    ("Spotify Premium", "Subscriptions", "Credit Card", ACCT_CC, 119, 119),
    ("Prime Video", "Subscriptions", "Credit Card", ACCT_CC, 299, 299),
    ("Hotstar", "Subscriptions", "Credit Card", ACCT_CC, 299, 299),
    ("YouTube Premium", "Subscriptions", "Credit Card", ACCT_CC, 129, 129),
    ("Apollo Pharmacy", "Healthcare", "UPI", ACCT_HDFC, 150, 1600),
    ("MedPlus", "Healthcare", "UPI", ACCT_HDFC, 120, 1400),
    ("PharmEasy", "Healthcare", "UPI", ACCT_HDFC, 150, 1500),
    ("Chai Point", "Food & Beverage", "Cash", ACCT_CASH, 80, 220),
    ("Starbucks", "Food & Beverage", "UPI", ACCT_HDFC, 220, 520),
    ("Cafe Coffee Day", "Food & Beverage", "UPI", ACCT_HDFC, 150, 380),
    ("Third Wave Coffee", "Food & Beverage", "UPI", ACCT_HDFC, 180, 420),
    ("PVR Cinemas", "Entertainment", "UPI", ACCT_HDFC, 250, 1200),
    ("INOX", "Entertainment", "UPI", ACCT_HDFC, 250, 1100),
    ("BookMyShow", "Entertainment", "UPI", ACCT_HDFC, 200, 1000),
]


def seed_transactions(sb, cat_map: Dict[str, str]) -> int:
    random.seed(42)  # deterministic
    batch: List[Dict[str, Any]] = []
    d = START
    while d <= TODAY:
        n = random.randint(5, 10)
        for _ in range(n):
            v_name, v_cat, v_pay, v_acct, lo, hi = random.choice(VENDORS)
            amt = random.randint(lo, hi)
            batch.append(
                {
                    "user_id": UID,
                    "amount": amt,
                    "currency": "INR",
                    "date": d.isoformat(),
                    "type": "expense",
                    "title": v_name,
                    "description": v_name,
                    "category_id": cat_map.get(v_cat),
                    "category_source": "manual",
                    "payment_method": v_pay,
                    "source_type": "manual",
                    "effective_amount": amt,
                    "status": "confirmed",
                    "account_id": v_acct,
                }
            )
        d += timedelta(days=1)

    # Salary: last day of each of the last 12 months
    from calendar import monthrange

    for mo_back in range(12):
        y = TODAY.year
        m = TODAY.month - mo_back
        while m <= 0:
            m += 12
            y -= 1
        last_day = monthrange(y, m)[1]
        sal_date = date(y, m, last_day)
        # Never create future-dated salary rows (skews 30d / 1M math).
        if sal_date > TODAY:
            sal_date = TODAY
        salary_amt = 85000 + (11 - mo_back) * 1000
        batch.append(
            {
                "user_id": UID,
                "amount": salary_amt,
                "currency": "INR",
                "date": sal_date.isoformat(),
                "type": "income",
                "title": f"Salary - {sal_date.strftime('%b %Y')}",
                "description": "Monthly salary",
                "source_type": "manual",
                "effective_amount": salary_amt,
                "status": "confirmed",
                "account_id": ACCT_SBI,
            }
        )

    # Chunk inserts because PostgREST body has limits.
    CHUNK = 500
    total = 0
    for i in range(0, len(batch), CHUNK):
        chunk = batch[i : i + CHUNK]
        sb.table("transactions").insert(chunk).execute()
        total += len(chunk)
        print(f"  inserted transactions {total}/{len(batch)}")
    return total


def mirror_documents(sb) -> int:
    """Mirror every seeded expense transaction into public.documents."""
    # Page through transactions for UID+expense, then batch-insert docs.
    offset = 0
    LIMIT = 1000
    total = 0
    while True:
        rows = (
            sb.table("transactions")
            .select(
                "id,amount,currency,date,title,description,category_id,payment_method"
            )
            .eq("user_id", UID)
            .eq("type", "expense")
            .range(offset, offset + LIMIT - 1)
            .execute()
            .data
            or []
        )
        if not rows:
            break
        docs = [
            {
                "user_id": UID,
                "type": "receipt",
                "vendor_name": r["title"],
                "amount": r["amount"],
                "currency": r.get("currency") or "INR",
                "tax_amount": 0,
                "date": r["date"],
                "category_id": r.get("category_id"),
                "description": r.get("description"),
                "payment_method": r.get("payment_method"),
                "status": "saved",
                "extracted_data": {
                    "seeded_by": "seed_nitin_via_api.py",
                    "source_transaction_id": r["id"],
                    "synthetic": True,
                },
                "category_source": "manual",
            }
            for r in rows
        ]
        # Insert in smaller PostgREST-friendly chunks.
        CHUNK = 500
        for i in range(0, len(docs), CHUNK):
            sb.table("documents").insert(docs[i : i + CHUNK]).execute()
        total += len(rows)
        print(f"  mirrored documents {total}")
        if len(rows) < LIMIT:
            break
        offset += LIMIT
    return total


def seed_budgets(sb, cat_map: Dict[str, str]) -> None:
    month_start = TODAY.replace(day=1)
    rows = [
        ("Groceries", cat_map.get("Groceries"), 12000),
        ("Dining", cat_map.get("Dining"), 6000),
        ("Transportation", cat_map.get("Transportation"), 8000),
        ("Utilities", cat_map.get("Utilities"), 5000),
        ("Shopping", cat_map.get("Shopping"), 10000),
        ("Subscriptions", cat_map.get("Subscriptions"), 2000),
        ("Entertainment", cat_map.get("Entertainment"), 2500),
    ]
    sb.table("budgets").insert(
        [
            {
                "user_id": UID,
                "name": name,
                "category_id": cid,
                "amount": amt,
                "period": "monthly",
                "currency": "INR",
                "is_active": True,
                "start_date": month_start.isoformat(),
            }
            for name, cid, amt in rows
        ]
    ).execute()


def seed_recurring(sb, cat_map: Dict[str, str]) -> None:
    rows = [
        ("Netflix", 649, cat_map["Subscriptions"], 335, 5),
        ("Spotify Premium", 119, cat_map["Subscriptions"], 330, 10),
        ("Airtel Fiber", 1499, cat_map["Utilities"], 333, 7),
        ("Electricity", 2000, cat_map["Utilities"], 325, 15),
        ("YouTube Premium", 129, cat_map["Subscriptions"], 240, 25),
    ]
    sb.table("recurring_series").insert(
        [
            {
                "user_id": UID,
                "title": t,
                "amount": a,
                "currency": "INR",
                "category_id": cid,
                "cadence": "monthly",
                "anchor_date": (TODAY - timedelta(days=ad)).isoformat(),
                "next_due": (TODAY + timedelta(days=nd)).isoformat(),
                "detection_source": "manual",
                "is_active": True,
            }
            for t, a, cid, ad, nd in rows
        ]
    ).execute()


def seed_lend_borrow(sb) -> None:
    rows = [
        ("Rahul", 5000, "lent", "pending", 12, "Weekend trip split"),
        ("Priya", 3000, "lent", "settled", -90, "Dinner share (closed)"),
        ("Vikram", 8000, "borrowed", "pending", 8, "Rent gap cover"),
        ("Sneha", 2000, "lent", "pending", 45, "Movie + dinner"),
        ("Arjun", 12000, "borrowed", "settled", -160, "Laptop repair (closed)"),
        ("Meera", 4500, "lent", "pending", 60, "Shopping split"),
        ("Karthik", 6000, "borrowed", "pending", 30, "Emergency cash"),
    ]
    sb.table("lend_borrow_entries").insert(
        [
            {
                "user_id": UID,
                "counterparty_name": n,
                "amount": a,
                "type": t,
                "status": s,
                "due_date": (TODAY + timedelta(days=off)).isoformat(),
                "notes": notes,
            }
            for n, a, t, s, off, notes in rows
        ]
    ).execute()


def seed_goat(sb) -> None:
    sb.table("goat_user_inputs").insert(
        [
            {
                "user_id": UID,
                "monthly_income": 90000,
                "income_currency": "INR",
                "pay_frequency": "monthly",
                "salary_day": 1,
                "emergency_fund_target_months": 6.0,
                "liquidity_floor": 150000,
                "household_size": 2,
                "dependents": 1,
                "risk_tolerance": "balanced",
                "planning_horizon_months": 12,
                "tone_preference": "direct",
                "notes": {
                    "seeded_by": "seed_nitin_via_api.py",
                    "readiness": "L3",
                },
            }
        ]
    ).execute()
    sb.table("goat_goals").insert(
        [
            {
                "user_id": UID,
                "goal_type": "emergency_fund",
                "title": "Emergency Fund (6 months)",
                "target_amount": 540000,
                "current_amount": 125000,
                "target_date": (TODAY + timedelta(days=180)).isoformat(),
                "priority": 1,
                "status": "active",
                "metadata": {"source": "seed"},
            },
            {
                "user_id": UID,
                "goal_type": "savings",
                "title": "Vacation — Goa Dec",
                "target_amount": 75000,
                "current_amount": 22000,
                "target_date": (TODAY + timedelta(days=240)).isoformat(),
                "priority": 3,
                "status": "active",
                "metadata": {"source": "seed"},
            },
            {
                "user_id": UID,
                "goal_type": "debt_payoff",
                "title": "Clear credit-card revolve",
                "target_amount": 20000,
                "current_amount": 5000,
                "target_date": (TODAY + timedelta(days=90)).isoformat(),
                "priority": 2,
                "status": "active",
                "metadata": {"source": "seed"},
            },
        ]
    ).execute()
    sb.table("goat_obligations").insert(
        [
            {
                "user_id": UID,
                "obligation_type": "emi",
                "lender_name": "HDFC Personal Loan",
                "current_outstanding": 280000,
                "monthly_due": 9500,
                "due_day": ((TODAY + timedelta(days=2)).day),
                "interest_rate": 11.25,
                "cadence": "monthly",
                "status": "active",
                "metadata": {"source": "seed"},
            },
            {
                "user_id": UID,
                "obligation_type": "rent",
                "lender_name": "Landlord",
                "current_outstanding": None,
                "monthly_due": 24000,
                "due_day": 5,
                "interest_rate": None,
                "cadence": "monthly",
                "status": "active",
                "metadata": {"source": "seed"},
            },
            {
                "user_id": UID,
                "obligation_type": "credit_card_min",
                "lender_name": "ICICI Amazon Pay",
                "current_outstanding": 18400,
                "monthly_due": 1840,
                "due_day": 12,
                "interest_rate": 38.00,
                "cadence": "monthly",
                "status": "active",
                "metadata": {"source": "seed"},
            },
        ]
    ).execute()


def set_profile_flags(sb) -> None:
    sb.table("profiles").update(
        {"goat_mode": True, "display_name": "Nitin", "preferred_currency": "INR"}
    ).eq("id", UID).execute()


def summarize(sb) -> None:
    def count(tbl: str) -> int:
        # Use user_id (always present) because some Goat tables have no
        # `id` column (user_id is the PK).
        r = (
            sb.table(tbl)
            .select("user_id", count="exact")
            .eq("user_id", UID)
            .limit(1)
            .execute()
        )
        return r.count or 0

    exp30 = (
        sb.table("transactions")
        .select("id", count="exact")
        .eq("user_id", UID)
        .eq("type", "expense")
        .gte("date", (TODAY - timedelta(days=30)).isoformat())
        .limit(1)
        .execute()
    )
    income = (
        sb.table("transactions")
        .select("id", count="exact")
        .eq("user_id", UID)
        .eq("type", "income")
        .limit(1)
        .execute()
    )
    print("── Seed summary for", UID, "──")
    print(f"  accounts          : {count('accounts')}")
    print(f"  transactions      : {count('transactions')}")
    print(f"    expenses 30d    : {exp30.count or 0}")
    print(f"    income (salary) : {income.count or 0}")
    print(f"  documents         : {count('documents')}")
    print(f"  budgets           : {count('budgets')}")
    print(f"  recurring_series  : {count('recurring_series')}")
    print(f"  lend_borrow       : {count('lend_borrow_entries')}")
    print(f"  goat_user_inputs  : {count('goat_user_inputs')}")
    print(f"  goat_goals        : {count('goat_goals')}")
    print(f"  goat_obligations  : {count('goat_obligations')}")


def main() -> int:
    print(f"Target UID : {UID}")
    print(f"Date range : {START} .. {TODAY}")
    sb = build_client()
    print("\n[1/9] Wiping user rows...")
    wipe(sb)
    print("\n[2/9] Ensuring default categories...")
    cat_map = ensure_default_categories(sb)
    missing = [
        n
        for n in (
            "Groceries",
            "Dining",
            "Transportation",
            "Utilities",
            "Shopping",
            "Subscriptions",
            "Entertainment",
            "Food & Beverage",
            "Healthcare",
        )
        if n not in cat_map
    ]
    if missing:
        print(f"  missing categories: {missing}", file=sys.stderr)
        return 2
    print("\n[3/9] Profile flags -> goat_mode=true...")
    set_profile_flags(sb)
    print("\n[4/9] Accounts (5)...")
    seed_accounts(sb)
    print("\n[5/9] Transactions (365 days, 5-10/day + salary)...")
    seed_transactions(sb, cat_map)
    print("\n[6/9] Mirror expenses -> documents...")
    mirror_documents(sb)
    print("\n[7/9] Budgets / Recurring...")
    seed_budgets(sb, cat_map)
    seed_recurring(sb, cat_map)
    print("\n[8/9] Lend / Borrow...")
    seed_lend_borrow(sb)
    print("\n[9/9] Goat Mode inputs / goals / obligations...")
    seed_goat(sb)
    print("")
    summarize(sb)
    print("\nDone. Refresh the dashboard in the app.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
