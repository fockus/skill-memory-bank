"""Pi guard hooks and post-write synchronization (Stage 4).

Real extension (installed shape, Pi's jiti) or the hooks module, real guard scripts, temp HOME and
temp projects. Every shell fixture is inert even if a guard failed: it only touches marker files
inside the temp project. Overridden scripts live in a temp skill copy made of symlinks.
"""

import hashlib
import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "tests/fixtures/pi_native_hooks_host.mjs"
PLAN = "# Plan: sample\n\n<!-- mb-stage:1 -->\n### Stage 1: First step\n\n- [ ] do it\n"


def _bank(proj: Path, protected=("guarded/**", ".env*")) -> Path:
    mb = proj / ".memory-bank"
    (mb / "plans" / "done").mkdir(parents=True)
    (mb / "specs").mkdir()
    for name in ("checklist", "roadmap", "status"):
        (mb / f"{name}.md").write_text(f"# {name}\n")
    globs = "".join(f'  - "{g}"\n' for g in protected)
    (mb / "pipeline.yaml").write_text(f"protected_paths:\n{globs}")
    (proj / "src").mkdir()
    (proj / "guarded").mkdir()
    (proj / "guarded" / "keep.txt").write_text("original\n")
    return mb


def _digest(path: Path) -> str:
    h = hashlib.sha256()
    for f in sorted(p for p in path.rglob("*") if p.is_file()):
        h.update(str(f.relative_to(path)).encode())
        h.update(f.read_bytes())
    return h.hexdigest()


