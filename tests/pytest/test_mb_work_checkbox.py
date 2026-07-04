"""I-093 Stage 4 (T2) — `scripts/mb-work-checkbox.sh` deterministic DoD flip.

The flipper is only allowed to mutate an item's DoD checkboxes when
``<bank>/.work-state.json`` says the gate already passed (``phase == "done"``)
for the matching ``item_no``. Everywhere else it must refuse without
mutating the file (fail-safe: no blind flips, no crashes on missing state).
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-checkbox.sh"

PLAN_MULTI_STAGE = """\
<!-- mb-stage:1 -->
## Этап 1
**DoD**
- ⬜ stage1 item

---

<!-- mb-stage:2 -->
## Этап 2
**DoD**
- ⬜ a
- [ ] b

---

<!-- mb-stage:3 -->
## Этап 3
**DoD**
- ⬜ stage3 item
"""

SPEC_TASK = """\
<!-- mb-task:1 -->
## Task 1
**DoD**
- [ ] c
- [ ] d
"""


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _write_state(
    mb: Path,
    *,
    item_no: int,
    phase: str = "done",
    run_id: str = "r1",
    source: str = "plan",
) -> None:
    state = {
        "run_id": run_id,
        "source": source,
        "item_no": item_no,
        "heading": "Stage",
        "cycle": 1,
        "max_cycles": 2,
        "steps": ["implement", "verify"],
        "phase": phase,
        "updated": "2026-07-04T00:00:00Z",
    }
    (mb / ".work-state.json").write_text(json.dumps(state) + "\n", encoding="utf-8")


def _run(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_flip_marks_item_checkboxes_done(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = tmp_path / "plan.md"
    plan.write_text(PLAN_MULTI_STAGE, encoding="utf-8")
    _write_state(mb, item_no=2, phase="done")

    r = _run("flip", str(plan), "2", mb=mb)

    assert r.returncode == 0, r.stderr
    text = plan.read_text(encoding="utf-8")
    assert "- ✅ a" in text
    assert "- [x] b" in text


def test_flip_scopes_to_item_block_only(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = tmp_path / "plan.md"
    plan.write_text(PLAN_MULTI_STAGE, encoding="utf-8")
    _write_state(mb, item_no=2, phase="done")

    r = _run("flip", str(plan), "2", mb=mb)

    assert r.returncode == 0, r.stderr
    text = plan.read_text(encoding="utf-8")
    assert "- ⬜ stage1 item" in text
    assert "- ⬜ stage3 item" in text


def test_flip_refused_when_state_not_done(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = tmp_path / "plan.md"
    plan.write_text(PLAN_MULTI_STAGE, encoding="utf-8")
    original = plan.read_bytes()
    _write_state(mb, item_no=2, phase="in-progress")

    r = _run("flip", str(plan), "2", mb=mb)

    assert r.returncode == 1
    assert plan.read_bytes() == original


def test_flip_is_idempotent(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = tmp_path / "plan.md"
    plan.write_text(PLAN_MULTI_STAGE, encoding="utf-8")
    _write_state(mb, item_no=2, phase="done")

    r1 = _run("flip", str(plan), "2", mb=mb)
    assert r1.returncode == 0, r1.stderr
    after_first = plan.read_bytes()

    r2 = _run("flip", str(plan), "2", mb=mb)
    assert r2.returncode == 0, r2.stderr
    assert plan.read_bytes() == after_first


def test_flip_spec_task_block(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    spec = tmp_path / "tasks.md"
    spec.write_text(SPEC_TASK, encoding="utf-8")
    _write_state(mb, item_no=1, phase="done", source="spec")

    r = _run("flip", str(spec), "1", mb=mb)

    assert r.returncode == 0, r.stderr
    text = spec.read_text(encoding="utf-8")
    assert "- [x] c" in text
    assert "- [x] d" in text


def test_flip_missing_item_is_usage_error(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = tmp_path / "plan.md"
    plan.write_text(PLAN_MULTI_STAGE, encoding="utf-8")
    _write_state(mb, item_no=99, phase="done")

    r = _run("flip", str(plan), "99", mb=mb)

    assert r.returncode == 2


def test_flip_missing_state_is_fail_safe_refuse(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = tmp_path / "plan.md"
    plan.write_text(PLAN_MULTI_STAGE, encoding="utf-8")
    original = plan.read_bytes()

    r = _run("flip", str(plan), "2", mb=mb)

    assert r.returncode == 1
    assert plan.read_bytes() == original
