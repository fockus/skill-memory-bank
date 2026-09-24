"""Commands run bundled scripts through `$SKILL_DIR`, never a Claude-only path.

On Codex, OpenCode and pi the skill loads from its own directory; a command that
runs `bash ~/.claude/skills/memory-bank/scripts/...` only works there because
`install.sh` also creates the Claude alias. Every command file that runs a
bundled helper through `"$SKILL_DIR"` must define it (the "Skill bundle root"
block from `commands/groom.md`); `commands/mb.md` defines it at the top.

Prose that merely names a `~/.claude/...` path (e.g. `/mb upgrade` docs) is fine.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
COMMAND_FILES = sorted((REPO_ROOT / "commands").glob("*.md"))
HARDCODED_RUN = re.compile(r"(bash|python3) ~/\.claude/")
SKILL_DIR_DEF = 'SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"'


@pytest.mark.parametrize(
    ("line", "flagged"),
    [
        ("bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh", True),
        ("eval \"$(bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh)\"", True),
        ("python3 ~/.claude/skills/memory-bank/scripts/mb-graph-query.py status", True),
        ("checks that `~/.claude/skills/skill-memory-bank` is a git repo", False),
        ("bash \"$SKILL_DIR\"/scripts/mb-metrics.sh", False),
    ],
    ids=["bash", "eval-bash", "python3", "upgrade-prose", "skill-dir"],
)
def test_hardcoded_run_regex_flags_invocations_not_prose(line: str, flagged: bool) -> None:
    assert bool(HARDCODED_RUN.search(line)) is flagged


@pytest.mark.parametrize("path", COMMAND_FILES, ids=lambda p: p.name)
def test_commands_run_no_hardcoded_claude_skill_path(path: Path) -> None:
    offending = [
        f"{path.name}:{n}: {line.strip()}"
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if HARDCODED_RUN.search(line)
    ]
    assert not offending, (
        "run bundled scripts through \"$SKILL_DIR\", not a Claude-only path:\n"
        + "\n".join(offending)
    )


@pytest.mark.parametrize(
    "path", [p for p in COMMAND_FILES if p.name != "mb.md"], ids=lambda p: p.name
)
def test_commands_using_skill_dir_define_it(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if '"$SKILL_DIR"' not in text:
        return
    assert SKILL_DIR_DEF in text, (
        f"{path.name} runs helpers via \"$SKILL_DIR\" but never defines it — "
        "add the 'Skill bundle root' block from commands/groom.md"
    )
