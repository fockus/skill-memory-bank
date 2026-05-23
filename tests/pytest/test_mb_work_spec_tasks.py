"""Sprint 2 Stage 1 — RED contract tests for `/mb work` spec-task integration.

All tests in this file are expected to FAIL (RED) until production scripts
(mb-work-resolve.sh, mb-work-range.sh, mb-work-plan.sh) are updated in
Stages 2-4 of the sdd-work-engine plan.

Naming convention: test_<what>_<condition>_<result>
Structure: Arrange-Act-Assert, isolated via tmp_path, no mocks.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RESOLVE = REPO_ROOT / "scripts" / "mb-work-resolve.sh"
RANGE_SH = REPO_ROOT / "scripts" / "mb-work-range.sh"
PLAN_SH = REPO_ROOT / "scripts" / "mb-work-plan.sh"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


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


def _make_spec_tasks(mb: Path, topic: str, n_tasks: int = 3) -> Path:
    """Create a minimal spec tasks.md with n_tasks mb-task markers."""
    spec_dir = mb / "specs" / topic
    spec_dir.mkdir(parents=True, exist_ok=True)
    tasks_path = spec_dir / "tasks.md"
    blocks = []
    for i in range(1, n_tasks + 1):
        req_id = f"REQ-{i:03d}"
        blocks.append(
            f"<!-- mb-task:{i} -->\n"
            f"## Task {i}: implement feature {i}\n\n"
            f"**Covers:** {req_id}\n"
            f"**Role:** developer\n\n"
            f"**What to do:**\n- step {i}\n\n"
            f"**DoD:**\n- [ ] criterion {i}\n- [ ] tests pass\n"
        )
    tasks_path.write_text(
        f"# Tasks: {topic}\n\n" + "\n".join(blocks),
        encoding="utf-8",
    )
    return tasks_path


def _make_plan(mb: Path, name: str, body: str = "") -> Path:
    p = mb / "plans" / f"{name}.md"
    p.write_text(
        f"---\ntype: feature\ntopic: {name}\nstatus: in-progress\n---\n\n# {name}\n\n{body}",
        encoding="utf-8",
    )
    return p


def _make_wrapper_plan(
    mb: Path,
    name: str,
    linked_spec: str,
    tasks_range: str | None = None,
) -> Path:
    """Create a plan-as-wrapper with linked_spec frontmatter."""
    fm_lines = [
        "---",
        "type: feature",
        f"topic: {name}",
        "status: in-progress",
        f"linked_spec: {linked_spec}",
    ]
    if tasks_range is not None:
        fm_lines.append(f"tasks: {tasks_range}")
    fm_lines.append("---")
    header = "\n".join(fm_lines)
    content = f"{header}\n\n# {name}\n\nExecution wrapper for {linked_spec}.\n"
    p = mb / "plans" / f"{name}.md"
    p.write_text(content, encoding="utf-8")
    return p


def _run_resolve(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    cmd = ["bash", str(RESOLVE), *args, "--mb", str(mb)]
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def _run_range(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(RANGE_SH), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _run_plan(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(PLAN_SH), *args, "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def _parse_jsonl(stdout: str) -> list[dict]:
    return [
        json.loads(line) for line in stdout.strip().splitlines() if line.strip().startswith("{")
    ]


# ---------------------------------------------------------------------------
# resolve tests (Form 3 + Form 1 for spec paths)
# ---------------------------------------------------------------------------


def test_resolve_topic_returns_spec_tasks_path_when_spec_exists(
    tmp_path: Path,
) -> None:
    """Form 3: topic resolves to specs/<topic>/tasks.md when spec exists with mb-task markers."""
    # Arrange
    mb = _init_mb(tmp_path)
    tasks = _make_spec_tasks(mb, "foo", n_tasks=2)

    # Act
    r = _run_resolve("foo", mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(tasks.resolve())


def test_resolve_existing_spec_tasks_path_returns_absolute_path(
    tmp_path: Path,
) -> None:
    """Form 1: direct path to specs/foo/tasks.md is resolved to absolute path."""
    # Arrange
    mb = _init_mb(tmp_path)
    tasks = _make_spec_tasks(mb, "bar", n_tasks=2)

    # Act
    r = _run_resolve(str(tasks), mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(tasks.resolve())


# ---------------------------------------------------------------------------
# mb-work-plan: source=spec, kind=task, covers
# ---------------------------------------------------------------------------


def test_work_plan_emits_source_spec_for_spec_tasks(tmp_path: Path) -> None:
    """mb-work-plan.sh with a spec tasks.md target emits source=spec, kind=task."""
    # Arrange
    mb = _init_mb(tmp_path)
    tasks = _make_spec_tasks(mb, "inventory-sync", n_tasks=2)

    # Act
    r = _run_plan("--target", str(tasks), mb=mb)

    # Assert: exit 0 and JSONL with source=spec
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    assert len(objs) >= 1
    for obj in objs:
        assert obj.get("source") == "spec", f"expected source=spec, got: {obj}"
        assert obj.get("kind") == "task", f"expected kind=task, got: {obj}"


def test_work_plan_covers_field_extracted_from_spec_tasks(tmp_path: Path) -> None:
    """Task with **Covers:** REQ-001 yields covers=['REQ-001'] in JSON output."""
    # Arrange
    mb = _init_mb(tmp_path)
    spec_dir = mb / "specs" / "cart"
    spec_dir.mkdir(parents=True)
    (spec_dir / "tasks.md").write_text(
        "# Tasks: cart\n\n"
        "<!-- mb-task:1 -->\n"
        "## Task 1: checkout flow\n\n"
        "**Covers:** REQ-001, REQ-002\n"
        "**Role:** backend\n\n"
        "**DoD:**\n- [ ] tests pass\n",
        encoding="utf-8",
    )

    # Act
    r = _run_plan("--target", str(spec_dir / "tasks.md"), mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    assert len(objs) == 1
    covers = objs[0].get("covers", [])
    assert "REQ-001" in covers, f"REQ-001 missing from covers: {covers}"
    assert "REQ-002" in covers, f"REQ-002 missing from covers: {covers}"


def test_work_plan_respects_explicit_developer_role_for_spec_tasks(tmp_path: Path) -> None:
    """Spec tasks with explicit Role: developer must not be re-routed to qa by pytest text."""
    mb = _init_mb(tmp_path)
    spec_dir = mb / "specs" / "overlay"
    spec_dir.mkdir(parents=True)
    (spec_dir / "tasks.md").write_text(
        "# Tasks: overlay\n\n"
        "<!-- mb-task:1 -->\n"
        "## Task 1: build resolver\n\n"
        "**Covers:** REQ-001\n"
        "**Role:** developer\n\n"
        "**Testing:** pytest validates resolver output.\n\n"
        "**DoD:**\n- [ ] resolver implemented\n",
        encoding="utf-8",
    )

    r = _run_plan("--target", str(spec_dir / "tasks.md"), mb=mb)

    assert r.returncode == 0, r.stderr
    obj = _parse_jsonl(r.stdout)[0]
    assert obj["role"] == "developer"
    assert obj["agent"] == "mb-developer"


def test_work_plan_item_no_alias_equals_stage_no(tmp_path: Path) -> None:
    """JSON output has item_no field equal to stage_no for backward compat."""
    # Arrange
    mb = _init_mb(tmp_path)
    tasks = _make_spec_tasks(mb, "orders", n_tasks=2)

    # Act
    r = _run_plan("--target", str(tasks), mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    for obj in objs:
        assert "item_no" in obj, f"item_no missing: {obj}"
        assert "stage_no" in obj, f"stage_no missing: {obj}"
        assert obj["item_no"] == obj["stage_no"], (
            f"item_no ({obj['item_no']}) != stage_no ({obj['stage_no']})"
        )


# ---------------------------------------------------------------------------
# mb-work-range: auto-detect mb-task markers
# ---------------------------------------------------------------------------


def test_work_range_auto_detects_mb_task_marker(tmp_path: Path) -> None:
    """mb-work-range.sh on a spec tasks.md file emits task indices 1..N."""
    # Arrange
    tasks = tmp_path / "tasks.md"
    tasks.write_text(
        "# Tasks\n\n"
        "<!-- mb-task:1 -->\n## Task 1: alpha\n\n- [ ] done\n\n"
        "<!-- mb-task:2 -->\n## Task 2: beta\n\n- [ ] done\n\n"
        "<!-- mb-task:3 -->\n## Task 3: gamma\n\n- [ ] done\n",
        encoding="utf-8",
    )

    # Act
    r = _run_range(str(tasks))

    # Assert: currently fails because range.sh only looks for mb-stage
    assert r.returncode == 0, r.stderr
    out = r.stdout.strip().splitlines()
    assert out == ["1", "2", "3"], f"expected [1,2,3], got {out}"


# ---------------------------------------------------------------------------
# mb-work-plan: range filtering on spec tasks
# ---------------------------------------------------------------------------


def test_work_plan_range_filters_spec_tasks(tmp_path: Path) -> None:
    """--range 2-3 on spec tasks.md emits only items 2 and 3."""
    # Arrange
    mb = _init_mb(tmp_path)
    tasks = _make_spec_tasks(mb, "payments", n_tasks=4)

    # Act
    r = _run_plan("--target", str(tasks), "--range", "2-3", mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    item_nos = [o.get("item_no") or o.get("stage_no") for o in objs]
    assert item_nos == [2, 3], f"expected [2,3], got {item_nos}"


# ---------------------------------------------------------------------------
# Plan-as-wrapper: linked_spec frontmatter
# ---------------------------------------------------------------------------


def test_work_plan_resolves_linked_spec_in_plan_frontmatter(tmp_path: Path) -> None:
    """Wrapper plan with linked_spec + tasks: 1-2 emits 2 items from spec, source=spec."""
    # Arrange
    mb = _init_mb(tmp_path)
    _make_spec_tasks(mb, "shipping", n_tasks=3)
    wrapper = _make_wrapper_plan(mb, "sprint-1-shipping", "specs/shipping", tasks_range="1-2")

    # Act
    r = _run_plan("--target", str(wrapper), mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    assert len(objs) == 2, f"expected 2 items, got {len(objs)}: {objs}"
    for obj in objs:
        assert obj.get("source") == "spec", f"expected source=spec: {obj}"
    assert objs[0].get("plan") == "sprint-1-shipping.md", (
        f"plan field should be wrapper basename: {objs[0]}"
    )


def test_work_plan_linked_spec_open_range(tmp_path: Path) -> None:
    """Wrapper plan with tasks: 2- emits items 2..N from linked spec."""
    # Arrange
    mb = _init_mb(tmp_path)
    _make_spec_tasks(mb, "catalog", n_tasks=4)
    wrapper = _make_wrapper_plan(mb, "sprint-catalog", "specs/catalog", tasks_range="2-")

    # Act
    r = _run_plan("--target", str(wrapper), mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    item_nos = [o.get("item_no") or o.get("stage_no") for o in objs]
    assert item_nos == [2, 3, 4], f"expected [2,3,4], got {item_nos}"


def test_work_plan_linked_spec_without_tasks_emits_all(tmp_path: Path) -> None:
    """Wrapper plan with linked_spec but no tasks key emits all spec items."""
    # Arrange
    mb = _init_mb(tmp_path)
    _make_spec_tasks(mb, "users", n_tasks=3)
    wrapper = _make_wrapper_plan(mb, "sprint-users-all", "specs/users", tasks_range=None)

    # Act
    r = _run_plan("--target", str(wrapper), mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    assert len(objs) == 3, f"expected 3 items, got {len(objs)}"
    for obj in objs:
        assert obj.get("source") == "spec", f"expected source=spec: {obj}"


# ---------------------------------------------------------------------------
# Regression: plain plan without linked_spec → backward compat
# ---------------------------------------------------------------------------


def test_work_plan_plain_plan_backward_compat(tmp_path: Path) -> None:
    """Plain plan with mb-stage markers (no linked_spec) emits source=plan, kind=stage."""
    # Arrange
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "plain.md"
    plan.write_text(
        "---\ntype: feature\ntopic: plain\nstatus: in-progress\n---\n\n# Plain\n\n"
        "<!-- mb-stage:1 -->\n## Stage 1: do A\n\n- [ ] done A\n\n"
        "<!-- mb-stage:2 -->\n## Stage 2: do B\n\n- [ ] done B\n",
        encoding="utf-8",
    )

    # Act
    r = _run_plan("--target", str(plan), mb=mb)

    # Assert: existing fields intact; regression guard
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    assert len(objs) == 2
    for obj in objs:
        # source and kind are NEW fields — currently missing from production output
        assert obj.get("source") == "plan", f"expected source=plan: {obj}"
        assert obj.get("kind") == "stage", f"expected kind=stage: {obj}"
        # Legacy fields must still be present
        assert "stage_no" in obj, f"stage_no missing: {obj}"
        assert "heading" in obj, f"heading missing: {obj}"


# ---------------------------------------------------------------------------
# Mixed markers: exit 1
# ---------------------------------------------------------------------------


def test_work_plan_mixed_markers_in_one_file_exits_one(tmp_path: Path) -> None:
    """File with both mb-stage and mb-task markers causes exit 1 with 'mixed' in stderr."""
    # Arrange
    mb = _init_mb(tmp_path)
    mixed = mb / "plans" / "mixed.md"
    mixed.write_text(
        "---\ntype: feature\ntopic: mixed\nstatus: in-progress\n---\n\n# Mixed\n\n"
        "<!-- mb-stage:1 -->\n## Stage 1: old stage\n\n- [ ] done\n\n"
        "<!-- mb-task:1 -->\n## Task 1: new task\n\n- [ ] done\n",
        encoding="utf-8",
    )

    # Act
    r = _run_plan("--target", str(mixed), mb=mb)

    # Assert
    assert r.returncode == 1, f"expected exit 1, got {r.returncode}"
    stderr_lower = r.stderr.lower()
    assert "mixed" in stderr_lower, f"expected 'mixed' in stderr: {r.stderr!r}"


# ---------------------------------------------------------------------------
# Empty target → first active plan (backward compat)
# ---------------------------------------------------------------------------


def test_work_plan_empty_target_uses_first_active_plan(tmp_path: Path) -> None:
    """Empty --target resolves to the first active plan from roadmap.md mb-active-plans block."""
    # Arrange
    mb = _init_mb(tmp_path)
    plan = mb / "plans" / "active-plan.md"
    plan.write_text(
        "---\ntype: feature\ntopic: active-plan\nstatus: in-progress\n---\n\n# Active\n\n"
        "<!-- mb-stage:1 -->\n## Stage 1: do it\n\n- [ ] done\n",
        encoding="utf-8",
    )
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n"
        "<!-- mb-active-plans -->\n"
        "- [active-plan](plans/active-plan.md)\n"
        "<!-- /mb-active-plans -->\n",
        encoding="utf-8",
    )

    # Act  (no --target)
    r = _run_plan(mb=mb)

    # Assert
    assert r.returncode == 0, r.stderr
    objs = _parse_jsonl(r.stdout)
    assert len(objs) == 1
    assert objs[0].get("plan") == "active-plan.md"
