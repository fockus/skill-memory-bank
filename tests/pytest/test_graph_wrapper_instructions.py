"""Agent instructions teach the same graph command the hooks print: `mb-graph.sh`.

graph-semantic-adoption Stage 4: the nudge and the SessionStart quick-ref say
`mb-graph.sh who-calls <Sym>`. If the instructions an agent reads (tooling-core
routing table, research agent, SKILL.md, /mb command, rules) still lead with the
long `python3 … mb-graph-query.py impact --graph … --symbol …` form, the agent has
two vocabularies — and on hosts without hooks (Codex …) it never learns the
wrapper at all. The long forms may stay as a reference for flags the wrapper does
not carry (`--json`, `--file`, `catchup`, `summary`), but never as a Claude-only
`~/.claude/...` invocation.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

LEAD_FILES = (
    "agents/mb-tooling-core.md",
    "agents/mb-research.md",
    "agents/mb-codebase-mapper.md",
    "agents/mb-engineering-core.md",
    "SKILL.md",
    "commands/mb.md",
    "commands/discuss.md",
    "commands/groom.md",
    "references/code-graph.md",
    "references/claude-md-template.md",
    "rules/CLAUDE-GLOBAL.md",
    "rules/RULES.md",
)

INSTRUCTION_FILES = sorted(
    p for d in ("agents", "commands", "references", "rules") for p in (REPO_ROOT / d).rglob("*.md")
) + [REPO_ROOT / "SKILL.md"]

CLAUDE_ONLY_GRAPH_RUN = re.compile(
    r"(bash|python3) ~/\.claude/\S*/(mb-graph-query\.py|mb-semantic-search\.py|mb-graph\.sh)"
)


@pytest.mark.parametrize("rel", LEAD_FILES)
def test_instruction_file_names_the_graph_wrapper(rel: str) -> None:
    text = (REPO_ROOT / rel).read_text(encoding="utf-8")
    assert "mb-graph.sh" in text, f"{rel} must teach mb-graph.sh (the command hooks print)"


@pytest.mark.parametrize("path", INSTRUCTION_FILES, ids=lambda p: str(p.relative_to(REPO_ROOT)))
def test_graph_and_search_are_never_run_through_a_claude_only_path(path: Path) -> None:
    offending = [
        f"{n}: {line.strip()[:120]}"
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if CLAUDE_ONLY_GRAPH_RUN.search(line)
    ]
    assert not offending, 'run graph/search via "$SKILL_DIR"/scripts/mb-graph.sh:\n' + "\n".join(
        offending
    )


def test_tooling_core_routing_rows_lead_with_the_wrapper() -> None:
    text = (REPO_ROOT / "agents" / "mb-tooling-core.md").read_text(encoding="utf-8")
    for cmd in ("who-calls", "impact", "tests", "search", "status"):
        assert f'"$SKILL_DIR"/scripts/mb-graph.sh {cmd}' in text, f"routing row for {cmd}"


# ── A bare "$SKILL_DIR" is empty in a fresh agent shell → `/scripts/mb-graph.sh:
# No such file` (rc 127). Every file that runs the wrapper through it must assign it.
SKILL_DIR_WRAPPER_RUN = re.compile(r'\$SKILL_DIR"?/scripts/mb-graph\.sh')
SKILL_DIR_ASSIGN = re.compile(r'SKILL_DIR="\$\{MB_SKILLS_ROOT:-\$\{SKILL_DIR')


@pytest.mark.parametrize("path", INSTRUCTION_FILES, ids=lambda p: str(p.relative_to(REPO_ROOT)))
def test_files_running_the_wrapper_via_skill_dir_assign_it(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if not SKILL_DIR_WRAPPER_RUN.search(text):
        return
    assert SKILL_DIR_ASSIGN.search(text), (
        f"{path.name} runs mb-graph.sh via $SKILL_DIR but never assigns it — add "
        'SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"'
    )


@pytest.mark.parametrize("rel", ("agents/mb-tooling-core.md", "agents/mb-research.md"))
def test_dispatched_agents_bind_skill_dir_from_the_skill_path_line(rel: str) -> None:
    # /mb work puts `Skill path: <SKILL_DIR>` into every dispatched prompt
    # (commands/work.md); the agent must know that line IS the value.
    text = (REPO_ROOT / rel).read_text(encoding="utf-8")
    assert "Skill path:" in text, f"{rel} must bind SKILL_DIR to the prompt's `Skill path:` line"


# The long structural form may appear in lead files only as an explicit
# reference: the `(= …)` equivalence column and the `--file` row of code-graph.md.
# catchup / summary / explain are not matched (the wrapper does not carry them).
STRUCTURAL_LONG_RUN = re.compile(r'mb-graph-query\.py"? (impact|neighbors|tests)\b')
ALLOWED_LONG_FORM = {
    "references/code-graph.md": ("(= `mb-graph-query.py ", "--graph $G --file path"),
}


@pytest.mark.parametrize("rel", LEAD_FILES)
def test_lead_files_do_not_run_the_long_structural_form(rel: str) -> None:
    allowed = ALLOWED_LONG_FORM.get(rel, ())
    offending = [
        f"{n}: {line.strip()[:120]}"
        for n, line in enumerate((REPO_ROOT / rel).read_text(encoding="utf-8").splitlines(), 1)
        if STRUCTURAL_LONG_RUN.search(line) and not any(a in line for a in allowed)
    ]
    assert not offending, f"{rel} runs the long form; use mb-graph.sh:\n" + "\n".join(offending)
