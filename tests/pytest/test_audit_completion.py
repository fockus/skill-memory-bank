"""Completion identity and target-directory regression contracts (R03/R04)."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def run_script(name: str, *args: object, cwd: Path) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    for key in ("MB_WORK_PARALLEL", "MB_WORK_RUN_ID", "MB_TEST_RUNNER_CMD", "MB_RULES_CHECK_CMD"):
        env.pop(key, None)
    return subprocess.run(
        ["bash", str(ROOT / "scripts" / name), *map(str, args)],
        cwd=cwd, env=env, text=True, capture_output=True, check=False,
    )


def test_completed_spec_cannot_certify_another_spec_with_same_item(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    for topic, ev in [("a", "none — waiver: documentation only"), ("b", "`false`")]:
        spec = bank / "specs" / topic
        spec.mkdir(parents=True)
        (spec / "tasks.md").write_text(
            f"# Tasks\n<!-- mb-task:1 -->\n## Task 1\n**Eval:** {ev}\n"
            f"**DoD:**\n- [ ] Implement {topic}\n"
        )
    init = run_script("mb-work-state.sh", "init", "spec", 1, "--source-topic", "a", "--mb", bank, cwd=tmp_path)
    assert init.returncode == 0, init.stderr
    done = run_script("mb-work-state.sh", "done", "--mb", bank, cwd=tmp_path)
    assert done.returncode == 0, done.stderr
    other = bank / "specs/b/tasks.md"
    original = other.read_bytes()

    result = run_script("mb-work-checkbox.sh", "flip", other, 1, "--mb", bank, cwd=tmp_path)

    assert result.returncode == 1, result.stdout
    assert other.read_bytes() == original
    own = bank / "specs/a/tasks.md"
    good = run_script("mb-work-checkbox.sh", "flip", own, 1, "--mb", bank, cwd=tmp_path)
    assert good.returncode == 0, good.stderr
    assert "- [x] Implement a" in own.read_text()


def test_unbound_legacy_done_state_refuses_certification(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    plan = tmp_path / "work-plan.md"
    plan.write_text("<!-- mb-stage:1 -->\n## Stage 1\n- [ ] Deliver result\n")
    (bank / ".work-state.json").write_text(json.dumps({"source": "plan", "item_no": 1, "phase": "done"}))

    result = run_script("mb-work-checkbox.sh", "flip", plan, 1, "--mb", bank, cwd=tmp_path)

    assert result.returncode == 1
    assert "- [ ] Deliver result" in plan.read_text()


@pytest.mark.parametrize("locator", ["explicit", "legacy-path", "legacy-directory"])
def test_done_source_relative_init_cannot_certify_other_cwd(tmp_path: Path, locator: str) -> None:
    first, other = tmp_path / "first project", tmp_path / "other project"
    bank = first / ".memory-bank"
    bank.mkdir(parents=True)
    other.mkdir()
    relative = Path("work-plan.md") if locator != "legacy-directory" else Path("work/tasks.md")
    for directory in (first, other):
        target = directory / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("<!-- mb-stage:1 -->\n## Stage 1\n- [ ] Deliver result\n")
    args = ["plan", 1, "--source-path", relative] if locator == "explicit" else [
        relative.parent if locator == "legacy-directory" else relative, 1
    ]
    init = run_script("mb-work-state.sh", "init", *args, "--mb", bank, cwd=first)
    assert init.returncode == 0, init.stderr
    done = run_script("mb-work-state.sh", "done", "--mb", bank, cwd=first)
    assert done.returncode == 0, done.stderr

    bad = run_script("mb-work-checkbox.sh", "flip", other / relative, 1, "--mb", bank, cwd=other)

    assert bad.returncode == 1, bad.stdout
    assert "- [ ] Deliver result" in (other / relative).read_text()
    state = json.loads((bank / ".work-state.json").read_text())
    assert state["source_path"] == str((first / relative).resolve())
    good = run_script("mb-work-checkbox.sh", "flip", first / relative, 1, "--mb", bank, cwd=other)
    assert good.returncode == 0, good.stderr
    assert "- [x] Deliver result" in (first / relative).read_text()


def test_legacy_unresolved_path_cannot_certify_new_bank_relative_candidate(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    (bank / "plans").mkdir(parents=True)
    target = bank / "plans/a.md"
    target.write_text(
        "<!-- mb-task:1 -->\n## Task 1\n**Eval:** `false`\n**DoD:**\n- [ ] Deliver result\n"
    )
    init = run_script("mb-work-state.sh", "init", "plans/a.md", 1, "--mb", bank, cwd=tmp_path)
    assert init.returncode == 0, init.stderr
    done = run_script("mb-work-state.sh", "done", "--mb", bank, cwd=tmp_path)
    assert done.returncode == 0, done.stderr
    assert json.loads((bank / ".work-state.json").read_text())["decl"]["verdict"] == "NOFILE"

    result = run_script("mb-work-checkbox.sh", "flip", target, 1, "--mb", bank, cwd=tmp_path)

    assert result.returncode == 1, result.stdout
    assert "- [ ] Deliver result" in target.read_text()


@pytest.mark.parametrize("field", ["source_path", "source"])
def test_legacy_relative_identity_without_init_cwd_refuses_flip(tmp_path: Path, field: str) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    plan = tmp_path / "work-plan.md"
    plan.write_text("<!-- mb-stage:1 -->\n## Stage 1\n- [ ] Deliver result\n")
    state = {"source": "plan", "phase": "done", "item_no": 1, field: "work-plan.md"}
    (bank / ".work-state.json").write_text(json.dumps(state))

    result = run_script("mb-work-checkbox.sh", "flip", plan, 1, "--mb", bank, cwd=tmp_path)

    assert result.returncode == 1, result.stdout
    assert "source" in result.stderr
    assert "- [ ] Deliver result" in plan.read_text()


def test_legacy_absolute_identity_preserves_same_source_idempotent_flip(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    plan = tmp_path / "work-plan.md"
    plan.write_text("<!-- mb-stage:1 -->\n## Stage 1\n- [ ] Deliver result\n")
    state = {"source": str(plan.resolve()), "phase": "done", "item_no": 1}
    (bank / ".work-state.json").write_text(json.dumps(state))

    for _ in range(2):
        result = run_script("mb-work-checkbox.sh", "flip", plan, 1, "--mb", bank, cwd=tmp_path)
        assert result.returncode == 0, result.stderr
        assert "- [x] Deliver result" in plan.read_text()


@pytest.mark.parametrize("replace", ["file", "parent"])
@pytest.mark.parametrize("legacy", [False, True])
def test_canonical_done_source_retargeted_by_symlink_refuses_foreign_flip(tmp_path, replace, legacy):
    bank = tmp_path / ".memory-bank"
    own, other = bank / "specs/a/tasks.md", bank / "specs/b/tasks.md"
    for path, ev in [(own, "none — waiver: docs"), (other, "`false`")]:
        path.parent.mkdir(parents=True)
        path.write_text(f"<!-- mb-task:1 -->\n## Task 1\n**Eval:** {ev}\n- [ ] Deliver result\n")
    init = run_script("mb-work-state.sh", "init", "spec", 1, "--source-topic", "a", "--mb", bank, cwd=tmp_path)
    assert init.returncode == 0, init.stderr
    done = run_script("mb-work-state.sh", "done", "--mb", bank, cwd=tmp_path)
    assert done.returncode == 0, done.stderr
    if legacy:
        state_file = bank / ".work-state.json"
        state = json.loads(state_file.read_text())
        state["source"] = state.pop("source_path")
        state_file.write_text(json.dumps(state))
    if replace == "file":
        own.rename(own.with_name("original.md"))
        own.symlink_to(other)
    else:
        own.parent.rename(own.parent.with_name("original"))
        own.parent.symlink_to(other.parent, target_is_directory=True)

    result = run_script("mb-work-checkbox.sh", "flip", other, 1, "--mb", bank, cwd=tmp_path)

    assert result.returncode == 1, result.stdout
    assert "- [ ] Deliver result" in other.read_text()


def test_target_symlink_to_unchanged_canonical_source_updates_source_and_keeps_alias(tmp_path):
    bank = tmp_path / ".memory-bank"
    own = bank / "specs/a/tasks.md"
    own.parent.mkdir(parents=True)
    own.write_text("<!-- mb-task:1 -->\n## Task 1\n**Eval:** none — waiver: docs\n- [ ] Deliver result\n")
    init = run_script("mb-work-state.sh", "init", "spec", 1, "--source-topic", "a", "--mb", bank, cwd=tmp_path)
    assert init.returncode == 0, init.stderr
    done = run_script("mb-work-state.sh", "done", "--mb", bank, cwd=tmp_path)
    assert done.returncode == 0, done.stderr
    alias = tmp_path / "alias.md"
    alias.symlink_to(own)

    result = run_script("mb-work-checkbox.sh", "flip", alias, 1, "--mb", bank, cwd=tmp_path)

    assert result.returncode == 0, result.stderr
    assert "- [x] Deliver result" in own.read_text()
    assert alias.is_symlink()


@pytest.mark.parametrize("ambiguous", [False, True])
def test_legacy_topic_init_binds_unique_source_or_refuses_ambiguity(tmp_path: Path, ambiguous: bool) -> None:
    bank = tmp_path / ".memory-bank"
    target = bank / "specs/demo/tasks.md"
    target.parent.mkdir(parents=True)
    text = "<!-- mb-task:1 -->\n## Task 1\n**Eval:** none — waiver: docs\n- [ ] Deliver result\n"
    target.write_text(text)
    if ambiguous:
        local = tmp_path / "demo/tasks.md"
        local.parent.mkdir()
        local.write_text(text)

    init = run_script("mb-work-state.sh", "init", "demo", 1, "--mb", bank, cwd=tmp_path)

    if ambiguous:
        assert init.returncode == 2, init.stdout
        assert not (bank / ".work-state.json").exists()
    else:
        assert init.returncode == 0, init.stderr
        state = json.loads((bank / ".work-state.json").read_text())
        assert state["source_path"] == str(target.resolve())
        done = run_script("mb-work-state.sh", "done", "--mb", bank, cwd=tmp_path)
        assert done.returncode == 0, done.stderr
        flip = run_script("mb-work-checkbox.sh", "flip", target, 1, "--mb", bank, cwd=tmp_path)
        assert flip.returncode == 0, flip.stderr


@pytest.mark.parametrize("directory", ["target", "target with spaces"])
def test_done_gates_explicit_directory_detects_violation_from_other_cwd(
    tmp_path: Path, directory: str
) -> None:
    target = tmp_path / directory
    target.mkdir()
    bank = target / ".memory-bank"
    bank.mkdir()
    subprocess.run(["git", "init", "-q", str(target)], check=True)
    (target / "unfinished.py").write_text("def transform(data):\n    # TODO: implement transform\n    return None\n")

    result = run_script("mb-done-gates.sh", "--mb", bank, "--dir", target, "--out", "json", cwd=tmp_path)

    gates = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
    placeholder = next(g for g in gates if g.get("gate") == "placeholders")
    tests = next(g for g in gates if g.get("gate") == "tests")
    assert tests["pass"] is True, result.stdout
    assert placeholder["pass"] is False, result.stdout
    assert result.returncode == 2
