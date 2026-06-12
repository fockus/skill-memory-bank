"""Tests for rrf_merge — Reciprocal Rank Fusion module.

Hand-computed reference values:
  RRF score for rank r with parameter k = 1 / (k + r)
  A symbol at rank 1 in both lists: 1/(60+1) + 1/(60+1) = 2/61 ≈ 0.032787
  A symbol at rank 1 in list1 only: 1/61 ≈ 0.016393
  A symbol at rank 2 in list2 only: 1/62 ≈ 0.016129
"""

import pytest

from memory_bank_skill.rrf import rrf_merge

# ---------------------------------------------------------------------------
# Basic fusion math (scenario 2 — hand-verifiable)
# ---------------------------------------------------------------------------


def test_rrf_merge_basic_scores():
    """Symbols in both rankings accumulate scores; hand-verifiable values."""
    # ranking1: A=1, B=2
    # ranking2: B=1, C=2
    # A: 1/61            ≈ 0.016393
    # B: 1/62 + 1/61     ≈ 0.016129 + 0.016393 = 0.032522  (appears in both)
    # C: 1/62            ≈ 0.016129
    rankings = [["A", "B"], ["B", "C"]]
    result = rrf_merge(rankings)

    keys = [k for k, _ in result]
    scores = {k: s for k, s in result}

    # B must score highest (it appears in both lists)
    assert keys[0] == "B"
    assert scores["B"] == pytest.approx(1 / 62 + 1 / 61)
    assert scores["A"] == pytest.approx(1 / 61)
    assert scores["C"] == pytest.approx(1 / 62)


def test_rrf_merge_scenario_2_deterministic_fused_order():
    """Scenario 2: BM25-only symbol and embeddings-only symbol fused with RRF scores."""
    # bm25_rankings:      X=rank1, Y=rank2
    # embedding_rankings: Y=rank1, X=rank2
    # X: 1/(60+1) + 1/(60+2) = 1/61 + 1/62
    # Y: 1/(60+2) + 1/(60+1) = 1/62 + 1/61  — same score, tie-break by key asc
    rankings = [["X", "Y"], ["Y", "X"]]
    result = rrf_merge(rankings)

    keys = [k for k, _ in result]
    scores = {k: s for k, s in result}

    assert set(keys) == {"X", "Y"}
    # Both symbols appear; scores are 1/(60+1) + 1/(60+2)
    expected = 1 / 61 + 1 / 62
    assert scores["X"] == pytest.approx(expected)
    assert scores["Y"] == pytest.approx(expected)
    # Tie-break: key ascending → X before Y
    assert keys == ["X", "Y"]


# ---------------------------------------------------------------------------
# Item in one ranking only
# ---------------------------------------------------------------------------


def test_rrf_merge_item_in_one_ranking():
    """Symbol absent from the second ranking still appears with partial score."""
    rankings = [["A", "B", "C"], ["D", "E"]]
    result = rrf_merge(rankings)

    keys = [k for k, _ in result]
    scores = {k: s for k, s in result}

    # D appears only in ranking2 at rank 1
    assert "D" in keys
    assert scores["D"] == pytest.approx(1 / 61)
    # A appears only in ranking1 at rank 1
    assert "A" in keys
    assert scores["A"] == pytest.approx(1 / 61)
    # All 5 symbols must be present
    assert set(keys) == {"A", "B", "C", "D", "E"}


# ---------------------------------------------------------------------------
# Identical rankings
# ---------------------------------------------------------------------------


def test_rrf_merge_identical_rankings():
    """Identical rankings double each symbol's score; order is preserved."""
    rankings = [["P", "Q", "R"], ["P", "Q", "R"]]
    result = rrf_merge(rankings)

    keys = [k for k, _ in result]
    scores = {k: s for k, s in result}

    # Every symbol appears in both lists at the same rank → doubled score
    assert scores["P"] == pytest.approx(2 / 61)
    assert scores["Q"] == pytest.approx(2 / 62)
    assert scores["R"] == pytest.approx(2 / 63)
    # Descending score order → same order as the input
    assert keys == ["P", "Q", "R"]


# ---------------------------------------------------------------------------
# Empty inputs
# ---------------------------------------------------------------------------


def test_rrf_merge_empty_rankings_list():
    """Empty rankings list returns empty result without error."""
    assert rrf_merge([]) == []


def test_rrf_merge_single_empty_ranking():
    """Single empty list returns empty result without error."""
    assert rrf_merge([[]]) == []


