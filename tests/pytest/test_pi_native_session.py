"""Pi session memory contracts: real extension, real scripts, real filesystem, temp HOME."""

import json
import os
import re
import subprocess
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "tests/fixtures/pi_native_session_host.mjs"
LOAD = {"op": "load"}
RESTORE = "mb-session-restore"
HANDOFF = "mb-handoff-restore"


def run(tmp_path, steps, env=None, branches=None, expect_kill=False):
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir(exist_ok=True)
    for cli in ["claude", "pi", "codex"]:
        tool = fake_bin / cli
        tool.write_text(f'#!/usr/bin/env bash\necho {cli} >> "{tmp_path}/cli-calls"\n')
        tool.chmod(0o755)
    full_env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "MB_UPDATE_CHECK": "off",
        "MB_PRECOMPACT_BUDGET": "20",
    }
    for name in [
        "MB_PATH",
        "MB_SESSION_CAPTURE",
        "MB_AUTOLOAD_CONTEXT",
        "MB_SUMMARY_BACKEND",
        "MB_SUMMARIZE_BIN",
        "MB_INDEX_DIR",
        "MB_PRECOMPACT_HANDOFF",
        "MB_SESSION_LLM_TIMEOUT",
    ]:
        full_env.pop(name, None)
    full_env.update(env or {})
    proc = subprocess.run(
        ["node", str(HOST)],
        cwd=ROOT,
        env=full_env,
        text=True,
        capture_output=True,
        input=json.dumps({"home": str(home), "steps": steps, "branches": branches or {}}),
        timeout=120,
    )
    if expect_kill:
        assert proc.returncode == -9, proc.stderr
        return None
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout.strip().splitlines()[-1])
    assert not [r for r in out["results"] if r.get("error")], out["results"]
    return out


def sess(sid, cwd):
    return {"id": sid, "cwd": str(cwd)}


def ev(event, s, rt="r1", wait=True, **payload):
    return {"op": "emit", "event": event, "session": s, "rt": rt, "wait": wait, "payload": payload}


def turn(s, text, rt="r1", path="src/app.py"):
    return [
        ev("input", s, rt, text=text, source="interactive"),
        ev("before_agent_start", s, rt, prompt=text),
        ev("tool_execution_start", s, rt, toolCallId="t1", toolName="edit", args={"path": path}),
        ev("tool_execution_end", s, rt, toolCallId="t1", toolName="edit", isError=False, result={}),
        ev("agent_end", s, rt, messages=[]),
    ]


def project(tmp_path, name, recent=None):
    cwd = tmp_path / name
    mb = cwd / ".memory-bank"
    (mb / "session").mkdir(parents=True)
    (mb / "status.md").write_text(f"# status\n{name.upper()}_STATUS\n")
    if recent:
        (mb / "session/_recent.md").write_text(
            f"## 2026-01-01 10:00 (main) — feedface\n{recent}\n\n"
        )
    return cwd, mb


def session_files(mb):
    return sorted(p for p in (mb / "session").glob("*.md") if p.name != "_recent.md")


def injected(out, custom_type):
    return [
        v["message"]["content"]
        for r in out["results"]
        if r["event"] == "before_agent_start"
        for v in r["values"]
        if v.get("message", {}).get("customType") == custom_type
    ]


def fm(text, key):
    head = text.split("\n---", 1)[0]
    match = re.search(rf"^{key}: ?(.*)$", head, re.M)
    return match.group(1) if match else None


def test_session_in_bank_records_one_header_one_turn_and_finalizes_summary(tmp_path):
    a, mb = project(tmp_path, "a")
    b, mb_b = project(tmp_path, "b")
    s = sess("0198c0de-aaaa-4c1d-9e8f-000000000001", a)
    run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "fix the upload test"),
            ev("input", s, text="ROUTER TEXT", source="extension"),
            ev("session_shutdown", s, reason="quit"),
        ],
    )
    [sf] = session_files(mb)
    text = sf.read_text()
    assert text.count("session_id:") == 1 and fm(text, "session_id") == s["id"]
    assert (
        fm(text, "agent") == "pi"
        and fm(text, "turns") == "1"
        and fm(text, "last_turn") == "pi-turn-1"
    )
    assert text.count("Turn 1: completed") == 1
    assert 'User: "fix the upload test"' in text and "ROUTER TEXT" not in text
    assert "Files: src/app.py" in text
    assert fm(text, "ended") and fm(text, "summary_mode") == "deterministic"
    assert fm(text, "summarized") == "false", "a deterministic summary is not an LLM summary"
    summary = text.split("## Summary\n", 1)[1]
    assert (
        summary.index("### What changed")
        < summary.index("### Decisions")
        < summary.index("### Files")
    )
    assert (
        "deterministic" in summary and "fix the upload test" in summary and "src/app.py" in summary
    )
    recent = (mb / "session/_recent.md").read_text()
    assert "0198c0de" in recent and "fix the upload test" in recent
    assert not session_files(mb_b)
    assert not (tmp_path / "cli-calls").exists(), "no fallback CLI is invoked by default"


