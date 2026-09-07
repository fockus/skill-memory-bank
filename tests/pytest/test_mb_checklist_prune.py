"""`scripts/mb-checklist-prune.sh` — checklist v2 compactor + v1→v2 migrator.

Contract (Sprint 1 Stage 5, AGR-043): nothing is ever deleted. Completed work
moves verbatim into ``progress.md``; per-stage v1 blocks of one plan collapse
into a single v2 block; open ``⬜`` lines are never moved.
"""

from __future__ import annotations

import os
import re
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


def _run(
    mb: Path, *args: str, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True, text=True, check=False,
        env={**os.environ, **(env or {})},
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
    # Section without plans/done link or with ⬜ remaining must NOT be an archive candidate.
    tail = r.stdout.split("# Archive candidates")[-1]
    assert "Stale notes" not in tail
    assert "Phase 2 Sprint 1" not in tail


def test_dry_run_makes_no_changes(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    before = (mb / "checklist.md").read_text(encoding="utf-8")
    _run(mb, "--dry-run")
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    assert before == after


def test_apply_moves_completed_sections_out_of_the_checklist(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    r = _run(mb, "--apply")
    assert r.returncode == 0, r.stderr
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    # v2 contract: a fully-done plans/done-linked section leaves the checklist whole —
    # it is no longer collapsed to a `### … — Plan: [...]` one-liner.
    assert "Did the thing." not in after
    assert "Subtask one" not in after
    assert "Phase 1 Sprint 1" not in after
    assert "Other stuff." not in after
    assert "Bullet block:" not in after
    assert "Phase 1 Sprint 2" not in after


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


def test_apply_idempotent_legacy_fixture(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    _run(mb, "--apply")
    after_first = (mb / "checklist.md").read_text(encoding="utf-8")
    # Second run must be no-op (one-liners already collapsed).
    time.sleep(1.1)  # ensure backup timestamp differs if a new one were created
    r2 = _run(mb, "--apply")
    after_second = (mb / "checklist.md").read_text(encoding="utf-8")
    assert after_first == after_second
    assert r2.returncode == 0


def test_hard_cap_exceeded_exits_3(tmp_path: Path) -> None:
    body = "# Big\n\n## ⏳ In flight\n\n" + "\n".join(f"- ⬜ Item {i}" for i in range(1, 200)) + "\n"
    mb = _init_mb(tmp_path, body)
    r = _run(mb, "--apply")
    # v2 contract: over cap is a hard signal (exit 3), not a soft warning.
    assert r.returncode == 3
    assert "over cap by" in (r.stderr + r.stdout)


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


# ---------------------------------------------------------------------------
# Stage 5 — checklist v2: one block per plan, done work archived to progress.md
# ---------------------------------------------------------------------------

V1_TWO_PLANS = """# Project — Чеклист

> Convention. Short active list only; hard cap ≤120 lines.

<!-- mb-plan:2026-01-01_feature_alpha.md -->
## Stage 1: first thing
- ✅ first thing

<!-- mb-plan:2026-01-01_feature_alpha.md -->
## Stage 2: second thing
- ⬜ second thing

<!-- mb-plan:2026-01-01_feature_alpha.md -->
## Stage 3: third thing
- ⬜ third thing

<!-- mb-plan:2026-02-02_fix_beta.md -->
## Stage 1: beta one
- ✅ beta one
"""

PLAN_ALPHA = """# Plan: feature — Alpha the first

<!-- mb-stage:1 -->
### Stage 1: first thing
"""


def _init_plans(mb: Path, name: str, body: str, *, done: bool = False) -> Path:
    target = mb / "plans" / ("done" if done else "")
    target.mkdir(parents=True, exist_ok=True)
    path = target / name
    path.write_text(body, encoding="utf-8")
    return path


_STAGE_PREFIX = re.compile(r"^Stage \d+ — ")


def _open_items(text: str) -> set[str]:
    """Open-item texts, normalised across the v1→v2 line rewrite."""
    out = set()
    for ln in text.splitlines():
        if "⬜" not in ln:
            continue
        body = ln.split("⬜", 1)[1].strip()
        out.add(_STAGE_PREFIX.sub("", body))
    return out


def test_per_stage_blocks_of_one_plan_compact_to_single_v2_block_keeping_statuses(
    tmp_path: Path,
) -> None:
    mb = _init_mb(tmp_path, V1_TWO_PLANS)
    _init_plans(mb, "2026-01-01_feature_alpha.md", PLAN_ALPHA)
    r = _run(mb, "--apply")
    assert r.returncode == 0, r.stderr
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    assert after.count("<!-- mb-plan:2026-01-01_feature_alpha.md -->") == 1
    assert "## Alpha the first — 1/3" in after
    assert "- ✅ Stage 1 — first thing" in after
    assert "- ⬜ Stage 2 — second thing" in after
    assert "- ⬜ Stage 3 — third thing" in after
    # second plan keeps its own block
    assert after.count("<!-- mb-plan:2026-02-02_fix_beta.md -->") == 1
    assert "- ✅ Stage 1 — beta one" in after


def test_open_stage_lines_never_moved(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, V1_TWO_PLANS)
    _init_plans(mb, "2026-01-01_feature_alpha.md", PLAN_ALPHA)
    before_names = {"second thing", "third thing"}
    _run(mb, "--apply")
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    after_names = {ln.split("—", 1)[1].strip() for ln in after.splitlines() if "⬜" in ln}
    assert after_names == before_names
    progress = mb / "progress.md"
    if progress.exists():
        assert "second thing" not in progress.read_text(encoding="utf-8")


def test_done_plan_block_moved_to_progress_verbatim(tmp_path: Path) -> None:
    body = """# Project — Чеклист

<!-- mb-plan:2026-03-03_feature_gamma.md -->
## Gamma — 2/2
- ✅ Stage 1 — g one
- ✅ Stage 2 — g two
"""
    mb = _init_mb(tmp_path, body)
    _init_plans(mb, "2026-03-03_feature_gamma.md", "# Plan: feature — Gamma\n", done=True)
    r = _run(mb, "--apply")
    assert r.returncode == 0, r.stderr
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "2026-03-03_feature_gamma.md" not in after
    progress = (mb / "progress.md").read_text(encoding="utf-8")
    assert "## [checklist archive]" in progress
    assert "<!-- mb-plan:2026-03-03_feature_gamma.md -->" in progress
    assert "## Gamma — 2/2" in progress
    assert "- ✅ Stage 1 — g one" in progress
    assert "- ✅ Stage 2 — g two" in progress


def test_legacy_done_oneliners_moved_to_progress(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    r = _run(mb, "--apply")
    assert r.returncode == 0, r.stderr
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    progress = (mb / "progress.md").read_text(encoding="utf-8")
    # Fully-done, plans/done-linked `### ` sections leave the checklist entirely…
    assert "Phase 1 Sprint 1" not in after
    assert "Phase 1 Sprint 2" not in after
    # …and land verbatim in progress.md.
    assert "### Phase 1 Sprint 1 ✅ (2026-04-25)" in progress
    assert "Did the thing." in progress
    assert "- ✅ Subtask one" in progress
    assert "### Phase 1 Sprint 2 ✅ (2026-04-25)" in progress
    assert "Bullet block:" in progress


def test_archive_append_unconfirmed_leaves_checklist_untouched(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, FIXTURE_FULL)
    # Hold the progress-append lock so the helper degrades to its fail-safe no-write path.
    (mb / ".work-progress.lock").mkdir()
    (mb / ".work-progress.lock" / "owner").write_text("someone-else", encoding="utf-8")
    r = _run(mb, "--apply", env={"MB_PROGRESS_APPEND_LOCK_TIMEOUT": "0"})
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    # Nothing was archived, so nothing may be removed: every candidate is still here.
    assert "### Phase 1 Sprint 1 ✅ (2026-04-25)" in after
    assert "Did the thing." in after
    assert "- ✅ Subtask one" in after
    assert "### Phase 1 Sprint 2 ✅ (2026-04-25)" in after
    assert "Bullet block:" in after
    assert r.returncode == 0
    assert not (mb / "progress.md").exists()
    assert "unconfirmed" in r.stderr


def test_cap_resolution_env_over_config_over_default(tmp_path: Path) -> None:
    body = "# Big\n\n" + "\n".join(f"- ⬜ Item {i}" for i in range(1, 30)) + "\n"
    mb = _init_mb(tmp_path, body)
    # default 100 → 31 lines is fine
    assert _run(mb, "--apply").returncode == 0
    # .mb-config lowers it → over cap
    (mb / ".mb-config").write_text("checklist_max_lines=10\n", encoding="utf-8")
    assert _run(mb, "--apply").returncode == 3
    # env wins over .mb-config
    assert _run(mb, "--apply", env={"MB_CHECKLIST_MAX_LINES": "500"}).returncode == 0


def test_still_over_cap_after_compaction_exits_3_lists_plans_and_moves_nothing(
    tmp_path: Path,
) -> None:
    chunks = ["# Project — Чеклист", ""]
    for p in range(1, 13):
        chunks.append(f"<!-- mb-plan:2026-01-{p:02d}_feature_p{p}.md -->")
        chunks.append(f"## Plan {p} — 0/8")
        chunks += [f"- ⬜ Stage {s} — p{p} step {s}" for s in range(1, 9)]
        chunks.append("")
    body = "\n".join(chunks) + "\n"
    mb = _init_mb(tmp_path, body)
    before = (mb / "checklist.md").read_text(encoding="utf-8")
    r = _run(mb, "--apply")
    assert r.returncode == 3, r.stdout + r.stderr
    out = r.stdout + r.stderr
    assert "over cap by" in out
    assert "12 plans in flight" in out
    for p in range(1, 13):
        assert f"2026-01-{p:02d}_feature_p{p}.md: 8 open" in out
    assert (mb / "checklist.md").read_text(encoding="utf-8") == before
    assert not list(mb.glob(".checklist.md.bak.*"))


def test_techflow_like_fixture_596_lines_compacts_and_signals_cap(tmp_path: Path) -> None:
    fixture = REPO_ROOT / "tests" / "fixtures" / "checklist-big.md"
    body = fixture.read_text(encoding="utf-8")
    assert len(body.splitlines()) == 596
    mb = _init_mb(tmp_path, body)
    before_open = _open_items(body)
    r = _run(mb, "--apply")
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    after_lines = len(after.splitlines())
    # 34 per-stage v1 blocks of 16 plans fold into 16 v2 blocks…
    assert 596 - after_lines > 150, after_lines
    assert after.count("<!-- mb-plan:") == 16
    # …but every open item survives byte-for-byte: live work is never cut.
    assert _open_items(after) == before_open
    # 105 live open items cannot fit under a 100-line cap → honest exit-3 signal.
    assert r.returncode == 3
    assert "over cap by" in (r.stdout + r.stderr)


def test_apply_idempotent_second_run_noop(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, V1_TWO_PLANS)
    _init_plans(mb, "2026-01-01_feature_alpha.md", PLAN_ALPHA)
    _run(mb, "--apply")
    first = (mb / "checklist.md").read_text(encoding="utf-8")
    backups_after_first = len(list(mb.glob(".checklist.md.bak.*")))
    time.sleep(1.1)
    r2 = _run(mb, "--apply")
    assert (mb / "checklist.md").read_text(encoding="utf-8") == first
    assert r2.returncode == 0
    # No content change → no second backup.
    assert len(list(mb.glob(".checklist.md.bak.*"))) == backups_after_first


def test_protected_sections_untouched(tmp_path: Path) -> None:
    body = """# Project

## ⏳ In flight

### Done-looking but protected
Plan: [plans/done/2026-04-25_feature_a.md](plans/done/2026-04-25_feature_a.md)
- ✅ done item

## ⏭ Next planned

- Sprint X — TBD
"""
    mb = _init_mb(tmp_path, body)
    _run(mb, "--apply")
    after = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "Done-looking but protected" in after
    assert "- ✅ done item" in after
