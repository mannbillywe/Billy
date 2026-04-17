from goat.deterministic import compute_scope


def _find(payload, key):
    return next((m for m in payload.metrics if m.key == key), None)


def test_overview_produces_metrics_even_empty(empty_bundle):
    p = compute_scope(empty_bundle, "overview")
    assert p.scope == "overview"
    assert len(p.metrics) >= 6
    nw = _find(p, "net_worth")
    assert nw is not None and nw.value is None
    assert "no_accounts" in nw.reason_codes
    sr = _find(p, "savings_rate")
    assert sr is not None
    assert "goat_user_inputs.monthly_income" in sr.inputs_missing


def test_overview_medium_has_savings_rate_and_net_worth(medium_bundle):
    p = compute_scope(medium_bundle, "overview")
    nw = _find(p, "net_worth")
    assert nw is not None and isinstance(nw.value, float)
    # 120000 savings asset - 8500 credit = 111500
    assert abs(nw.value - 111500.0) < 1.0
    sr = _find(p, "savings_rate")
    assert sr is not None and sr.value is not None
    assert 0.0 < sr.value < 1.0
    assert "goat_user_inputs.monthly_income" in sr.inputs_used


def test_cashflow_partial_without_salary_day(sparse_bundle):
    p = compute_scope(sparse_bundle, "cashflow")
    inflow = _find(p, "cashflow_inflow")
    eom = _find(p, "end_of_month_spend_forecast_directional")
    assert inflow is not None
    assert eom is not None and eom.value is None
    assert "goat_user_inputs.salary_day" in eom.inputs_missing


def test_budgets_flags_overrun_vs_pace(medium_bundle):
    p = compute_scope(medium_bundle, "budgets")
    tracked = _find(p, "budgets_tracked")
    assert tracked is not None and tracked.value == 1
    # The fixture has spent=6800 of 8000 limit on day 1 of the month => overrun.
    util = next(m for m in p.metrics if m.key.startswith("budget_") and m.key.endswith("_utilization"))
    assert util.detail["overrun"] is True


def test_recurring_counts_and_monthly_burden(medium_bundle):
    p = compute_scope(medium_bundle, "recurring")
    assert _find(p, "recurring_active_count").value == 1
    assert _find(p, "recurring_monthly_burden").value == 499.0
    assert _find(p, "recurring_share_of_income").value is not None


def test_debt_reports_zero_when_nothing_declared(medium_bundle):
    p = compute_scope(medium_bundle, "debt")
    assert _find(p, "obligation_outstanding_total").value == 0.0
    dti = _find(p, "debt_to_income_ratio")
    # declared income + no obligations => DTI = 0
    assert dti.value == 0.0


def test_goals_returns_gap_and_required_monthly(medium_bundle):
    p = compute_scope(medium_bundle, "goals")
    assert _find(p, "goals_active_count").value == 1
    gap_metric = next(m for m in p.metrics if m.key.startswith("goal_") and m.key.endswith("_gap"))
    assert gap_metric.value == 105000.0
    assert gap_metric.detail["required_monthly"] is not None


def test_full_scope_aggregates_all(medium_bundle):
    p = compute_scope(medium_bundle, "full")
    keys = {m.key for m in p.metrics}
    assert "net_worth" in keys
    assert "cashflow_outflow" in keys
    assert "budgets_tracked" in keys
    assert "recurring_active_count" in keys
    assert "debt_to_income_ratio" in keys
    assert "goals_active_count" in keys
