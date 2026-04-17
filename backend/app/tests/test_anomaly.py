"""Tests for the anomaly layer."""
from __future__ import annotations

from datetime import date, timedelta

from goat.anomaly import run_anomaly_layer
from goat.anomaly.robust import mad, robust_z
from goat.data_loader import GoatDataBundle


# ─── Helpers ─────────────────────────────────────────────────────────────────


def _tx(d: date, amt: float, t: str = "expense", cat: str = "food", tx_id: str | None = None):
    return {
        "id": tx_id or f"tx-{d.isoformat()}-{amt}-{cat}",
        "amount": amt,
        "date": d.isoformat(),
        "type": t,
        "category_id": cat,
        "status": "confirmed",
        "updated_at": f"{d.isoformat()}T00:00:00+00:00",
    }


# ─── Robust stats ────────────────────────────────────────────────────────────


def test_mad_and_robust_z_flat_history():
    hist = [100, 100, 100, 100]
    assert mad(hist) == 0
    # flat history with iqr=0 → robust_z returns 0 (no false spike)
    assert robust_z(500, hist) == 0


def test_robust_z_flags_outlier():
    hist = [100, 110, 95, 105, 98, 102, 107, 100, 103]
    z = robust_z(500, hist)
    assert z > 3.5, f"expected spike, got z={z}"


# ─── Layer behaviour ─────────────────────────────────────────────────────────


def test_layer_disabled_on_tiny_window():
    end = date(2026, 4, 1)
    b = GoatDataBundle(
        user_id="u1",
        scope="overview",
        range_start=end - timedelta(days=3),
        range_end=end,
    )
    layer = run_anomaly_layer(b)
    assert layer.disabled is True
    assert layer.items == []


def test_amount_spike_detected():
    end = date(2026, 4, 1)
    start = end - timedelta(days=60)
    prior = [_tx(start + timedelta(days=i), 300 + (i % 5) * 10) for i in range(40)]
    # a 5x spike in the current window
    cur = [_tx(end - timedelta(days=5), 1800, tx_id="spiky"), _tx(end - timedelta(days=2), 310)]
    b = GoatDataBundle(
        user_id="u2",
        scope="overview",
        range_start=start,
        range_end=end,
        transactions_in_range=cur,
        transactions_prior_range=prior,
    )
    layer = run_anomaly_layer(b)
    spikes = [i for i in layer.items if i.anomaly_type == "amount_spike_category"]
    assert any(s.entity_id == "spiky" for s in spikes)
    s = next(i for i in spikes if i.entity_id == "spiky")
    assert s.method == "robust_mad"
    assert s.score and s.score >= 3.5
    assert s.explanation


def test_recurring_bill_jump_detected():
    end = date(2026, 4, 1)
    occ = [
        {
            "id": f"o-{i}",
            "series_id": "rs1",
            "status": "paid",
            "actual_amount": 500,
            "due_date": (end - timedelta(days=30 * (6 - i))).isoformat(),
        }
        for i in range(5)
    ]
    # latest jump: 500 → 900 (+80%)
    occ.append(
        {
            "id": "o-latest",
            "series_id": "rs1",
            "status": "paid",
            "actual_amount": 900,
            "due_date": end.isoformat(),
        }
    )
    b = GoatDataBundle(
        user_id="u3",
        scope="recurring",
        range_start=end - timedelta(days=180),
        range_end=end,
        recurring_occurrences=occ,
    )
    layer = run_anomaly_layer(b)
    jumps = [i for i in layer.items if i.anomaly_type == "recurring_bill_jump"]
    assert jumps and jumps[0].entity_id == "rs1"


def test_duplicate_like_pattern_detected():
    end = date(2026, 4, 1)
    start = end - timedelta(days=30)
    tx = [
        _tx(end - timedelta(days=1), 250.00, cat="coffee", tx_id="a"),
        _tx(end - timedelta(days=1), 250.00, cat="coffee", tx_id="b"),
        _tx(end - timedelta(days=1), 250.00, cat="coffee", tx_id="c"),
    ]
    b = GoatDataBundle(
        user_id="u4",
        scope="overview",
        range_start=start,
        range_end=end,
        transactions_in_range=tx,
    )
    layer = run_anomaly_layer(b)
    dups = [i for i in layer.items if i.anomaly_type == "duplicate_like_pattern"]
    assert dups


def test_no_false_positives_on_sparse_data():
    end = date(2026, 4, 1)
    b = GoatDataBundle(
        user_id="u5",
        scope="overview",
        range_start=end - timedelta(days=20),
        range_end=end,
        transactions_in_range=[_tx(end - timedelta(days=2), 100)],
        transactions_prior_range=[],
    )
    layer = run_anomaly_layer(b)
    # With no prior window and no thresholds met, we shouldn't flag anything.
    assert all(i.severity != "warn" for i in layer.items)
