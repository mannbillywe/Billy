from goat.deterministic import compute_scope
from goat.missing_inputs import compute_coverage
from goat.recommendations import generate


def test_missing_input_recs_for_empty_bundle(empty_bundle):
    payload = compute_scope(empty_bundle, "overview")
    cov = compute_coverage(empty_bundle, "overview")
    recs = generate(scope="overview", bundle=empty_bundle, payload=payload, coverage=cov)
    kinds = {r.kind for r in recs}
    assert "missing_input" in kinds
    # All recs dedupe by fingerprint
    fps = [r.rec_fingerprint for r in recs]
    assert len(fps) == len(set(fps))


def test_fingerprint_stable_across_runs(empty_bundle):
    payload = compute_scope(empty_bundle, "overview")
    cov = compute_coverage(empty_bundle, "overview")
    recs_a = generate(scope="overview", bundle=empty_bundle, payload=payload, coverage=cov)
    recs_b = generate(scope="overview", bundle=empty_bundle, payload=payload, coverage=cov)
    assert {r.rec_fingerprint for r in recs_a} == {r.rec_fingerprint for r in recs_b}


def test_existing_open_fingerprints_suppresses_duplicates(empty_bundle):
    payload = compute_scope(empty_bundle, "overview")
    cov = compute_coverage(empty_bundle, "overview")
    recs_first = generate(scope="overview", bundle=empty_bundle, payload=payload, coverage=cov)
    existing = {r.rec_fingerprint for r in recs_first}
    recs_second = generate(
        scope="overview",
        bundle=empty_bundle,
        payload=payload,
        coverage=cov,
        existing_open_fingerprints=existing,
    )
    assert recs_second == []


def test_budget_overrun_rec_emitted(medium_bundle):
    payload = compute_scope(medium_bundle, "full")
    cov = compute_coverage(medium_bundle, "full")
    recs = generate(scope="full", bundle=medium_bundle, payload=payload, coverage=cov)
    assert any(r.kind == "budget_overrun" for r in recs)


def test_goal_shortfall_rec_emitted(medium_bundle):
    payload = compute_scope(medium_bundle, "goals")
    cov = compute_coverage(medium_bundle, "goals")
    recs = generate(scope="goals", bundle=medium_bundle, payload=payload, coverage=cov)
    assert any(r.kind == "goal_shortfall" for r in recs)


def test_priority_sorted_desc(medium_bundle):
    payload = compute_scope(medium_bundle, "full")
    cov = compute_coverage(medium_bundle, "full")
    recs = generate(scope="full", bundle=medium_bundle, payload=payload, coverage=cov)
    priorities = [r.priority for r in recs]
    assert priorities == sorted(priorities, reverse=True)
