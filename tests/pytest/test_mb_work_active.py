"""Choosing the next active plan for `/mb work` with no target (mb_work_active.select)."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import mb_work_active as wa  # noqa: E402


def _plan(
    bank: Path,
    name: str,
    status: str | None = None,
    depends: str | None = None,
    done_dir: bool = False,
) -> str:
    folder = bank / "plans" / ("done" if done_dir else "")
    folder.mkdir(parents=True, exist_ok=True)
    fm = [f"status: {status}"] if status else []
    fm += [f"depends_on: {depends}"] if depends else []
    head = "---\n" + "\n".join(fm) + "\n---\n" if fm else ""
    (folder / name).write_text(head + "# plan\n", encoding="utf-8")
    return f"plans/{'done/' if done_dir else ''}{name}"


@pytest.fixture
def bank(tmp_path: Path) -> Path:
    return tmp_path / "bank"


def test_select_paused_cancelled_done_blocked_skipped_with_reason(bank: Path) -> None:
    rels = [_plan(bank, f"{s}.md", s) for s in ("paused", "cancelled", "done", "blocked")]
    rels.append(_plan(bank, "go.md", "queued"))

    result = wa.select(bank, rels)

    assert result["pick"] == "plans/go.md"
    assert {rel: reason for rel, reason in result["skipped"]} == {
        f"plans/{s}.md": f"status: {s}" for s in ("paused", "cancelled", "done", "blocked")
    }


def test_select_open_dependency_skips_plan(bank: Path) -> None:
    _plan(bank, "base.md", "in_progress")
    rels = [_plan(bank, "next.md", "queued", "[base.md]"), _plan(bank, "other.md", "queued")]

    result = wa.select(bank, rels)

    assert result["pick"] == "plans/other.md"
    assert result["skipped"] == [("plans/next.md", "depends_on base.md is not closed")]


def test_select_dependency_closed_by_done_dir_or_status(bank: Path) -> None:
    _plan(bank, "archived.md", done_dir=True)
    _plan(bank, "finished.md", "done")
    rel = _plan(bank, "next.md", "queued", '["archived.md", plans/finished.md]')

    assert wa.select(bank, [rel])["pick"] == rel


def test_select_missing_dependency_is_open(bank: Path) -> None:
    rel = _plan(bank, "next.md", "queued", "[ghost.md]")

    result = wa.select(bank, [rel])

    assert result["pick"] is None
    assert result["skipped"] == [(rel, "depends_on ghost.md is not closed")]


def test_select_several_eligible_prefers_single_in_progress(bank: Path) -> None:
    rels = [
        _plan(bank, "a.md", "queued"),
        _plan(bank, "b.md", "in_progress"),
        _plan(bank, "c.md", "queued"),
    ]

    assert wa.select(bank, rels)["pick"] == "plans/b.md"


def test_select_several_eligible_without_single_in_progress_is_ambiguous(bank: Path) -> None:
    rels = [_plan(bank, "a.md", "in_progress"), _plan(bank, "b.md", "in_progress")]

    result = wa.select(bank, rels)

    assert result["pick"] is None
    assert result["eligible"] == [("plans/a.md", "in_progress"), ("plans/b.md", "in_progress")]


def test_select_no_frontmatter_or_unsafe_link_stays_eligible_unread(bank: Path) -> None:
    (bank / "specs" / "x").mkdir(parents=True)
    (bank / "specs" / "x" / "tasks.md").write_text("# tasks\n", encoding="utf-8")

    assert wa.select(bank, ["specs/x/tasks.md"])["pick"] == "specs/x/tasks.md"
    # The resolver, not the selector, rejects an escaping link; it must reach it unread.
    assert wa.select(bank, ["../../etc/passwd"])["pick"] == "../../etc/passwd"