def test_session_started_in_project_subfolder_records_into_project_bank(tmp_path):
    a, mb = project(tmp_path, "a")
    deep = a / "src" / "deep"
    deep.mkdir(parents=True)
    s = sess("0198c0de-dddd-4c1d-9e8f-000000000009", deep)
    run(
        tmp_path,
        [LOAD, ev("session_start", s, reason="startup"), *turn(s, "work from a subfolder")],
    )
    [sf] = session_files(mb)
    assert fm(sf.read_text(), "session_id") == s["id"]
    assert not (deep / ".memory-bank").exists()


def test_start_reload_resume_continue_same_file_without_duplicate_ids(tmp_path):
    a, mb = project(tmp_path, "a")
    s = sess("0198c0de-bbbb-4c1d-9e8f-000000000002", a)
    run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "first request"),
            ev("session_shutdown", s, reason="reload"),
            {"op": "load", "rt": "r2"},
            ev("session_start", s, "r2", reason="reload"),
            *turn(s, "second request", "r2"),
            ev("session_shutdown", s, "r2", reason="quit"),
        ],
    )
    run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="resume"),
            *turn(s, "third request"),
            ev("session_shutdown", s, reason="quit"),
        ],
    )
    [sf] = session_files(mb)
    text = sf.read_text()
    assert text.count("session_id:") == 1 and text.count("summary_schema:") == 1
    assert fm(text, "turns") == "3" and fm(text, "last_turn") == "pi-turn-3"
    for n in (1, 2, 3):
        assert text.count(f"Turn {n}: completed") == 1
    assert text.count("## Summary") == 1 and "third request" in text.split("## Summary", 1)[1]
    live = text.split("## Live log", 1)[1].split("\n## ", 1)[0]
    assert all(req in live for req in ["first request", "second request", "third request"])
    recent = (mb / "session/_recent.md").read_text()
    assert recent.count("0198c0de") == 1


def test_switch_from_bank_a_to_b_records_and_restores_only_b(tmp_path):
    a, mb_a = project(tmp_path, "a", recent="ALPHA_ONLY summary")
    b, mb_b = project(tmp_path, "b", recent="BETA_ONLY summary")
    s1, s2 = (
        sess("aaaaaaaa-0000-4000-8000-000000000001", a),
        sess("bbbbbbbb-0000-4000-8000-000000000002", b),
    )
    out = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s1, reason="startup"),
            *turn(s1, "request for A"),
            ev("session_shutdown", s1, reason="new"),
            ev("session_start", s2, reason="new"),
            *turn(s2, "request for B"),
            ev("session_shutdown", s2, reason="quit"),
        ],
    )
    first, second = injected(out, RESTORE)
    assert "ALPHA_ONLY" in first and "BETA_ONLY" not in first
    assert "BETA_ONLY" in second and "ALPHA_ONLY" not in second and "request for A" not in second
    [fa], [fb] = session_files(mb_a), session_files(mb_b)
    assert "request for A" in fa.read_text() and "request for B" not in fa.read_text()
    assert "request for B" in fb.read_text() and "request for A" not in fb.read_text()


def test_second_session_restores_previous_summary_once_as_context_not_user_request(tmp_path):
    a, mb = project(tmp_path, "a")
    s1, s2 = (
        sess("11111111-0000-4000-8000-000000000001", a),
        sess("22222222-0000-4000-8000-000000000002", a),
    )
    run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s1, reason="startup"),
            *turn(s1, "ship the parser"),
            ev("session_shutdown", s1, reason="quit"),
        ],
    )
    out = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s2, reason="startup"),
            ev("input", s2, text="continue", source="interactive"),
            ev("before_agent_start", s2, prompt="continue"),
            ev("before_agent_start", s2, prompt="again"),
        ],
    )
    [restored] = injected(out, RESTORE)
    assert "ship the parser" in restored and "not a new user request" in restored
    reloaded = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s2, reason="reload"),
            ev("before_agent_start", s2, prompt="after reload"),
        ],
        branches=out["branches"],
    )
    assert not injected(reloaded, RESTORE), "restore already on the branch is not replayed"
    s2_file = next(p for p in session_files(mb) if "22222222" in p.name).read_text()
    assert "ship the parser" not in s2_file.split("## Live log", 1)[1]


