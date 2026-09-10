"""mb-work-cost-diet Sprint 1 Stage 7 — the core-file caps are wired, not declared.

AGR-043: `status.md` and `checklist.md` are strict registries with hard line
caps enforced by code. A cap that only lives in a header comment is a
convention nobody runs, so the docs that drive the agents must name the tool
that enforces it and the strict-actualize contract that repairs an overflow.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]


def _read(rel: str) -> str:
    return (REPO_ROOT / rel).read_text(encoding="utf-8")


def test_manager_documents_strict_actualize_contract() -> None:
    text = _read("agents/mb-manager.md")
    assert "actualize --strict" in text, "MB Manager has no `actualize --strict` action"
    assert "mb-core-cap.sh check" in text, (
        "`actualize --strict` must end with mb-core-cap.sh check — otherwise the "
        "subagent cannot know whether it actually got under the cap"
    )
    assert "mb-work-progress-append.sh" in text, (
        "AGR-043: everything removed from status.md must land in progress.md verbatim first"
    )
    assert "DONE_WITH_CONCERNS" in text


def test_done_step_five_runs_the_cap_fixer() -> None:
    text = _read("commands/done.md")
    assert "mb-core-cap.sh fix" in text
    # `fix` composes Stage 4 rotation — the doc must keep naming it, so nobody
    # thinks rotation was dropped.
    assert "mb-status-rotate.sh" in text


def test_mb_router_exposes_update_strict() -> None:
    text = _read("commands/mb.md")
    assert "update --strict" in text
    assert "actualize --strict" in text


@pytest.mark.parametrize(
    "template",
    [
        "templates/.memory-bank/status.md",
        "templates/locales/en/.memory-bank/status.md",
        "templates/locales/ru/.memory-bank/status.md",
        "templates/locales/es/.memory-bank/status.md",
        "templates/locales/zh/.memory-bank/status.md",
    ],
)
def test_status_templates_declare_the_hard_cap(template: str) -> None:
    text = _read(template)
    assert "hard cap" in text.lower(), f"{template}: no cap convention in the header"
    assert "mb-core-cap.sh" in text, f"{template}: cap is declared but no tool enforces it"
    assert "progress.md" in text, f"{template}: does not say where history goes"


def test_structure_reference_documents_core_file_caps() -> None:
    text = _read("references/structure.md")
    assert "mb-core-cap.sh" in text
    assert "MB_STATUS_MAX_LINES" in text
    assert "MB_CORE_CAP" in text


def test_drift_check_is_core_cap_not_status_size() -> None:
    text = _read("scripts/mb-drift.sh")
    assert "core_cap" in text
    assert "status_size" not in text, (
        "check 17 was renamed status_size → core_cap (line caps, not 24 KB)"
    )
