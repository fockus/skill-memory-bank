"""Native opt-in preserves only canonical successful state; legacy contracts stay unchanged."""

from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "scripts/mb-work-state.sh"


class Work:
    def __init__(self, root: Path, *, native: bool = True, plan: bool = False) -> None:
        self.root = root.resolve()
        self.bank = self.root / ".memory-bank"
        self.source = self.bank / ("plans/case.md" if plan else "specs/case/tasks.md")
        self.source.parent.mkdir(parents=True)
        self.source.write_text("<!-- mb-stage:1 -->\n### Stage 1\n- [ ] Product\n" if plan else
                               "<!-- mb-task:1 -->\n## Task 1\n**Role:** developer\n"
                               "**Eval:** python3 check.py — red: product wrong; exit: 1; output~: PRODUCT_RED\n"
                               "**DoD:**\n- [ ] Product\n")
        (self.root / "check.py").write_text("from pathlib import Path\nimport sys\n"
                                            "ok = Path('product').exists()\n"
                                            "print('PRODUCT_GREEN' if ok else 'PRODUCT_RED')\nsys.exit(0 if ok else 1)\n")
        (self.root / "eval.cmd").write_text("python3 check.py\n")
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("MB_", "CLAUDE_"))}
        self.env.update(HOME=str(self.root), MB_REPO_ROOT=str(self.root))
        self.run_id = "native-A"
        if native:
            self.env.update(MB_WORK_RETAIN_STATE="1", MB_WORK_RETAIN_BANK=str(self.bank),
                            MB_WORK_RUN_ID=self.run_id, MB_WORK_PARALLEL="1")
        self.plan = plan

    @property
    def retained(self) -> Path:
        return self.bank / ".work-completed" / f"{self.run_id}.json"

    @property
    def live(self) -> Path:
        return self.bank / ".work-state" / f"{self.run_id}.json" if self.env.get("MB_WORK_PARALLEL") else self.bank / ".work-state.json"

    def run(self, *args: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(["bash", str(STATE), *args, "--mb", str(self.bank), "--run-id", self.run_id],
                                cwd=self.root, env=self.env, capture_output=True, text=True, timeout=15)
        assert result.returncode == expected, result.stdout + result.stderr
        return result

    def init(self) -> None:
        self.run("init", "plan" if self.plan else "spec", "1", "--source-path", str(self.source), "--max-cycles", "2")

    def finish(self) -> dict:
        if not self.plan:
            self.run("eval-red", "--cmd-file", "eval.cmd", "--output-re", "PRODUCT_RED", "--expected-exit", "1")
            (self.root / "product").write_text("green\n")
            self.run("eval-green", "--cmd-file", "eval.cmd")
        self.run("done")
        result = subprocess.run(["bash", str(ROOT / "scripts/mb-work-checkbox.sh"), "flip", str(self.source), "1",
                                 "--run-id", self.run_id, "--mb", str(self.bank)],
                                cwd=self.root, env=self.env, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stdout + result.stderr
        return json.loads(self.run("status").stdout)


@pytest.mark.parametrize("plan", [False, True])
def test_grouped_clear_retains_exact_helper_owned_full_state_and_honest_gate(tmp_path: Path, plan: bool) -> None:
    work = Work(tmp_path, plan=plan)
    work.init()
    completed = work.finish()
    assert completed["eval_gate"] == ("unverified:no_declaration_surface" if plan else "verified:red_green")
    assert work.run("clear").stdout == ""
    assert not work.live.exists()
    assert json.loads(work.retained.read_text()) == completed
    assert json.loads(work.run("retained").stdout) == completed
    assert json.loads(work.run("status", "--all").stdout) == []
    assert stat.S_IMODE(work.retained.stat().st_mode) == 0o600
    assert stat.S_IMODE(work.retained.parent.stat().st_mode) == 0o700


def test_default_clear_has_no_new_artifact_or_output(tmp_path: Path) -> None:
    work = Work(tmp_path, native=False)
    work.init()
    work.finish()
    assert work.run("clear").stdout == ""
    assert not work.live.exists() and not work.retained.parent.exists()
    assert work.run("status").stdout.strip() == "{}"


@pytest.mark.parametrize("plan", [False, True])
def test_repeated_clear_preserves_only_existing_revalidated_success(tmp_path: Path, plan: bool) -> None:
    work = Work(tmp_path, plan=plan)
    work.init()
    completed = work.finish()
    work.run("clear")
    retained = work.retained.read_bytes()
    assert work.run("clear").stdout == ""
    assert json.loads(work.run("retained").stdout) == completed
    assert work.retained.read_bytes() == retained
    assert json.loads(work.run("status", "--all").stdout) == []


def test_repeated_clear_without_init_does_not_manufacture_completion(tmp_path: Path) -> None:
    work = Work(tmp_path)
    work.run("clear")
    work.run("clear")
    assert json.loads(work.run("retained").stdout) == {}
    assert not work.retained.parent.exists()


def test_native_canonical_callers_may_use_a_relative_bank_locator(tmp_path: Path) -> None:
    work = Work(tmp_path)
    result = subprocess.run(["bash", str(STATE), "init", "spec", "1", "--source-path", str(work.source), "--mb", ".memory-bank"],
                            cwd=work.root, env=work.env, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    completed = work.finish()
    for operation in ("clear", "retained"):
        result = subprocess.run(["bash", str(STATE), operation, "--mb", ".memory-bank"],
                                cwd=work.root, env=work.env, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == completed


@pytest.mark.parametrize("parallel", ["true", "on"])
def test_retention_uses_the_canonical_helpers_parallel_slot_selection(tmp_path: Path, parallel: str) -> None:
    work = Work(tmp_path, plan=True)
    work.env["MB_WORK_PARALLEL"] = parallel
    work.init()
    completed = work.finish()
    work.run("clear")
    assert json.loads(work.run("retained").stdout) == completed


def test_same_id_reinit_and_failed_eval_with_stale_checked_boxes_cannot_reuse_success(tmp_path: Path) -> None:
    work = Work(tmp_path)
    work.init()
    work.finish()
    work.run("clear")
    assert work.retained.exists()
    work.init()
    assert not work.retained.exists()
    assert "- [x]" in work.source.read_text()
    (tmp_path / "product").unlink()
    work.run("eval-red", "--cmd-file", "eval.cmd", "--output-re", "PRODUCT_RED", "--expected-exit", "1")
    work.run("eval-green", "--cmd-file", "eval.cmd", expected=1)
    work.run("done", expected=5)
    work.run("clear")
    assert json.loads(work.run("retained").stdout) == {}


@pytest.mark.parametrize("change", ["declaration", "eval-proof", "adapt", "run-id"])
def test_retained_reader_revalidates_existing_proof_and_identity(tmp_path: Path, change: str) -> None:
    work = Work(tmp_path)
    work.init()
    work.finish()
    work.run("clear")
    if change == "declaration":
        work.source.write_text(work.source.read_text().replace("python3 check.py", "python3 other.py"))
    else:
        data = json.loads(work.retained.read_text())
        if change == "eval-proof":
            data["eval"]["green_exit"] = 1
        elif change == "run-id":
            data["run_id"] = "foreign-run"
        else:
            data["adapt"] = {"subitems": [{"id": "1.1", "parent": "1", "phase": "open"}]}
        work.retained.write_text(json.dumps(data))
    result = work.run("retained", expected=2 if change == "run-id" else 0)
    if change != "run-id":
        assert json.loads(result.stdout) == {}
        assert work.run("clear").stdout == ""
        assert not work.retained.exists()


@pytest.mark.parametrize("unsafe", ["leaf", "parent", "ancestor", "oversize", "traversal"])
def test_unsafe_retention_paths_refuse_without_reading_or_writing_foreign_data(tmp_path: Path, unsafe: str) -> None:
    work = Work(tmp_path / "owned", plan=True)
    work.init()
    work.finish()
    foreign = tmp_path / "foreign"
    foreign.mkdir()
    canary = foreign / "canary.json"
    canary.write_text("FOREIGN_UNTOUCHED")
    if unsafe == "leaf":
        work.retained.parent.mkdir(mode=0o700)
        work.retained.symlink_to(canary)
    elif unsafe == "parent":
        work.retained.parent.symlink_to(foreign, target_is_directory=True)
    elif unsafe == "ancestor":
        alias = tmp_path / "alias"
        alias.symlink_to(work.root, target_is_directory=True)
        work.bank = alias / ".memory-bank"
        work.env["MB_WORK_RETAIN_BANK"] = str(work.bank)
    elif unsafe == "oversize":
        work.retained.parent.mkdir(mode=0o700)
        work.retained.write_bytes(b"x" * (1024 * 1024 + 1))
        work.retained.chmod(0o600)
    else:
        work.run_id = "../foreign"
        work.env["MB_WORK_RUN_ID"] = work.run_id
    work.run("clear", expected=2)
    work.run("retained", expected=2)
    assert canary.read_text() == "FOREIGN_UNTOUCHED"
    assert sorted(p.name for p in foreign.iterdir()) == ["canary.json"]


def test_native_run_and_bank_environment_cannot_mutate_a_foreign_slot(tmp_path: Path) -> None:
    work = Work(tmp_path / "owner", plan=True)
    work.init()
    original = work.live.read_bytes()
    for flags in [("--run-id", "foreign"), ("--mb", str(tmp_path / "other-bank"))]:
        result = subprocess.run(["bash", str(STATE), "clear", "--mb", str(work.bank), "--run-id", work.run_id, *flags],
                                cwd=work.root, env=work.env, capture_output=True, text=True, timeout=15)
        assert result.returncode == 2
        assert work.live.read_bytes() == original


def test_parallel_native_runs_keep_retention_and_live_slots_separate(tmp_path: Path) -> None:
    work = Work(tmp_path, plan=True)
    work.init()
    work.finish()
    work.run("clear")
    first = work.retained.read_bytes()
    work.run_id = "native-B"
    work.env["MB_WORK_RUN_ID"] = work.run_id
    work.source = work.bank / "plans/second.md"
    work.source.write_text("<!-- mb-stage:1 -->\n### Stage 1\n- [ ] Other\n")
    work.init()
    assert json.loads(work.run("retained").stdout) == {}
    assert (work.retained.parent / "native-A.json").read_bytes() == first
    assert [s["run_id"] for s in json.loads(work.run("status", "--all").stdout)] == ["native-B"]


def test_retention_directory_and_live_input_are_bounded_without_deleting_unrelated_files(tmp_path: Path) -> None:
    work = Work(tmp_path, plan=True)
    work.init()
    work.finish()
    original = work.live.read_bytes()
    work.live.write_bytes(original + b" " * (1024 * 1024))
    work.run("clear", expected=2)
    work.live.write_bytes(original)
    work.retained.parent.mkdir(mode=0o700)
    for number in range(257):
        (work.retained.parent / f"unrelated-{number}").touch(mode=0o600)
    work.run("clear", expected=2)
    assert work.live.read_bytes() == original and len(list(work.retained.parent.iterdir())) == 257


def test_retained_reader_refuses_a_source_symlink_without_reading_foreign_content(tmp_path: Path) -> None:
    work = Work(tmp_path)
    work.init()
    work.finish()
    work.run("clear")
    foreign = tmp_path / "foreign.md"
    foreign.write_text("PRIVATE_FOREIGN_CANARY")
    work.source.unlink()
    work.source.symlink_to(foreign)
    result = work.run("retained", expected=2)
    assert "PRIVATE_FOREIGN_CANARY" not in result.stdout + result.stderr
    assert foreign.read_text() == "PRIVATE_FOREIGN_CANARY"
