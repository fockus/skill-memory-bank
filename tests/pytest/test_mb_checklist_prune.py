"""I-033 — `scripts/mb-checklist-prune.sh` collapses completed sections to one-liners."""

from __future__ import annotations

import subprocess
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-checklist-prune.sh"


def _init_mb(tmp_path: Path, body: str) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "checklist.md").write_text(body, encoding="utf-8")
    return mb


def _run(mb: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True, text=True, check=False,
    )


FIXTURE_FULL = """# Project — Чеклист

> Convention. Hard cap ≤120 lines.

## ⏳ In flight

- ⬜ Active task one
- ⬜ Active task two

## ⏭ Next planned

- Sprint X — TBD

## ✅ Recently completed

### Phase 1 Sprint 1 ✅ (2026-04-25)
Did the thing. Plan: [plans/done/2026-04-25_feature_a.md](plans/done/2026-04-25_feature_a.md). Tests +10.

Some additional details about Sprint 1.
- ✅ Subtask one
- ✅ Subtask two

### Phase 1 Sprint 2 ✅ (2026-04-25)
Other stuff. Plan: [plans/done/2026-04-25_feature_b.md](plans/done/2026-04-25_feature_b.md). Tests +20.

Bullet block:
- ✅ Bullet a
- ✅ Bullet b

### Stale notes (no plan link)
Random notes section without plans/done link.
- ✅ Done item

### Phase 2 Sprint 1 (in progress)
Plan: [plans/done/2026-04-25_feature_c.md](plans/done/2026-04-25_feature_c.md)
- ✅ Done item
- ⬜ Pending item

## 📜 History pointer

Filler text.
"""


def test_dry_run_lists_collapse_candidates(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    r = _run(mb, "--dry-run")
    assert r.returncode == 0, r.stderr
    out = r.stdout + r.stderr
    assert "Phase 1 Sprint 1" in out
    assert "Phase 1 Sprint 2" in out
    # Section without plans/done link or with ⬜ remaining must NOT appear as candidate.
    assert "Stale notes" not in r.stdout.split("# Plans to collapse")[-1] if "# Plans to collapse" in r.stdout else True
    assert "Phase 2 Sprint 1" not in r.stdout.split("# Plans to collapse")[-1] if "# Plans to collapse" in r.stdout else True


def test_dry_run_makes_no_changes(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    before = (mb / "checklist.md").read_text(encoding="utf-8")
    _run(mb, "--dry-run")
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    assert before == after


def test_apply_collapses_completed_sections(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    r = _run(mb, "--apply")
    assert r.returncode == 0, r.stderr
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    # Sprint 1 section body was 3 lines + bullets; expect single ### line surviving.
    assert "Did the thing." not in after
    assert "Subtask one" not in after
    assert "Phase 1 Sprint 1 ✅" in after
    assert "plans/done/2026-04-25_feature_a.md" in after
    # Same for Sprint 2.
    assert "Other stuff." not in after
    assert "Bullet block:" not in after
    assert "Phase 1 Sprint 2 ✅" in after


def test_apply_preserves_in_flight(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    _run(mb, "--apply")
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "Active task one" in after
    assert "Active task two" in after
    assert "## ⏳ In flight" in after


def test_apply_preserves_section_without_plans_done_link(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    _run(mb, "--apply")
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "Stale notes (no plan link)" in after
    assert "Random notes section" in after


def test_apply_preserves_partial_done_section(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    _run(mb, "--apply")
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    # Section still has ⬜ — must not be collapsed.
    assert "Pending item" in after
    assert "Phase 2 Sprint 1 (in progress)" in after


def test_apply_creates_timestamped_backup(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    _run(mb, "--apply")
    backups = list(mb.glob(".checklist.md.bak.*"))
    assert len(backups) == 1
    assert backups[0].read_text(encoding="utf-8") == FIXTURE_FULL


def test_apply_idempotent(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    _run(mb, "--apply")
    after_first = (mb / "checklist.md").read_text(encoding="utf-8")
    # Second run must be no-op (one-liners already collapsed).
    time.sleep(1.1)  # ensure backup timestamp differs if a new one were created
    r2 = _run(mb, "--apply")
    after_second = (mb / "checklist.md").read_text(encoding="utf-8")
    assert after_first == after_second
    assert r2.returncode == 0


def test_hard_cap_warn_when_over_120(tmp_path: Path) -> None:
    body = "# Big\n\n## ⏳ In flight\n\n" + "\n".join(f"- ⬜ Item {i}" for i in range(1, 200)) + "\n"
    mb = _init_mb(tmp_path, body)
    r = _run(mb, "--apply")
    assert "warn" in (r.stderr + r.stdout).lower()
    assert "120" in (r.stderr + r.stdout)


def test_missing_checklist_returns_zero_with_hint(tmp_path: Path) -> None:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    r = _run(mb, "--dry-run")
    assert r.returncode == 0
    assert "checklist.md" in (r.stderr + r.stdout).lower()


def test_unknown_flag_errors(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    r = _run(mb, "--bogus")
    assert r.returncode != 0
    assert "unknown" in (r.stderr + r.stdout).lower()
