---
type: refactor
topic: skill-v2-phase1-sprint2-autosync
status: in_progress
depends_on: [plans/done/2026-04-22_refactor_skill-v2-phase1-sprint1-rename.md]
parallel_safe: false
linked_specs: [specs/mb-skill-v2]
sprint: 2
phase_of: skill-v2-phase1
created: 2026-04-22
---

# Skill v2 — Phase 1 Sprint 2: Roadmap Autosync + Traceability + Phase/Sprint/Task Parser

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `roadmap.md` a live-synced view of `plans/*.md` frontmatter state, introduce `traceability.md` autogeneration, and teach the plan-sync / plan-done scripts to recognize the modern `## Task N:` / `#### Task N:` heading format in addition to the legacy `### Stage N:` form.

**Architecture:** Two new pure-bash-with-python-helper scripts (`mb-roadmap-sync.sh`, `mb-traceability-gen.sh`) that scan `plans/` and (optionally) `specs/<topic>/requirements.md`, regenerate two target files between sentinel markers, idempotent across reruns. `mb-plan-sync.sh` and `mb-plan-done.sh` get a widened heading regex and a shared stage-parser helper. Two new slash-command entry points (`/mb roadmap-sync`, `/mb traceability-gen`) trigger the generators manually; `mb-plan-sync.sh` and `mb-plan-done.sh` call them automatically at end-of-run.

**Tech Stack:** bash 3.2+ (scripts), awk + python3 (parsing), pytest (tests), pyyaml-free YAML parsing (regex — avoid new deps).

