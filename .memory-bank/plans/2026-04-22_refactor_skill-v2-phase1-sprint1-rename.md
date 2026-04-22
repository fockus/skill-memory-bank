---
type: refactor
topic: skill-v2-phase1-sprint1-rename
status: queued
depends_on: []
parallel_safe: false
linked_specs: [specs/mb-skill-v2]
sprint: 1
phase_of: skill-v2-phase1
created: 2026-04-22
---

# Skill v2 — Phase 1 Sprint 1: Rename Migration (v1 → v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `STATUS.md/BACKLOG.md/RESEARCH.md/plan.md` → `status.md/backlog.md/research.md/roadmap.md` across skill code and user `.memory-bank/` directories, with a safe idempotent migration script, backup, autodetect, and full backward compatibility window.

**Architecture:** One migration script (`mb-migrate-v2.sh`) handles user `.memory-bank/` rename + content transform + reference fixup. Skill's own code (commands, references, scripts, agents, adapters, tests, docs) is updated in-place via a structured refactor. Autodetect in `/mb start` / `/mb context` / `/mb doctor` prompts users to run migration. 2-version backward-compat window: scripts continue to read old names if present.

**Tech Stack:** bash (scripts), pytest (tests), grep/sed (fixups), Python helpers where logic is complex.

**Gate (Sprint 1 success):**
1. `mb-migrate-v2.sh --dry-run` prints diff without side effects
2. `mb-migrate-v2.sh --apply` migrates a v1 fixture to v2 idempotently (twice = noop second run)
3. Skill's own tests all pass (regression clean)
4. Skill's own `.memory-bank/` migrated (dogfood)
5. `/mb doctor` detects unmigrated `.memory-bank/` and prints clear remediation
6. All skill code references new lowercase names; no references to `STATUS.md/BACKLOG.md/RESEARCH.md/plan.md` remain except in: `scripts/mb-migrate-v2.sh` (logic), `CHANGELOG.md` (history), `docs/MIGRATION-v3-v3.1.md` (historical)

---

## File Structure

**New files:**
- `scripts/mb-migrate-v2.sh` — main migration script (rename + content transform + refs fixup)
- `tests/pytest/test_migrate_v2.py` — pytest for migration logic
- `tests/pytest/fixtures/mb_v1_layout/` — fixture directory mimicking v1 `.memory-bank/`
- `docs/MIGRATION-v1-v2.md` — user-facing migration guide

