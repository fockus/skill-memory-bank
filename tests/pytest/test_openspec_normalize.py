"""Tests for `scripts/mb_openspec_normalize.py` + the `--normalize` wiring (T6).

Contract (design.md D-03/D-04 — Covers REQ-007, REQ-008, REQ-010):

    convert(ch, normalize=True, mb_path=..., llm=<mock>) fills the requirement
    text/scenario/Covers slots via an injected `llm` callable, caches each
    result by source-requirement hash under
    `<mb_path>/.index/openspec/normalize-cache.json` (an unchanged source
    requirement never re-invokes `llm`), and falls back to the exact
    deterministic values (+ a stderr warning, the import still succeeds) when
    `llm` raises/is unavailable.

Unit-level tests inject a mocked `llm` directly into `convert()` — no real
network/subagent dispatch. Two CLI-level tests additionally drive the real
`mb-openspec.py import --normalize` end-to-end through the actual
`default_llm_dispatch` seam, but still without any real network/subagent
call: `MB_SUBINVOKE_CMD` is overridden to a trivial local shell command
(`printf ...` / `false`), the same override mechanism
`mb-subinvoke-resolve.sh` already documents for operators/tests.
"""

from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"
SCRIPT = REPO_ROOT / "scripts" / "mb-openspec.py"
FIXTURE = (
    REPO_ROOT / "tests" / "pytest" / "fixtures" / "openspec" / "changes" / "add-metadata-tracking"
)

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import mb_openspec_convert as convert_mod  # noqa: E402
import mb_openspec_parse as parse_mod  # noqa: E402
from mb_openspec_normalize import requirement_source_hash  # noqa: E402


def _change():
    return parse_mod.parse_change(FIXTURE)


def _normalizable_requirements(ch):
    """Requirements `convert()` actually calls `normalize_requirement` for:
    every ADDED/MODIFIED requirement. REMOVED becomes a design.md note only
    (never normalized) and RENAMED is deferred entirely on a fresh import
    (no prior anchor to resolve against) — see
    `mb_openspec_convert._build_requirements`."""
    return [r for r in ch.requirements if r.change_kind in ("added", "modified")]


def _make_llm():
    """A deterministic fake `llm` callable + the list of payloads it was called with."""
    calls: list[dict] = []

    def llm(payload):
        calls.append(copy.deepcopy(payload))
        slots = {
            "text": f"WHEN {payload['name']} is invoked, the system SHALL "
            f"{payload['text'].strip()}",
            "scenario": None,
            "covers": [],
        }
        if payload["needs_scenario"]:
            slots["scenario"] = {
                "name": f"{payload['name']} generated scenario",
                "steps": [["WHEN", "triggered"], ["THEN", "succeeds"]],
            }
        return slots

    return llm, calls


def _cache_path(bank: Path) -> Path:
    return bank / ".index" / "openspec" / "normalize-cache.json"


# ---------------------------------------------------------------------------
# Unit-level: convert(normalize=True, llm=<mock>) — cache populate/reuse
# ---------------------------------------------------------------------------


def test_normalize_first_run_populates_cache_and_calls_llm_per_requirement(tmp_path):
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    ch = _change()
    llm, calls = _make_llm()

    requirements_md, _design_md, _tasks_md = convert_mod.convert(
        ch, normalize=True, mb_path=bank, llm=llm
    )

    expected = _normalizable_requirements(ch)
    assert len(calls) == len(expected)

    cache_file = _cache_path(bank)
    assert cache_file.is_file()
    cache_data = json.loads(cache_file.read_text(encoding="utf-8"))
    assert len(cache_data) == len(expected)
    for req in expected:
        assert requirement_source_hash(req) in cache_data

    assert "the system SHALL" in requirements_md
    assert "generated scenario" in requirements_md  # the one requirement with no source scenario


def test_normalize_second_run_reuses_cache_no_second_llm_call(tmp_path):
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    ch = _change()
    llm, calls = _make_llm()

    first_md, _d, _t = convert_mod.convert(ch, normalize=True, mb_path=bank, llm=llm)
    first_call_count = len(calls)
    assert first_call_count == len(_normalizable_requirements(ch))

    second_md, _d2, _t2 = convert_mod.convert(ch, normalize=True, mb_path=bank, llm=llm)

    assert len(calls) == first_call_count  # no new llm invocations at all
    assert second_md == first_md


def test_normalize_changed_requirement_regenerates_only_that_slot(tmp_path):
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    ch = _change()
    llm, calls = _make_llm()

    convert_mod.convert(ch, normalize=True, mb_path=bank, llm=llm)
    first_call_count = len(calls)
    assert first_call_count > 0

    # Simulate an upstream edit to exactly one requirement's source text.
    target = next(r for r in ch.requirements if r.change_kind == "modified")
    target.text = target.text + " Updated wording."

    convert_mod.convert(ch, normalize=True, mb_path=bank, llm=llm)

    assert len(calls) == first_call_count + 1  # exactly one new call
    assert calls[-1]["name"] == target.name  # for the changed requirement only

    cache_data = json.loads(_cache_path(bank).read_text(encoding="utf-8"))
    assert len(cache_data) == first_call_count + 1  # unchanged reqs' entries preserved, one added


