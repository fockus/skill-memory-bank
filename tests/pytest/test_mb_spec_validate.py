"""Sprint 1 Stage 4 — `scripts/mb-spec-validate.sh` contract tests.

Validates the integrity of a Kiro-style spec triple
(``<mb>/specs/<topic>/{requirements,design,tasks}.md``):

1. ``requirements.md`` exists and passes ``mb-ears-validate.sh``.
2. ``tasks.md`` exists and ``mb_work_items.parse_work_items`` returns ≥ 1 item.
3. Every task has a non-empty ``**Covers:**`` field.
4. Every task has ≥ 1 DoD checkbox line.
5. Every task body contains a ``Testing`` section (case-insensitive).
6. Every ``REQ-NNN`` in requirements.md is referenced by ≥ 1 task ``covers``.

Exit codes:
    * 0 — clean (violations empty)
    * 1 — one or more violations (details on stderr)
    * 2 — usage / resolver error

Optional ``--json`` emits ``{"violations": [...]}`` on stdout.

Stage 4 is RED until ``scripts/mb-spec-validate.sh`` exists.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from textwrap import dedent

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-spec-validate.sh"


# ──────────────────────────────────────────────────────────────────────
# Test fixtures
# ──────────────────────────────────────────────────────────────────────


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "specs").mkdir()
    return mb


_VALID_REQ = """\
# Requirements: demo

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall persist work items to disk.
- **REQ-002** (event-driven): When a stage completes, the system shall update the checklist.
"""

_VALID_TASKS = """\
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** developer

**What to do:**
- Implement disk persistence.

**Testing (TDD — tests BEFORE implementation):**
- Unit test for round-trip serialization.

**DoD:**
- [ ] Disk write succeeds.
- [ ] tests pass.

<!-- mb-task:2 -->
## Task 2: refresh checklist on completion

**Covers:** REQ-002
**Role:** developer

**What to do:**
- Wire stage-completion event.

**Testing (TDD — tests BEFORE implementation):**
- Integration test for checklist update.

**DoD:**
- [ ] Checklist line flips to ✅.
- [ ] tests pass.
"""


def _make_spec(mb: Path, topic: str, *, req: str | None = None, tasks: str | None = None) -> Path:
    spec_dir = mb / "specs" / topic
    spec_dir.mkdir(parents=True, exist_ok=True)
    (spec_dir / "requirements.md").write_text(req if req is not None else _VALID_REQ, encoding="utf-8")
    (spec_dir / "tasks.md").write_text(tasks if tasks is not None else _VALID_TASKS, encoding="utf-8")
    (spec_dir / "design.md").write_text("# Design\n", encoding="utf-8")
    return spec_dir


def _run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, **(env or {})} if env else None,
    )


# ──────────────────────────────────────────────────────────────────────
# Tests (Stage 4 RED until mb-spec-validate.sh exists)
# ──────────────────────────────────────────────────────────────────────


def test_spec_validate_passes_on_well_formed_spec(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    spec = _make_spec(mb, "demo")
    r = _run(str(spec))
    assert r.returncode == 0, f"stderr={r.stderr!r}"


def test_spec_validate_fails_when_req_orphan(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    req_with_orphan = _VALID_REQ + (
        "- **REQ-003** (ubiquitous): The system shall expose an orphan requirement.\n"
    )
    _make_spec(mb, "demo", req=req_with_orphan)
    r = _run(str(mb / "specs" / "demo"))
    assert r.returncode == 1, f"expected exit 1, got {r.returncode}; stderr={r.stderr!r}"
    assert "REQ-003" in r.stderr


def test_spec_validate_fails_on_task_without_covers(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    tasks = _VALID_TASKS.replace("**Covers:** REQ-001\n", "")
    _make_spec(mb, "demo", tasks=tasks)
    r = _run(str(mb / "specs" / "demo"))
    assert r.returncode == 1
    assert "Covers" in r.stderr or "covers" in r.stderr


def test_spec_validate_fails_on_task_without_dod(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    tasks_no_dod = """\
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** developer

**What to do:**
- Implement disk persistence.

**Testing (TDD — tests BEFORE implementation):**
- Unit test for round-trip serialization.

<!-- mb-task:2 -->
## Task 2: refresh checklist on completion

**Covers:** REQ-002
**Role:** developer

**What to do:**
- Wire stage-completion event.

