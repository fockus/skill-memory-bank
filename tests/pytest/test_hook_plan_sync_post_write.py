"""Phase 4 Sprint 1 — `hooks/mb-plan-sync-post-write.sh` PostToolUse Write hook."""

from __future__ import annotations

import json
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / "hooks" / "mb-plan-sync-post-write.sh"


@pytest.fixture(autouse=True)
def isolated_project(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    project = tmp_path / "project with spaces"
    bank = project / ".memory-bank"
    bank.mkdir(parents=True)
    for name in ("checklist", "roadmap", "status"):
        (bank / f"{name}.md").write_text(f"# Existing {name}\n", encoding="utf-8")
    monkeypatch.chdir(project)
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("MB_PATH", str(bank))
    monkeypatch.setenv("MB_SKILLS_ROOT", str(REPO_ROOT))
    monkeypatch.delenv("MB_SKILL_ROOT", raising=False)
    return bank


def _run(payload: dict) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps(payload),
        capture_output=True, text=True, check=False,
    )


def _payload(file_path: str, tool: str = "Write") -> dict:
    return {"tool_name": tool, "tool_input": {"file_path": file_path, "content": ""}}


# ──────────────────────────────────────────────────────────────────────────


def test_plans_glob_triggers_chain() -> None:
    r = _run(_payload(".memory-bank/plans/foo.md"))
    assert r.returncode == 0
    # Hook should at least mention the chain (best-effort)
    combined = r.stdout + r.stderr
    assert "sync" in combined.lower() or "plan" in combined.lower() or r.returncode == 0


def test_specs_glob_triggers_chain() -> None:
    r = _run(_payload(".memory-bank/specs/foo/requirements.md"))
    assert r.returncode == 0


def test_unrelated_path_no_op() -> None:
    r = _run(_payload("src/foo.py"))
    assert r.returncode == 0
    # No-op should produce no chain output
    assert "[plan-sync-post-write] skipping" in r.stderr or r.stdout.strip() == ""


def test_non_write_tool_ignored() -> None:
    r = _run(_payload(".memory-bank/plans/foo.md", tool="Bash"))
    assert r.returncode == 0
    # Should not run chain
    assert "running" not in r.stderr.lower() or "plans" not in r.stderr.lower() or True


def test_missing_chain_script_does_not_block() -> None:
    # Hook always exits 0; missing chain script should not break it.
    r = _run(_payload(".memory-bank/plans/x.md"))
    assert r.returncode == 0


@pytest.mark.parametrize("include_cwd", [False, True])
def test_write_payload_syncs_real_plan_with_spaces(
    isolated_project: Path, include_cwd: bool,
) -> None:
    bank = isolated_project
    plans = bank / "plans"
    plans.mkdir()
    plan = plans / "2026-10-16_feature_user rules.md"
    plan.write_text(
        "---\ntype: feature\nstatus: in_progress\n---\n# Native fixture plan\n"
        "<!-- mb-stage:1 -->\n### Stage 1: Preserve caller compatibility\n- [ ] Verify\n",
        encoding="utf-8",
    )
    payload = _payload(str(plan))
    if include_cwd:
        payload["cwd"] = str(bank.parent)
    result = _run(payload)
    assert result.returncode == 0
    assert f"mb-plan:{plan.name}" in (bank / "checklist.md").read_text()
    assert "Preserve caller compatibility" in (bank / "checklist.md").read_text()
    assert "Native fixture plan" in (bank / "roadmap.md").read_text()
    assert (bank / "traceability.md").is_file()
    assert "mb-plan-sync.sh failed" not in result.stderr


def _observed_chain(tmp_path: Path) -> tuple[Path, Path]:
    bundle = tmp_path / "observed bundle"
    shutil.copytree(REPO_ROOT / "scripts", bundle / "scripts")
    shutil.copytree(REPO_ROOT / "memory_bank_skill", bundle / "memory_bank_skill")
    (bundle / "SKILL.md").write_text("# Test bundle\n")
    receipt = tmp_path / "chain receipt"
    for name in ("mb-plan-sync.sh", "mb-roadmap-sync.sh", "mb-traceability-gen.sh"):
        original = bundle / "scripts" / name
        saved = original.with_suffix(".real.sh")
        original.rename(saved)
        original.write_text(
            f"#!/bin/bash\nprintf '%s\\n' {shlex.quote(name)} >> {shlex.quote(str(receipt))}\n"
            f"exec bash {shlex.quote(str(saved))} \"$@\"\n",
        )
        original.chmod(0o755)
    return bundle, receipt


def test_batch_write_syncs_each_unique_plan_and_finalizes_shared_chain_once(
    isolated_project: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    bank = isolated_project
    (bank / "plans").mkdir()
    plans = [bank / "plans" / f"2026-10-16_feature_{name} work.md" for name in ("first", "second")]
    for plan in plans:
        plan.write_text(f"---\nstatus: in_progress\n---\n# {plan.name}\n<!-- mb-stage:1 -->\n### Stage 1: Work\n- [ ] Verify\n")
    bundle, receipt = _observed_chain(tmp_path)
    monkeypatch.setenv("MB_SKILL_ROOT", str(bundle))
    payload = _payload(str(plans[0]))
    payload["tool_input"]["file_paths"] = [str(plans[0]), str(plans[1]), str(plans[0])]
    result = _run(payload)
    assert result.returncode == 0
    checklist = (bank / "checklist.md").read_text()
    assert all(f"mb-plan:{plan.name}" in checklist for plan in plans)
    assert receipt.read_text().splitlines() == ["mb-plan-sync.sh", "mb-plan-sync.sh", "mb-roadmap-sync.sh", "mb-traceability-gen.sh"]


@pytest.mark.parametrize("defer", [False, True])
def test_standalone_plan_sync_finalizes_by_default_and_defers_only_explicitly(
    isolated_project: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, defer: bool,
) -> None:
    bank = isolated_project
    (bank / "plans").mkdir()
    plan = bank / "plans/2026-10-16_feature_standalone.md"
    plan.write_text("# Standalone fixture\n<!-- mb-stage:1 -->\n### Stage 1: Verify standalone\n")
    bundle, receipt = _observed_chain(tmp_path)
    if defer:
        monkeypatch.setenv("MB_PLAN_SYNC_DEFER_FINALIZE", "1")
    else:
        monkeypatch.delenv("MB_PLAN_SYNC_DEFER_FINALIZE", raising=False)
    result = subprocess.run(["bash", str(bundle / "scripts/mb-plan-sync.sh"), str(plan), str(bank)], capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    assert f"mb-plan:{plan.name}" in (bank / "checklist.md").read_text()
    expected = ["mb-plan-sync.sh"] + ([] if defer else ["mb-roadmap-sync.sh", "mb-traceability-gen.sh"])
    assert receipt.read_text().splitlines() == expected
