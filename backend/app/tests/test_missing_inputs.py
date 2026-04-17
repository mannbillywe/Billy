from goat.missing_inputs import classify_readiness, compute_coverage


def test_empty_bundle_is_L1_with_low_coverage(empty_bundle):
    cov = compute_coverage(empty_bundle, "overview")
    assert cov.readiness_level == "L1"
    assert cov.coverage_score < 0.3
    missing_keys = {m.key for m in cov.missing_inputs}
    assert "goat_user_inputs.monthly_income" in missing_keys
    assert "goat_user_inputs.salary_day" in missing_keys
    assert "accounts.any" in missing_keys


def test_sparse_bundle_still_gives_partial_output(sparse_bundle):
    cov = compute_coverage(sparse_bundle, "overview")
    assert cov.readiness_level == "L1"
    assert cov.coverage_score > 0.0
    assert "transactions.in_range" in cov.inputs_used


def test_medium_bundle_reaches_L3(medium_bundle):
    cov = compute_coverage(medium_bundle, "overview")
    assert cov.readiness_level == "L3"
    assert "goat_user_inputs.monthly_income" in cov.inputs_used
    assert "goat_user_inputs.salary_day" in cov.inputs_used
    assert "accounts.active" in cov.inputs_used


def test_readiness_requires_tx_for_L2(empty_bundle):
    # No transactions => L1 even if income is declared.
    empty_bundle.goat_user_inputs = {"monthly_income": 50000, "salary_day": 1}
    assert classify_readiness(empty_bundle) == "L1"