**Gate (Sprint 2 success):**
1. `mb-roadmap-sync.sh` scans `plans/*.md`, regenerates `## Now / ## Next / ## Parallel-safe / ## Paused-Archived / ## Linked Specs (active)` sections inside a `<!-- mb-roadmap-auto -->` fence, idempotent (second run → byte-identical).
2. `mb-traceability-gen.sh` produces `traceability.md` from `specs/<topic>/requirements.md` + plans' `covers_requirements` + tests' `REQ-NNN` markers; handles zero-spec state gracefully.
3. `mb-plan-sync.sh` / `mb-plan-done.sh` correctly recognize a plan that uses `## Task N:` headings (like Sprint 1's completed plan) — verified by test fixture.
4. `/mb roadmap-sync` and `/mb traceability-gen` slash commands exist and invoke respective scripts with correct `mb_path` resolution.
5. `mb-plan-sync.sh` / `mb-plan-done.sh` auto-invoke the two generators at end-of-run (non-fatal on failure: warn, don't error).
6. All existing tests still pass (regression green).
7. New tests added for: each generator (happy + empty-state + idempotent), parser extension (Sprint 1 plan parses → 14 tasks), chain invocation.
8. shellcheck clean, ruff clean.

---

## File Structure

**New files:**
- `scripts/mb-roadmap-sync.sh` — scan `plans/*.md` frontmatter, regenerate roadmap autosync block
- `scripts/mb-traceability-gen.sh` — generate `traceability.md` from specs + plans + tests
- `commands/roadmap-sync.md` — slash command spec for `/mb roadmap-sync`
- `commands/traceability-gen.md` — slash command spec for `/mb traceability-gen`
- `tests/pytest/test_roadmap_sync.py` — pytest for mb-roadmap-sync.sh
- `tests/pytest/test_traceability_gen.py` — pytest for mb-traceability-gen.sh
- `tests/pytest/test_parse_stages_phase_sprint_task.py` — pytest for extended parser
- `tests/pytest/fixtures/plans_phase_sprint/` — fixture plans using new heading format

**Modified files:**
- `scripts/mb-plan-sync.sh` — widen `parse_stages()` regex; end-of-run chain call
- `scripts/mb-plan-done.sh` — widen `parse_stages()` regex; end-of-run chain call
- `commands/mb.md` — register new slash commands in index (if indexed there)

**Guarantees:**
- No new runtime dependencies (python3 already required)
- Backwards-compatible: legacy `### Stage N:` continues to parse
- Idempotent: second run of any generator produces byte-identical output

---

## Task 1: Fixture plans using Phase/Sprint/Task heading format

**Files:**
- Create: `tests/pytest/fixtures/plans_phase_sprint/phase_sprint_task.md`
- Create: `tests/pytest/fixtures/plans_phase_sprint/legacy_stage.md`
- Create: `tests/pytest/fixtures/plans_phase_sprint/mixed.md`

- [ ] **Step 1: Create `phase_sprint_task.md` fixture (modern format used by Sprint 1)**

File: `tests/pytest/fixtures/plans_phase_sprint/phase_sprint_task.md`

```markdown
---
type: feature
topic: fixture-phase-sprint-task
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
sprint: 1
phase_of: fixture-phase
created: 2026-04-22
---

# Fixture: Phase/Sprint/Task Heading Plan

**Goal:** Smoke fixture for modern `## Task N:` headings.

---

## Task 1: First bite-sized unit

- [ ] Step 1: do X
- [ ] Step 2: commit

## Task 2: Second unit

- [ ] Step 1: do Y

## Task 3: Third unit

- [ ] Step 1: do Z
```

- [ ] **Step 2: Create `legacy_stage.md` fixture (old format — backward compat)**

File: `tests/pytest/fixtures/plans_phase_sprint/legacy_stage.md`

```markdown
---
type: refactor
topic: fixture-legacy-stage
status: queued
depends_on: []
parallel_safe: true
linked_specs: []
sprint: 0
phase_of: legacy
created: 2026-04-22
---

# Fixture: Legacy Stage Heading Plan

---

<!-- mb-stage:1 -->
### Stage 1: Setup

- ⬜ Do setup work

<!-- mb-stage:2 -->
### Stage 2: Core logic

- ⬜ Do core work

<!-- mb-stage:3 -->
### Stage 3: Finalize

- ⬜ Final work
```

- [ ] **Step 3: Create `mixed.md` fixture (edge case — both forms)**

File: `tests/pytest/fixtures/plans_phase_sprint/mixed.md`

```markdown
---
type: feature
topic: fixture-mixed
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
sprint: 1
phase_of: mixed
created: 2026-04-22
---

# Fixture: Mixed Heading Plan

---

## Task 1: Modern heading first

- [ ] Step 1: do A

### Stage 2: Legacy heading

- ⬜ Legacy bullet
```

- [ ] **Step 4: Commit**

```bash
git add tests/pytest/fixtures/plans_phase_sprint/
git commit -m "test(plan-parser): add fixture plans with Phase/Sprint/Task + legacy Stage headings"
```

---

## Task 2: Failing tests for extended parse_stages() in mb-plan-sync.sh

**Files:**
- Create: `tests/pytest/test_parse_stages_phase_sprint_task.py`

- [ ] **Step 1: Write failing pytest that exercises mb-plan-sync.sh on fixtures**

File: `tests/pytest/test_parse_stages_phase_sprint_task.py`

```python
"""Tests for extended stage parser in mb-plan-sync.sh / mb-plan-done.sh.

The parser must recognize three heading forms:
  1. Modern `## Task N: <name>`
  2. Legacy `### Stage N: <name>` (with or without <!-- mb-stage:N --> marker)
  3. Mixed files (prefer explicit markers; otherwise first match wins)
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SYNC_SCRIPT = REPO_ROOT / "scripts" / "mb-plan-sync.sh"
FIXTURES = REPO_ROOT / "tests" / "pytest" / "fixtures" / "plans_phase_sprint"


def _init_mb(tmp_path: Path) -> Path:
    """Create a minimal .memory-bank/ with required core files + plans/."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text("# Roadmap\n", encoding="utf-8")
    (mb / "plans").mkdir()
    return mb


def _run_sync(plan_path: Path, mb_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SYNC_SCRIPT), str(plan_path), str(mb_path)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_sync_parses_phase_sprint_task_headings(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "phase_sprint_task.md"
    shutil.copy2(FIXTURES / "phase_sprint_task.md", plan)

    result = _run_sync(plan, mb)

    assert result.returncode == 0, result.stderr
    # mb-plan-sync.sh reports "stages=N" — modern plan has 3 tasks
    assert "stages=3" in result.stdout
    # checklist.md should now have 3 `## Stage N: <name>` sections
    checklist = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "## Stage 1: First bite-sized unit" in checklist
    assert "## Stage 2: Second unit" in checklist
    assert "## Stage 3: Third unit" in checklist


def test_sync_still_parses_legacy_stage_headings(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "legacy_stage.md"
    shutil.copy2(FIXTURES / "legacy_stage.md", plan)

    result = _run_sync(plan, mb)

    assert result.returncode == 0, result.stderr
    assert "stages=3" in result.stdout
    checklist = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "## Stage 1: Setup" in checklist
    assert "## Stage 2: Core logic" in checklist
    assert "## Stage 3: Finalize" in checklist


def test_sync_parses_mixed_headings(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "mixed.md"
    shutil.copy2(FIXTURES / "mixed.md", plan)

    result = _run_sync(plan, mb)

    assert result.returncode == 0, result.stderr
    # Mixed file: 1 Task + 1 Stage = 2 stages total
    assert "stages=2" in result.stdout
    checklist = (mb / "checklist.md").read_text(encoding="utf-8")
    assert "## Stage 1: Modern heading first" in checklist
    assert "## Stage 2: Legacy heading" in checklist
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/pytest/test_parse_stages_phase_sprint_task.py -v`
Expected: All 3 tests FAIL with `stages=0` or exit code 2 (parser doesn't recognize `## Task N:`).

- [ ] **Step 3: Commit failing tests (TDD red)**

```bash
git add tests/pytest/test_parse_stages_phase_sprint_task.py
git commit -m "test(plan-parser): add failing tests for Phase/Sprint/Task + legacy heading parse"
```

---

## Task 3: Extend parse_stages() in mb-plan-sync.sh

**Files:**
- Modify: `scripts/mb-plan-sync.sh:64-98` (the `parse_stages()` function and its fallback)

- [ ] **Step 1: Widen the awk regex in parse_stages() to match `## Task N:` too**

Current fallback in mb-plan-sync.sh:89-97 only matches `^### [^0-9]+[0-9]+:`. Change the fallback block to accept either `##` or `###` headings and either `Task` or `Stage` word before the number.

Replace lines 89-97:

```bash
if [ "$rc" -eq 42 ] || [ -z "$stages" ]; then
  stages=$(awk '
    /^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:/ {
      line = $0
      match(line, /[0-9]+/)
      n = substr(line, RSTART, RLENGTH)
      sub(/^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:[[:space:]]*/, "", line)
      printf "%s\t%s\n", n, line
    }
  ' "$PLAN_FILE")
fi
```

Also widen the marker-driven block (lines 64-83) so that after a `<!-- mb-stage:N -->` marker it accepts `##` or `###` heading with `Task|Stage|Phase|Sprint`:

Replace the `parse_stages()` function body:

```bash
parse_stages() {
  awk '
    BEGIN { use_markers = 0 }
    /<!-- mb-stage:[0-9]+ -->/ {
      use_markers = 1
      match($0, /[0-9]+/)
      pending = substr($0, RSTART, RLENGTH)
      next
    }
    pending != "" && /^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:/ {
      sub(/^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:[[:space:]]*/, "")
      printf "%s\t%s\n", pending, $0
      pending = ""
      next
    }
    END {
      if (use_markers == 0) exit 42
    }
  ' "$PLAN_FILE"
}
```

- [ ] **Step 2: Run the new tests to verify green**

Run: `python3 -m pytest tests/pytest/test_parse_stages_phase_sprint_task.py -v`
Expected: 3 PASSED.

- [ ] **Step 3: Run full suite to verify no regression**

Run: `python3 -m pytest tests/pytest -q`
Expected: All previously-passing tests still pass (265+).

- [ ] **Step 4: shellcheck the modified script**

Run: `shellcheck scripts/mb-plan-sync.sh`
Expected: clean (only SC1091 info about _lib.sh).

- [ ] **Step 5: Commit**

```bash
git add scripts/mb-plan-sync.sh
git commit -m "feat(plan-sync): extend parse_stages regex to Task/Stage/Phase/Sprint headings at ##-#### levels"
```

---

## Task 4: Extend parse_stages() in mb-plan-done.sh (mirror Task 3)

**Files:**
- Modify: `scripts/mb-plan-done.sh:73-105`

- [ ] **Step 1: Add failing test that verifies mb-plan-done.sh parses modern format**

Append to `tests/pytest/test_parse_stages_phase_sprint_task.py`:

```python
DONE_SCRIPT = REPO_ROOT / "scripts" / "mb-plan-done.sh"


def _run_done(plan_path: Path, mb_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(DONE_SCRIPT), str(plan_path), str(mb_path)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_done_parses_phase_sprint_task_headings(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    # status.md optional but both scripts write to it; give them an empty one.
    (mb / "status.md").write_text("# Status\n", encoding="utf-8")
    plan = mb / "plans" / "phase_sprint_task.md"
    shutil.copy2(FIXTURES / "phase_sprint_task.md", plan)

    # First, run sync so checklist has the sections mb-plan-done will remove
    sync = _run_sync(plan, mb)
    assert sync.returncode == 0, sync.stderr

    # Now close the plan
    done = _run_done(plan, mb)

    assert done.returncode == 0, done.stderr
    assert "removed_sections=3" in done.stdout
    # Plan file moved to plans/done/
    assert not plan.exists()
    assert (mb / "plans" / "done" / "phase_sprint_task.md").is_file()
```

- [ ] **Step 2: Run — expect fail**

Run: `python3 -m pytest tests/pytest/test_parse_stages_phase_sprint_task.py::test_done_parses_phase_sprint_task_headings -v`
Expected: FAIL (mb-plan-done.sh exit 2 "Failed to extract stages").

- [ ] **Step 3: Apply the same regex widening in mb-plan-done.sh**

Replace `parse_stages()` at lines 73-90 of `scripts/mb-plan-done.sh`:

```bash
parse_stages() {
  awk '
    BEGIN { use_markers = 0 }
    /<!-- mb-stage:[0-9]+ -->/ {
      use_markers = 1
      match($0, /[0-9]+/)
      pending = substr($0, RSTART, RLENGTH)
      next
    }
    pending != "" && /^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:/ {
      sub(/^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:[[:space:]]*/, "")
      printf "%s\t%s\n", pending, $0
      pending = ""
      next
    }
    END { if (use_markers == 0) exit 42 }
  ' "$PLAN_FILE"
}
```

And the fallback at lines 95-105:

```bash
if [ "$rc" -eq 42 ] || [ -z "$stages" ]; then
  stages=$(awk '
    /^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:/ {
      line = $0
      match(line, /[0-9]+/)
      n = substr(line, RSTART, RLENGTH)
      sub(/^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:[[:space:]]*/, "", line)
      printf "%s\t%s\n", n, line
    }
  ' "$PLAN_FILE")
fi
```

- [ ] **Step 4: Run test — expect pass**

Run: `python3 -m pytest tests/pytest/test_parse_stages_phase_sprint_task.py -v`
Expected: 4 PASSED.

- [ ] **Step 5: Full regression**

Run: `python3 -m pytest tests/pytest -q`
Expected: 269+ passed.

- [ ] **Step 6: shellcheck**

Run: `shellcheck scripts/mb-plan-done.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/mb-plan-done.sh tests/pytest/test_parse_stages_phase_sprint_task.py
git commit -m "feat(plan-done): extend parse_stages regex to Task/Stage/Phase/Sprint headings"
```

---

## Task 5: Contract test for mb-roadmap-sync.sh (TDD red)

**Files:**
- Create: `tests/pytest/test_roadmap_sync.py`

- [ ] **Step 1: Write the contract test upfront (Contract-First)**

File: `tests/pytest/test_roadmap_sync.py`

```python
"""Contract tests for mb-roadmap-sync.sh.

Public contract (what the script MUST do):
  C1. Scan `.memory-bank/plans/*.md` frontmatter
  C2. Between `<!-- mb-roadmap-auto -->` and `<!-- /mb-roadmap-auto -->`
      fences in roadmap.md, regenerate these sections:
        - `## Now (in progress)` — plans with status: in_progress
        - `## Next (strict order — depends)` — plans with status: queued AND depends_on non-empty
        - `## Parallel-safe (can run now)` — plans with status: queued AND parallel_safe: true AND depends_on empty
        - `## Paused / Archived` — plans with status: paused | cancelled
        - `## Linked Specs (active)` — distinct values from plans' linked_specs
  C3. Content outside the fence is preserved byte-for-byte
  C4. If fence is missing, script injects it after the `# Roadmap` H1
  C5. Idempotent: second run → byte-identical output
  C6. Exit 0 on success; non-zero on missing .memory-bank/ or malformed plan
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from textwrap import dedent

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-roadmap-sync.sh"


def _make_plan(
    plans_dir: Path,
    filename: str,
    *,
    type_: str = "feature",
    topic: str = "demo",
    status: str = "in_progress",
    depends_on: str = "[]",
    parallel_safe: str = "false",
    linked_specs: str = "[]",
    sprint: int = 1,
    phase_of: str = "demo",
) -> Path:
    body = dedent(f"""\
        ---
        type: {type_}
        topic: {topic}
        status: {status}
        depends_on: {depends_on}
        parallel_safe: {parallel_safe}
        linked_specs: {linked_specs}
        sprint: {sprint}
        phase_of: {phase_of}
        created: 2026-04-22
        ---

        # Plan: {topic}

        ## Task 1: Demo

        - [ ] Step 1
        """)
    path = plans_dir / filename
    path.write_text(body, encoding="utf-8")
    return path


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "plans").mkdir()
    (mb / "plans" / "done").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        dedent("""\
            # Roadmap

            _Last updated: stub_

            <!-- mb-roadmap-auto -->
            OLD CONTENT TO BE REPLACED
            <!-- /mb-roadmap-auto -->

            ## See also
            - traceability.md
            """),
        encoding="utf-8",
    )
    return mb


def _run(mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_contract_c1_c2_c5_basic_sync(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_now-demo.md",
        status="in_progress",
        topic="now-demo",
    )
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_next-demo.md",
        status="queued",
        depends_on="[plans/2026-04-22_feature_now-demo.md]",
        topic="next-demo",
    )
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_parallel-demo.md",
        status="queued",
        parallel_safe="true",
        topic="parallel-demo",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    assert "## Now (in progress)" in roadmap
    assert "now-demo" in roadmap
    assert "## Next (strict order — depends)" in roadmap
    assert "next-demo" in roadmap
    assert "## Parallel-safe (can run now)" in roadmap
    assert "parallel-demo" in roadmap
    # Old content gone
    assert "OLD CONTENT TO BE REPLACED" not in roadmap
    # Outside-fence content preserved
    assert "## See also" in roadmap


def test_contract_c3_outside_fence_preserved(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    # Rewrite roadmap with distinctive outside-fence content
    (mb / "roadmap.md").write_text(
        dedent("""\
            # Roadmap

            SENTINEL-OUTSIDE-A

            <!-- mb-roadmap-auto -->
            replace me
            <!-- /mb-roadmap-auto -->

            SENTINEL-OUTSIDE-B
            """),
        encoding="utf-8",
    )
    _make_plan(mb / "plans", "2026-04-22_feature_x.md", topic="x")

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    assert "SENTINEL-OUTSIDE-A" in roadmap
    assert "SENTINEL-OUTSIDE-B" in roadmap
    assert "replace me" not in roadmap


def test_contract_c4_injects_fence_when_missing(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    (mb / "roadmap.md").write_text("# Roadmap\n\nno fence yet\n", encoding="utf-8")
    _make_plan(mb / "plans", "2026-04-22_feature_y.md", topic="y")

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    assert "<!-- mb-roadmap-auto -->" in roadmap
    assert "<!-- /mb-roadmap-auto -->" in roadmap
    assert "# Roadmap" in roadmap


def test_contract_c5_idempotent(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_plan(mb / "plans", "2026-04-22_feature_a.md", topic="a")
    _make_plan(mb / "plans", "2026-04-22_feature_b.md", status="paused", topic="b")

    first = _run(mb)
    assert first.returncode == 0, first.stderr
    after_first = (mb / "roadmap.md").read_text(encoding="utf-8")

    second = _run(mb)
    assert second.returncode == 0, second.stderr
    after_second = (mb / "roadmap.md").read_text(encoding="utf-8")

    assert after_first == after_second


def test_contract_c6_missing_mb_exits_nonzero(tmp_path: Path) -> None:
    result = subprocess.run(
        ["bash", str(SCRIPT), str(tmp_path / "nonexistent")],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0


def test_paused_and_linked_specs_sections(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_paused.md",
        status="paused",
        topic="paused-one",
    )
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_with-spec.md",
        status="in_progress",
        linked_specs="[specs/demo-spec]",
        topic="with-spec",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    assert "## Paused / Archived" in roadmap
    assert "paused-one" in roadmap
    assert "## Linked Specs (active)" in roadmap
    assert "specs/demo-spec" in roadmap
```

- [ ] **Step 2: Run test — expect hard fail (script doesn't exist)**

Run: `python3 -m pytest tests/pytest/test_roadmap_sync.py -v`
Expected: ALL tests FAIL — subprocess returns non-zero because script file is missing.

- [ ] **Step 3: Commit failing contract**

```bash
git add tests/pytest/test_roadmap_sync.py
git commit -m "test(roadmap-sync): Contract-First tests for mb-roadmap-sync.sh (6 contracts)"
```

---

## Task 6: Implement mb-roadmap-sync.sh

**Files:**
- Create: `scripts/mb-roadmap-sync.sh`

- [ ] **Step 1: Create script with frontmatter parser and autosync fence regeneration**

File: `scripts/mb-roadmap-sync.sh`

```bash
#!/usr/bin/env bash
# mb-roadmap-sync.sh — regenerate roadmap.md autosync block from plans/*.md frontmatter.
#
# Usage: mb-roadmap-sync.sh [mb_path]
#
# Effects:
#   - Scan `.memory-bank/plans/*.md` (not plans/done/) for frontmatter
#   - Between `<!-- mb-roadmap-auto -->` and `<!-- /mb-roadmap-auto -->` fences,
#     emit these sections:
#       ## Now (in progress)            — status: in_progress
#       ## Next (strict order — depends) — status: queued AND depends_on non-empty
#       ## Parallel-safe (can run now)  — status: queued AND parallel_safe: true AND depends_on empty
#       ## Paused / Archived             — status: paused|cancelled
#       ## Linked Specs (active)        — distinct linked_specs entries from non-done plans
#   - Content OUTSIDE the fence is preserved byte-for-byte
#   - If fence is missing, inject it after the `# Roadmap` H1 line
#   - Idempotent
#
# Exit: 0 OK, 1 missing mb_path / malformed plan, 2 unexpected internal error.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MB_PATH=$(mb_resolve_path "${1:-}")
[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }

ROADMAP="$MB_PATH/roadmap.md"
PLANS_DIR="$MB_PATH/plans"

[ -f "$ROADMAP" ] || { echo "[error] roadmap.md not found: $ROADMAP" >&2; exit 1; }
[ -d "$PLANS_DIR" ] || { echo "[error] plans/ not found: $PLANS_DIR" >&2; exit 1; }

# Delegate the heavy lifting to python3 — YAML-ish frontmatter + section composition.
python3 - "$MB_PATH" <<'PY'
import re
import sys
from pathlib import Path

mb = Path(sys.argv[1])
roadmap_path = mb / "roadmap.md"
plans_dir = mb / "plans"

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def parse_frontmatter(text: str) -> dict[str, str]:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        out[k.strip()] = v.strip()
    return out


def parse_list(raw: str) -> list[str]:
    """Parse a YAML flow-style list like `[a, b, c]` or `[]`. Returns [] on failure."""
    raw = raw.strip()
    if not (raw.startswith("[") and raw.endswith("]")):
        return []
    inner = raw[1:-1].strip()
    if not inner:
        return []
    return [item.strip().strip('"\'') for item in inner.split(",") if item.strip()]


def plan_title(path: Path, text: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            t = line[2:].strip()
            # Strip `Type:` prefix if any
            t = re.sub(r"^[A-Za-zА-Яа-я][\w\s/-]*:[\s　]*", "", t)
            return t or path.name
    return path.name


# Collect plans (not plans/done/)
plans: list[dict[str, object]] = []
for path in sorted(plans_dir.glob("*.md")):
    if path.parent.name == "done":
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        continue
    fm = parse_frontmatter(text)
    if not fm:
        continue
    plans.append(
        {
            "path": path,
            "rel": f"plans/{path.name}",
            "status": fm.get("status", "").strip(),
            "depends_on": parse_list(fm.get("depends_on", "[]")),
            "parallel_safe": fm.get("parallel_safe", "false").strip().lower() == "true",
            "linked_specs": parse_list(fm.get("linked_specs", "[]")),
            "topic": fm.get("topic", path.stem).strip(),
            "sprint": fm.get("sprint", "").strip(),
            "phase_of": fm.get("phase_of", "").strip(),
            "title": plan_title(path, text),
        }
    )


def fmt_plan_line(p: dict[str, object], prefix: str = "- ") -> str:
    return f"{prefix}[{p['topic']}]({p['rel']}) — {p['title']}"


now_plans = [p for p in plans if p["status"] == "in_progress"]
queued = [p for p in plans if p["status"] == "queued"]
next_plans = [p for p in queued if p["depends_on"]]
parallel_plans = [p for p in queued if p["parallel_safe"] and not p["depends_on"]]
paused_plans = [p for p in plans if p["status"] in ("paused", "cancelled")]

linked_specs_set: list[str] = []
seen: set[str] = set()
for p in plans:
    if p["status"] in ("cancelled",):
        continue
    for spec in p["linked_specs"]:  # type: ignore[union-attr]
        if spec not in seen:
            seen.add(spec)
            linked_specs_set.append(spec)


def render_section(title: str, items: list[str]) -> str:
    if not items:
        return f"## {title}\n\n_None._\n"
    body = "\n".join(items)
    return f"## {title}\n\n{body}\n"


lines_now = [fmt_plan_line(p) for p in now_plans]
lines_next = [fmt_plan_line(p) for p in next_plans]
lines_parallel = [fmt_plan_line(p) for p in parallel_plans]
lines_paused = [fmt_plan_line(p) for p in paused_plans]
lines_specs = [f"- {s}" for s in linked_specs_set]

auto_body = "\n".join(
    [
        render_section("Now (in progress)", lines_now),
        render_section("Next (strict order — depends)", lines_next),
        render_section("Parallel-safe (can run now)", lines_parallel),
        render_section("Paused / Archived", lines_paused),
        render_section("Linked Specs (active)", lines_specs),
    ]
)

roadmap_text = roadmap_path.read_text(encoding="utf-8")

fence_open = "<!-- mb-roadmap-auto -->"
fence_close = "<!-- /mb-roadmap-auto -->"

block = f"{fence_open}\n{auto_body}{fence_close}\n"

if fence_open in roadmap_text and fence_close in roadmap_text:
    pattern = re.compile(
        re.escape(fence_open) + r".*?" + re.escape(fence_close) + r"\n?",
        re.DOTALL,
    )
    new_text = pattern.sub(block, roadmap_text, count=1)
else:
    # Inject after first `# Roadmap` H1 (or append at end if absent)
    h1 = re.search(r"^# Roadmap.*?$", roadmap_text, re.MULTILINE)
    if h1:
        insertion_point = h1.end()
        # Skip blank lines immediately after the H1
        m = re.match(r"\n+", roadmap_text[insertion_point:])
        if m:
            insertion_point += m.end()
        new_text = (
            roadmap_text[:insertion_point]
            + block
            + "\n"
            + roadmap_text[insertion_point:]
        )
    else:
        new_text = roadmap_text.rstrip() + "\n\n" + block

if new_text != roadmap_text:
    roadmap_path.write_text(new_text, encoding="utf-8")

print(f"[roadmap-sync] plans={len(plans)} now={len(now_plans)} next={len(next_plans)} parallel={len(parallel_plans)} paused={len(paused_plans)} specs={len(linked_specs_set)}")
PY
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/mb-roadmap-sync.sh`

- [ ] **Step 3: Run tests — expect green**

Run: `python3 -m pytest tests/pytest/test_roadmap_sync.py -v`
Expected: 6 PASSED.

- [ ] **Step 4: Full regression**

Run: `python3 -m pytest tests/pytest -q`
Expected: all green.

- [ ] **Step 5: shellcheck + ruff**

Run: `shellcheck scripts/mb-roadmap-sync.sh && ruff check scripts tests/pytest`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add scripts/mb-roadmap-sync.sh
git commit -m "feat(roadmap-sync): implement mb-roadmap-sync.sh with fence-preserving idempotent regeneration"
```

---

## Task 7: Contract test for mb-traceability-gen.sh (TDD red)

**Files:**
- Create: `tests/pytest/test_traceability_gen.py`

- [ ] **Step 1: Write contract test**

File: `tests/pytest/test_traceability_gen.py`

```python
"""Contract tests for mb-traceability-gen.sh.

Public contract:
  T1. Scan `.memory-bank/specs/*/requirements.md` for REQ-NNN definitions
      (first `- REQ-NNN:` or `### REQ-NNN` — either form)
  T2. Scan `.memory-bank/plans/*.md` AND `plans/done/*.md` for `covers_requirements:`
      frontmatter or `<!-- covers: REQ-NNN[, REQ-NNN] -->` inline markers
  T3. Scan `tests/` (if present at repo root OR at `mb_path/tests/`) for `REQ_NNN`
      substrings in file content — treat those tests as covering the REQ
  T4. Produce `.memory-bank/traceability.md` with:
        - `_Autogenerated by mb-traceability-gen.sh. Do not edit manually._` header
        - Coverage summary (Total REQs / Planned / Tested)
        - Matrix table | REQ | Spec | Plan / Stage | Tests | Status |
        - Orphans section for REQs without plan OR tests without REQ link (best-effort)
  T5. If no specs directory exists, produce a minimal `traceability.md` that says
      "No specs yet — run /mb sdd <topic> to create requirements." and exit 0
  T6. Idempotent
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from textwrap import dedent

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-traceability-gen.sh"


def _init_mb(tmp_path: Path, *, with_specs: bool = True) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "plans").mkdir()
    (mb / "plans" / "done").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text("# Roadmap\n", encoding="utf-8")
    if with_specs:
        (mb / "specs").mkdir()
        (mb / "specs" / "demo").mkdir()
        (mb / "specs" / "demo" / "requirements.md").write_text(
            dedent("""\
                # demo requirements

                - REQ-001: The system must X.
                - REQ-002: When Y, the system shall Z.
                - REQ-003: The system must W.
                """),
            encoding="utf-8",
        )
    return mb


def _run(mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_contract_t1_t4_basic_matrix(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    # Plan with frontmatter covers + one inline marker
    (mb / "plans" / "2026-04-22_feature_demo.md").write_text(
        dedent("""\
            ---
            type: feature
            topic: demo
            status: in_progress
            depends_on: []
            parallel_safe: false
            linked_specs: [specs/demo]
            sprint: 1
            phase_of: demo
            created: 2026-04-22
            covers_requirements: [REQ-001, REQ-002]
            ---

            # Plan: demo

            ## Task 1: First

            <!-- covers: REQ-003 -->
            - [ ] Step 1
            """),
        encoding="utf-8",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    assert "Autogenerated by mb-traceability-gen.sh" in trace
    assert "REQ-001" in trace
    assert "REQ-002" in trace
    assert "REQ-003" in trace
    assert "## Coverage" in trace
    assert "Total REQs: 3" in trace


def test_contract_t5_no_specs(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path, with_specs=False)
    result = _run(mb)
    assert result.returncode == 0, result.stderr
    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    assert "No specs yet" in trace


def test_contract_t6_idempotent(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    first = _run(mb)
    assert first.returncode == 0, first.stderr
    after_first = (mb / "traceability.md").read_text(encoding="utf-8")

    second = _run(mb)
    assert second.returncode == 0, second.stderr
    after_second = (mb / "traceability.md").read_text(encoding="utf-8")
    assert after_first == after_second


def test_orphan_detection(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    # Plan covers only REQ-001 — REQ-002 and REQ-003 become orphans
    (mb / "plans" / "2026-04-22_feature_partial.md").write_text(
        dedent("""\
            ---
            type: feature
            topic: partial
            status: in_progress
            depends_on: []
            parallel_safe: false
            linked_specs: [specs/demo]
            sprint: 1
            phase_of: demo
            created: 2026-04-22
            covers_requirements: [REQ-001]
            ---

            # Plan: partial

            ## Task 1: First
            """),
        encoding="utf-8",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    trace = (mb / "traceability.md").read_text(encoding="utf-8")
    assert "## Orphans" in trace
    # REQ-002 and REQ-003 uncovered → should appear in orphan list
    assert "REQ-002" in trace.split("## Orphans")[1]
    assert "REQ-003" in trace.split("## Orphans")[1]
```

- [ ] **Step 2: Run — expect hard fail (script missing)**

Run: `python3 -m pytest tests/pytest/test_traceability_gen.py -v`
Expected: all FAIL.

- [ ] **Step 3: Commit failing contract**

```bash
git add tests/pytest/test_traceability_gen.py
git commit -m "test(traceability-gen): Contract-First tests for mb-traceability-gen.sh (6 contracts)"
```

---

## Task 8: Implement mb-traceability-gen.sh

**Files:**
- Create: `scripts/mb-traceability-gen.sh`

- [ ] **Step 1: Create script**

File: `scripts/mb-traceability-gen.sh`

```bash
#!/usr/bin/env bash
# mb-traceability-gen.sh — regenerate traceability.md from specs + plans + tests.
#
# Usage: mb-traceability-gen.sh [mb_path]
#
# Scans:
#   .memory-bank/specs/*/requirements.md  — REQ-NNN definitions
#   .memory-bank/plans/*.md + plans/done/*.md — covers_requirements frontmatter
#                                              + `<!-- covers: REQ-NNN -->` markers
#   tests/ (project root) AND mb_path/tests/ — grep for `REQ_NNN` substrings
#
# Writes: .memory-bank/traceability.md (full regeneration; idempotent).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MB_PATH=$(mb_resolve_path "${1:-}")
[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }

python3 - "$MB_PATH" <<'PY'
import re
import sys
from pathlib import Path

mb = Path(sys.argv[1])
specs_dir = mb / "specs"
plans_dir = mb / "plans"
out_path = mb / "traceability.md"

REQ_RE = re.compile(r"\bREQ-(\d{3,})\b")
REQ_TEST_RE = re.compile(r"\bREQ_(\d{3,})\b")

# T5: handle no-specs state
if not specs_dir.is_dir() or not any(specs_dir.glob("*/requirements.md")):
    out_path.write_text(
        "# Traceability Matrix\n\n"
        "_Autogenerated by mb-traceability-gen.sh. Do not edit manually._\n\n"
        "No specs yet — run `/mb sdd <topic>` to create requirements.\n",
        encoding="utf-8",
    )
    print("[traceability-gen] no specs — minimal output written")
    sys.exit(0)

# T1: collect REQs from each spec
reqs: dict[str, dict[str, str]] = {}
for req_file in sorted(specs_dir.glob("*/requirements.md")):
    spec_name = req_file.parent.name
    text = req_file.read_text(encoding="utf-8")
    for m in REQ_RE.finditer(text):
        req_id = f"REQ-{m.group(1)}"
        reqs.setdefault(
            req_id,
            {"spec": f"specs/{spec_name}/requirements.md", "planned": "", "tests": ""},
        )


def parse_list(raw: str) -> list[str]:
    raw = raw.strip()
    if not (raw.startswith("[") and raw.endswith("]")):
        return []
    inner = raw[1:-1].strip()
    if not inner:
        return []
    return [item.strip().strip('"\'') for item in inner.split(",") if item.strip()]


FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
COVERS_MARKER_RE = re.compile(r"<!--\s*covers:\s*([^-]+?)\s*-->")


def plan_paths() -> list[Path]:
    out: list[Path] = []
    for p in sorted(plans_dir.glob("*.md")):
        out.append(p)
    done = plans_dir / "done"
    if done.is_dir():
        for p in sorted(done.glob("*.md")):
            out.append(p)
    return out


# T2: collect plan coverage
for plan in plan_paths():
    text = plan.read_text(encoding="utf-8")
    covered: set[str] = set()
    fm = FRONTMATTER_RE.match(text)
    if fm:
        for line in fm.group(1).splitlines():
            if line.strip().startswith("covers_requirements:"):
                _, _, v = line.partition(":")
                covered.update(parse_list(v))
    for m in COVERS_MARKER_RE.finditer(text):
        for item in m.group(1).split(","):
            item = item.strip()
            if REQ_RE.fullmatch(item):
                covered.add(item)
    if not covered:
        continue
    rel = plan.relative_to(mb).as_posix()
    for req in covered:
        if req in reqs:
            existing = reqs[req]["planned"]
            reqs[req]["planned"] = (existing + " " if existing else "") + rel

# T3: grep tests at repo-root/tests and mb/tests
test_roots = [mb.parent / "tests", mb / "tests"]
for root in test_roots:
    if not root.is_dir():
        continue
    for tf in root.rglob("*"):
        if not tf.is_file():
            continue
        if tf.suffix not in {".py", ".ts", ".tsx", ".js", ".go", ".rs", ".sh"}:
            continue
        try:
            content = tf.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        hits: set[str] = set()
        for m in REQ_RE.finditer(content):
            hits.add(f"REQ-{m.group(1)}")
        for m in REQ_TEST_RE.finditer(content):
            hits.add(f"REQ-{m.group(1)}")
        if not hits:
            continue
        rel = tf.relative_to(mb.parent if root == mb.parent / "tests" else mb).as_posix()
        for req in hits:
            if req in reqs:
                existing = reqs[req]["tests"]
                reqs[req]["tests"] = (existing + " " if existing else "") + rel

# Compose output
total = len(reqs)
planned = sum(1 for r in reqs.values() if r["planned"])
tested = sum(1 for r in reqs.values() if r["tests"])


def status_for(r: dict[str, str]) -> str:
    if r["planned"] and r["tests"]:
        return "✅"
    if r["planned"]:
        return "🏗️"
    return "⬜"


rows = []
for req_id in sorted(reqs):
    r = reqs[req_id]
    rows.append(
        f"| {req_id} | {r['spec']} | {r['planned'] or '—'} | {r['tests'] or '—'} | {status_for(r)} |"
    )

orphans = [req_id for req_id, r in sorted(reqs.items()) if not r["planned"]]

body = [
    "# Traceability Matrix",
    "",
    "_Autogenerated by mb-traceability-gen.sh. Do not edit manually._",
    "",
    "## Coverage",
    f"- Total REQs: {total}",
    f"- Planned: {planned}",
    f"- Tested: {tested}",
    "",
    "## Matrix",
    "",
    "| REQ | Spec | Plan / Stage | Tests | Status |",
    "|-----|------|--------------|-------|--------|",
]
body.extend(rows if rows else ["| _no REQs_ | — | — | — | — |"])

body.extend(
    [
        "",
        "## Orphans",
        "",
        *(
            [f"- {req} — in spec but no covering plan" for req in orphans]
            if orphans
            else ["_None._"]
        ),
        "",
    ]
)

out_path.write_text("\n".join(body), encoding="utf-8")
print(f"[traceability-gen] total={total} planned={planned} tested={tested} orphans={len(orphans)}")
PY
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/mb-traceability-gen.sh`

- [ ] **Step 3: Run tests — expect green**

Run: `python3 -m pytest tests/pytest/test_traceability_gen.py -v`
Expected: 4 PASSED.

- [ ] **Step 4: Full regression + lint**

Run: `python3 -m pytest tests/pytest -q && shellcheck scripts/mb-traceability-gen.sh && ruff check scripts tests/pytest`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/mb-traceability-gen.sh
git commit -m "feat(traceability-gen): implement mb-traceability-gen.sh with zero-spec fallback and orphan detection"
```

---

## Task 9: Wire mb-roadmap-sync + mb-traceability-gen into mb-plan-sync.sh and mb-plan-done.sh

**Files:**
- Modify: `scripts/mb-plan-sync.sh` (append chain call before final `echo`)
- Modify: `scripts/mb-plan-done.sh` (same)

- [ ] **Step 1: Add failing test for chain invocation**

Append to `tests/pytest/test_parse_stages_phase_sprint_task.py`:

```python
def test_sync_chain_updates_roadmap_and_traceability(tmp_path: Path) -> None:
    """mb-plan-sync.sh must trigger mb-roadmap-sync.sh + mb-traceability-gen.sh at end-of-run."""
    mb = _init_mb(tmp_path)
    # Pre-populate roadmap with the autosync fence so we can detect regeneration
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n<!-- mb-roadmap-auto -->\nINITIAL\n<!-- /mb-roadmap-auto -->\n",
        encoding="utf-8",
    )
    plan = mb / "plans" / "phase_sprint_task.md"
    shutil.copy2(FIXTURES / "phase_sprint_task.md", plan)

    result = _run_sync(plan, mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    # After chain call, INITIAL is gone and plan topic appears
    assert "INITIAL" not in roadmap
    assert "fixture-phase-sprint-task" in roadmap
    # traceability.md should exist (no-specs fallback)
    assert (mb / "traceability.md").is_file()
```

- [ ] **Step 2: Run — expect fail**

Run: `python3 -m pytest tests/pytest/test_parse_stages_phase_sprint_task.py::test_sync_chain_updates_roadmap_and_traceability -v`
Expected: FAIL — "INITIAL" still in roadmap (chain not wired).

- [ ] **Step 3: Wire into mb-plan-sync.sh**

Edit `scripts/mb-plan-sync.sh`. Replace the final report block (the `echo "[sync] ..."` line) with:

```bash
# ═══════════════════════════════════════════════════════════════
# Report
# ═══════════════════════════════════════════════════════════════
stage_count=$(printf '%s\n' "$stages" | grep -c . || true)
echo "[sync] plan=$BASENAME stages=$stage_count added=$added_count"

# ═══════════════════════════════════════════════════════════════
# Chain: roadmap-sync + traceability-gen (best-effort — warn, don't fail)
# ═══════════════════════════════════════════════════════════════
SCRIPT_DIR=$(dirname "$0")
if [ -x "$SCRIPT_DIR/mb-roadmap-sync.sh" ]; then
  "$SCRIPT_DIR/mb-roadmap-sync.sh" "$MB_PATH" || echo "[warn] mb-roadmap-sync.sh failed (non-fatal)" >&2
fi
if [ -x "$SCRIPT_DIR/mb-traceability-gen.sh" ]; then
  "$SCRIPT_DIR/mb-traceability-gen.sh" "$MB_PATH" || echo "[warn] mb-traceability-gen.sh failed (non-fatal)" >&2
fi
```

- [ ] **Step 4: Wire into mb-plan-done.sh**

Edit `scripts/mb-plan-done.sh`. Append after the final `echo "[done] ..."` line:

```bash
# ═══════════════════════════════════════════════════════════════
# Chain: roadmap-sync + traceability-gen (best-effort — warn, don't fail)
# ═══════════════════════════════════════════════════════════════
SCRIPT_DIR=$(dirname "$0")
if [ -x "$SCRIPT_DIR/mb-roadmap-sync.sh" ]; then
  "$SCRIPT_DIR/mb-roadmap-sync.sh" "$MB_PATH" || echo "[warn] mb-roadmap-sync.sh failed (non-fatal)" >&2
fi
if [ -x "$SCRIPT_DIR/mb-traceability-gen.sh" ]; then
  "$SCRIPT_DIR/mb-traceability-gen.sh" "$MB_PATH" || echo "[warn] mb-traceability-gen.sh failed (non-fatal)" >&2
fi
```

- [ ] **Step 5: Run tests — expect green**

Run: `python3 -m pytest tests/pytest -q`
Expected: all green.

- [ ] **Step 6: shellcheck**

Run: `shellcheck scripts/mb-plan-sync.sh scripts/mb-plan-done.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/mb-plan-sync.sh scripts/mb-plan-done.sh tests/pytest/test_parse_stages_phase_sprint_task.py
git commit -m "feat(plan-chain): auto-invoke mb-roadmap-sync + mb-traceability-gen from plan-sync/plan-done"
```

---

## Task 10: Slash commands `/mb roadmap-sync` and `/mb traceability-gen`

**Files:**
- Create: `commands/roadmap-sync.md`
- Create: `commands/traceability-gen.md`

- [ ] **Step 1: Create roadmap-sync command file**

File: `commands/roadmap-sync.md`

```markdown
---
description: Regenerate roadmap.md autosync block from plans/*.md frontmatter
---

# /mb roadmap-sync

Regenerate `.memory-bank/roadmap.md` autosync block from `plans/*.md` frontmatter.

## What it does

Scans `.memory-bank/plans/*.md` (not `plans/done/`) for frontmatter fields:
- `status` — in_progress / queued / paused / cancelled
- `depends_on` — list of plan paths
- `parallel_safe` — true / false
- `linked_specs` — list of spec paths

Regenerates sections between `<!-- mb-roadmap-auto -->` fences:
- `## Now (in progress)`
- `## Next (strict order — depends)`
- `## Parallel-safe (can run now)`
- `## Paused / Archived`
- `## Linked Specs (active)`

Content outside the fence is preserved byte-for-byte. Idempotent.

## Usage

Run this command when plan frontmatter changes (status flip, new plan added, spec linked).

Under the hood it invokes `scripts/mb-roadmap-sync.sh`. Also runs automatically at the end of `/mb plan` and `/mb done`.

## Exit codes

- `0` — success
- `1` — `.memory-bank/` not found or malformed plan frontmatter
```

- [ ] **Step 2: Create traceability-gen command file**

File: `commands/traceability-gen.md`

```markdown
---
description: Regenerate traceability.md from specs + plans + tests
---

# /mb traceability-gen

Regenerate `.memory-bank/traceability.md` — the REQ → Plan → Test coverage matrix.

## What it does

Scans:
- `.memory-bank/specs/*/requirements.md` for `REQ-NNN` definitions
- `.memory-bank/plans/*.md` + `plans/done/*.md` for:
  - `covers_requirements: [REQ-NNN, ...]` frontmatter field
  - `<!-- covers: REQ-NNN -->` inline markers
- `tests/` (repo root) and `.memory-bank/tests/` for `REQ_NNN` / `REQ-NNN` substrings

Produces a full-overwrite `traceability.md` with:
- Coverage summary (Total / Planned / Tested)
- Matrix table
- Orphans section (REQs in spec but no covering plan)

## Zero-spec fallback

If no `specs/*/requirements.md` exists, produces a minimal `traceability.md` saying
"No specs yet — run `/mb sdd <topic>` to create requirements." and exits 0.

## Usage

Run after adding requirements, wiring `covers_requirements:` in a plan, or adding REQ-NNN markers to tests. Also runs automatically at the end of `/mb plan` and `/mb done`.

## Exit codes

- `0` — success
- `1` — `.memory-bank/` not found
```

- [ ] **Step 3: Verify command files parse as valid YAML frontmatter + markdown**

Run: `python3 -c "
from pathlib import Path
import re
for f in Path('commands').glob('*.md'):
    text = f.read_text()
    if text.startswith('---'):
        m = re.match(r'^---\s*\n.*?\n---\s*\n', text, re.DOTALL)
        assert m, f'{f}: bad frontmatter'
print('ok')
"`
Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add commands/roadmap-sync.md commands/traceability-gen.md
git commit -m "feat(commands): add /mb roadmap-sync and /mb traceability-gen slash commands"
```

---

## Task 11: Final regression + Sprint 2 gate verification

**Files:**
- None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `python3 -m pytest tests/pytest -v --tb=short 2>&1 | tail -40`
Expected: all tests pass, no failures. Expected new count: ~275+.

- [ ] **Step 2: shellcheck all shell scripts**

Run: `find scripts -name '*.sh' -exec shellcheck {} +`
Expected: clean (only SC1091 info from _lib.sh source lines).

- [ ] **Step 3: ruff lint**

Run: `ruff check scripts tests/pytest`
Expected: `All checks passed!`

- [ ] **Step 4: Verify Sprint 2 gate manually**

Run:
```bash
# Create a throwaway .memory-bank with one in-progress plan
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.memory-bank/plans"
cat > "$tmpdir/.memory-bank/checklist.md" <<'EOF'
# Checklist
EOF
cat > "$tmpdir/.memory-bank/roadmap.md" <<'EOF'
# Roadmap
EOF
cat > "$tmpdir/.memory-bank/plans/2026-04-22_feature_smoke.md" <<'EOF'
---
type: feature
topic: smoke
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
sprint: 1
phase_of: smoke
created: 2026-04-22
---
# Plan: smoke

## Task 1: Do thing

- [ ] Step 1
EOF

bash scripts/mb-roadmap-sync.sh "$tmpdir/.memory-bank"
bash scripts/mb-traceability-gen.sh "$tmpdir/.memory-bank"
bash scripts/mb-plan-sync.sh "$tmpdir/.memory-bank/plans/2026-04-22_feature_smoke.md" "$tmpdir/.memory-bank"
cat "$tmpdir/.memory-bank/roadmap.md"
cat "$tmpdir/.memory-bank/traceability.md"
cat "$tmpdir/.memory-bank/checklist.md"
rm -rf "$tmpdir"
```
Expected:
- `roadmap.md` shows `smoke` under `## Now (in progress)`
- `traceability.md` has "No specs yet" or (if specs/ exists) matrix
- `checklist.md` has `## Stage 1: Do thing`

- [ ] **Step 5: Move plan file to plans/done/ and update status**

Update frontmatter of this plan file: `status: done`.

```bash
sed -i '' 's/^status: in_progress/status: done/' .memory-bank/plans/2026-04-22_refactor_skill-v2-phase1-sprint2-autosync.md
```

- [ ] **Step 6: Final commit**

```bash
git add .memory-bank/plans/2026-04-22_refactor_skill-v2-phase1-sprint2-autosync.md
git commit -m "chore(sprint-2): finalize plan status: done; Phase 1 Sprint 2 complete"
```

---

## Appendix — Self-review checklist (I did this myself before handing over to implementer)

- [x] Spec coverage: every gate item maps to a task
  - Gate 1 (roadmap-sync contract) → Tasks 5+6
  - Gate 2 (traceability-gen) → Tasks 7+8
  - Gate 3 (Phase/Sprint/Task parser) → Tasks 1–4
  - Gate 4 (slash commands) → Task 10
  - Gate 5 (auto-chain) → Task 9
  - Gate 6 (regression) → Task 11
  - Gate 7 (new tests) → Tasks 2, 5, 7
  - Gate 8 (lint) → Tasks 3, 6, 8, 11
- [x] No placeholders: every step has exact code, exact paths, exact commands
- [x] Type consistency: `parse_list`, `FRONTMATTER_RE`, status strings are consistent across Tasks 6 and 8
- [x] TDD: test-first in Tasks 2→3, 5→6, 7→8, 9
- [x] Frequent commits: 11 commits at minimum
- [x] bash 3.2 compat: no `declare -A`, no `${var,,}`, no `${var^^}`
- [x] Idempotency: both generators guaranteed by contract tests
