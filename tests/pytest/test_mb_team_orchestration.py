"""MB Team orchestration guard rails: follow-up tracks, console automation, the orchestrator
guard hook, the track Workflow script and its args, the codex reviewer model, the agree cap."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
GUARD = ROOT / "hooks" / "mb-team-guard.py"
WORKFLOW = ROOT / "workflows" / "mb-team-track.js"


def _env(tmp_path: Path, **extra: str) -> dict:
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    env.update(MB_LOCK_DIR=str(tmp_path / "locks"), **extra)
    return env


def _bank(tmp_path: Path) -> Path:
    proj = tmp_path / "proj"
    bank = proj / ".memory-bank"
    bank.mkdir(parents=True)
    (bank / "COORDINATION.md").write_text("# Coordination board\n", encoding="utf-8")
    (bank / "progress.md").write_text("# Progress\n", encoding="utf-8")
    (proj / "f").mkdir()
    (proj / "f" / "x.txt").write_text("base\n", encoding="utf-8")
    git = ["git", "-C", str(proj), "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run(["git", "init", "-q", str(proj)], check=True)
    subprocess.run([*git, "add", "-A"], check=True)
    subprocess.run([*git, "commit", "-qm", "init"], check=True)
    return bank


def _team(tmp_path: Path, bank: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(SCRIPTS / "mb-team.sh"), "--mb", str(bank), *args],
        capture_output=True,
        text=True,
        cwd=bank.parent,
        env=_env(tmp_path),
    )


def _ok(r: subprocess.CompletedProcess) -> subprocess.CompletedProcess:
    assert r.returncode == 0, r.stdout + r.stderr
    return r


def _team_json(bank: Path, topic: str = "demo") -> dict:
    return json.loads((bank / "reports" / topic / "team.json").read_text(encoding="utf-8"))


def _demo(tmp_path: Path) -> Path:
    bank = _bank(tmp_path)
    _ok(_team(tmp_path, bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)))
    _ok(
        _team(
            tmp_path,
            bank,
            "track",
            "add",
            "A",
            "--task",
            "task A",
            "--dod",
            "a test proves it",
            "--files",
            "f/**",
            "--size",
            "standard",
        )
    )
    return bank


# ---- 6. built-in console lock resource -------------------------------------------------------


def test_console_resource_is_builtin_and_bank_scoped(tmp_path):
    bank = _bank(tmp_path)
    r = _ok(
        subprocess.run(
            [
                sys.executable,
                str(SCRIPTS / "mb_team_config.py"),
                "resource",
                "console",
                "--mb",
                str(bank),
            ],
            capture_output=True,
            text=True,
            env=_env(tmp_path),
        )
    )
    res = json.loads(r.stdout)
    assert res["scope"] == "bank" and res["path"] == str(bank / ".locks" / "res" / "console")


def test_track_may_declare_the_console_resource_without_team_resources(tmp_path):
    bank = _demo(tmp_path)
    _ok(
        _team(
            tmp_path,
            bank,
            "track",
            "add",
            "B",
            "--task",
            "t",
            "--dod",
            "d",
            "--files",
            "g/**",
            "--resources",
            "console",
        )
    )


# ---- 4. console automation --------------------------------------------------------------------


def test_track_set_writes_the_track_console_line_in_place_and_posts_the_note(tmp_path):
    bank = _demo(tmp_path)
    _ok(
        _team(
            tmp_path,
            bank,
            "track",
            "set",
            "A",
            "--status",
            "dispatched",
            "--note",
            "executor started",
        )
    )
    _ok(
        _team(
            tmp_path, bank, "track", "set", "A", "--status", "returned", "--note", "12 tests green"
        )
    )
    _ok(_team(tmp_path, bank, "track", "set", "A", "--note", "verifier PASS"))
    console = (bank / "orchestrator-console.md").read_text(encoding="utf-8")
    lines = [ln for ln in console.splitlines() if ln.startswith("- A [")]
    assert len(lines) == 1 and "returned" in lines[0] and "verifier PASS" in lines[0]
    assert "## Tracks" in console
    board = (bank / "COORDINATION.md").read_text(encoding="utf-8")
    assert "A returned: 12 tests green" in board and "A note: verifier PASS" in board
    assert _team_json(bank)["tracks"][0]["status"] == "returned"


def test_console_check_enforces_the_line_cap(tmp_path):
    bank = _bank(tmp_path)
    console = bank / "orchestrator-console.md"
    console.write_text("# c\n" + "- x\n" * 39, encoding="utf-8")
    cmd = ["bash", str(SCRIPTS / "mb-console.sh"), "check", "--mb", str(bank)]
    _ok(subprocess.run(cmd, capture_output=True, text=True, env=_env(tmp_path)))
    console.write_text("# c\n" + "- x\n" * 45, encoding="utf-8")
    r = subprocess.run(cmd, capture_output=True, text=True, env=_env(tmp_path))
    assert r.returncode == 1 and "46" in r.stderr and "progress.md" in r.stderr


# ---- 2. follow-up tracks ----------------------------------------------------------------------


def _finish(tmp_path, bank, tid):
    for s in ("dispatched", "returned", "done"):
        _ok(_team(tmp_path, bank, "--topic", "demo", "track", "set", tid, "--status", s))


def test_track_set_same_status_books_without_a_transition(tmp_path):
    bank = _demo(tmp_path)
    for st_ in ("dispatched", "returned", "fixing"):
        _ok(_team(tmp_path, bank, "track", "set", "A", "--status", st_))
    _ok(_team(tmp_path, bank, "track", "set", "A", "--status", "fixing", "--note", "fix stage started"))
    track = _team_json(bank)["tracks"][0]
    assert track["status"] == "fixing" and track["fix_cycle"] == 1
    assert "A fixing: fix stage started" in (bank / "COORDINATION.md").read_text(encoding="utf-8")


def test_followup_track_reopens_a_closed_team_and_commits_through_team_commit(tmp_path):
    bank = _demo(tmp_path)
    _finish(tmp_path, bank, "A")
    _ok(_team(tmp_path, bank, "close"))
    refused = _team(
        tmp_path,
        bank,
        "--topic",
        "demo",
        "track",
        "add",
        "F",
        "--task",
        "fix",
        "--dod",
        "d",
        "--files",
        "f/**",
    )
    assert refused.returncode == 2 and "--followup" in refused.stderr
    _ok(
        _team(
            tmp_path,
            bank,
            "track",
            "add",
            "F",
            "--followup",
            "--task",
            "fix it",
            "--dod",
            "d",
            "--files",
            "f/**",
            "--size",
            "small",
        )
    )
    team = _team_json(bank)
    assert team["closed"] is False and team["tracks"][-1]["followup"] is True
    assert "reopened for follow-up F" in (bank / "COORDINATION.md").read_text(encoding="utf-8")
    (bank.parent / "f" / "x.txt").write_text("fixed\n", encoding="utf-8")
    _finish(tmp_path, bank, "F")
    _ok(_team(tmp_path, bank, "commit", "--tracks", "F", "-m", "fix: follow-up F", "--yes"))
    log = subprocess.run(
        ["git", "-C", str(bank.parent), "log", "-1", "--name-only", "--format=%s"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "fix: follow-up F" in log and "f/x.txt" in log


# ---- 3 / 4 / 5. orchestrator guard hook -------------------------------------------------------


def _hook(tmp_path: Path, payload, **env: str) -> subprocess.CompletedProcess:
    data = payload if isinstance(payload, str) else json.dumps(payload)
    return subprocess.run(
        [sys.executable, str(GUARD)],
        input=data,
        capture_output=True,
        text=True,
        env=_env(tmp_path, **env),
        timeout=30,
    )


def _register(tmp_path: Path, bank: Path, sid: str = "S1") -> None:
    r = _hook(
        tmp_path,
        {
            "hook_event_name": "PreToolUse",
            "session_id": sid,
            "cwd": str(bank.parent),
            "tool_name": "Bash",
            "tool_input": {"command": f"bash mb-team.sh --mb '{bank}' next"},
        },
    )
    assert r.returncode == 0 and r.stdout.strip() in ("", "{}"), r.stdout + r.stderr


def _edit(bank: Path, path: Path, sid: str = "S1", **extra) -> dict:
    return {
        "hook_event_name": "PreToolUse",
        "session_id": sid,
        "cwd": str(bank.parent),
        "tool_name": "Edit",
        "tool_input": {"file_path": str(path), "old_string": "a", "new_string": "b"},
        **extra,
    }


def _decision(r: subprocess.CompletedProcess) -> str:
    assert r.returncode == 0, r.stderr
    out = r.stdout.strip()
    return (
        json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out not in ("", "{}") else ""
    )


def test_guard_denies_orchestrator_code_edits_and_allows_bank_subagents_and_others(tmp_path):
    bank = _demo(tmp_path)
    code = bank.parent / "f" / "x.txt"
    assert _decision(_hook(tmp_path, _edit(bank, code))) == ""  # not an orchestrator yet
    _register(tmp_path, bank)
    denied = _hook(tmp_path, _edit(bank, code))
    assert _decision(denied) == "deny" and "delegate this as a track" in denied.stdout
    assert _decision(_hook(tmp_path, _edit(bank, bank / "orchestrator-console.md"))) == ""
    assert _decision(_hook(tmp_path, _edit(bank, code, agent_id="sub-1"))) == ""
    assert _decision(_hook(tmp_path, _edit(bank, tmp_path / "elsewhere.txt"))) == ""
    assert _decision(_hook(tmp_path, _edit(bank, code, sid="S2"))) == ""
    assert _decision(_hook(tmp_path, _edit(bank, code), MB_TEAM_GUARD="off")) == ""
    (bank / ".mb-config").write_text("team_guard=off\n", encoding="utf-8")
    assert _decision(_hook(tmp_path, _edit(bank, code))) == ""


def test_guard_explicit_orchestrator_flag_and_fail_open(tmp_path):
    bank = _demo(tmp_path)
    code = bank.parent / "f" / "x.txt"
    assert _decision(_hook(tmp_path, _edit(bank, code, sid="S9"), MB_ORCHESTRATOR="1")) == "deny"
    for junk in ("", "not json", "[]", json.dumps({"tool_name": "Edit"})):
        r = _hook(tmp_path, junk)
        assert r.returncode == 0 and r.stdout.strip() in ("", "{}")


def test_guard_points_git_commit_to_team_commit_once_per_command(tmp_path):
    bank = _demo(tmp_path)
    _register(tmp_path, bank)
    commit = {
        "hook_event_name": "PreToolUse",
        "session_id": "S1",
        "cwd": str(bank.parent),
        "tool_name": "Bash",
        "tool_input": {"command": "git -C . commit -m 'x' -- f/x.txt"},
    }
    first = _hook(tmp_path, commit)
    assert _decision(first) == "deny"
    assert "team commit" in first.stdout and "FREEZE (active)" in first.stdout
    assert _decision(_hook(tmp_path, commit)) == ""  # the same command again passes
    other = {**commit, "session_id": "S2"}
    assert _decision(_hook(tmp_path, other)) == ""


def test_guard_stop_reminds_once_when_the_console_is_stale(tmp_path):
    bank = _demo(tmp_path)
    _register(tmp_path, bank)
    console = bank / "orchestrator-console.md"
    console.write_text("# console\n", encoding="utf-8")
    old = time.time() - 600
    os.utime(console, (old, old))
    stop = {
        "hook_event_name": "Stop",
        "session_id": "S1",
        "cwd": str(bank.parent),
        "stop_hook_active": False,
    }
    first = _hook(tmp_path, stop)
    assert first.returncode == 0 and json.loads(first.stdout)["decision"] == "block"
    assert "orchestrator-console.md" in json.loads(first.stdout)["reason"]
    assert _hook(tmp_path, stop).stdout.strip() == ""  # once per change
    assert _hook(tmp_path, {**stop, "stop_hook_active": True}).stdout.strip() == ""
    assert _hook(tmp_path, {**stop, "session_id": "S2"}).stdout.strip() == ""


def test_guard_is_registered_for_claude_code():
    hooks = json.loads((ROOT / "settings" / "hooks.json").read_text(encoding="utf-8"))
    pre = [
        h["command"]
        for e in hooks["PreToolUse"]
        for h in e["hooks"]
        if "mb-team-guard.py" in h["command"]
        for _ in [e]
        if "Edit" in e["matcher"] and "Bash" in e["matcher"]
    ]
    stop = [
        h["command"]
        for e in hooks["Stop"]
        for h in e["hooks"]
        if "mb-team-guard.py" in h["command"]
    ]
    assert pre and stop
    assert os.access(GUARD, os.X_OK)


# ---- 1. track Workflow ------------------------------------------------------------------------


def test_workflow_args_resolve_models_reviewer_command_and_paths(tmp_path):
    bank = _demo(tmp_path)
    args = json.loads(_ok(_team(tmp_path, bank, "workflow-args", "--tracks", "A")).stdout)
    assert args["bank"] == str(bank) and args["tree"] == str(bank.parent.resolve())
    assert args["skill"] == str(ROOT) and args["topic"] == "demo"
    t = args["tracks"][0]
    assert t["id"] == "A" and t["start"] == "execute" and t["agent"] == "mb-developer"
    assert t["verifier"]["agent"] == "plan-verifier" and t["verifier"]["effort"]
    assert args["judge"]["agent"] == "mb-judge" and args["judge"]["model"]
    rv = args["review"]
    assert rv["max_rounds"] == 2 and Path(rv["template"]).is_file()
    assert "codex exec" in rv["command"] and str(bank.parent.resolve()) in rv["command"]
    assert (
        "{prompt}" in rv["command"] and "{out}" in rv["command"] and "{model}" not in rv["command"]
    )
    assert rv["model"] in rv["command"]


_DRIVER = r"""
const fs = require('fs');
const src = fs.readFileSync(process.argv[1], 'utf8').replace('export const meta', 'const meta');
const AsyncFunction = (async () => {}).constructor;
const strict = process.argv[3] === 'strict';  // every round requests changes
const calls = [];
let round = 0;
const agent = async (prompt, opts) => {
  calls.push({label: opts.label, prompt, schema: opts.schema});
  const p = opts.label.split(':')[0];
  if (p === 'exec' || p === 'fix') return {status: 'DONE', summary: 'ok'};
  if (p === 'verify') return {pass: true, issues: []};
  if (p.startsWith('review')) { round++; return round === 1 || strict
      ? {verdict: 'CHANGES_REQUESTED', file: '/r' + round, findings: [{severity: 'major', text: 'bug'}]}
      : {verdict: 'APPROVED', file: '/r2', findings: []}; }
  if (p === 'triage') return {fix: ['bug at x:1'], accept: []};
  if (p === 'judge') return {decision: 'GO', rationale: 'ok', blocking: [], backlog: ['b1'], commit_paths: ['f/x.txt'],
                             orchestrator_checks: ['count rows in the live db']};
  throw new Error('unexpected agent ' + opts.label);
};
const parallel = async (thunks) => Promise.all(thunks.map((t) => t()));
const args = JSON.parse(process.argv[2]);
new AsyncFunction('args', 'agent', 'parallel', 'pipeline', 'log', 'phase', src)(args, agent, parallel, null, () => {}, () => {})
  .then((res) => console.log(JSON.stringify({res, calls})));
