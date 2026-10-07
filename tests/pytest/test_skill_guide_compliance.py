"""Compliance gate: the memory-bank skill vs Anthropic skill-authoring rules.

Deterministic (no network, no LLM). Each check is a pure helper in
`_skill_guide_checks.py`; fixtures prove red/green, `test_repo_*` run it on the
real skill (plan 2026-10-06_fix_anthropic-skill-guide-compliance-sprint1-skill).
"""

from __future__ import annotations

from pathlib import Path

import pytest
from _skill_guide_checks import (
    check_command_descriptions,
    check_files_mentioned,
    check_reference_toc,
    check_skill_frontmatter,
    check_skill_paths_exist,
    check_skill_size,
    github_slug,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
GOOD_DESC = "Project memory. Use when the project has a .memory-bank/ directory."


def _write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _skill(
    root: Path, name: str = "memory-bank", desc: str = GOOD_DESC, body: str = "# Skill\n"
) -> None:
    _write(root, "SKILL.md", f'---\nname: {name}\ndescription: "{desc}"\n---\n{body}')


def _long_doc(head: str, sections: tuple[str, ...] = ("Alpha", "Beta")) -> str:
    body = "".join(f"## {s}\n" + "text\n" * 60 for s in sections)
    return f"# Doc\n\n{head}\n{body}"


# --- check 1: SKILL.md frontmatter -------------------------------------------


@pytest.mark.parametrize(
    ("name", "desc", "expected"),
    [
        ("Memory_Bank", GOOD_DESC, "name: invalid format 'Memory_Bank'"),
        ("claude-memory", GOOD_DESC, "name: reserved word in 'claude-memory'"),
        ("memory-bank", "x" * 1025, "description: length 1025 outside 1..1024"),
        ("memory-bank", "Uses <tag> markup. Use when asked.", "description: contains XML tag"),
        ("memory-bank", "Project memory for agents.", "description: no 'when' marker"),
        ("memory-bank", "I keep memory. Use when asked.", "description: not third person"),
    ],
    ids=["bad-name", "reserved-word", "long-desc", "xml-tag", "no-when", "first-person"],
)
def test_skill_frontmatter_violation_reported(tmp_path, name, desc, expected):
    _skill(tmp_path, name=name, desc=desc)
    assert expected in check_skill_frontmatter(tmp_path)


def test_skill_frontmatter_compliant_no_violations(tmp_path):
    _skill(tmp_path)
    assert check_skill_frontmatter(tmp_path) == []


def test_repo_skill_frontmatter_compliant():
    assert check_skill_frontmatter(REPO_ROOT) == []


# --- check 2: SKILL.md size --------------------------------------------------


def test_skill_size_body_over_limit_reported(tmp_path):
    _skill(tmp_path, body="line\n" * 301)
    assert check_skill_size(tmp_path) == ["SKILL.md body: 301 lines > 300"]


def test_skill_size_bytes_over_limit_reported(tmp_path):
    _skill(tmp_path, body="x" * 36500 + "\n")
    assert any(v.endswith("bytes > 36000") for v in check_skill_size(tmp_path))


def test_skill_size_within_limits_no_violations(tmp_path):
    _skill(tmp_path, body="line\n" * 300)
    assert check_skill_size(tmp_path) == []


def test_repo_skill_size_within_limits():
    assert check_skill_size(REPO_ROOT) == []


# --- check 3: table of contents in long references ---------------------------


@pytest.mark.parametrize(
    ("head", "expected"),
    [
        ("", "references/big.md: 125 lines, no table of contents"),
        (
            "## Contents\n- [Alpha](#alpha)\n- [Gamma](#gamma)",
            "references/big.md: broken ToC anchor #gamma",
        ),
    ],
    ids=["no-toc", "broken-anchor"],
)
def test_reference_toc_violation_reported(tmp_path, head, expected):
    _write(tmp_path, "references/big.md", _long_doc(head))
    assert expected in check_reference_toc(tmp_path)


@pytest.mark.parametrize(
    "head",
    ["## Contents\n- [Alpha](#alpha)\n- [Beta](#beta)", "## Оглавление\n- [Alpha](#alpha)"],
    ids=["english", "russian"],
)
def test_reference_toc_present_no_violations(tmp_path, head):
    _write(tmp_path, "references/big.md", _long_doc(head))
    _write(tmp_path, "references/short.md", "# Short\n" + "text\n" * 50)
    assert check_reference_toc(tmp_path) == []


def test_github_slug_strips_punctuation_keeps_unicode():
    assert github_slug("Stage 2: `SKILL.md` — Обзор_v2!") == "stage-2-skillmd--обзор_v2"


def test_repo_reference_toc_present():
    assert check_reference_toc(REPO_ROOT) == []


# --- check 4: every skill file mentioned in SKILL.md --------------------------


def test_files_mentioned_directory_only_reported(tmp_path):
    _skill(tmp_path, body="See references/ and rules/RULES.md.\n")
    _write(tmp_path, "references/a.md", "# A\n")
    _write(tmp_path, "rules/RULES.md", "# R\n")
    assert check_files_mentioned(tmp_path) == ["references/a.md: not mentioned in SKILL.md"]


def test_files_mentioned_all_listed_no_violations(tmp_path):
    _skill(tmp_path, body="references/a.md, flow-templates/patterns/p.md\n")
    _write(tmp_path, "references/a.md", "# A\n")
    _write(tmp_path, "flow-templates/patterns/p.md", "# P\n")
    assert check_files_mentioned(tmp_path) == []


def test_repo_files_mentioned_in_skill():
    assert check_files_mentioned(REPO_ROOT) == []


# --- check 5: paths referenced from SKILL.md exist ----------------------------


def test_skill_paths_missing_file_reported(tmp_path):
    _skill(tmp_path, body="Run `scripts/gone.sh`, then [ok](scripts/ok.sh).\n")
    _write(tmp_path, "scripts/ok.sh", "")
    assert check_skill_paths_exist(tmp_path) == [
        "scripts/gone.sh: referenced in SKILL.md but missing on disk"
    ]


def test_skill_paths_existing_templated_or_foreign_no_violations(tmp_path):
    body = (
        "`scripts/ok.sh`, `references/<topic>.md`, `agents/*.md`, `hooks/{a,b}.sh`,\n"
        "`.cursor/rules/x.mdc`, `~/.claude/hooks/y.sh`, prose about local hooks/configs.\n"
    )
    _skill(tmp_path, body=body)
    _write(tmp_path, "scripts/ok.sh", "")
    assert check_skill_paths_exist(tmp_path) == []


def test_repo_skill_paths_exist():
    assert check_skill_paths_exist(REPO_ROOT) == []


# --- check 6: command descriptions --------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("# /mb x\n", "commands/x.md: missing frontmatter"),
        ("---\ndescription: Do x\n---\n", "commands/x.md: description has no 'when' marker"),
        ("---\ndescription:\n---\n", "commands/x.md: description length 0 outside 1..1024"),
        (
            "---\ndescription: Do x. Use when asked.\ndisable-model-invocation: false\n---\n",
            "commands/x.md: disable-model-invocation is forbidden (AGR-061)",
        ),
    ],
    ids=["no-frontmatter", "no-when", "empty", "disable-invocation"],
)
def test_command_description_violation_reported(tmp_path, text, expected):
    _write(tmp_path, "commands/x.md", text)
    assert check_command_descriptions(tmp_path) == [expected]


def test_command_description_compliant_no_violations(tmp_path):
    _write(tmp_path, "commands/x.md", "---\ndescription: 'Do x. Triggers on /mb x.'\n---\n")
    assert check_command_descriptions(tmp_path) == []


def test_repo_command_descriptions_compliant():
    assert check_command_descriptions(REPO_ROOT) == []