**Modified files (bulk refactor, lowercase names):**
- `commands/mb.md`, `commands/start.md`, `commands/done.md`, `commands/plan.md`, `commands/catchup.md`, `commands/adr.md`, `commands/changelog.md`
- `references/structure.md`, `references/templates.md`, `references/planning-and-verification.md`, `references/command-template.md`, `references/workflow.md`, `references/metadata.md`, `references/claude-md-template.md`
- `agents/mb-doctor.md`, `agents/mb-manager.md`, `agents/plan-verifier.md`
- `scripts/mb-plan-sync.sh`, `scripts/mb-plan-done.sh`, `scripts/mb-compact.sh`, `scripts/mb-drift.sh`, `scripts/mb-idea.sh`, `scripts/mb-idea-promote.sh`, `scripts/mb-adr.sh`, `scripts/mb-context.sh`, `scripts/mb-index.sh`, `scripts/mb-init-bank.sh`, `scripts/mb-metrics.sh`, `scripts/mb-search.sh`, `scripts/mb-tags-normalize.sh`, `scripts/mb-upgrade.sh`, `scripts/mb-rules-check.sh`, `scripts/mb-config.sh`, `scripts/mb-import.py`, `scripts/mb-index-json.py`
- `adapters/windsurf.sh`, `adapters/cline.sh`, `adapters/cursor.sh`, `adapters/pi.sh`, `adapters/kilo.sh`, `adapters/_lib_agents_md.sh`
- `tests/pytest/test_templates_format.py`, `tests/pytest/test_locales_structure.py`, `tests/pytest/test_import.py`
- `memory_bank_skill/cli.py`
- `install.sh`
- `SKILL.md`, `README.md`, `CHANGELOG.md`, `CLAUDE.md` (skill's own)
- `.memory-bank/` of the skill itself (dogfood migration)

**Extended files:**
- `scripts/mb-doctor.sh` (if exists) or `agents/mb-doctor.md` — add migration check
- `commands/start.md`, `commands/mb.md` — autodetect old layout, prompt migration

**Preserved references to old names (intentional):**
- `scripts/mb-migrate-v2.sh` — migration logic must reference both
- `CHANGELOG.md` — historical release notes
- `docs/MIGRATION-v3-v3.1.md` — historical migration doc

---

## Task 1: Create v1 fixture for migration tests

**Files:**
- Create: `tests/pytest/fixtures/mb_v1_layout/STATUS.md`
- Create: `tests/pytest/fixtures/mb_v1_layout/BACKLOG.md`
- Create: `tests/pytest/fixtures/mb_v1_layout/RESEARCH.md`
- Create: `tests/pytest/fixtures/mb_v1_layout/plan.md`
- Create: `tests/pytest/fixtures/mb_v1_layout/checklist.md`
- Create: `tests/pytest/fixtures/mb_v1_layout/progress.md`
- Create: `tests/pytest/fixtures/mb_v1_layout/notes/2026-04-15_12-00_example.md`
- Create: `tests/pytest/fixtures/mb_v1_layout/plans/2026-04-20_feature_example.md`

- [ ] **Step 1: Create fixture directory and v1 files**

Run:
```bash
mkdir -p tests/pytest/fixtures/mb_v1_layout/{notes,plans,plans/done}
```

Write `tests/pytest/fixtures/mb_v1_layout/STATUS.md`:
```markdown
# Status

_Last updated: 2026-04-15_

## Current phase
Refactor auth system — Sprint 1/3

## Metrics
- Tests: 142 passing
- Coverage: 87%

## See also
- See plan.md for priorities
- See BACKLOG.md for ideas
- See RESEARCH.md for hypotheses
```

Write `tests/pytest/fixtures/mb_v1_layout/plan.md`:
```markdown
# Plan

## Priorities
1. Finish auth refactor
2. Start billing module

<!-- mb-active-plan -->
Active plan: plans/2026-04-20_feature_example.md
Current stage: Stage 2
<!-- /mb-active-plan -->

## Direction
Focus on backend work this sprint.
```

Write `tests/pytest/fixtures/mb_v1_layout/BACKLOG.md`:
```markdown
# Backlog

## Ideas
- **I-001**: Add GraphQL layer
- **I-002**: Cache invalidation via Redis

## ADR
- **ADR-001**: Use JWT for session tokens
```

Write `tests/pytest/fixtures/mb_v1_layout/RESEARCH.md`:
```markdown
# Research

## Active hypotheses
- **H-001**: Rate limiting via token bucket reduces abuse by 80%
```

Write `tests/pytest/fixtures/mb_v1_layout/checklist.md`:
```markdown
# Checklist

## Stage 1: Setup
- [x] Initialize module
- [x] Write base tests

## Stage 2: Core logic
- [ ] Implement handler
- [ ] Write integration tests
```

Write `tests/pytest/fixtures/mb_v1_layout/progress.md`:
```markdown
# Progress

## 2026-04-15
- Kicked off auth refactor
- Completed Stage 1 of plan
```

Write `tests/pytest/fixtures/mb_v1_layout/notes/2026-04-15_12-00_example.md`:
```markdown
---
topic: example
tags: [auth, refactor]
---

# Note: Example

Small observation about auth module.
Reference: see STATUS.md for context.
```

Write `tests/pytest/fixtures/mb_v1_layout/plans/2026-04-20_feature_example.md`:
```markdown
---
type: feature
topic: example
created: 2026-04-20
---

# Plan: Example

## Context
Reference: see plan.md and BACKLOG.md.

<!-- mb-stage:1 -->
## Stage 1: Setup
- [x] Init
<!-- /mb-stage:1 -->

<!-- mb-stage:2 -->
## Stage 2: Core logic
- [ ] Impl
<!-- /mb-stage:2 -->
```

- [ ] **Step 2: Verify fixture shape**

Run:
```bash
find tests/pytest/fixtures/mb_v1_layout -type f | sort
```

Expected output (exactly these 8 files):
```
tests/pytest/fixtures/mb_v1_layout/BACKLOG.md
tests/pytest/fixtures/mb_v1_layout/RESEARCH.md
tests/pytest/fixtures/mb_v1_layout/STATUS.md
tests/pytest/fixtures/mb_v1_layout/checklist.md
tests/pytest/fixtures/mb_v1_layout/notes/2026-04-15_12-00_example.md
tests/pytest/fixtures/mb_v1_layout/plan.md
tests/pytest/fixtures/mb_v1_layout/plans/2026-04-20_feature_example.md
tests/pytest/fixtures/mb_v1_layout/progress.md
```

- [ ] **Step 3: Commit**

```bash
git add tests/pytest/fixtures/mb_v1_layout/
git commit -m "test(migrate-v2): add v1 .memory-bank fixture for migration tests"
```

---

## Task 2: Write failing detection test

**Files:**
- Create: `tests/pytest/test_migrate_v2.py`

- [ ] **Step 1: Write failing test `test_detect_v1_layout`**

Write `tests/pytest/test_migrate_v2.py`:
```python
"""Tests for scripts/mb-migrate-v2.sh — rename migration v1 → v2."""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-migrate-v2.sh"
FIXTURE = REPO_ROOT / "tests" / "pytest" / "fixtures" / "mb_v1_layout"


@pytest.fixture
def v1_copy(tmp_path: Path) -> Path:
    """Return a freshly-copied v1 layout in a tmp dir."""
    dest = tmp_path / ".memory-bank"
    shutil.copytree(FIXTURE, dest)
    return dest


def run_script(mb_path: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, str(mb_path)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_detect_v1_layout(v1_copy: Path) -> None:
    """Script detects v1 and reports what will change."""
    result = run_script(v1_copy, "--dry-run")
    assert result.returncode == 0, result.stderr
    assert "STATUS.md → status.md" in result.stdout
    assert "BACKLOG.md → backlog.md" in result.stdout
    assert "RESEARCH.md → research.md" in result.stdout
    assert "plan.md → roadmap.md" in result.stdout
```

- [ ] **Step 2: Run test — must fail (script not yet created)**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py::test_detect_v1_layout -v
```

Expected: FAIL with `FileNotFoundError` or non-zero exit (script missing).

- [ ] **Step 3: Commit test**

```bash
git add tests/pytest/test_migrate_v2.py
git commit -m "test(migrate-v2): add failing detection test for v1 layout"
```

---

## Task 3: Create migration script skeleton with dry-run detection

**Files:**
- Create: `scripts/mb-migrate-v2.sh`

- [ ] **Step 1: Write script skeleton — detection only**

Write `scripts/mb-migrate-v2.sh`:
```bash
#!/usr/bin/env bash
# mb-migrate-v2.sh — one-shot v1 → v2 migrator for .memory-bank/
#
# Renames STATUS/BACKLOG/RESEARCH/plan → lowercase status/backlog/research/roadmap,
# transforms plan.md → roadmap.md content structure, fixes references,
# creates a timestamped backup.
#
# Usage: mb-migrate-v2.sh [--dry-run|--apply] [mb_path]

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MODE="dry-run"
MB_ARG=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --*)
      echo "[error] unknown flag: $arg" >&2
      echo "Usage: mb-migrate-v2.sh [--dry-run|--apply] [mb_path]" >&2
      exit 1
      ;;
    *) MB_ARG="$arg" ;;
  esac
done

MB_PATH=$(mb_resolve_path "$MB_ARG")
[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }
MB_PATH=$(cd "$MB_PATH" && pwd)

# === Detection ===
# Using parallel arrays (bash 3.2 compatible — macOS default shell).
RENAMES_OLD=("STATUS.md" "BACKLOG.md" "RESEARCH.md" "plan.md")
RENAMES_NEW=("status.md" "backlog.md" "research.md" "roadmap.md")

planned_renames=()
for i in "${!RENAMES_OLD[@]}"; do
  old="${RENAMES_OLD[$i]}"
  new="${RENAMES_NEW[$i]}"
  if [ -f "$MB_PATH/$old" ] && [ ! -f "$MB_PATH/$new" ]; then
    planned_renames+=("$old → $new")
  fi
done

if [ "${#planned_renames[@]}" -eq 0 ]; then
  echo "[ok] no v1 files detected — nothing to migrate"
  exit 0
