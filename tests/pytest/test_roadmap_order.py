"""Contract tests for scripts/mb_roadmap_order.py — S4 Task 1 (design.md C1/C2).

Every ICE-grammar branch and every comparator step (pin → score → created →
topic → rel) plus legacy_tail ordering, dependency respect and cycle handling
is exercised in isolation, so the roadmap-sync ordering contract is provable
without driving the whole shell script.
"""

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts"))

from mb_roadmap_order import (  # noqa: E402
    CYCLE_WARNING,
    has_priority,
    ice_is_block_style,
    parse_ice_score,
    parse_pin,
    priority_order,
)


def item(name, *, topic=None, rel=None, ice_score=None, pin=None, created=None, depends_on=None):
    return {
        "name": name,
        "topic": topic if topic is not None else name,
        "rel": rel if rel is not None else f"plans/{name}",
        "ice_score": ice_score,
        "pin": pin,
        "created": created,
        "depends_on": depends_on or [],
    }


def order(items, warn=None):
    return [it["name"] for it in priority_order(items, warn=warn)]


# ── parse_ice_score grammar ─────────────────────────────────────────────────


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("{impact: 8, confidence: 9, ease: 7}", 504),
        ("{ease: 7, impact: 8, confidence: 9}", 504),  # key order irrelevant
        ("{impact: 1, confidence: 1, ease: 1}", 1),
        ("{impact: 10, confidence: 10, ease: 10}", 1000),
    ],
)
def test_parse_ice_score_valid(raw, expected):
    assert parse_ice_score(raw) == expected


@pytest.mark.parametrize(
    "raw",
    [
        "",  # empty
        "   ",  # blank
        "432",  # plain-int (legacy draft)
        "{impact: 8, confidence: 9}",  # 2 keys
        "{impact: 8, confidence: 9, ease: 7, extra: 2}",  # 4 keys
        "{impact: 8, impact: 9, ease: 7}",  # duplicate key
        "{impact: 8, confidence: 9, weight: 7}",  # wrong key
        "{impact: 0, confidence: 9, ease: 7}",  # below range
        "{impact: 11, confidence: 9, ease: 7}",  # above range
        "{impact: 8.5, confidence: 9, ease: 7}",  # non-integer
        "{impact: eight, confidence: 9, ease: 7}",  # non-numeric
        "[8, 9, 7]",  # list, not mapping
        "{}",  # empty mapping
    ],
)
def test_parse_ice_score_invalid(raw):
    assert parse_ice_score(raw) is None


# ── ice_is_block_style ──────────────────────────────────────────────────────


def test_ice_is_block_style_true():
    text = "---\ntopic: x\nice:\n  impact: 8\n  confidence: 9\n  ease: 7\n---\n# X\n"
    assert ice_is_block_style(text) is True


def test_ice_is_block_style_false_for_flow():
    text = "---\ntopic: x\nice: {impact: 8, confidence: 9, ease: 7}\n---\n# X\n"
    assert ice_is_block_style(text) is False


def test_ice_is_block_style_false_without_frontmatter():
    assert ice_is_block_style("# just a heading\n") is False


# ── parse_pin ───────────────────────────────────────────────────────────────


@pytest.mark.parametrize("raw,expected", [("1", 1), ("42", 42), ("007", 7)])
def test_parse_pin_valid(raw, expected):
    assert parse_pin(raw) == expected


@pytest.mark.parametrize("raw", ["", "0", "-1", "abc", "1.5", "  "])
def test_parse_pin_invalid(raw):
    assert parse_pin(raw) is None


# ── Oversized integers must degrade, not crash (C1: no input crashes sync) ────
# A 5000-digit run passes the `^-?\d+$` regex but blows past CPython's
# int_max_str_digits (default 4300) on int() — the parser must return None
# (invalid), never let the ValueError escape and abort roadmap-sync.


def test_parse_ice_score_oversized_component_is_invalid_not_crash():
    big = "5" * 5000
    assert parse_ice_score("{impact: " + big + ", confidence: 9, ease: 7}") is None


def test_parse_pin_oversized_is_invalid_not_crash():
    assert parse_pin("5" * 5000) is None


# ── has_priority ────────────────────────────────────────────────────────────


def test_has_priority_variants():
    assert has_priority(item("a", ice_score=100)) is True
    assert has_priority(item("a", pin=2)) is True
    assert has_priority(item("a")) is False  # neither ⇒ legacy_tail


# ── Comparator steps (each isolated) ────────────────────────────────────────


def test_step_pin_beats_score():
    items = [item("hi", ice_score=999), item("pinned", ice_score=1, pin=1)]
    assert order(items) == ["pinned", "hi"]


def test_step_score_descending_without_pin():
    items = [item("low", ice_score=100), item("high", ice_score=500), item("mid", ice_score=300)]
    assert order(items) == ["high", "mid", "low"]


