"""Contract tests for the GIVEN/WHEN/THEN scenario layer.

Covers two scripts:
  * ``scripts/mb-scenario-extract.py`` — parse ``<!-- mb-scenario:N -->`` blocks
    into a normalized test-plan (JSON Lines) and ``--validate`` their structure.
  * ``scripts/mb-spec-validate.sh`` scenario integration — present scenarios are
    structure-checked always (no-op when absent); ``--require-scenarios`` (opt-in)
    additionally enforces ≥1 scenario per REQ.

Design contract: the scenario layer is ADDITIVE and OPT-IN. Specs without any
``<!-- mb-scenario:N -->`` blocks behave exactly as before (backward compatible).
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EXTRACT = REPO_ROOT / "scripts" / "mb-scenario-extract.py"
VALIDATE = REPO_ROOT / "scripts" / "mb-spec-validate.sh"


# ──────────────────────────────────────────────────────────────────────
# Fixtures
# ──────────────────────────────────────────────────────────────────────

_SCENARIO_OK = """\
<!-- mb-scenario:1 -->
### Scenario: Account lockout after repeated failures
**Covers:** REQ-006

- GIVEN an account at the failed-attempt threshold within the window
- WHEN another authentication attempt is made
- THEN authentication is locked for the cooldown
- AND an audit event is recorded
<!-- /mb-scenario:1 -->
"""

_SCENARIO_MISSING_THEN = """\
<!-- mb-scenario:1 -->
### Scenario: Missing then clause
**Covers:** REQ-006

- GIVEN a user
- WHEN they log in
<!-- /mb-scenario:1 -->
"""

_REQ_HEADER = "# Requirements: demo\n\n## Requirements (EARS)\n\n"
_REQ_006 = "- **REQ-006** If attempts exceed the threshold, then the system shall lock the account.\n"
_REQ_007 = "- **REQ-007** If authentication fails, then the system shall return a generic error.\n"

_VALID_TASKS = """\
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: implement
**Covers:** {covers}
**Role:** backend

**What to do:**
- thing

**Testing (TDD — tests BEFORE implementation):**
- a test

**DoD:**
- [ ] done
<!-- /mb-task:1 -->
"""


def _write(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    return path


def _run_extract(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(EXTRACT), *args], capture_output=True, text=True, check=False
    )


def _run_validate(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(VALIDATE), *args], capture_output=True, text=True, check=False
    )


def _make_spec(tmp_path: Path, *, req: str, tasks: str) -> Path:
    spec = tmp_path / ".memory-bank" / "specs" / "demo"
    spec.mkdir(parents=True)
    _write(spec / "requirements.md", req)
    _write(spec / "tasks.md", tasks)
    _write(spec / "design.md", "# Design\n")
    return spec


# ──────────────────────────────────────────────────────────────────────
# mb-scenario-extract.py — parsing
# ──────────────────────────────────────────────────────────────────────


def test_extract_parses_scenario_into_test_plan(tmp_path: Path) -> None:
    f = _write(tmp_path / "r.md", _REQ_HEADER + _REQ_006 + "\n## Scenarios\n\n" + _SCENARIO_OK)
    r = _run_extract(str(f))
    assert r.returncode == 0, r.stderr
    rows = [json.loads(line) for line in r.stdout.splitlines() if line.strip()]
    assert len(rows) == 1
    s = rows[0]
    assert s["covers"] == ["REQ-006"]
    assert s["given"] and s["when"] and s["then"]
    assert s["extra"] == ["an audit event is recorded"]
    assert s["test_id"].startswith("REQ-006__")


def test_extract_no_scenarios_is_empty_and_clean(tmp_path: Path) -> None:
    f = _write(tmp_path / "r.md", _REQ_HEADER + _REQ_006)
    r = _run_extract(str(f))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_extract_validate_clean_on_wellformed(tmp_path: Path) -> None:
    f = _write(tmp_path / "r.md", _REQ_HEADER + _REQ_006 + _SCENARIO_OK)
    r = _run_extract("--validate", str(f))
    assert r.returncode == 0, r.stderr


def test_extract_validate_flags_missing_then(tmp_path: Path) -> None:
    f = _write(tmp_path / "r.md", _REQ_HEADER + _REQ_006 + _SCENARIO_MISSING_THEN)
    r = _run_extract("--validate", str(f))
    assert r.returncode == 1
    assert "THEN" in r.stderr


def test_extract_validate_clean_when_no_scenarios(tmp_path: Path) -> None:
    f = _write(tmp_path / "r.md", _REQ_HEADER + _REQ_006)
    r = _run_extract("--validate", str(f))
    assert r.returncode == 0


def test_extract_missing_file_is_usage_error(tmp_path: Path) -> None:
    r = _run_extract(str(tmp_path / "nope.md"))
    assert r.returncode == 2


# ──────────────────────────────────────────────────────────────────────
# mb-spec-validate.sh — scenario integration
# ──────────────────────────────────────────────────────────────────────


def test_validate_passes_with_wellformed_scenario(tmp_path: Path) -> None:
    spec = _make_spec(
        tmp_path,
        req=_REQ_HEADER + _REQ_006 + "\n## Scenarios\n\n" + _SCENARIO_OK,
        tasks=_VALID_TASKS.format(covers="REQ-006"),
    )
    r = _run_validate(str(spec))
    assert r.returncode == 0, r.stderr


def test_validate_fails_on_malformed_scenario_without_flag(tmp_path: Path) -> None:
    # Structure of present scenarios is checked even without --require-scenarios.
    spec = _make_spec(
        tmp_path,
        req=_REQ_HEADER + _REQ_006 + "\n## Scenarios\n\n" + _SCENARIO_MISSING_THEN,
        tasks=_VALID_TASKS.format(covers="REQ-006"),
    )
    r = _run_validate(str(spec))
    assert r.returncode == 1
    assert "THEN" in r.stderr


def test_validate_backward_compatible_without_scenarios(tmp_path: Path) -> None:
    # A spec with NO scenarios stays green without the opt-in flag.
    spec = _make_spec(
        tmp_path,
        req=_REQ_HEADER + _REQ_006,
        tasks=_VALID_TASKS.format(covers="REQ-006"),
    )
    r = _run_validate(str(spec))
    assert r.returncode == 0, r.stderr


def test_validate_require_scenarios_flags_uncovered_req(tmp_path: Path) -> None:
    spec = _make_spec(
        tmp_path,
        req=_REQ_HEADER + _REQ_006 + _REQ_007 + "\n## Scenarios\n\n" + _SCENARIO_OK,
        tasks=_VALID_TASKS.format(covers="REQ-006, REQ-007"),
    )
    # Without the flag: REQ-007 lacking a scenario is fine.
    assert _run_validate(str(spec)).returncode == 0
    # With the flag: REQ-007 has no scenario → violation.
    r = _run_validate("--require-scenarios", str(spec))
    assert r.returncode == 1
    assert "REQ-007" in r.stderr


def test_validate_require_scenarios_passes_when_all_covered(tmp_path: Path) -> None:
    spec = _make_spec(
        tmp_path,
        req=_REQ_HEADER + _REQ_006 + "\n## Scenarios\n\n" + _SCENARIO_OK,
        tasks=_VALID_TASKS.format(covers="REQ-006"),
    )
    r = _run_validate("--require-scenarios", str(spec))
    assert r.returncode == 0, r.stderr