fi

echo "[detected] v1 layout — planned renames:"
for r in "${planned_renames[@]}"; do
  echo "  - $r"
done

if [ "$MODE" = "dry-run" ]; then
  echo "[dry-run] no files changed — run with --apply to execute"
  exit 0
fi

# === Apply (stub until Task 4+) ===
echo "[error] --apply not yet implemented" >&2
exit 2
```

- [ ] **Step 2: Make executable**

Run:
```bash
chmod +x scripts/mb-migrate-v2.sh
```

- [ ] **Step 3: Run detection test — must now pass**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py::test_detect_v1_layout -v
```

Expected: PASS.

- [ ] **Step 4: Commit skeleton**

```bash
git add scripts/mb-migrate-v2.sh
git commit -m "feat(migrate-v2): add detection-only skeleton with --dry-run"
```

---

## Task 4: Implement rename + backup (file-level only, no content transform)

**Files:**
- Modify: `scripts/mb-migrate-v2.sh`
- Modify: `tests/pytest/test_migrate_v2.py`

- [ ] **Step 1: Write failing test for rename + backup**

Append to `tests/pytest/test_migrate_v2.py`:
```python
def test_apply_renames_files(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    # Old files gone, new files present
    assert not (v1_copy / "STATUS.md").exists()
    assert not (v1_copy / "BACKLOG.md").exists()
    assert not (v1_copy / "RESEARCH.md").exists()
    assert not (v1_copy / "plan.md").exists()
    assert (v1_copy / "status.md").is_file()
    assert (v1_copy / "backlog.md").is_file()
    assert (v1_copy / "research.md").is_file()
    assert (v1_copy / "roadmap.md").is_file()


def test_apply_creates_backup(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    backups = sorted(v1_copy.glob(".migration-backup-*/"))
    assert len(backups) == 1
    backup = backups[0]
    # Backup contains all original files with original names
    assert (backup / "STATUS.md").is_file()
    assert (backup / "BACKLOG.md").is_file()
    assert (backup / "RESEARCH.md").is_file()
    assert (backup / "plan.md").is_file()
```

- [ ] **Step 2: Run — both tests fail**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py::test_apply_renames_files tests/pytest/test_migrate_v2.py::test_apply_creates_backup -v
```

Expected: both FAIL (script currently exits with error 2 on `--apply`).

- [ ] **Step 3: Replace stub `--apply` section with real implementation**

In `scripts/mb-migrate-v2.sh`, replace the final `echo "[error] --apply not yet implemented" >&2; exit 2` with:

```bash
# === Backup ===
ts=$(date +%Y%m%d-%H%M%S)
backup_dir="$MB_PATH/.migration-backup-$ts"
mkdir -p "$backup_dir"
for i in "${!RENAMES_OLD[@]}"; do
  old="${RENAMES_OLD[$i]}"
  if [ -f "$MB_PATH/$old" ]; then
    cp "$MB_PATH/$old" "$backup_dir/$old"
  fi
done
echo "[backup] saved to $backup_dir"

# === Rename ===
for i in "${!RENAMES_OLD[@]}"; do
  old="${RENAMES_OLD[$i]}"
  new="${RENAMES_NEW[$i]}"
  if [ -f "$MB_PATH/$old" ] && [ ! -f "$MB_PATH/$new" ]; then
    mv "$MB_PATH/$old" "$MB_PATH/$new"
    echo "[renamed] $old → $new"
  fi
done

echo "[ok] rename phase complete — see Task 5 for content transform"
```

- [ ] **Step 4: Run both tests — must pass**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py -v
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/mb-migrate-v2.sh tests/pytest/test_migrate_v2.py
git commit -m "feat(migrate-v2): implement rename + backup"
```

---

## Task 5: Implement content transform plan.md → roadmap.md

Transform `plan.md` content into the new roadmap format: wrap legacy `<!-- mb-active-plan -->` into `## Now (in progress)` section, move "priorities/direction" text into `## See also`, add empty skeleton sections.

**Files:**
- Modify: `scripts/mb-migrate-v2.sh`
- Modify: `tests/pytest/test_migrate_v2.py`

- [ ] **Step 1: Write failing test for roadmap.md content**

Append to `tests/pytest/test_migrate_v2.py`:
```python
def test_roadmap_content_transformed(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    roadmap = (v1_copy / "roadmap.md").read_text(encoding="utf-8")
    # New sections present
    assert "# Roadmap" in roadmap
    assert "## Now (in progress)" in roadmap
    assert "## Next" in roadmap
    assert "## Parallel-safe" in roadmap
    assert "## Paused / Archived" in roadmap
    assert "## Linked Specs" in roadmap
    # Legacy content preserved in See also
    assert "## See also" in roadmap
    # Active plan block carried over
    assert "<!-- mb-active-plan -->" in roadmap
    assert "plans/2026-04-20_feature_example.md" in roadmap
```

- [ ] **Step 2: Run — fails (no transform yet)**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py::test_roadmap_content_transformed -v
```

Expected: FAIL (roadmap.md contains raw plan.md copy, missing new sections).

- [ ] **Step 3: Add content transform after rename phase**

In `scripts/mb-migrate-v2.sh`, after the rename loop but before the final `echo "[ok] rename phase complete"`, insert:

```bash
# === Content transform: roadmap.md ===
if [ -f "$MB_PATH/roadmap.md" ]; then
  python3 - "$MB_PATH/roadmap.md" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Extract legacy active-plan block (if any)
m = re.search(r"<!-- mb-active-plan -->.*?<!-- /mb-active-plan -->", text, re.DOTALL)
active_plan_block = m.group(0) if m else ""

# Strip old top heading and active-plan block from source
body = re.sub(r"^\s*#\s+Plan\s*\n+", "", text, count=1)
body = re.sub(r"<!-- mb-active-plan -->.*?<!-- /mb-active-plan -->\n*", "", body, flags=re.DOTALL)

# Build new roadmap
now_section = "## Now (in progress)\n\n"
if active_plan_block:
    now_section += active_plan_block + "\n"
else:
    now_section += "_No active plan. Run /mb plan <type> <topic> to start._\n"