def test_rrf_merge_all_empty_rankings():
    """Multiple empty lists return empty result without error."""
    assert rrf_merge([[], [], []]) == []


def test_rrf_merge_one_empty_one_nonempty():
    """One empty list and one non-empty list still produces results."""
    rankings = [[], ["X", "Y"]]
    result = rrf_merge(rankings)

    keys = [k for k, _ in result]
    scores = {k: s for k, s in result}

    assert set(keys) == {"X", "Y"}
    assert scores["X"] == pytest.approx(1 / 61)
    assert scores["Y"] == pytest.approx(1 / 62)


# ---------------------------------------------------------------------------
# Single ranking input
# ---------------------------------------------------------------------------


def test_rrf_merge_single_ranking():
    """Single ranking degrades gracefully — returns the RRF-scored ordering."""
    rankings = [["A", "B", "C"]]
    result = rrf_merge(rankings)

    keys = [k for k, _ in result]
    scores = {k: s for k, s in result}

    assert keys == ["A", "B", "C"]
    assert scores["A"] == pytest.approx(1 / 61)
    assert scores["B"] == pytest.approx(1 / 62)
    assert scores["C"] == pytest.approx(1 / 63)


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------


def test_rrf_merge_determinism():
    """Two consecutive runs return identical ordering."""
    rankings = [["X", "A", "M"], ["M", "X", "Z"], ["Z", "A"]]
    first = rrf_merge(rankings)
    second = rrf_merge(rankings)
    assert first == second


def test_rrf_merge_determinism_with_ties():
    """Tie-breaking by key name is stable across multiple calls."""
    # All three items appear exactly once at rank 1 in separate rankings
    rankings = [["C"], ["A"], ["B"]]
    run1 = rrf_merge(rankings)
    run2 = rrf_merge(rankings)
    # Tie resolved alphabetically
    assert [k for k, _ in run1] == ["A", "B", "C"]
    assert run1 == run2


# ---------------------------------------------------------------------------
# k parameter effect
# ---------------------------------------------------------------------------


def test_rrf_merge_k_parameter_smaller_k_inflates_top_rank():
    """Smaller k gives a higher score to rank-1 items relative to rank-2."""
    rankings = [["A"], ["B"]]

    result_k10 = rrf_merge(rankings, k=10)
    result_k60 = rrf_merge(rankings, k=60)

    scores_k10 = {k: s for k, s in result_k10}
    scores_k60 = {k: s for k, s in result_k60}

    # k=10: 1/(10+1) = 1/11 ≈ 0.0909
    # k=60: 1/(60+1) = 1/61 ≈ 0.0164
    assert scores_k10["A"] == pytest.approx(1 / 11)
    assert scores_k60["A"] == pytest.approx(1 / 61)
    assert scores_k10["A"] > scores_k60["A"]


def test_rrf_merge_k_parameter_custom_value():
    """Custom k produces expected scores for a two-ranking fusion."""
    rankings = [["A", "B"], ["B", "A"]]
    k = 5
    result = rrf_merge(rankings, k=k)
    scores = {key: s for key, s in result}

    # A: rank 1 in list1, rank 2 in list2 → 1/(5+1) + 1/(5+2) = 1/6 + 1/7
    assert scores["A"] == pytest.approx(1 / 6 + 1 / 7)
    # B: rank 2 in list1, rank 1 in list2 → same
    assert scores["B"] == pytest.approx(1 / 7 + 1 / 6)
    # Tie-break: A < B alphabetically → A first
    keys = [k for k, _ in result]
    assert keys == ["A", "B"]


# ---------------------------------------------------------------------------
# Return-type contract
# ---------------------------------------------------------------------------


def test_rrf_merge_returns_list_of_tuples():
    """Return value is a list of (key, float) tuples."""
    result = rrf_merge([["A", "B"]])
    assert isinstance(result, list)
    for item in result:
        assert isinstance(item, tuple)
        assert len(item) == 2
        key, score = item
        assert isinstance(score, float)


def test_rrf_merge_scores_are_positive():
    """All returned scores are strictly positive."""
    rankings = [["A", "B", "C"], ["C", "D"]]
    result = rrf_merge(rankings)
    for _, score in result:
        assert score > 0


def test_rrf_merge_descending_order():
    """Result is sorted in descending score order (ties: key ascending)."""
    rankings = [["A", "B", "C", "D"], ["D", "C", "B", "A"]]
    result = rrf_merge(rankings)

    scores = [s for _, s in result]
    # Each consecutive score must be >= the next
    for i in range(len(scores) - 1):
        assert scores[i] >= scores[i + 1]
