"""Project Key rules block in delta mode (AGR-083): the project CLAUDE.md / AGENTS.md carries only
what the project changes against the user-level selection; hosts with a global instructions file
already load the full block. `render_block(..., base=None)` stays the full block."""

from __future__ import annotations

import pytest

from memory_bank_skill.key_rules import load_catalog, render_block, resolve_effective

CATALOG = load_catalog()
POINTER = "Details: `RULES.md`."
TINY_BUDGET = 300


def _delta(project: dict | None, user: dict | None = None) -> str:
    return render_block(resolve_effective(user, project), POINTER, base=resolve_effective(user, None))


def _rule_lines(block: str) -> list[str]:
    return [line for line in block.splitlines() if line.startswith("- ")]


@pytest.mark.parametrize("user", [None, {"quality": {"tdd": "off"}, "key_rules": {"custom": ["user rule"]}}])
def test_delta_no_project_differences_renders_tiny_block_with_pointer(user: dict | None) -> None:
    block = _delta(None, user)
    assert block.startswith("<!-- mb-key-rules:start -->\n## Key rules\n")
    assert "Global Key rules apply" in block and POINTER in block
    assert _rule_lines(block) == []
    assert len(block.encode("utf-8")) <= TINY_BUDGET


def test_delta_project_profile_equal_to_user_has_no_differences() -> None:
    same = {"quality": {"testing_trophy": "off"}}
    assert _rule_lines(_delta(same, same)) == []


def test_delta_added_rule_carries_its_full_text_only() -> None:
    # Every plain catalog rule is on by default: a project adds one the user turned off.
    user = {"key_rules": {"disabled": ["deletion-over-addition"]}, "quality": {"principles": {"kiss": "off"}}}
    block = _delta({"key_rules": {"enabled": ["deletion-over-addition"]}, "quality": {"principles": {"kiss": "on"}}},
                   user)
    assert "- Deletion over addition, boring over clever" in block
    assert "- KISS: the simplest working solution wins" in block
    assert "TDD: new logic" not in block and "DRY:" not in block
    assert "Off in this project" not in block and "Replaces" not in block


def test_delta_disabled_rule_listed_by_id_without_its_text() -> None:
    block = _delta({"quality": {"testing_trophy": "off", "principles": {"kiss": "off"}}})
    assert "- Off in this project: `kiss`, `testing-trophy`." in block
    assert "Testing Trophy:" not in block and "KISS:" not in block


def test_delta_custom_rules_only_the_project_ones() -> None:
    block = _delta({"key_rules": {"custom": ["no ORM in this repo"]}}, {"key_rules": {"custom": ["user rule"]}})
    assert "- no ORM in this repo (your rule)" in block
    assert "user rule" not in block


@pytest.mark.parametrize(
    ("project", "present", "absent", "replaced"),
    [
        ({"quality": {"tdd": "on"}}, "TDD: new logic", "standard+ tier", "tdd"),
        ({"quality": {"coverage": {"enabled": True, "overall": 80}}}, "Coverage: overall 80%+", "85%", None),
        ({"architecture": "hexagonal"}, "Hexagonal:", "Clean Architecture", "architecture"),
        ({"architecture": ["clean", "fsd"]}, "Clean Architecture:", "DDD folders:", "architecture"),
    ],
)
def test_delta_changed_quality_setting_renders_new_text_and_names_the_replaced_line(
        project: dict, present: str, absent: str, replaced: str | None) -> None:
    block = _delta(project)
    assert present in block and absent not in block
    if replaced:
        assert f"- Replaces the global line: `{replaced}`." in block


def test_delta_changed_setting_against_user_value_not_against_defaults() -> None:
    user = {"quality": {"coverage": {"enabled": True, "overall": 90}}}
    block = _delta({"quality": {"coverage": {"overall": 80}}}, user)
    assert "Coverage: overall 80%+" in block
    assert "- Replaces the global line: `coverage`." in block


def test_delta_strict_discipline_adds_strict_lines_and_turns_off_the_calm_one() -> None:
    block = _delta({"discipline": "strict"})
    for line in CATALOG["strict_lines"]:
        assert f"- {line}" in block
    assert "`targeted-verification`" in block and 'Evidence before "done"' not in block


def test_delta_calm_project_under_strict_user_turns_strict_off() -> None:
    block = _delta({"discipline": "calm"}, {"discipline": "strict"})
    assert 'Evidence before "done"' in block and "`strict-discipline`" in block
    assert "Strict:" not in block


def test_delta_two_overrides_stays_small() -> None:
    block = _delta({"quality": {"testing_trophy": "off"}, "key_rules": {"custom": ["no ORM in this repo"]}})
    assert block.splitlines()[1] == "## Key rules — project overrides"
    assert block.rstrip("\n").endswith(f"{POINTER}\n<!-- mb-key-rules:end -->")
    assert len(block.encode("utf-8")) <= 400


def test_full_mode_unchanged_when_no_base() -> None:
    block = render_block(resolve_effective(None, {"quality": {"testing_trophy": "off"}}), POINTER)
    assert "TDD: new logic" in block and "Testing Trophy:" not in block
    assert "Off in this project" not in block and "Global Key rules apply" not in block
