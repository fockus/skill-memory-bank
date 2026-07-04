"""Phase 3 Sprint 2 — `scripts/mb-work-resolve.sh` target resolver."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-resolve.sh"
STATE_SCRIPT = REPO_ROOT / "scripts" / "mb-work-state.sh"


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


def _write_plan(mb: Path, name: str, body: str = "") -> Path:
    p = mb / "plans" / f"{name}.md"
    p.write_text(
        f"---\ntype: feature\ntopic: {name}\nstatus: in-progress\n---\n\n# {name}\n\n{body}",
        encoding="utf-8",
    )
    return p


def _run(
    *args: str, mb: Path | None = None, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    cmd = ["bash", str(SCRIPT), *args]
    if mb is not None:
        cmd.append(str(mb))
    return subprocess.run(cmd, capture_output=True, text=True, check=False, env=env)


def _claim(mb: Path, source: str, run_id: str) -> None:
    """Claim `source` for `run_id` via mb-work-state.sh init (MB_WORK_PARALLEL=1)."""
    env = dict(os.environ)
    env["MB_WORK_PARALLEL"] = "1"
    r = subprocess.run(
        ["bash", str(STATE_SCRIPT), "init", source, "1", "--run-id", run_id, "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )
    assert r.returncode == 0, r.stderr


def _active_plans_roadmap(links: list[tuple[str, str]]) -> str:
    body = "\n".join(f"- [{name}]({rel})" for name, rel in links)
    return f"# Roadmap\n\n<!-- mb-active-plans -->\n{body}\n<!-- /mb-active-plans -->\n"


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
        f"# Roadmap\n\n<!-- mb-active-plans -->\n- [in-flight]({rel})\n<!-- /mb-active-plans -->\n",
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


# ── NEW: spec-task resolution (Stage 1 RED tests) ─────────────────────────


def test_form3_topic_resolves_to_spec_tasks_when_marker_present(tmp_path: Path) -> None:
    """Form 3: topic with mb-task markers in tasks.md → resolved to absolute spec path."""
    mb = _init_mb(tmp_path)
    spec_dir = mb / "specs" / "billing"
    spec_dir.mkdir()
    tasks = spec_dir / "tasks.md"
    tasks.write_text(
        "# Tasks: billing\n\n<!-- mb-task:1 -->\n## Task 1: setup\n\n- [ ] done\n",
        encoding="utf-8",
    )
    r = _run("billing", mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(tasks.resolve())


def test_form1_direct_path_to_spec_tasks_returns_absolute_path(tmp_path: Path) -> None:
    """Form 1: direct path to specs/foo/tasks.md returns its absolute path."""
    mb = _init_mb(tmp_path)
    spec_dir = mb / "specs" / "auth"
    spec_dir.mkdir()
    tasks = spec_dir / "tasks.md"
    tasks.write_text(
        "# Tasks: auth\n\n<!-- mb-task:1 -->\n## Task 1: login flow\n\n- [ ] done\n",
        encoding="utf-8",
    )
    r = _run(str(tasks), mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(tasks.resolve())


def test_form4_candidates_include_specs_entries(tmp_path: Path) -> None:
    """Form 4 freeform: stderr candidate list includes specs/ entries alongside plans/."""
    mb = _init_mb(tmp_path)
    _write_plan(mb, "some-plan")
    spec_dir = mb / "specs" / "notifications"
    spec_dir.mkdir()
    (spec_dir / "tasks.md").write_text(
        "<!-- mb-task:1 -->\n## Task 1: notify\n\n- [ ] done\n",
        encoding="utf-8",
    )
    r = _run("resolve the notification spec issue please", mb=mb)
    assert r.returncode == 3
    combined = r.stderr + r.stdout
    # Candidate list must mention specs/ paths, not only plans/
    assert "specs" in combined.lower(), f"expected 'specs' in stderr candidates, got:\n{combined}"


# ── NEW: I-094 S5 — --skip-claimed / claim-note (MB_WORK_PARALLEL) ────────


def test_empty_target_skips_claimed_plan(tmp_path: Path) -> None:
    """Empty-target + --skip-claimed: source A is claimed by a live run → resolve returns B."""
    mb = _init_mb(tmp_path)
    plan_a = _write_plan(mb, "plan-a")
    plan_b = _write_plan(mb, "plan-b")
    (mb / "roadmap.md").write_text(
        _active_plans_roadmap([("plan-a", "plans/plan-a.md"), ("plan-b", "plans/plan-b.md")]),
        encoding="utf-8",
    )
    _claim(mb, str(plan_a.resolve()), "r1")

    env = dict(os.environ)
    env["MB_WORK_PARALLEL"] = "1"
    r = _run("--skip-claimed", mb=mb, env=env)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(plan_b.resolve())


def test_empty_target_all_claimed_exits_1(tmp_path: Path) -> None:
    """Empty-target + --skip-claimed: both A and B claimed by live runs → exit 1."""
    mb = _init_mb(tmp_path)
    plan_a = _write_plan(mb, "plan-a")
    plan_b = _write_plan(mb, "plan-b")
    (mb / "roadmap.md").write_text(
        _active_plans_roadmap([("plan-a", "plans/plan-a.md"), ("plan-b", "plans/plan-b.md")]),
        encoding="utf-8",
    )
    _claim(mb, str(plan_a.resolve()), "r1")
    _claim(mb, str(plan_b.resolve()), "r2")

    env = dict(os.environ)
    env["MB_WORK_PARALLEL"] = "1"
    r = _run("--skip-claimed", mb=mb, env=env)
    assert r.returncode == 1
    assert "all active plans claimed" in (r.stderr + r.stdout).lower()


def test_explicit_claimed_target_warns_but_resolves(tmp_path: Path) -> None:
    """Explicit target claimed by run r1 → exit 0, path printed, stderr claim-note."""
    mb = _init_mb(tmp_path)
    plan_a = _write_plan(mb, "plan-a")
    _claim(mb, str(plan_a.resolve()), "r1")

    env = dict(os.environ)
    env["MB_WORK_PARALLEL"] = "1"
    r = _run(str(plan_a), mb=mb, env=env)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(plan_a.resolve())
    assert "claimed by run r1" in r.stderr.lower()
    assert "--takeover" in r.stderr.lower()


def test_skip_claimed_off_by_default(tmp_path: Path) -> None:
    """No --skip-claimed / no MB_WORK_PARALLEL → resolution byte-identical to today,
    even though the (sole) active plan is claimed by a live run."""
    mb = _init_mb(tmp_path)
    plan_a = _write_plan(mb, "plan-a")
    (mb / "roadmap.md").write_text(
        _active_plans_roadmap([("plan-a", "plans/plan-a.md")]),
        encoding="utf-8",
    )
    _claim(mb, str(plan_a.resolve()), "r1")

    r = _run(mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(plan_a.resolve())
    assert r.stderr == ""
