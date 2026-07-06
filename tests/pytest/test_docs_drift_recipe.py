"""Contract: the MB drift/auto-commit recipe stays documented (I-087 B2).

The audit found MB_AUTO_COMMIT existed but was documented nowhere as a recipe, and the
new mb-freshness.sh drift alarm needs a discoverable home. This pins both so the recipe
cannot silently drift out of the docs.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "SKILL.md"
SESSION_DOC = ROOT / "docs" / "concepts" / "session-memory.md"
DONE = ROOT / "commands" / "done.md"
CROSS_AGENT_SETUP = ROOT / "docs" / "cross-agent-setup.md"


def test_skill_documents_auto_commit_recipe() -> None:
    text = SKILL.read_text(encoding="utf-8")
    assert "MB_AUTO_COMMIT" in text, "SKILL.md must document the MB_AUTO_COMMIT recipe"


def test_session_doc_documents_auto_commit_and_freshness() -> None:
    text = SESSION_DOC.read_text(encoding="utf-8")
    assert "MB_AUTO_COMMIT" in text, "session-memory.md must show the MB_AUTO_COMMIT recipe"
    assert "mb-freshness.sh" in text, (
        "session-memory.md must reference the mb-freshness.sh drift alarm"
    )


def test_done_command_links_auto_commit_and_freshness() -> None:
    text = DONE.read_text(encoding="utf-8")
    assert "MB_AUTO_COMMIT" in text, "commands/done.md must mention MB_AUTO_COMMIT"
    assert "mb-freshness.sh" in text, "commands/done.md must note the freshness/drift relationship"


# ---------------------------------------------------------------------------
# Doc-vs-reality grep-guards (Batch 7 / C1, D-1, D-2, D-4) — scoped to
# docs/cross-agent-setup.md only; deliberately does NOT read SKILL.md to
# avoid coupling to files owned by a parallel work stream.
# ---------------------------------------------------------------------------


def _table_row(text: str, row_label: str) -> str:
    """Return the markdown table row starting with `| {row_label} |`."""
    needle = f"| {row_label} |"
    for line in text.splitlines():
        if line.startswith(needle):
            return line
    raise AssertionError(f"table row {row_label!r} not found in {CROSS_AGENT_SETUP.name}")


def test_hook_matrix_codex_sessionend_is_git_hooks_fallback() -> None:
    """D-2: Codex has no native SessionEnd hook — the auto-capture row must say
    'git-hooks-fallback' honestly instead of implying a native capability."""
    text = CROSS_AGENT_SETUP.read_text(encoding="utf-8")
    row = _table_row(text, "SessionEnd auto-capture")
    codex_cell = [c.strip() for c in row.strip().strip("|").split("|")][-1]
    assert "git-hooks-fallback" in codex_cell, (
        "cross-agent-setup.md hook matrix: Codex 'SessionEnd auto-capture' cell must say "
        f"'git-hooks-fallback' (B5), not overclaim a native SessionEnd hook. Got: {codex_cell!r}"
    )


def test_hook_matrix_pi_extension_claim_does_not_overclaim_wiring() -> None:
    """D-1: adapters/pi_session_memory_extension.ts ships as source but no adapter
    installs it — the hook matrix must not claim it fires wired lifecycle events."""
    text = CROSS_AGENT_SETUP.read_text(encoding="utf-8")
    for stale_claim in (
        "Extension `session_shutdown` event",
        "Extension `session_before_compact` event",
        "Extension `tool_call` event (blockable)",
        "Extension `session_start` event (check",
    ):
        assert stale_claim not in text, (
            f"cross-agent-setup.md reintroduced an unwired-Pi-extension overclaim: {stale_claim!r}. "
            "adapters/pi_session_memory_extension.ts is not installed by any adapter — "
            "describe Pi's actual coverage as git-hooks-fallback (or 'no installed fallback')."
        )


def test_cursor_ide_cli_wording_is_consistent_with_cursor_extension_doc() -> None:
    """D-4: cross-agent-setup.md and cursor-extension.md used to contradict each other
    about which Cursor surface (IDE vs agent CLI) fires the full hook set. Lock the
    corrected direction: the agent CLI fires the full set; the IDE is best-effort."""
    text = CROSS_AGENT_SETUP.read_text(encoding="utf-8")
    assert "Cursor CLI only fires" not in text, (
        "Stale/reversed IDE-vs-CLI claim reintroduced in cross-agent-setup.md — the agent "
        "CLI fires the FULL hook set; the IDE is the best-effort side. "
        "See docs/cursor-extension.md#limitations."
    )
    assert "agent CLI* fires the full CC-compatible hook" in text, (
        "cross-agent-setup.md must state the agent CLI fires the full hook set "
        "(matching docs/cursor-extension.md)."
    )