@pytest.fixture
def world(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    env.update({"HOME": str(home), "MB_UPDATE_CHECK": "off", "MB_GRAPH_CATCHUP": "off"})
    a, b = tmp_path / "alpha", tmp_path / "beta"
    _bank(a)
    _bank(b, protected=(".env*",))
    return {"tmp": tmp_path, "home": home, "env": env, "a": a, "b": b}


def stub_skill(world, overrides: dict) -> Path:
    """Skill copy of symlinks; `overrides` replaces scripts by relative path (None = absent)."""
    skill = world["tmp"] / "skill"
    skill.mkdir()
    for name in ("SKILL.md", "VERSION", "adapters", "references", "memory_bank_skill", "rules"):
        (skill / name).symlink_to(ROOT / name)
    for sub in ("scripts", "hooks"):
        (skill / sub).mkdir()
        for entry in (ROOT / sub).iterdir():
            (skill / sub / entry.name).symlink_to(entry)
    for rel, text in overrides.items():
        (skill / rel).unlink()
        if text is not None:
            (skill / rel).write_text(text)
            (skill / rel).chmod(0o755)
    return skill


def run(world, steps, skill=None, mode="ext", timeout_ms=None):
    payload = {"home": str(world["home"]), "mode": mode, "steps": steps}
    if skill:
        payload["skillDir"] = str(skill)
    if timeout_ms:
        payload["timeoutMs"] = timeout_ms
    proc = subprocess.run(
        ["node", str(HOST)],
        cwd=ROOT,
        env=world["env"],
        text=True,
        capture_output=True,
        timeout=120,
        input=json.dumps(payload),
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip().splitlines()[-1])


def tool(name, cwd, fail=False, **params):
    return {"tool": name, "cwd": str(cwd), "input": params, "fail": fail}


def test_extension_registers_guard_and_sync_hooks(world):
    head = run(world, [])[0]
    assert {"tool_call", "tool_result"} <= set(head["events"])


def test_write_and_edit_to_protected_path_blocked_before_mutation(world):
    a, b = world["a"], world["b"]
    out = run(
        world,
        [
            tool("write", a, path="guarded/new.txt", content="x"),
            tool("write", a, path=".env", content="SECRET=1"),
            tool(
                "edit",
                a,
                path="guarded/keep.txt",
                edits=[{"oldText": "original", "newText": "pwned"}],
            ),
            # The current bank decides: beta's pipeline does not protect guarded/**.
            tool("write", b, path="guarded/new.txt", content="beta may"),
        ],
    )
    for r in out[1:4]:
        assert r["blocked"] and not r["executed"], r
        assert "protected" in r["reason"].lower(), r
    assert not (a / "guarded/new.txt").exists() and not (a / ".env").exists()
    assert (a / "guarded/keep.txt").read_text() == "original\n"
    assert out[4]["executed"] and (b / "guarded/new.txt").read_text() == "beta may"


def test_canonical_and_relative_paths_are_resolved_before_the_check(world):
    a = world["a"]
    (a / "link").symlink_to(a / "guarded")
    out = run(
        world,
        [
            tool("write", a, path=str(a / "guarded/abs.txt"), content="x"),
            tool("write", a, path="./src/../guarded/dots.txt", content="x"),
            tool("write", a, path="link/via-symlink.txt", content="x"),
            tool("write", a, path="@guarded/at.txt", content="x"),
            tool("write", a / "src", path="../guarded/from-subdir.txt", content="x"),
        ],
    )
    for r in out[1:6]:
        assert r["blocked"] and not r["executed"], r
    assert sorted(p.name for p in (a / "guarded").iterdir()) == ["keep.txt"]


def test_safe_read_and_ordinary_write_and_bash_are_allowed(world):
    a = world["a"]
    out = run(
        world,
        [
            tool("read", a, path="guarded/keep.txt"),
            tool("write", a, path="src/ok.py", content="x = 1\n"),
            tool("bash", a, command="touch SAFE_RAN"),
        ],
    )
    assert [r["executed"] for r in out[1:4]] == [True, True, True], out
    assert (a / "src/ok.py").exists() and (a / "SAFE_RAN").exists()


def test_dangerous_shell_fixture_never_executes(world):
    a = world["a"]
    out = run(
        world,
        [
            tool("bash", a, command="touch RAN_DROP; echo 'DROP TABLE users' > /dev/null"),
            tool("bash", a, command="touch RAN_NOVERIFY; echo git commit --no-verify > /dev/null"),
            tool("bash", a, command="touch RAN_PROTECTED; echo x > .env.local"),
        ],
    )
    for r in out[1:4]:
        assert r["blocked"] and not r["executed"], r
    assert "DROP" in out[1]["reason"] and "no-verify" in out[2]["reason"]
    assert not list(a.glob("RAN_*")) and not (a / ".env.local").exists()


@pytest.mark.parametrize(
    "bad",
    [
        tool("write", "{cwd}"),
        tool("write", "{cwd}", path=42, content="x"),
        tool("edit", "{cwd}", path="", edits=[]),
        tool("bash", "{cwd}", command=None),
    ],
    ids=["write-no-path", "write-non-string-path", "edit-empty-path", "bash-no-command"],
)
def test_malformed_mutating_input_is_blocked(world, bad):
    bad = {**bad, "cwd": str(world["a"])}
    out = run(world, [bad, tool("read", world["a"])])
    assert out[1]["blocked"] and "malformed" in out[1]["reason"].lower(), out[1]
    assert out[2]["executed"], "non-mutating tools are not guarded"


def test_guard_crash_fails_closed_with_bounded_diagnostic(world):
    skill = stub_skill(
        world, {"hooks/block-dangerous.sh": "#!/bin/bash\nyes crash | head -c 100000 >&2\nexit 1\n"}
    )
    out = run(world, [tool("bash", world["a"], command="touch RAN")], skill=skill)
    assert out[1]["blocked"] and len(out[1]["reason"]) < 4000, out[1]
    assert not (world["a"] / "RAN").exists()


def test_hanging_guard_is_bounded_by_timeout_and_cancellation(world):
    skill = stub_skill(world, {"hooks/block-dangerous.sh": "#!/bin/bash\nsleep 30\n"})
    a = world["a"]
    timed = run(
        world, [tool("bash", a, command="touch RAN")], skill=skill, mode="module", timeout_ms=500
    )
    assert timed[1]["blocked"] and "timed out" in timed[1]["reason"] and timed[1]["ms"] < 5000, (
        timed
    )
    step = {**tool("bash", a, command="touch RAN"), "abortAfterMs": 300}
    cancelled = run(world, [step], skill=skill)
    assert cancelled[1]["blocked"] and "cancelled" in cancelled[1]["reason"], cancelled
    assert cancelled[1]["ms"] < 5000 and not (a / "RAN").exists()


def _sync_logger(world) -> tuple[Path, Path]:
    log = world["tmp"] / "plan-sync.log"
    real = ROOT / "scripts/mb-plan-sync.sh"
    script = f'#!/bin/bash\necho "$1|${{2:-}}|${{MB_PATH:-}}" >> "{log}"\nexec bash "{real}" "$@"\n'
    return stub_skill(world, {"scripts/mb-plan-sync.sh": script}), log


def test_scoped_plan_write_syncs_once_with_current_bank_and_no_recursion(world):
    skill, log = _sync_logger(world)
    a, b = world["a"], world["b"]
    before_b = _digest(b)
    out = run(
        world,
        [
            tool(
                "write",
                a / "src",
                path="../.memory-bank/plans/2026-10-08_feature_sample.md",
                content=PLAN,
            )
        ],
        skill=skill,
    )
    assert out[1]["executed"], out
    plan = (a / ".memory-bank/plans/2026-10-08_feature_sample.md").resolve()
    bank = (a / ".memory-bank").resolve()
    lines = log.read_text().splitlines()
    assert len(lines) == 1, lines
    path, bank_arg, mb_env = lines[0].split("|")
    assert (
        Path(path).resolve() == plan
        and Path(bank_arg).resolve() == bank
        and Path(mb_env).resolve() == bank
    )
    assert "First step" in (a / ".memory-bank/checklist.md").read_text()
    # plan-sync rewrote bank files, yet the host saw exactly one tool lifecycle.
    assert out[-1]["counts"] == {"tool_call": 1, "tool_result": 1}
    assert _digest(b) == before_b


def test_failed_and_unrelated_writes_do_not_sync(world):
    skill, log = _sync_logger(world)
    a, b = world["a"], world["b"]
    (a / "notes/plans").mkdir(parents=True)
    out = run(
        world,
        [
            tool(
                "write", a, fail=True, path=".memory-bank/plans/2026-10-08_failed.md", content=PLAN
            ),
            tool("write", a, path="src/app.py", content="x = 1\n"),
            tool("write", a, path="notes/plans/look-alike.md", content=PLAN),
            tool("write", a, path=".memory-bank/plans/done/2026-01-01_archived.md", content=PLAN),
            tool("write", a, path=str(b / ".memory-bank/plans/2026-10-08_other.md"), content=PLAN),
        ],
        skill=skill,
    )
    assert all(r["ok"] for r in out[1:6]), out
    assert not log.exists() or log.read_text() == ""
    assert "First step" not in (a / ".memory-bank/checklist.md").read_text()
    assert "First step" not in (b / ".memory-bank/checklist.md").read_text()


def test_plan_sync_failure_keeps_tool_result_with_bounded_diagnostic(world):
    noisy = "#!/bin/bash\nyes boom | head -c 100000 >&2\nexit 1\n"
    skill = stub_skill(world, {"scripts/mb-plan-sync.sh": noisy})
    out = run(
        world,
        [tool("write", world["a"], path=".memory-bank/plans/2026-10-08_x.md", content=PLAN)],
        skill=skill,
    )
    r = out[1]
    assert r["ok"] and r["executed"], r
    assert r["text"].startswith("tool output") and "plan-sync failed" in r["text"]
    assert len(r["text"]) < 4000


def test_optional_nudge_and_catchup_failures_never_break_user_tools(world):
    a = world["a"]
    (a / ".memory-bank/codebase").mkdir()
    (a / ".memory-bank/codebase/graph.json").write_text("{}")
    broken = "#!/bin/bash\necho not-json\nexit 3\n"
    skill = stub_skill(
        world, {"hooks/mb-graph-nudge.sh": broken, "scripts/mb-graph-query.py": broken}
    )
    world["env"].pop("MB_GRAPH_CATCHUP")
    out = run(
        world,
        [
            {"emit": "session_start", "cwd": str(a), "event": {"reason": "startup"}},
            {**tool("bash", a, command="grep -rn foo src || true"), "output": "grep output"},
            {"emit": "session_compact", "cwd": str(a), "event": {}},
        ],
        skill=skill,
    )
    assert all(r["ok"] for r in out[1:4]), out
    assert out[2]["executed"] and out[2]["text"] == "grep output"