def test_step_created_ascending_is_decisive_over_later_keys():
    # Isolation: the earlier `created` must win even though its topic AND rel
    # both sort LATER — so dropping `created` from the comparator would flip the
    # result to the topic/rel winner. Equal pin+score up to this step.
    items = [
        item("winner", topic="zzz", rel="plans/zzz.md", ice_score=400, created="2026-01-01"),
        item("loser", topic="aaa", rel="plans/aaa.md", ice_score=400, created="2026-02-01"),
    ]
    assert order(items) == ["winner", "loser"]


def test_step_topic_ascending_is_decisive_over_rel():
    # Isolation: the earlier `topic` must win even though its rel sorts LATER, so
    # dropping `topic` would flip the result to the rel winner. Equal
    # pin+score+created up to this step.
    items = [
        item("winner", topic="alpha", rel="plans/zzz.md", ice_score=400, created="2026-01-01"),
        item("loser", topic="zeta", rel="plans/aaa.md", ice_score=400, created="2026-01-01"),
    ]
    assert order(items) == ["winner", "loser"]


def test_step_rel_ascending_as_final_tiebreak():
    # identical score/created/topic ⇒ only rel separates them (total order)
    items = [
        item("b", topic="same", rel="plans/b.md", ice_score=400, created="2026-01-01"),
        item("a", topic="same", rel="plans/a.md", ice_score=400, created="2026-01-01"),
    ]
    assert order(items) == ["a", "b"]


def test_missing_created_sorts_last_among_equal_score():
    # Isolation: a real `created` beats a missing one (default 9999-12-31) even
    # when the dated item's topic AND rel sort LATER — dropping `created` would
    # let the topic/rel winner (the undated item) jump ahead.
    items = [
        item("nodate", topic="aaa", rel="plans/aaa.md", ice_score=400),
        item("dated", topic="zzz", rel="plans/zzz.md", ice_score=400, created="2026-01-01"),
    ]
    assert order(items) == ["dated", "nodate"]


def test_pin_without_ice_participates():
    items = [item("scored", ice_score=500), item("pinonly", pin=1)]
    assert order(items) == ["pinonly", "scored"]


def test_duplicate_pin_decided_by_score():
    items = [item("x", ice_score=300, pin=1), item("y", ice_score=500, pin=1)]
    assert order(items) == ["y", "x"]


def test_ice_confirmed_does_not_affect_order():
    # priority_order never reads ice_confirmed; adding it must not perturb order.
    a = item("a", ice_score=432)
    a["ice_confirmed"] = False
    b = item("b", ice_score=504)
    b["ice_confirmed"] = True
    assert order([a, b]) == ["b", "a"]


# ── legacy_tail + dependencies + cycles ─────────────────────────────────────


def test_no_ice_items_keep_original_relative_order_in_tail():
    items = [
        item("scored", ice_score=500),
        item("tail_b"),  # no ice/pin — original order among tail preserved
        item("tail_a"),
    ]
    assert order(items) == ["scored", "tail_b", "tail_a"]


def test_dependency_emitted_before_dependent():
    # names carry `.md` (as the real script's path.name does) so depends_on resolves
    items = [
        item("a.md", ice_score=999, depends_on=["c.md"]),
        item("b.md", ice_score=1),
        item("c.md", ice_score=1),
    ]
    result = order(items)
    assert result.index("c.md") < result.index("a.md")


def test_cycle_warns_with_first_remaining_and_keeps_stable_order():
    msgs = []
    items = [
        item("a.md", ice_score=432, depends_on=["b.md"]),
        item("b.md", ice_score=504, depends_on=["a.md"]),
    ]
    result = order(items, warn=msgs.append)
    # cycle ⇒ remainder emitted in original order, warning names the first
    assert result == ["a.md", "b.md"]
    assert msgs == [CYCLE_WARNING.format(name="a.md")]


# ── Shared group-ordering contract fixture (design C2, R2-003-R3) ────────────
# The single physical fixture tests/fixtures/svp_group_ordering.json is the
# cross-consumer authority: BOTH the S4 roadmap render and S3's
# mb-work-resolve.sh --group order via priority_order, so its four canonical
# cases must map to the fixture's expected topic order here.

_ORDERING_FIXTURE = os.path.join(
    os.path.dirname(__file__), "..", "fixtures", "svp_group_ordering.json"
)


def _member_item(m):
    return {
        "name": m["topic"],
        "topic": m["topic"],
        "rel": f"specs/{m['topic']}/requirements.md",
        "ice_score": parse_ice_score(m["ice"]) if m.get("ice") else None,
        "pin": parse_pin(m["pin"]) if m.get("pin") else None,
        "created": m.get("created"),
        "depends_on": m.get("blocked_by") or [],
    }


def _load_ordering_cases():
    with open(_ORDERING_FIXTURE, encoding="utf-8") as fh:
        return json.load(fh)["cases"]


@pytest.mark.parametrize("case", _load_ordering_cases(), ids=lambda c: c["name"])
def test_svp_group_ordering_fixture_shared_comparator(case):
    items = [_member_item(m) for m in case["members"]]
    got = [it["topic"] for it in priority_order(items)]
    assert got == case["expected_order"]
