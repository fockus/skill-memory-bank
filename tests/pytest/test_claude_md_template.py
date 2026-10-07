"""references/claude-md-template.md generates the project CLAUDE.md (`/mb init --full`).

Anthropic memory guidance: CLAUDE.md stays short, holds only per-session facts
(commands, conventions, layout) and must not contradict other loaded instructions.
Engineering rules already arrive via the global ~/.claude/CLAUDE.md, so the
template must not restate them, hard-code a response language, or duplicate the
status-line rule.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = REPO_ROOT / "references" / "claude-md-template.md"
MB_COMMAND = REPO_ROOT / "commands" / "mb.md"

HEADING = re.compile(r"^(#{1,6}) (.+?)\s*$")


def _template() -> str:
    return TEMPLATE.read_text(encoding="utf-8")


def _body() -> str:
    """Template body after the preamble divider = what lands in the generated CLAUDE.md."""
    _, sep, body = _template().partition("\n---\n")
    assert sep, "template must keep its preamble divider"
    return body


def _headings(text: str) -> list[tuple[int, str]]:
    out, fenced = [], False
    for line in text.splitlines():
        if line.startswith("```"):
            fenced = not fenced
            continue
        m = None if fenced else HEADING.match(line)
        if m:
            out.append((len(m.group(1)), m.group(2)))
    return out


@pytest.mark.parametrize(
    "forbidden",
    ["respond in English", "Language —", "**Language**", "MANDATORY", "[MEMORY BANK: ACTIVE]", "jq -r"],
)
def test_template_body_has_no_conflicting_or_duplicated_instruction(forbidden: str) -> None:
    assert forbidden not in _template()


@pytest.mark.parametrize(
    "prefix",
    ["> **TDD**", "> **SOLID", "> **DRY", "> **Contract-First**", "> **Testing Trophy**", "> **Coverage**"],
)
def test_template_does_not_restate_global_engineering_rules(prefix: str) -> None:
    assert not [line for line in _template().splitlines() if line.startswith(prefix)]


def test_commands_section_has_tooling_placeholders_before_architecture() -> None:
    body = _body()
    assert "\n## Commands\n" in body and "\n## Architecture\n" in body
    commands = body.split("\n## Commands\n", 1)[1].split("\n## ", 1)[0]
    for ph in ("{BUILD_CMD}", "{TEST_CMD}", "{LINT_CMD}"):
        assert ph in commands
    assert body.index("\n## Commands\n") < body.index("\n## Architecture\n")


def test_headings_never_skip_a_level_downward() -> None:
    prev = 1
    for level, title in _headings(_body()):
        assert level <= prev + 1, f"heading '{title}' skips from h{prev} to h{level}"
        prev = level


@pytest.mark.parametrize(
    "title",
    ["Languages", "Runtime", "Frameworks", "Key Dependencies", "Configuration",
     "Naming Patterns", "Code Style", "Pattern Overview"],
)
def test_stack_subsections_are_not_top_level(title: str) -> None:
    assert (2, title) not in _headings(_body())


def test_template_body_fits_eighty_lines() -> None:
    assert len(_body().strip("\n").splitlines()) <= 80


def test_mb_init_step4_required_sections_match_template() -> None:
    step4 = MB_COMMAND.read_text(encoding="utf-8").split("#### Step 4: Generate `CLAUDE.md`", 1)[1]
    step4 = step4.split("\n---\n", 1)[0]
    required = step4.split("Required sections", 1)[1]
    listed = re.findall(r"^- \*\*(.+?)\*\*", required, re.M)
    template_sections = [t for lvl, t in _headings(_body()) if lvl == 2]
    assert listed == template_sections