new_roadmap = f"""# Roadmap

_Last updated: auto-synced by mb-roadmap-sync.sh_

{now_section}
## Next (strict order — depends)

_Queued plans appear here. See plans/*.md frontmatter: depends_on._

## Parallel-safe (can run now)

_Independent plans. See plans/*.md frontmatter: parallel_safe: true._

## Paused / Archived

_Plans in paused/cancelled state._

## Linked Specs (active)

_Active specs/<topic>/ directories._

## See also
- traceability.md — REQ coverage matrix
- backlog.md — future ideas & ADR
- checklist.md — current in-flight tasks

---

### Legacy content (from v1 plan.md — review and integrate above)

{body.strip()}
"""

path.write_text(new_roadmap, encoding="utf-8")
print(f"[transformed] {path}")
PY
fi
```

- [ ] **Step 4: Run all migration tests — must pass**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py -v
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/mb-migrate-v2.sh tests/pytest/test_migrate_v2.py
git commit -m "feat(migrate-v2): transform plan.md → roadmap.md with new sections"
```

---

## Task 6: Implement reference fixup in user .md files

Replace `STATUS.md` → `status.md` etc. inside all `.md` files under `.memory-bank/` (notes, plans, progress, etc).

**Files:**
- Modify: `scripts/mb-migrate-v2.sh`
- Modify: `tests/pytest/test_migrate_v2.py`

- [ ] **Step 1: Write failing test for reference fixup**

Append to `tests/pytest/test_migrate_v2.py`:
```python
def test_references_updated_in_notes(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    note = (v1_copy / "notes" / "2026-04-15_12-00_example.md").read_text(encoding="utf-8")
    assert "STATUS.md" not in note
    assert "status.md" in note


def test_references_updated_in_plans(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    plan = (v1_copy / "plans" / "2026-04-20_feature_example.md").read_text(encoding="utf-8")
    assert "plan.md" not in plan or "roadmap.md" in plan
    assert "BACKLOG.md" not in plan


def test_references_untouched_in_backup(v1_copy: Path) -> None:
    result = run_script(v1_copy, "--apply")
    assert result.returncode == 0, result.stderr
    backups = sorted(v1_copy.glob(".migration-backup-*/"))
    backup = backups[0]
    # Backup copies are pristine — old names preserved
    assert (backup / "STATUS.md").is_file()
    status_content = (backup / "STATUS.md").read_text(encoding="utf-8")
    assert "# Status" in status_content  # original heading intact
```

- [ ] **Step 2: Run — all three fail**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py -v -k "references"
```

Expected: 3 FAIL (no reference fixup in script yet).

- [ ] **Step 3: Add reference-fixup phase**

In `scripts/mb-migrate-v2.sh`, **after** the content transform block but **before** final `echo`, insert:

```bash
# === Reference fixup in .memory-bank/ .md files ===
# Excludes the backup directory itself.
python3 - "$MB_PATH" <<'PY'
import re
import sys
from pathlib import Path

mb = Path(sys.argv[1])
replacements = [
    (re.compile(r"\bSTATUS\.md\b"), "status.md"),
    (re.compile(r"\bBACKLOG\.md\b"), "backlog.md"),
    (re.compile(r"\bRESEARCH\.md\b"), "research.md"),
    # plan.md → roadmap.md ONLY for file references — not for "the plan.md" prose
    # Heuristic: only replace when preceded by a slash or at-word-boundary with .md suffix
    (re.compile(r"(?<![A-Za-z0-9_\-])plan\.md\b"), "roadmap.md"),
]

# Exclude backup dir
skip_prefixes = tuple(str(p) for p in mb.glob(".migration-backup-*"))

for md in mb.rglob("*.md"):
    s = str(md)
    if s.startswith(skip_prefixes):
        continue
    original = md.read_text(encoding="utf-8")
    updated = original
    for pat, repl in replacements:
        updated = pat.sub(repl, updated)
    if updated != original:
        md.write_text(updated, encoding="utf-8")
        print(f"[refs] updated {md.relative_to(mb)}")
PY
```

- [ ] **Step 4: Run reference tests — must pass**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py -v
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/mb-migrate-v2.sh tests/pytest/test_migrate_v2.py
git commit -m "feat(migrate-v2): fixup references inside .md files"
```

---

## Task 7: Idempotency test

Running the migration twice must be safe — second run is a noop.

**Files:**
- Modify: `tests/pytest/test_migrate_v2.py`

- [ ] **Step 1: Write idempotency test**

Append to `tests/pytest/test_migrate_v2.py`:
```python
def test_idempotent_double_apply(v1_copy: Path) -> None:
    first = run_script(v1_copy, "--apply")
    assert first.returncode == 0, first.stderr
    # Capture roadmap content after first run
    roadmap_after_first = (v1_copy / "roadmap.md").read_text(encoding="utf-8")
    # Second run — no v1 files remain, script should exit ok with "no v1 files detected"
    second = run_script(v1_copy, "--apply")
    assert second.returncode == 0, second.stderr
    assert "no v1 files detected" in second.stdout
    # Roadmap not re-transformed (content unchanged)
    roadmap_after_second = (v1_copy / "roadmap.md").read_text(encoding="utf-8")
    assert roadmap_after_first == roadmap_after_second
    # Only one backup dir exists (second run didn't create another)
    backups = sorted(v1_copy.glob(".migration-backup-*/"))
    assert len(backups) == 1
```

- [ ] **Step 2: Run test — must pass**

Run:
```bash
pytest tests/pytest/test_migrate_v2.py::test_idempotent_double_apply -v
```

Expected: PASS (the detection phase in Task 3 already handles "no files → early exit").

If FAIL (because detection created an empty backup even when nothing to migrate), fix script: move `mkdir backup_dir` **after** detection of planned renames. If `planned_renames` is empty, script exits before backup creation — this is already the case per Task 3 detection block (`exit 0` when empty). Verify, then commit.

- [ ] **Step 3: Commit**

```bash
git add tests/pytest/test_migrate_v2.py
git commit -m "test(migrate-v2): verify idempotent double-apply"
```

---

## Task 8: Bulk-update skill's own commands/ and references/ to new names

Scope: all skill code that references old filenames. Not user-facing migration — this is the skill's own internal refactor.

