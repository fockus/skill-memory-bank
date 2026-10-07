"""Quality step of the interactive onboarding (`mb-rules.sh init --interactive`, install.sh Step 5.5)."""

from __future__ import annotations

import io

import pytest

from memory_bank_skill.key_rules import load_catalog
from memory_bank_skill.key_rules_edit import Selection
from memory_bank_skill.key_rules_prompt import quality_prompt


def _run(answers: str, data: dict | None = None) -> tuple[Selection, str]:
    sel = Selection(load_catalog(), data or {}, None)
    out = io.StringIO()
    quality_prompt(sel, "user", io.StringIO(answers), out)
    return sel, out.getvalue()


def test_quality_prompt_answers_set_architecture_tdd_trophy_coverage() -> None:
    sel, _ = _run("2,3\noff\noff\n80/95/70\n")
    assert sel.architecture == ["hexagonal", "modular-monolith"]
    assert sel.quality["tdd"] == "off"
    assert sel.quality["testing_trophy"] == "off"
    assert sel.quality["coverage"] == {"enabled": True, "overall": 80, "core": 95, "infra": 70}


def test_quality_prompt_enter_keeps_everything_and_shows_current() -> None:
    data = {"architecture": ["fsd"], "quality": {"tdd": "on", "coverage": {"enabled": True, "overall": 90}}}
    sel, out = _run("\n\n\n\n", data)
    assert sel.architecture == ["fsd"]
    assert sel.quality == data["quality"]
    assert "current: fsd" in out
    assert "current: on" in out
    assert "current: 90/95/70" in out


def test_quality_prompt_custom_architecture_with_numbers() -> None:
    sel, _ = _run("1 c layers talk via events only\n\n\n\n")
    assert sel.architecture == ["clean", {"custom": "layers talk via events only"}]


def test_quality_prompt_custom_architecture_alone_is_a_list() -> None:
    sel, _ = _run("c my layering\n\n\n\n")
    assert sel.architecture == [{"custom": "my layering"}]


@pytest.mark.parametrize(("answers", "check"), [
    ("9\n4\n\n\n\n", lambda s: s.architecture == "microservices"),
    ("\nmaybe\nsmall+\n\n\n", lambda s: s.quality == {"tdd": "small+"}),
    ("\n\n\n180/95/70\n50/50/50\n", lambda s: s.quality["coverage"]["overall"] == 50),
])
def test_quality_prompt_invalid_answer_reasks_once(answers: str, check) -> None:
    sel, out = _run(answers)
    assert check(sel)
    assert "  ! " in out


@pytest.mark.parametrize("answers", ["x\ny\n\n\n\n", "\non off\nbad\n\n\n", "\n\n\n1/2\n1/2/300\n"])
def test_quality_prompt_two_invalid_answers_keep_current(answers: str) -> None:
    sel, out = _run(answers, {"architecture": "ddd"})
    assert sel.architecture == "ddd"
    assert sel.quality == {}
    assert "keeping the current value" in out


def test_quality_prompt_eof_keeps_current() -> None:
    sel, _ = _run("")
    assert sel.architecture is None
    assert sel.quality == {}
