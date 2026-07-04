"""Backlog I-094 S1 — `scripts/mb-work-slots.sh` sourced helper.

Per-run slot-path resolution + a source→run claim index, gated behind
`MB_WORK_PARALLEL`. The script is a sourced library (no `main`, never executed
directly) consumed by `mb-work-state.sh` (and, in later stages, budget /
checkbox / resolve / diff). Tests source it inside a tiny bash harness and
call the public `mbw_*` functions directly.

See `.memory-bank/plans/2026-07-04_fix_mb-work-parallel-runs.md` (Stage 1).
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SLOTS = REPO_ROOT / "scripts" / "mb-work-slots.sh"


def _run(script: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    full_env = dict(os.environ)
    full_env.pop("MB_WORK_PARALLEL", None)
    if env:
        full_env.update(env)
    harness = f'source "{SLOTS}" && {script}'
    return subprocess.run(
        ["bash", "-c", harness],
        capture_output=True,
        text=True,
        check=False,
        env=full_env,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_state_slot_singleton_when_parallel_off_no_runid(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    r = _run(f'mbw_state_slot "{bank}" ""')
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == f"{bank}/.work-state.json"


def test_state_slot_perrun_when_parallel_on(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    r = _run(f'mbw_state_slot "{bank}" "r1"', env={"MB_WORK_PARALLEL": "1"})
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == f"{bank}/.work-state/r1.json"

    # Budget slots follow the identical rule under the same directory scheme.
    rb = _run(f'mbw_budget_slot "{bank}" "r1"', env={"MB_WORK_PARALLEL": "1"})
    assert rb.returncode == 0, rb.stderr
    assert rb.stdout.strip() == f"{bank}/.work-budget/r1.json"

    # Parallel on but no run_id supplied → still the singleton (env alone
    # does not route to a per-run slot; a run_id is required too).
    r2 = _run(f'mbw_state_slot "{bank}" ""', env={"MB_WORK_PARALLEL": "1"})
    assert r2.returncode == 0, r2.stderr
    assert r2.stdout.strip() == f"{bank}/.work-state.json"


def test_index_set_get_del_roundtrip(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()

    r = _run(f'mbw_index_set "{bank}" "plans/a.md" "r1" && mbw_index_get "{bank}" "plans/a.md"')
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "r1"

    r2 = _run(f'mbw_index_del "{bank}" "plans/a.md" && mbw_index_get "{bank}" "plans/a.md"')
    assert r2.returncode == 0, r2.stderr
    assert r2.stdout.strip() == ""


def test_index_get_missing_is_failsafe_empty(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"

    # Absent bank / never-set source.
    r = _run(f'mbw_index_get "{bank}" "plans/never-set.md"')
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == ""

    # Corrupt entry: a directory sitting where a one-line file is expected.
    r_hash = _run('mbw_source_hash "plans/corrupt.md"')
    assert r_hash.returncode == 0, r_hash.stderr
    idx_dir = bank / ".work-state" / "by-source"
    idx_dir.mkdir(parents=True)
    (idx_dir / r_hash.stdout.strip()).mkdir()

    r2 = _run(f'mbw_index_get "{bank}" "plans/corrupt.md"')
    assert r2.returncode == 0, r2.stderr
    assert r2.stdout.strip() == ""
    assert "traceback" not in (r2.stdout + r2.stderr).lower()