**Files (write):**
- `commands/mb.md` — main dispatcher
- `commands/start.md`, `commands/done.md`, `commands/plan.md`, `commands/catchup.md`, `commands/adr.md`, `commands/changelog.md`
- `references/structure.md`, `references/templates.md`, `references/planning-and-verification.md`, `references/command-template.md`, `references/workflow.md`, `references/metadata.md`, `references/claude-md-template.md`
- `agents/mb-doctor.md`, `agents/mb-manager.md`, `agents/plan-verifier.md`

- [ ] **Step 1: Write test that asserts no old names remain in skill code**

Create `tests/pytest/test_skill_naming_v2.py`:
```python
"""Guard: skill source code must use v2 lowercase filenames.

Exclusions:
- scripts/mb-migrate-v2.sh (migration logic references both)
- scripts/mb-migrate-structure.sh (historical v3.0 → v3.1 migrator)
- CHANGELOG.md (release history)
- docs/MIGRATION-*.md (migration documentation)
- tests/pytest/fixtures/** (test fixtures intentionally v1)
- tests/pytest/test_migrate_v2.py (tests migration logic)
- .memory-bank/** (may contain user data during dogfood migration)
- .pre-migrate*/** (pre-migration backups)
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

EXCLUDED_PATHS = (
    "scripts/mb-migrate-v2.sh",
    "scripts/mb-migrate-structure.sh",
    "CHANGELOG.md",
    "docs/MIGRATION-v3-v3.1.md",
    "docs/MIGRATION-v1-v2.md",
    "tests/pytest/fixtures/",
    "tests/pytest/test_migrate_v2.py",
    "tests/pytest/test_skill_naming_v2.py",
    ".memory-bank/",
    ".pre-migrate",
    "SECURITY_AUDIT_REPORT.md",
    "dist/",
    "site/",
    ".git/",
    ".pytest_cache/",
    ".ruff_cache/",
)

OLD_NAMES = re.compile(r"\b(STATUS|BACKLOG|RESEARCH)\.md\b")
# plan.md: only flag when it's clearly a file reference (path-like or in backticks)
OLD_PLAN = re.compile(r"(?<![A-Za-z0-9_\-])plan\.md\b")


def _is_excluded(path: Path) -> bool:
    rel = path.relative_to(REPO_ROOT).as_posix()
    return any(rel.startswith(p) for p in EXCLUDED_PATHS)


@pytest.mark.parametrize(
    "suffix",
    ["*.md", "*.sh", "*.py"],
)
def test_no_v1_uppercase_names(suffix: str) -> None:
    offenders: list[str] = []
    for f in REPO_ROOT.rglob(suffix):
        if _is_excluded(f):
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, PermissionError):
            continue
        if OLD_NAMES.search(text):
            offenders.append(f.relative_to(REPO_ROOT).as_posix())
    assert not offenders, (
        f"Files still reference STATUS.md/BACKLOG.md/RESEARCH.md:\n  "
        + "\n  ".join(offenders)
    )


@pytest.mark.parametrize(
    "suffix",
    ["*.md", "*.sh", "*.py"],
)
def test_no_v1_plan_md(suffix: str) -> None:
    offenders: list[str] = []
    for f in REPO_ROOT.rglob(suffix):
        if _is_excluded(f):
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, PermissionError):
            continue
        if OLD_PLAN.search(text):
            offenders.append(f.relative_to(REPO_ROOT).as_posix())
    assert not offenders, (
        f"Files still reference plan.md (expected roadmap.md):\n  "
        + "\n  ".join(offenders)
    )
```

- [ ] **Step 2: Run test — must fail with a long list of offenders**

Run:
```bash
pytest tests/pytest/test_skill_naming_v2.py -v
```

Expected: FAIL — output lists ~30+ files.

