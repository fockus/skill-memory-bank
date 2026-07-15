"""Doc-vs-reality contract tests for SKILL.md and README.md.

Locks in the invariant that documented counts/tables match the actual file
tree under commands/, scripts/, agents/, hooks/, references/.

These tests are deliberately strict: any new command/script/agent/hook
must be reflected in the public-facing docs in the same commit, otherwise
CI fails. Antidote to the "declarative intent != contract" lesson recorded
in `.memory-bank/lessons.md` (2026-04-25).
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_MD = REPO_ROOT / "SKILL.md"
README_MD = REPO_ROOT / "README.md"
COMMANDS_DIR = REPO_ROOT / "commands"
SCRIPTS_DIR = REPO_ROOT / "scripts"
AGENTS_DIR = REPO_ROOT / "agents"
HOOKS_DIR = REPO_ROOT / "hooks"
REFERENCES_DIR = REPO_ROOT / "references"
INSTALL_SH = REPO_ROOT / "install.sh"
SESSION_MEMORY_MD = REFERENCES_DIR / "session-memory.md"

CODE_SPAN_FIRST_COL_RE = re.compile(r"^\|\s*`([^`]+)`")


def _filesystem_basenames(directory: Path, suffixes: tuple[str, ...]) -> set[str]:
    """Return basenames (without extension) for files matching any suffix."""
    out: set[str] = set()
    for path in directory.iterdir():
        if not path.is_file():
            continue
        for suffix in suffixes:
            if path.name.endswith(suffix):
                out.add(path.name)
                break
    return out


def _section_lines(md_text: str, heading_prefix: str) -> list[str]:
    """Return lines belonging to the section starting with given heading prefix.

    Stops at the next heading of the same or higher level (any line starting
    with '## '). Heading match is by `startswith` to be robust to trailing
    qualifiers (e.g. "## Agents — subagents (sonnet)").
    """
    lines = md_text.splitlines()
    result: list[str] = []
    capturing = False
    for line in lines:
        if line.startswith(heading_prefix):
            capturing = True
            continue
        if capturing and line.startswith("## "):
            break
        if capturing:
            result.append(line)
    return result


def _table_first_column_codespans(section_lines: list[str]) -> set[str]:
    """Extract first-column backtick-quoted tokens from markdown table rows.

    For a row like '| `mb-context.sh [--deep]` | description |' returns
    'mb-context.sh' (everything before first whitespace inside the codespan).
    """
    out: set[str] = set()
    for line in section_lines:
        m = CODE_SPAN_FIRST_COL_RE.match(line)
        if not m:
            continue
        token = m.group(1).split()[0]
        out.add(token)
    return out


# ---------------------------------------------------------------------------
# 1. SKILL.md — top-level command count
# ---------------------------------------------------------------------------


def test_skill_md_command_count_matches_filesystem() -> None:
    """SKILL.md must declare the actual number of *.md files in commands/."""
    actual = len(list(COMMANDS_DIR.glob("*.md")))
    text = SKILL_MD.read_text(encoding="utf-8")

    # Look for a phrase like "24 commands" / "Dev toolkit — 24 commands"
    matches = re.findall(r"\*\*(\d+)\s+commands?\*\*|—\s+(\d+)\s+commands?\b", text)
    declared = [int(a or b) for a, b in matches if (a or b)]
    assert declared, (
        f"SKILL.md declares no command count; expected '... — {actual} commands' phrase. "
        "Update SKILL.md intro/overview to include the count."
    )
    assert all(n == actual for n in declared), (
        f"SKILL.md declares command count {declared}, but commands/ has {actual} *.md files. "
        f"Fix SKILL.md to say '{actual} commands'."
    )


# ---------------------------------------------------------------------------
# 2. SKILL.md — script table covers every scripts/*.{sh,py}
# ---------------------------------------------------------------------------


def test_skill_md_script_table_lists_all_scripts() -> None:
    """Every shell + python script must appear in the SKILL.md script table."""
    fs_scripts = _filesystem_basenames(SCRIPTS_DIR, (".sh", ".py"))
    # Python package marker is not a tool — only present so `from scripts.X import ...`
    # works in tests after the sdd-unification Sprint 1.
    fs_scripts.discard("__init__.py")
    text = SKILL_MD.read_text(encoding="utf-8")
    section = _section_lines(text, "## Tools")
    assert section, "SKILL.md must contain a '## Tools' section listing scripts"
    documented = _table_first_column_codespans(section)
    missing = sorted(fs_scripts - documented)
    extras = sorted(documented - fs_scripts - {"_lib.sh"})  # _lib is a shared helper, not a tool
    # _lib.sh is allowed as a documented helper
    assert not missing, (
        f"SKILL.md '## Tools' table missing {len(missing)} scripts: {missing}. Add a row for each."
    )
    assert not extras, f"SKILL.md '## Tools' table references non-existent scripts: {extras}."


# ---------------------------------------------------------------------------
# 3. SKILL.md — agents table covers every agents/*.md
# ---------------------------------------------------------------------------


def test_skill_md_agents_table_lists_all_agents() -> None:
    fs_agents = {p.stem for p in AGENTS_DIR.glob("*.md")}
    text = SKILL_MD.read_text(encoding="utf-8")
    section = _section_lines(text, "## Agents")
    assert section, "SKILL.md must contain a '## Agents' section listing subagents"
    documented = _table_first_column_codespans(section)
    missing = sorted(fs_agents - documented)
    extras = sorted(documented - fs_agents)
    assert not missing, f"SKILL.md '## Agents' table missing {len(missing)} agents: {missing}."
    assert not extras, f"SKILL.md '## Agents' table references non-existent agents: {extras}."


# ---------------------------------------------------------------------------
# 4. SKILL.md — hooks table covers every hooks/*.sh
# ---------------------------------------------------------------------------


def test_skill_md_hooks_table_lists_all_hooks() -> None:
    fs_hooks = _filesystem_basenames(HOOKS_DIR, (".sh",))
    text = SKILL_MD.read_text(encoding="utf-8")
    section = _section_lines(text, "## Hooks")
    assert section, (
        "SKILL.md must contain a '## Hooks' section listing all hooks/*.sh files. "
        "Add a section after Agents documenting each hook with its trigger."
    )
    documented = _table_first_column_codespans(section)
    missing = sorted(fs_hooks - documented)
    extras = sorted(documented - fs_hooks)
    assert not missing, f"SKILL.md '## Hooks' table missing {len(missing)} hooks: {missing}."
    assert not extras, f"SKILL.md '## Hooks' table references non-existent hooks: {extras}."


# ---------------------------------------------------------------------------
# 5. SKILL.md — References section links every references/*.md
# ---------------------------------------------------------------------------


def test_skill_md_references_link_existing_files() -> None:
    fs_refs = {p.name for p in REFERENCES_DIR.glob("*.md")}
    text = SKILL_MD.read_text(encoding="utf-8")
    section = _section_lines(text, "## References")
    assert section, "SKILL.md must contain a '## References' section"
    section_text = "\n".join(section)
    # Match `references/<name>.md` as inline ref or bare path.
    # Character class includes '.' to support filenames with multiple dots
    # (e.g. rules-profile.schema.md).
    linked = set(re.findall(r"references/([A-Za-z0-9_\-\.]+\.md)", section_text))
    missing = sorted(fs_refs - linked)
    nonexistent = sorted(linked - fs_refs)
    assert not missing, (
        f"SKILL.md '## References' missing links for: {missing}. "
        "Each references/*.md must be linked from the References section."
    )
    assert not nonexistent, f"SKILL.md '## References' links non-existent files: {nonexistent}."


# ---------------------------------------------------------------------------
# 6. README.md — top-level command count
# ---------------------------------------------------------------------------


def test_readme_command_count_matches_filesystem() -> None:
    actual = len(list(COMMANDS_DIR.glob("*.md")))
    text = README_MD.read_text(encoding="utf-8")
    matches = re.findall(r"\*\*(\d+)\s+top-level slash-commands?\*\*", text)
    assert matches, "README.md must declare the count via '**N top-level slash-commands**' phrase."
    declared = [int(m) for m in matches]
    assert all(n == actual for n in declared), (
        f"README.md declares {declared} top-level slash-commands, but commands/ has {actual} *.md files. "
        f"Fix README.md to say '**{actual} top-level slash-commands**' and add table rows for missing commands."
    )


# ---------------------------------------------------------------------------
# 7. install.sh header comment — dev-command count (CDX-D2 regression guard)
# ---------------------------------------------------------------------------


def test_install_sh_header_command_count_matches_filesystem() -> None:
    """`install.sh`'s top header comment must declare the actual commands/*.md count.

    Regression guard for CDX-D2: the header once said "18 dev commands" while
    commands/ had grown to 29 — catches the next drift the same way.
    """
    actual = len(list(COMMANDS_DIR.glob("*.md")))
    text = INSTALL_SH.read_text(encoding="utf-8")
    header = "\n".join(text.splitlines()[:10])
    matches = re.findall(r"(\d+)\s+dev commands?\b", header)
    assert matches, (
        "install.sh header comment must declare the count via 'N dev commands' phrasing."
    )
    declared = [int(m) for m in matches]
    assert all(n == actual for n in declared), (
        f"install.sh header declares {declared} dev commands, but commands/ has {actual} *.md files. "
        f"Fix install.sh's header comment to say '{actual} dev commands'."
    )


# ---------------------------------------------------------------------------
# 8. references/session-memory.md + SKILL.md — Stage 8 doc-vs-code reconciliation
# ---------------------------------------------------------------------------


def test_session_memory_doc_matches_code_defaults() -> None:
    """`references/session-memory.md` must state the real hook defaults/behavior.

    Regression guard for the Stage 8 reconciliation (2026-07-15 session-memory
    graph hardening plan): docs previously drifted from `hooks/mb-session-*.sh`
    on MB_CATCHUP_MAX, MB_AUTO_CAPTURE, the dead MB_RECALL var, the non-existent
    `## Diagnostics` section, and the Summary section count.
    """
    text = SESSION_MEMORY_MD.read_text(encoding="utf-8")

    # MB_CATCHUP_MAX default matches hooks/mb-session-catchup.sh ("${MB_CATCHUP_MAX:-2}")
    assert re.search(r"`MB_CATCHUP_MAX`\s*\|\s*2\s*\|", text), (
        "session-memory.md must document MB_CATCHUP_MAX default as 2 "
        "(matches hooks/mb-session-catchup.sh)."
    )

    # MB_AUTO_CAPTURE default matches hooks/session-end-autosave.sh ("${MB_AUTO_CAPTURE:-auto}"),
    # stated as a plain resolved fact — no "under review" hedging language.
    assert re.search(r"`MB_AUTO_CAPTURE`\s*\|\s*auto\s*\|", text), (
        "session-memory.md must document MB_AUTO_CAPTURE default as auto "
        "(matches hooks/session-end-autosave.sh)."
    )
    assert "under review" not in text.lower(), (
        "MB_AUTO_CAPTURE default is a resolved decision (AGR/Stage 8) — "
        "do not hedge with 'under review' wording."
    )

    # MB_RECALL is dead (no hook/script ever reads it); MB_RECALL_LIMIT is the live var
    # and must be left alone.
    assert not re.search(r"MB_RECALL\b(?!_LIMIT)", text), (
        "session-memory.md still documents the dead MB_RECALL variable; "
        "only MB_RECALL_LIMIT is real (see hooks/mb-recall.sh)."
    )

    # The `## Diagnostics` section does not exist in any capture/summarize hook output.
    assert "## Diagnostics" not in text, (
        "session-memory.md documents a '## Diagnostics' section that no hook ever writes."
    )

    # Summary section count: exactly 4 named headings inside the `## Summary` fenced
    # example, matching hooks/mb-session-summarize.sh's fixed rank table.
    summary_block_match = re.search(
        r"### Section `## Summary`.*?```markdown\n(.*?)\n```", text, flags=re.DOTALL
    )
    assert summary_block_match, "session-memory.md must contain a fenced '## Summary' example."
    summary_headings = re.findall(r"^### (.+)$", summary_block_match.group(1), flags=re.MULTILINE)
    expected = ["What changed", "Decisions", "Open questions", "Files"]
    assert summary_headings == expected, (
        f"session-memory.md '## Summary' section must document exactly the 4 headings "
        f"{expected} in order (matches hooks/mb-session-summarize.sh); found {summary_headings}."
    )


def test_skill_md_recall_description_is_hybrid_not_ripgrep_only() -> None:
    """SKILL.md must describe `/mb recall` as hybrid semantic+lexical (RRF), not ripgrep-only.

    Regression guard: `hooks/mb-recall.sh` fuses semantic + lexical hits via RRF
    (Reciprocal Rank Fusion) when the semantic backend is available, falling back to
    lexical-only otherwise — SKILL.md previously undersold this as plain ripgrep.
    """
    text = SKILL_MD.read_text(encoding="utf-8")
    recall_lines = [line for line in text.splitlines() if "recall" in line.lower()]
    assert recall_lines, "SKILL.md must mention `/mb recall` somewhere."

    recall_block = "\n".join(recall_lines)
    assert re.search(r"\bRRF\b|semantic", recall_block, re.IGNORECASE), (
        "SKILL.md's recall description must mention hybrid semantic/RRF search."
    )
    assert not re.search(r"ripgrep over", recall_block, re.IGNORECASE), (
        "SKILL.md must not describe `/mb recall` as ripgrep-only anymore."
    )


# Sanity check — the helpers themselves work as expected
@pytest.mark.parametrize(
    "raw,expected",
    [
        ("| `foo.sh` | bar |", "foo.sh"),
        ("| `mb-context.sh [--deep]` | desc |", "mb-context.sh"),
        ("plain text", None),
        ("|`no-space`| desc |", "no-space"),  # \s* matches zero whitespace too
    ],
)
def test_codespan_first_column_helper(raw: str, expected: str | None) -> None:
    m = CODE_SPAN_FIRST_COL_RE.match(raw)
    if expected is None:
        assert m is None
    else:
        assert m is not None
        assert m.group(1).split()[0] == expected
