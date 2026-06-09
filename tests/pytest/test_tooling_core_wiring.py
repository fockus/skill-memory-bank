"""Stage 2 wiring tests — mb-tooling-core injected into the dispatch points.

`agents/mb-tooling-core.md` (Stage 1, a `partial: true` block) carries the
graph-first code-understanding routing table. Stage 2 wires it into the three
Task-dispatch surfaces so the discipline reaches the agents:

  - `commands/work.md` §3a implement step — prepended AFTER engineering-core,
    BEFORE the role delta (engineering-core primacy / "stricter wins" preserved).
  - `commands/work.md` §3c review step — inlined into the reviewer prompt.
  - `commands/mb.md` `### verify` section — inlined into the plan-verifier prompt.

Plus standalone fallback notes in `agents/mb-reviewer.md` and
`agents/plan-verifier.md` mirroring the role-file pattern.

These tests assert the LITERAL reference strings (per lesson "assert real
strings not should") and the engineering-core-before-tooling-core ordering.
"""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
WORK_MD = REPO_ROOT / "commands" / "work.md"
MB_MD = REPO_ROOT / "commands" / "mb.md"
REVIEWER = REPO_ROOT / "agents" / "mb-reviewer.md"
PLAN_VERIFIER = REPO_ROOT / "agents" / "plan-verifier.md"

ENGINEERING_CORE_REF = "mb-engineering-core.md"
TOOLING_CORE_REF = "mb-tooling-core.md"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_work_md_references_both_cores() -> None:
    text = _read(WORK_MD)
    assert ENGINEERING_CORE_REF in text, "work.md must reference mb-engineering-core.md"
    assert TOOLING_CORE_REF in text, "work.md must reference mb-tooling-core.md"


def test_work_md_engineering_core_precedes_tooling_core() -> None:
    """Order invariant: engineering-core's primacy must be preserved.

    Its first occurrence must appear at a LOWER character index than
    tooling-core's first occurrence (core before tooling-core in the prepend).
    """
    text = _read(WORK_MD)
    eng_idx = text.find(ENGINEERING_CORE_REF)
    tool_idx = text.find(TOOLING_CORE_REF)
    assert eng_idx != -1, "engineering-core reference not found in work.md"
    assert tool_idx != -1, "tooling-core reference not found in work.md"
    assert eng_idx < tool_idx, (
        f"engineering-core ({eng_idx}) must precede tooling-core ({tool_idx})"
    )


def test_work_md_references_tooling_core_in_implement_and_review() -> None:
    """tooling-core wired into BOTH §3a (implement) and §3c (review).

    It must appear at least twice: once in the implement-step prompt and once
    in the reviewer-step prompt.
    """
    text = _read(WORK_MD)
    assert text.count(TOOLING_CORE_REF) >= 2, (
        "mb-tooling-core.md must appear in both the implement (§3a) and "
        f"review (§3c) Task prompts; found {text.count(TOOLING_CORE_REF)}"
    )


def test_mb_md_verify_section_references_tooling_core() -> None:
    """The plan-verifier dispatch in `### verify` inlines tooling-core."""
    text = _read(MB_MD)
    verify_idx = text.find("### verify")
    assert verify_idx != -1, "### verify section not found in mb.md"
    # Scope to the verify region: from `### verify` to the next top-level `### `.
    next_section = text.find("\n### ", verify_idx + len("### verify"))
    region = text[verify_idx : next_section if next_section != -1 else len(text)]
    assert TOOLING_CORE_REF in region, (
        "mb-tooling-core.md must be referenced inside the `### verify` section"
    )


def test_reviewer_agent_has_tooling_core_fallback_note() -> None:
    assert TOOLING_CORE_REF in _read(REVIEWER), (
        "mb-reviewer.md must carry a standalone fallback note for mb-tooling-core.md"
    )


def test_plan_verifier_agent_has_tooling_core_fallback_note() -> None:
    assert TOOLING_CORE_REF in _read(PLAN_VERIFIER), (
        "plan-verifier.md must carry a standalone fallback note for mb-tooling-core.md"
    )