- [ ] **Step 3: Bulk replace in commands/, references/, agents/**

Run these commands from repo root (macOS `sed` requires `-i ''`):

```bash
# macOS vs Linux sed compatibility
SED_INPLACE=(-i "")
if sed --version >/dev/null 2>&1; then SED_INPLACE=(-i); fi

find commands references agents -type f -name "*.md" -print0 | xargs -0 sed "${SED_INPLACE[@]}" \
  -e 's/\bSTATUS\.md\b/status.md/g' \
  -e 's/\bBACKLOG\.md\b/backlog.md/g' \
  -e 's/\bRESEARCH\.md\b/research.md/g'

# plan.md — careful: only when it's a file reference, not prose
# Use word boundary + preceding non-identifier char
find commands references agents -type f -name "*.md" -print0 | xargs -0 perl -i -pe 's/(?<![A-Za-z0-9_\-])plan\.md\b/roadmap.md/g'
```

- [ ] **Step 4: Re-run test — should show fewer offenders now (scripts/, adapters/, tests remain)**

Run:
```bash
pytest tests/pytest/test_skill_naming_v2.py -v
```

Expected: still FAIL but offender list smaller — only scripts/, adapters/, tests/pytest/, install.sh, memory_bank_skill/, docs/, root *.md.

- [ ] **Step 5: Manually inspect diff, fix contextual issues**

Run:
```bash
git diff commands/ references/ agents/ | less
```

Look for:
- prose that says "the plan file" incorrectly replaced (e.g., "refactor the roadmap.md logic" where "plan.md" was meant as generic concept)
- headings that should stay `# Plan` (describing the concept, not the file)

Fix any issues with direct edits.

- [ ] **Step 6: Commit**

```bash
git add commands/ references/ agents/ tests/pytest/test_skill_naming_v2.py
git commit -m "refactor(skill): rename v1 → v2 in commands/ references/ agents/"
```

---

## Task 9: Bulk-update skill's own scripts/ and adapters/ and memory_bank_skill/

**Files:**
- All of `scripts/*.sh` and `scripts/*.py` (except `mb-migrate-v2.sh` and `mb-migrate-structure.sh`)
- All of `adapters/*.sh`
- `memory_bank_skill/cli.py`
- `install.sh`

- [ ] **Step 1: Bulk replace in scripts/, adapters/, memory_bank_skill/**

From repo root:
```bash
SED_INPLACE=(-i "")
if sed --version >/dev/null 2>&1; then SED_INPLACE=(-i); fi

# Scripts — exclude the two migrators
for f in $(find scripts -type f \( -name "*.sh" -o -name "*.py" \) \
             ! -name "mb-migrate-v2.sh" \
             ! -name "mb-migrate-structure.sh"); do
  sed "${SED_INPLACE[@]}" \
    -e 's/\bSTATUS\.md\b/status.md/g' \
    -e 's/\bBACKLOG\.md\b/backlog.md/g' \
    -e 's/\bRESEARCH\.md\b/research.md/g' \
    "$f"
  perl -i -pe 's/(?<![A-Za-z0-9_\-])plan\.md\b/roadmap.md/g' "$f"
done

# Adapters
for f in adapters/*.sh; do
  sed "${SED_INPLACE[@]}" \
    -e 's/\bSTATUS\.md\b/status.md/g' \
    -e 's/\bBACKLOG\.md\b/backlog.md/g' \
    -e 's/\bRESEARCH\.md\b/research.md/g' \
    "$f"
  perl -i -pe 's/(?<![A-Za-z0-9_\-])plan\.md\b/roadmap.md/g' "$f"
done

# memory_bank_skill/ and install.sh
for f in memory_bank_skill/*.py install.sh; do
  sed "${SED_INPLACE[@]}" \
    -e 's/\bSTATUS\.md\b/status.md/g' \
    -e 's/\bBACKLOG\.md\b/backlog.md/g' \
    -e 's/\bRESEARCH\.md\b/research.md/g' \
    "$f"
  perl -i -pe 's/(?<![A-Za-z0-9_\-])plan\.md\b/roadmap.md/g' "$f"
done
```

- [ ] **Step 2: Manual inspection**

Run:
```bash
git diff scripts/ adapters/ memory_bank_skill/ install.sh | head -200
```

Look for:
- string literals that are HEREDOC templates written to user `.memory-bank/` — these should use NEW names (good — keeps init-new projects on v2)
- variable names like `STATUS_MD=...` → rename to `STATUS_FILE=`, but actual value should now be `status.md`
- error messages mentioning old names → update

Fix by direct edits.

- [ ] **Step 3: Re-run naming guard test**

Run:
```bash
pytest tests/pytest/test_skill_naming_v2.py -v
```

Expected: should PASS now (or have only tests/ and docs/ remaining — handled in Task 10+11).

- [ ] **Step 4: Run full test suite — existing tests should still pass**

Run:
```bash
pytest tests/pytest/ -v
```

Expected: all existing tests pass. If any fail due to old-name expectations, note them for Task 10.

- [ ] **Step 5: Commit**

```bash
git add scripts/ adapters/ memory_bank_skill/ install.sh
git commit -m "refactor(skill): rename v1 → v2 in scripts/ adapters/ memory_bank_skill/"
```

---

## Task 10: Update existing pytest tests to expect v2 names

**Files:**
- `tests/pytest/test_templates_format.py`
- `tests/pytest/test_locales_structure.py`
- `tests/pytest/test_import.py`
- Potentially other tests that assert file structures

- [ ] **Step 1: Identify tests using old names**

Run:
```bash
grep -l "STATUS\.md\|BACKLOG\.md\|RESEARCH\.md" tests/pytest/*.py
grep -l "\bplan\.md\b" tests/pytest/*.py | grep -v test_migrate_v2 | grep -v fixtures
```

- [ ] **Step 2: Update each test file**

For each file from Step 1 (except `test_migrate_v2.py` and fixture files):
- Replace assertions/strings: `STATUS.md → status.md`, `BACKLOG.md → backlog.md`, `RESEARCH.md → research.md`, `plan.md → roadmap.md`
- For parametrized lists of expected files, update entries
- Keep tests semantically equivalent — just the names change

Use same sed/perl as Tasks 8-9:
```bash
SED_INPLACE=(-i "")
if sed --version >/dev/null 2>&1; then SED_INPLACE=(-i); fi

for f in tests/pytest/test_templates_format.py tests/pytest/test_locales_structure.py tests/pytest/test_import.py; do
  sed "${SED_INPLACE[@]}" \
    -e 's/\bSTATUS\.md\b/status.md/g' \
    -e 's/\bBACKLOG\.md\b/backlog.md/g' \
    -e 's/\bRESEARCH\.md\b/research.md/g' \
    "$f"
  perl -i -pe 's/(?<![A-Za-z0-9_\-])plan\.md\b/roadmap.md/g' "$f"
done
```

- [ ] **Step 3: Run full test suite**

Run:
```bash
pytest tests/pytest/ -v
```

Expected: all PASS (both existing tests + migration tests + naming guard).

If any test fails, read the assertion carefully — it may reference old names in a context that wasn't caught by regex (e.g., inside a heredoc-assembled expected-content string). Fix manually.

- [ ] **Step 4: Commit**

```bash
git add tests/pytest/
git commit -m "test(skill): update existing tests to expect v2 lowercase names"
```

---

## Task 11: Autodetect in `/mb start` and `/mb doctor` — prompt migration

User running the skill on a v1 `.memory-bank/` should see a clear prompt to run migration, not silent failures.

**Files:**
- `commands/start.md`
- `commands/mb.md` (section for `/mb context` and `/mb doctor`)
- `agents/mb-doctor.md`

- [ ] **Step 1: Add autodetect snippet to `commands/start.md`**

In `commands/start.md`, add near the top of the script (after `## Preparation` / before reading core files):

```markdown
## Pre-flight: detect v1 layout

If `.memory-bank/STATUS.md` or `.memory-bank/plan.md` exists (without `.memory-bank/status.md` or `.memory-bank/roadmap.md`), the project is on v1 naming.

Tell the user:

> "Detected v1 Memory Bank layout (uppercase STATUS.md / plan.md). v2 requires lowercase names. Run:
>
> ```
> bash ~/.claude/skills/memory-bank/scripts/mb-migrate-v2.sh --dry-run
> ```
>
> to preview, then `--apply` to execute. Backup is created automatically."

Do not proceed with context loading — ask the user to run migration first. If the user explicitly says "read v1 anyway", fall back to reading old names (backward compat).
```

- [ ] **Step 2: Add migration check to `agents/mb-doctor.md`**

In `agents/mb-doctor.md`, append a new check near existing consistency checks:

```markdown
### Check: v2 naming migration

- Detect presence of `STATUS.md`, `BACKLOG.md`, `RESEARCH.md`, `plan.md` in `.memory-bank/`
- If any exist AND the corresponding v2-name (`status.md` etc.) does NOT exist:
  - Report: `WARN: v1 layout detected — X files need rename`
  - List the files
  - Suggest: `Run: bash scripts/mb-migrate-v2.sh --apply`
- If both exist (partial migration / user-created duplicate):
  - Report: `ERROR: both v1 and v2 files present for X — resolve manually`
```

- [ ] **Step 3: Add equivalent snippet to `commands/mb.md` `/mb context` subcommand and `/mb doctor` subcommand**

Find the section handling `context` (or `(empty)`) in `commands/mb.md` and add: before collecting context, run the same v1-detect snippet from Step 1 as a soft warning (not a hard stop — context can still be assembled from old names for 2 versions).

Find the section handling `doctor` and hand off to the extended `mb-doctor.md` check.

- [ ] **Step 4: Manual smoke-test against v1 fixture**

Run:
```bash
# Temp copy fixture somewhere invokable
cp -r tests/pytest/fixtures/mb_v1_layout /tmp/mb_v1_smoke
cd /tmp/mb_v1_smoke && mkdir -p .memory-bank && mv * .memory-bank/ 2>/dev/null || true
# Now invoke /mb doctor equivalent — via the script
# (Doctor is agent-driven; verify by reading the agent output signal)
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-v2.sh --dry-run /tmp/mb_v1_smoke/.memory-bank
```

Expected: clear "v1 layout detected" output with planned renames.

- [ ] **Step 5: Commit**

```bash
git add commands/start.md commands/mb.md agents/mb-doctor.md
git commit -m "feat(start/doctor): autodetect v1 layout and prompt migration"
```

---

## Task 12: Update skill's own top-level docs

**Files:**
- `SKILL.md`
- `README.md`
- `CLAUDE.md` (skill's own, not user's)
- `CHANGELOG.md` — append v2 entry
- `docs/i18n.md`, `docs/cross-agent-setup.md`, `docs/repo-migration.md`
- Create: `docs/MIGRATION-v1-v2.md`

- [ ] **Step 1: Bulk replace in docs/ and top-level .md (except CHANGELOG.md and existing MIGRATION-v3-v3.1.md)**

From repo root:
```bash
SED_INPLACE=(-i "")
if sed --version >/dev/null 2>&1; then SED_INPLACE=(-i); fi

for f in SKILL.md README.md CLAUDE.md docs/i18n.md docs/cross-agent-setup.md docs/repo-migration.md; do
  [ -f "$f" ] || continue
  sed "${SED_INPLACE[@]}" \
    -e 's/\bSTATUS\.md\b/status.md/g' \
    -e 's/\bBACKLOG\.md\b/backlog.md/g' \
    -e 's/\bRESEARCH\.md\b/research.md/g' \
    "$f"
  perl -i -pe 's/(?<![A-Za-z0-9_\-])plan\.md\b/roadmap.md/g' "$f"
done
```

- [ ] **Step 2: Create `docs/MIGRATION-v1-v2.md`**

Write `docs/MIGRATION-v1-v2.md`:
```markdown
# Migration v1 → v2: lowercase filenames

_Since: skill version 2.0.0._

## What changed

Four files renamed:

| v1 (old) | v2 (new) |
|----------|----------|
| `STATUS.md` | `status.md` |
| `BACKLOG.md` | `backlog.md` |
| `RESEARCH.md` | `research.md` |
| `plan.md` | `roadmap.md` (+ new format) |

## Why

- consistent lowercase filename convention
- `plan.md` expanded to true roadmap with ordering, dependencies, and status per plan (see [spec](../.memory-bank/specs/mb-skill-v2/design.md))

## How to migrate

From project root:

```bash
# Preview what will change (no writes)
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-v2.sh --dry-run

# Apply (creates backup in .memory-bank/.migration-backup-<timestamp>/)
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-v2.sh --apply
```

## What the script does

1. Creates timestamped backup in `.memory-bank/.migration-backup-<ts>/`
2. Renames 4 files
3. Transforms `roadmap.md` content — legacy `<!-- mb-active-plan -->` block is placed in new `## Now (in progress)` section; remaining content is preserved in `## See also` section
4. Updates cross-references (`STATUS.md` → `status.md`, etc.) in all `.md` files inside `.memory-bank/`
5. Is idempotent — running twice is safe (second run is a no-op)

## Backward compatibility window

- For 2 skill versions, core scripts (`mb-context.sh`, `mb-search.sh`, etc.) fall back to reading old names if new ones are not present
- `/mb doctor` will WARN if v1 files still exist
- After 2 versions, `/mb doctor` will ERROR without migration

## Rollback

Each `--apply` run creates `.migration-backup-<timestamp>/`. To rollback:

```bash
cp -r .memory-bank/.migration-backup-<ts>/* .memory-bank/
rm .memory-bank/status.md .memory-bank/backlog.md .memory-bank/research.md .memory-bank/roadmap.md
```

(Or `git checkout .memory-bank/` if the directory is under version control and was committed before migration.)
```

- [ ] **Step 3: Append to `CHANGELOG.md`**

At the top of `CHANGELOG.md` (above existing entries), add:

```markdown
## [2.0.0-alpha.1] - 2026-04-22

### Breaking

- **Rename core files to lowercase:**
  - `STATUS.md` → `status.md`
  - `BACKLOG.md` → `backlog.md`
  - `RESEARCH.md` → `research.md`
  - `plan.md` → `roadmap.md` (with new roadmap format)
- Migration via `scripts/mb-migrate-v2.sh` — see `docs/MIGRATION-v1-v2.md`
- 2-version backward-compat window; `/mb doctor` warns on unmigrated layouts.

### Added

- `scripts/mb-migrate-v2.sh` — idempotent v1 → v2 migrator (rename + content transform + reference fixup + backup)
- `docs/MIGRATION-v1-v2.md` — user-facing migration guide
- `tests/pytest/test_migrate_v2.py` — migration coverage
- `tests/pytest/test_skill_naming_v2.py` — guard: skill code uses v2 names only

### Changed

- All `commands/`, `references/`, `scripts/` (except migrators), `agents/`, `adapters/`, `memory_bank_skill/`, top-level docs, and existing `tests/` updated to use v2 names.
- `/mb start`, `/mb context`, `/mb doctor` autodetect v1 layout and prompt migration.
```

- [ ] **Step 4: Re-run naming guard**

Run:
```bash
pytest tests/pytest/test_skill_naming_v2.py -v
```

Expected: PASS (all skill code uses v2 names; only allowed exclusions retain old names).

- [ ] **Step 5: Commit**

```bash
git add SKILL.md README.md CLAUDE.md docs/ CHANGELOG.md
git commit -m "docs: update to v2 naming + add MIGRATION-v1-v2.md + CHANGELOG"
```

---

## Task 13: Dogfood — migrate skill's own `.memory-bank/`

The skill's own `.memory-bank/` currently has `STATUS.md`, `BACKLOG.md`, `RESEARCH.md`, `plan.md`. Run the migration script on it.

**Files:**
- `.memory-bank/` of the skill itself

- [ ] **Step 1: Preview**

```bash
bash scripts/mb-migrate-v2.sh --dry-run .memory-bank
```

Expected output: "v1 layout detected" with 4 renames listed.

- [ ] **Step 2: Apply**

```bash
bash scripts/mb-migrate-v2.sh --apply .memory-bank
```

Expected output: backup created, 4 renames performed, `roadmap.md` transformed, references fixed.

- [ ] **Step 3: Verify layout**

```bash
ls .memory-bank/ | grep -E "^(status|backlog|research|roadmap)\.md$"
```

Expected: 4 matching lines.

```bash
ls .memory-bank/ | grep -E "^(STATUS|BACKLOG|RESEARCH|plan)\.md$"
```

Expected: no output (old names gone).

- [ ] **Step 4: Spot-check roadmap.md**

Run:
```bash
head -30 .memory-bank/roadmap.md
```

Expected: new format with `## Now (in progress)`, `## Next`, `## Parallel-safe`, etc.

- [ ] **Step 5: Run full test suite**

Run:
```bash
pytest tests/pytest/ -v
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add .memory-bank/
git commit -m "chore(.memory-bank): dogfood v1 → v2 migration on skill's own bank"
```

Note: the migration backup directory (`.memory-bank/.migration-backup-*/`) will be created. Add it to `.gitignore` or commit it explicitly — decision is: **commit the backup** so history is fully reproducible. Update `.gitignore` only if file sizes make this infeasible (check `du -sh .memory-bank/.migration-backup-*/` — if >1MB, add to .gitignore; otherwise commit).

---

## Task 14: Final regression check + tag release candidate

- [ ] **Step 1: Run complete test suite**

Run:
```bash
pytest tests/pytest/ -v --tb=short
```

Expected: all PASS.

- [ ] **Step 2: Manual smoke-tests on a fresh fixture**

```bash
# Create a fresh v1 project
TMP=$(mktemp -d)
cp -r tests/pytest/fixtures/mb_v1_layout "$TMP/.memory-bank"

