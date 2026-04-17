from goat.fingerprints import data_fingerprint, rec_fingerprint


def test_data_fingerprint_stable_for_same_inputs():
    args = dict(
        user_id="u",
        scope="overview",
        range_start="2026-01-01",
        range_end="2026-04-01",
        counts={"tx": 10, "ac": 2},
        stamps={"tx": "2026-03-01T00:00:00", "ac": "2026-03-20T00:00:00"},
    )
    assert data_fingerprint(**args) == data_fingerprint(**args)


def test_data_fingerprint_changes_with_data_change():
    base = dict(
        user_id="u",
        scope="overview",
        range_start="2026-01-01",
        range_end="2026-04-01",
        counts={"tx": 10},
        stamps={"tx": "2026-03-01T00:00:00"},
    )
    other_count = {**base, "counts": {"tx": 11}}
    other_stamp = {**base, "stamps": {"tx": "2026-03-02T00:00:00"}}
    assert data_fingerprint(**base) != data_fingerprint(**other_count)
    assert data_fingerprint(**base) != data_fingerprint(**other_stamp)


def test_rec_fingerprint_stable():
    assert rec_fingerprint("missing_input", "goat_user_inputs.monthly_income") == rec_fingerprint(
        "missing_input", "goat_user_inputs.monthly_income"
    )
    assert rec_fingerprint("budget_overrun", "bid-1") != rec_fingerprint("budget_overrun", "bid-2")
