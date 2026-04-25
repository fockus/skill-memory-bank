"""Phase 3 Sprint 2 — `scripts/mb-work-plan.sh` execution-plan emitter."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-plan.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "plans" / "done").mkdir(parents=True)
    (mb / "specs").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n",
        encoding="utf-8",
    )
    return mb


def _stage(no: int, heading: str, body: str = "- ✅ DoD bit\n") -> str:
    return f"<!-- mb-stage:{no} -->\n## Stage {no}: {heading}\n\n{body}\n"


def _plan(stages: list[str]) -> str:
    return (
        "---\ntype: feature\ntopic: foo\nstatus: in-progress\n---\n\n# Plan\n\n"
        + "".join(stages)
    )


def _run(*args: str, mb: Path | None = None) -> subprocess.CompletedProcess[str]:
    cmd = ["bash", str(SCRIPT), *args]
    if mb is not None:
        cmd += ["--mb", str(mb)]
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def _parse_jsonl(stdout: str) -> list[dict]:
    return [json.loads(line) for line in stdout.strip().splitlines() if line.strip().startswith("{")]


# ──────────────────────────────────────────────────────────────────────────


def test_emits_one_object_per_stage(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(_plan([_stage(1, "do A"), _stage(2, "do B"), _stage(3, "do C")]), encoding="utf-8")
    r = _run("--target", str(plan), mb=mb)
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    assert len(objs) == 3
    for o in objs:
        for k in ("plan", "stage_no", "heading", "role", "agent", "status", "dod_lines"):
            assert k in o, f"missing {k}"


def test_role_auto_detect_frontend(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(
        _plan([_stage(1, "Build React UI component", "- ✅ Tailwind classes\n")]),
        encoding="utf-8",
    )
    r = _run("--target", str(plan), mb=mb)
    assert r.returncode == 0, r.stderr
    obj = _parse_jsonl(r.stdout)[0]
    assert obj["role"] == "frontend"
    assert obj["agent"] == "mb-frontend"


def test_role_auto_detect_backend(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(
        _plan([_stage(1, "Create FastAPI endpoint", "- ✅ Pydantic schema\n")]),
        encoding="utf-8",
    )
    r = _run("--target", str(plan), mb=mb)
    assert r.returncode == 0, r.stderr
    obj = _parse_jsonl(r.stdout)[0]
    assert obj["role"] == "backend"


def test_role_auto_detect_devops(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(
        _plan([_stage(1, "Update Dockerfile + CI", "- ✅ k8s manifests\n")]),
        encoding="utf-8",
    )
    r = _run("--target", str(plan), mb=mb)
    obj = _parse_jsonl(r.stdout)[0]
    assert obj["role"] == "devops"


def test_role_auto_detect_qa(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(
        _plan([_stage(1, "RED tests for parser", "- ✅ pytest cases\n")]),
        encoding="utf-8",
    )
    r = _run("--target", str(plan), mb=mb)
    obj = _parse_jsonl(r.stdout)[0]
    assert obj["role"] == "qa"


def test_role_default_developer(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(
        _plan([_stage(1, "Generic refactor", "- ✅ improve\n")]),
        encoding="utf-8",
    )
    r = _run("--target", str(plan), mb=mb)
    obj = _parse_jsonl(r.stdout)[0]
    assert obj["role"] == "developer"
    assert obj["agent"] == "mb-developer"


def test_range_filter(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(
        _plan([_stage(i, f"thing {i}") for i in range(1, 6)]),
        encoding="utf-8",
    )
    r = _run("--target", str(plan), "--range", "2-4", mb=mb)
    objs = _parse_jsonl(r.stdout)
    assert [o["stage_no"] for o in objs] == [2, 3, 4]


def test_dry_run_human_header(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(_plan([_stage(1, "thing one")]), encoding="utf-8")
    r = _run("--target", str(plan), "--dry-run", mb=mb)
    assert r.returncode == 0, r.stderr
    assert "Execution Plan" in r.stdout


def test_no_target_with_no_active_plan(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run(mb=mb)
    assert r.returncode == 1


def test_dod_lines_count(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "p.md"
    plan.write_text(
        _plan([_stage(1, "thing", "- ✅ first\n- ⬜ second\n- ⬜ third\n")]),
        encoding="utf-8",
    )
    r = _run("--target", str(plan), mb=mb)
    obj = _parse_jsonl(r.stdout)[0]
    assert obj["dod_lines"] == 3