def test_normalize_llm_unavailable_falls_back_deterministically(tmp_path, capsys):
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    ch = _change()

    def failing_llm(payload):
        raise RuntimeError("simulated llm outage")

    baseline_md, _bd, _bt = convert_mod.convert(ch)
    normalized_md, _nd, _nt = convert_mod.convert(ch, normalize=True, mb_path=bank, llm=failing_llm)

    assert normalized_md == baseline_md  # exact deterministic fallback, not a degraded rewrite
    captured = capsys.readouterr()
    assert "llm unavailable" in captured.err

    # A transient failure is never cached — it must stay retry-able (REQ-010's
    # fail-open spirit: don't permanently downgrade a requirement because the
    # LLM happened to be down on one run).
    assert not _cache_path(bank).exists()


def test_normalize_false_never_touches_cache_or_llm(tmp_path):
    """NFR-001 guard: `normalize=False` (the default) is byte-identical to the
    pre-T6 path even when `mb_path`/`llm` are supplied — the golden-fixture
    byte-identity test in test_openspec_convert.py is the primary NFR-001
    guard; this asserts the seam itself is a true no-op when unused."""
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    ch = _change()

    def forbidden_llm(_payload):
        raise AssertionError("llm must never be invoked when normalize=False")

    baseline = convert_mod.convert(ch)
    guarded = convert_mod.convert(ch, normalize=False, mb_path=bank, llm=forbidden_llm)

    assert guarded == baseline
    assert not _cache_path(bank).exists()


# ---------------------------------------------------------------------------
# CLI-level: `mb-openspec.py import --normalize` end-to-end through the real
# default_llm_dispatch seam (MB_SUBINVOKE_CMD override -- no real network).
# ---------------------------------------------------------------------------


def _write_demo_change(change_dir: Path) -> None:
    (change_dir / "specs" / "demo").mkdir(parents=True, exist_ok=True)
    (change_dir / "proposal.md").write_text(
        "## Why\n\nDemo change for --normalize CLI tests.\n\n## What Changes\n\n- Demo.\n",
        encoding="utf-8",
    )
    (change_dir / "specs" / "demo" / "spec.md").write_text(
        "## ADDED Requirements\n\n"
        "### Requirement: Demo Thing\n"
        "The system SHALL do the demo thing.\n",
        encoding="utf-8",
    )
    (change_dir / "tasks.md").write_text("## 1. Setup\n- [ ] do it\n", encoding="utf-8")


def test_cli_import_normalize_wires_default_dispatcher_end_to_end(tmp_path):
    bank = tmp_path / ".memory-bank"
    (bank / "specs").mkdir(parents=True)
    change_dir = tmp_path / "openspec" / "changes" / "demo"
    _write_demo_change(change_dir)

    fake_llm_cmd = (
        "printf 'TEXT: WHEN demo runs, the system SHALL do the demo thing.\\n"
        "SCENARIO: Demo scenario | WHEN triggered | THEN succeeds\\n"
        "COVERS: NONE\\n'"
    )
    env = dict(os.environ)
    env["MB_SUBINVOKE_CMD"] = fake_llm_cmd

    proc = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "import",
            str(change_dir),
            "--as",
            "demo",
            "--mb",
            str(bank),
            "--normalize",
        ],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )

    assert proc.returncode == 0, proc.stderr
    req_md = (bank / "specs" / "demo" / "requirements.md").read_text(encoding="utf-8")
    assert "WHEN demo runs, the system SHALL do the demo thing." in req_md
    assert "Demo scenario" in req_md
    assert _cache_path(bank).is_file()


def test_cli_import_normalize_llm_unavailable_still_exits_zero(tmp_path):
    bank = tmp_path / ".memory-bank"
    (bank / "specs").mkdir(parents=True)
    change_dir = tmp_path / "openspec" / "changes" / "demo2"
    _write_demo_change(change_dir)

    env = dict(os.environ)
    env["MB_SUBINVOKE_CMD"] = "false"  # always fails -- simulates an unavailable LLM

    proc = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "import",
            str(change_dir),
            "--as",
            "demo2",
            "--mb",
            str(bank),
            "--normalize",
        ],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )

    assert proc.returncode == 0, proc.stderr
    assert "llm unavailable" in proc.stderr
    req_md = (bank / "specs" / "demo2" / "requirements.md").read_text(encoding="utf-8")
    assert "do the demo thing" in req_md  # deterministic fallback text still present