"""
_WF_ARGS = {
    "topic": "demo", "bank": "/b", "tree": "/t", "skill": "/s",
    "team": "bash /s/scripts/mb-team.sh --mb /b --topic demo",
    "review": {"command": "codex exec -C /t < {prompt} > {out}", "max_rounds": 2,
               "template": "/s/workflows/r.md", "model": "m-x", "effort": "high"},
    "judge": {"agent": "mb-judge", "model": "opus", "effort": "xhigh"},
    "triage": {"model": "opus", "effort": "high"},
    "tracks": [{"id": "A", "start": "execute", "agent": "mb-developer", "model": "opus", "effort": "medium",
                "review": True, "verifier": {"agent": "plan-verifier", "model": "opus", "effort": "high"},
                "prompt": "/b/reports/demo/tracks/A.prompt.md", "report": "/b/reports/demo/A.md"}],
}


def _run_workflow(mode: str = "") -> dict:
    assert shutil.which("node"), "node runs the workflow script (CI installs it for the OpenCode tests)"
    r = subprocess.run(["node", "-e", _DRIVER, str(WORKFLOW), json.dumps(_WF_ARGS), mode],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def test_workflow_script_is_portable_and_runs_the_full_track_loop():
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "/Users/" not in text and "hermes" not in text and "gpt-" not in text
    out = _run_workflow()
    labels = [c["label"].split(":")[0] for c in out["calls"]]
    assert labels == ["exec", "verify", "review-r1", "triage", "fix", "review-r2", "judge"]
    joined = "\n".join(c["prompt"] for c in out["calls"])
    assert "bash /s/scripts/mb-team.sh --mb /b --topic demo track set A" in joined
    assert (
        "codex exec -C /t < /b/reports/demo/A-review/round1.prompt.md > /b/reports/demo/A-review/round1.out.md"
        in joined
    )
    assert "unreviewed" not in out["calls"][-1]["prompt"]


def test_workflow_returns_a_short_summary_with_orchestrator_checks():
    out = _run_workflow()
    assert out["res"] == [{"id": "A", "decision": "GO", "commit_paths": ["f/x.txt"], "blocking": [],
                           "backlog": ["b1"], "orchestrator_checks": ["count rows in the live db"],
                           "reviews": ["CHANGES_REQUESTED", "APPROVED"], "unreviewed_fix": False}]
    judge_schema = out["calls"][-1]["schema"]
    assert "orchestrator_checks" in judge_schema["required"]


def test_workflow_judge_reviews_a_fix_made_after_the_last_round():
    out = _run_workflow("strict")
    labels = [c["label"].split(":")[0] for c in out["calls"]]
    assert labels == ["exec", "verify", "review-r1", "triage", "fix", "review-r2", "triage", "fix", "judge"]
    judge = out["calls"][-1]["prompt"]
    assert "unreviewed" in judge and "round2.diff" in judge
    assert out["res"][0]["unreviewed_fix"] is True


def test_team_command_runs_the_track_loop_through_the_workflow_script():
    text = (ROOT / "commands" / "team.md").read_text(encoding="utf-8")
    assert "workflows/mb-team-track.js" in text and "Workflow" in text and "workflow-args" in text
    install = (ROOT / "install.sh").read_text(encoding="utf-8")
    assert "workflows/mb-team-track.js" in install and ".claude/workflows" in install


# ---- 6. codex reviewer model from pipeline.yaml ------------------------------------------------


def test_external_reviewer_model_comes_from_the_pipeline(tmp_path):
    bank = _bank(tmp_path)
    cmd = ["bash", str(SCRIPTS / "mb-reviewer-resolve.sh"), "--external", "--mb", str(bank)]
    default = json.loads(
        _ok(subprocess.run(cmd, capture_output=True, text=True, env=_env(tmp_path))).stdout
    )
    assert default["model"] == "gpt-6-astra" and default["effort"] == "high"
    (bank / "pipeline.yaml").write_text(
        "version: 1\nmodel_profiles:\n  codex: {premium: gpt-6.2-astra, mid: gpt-6.1-sol}\n",
        encoding="utf-8",
    )
    assert (
        json.loads(
            _ok(subprocess.run(cmd, capture_output=True, text=True, env=_env(tmp_path))).stdout
        )["model"]
        == "gpt-6.2-astra"
    )
    agent = (ROOT / "agents" / "codex-reviewer.md").read_text(encoding="utf-8")
    assert (
        "mb-reviewer-resolve.sh" in agent and "--external" in agent and "gpt-5.6-sol" not in agent
    )


# ---- 6. agreements cap -----------------------------------------------------------------------


def test_agree_list_suggests_consolidation_above_the_cap(tmp_path):
    bank = _bank(tmp_path)
    rows = "".join(f"- AGR-{i:03d}: decision {i} [2026-11-01]\n" for i in range(1, 27))
    (bank / "agreements.md").write_text(
        f"# Agreements\n\n## Active\n{rows}\n## Open questions\n\n## Archive\n", encoding="utf-8"
    )
    r = _ok(
        subprocess.run(
            ["bash", str(SCRIPTS / "mb-agree.sh"), "list", "--mb", str(bank)],
            capture_output=True,
            text=True,
            env=_env(tmp_path),
            cwd=bank.parent,
        )
    )
    assert "AGR-026" in r.stdout
    assert "26 active" in r.stderr and "consolidate" in r.stderr and "--supersedes" in r.stderr


def test_guard_never_writes_state_through_a_symlinked_state_dir(tmp_path):
    bank = _demo(tmp_path)
    victim = tmp_path / "victim"
    victim.mkdir()
    (tmp_path / "locks").mkdir(mode=0o700)
    (tmp_path / "locks" / "team-guard").symlink_to(victim)
    _register(tmp_path, bank)
    assert list(victim.iterdir()) == []
    assert _decision(_hook(tmp_path, _edit(bank, bank.parent / "f" / "x.txt"))) == ""


def test_track_set_add_files_widens_globs_for_team_commit_and_refuses_overlap(tmp_path):
    bank = _demo(tmp_path)
    _ok(_team(tmp_path, bank, "track", "add", "B", "--task", "t", "--dod", "d", "--files", "lib/b/**"))
    (bank.parent / "shared").mkdir()
    (bank.parent / "shared" / "helper.py").write_text("fixed\n", encoding="utf-8")
    refused = _team(tmp_path, bank, "track", "set", "A", "--add-files", "lib/**")
    assert refused.returncode == 2 and "B" in refused.stderr
    _ok(_team(tmp_path, bank, "track", "set", "A", "--add-files", "shared/helper.py"))
    assert _team_json(bank)["tracks"][0]["files"] == ["f/**", "shared/helper.py"]
    _finish(tmp_path, bank, "A")
    _ok(_team(tmp_path, bank, "commit", "--tracks", "A", "-m", "fix: shared helper", "--yes"))
    log = subprocess.run(["git", "-C", str(bank.parent), "log", "-1", "--name-only", "--format=%s"],
                         capture_output=True, text=True, check=True).stdout
    assert "shared/helper.py" in log