**Testing (TDD — tests BEFORE implementation):**
- Integration test for checklist update.
"""
    _make_spec(mb, "demo", tasks=tasks_no_dod)
    r = _run(str(mb / "specs" / "demo"))
    assert r.returncode == 1
    assert "DoD" in r.stderr or "dod" in r.stderr


def test_spec_validate_fails_on_task_without_testing_section(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    tasks = _VALID_TASKS.replace(
        "**Testing (TDD — tests BEFORE implementation):**\n- Unit test for round-trip serialization.\n\n",
        "",
    )
    _make_spec(mb, "demo", tasks=tasks)
    r = _run(str(mb / "specs" / "demo"))
    assert r.returncode == 1
    assert "Testing" in r.stderr or "testing" in r.stderr


def test_spec_validate_fails_on_invalid_ears_in_requirements(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    bad_req = "# Requirements: demo\n\n## Requirements (EARS)\n\n- **REQ-001** this is not a valid EARS sentence.\n"
    _make_spec(mb, "demo", req=bad_req)
    r = _run(str(mb / "specs" / "demo"))
    assert r.returncode == 1
    assert "EARS" in r.stderr or "ears" in r.stderr or "REQ-001" in r.stderr


def test_spec_validate_resolves_topic_via_mb_path(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_spec(mb, "demo")
    # topic form: pass `demo` plus mb path as second positional
    r = _run("demo", str(mb))
    assert r.returncode == 0, f"stderr={r.stderr!r}"


def test_spec_validate_json_mode_emits_structured_output(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    tasks = _VALID_TASKS.replace("**Covers:** REQ-001\n", "")
    _make_spec(mb, "demo", tasks=tasks)
    r = _run("--json", str(mb / "specs" / "demo"))
    assert r.returncode == 1
    assert r.stderr == "", f"JSON mode must not write violations to stderr, got: {r.stderr!r}"
    data = json.loads(r.stdout)
    assert "violations" in data
    assert isinstance(data["violations"], list)
    assert data["violations"], "expected at least one violation entry"


def test_spec_validate_json_mode_passes_on_clean_spec(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_spec(mb, "demo")
    r = _run("--json", str(mb / "specs" / "demo"))
    assert r.returncode == 0, f"stderr={r.stderr!r}"
    data = json.loads(r.stdout)
    assert data == {"violations": []}


def test_spec_validate_usage_error_when_no_args(tmp_path: Path) -> None:
    r = _run()
    assert r.returncode == 2


@pytest.mark.parametrize(
    "missing",
    ["requirements.md", "tasks.md"],
)
def test_spec_validate_fails_when_required_file_missing(tmp_path: Path, missing: str) -> None:
    mb = _init_mb(tmp_path)
    spec = _make_spec(mb, "demo")
    (spec / missing).unlink()
    r = _run(str(spec))
    assert r.returncode == 1
    assert missing in r.stderr


# ──────────────────────────────────────────────────────────────────────
# Prefixed REQ-ID scheme support (REQ-RS-NNN) — shared-grammar fix.
# ──────────────────────────────────────────────────────────────────────

_RS_REQ = dedent("""\
    # Requirements: stream

    ## Requirements (EARS)

    - **REQ-RS-001** (event-driven): When research yields candidates, the system shall return three.
    - **REQ-RS-008** (state-driven): While the browser fetch runs, the system shall cap concurrency to one.
    """)

_RS_TASKS = dedent("""\
    # Tasks: stream

    <!-- mb-task:1 -->
    ## Task 1: recommendation engine

    **Covers:** REQ-RS-001 (prefer 3)
    **Role:** developer

    **What to do:**
    - Build the engine.

    **Testing (TDD — tests BEFORE implementation):**
    - Unit test for the count.

    **DoD:**
    - [ ] Returns three.
    - [ ] tests pass.

    <!-- mb-task:2 -->
    ## Task 2: browser fetch cap

    **Covers:** REQ-RS-008
    **Role:** backend

    **What to do:**
    - Cap concurrency.

    **Testing (TDD — tests BEFORE implementation):**
    - Integration test for the shared semaphore.

    **DoD:**
    - [ ] max_active == 1.
    - [ ] tests pass.
    """)


def test_spec_validate_passes_on_well_formed_prefixed_scheme_spec(tmp_path: Path) -> None:
    """A spec using the ``REQ-RS-NNN`` scheme, fully covered by tasks, is clean.

    Before the shared-grammar fix the digit-only regex matched none of the
    REQ-RS ids, so EARS/orphan checks silently validated nothing (false green).
    """
    mb = _init_mb(tmp_path)
    spec = _make_spec(mb, "stream", req=_RS_REQ, tasks=_RS_TASKS)
    r = _run(str(spec))
    assert r.returncode == 0, f"stderr={r.stderr!r}"


def test_spec_validate_flags_prefixed_scheme_orphan(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    # Task 2 (covering REQ-RS-008) removed → REQ-RS-008 becomes an orphan.
    tasks_only_001 = _RS_TASKS.split("<!-- mb-task:2 -->")[0]
    _make_spec(mb, "stream", req=_RS_REQ, tasks=tasks_only_001)
    r = _run(str(mb / "specs" / "stream"))
    assert r.returncode == 1, f"stderr={r.stderr!r}"
    assert "REQ-RS-008" in r.stderr, r.stderr


def test_spec_validate_invalid_ears_detected_on_prefixed_scheme(tmp_path: Path) -> None:
    """An EARS-malformed ``REQ-RS-NNN`` bullet is now actually validated."""
    mb = _init_mb(tmp_path)
    bad_req = (
        "# Requirements: stream\n\n## Requirements (EARS)\n\n"
        "- **REQ-RS-001** this bullet has no trigger and no shall verb.\n"
    )
    _make_spec(mb, "stream", req=bad_req, tasks=_RS_TASKS)
    r = _run(str(mb / "specs" / "stream"))
    assert r.returncode == 1
    assert "REQ-RS-001" in r.stderr or "EARS" in r.stderr


# ──────────────────────────────────────────────────────────────────────
# --require-tests — REQ→test hard-gate.
# ──────────────────────────────────────────────────────────────────────


def _write_tests(repo_root: Path, body: str, name: str = "test_cov.py") -> None:
    troot = repo_root / "tests"
    troot.mkdir(parents=True, exist_ok=True)
    (troot / name).write_text(body, encoding="utf-8")


def test_require_tests_flags_req_without_covering_test(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)  # mb at tmp_path/.memory-bank → repo root = tmp_path
    _make_spec(mb, "demo")  # REQ-001, REQ-002
    _write_tests(tmp_path, "def test_REQ_001_only():\n    pass\n")
    r = _run("--require-tests", str(mb / "specs" / "demo"))
    assert r.returncode == 1, f"stderr={r.stderr!r}"
    assert "REQ-002 has no covering test" in r.stderr, r.stderr
    assert "REQ-001 has no covering test" not in r.stderr


def test_require_tests_passes_when_every_req_has_a_test(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_spec(mb, "demo")
    _write_tests(tmp_path, "def test_REQ_001(): pass\n\ndef test_REQ_002(): pass\n")
    r = _run("--require-tests", str(mb / "specs" / "demo"))
    assert r.returncode == 0, f"stderr={r.stderr!r}"


def test_require_tests_off_by_default(tmp_path: Path) -> None:
    """Without the flag a missing test is NOT a violation (backward compat)."""
    mb = _init_mb(tmp_path)
    _make_spec(mb, "demo")  # no tests dir at all
    r = _run(str(mb / "specs" / "demo"))
    assert r.returncode == 0, f"stderr={r.stderr!r}"


def test_require_tests_honours_mb_test_roots_for_subpackage_layout(tmp_path: Path) -> None:
    """A monorepo whose tests live in ``pkg/tests`` points MB_TEST_ROOTS at them."""
    mb = _init_mb(tmp_path)
    _make_spec(mb, "demo")
    pkg_tests = tmp_path / "pkg" / "tests"
    pkg_tests.mkdir(parents=True)
    (pkg_tests / "test_x.py").write_text(
        "def test_REQ_001(): pass\n\ndef test_REQ_002(): pass\n", encoding="utf-8"
    )
    # Default roots (tmp/tests, mb/tests) don't exist → without the env it fails.
    r_default = _run("--require-tests", str(mb / "specs" / "demo"))
    assert r_default.returncode == 1
    # With MB_TEST_ROOTS pointing at the sub-package, both REQs are covered.
    r_env = _run(
        "--require-tests", str(mb / "specs" / "demo"), env={"MB_TEST_ROOTS": "pkg/tests"}
    )
    assert r_env.returncode == 0, f"stderr={r_env.stderr!r}"
