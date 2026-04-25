"""Phase 3 Sprint 2 — `scripts/mb-work-resolve.sh` target resolver."""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-resolve.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "plans" / "done").mkdir(parents=True)
    (mb / "specs").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n"
        "<!-- mb-active-plans -->\n"
        "<!-- /mb-active-plans -->\n",
        encoding="utf-8",
    )
    return mb


def _write_plan(mb: Path, name: str, body: str = "") -> Path:
    p = mb / "plans" / f"{name}.md"
    p.write_text(
        f"---\ntype: feature\ntopic: {name}\nstatus: in-progress\n---\n\n# {name}\n\n{body}",
        encoding="utf-8",
    )
    return p


def _run(*args: str, mb: Path | None = None) -> subprocess.CompletedProcess[str]:
    cmd = ["bash", str(SCRIPT), *args]
    if mb is not None:
        cmd.append(str(mb))
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


# ──────────────────────────────────────────────────────────────────────────


def test_form1_existing_path(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = _write_plan(mb, "auth-refactor")
    r = _run(str(plan), mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(plan.resolve())


def test_form2_substring_unique(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = _write_plan(mb, "billing-migrate-stripe")
    r = _run("billing", mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(plan.resolve())


def test_form2_substring_ambiguous(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _write_plan(mb, "auth-refactor")
    _write_plan(mb, "auth-bugfix")
    r = _run("auth", mb=mb)
    assert r.returncode == 2
    msg = (r.stderr + r.stdout).lower()
    assert "auth-refactor" in msg
    assert "auth-bugfix" in msg


def test_form3_topic_specs_tasks(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    spec_dir = mb / "specs" / "inventory"
    spec_dir.mkdir()
    tasks = spec_dir / "tasks.md"
    tasks.write_text("# tasks\n", encoding="utf-8")
    r = _run("inventory", mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(tasks.resolve())


def test_form4_freeform_three_words(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _write_plan(mb, "auth-refactor")
    r = _run("fix the auth flake", mb=mb)
    assert r.returncode == 3
    msg = (r.stderr + r.stdout).lower()
    assert "freeform" in msg


def test_form5_empty_with_one_active(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    plan = _write_plan(mb, "in-flight")
    rel = "plans/in-flight.md"
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n"
        "<!-- mb-active-plans -->\n"
        f"- [in-flight]({rel})\n"
        "<!-- /mb-active-plans -->\n",
        encoding="utf-8",
    )
    r = _run(mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(plan.resolve())


def test_form5_empty_no_active(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run(mb=mb)
    assert r.returncode == 1
    assert "no active" in (r.stderr + r.stdout).lower()


def test_unknown_target_fails(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("doesnotexist", mb=mb)
    assert r.returncode == 1
    assert "not found" in (r.stderr + r.stdout).lower()


def test_done_plans_excluded_from_substring(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    done = mb / "plans" / "done" / "old-plan.md"
    done.write_text("---\nstatus: done\n---\n\n# old\n", encoding="utf-8")
    r = _run("old", mb=mb)
    assert r.returncode == 1, r.stdout