def test_compaction_writes_real_handoff_capsule_and_injects_it_once(tmp_path):
    a, mb = project(tmp_path, "a")
    s = sess("33333333-0000-4000-8000-000000000003", a)
    out = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "long task"),
            ev("session_before_compact", s, reason="threshold", willRetry=False),
            ev("session_compact", s, reason="threshold", willRetry=False, fromExtension=False),
            ev("before_agent_start", s, prompt="next"),
            ev("before_agent_start", s, prompt="next again"),
        ],
    )
    compact = next(r for r in out["results"] if r["event"] == "session_before_compact")
    assert not any(v.get("cancel") for v in compact["values"]), "compaction is never blocked"
    latest = (mb / "handoff/latest.md").read_text()
    assert fm(latest, "trigger") == "pre_compact" and fm(latest, "session_id") == s["id"]
    [capsule] = injected(out, HANDOFF)
    assert "Handoff capsule" in capsule and "pre_compact" in capsule
    text = session_files(mb)[0].read_text()
    assert (
        "## Handoff capsule" in text and "saved handoff/latest.md (pre_compact, threshold)" in text
    )


@pytest.mark.parametrize("mode", ["capture-off", "restore-off", "no-bank"])
def test_capture_restore_and_bank_switches_are_independent(tmp_path, mode):
    a, mb = project(tmp_path, "a", recent="PRIOR_SESSION summary")
    if mode == "no-bank":
        a = tmp_path / "bare"
        a.mkdir()
    env = {
        "capture-off": {"MB_SESSION_CAPTURE": "off"},
        "restore-off": {"MB_AUTOLOAD_CONTEXT": "off"},
        "no-bank": {},
    }[mode]
    s = sess("44444444-0000-4000-8000-000000000004", a)
    out = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "work"),
            ev("session_before_compact", s, reason="manual", willRetry=False),
            ev("session_compact", s, reason="manual", willRetry=False, fromExtension=False),
            ev("before_agent_start", s, prompt="next"),
            ev("session_shutdown", s, reason="quit"),
        ],
        env=env,
    )
    restored = injected(out, RESTORE)
    if mode == "capture-off":
        assert not session_files(mb)
        assert restored and "PRIOR_SESSION" in restored[0]
    elif mode == "restore-off":
        assert len(session_files(mb)) == 1 and not restored and not injected(out, HANDOFF)
    else:
        assert not restored and not injected(out, HANDOFF)
        assert sorted(p.name for p in a.iterdir()) == [], "absent bank is never initialized"


def test_forced_termination_leaves_live_log_and_no_forged_summary(tmp_path):
    a, mb = project(tmp_path, "a")
    s = sess("55555555-0000-4000-8000-000000000005", a)
    run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "half done work"),
            {"op": "kill"},
        ],
        expect_kill=True,
    )
    [sf] = session_files(mb)
    text = sf.read_text()
    assert "half done work" in text and "Turn 1: completed" in text
    assert (
        "## Summary" not in text and fm(text, "ended") is None and fm(text, "summarized") == "false"
    )
    later = sess("66666666-0000-4000-8000-000000000006", a)
    run(
        tmp_path,
        [
            LOAD,
            ev("session_start", later, reason="startup"),
            ev("session_shutdown", later, reason="quit"),
        ],
    )
    assert "## Summary" not in sf.read_text()
    recent = mb / "session/_recent.md"
    assert not recent.exists() or "55555555" not in recent.read_text()


def test_handoff_script_failure_does_not_block_compaction_or_capture(tmp_path):
    a, mb = project(tmp_path, "a")
    (mb / "handoff").write_text("not a directory")
    s = sess("77777777-0000-4000-8000-000000000007", a)
    out = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "before compaction"),
            ev("session_before_compact", s, reason="overflow", willRetry=True),
            ev("session_compact", s, reason="overflow", willRetry=True, fromExtension=False),
            *turn(s, "after compaction"),
            ev("session_shutdown", s, reason="quit"),
        ],
    )
    assert not injected(out, HANDOFF)
    text = session_files(mb)[0].read_text()
    assert (
        "## Handoff capsule" in text
        and "failed:" in text
        and "after compaction" in text
        and fm(text, "turns") == "2"
    )