# Preview
bash scripts/mb-migrate-v2.sh --dry-run "$TMP/.memory-bank"

# Apply
bash scripts/mb-migrate-v2.sh --apply "$TMP/.memory-bank"

# Re-run — idempotent
bash scripts/mb-migrate-v2.sh --apply "$TMP/.memory-bank"

# Inspect
ls -la "$TMP/.memory-bank/"
cat "$TMP/.memory-bank/roadmap.md"

# Cleanup
rm -rf "$TMP"
```

Expected: second `--apply` says "no v1 files detected", layout is final v2, roadmap.md has new sections, backup dir present.

- [ ] **Step 3: Lint shell scripts**

Run:
```bash
shellcheck scripts/mb-migrate-v2.sh
```

Expected: no warnings. Fix any that appear.

- [ ] **Step 4: Run Python ruff (if configured)**

```bash
ruff check tests/pytest/test_migrate_v2.py tests/pytest/test_skill_naming_v2.py
```

Expected: clean. Fix any issues.

- [ ] **Step 5: Commit any lint fixes**

```bash
git add -A
git diff --cached  # review first
git commit -m "chore(migrate-v2): lint cleanup"
```

- [ ] **Step 6: Summary update — this plan's DoD**

Run:
```bash
bash scripts/mb-plan-sync.sh .memory-bank/plans/2026-04-22_refactor_skill-v2-phase1-sprint1-rename.md
```

(The sync script should find this plan, parse its stages from `- [ ]` markers, and update `.memory-bank/checklist.md`.)

Then update frontmatter `status: queued` → `status: done`, and run:

```bash
bash scripts/mb-plan-done.sh .memory-bank/plans/2026-04-22_refactor_skill-v2-phase1-sprint1-rename.md
```

(This moves the plan to `plans/done/` per existing convention.)

- [ ] **Step 7: Final commit**

```bash
git add .memory-bank/
git commit -m "chore(mb): mark skill-v2-phase1-sprint1-rename plan done"
```

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| `perl -i -pe` on plan.md replaces the word "plan" in prose, breaking readability | Medium | Regex `(?<![A-Za-z0-9_\-])plan\.md\b` requires non-identifier char before "plan" + `.md` suffix → matches file refs only. Manual diff review in Task 8 Step 5 and Task 9 Step 2. |
| Existing test fixtures (NOT `mb_v1_layout`) break due to name changes | Medium | Task 10 scans all test files and updates them explicitly. Full test suite run after each bulk change. |
| User running v1 skill code against v2 `.memory-bank/` (partial install) | Low | 2-version backward-compat window: core scripts (context, search) check both old and new names. |
| `mb-plan-sync.sh` internals rely on `plan.md` name in heredocs | High | Task 9 covers scripts; Task 14 Step 6 verifies by actually running the script. |
| Git case-sensitivity on macOS HFS+ → `STATUS.md` vs `status.md` are "same file" | Medium | `mv` via bash works even on case-insensitive FS (because rename is to different name); `git mv` would fail — we use plain `mv` in the script. Verify on macOS test run in Task 14. |
| Backup dir commits bloat repo (.memory-bank/.migration-backup-*) | Low | Task 13 Step 6: inspect size, decide commit vs .gitignore. |

## Gate (re-stated)

1. `pytest tests/pytest/ -v` — all green (existing + new)
2. `pytest tests/pytest/test_skill_naming_v2.py -v` — naming guard passes
3. `bash scripts/mb-migrate-v2.sh --apply` on fresh v1 fixture → correct v2 layout
4. Re-run → "no v1 files detected" (idempotent)
5. Skill's own `.memory-bank/` migrated and committed
6. `shellcheck scripts/mb-migrate-v2.sh` — clean
7. `/mb doctor` (manual run) reports no issues
