"""D-35 escalation + decomposition-registry contract (svp-sdd-core Task 5).

Supplementary to the `mb-sdd-candidate.sh` bats suite: asserts that the four
D-35 menu branches, the deterministic discard-on-cancel, the child-spec
frontmatter, the single-writer registry via `mb-idea.sh`, the partial-failure
loud report, and the orphaned-candidate rule are all present in the
`commands/sdd.md` prompt contract (REQ-010/011/014/053).
"""

from __future__ import annotations

import pathlib
import re

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SDD = (REPO_ROOT / "commands" / "sdd.md").read_text(encoding="utf-8")
SDD_L = SDD.lower()


def test_menu_has_four_branches() -> None:
    # split now / MVP-trim → registry / umbrella+JIT / budget_override.
    assert re.search(r"(?i)split now", SDD)
    assert re.search(r"(?i)mvp", SDD)
    assert re.search(r"(?i)umbrella", SDD)
    assert "budget_override: user" in SDD


def test_cancel_discards_via_helper_and_blocks() -> None:
    assert re.search(r"mb-sdd-candidate\.sh\s+discard", SDD)
    assert "sdd_status=blocked" in SDD


def test_auto_branch_records_assumption() -> None:
    assert re.search(r"(?i)auto[^\n]*assumption|assumption[^\n]*auto", SDD)
    assert re.search(r"(?i)self-interview", SDD)


def test_registry_single_writer_via_mb_idea() -> None:
    assert re.search(r'mb-idea\.sh\s+"\[SPEC:<group>\]', SDD)
    assert re.search(r"(?i)single writer|sole (registry )?writer|only writer", SDD_L)


def test_child_frontmatter_group_and_parent_context() -> None:
    assert "group: <group>" in SDD
    assert "parent_context: context/<umbrella>.md" in SDD


def test_partial_failure_loud_report() -> None:
    assert re.search(r"(?i)partial failure", SDD)
    assert re.search(r"(?i)loud report", SDD)
    # created children stay draft, unwritten ones are named.
    assert re.search(r"(?i)status: draft", SDD)


def test_orphaned_candidate_overwritten_not_accepted() -> None:
    assert re.search(r"(?i)orphaned", SDD)
    assert re.search(r"(?i)overwritten|never published as-is", SDD)


def test_budget_override_scope_narrowed() -> None:
    # override lifts only spec=over, and only when no task/stage overflow.
    assert re.search(r"(?i)only[^\n]*spec=over|spec=over[^\n]*only", SDD)
    assert re.search(r"(?i)never overridable|unbreakable|hard[- ]?cap", SDD)