def test_unwritable_session_dir_keeps_pi_running_and_restore_working(tmp_path):
    a, mb = project(tmp_path, "a")
    (mb / "session").rmdir()
    (mb / "session").write_text("blocked")
    (mb / "handoff").mkdir()
    (mb / "handoff/latest.md").write_text(
        "---\ntrigger: manual_update\n---\n# Handoff capsule\nKEEP_GOING\n"
    )
    s = sess("88888888-0000-4000-8000-000000000008", a)
    out = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "still works"),
            ev("session_shutdown", s, reason="quit"),
        ],
    )
    [restored] = injected(out, RESTORE)
    assert "KEEP_GOING" in restored
    assert (mb / "session").read_text() == "blocked"


def test_llm_summary_only_through_configured_summarizer(tmp_path):
    a, mb = project(tmp_path, "a")
    summarizer = tmp_path / "summarize"
    summarizer.write_text(
        "#!/usr/bin/env bash\ncat >/dev/null\nprintf '### What changed\\n- LLM_TEXT\\n"
        "### Decisions\\n- (none)\\n### Open questions\\n- (none)\\n### Files\\n- (none)\\n'\n"
    )
    summarizer.chmod(0o755)
    s = sess("99999999-0000-4000-8000-000000000009", a)
    run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "use the llm"),
            ev("session_shutdown", s, reason="quit"),
        ],
        env={"MB_SUMMARY_BACKEND": "command", "MB_SUMMARIZE_BIN": str(summarizer)},
    )
    text = session_files(mb)[0].read_text()
    assert fm(text, "summary_mode") == "llm" and fm(text, "summarized") == "true"
    assert text.count("## Summary") == 1 and "LLM_TEXT" in text
    recent = (mb / "session/_recent.md").read_text()
    assert "LLM_TEXT" in recent and recent.count("99999999") == 1


def test_hanging_summarizer_is_bounded_and_falls_back_to_disclosed_deterministic(tmp_path):
    a, mb = project(tmp_path, "a")
    summarizer = tmp_path / "hang"
    summarizer.write_text("#!/usr/bin/env bash\nsleep 60\n")
    summarizer.chmod(0o755)
    s = sess("aaaabbbb-0000-4000-8000-00000000000a", a)
    started = time.monotonic()
    out = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s, reason="startup"),
            *turn(s, "bounded please"),
            ev("session_shutdown", s, reason="quit"),
        ],
        env={
            "MB_SUMMARY_BACKEND": "command",
            "MB_SUMMARIZE_BIN": str(summarizer),
            "MB_SESSION_LLM_TIMEOUT": "1",
        },
    )
    assert time.monotonic() - started < 30
    shutdown = next(r for r in out["results"] if r["event"] == "session_shutdown")
    assert shutdown["ms"] < 15000
    text = session_files(mb)[0].read_text()
    assert (
        fm(text, "summary_mode") == "deterministic"
        and "bounded please" in text.split("## Summary", 1)[1]
    )
    assert "LLM summarizer did not complete" in text


def test_stale_start_and_compaction_callbacks_never_reach_replacement_session(tmp_path):
    a, mb_a = project(tmp_path, "a")
    b, mb_b = project(tmp_path, "b")
    s1, s2 = (
        sess("cccccccc-0000-4000-8000-00000000000c", a),
        sess("dddddddd-0000-4000-8000-00000000000d", b),
    )
    out = run(
        tmp_path,
        [
            LOAD,
            ev("session_start", s1, wait=False, reason="startup"),
            ev("session_shutdown", s1, wait=False, reason="new"),
            ev("session_start", s2, reason="new"),
            ev("input", s2, text="B request", source="interactive"),
            ev("session_before_compact", s2, wait=False, reason="threshold", willRetry=False),
            ev("session_shutdown", s2, wait=False, reason="new"),
            ev("session_start", s1, reason="resume"),
            {"op": "settle"},
            ev("before_agent_start", s1, prompt="after switch"),
            ev("session_compact", s1, reason="threshold", willRetry=False, fromExtension=False),
            ev("before_agent_start", s1, prompt="after compact"),
        ],
    )
    assert not injected(out, HANDOFF), "B's late handoff never injects into the replacement session"
    [fb] = session_files(mb_b)
    assert fm(fb.read_text(), "session_id") == s2["id"] and "B request" in fb.read_text()
    files_a = session_files(mb_a)
    assert [fm(p.read_text(), "session_id") for p in files_a] == [s1["id"]]
    assert (
        files_a[0].read_text().count("session_id:") == 1
        and "B request" not in files_a[0].read_text()
    )
