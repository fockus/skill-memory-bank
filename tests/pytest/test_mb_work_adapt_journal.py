"""svp-adapt-escalation T3 — escalation journal, cascade stop, summary (design C3)."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys

import pytest
from _inproc import load_adapt, run_main

ADAPT = str(pathlib.Path(__file__).resolve().parents[2] / "scripts" / "mb_work_adapt.py")


def _run(*args: str) -> subprocess.CompletedProcess:
    return run_main(load_adapt().main, list(args))


def _open(bank, item="4", run="r1", mode="hitl", triggers="verify_fail_cycles", *extra):
    return _run(
        "esc-open",
        "--bank",
        str(bank),
        "--run-id",
        run,
        "--item-id",
        item,
        "--cycle",
        "0",
        "--mode",
        mode,
        "--triggers",
        triggers,
        *extra,
    )


def _journal(bank) -> list[dict]:
    path = pathlib.Path(bank) / "tmp" / "escalations.jsonl"
    return [json.loads(ln) for ln in path.read_text(encoding="utf-8").splitlines()]


def _resolve(bank, esc_id, resolution, backlog=""):
    extra = ["--backlog-id", backlog] if backlog else []
    return _run(
        "esc-resolve", "--bank", str(bank), "--id", esc_id, "--resolution", resolution, *extra
    )


def test_esc_open_writes_opened_record(tmp_path: pathlib.Path) -> None:
    res = _open(tmp_path)
    assert res.returncode == 0, res.stderr
    out = json.loads(res.stdout)
    assert out["decision"] == "fork_user" and out["consecutive"] == 1
    (line,) = _journal(tmp_path)
    assert line["event"] == "opened" and line["escalation_id"] == out["escalation_id"]
    assert line["seq"] == 1 and line["triggers"] == ["verify_fail_cycles"] and line["ts"]


def test_esc_open_decision_follows_mode(tmp_path: pathlib.Path) -> None:
    assert json.loads(_open(tmp_path, "1", mode="autonomous").stdout)["decision"] == "auto_split"
    refused = _open(tmp_path, "2", "r1", "autonomous", "review_cycles", "--split-refused")
    assert json.loads(refused.stdout)["decision"] == "stub_continue"
    assert _open(tmp_path, "3", "r1", "hitl", "review_cycles", "--split-refused").returncode == 2


def test_esc_open_seq_counts_per_item_and_cycle(tmp_path: pathlib.Path) -> None:
    _open(tmp_path)
    second = json.loads(_open(tmp_path).stdout)
    assert second["escalation_id"].endswith(":2")


def test_esc_resolve_correlates_by_escalation_id(tmp_path: pathlib.Path) -> None:
    esc = json.loads(_open(tmp_path, "a:b").stdout)["escalation_id"]
    assert _resolve(tmp_path, esc, "continue").returncode == 0
    lines = _journal(tmp_path)
    assert [ln["event"] for ln in lines] == ["opened", "resolved"]
    assert lines[1]["escalation_id"] == esc and lines[1]["resolved_by"] == "user"
    assert lines[1]["item_id"] == "a:b" and lines[1]["backlog_id"] is None


def test_esc_resolve_matrix(tmp_path: pathlib.Path) -> None:
    hitl = json.loads(_open(tmp_path, "1").stdout)["escalation_id"]
    auto = json.loads(_open(tmp_path, "2", mode="autonomous").stdout)["escalation_id"]
    stub = json.loads(_open(tmp_path, "3", "r2", "autonomous", "x", "--split-refused").stdout)[
        "escalation_id"
    ]
    assert _resolve(tmp_path, hitl, "skip").returncode == 2  # backlog id required
    assert _resolve(tmp_path, hitl, "continue", "I-001").returncode == 2  # forbidden
    assert _resolve(tmp_path, hitl, "stub_continue", "I-001").returncode == 2  # wrong decision
    assert _resolve(tmp_path, auto, "continue").returncode == 2
    assert _resolve(tmp_path, auto, "decompose").returncode == 0
    assert _resolve(tmp_path, stub, "stub_continue").returncode == 2
    assert _resolve(tmp_path, stub, "stub_continue", "I-009").returncode == 0
    assert _resolve(tmp_path, "nope", "continue").returncode == 2
    resolved = [ln for ln in _journal(tmp_path) if ln["event"] == "resolved"]
    assert [ln["resolved_by"] for ln in resolved] == ["orchestrator", "orchestrator"]


def test_esc_resolve_is_idempotent_and_corrections_append(tmp_path: pathlib.Path) -> None:
    esc = json.loads(_open(tmp_path).stdout)["escalation_id"]
    _resolve(tmp_path, esc, "continue")
    _resolve(tmp_path, esc, "continue")
    assert len(_journal(tmp_path)) == 2
    _resolve(tmp_path, esc, "simplify")
    assert [ln.get("resolution") for ln in _journal(tmp_path)] == [None, "continue", "simplify"]
    assert "correction" in _run("esc-summary", "--bank", str(tmp_path), "--run-id", "r1").stdout


def test_cascade_stop_after_three_consecutive_and_clean_resets(tmp_path: pathlib.Path) -> None:
    decisions = [json.loads(_open(tmp_path, str(i)).stdout)["decision"] for i in (1, 2)]
    assert decisions == ["fork_user", "fork_user"]
    third = json.loads(_open(tmp_path, "3").stdout)
    assert third["decision"] == "stop_run" and third["consecutive"] == 3
    assert _resolve(tmp_path, third["escalation_id"], "continue").returncode == 2
    assert (
        _run("esc-clean", "--bank", str(tmp_path), "--run-id", "r1", "--item-id", "4").returncode
        == 0
    )
    assert json.loads(_open(tmp_path, "5").stdout)["consecutive"] == 1
    assert json.loads(_open(tmp_path, "6", run="r2").stdout)["consecutive"] == 1


@pytest.mark.parametrize(
    "bad",
    [
        '{"event":"mystery","ts":"x"}',
        '{"ts":"x","event":"clean","run_id":"r1","item_id":"1","cycle":0,"extra":1}',
        '{"ts":"x","event":"clean","run_id":"r1","item_id":"1","cycle":"0"}',
        "not json",
    ],
)
def test_invalid_journal_line_fails_loud_without_append(tmp_path: pathlib.Path, bad: str) -> None:
    path = tmp_path / "tmp" / "escalations.jsonl"
    path.parent.mkdir()
    path.write_text(bad + "\n", encoding="utf-8")
    res = _open(tmp_path)
    assert res.returncode == 1 and "code=invalid_log_line line=1" in res.stderr
    assert path.read_text(encoding="utf-8") == bad + "\n"


def test_journal_concurrent_writers_keep_every_line(tmp_path: pathlib.Path) -> None:
    procs = [
        subprocess.Popen(
            [
                sys.executable,
                ADAPT,
                "esc-open",
                "--bank",
                str(tmp_path),
                "--run-id",
                f"r{r}",
                "--item-id",
                str(i),
                "--cycle",
                "0",
                "--mode",
                "hitl",
                "--triggers",
                "t",
                "--pipeline",
                "",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for r in (1, 2)
        for i in range(4)
    ]
    errs = [(p.wait(timeout=120), p.stderr.read()) for p in procs]
    assert all(rc == 0 for rc, _ in errs), errs
    lines = _journal(tmp_path)
    assert len(lines) == 8 and all(ln["event"] == "opened" for ln in lines)
    # cascade_stop 3 per run: the 3rd-and-later opens of a run are stop_run, counted without gaps
    for run in ("r1", "r2"):
        assert sorted(ln["consecutive"] for ln in lines if ln["run_id"] == run) == list(range(1, 5))
    assert not (tmp_path / "tmp" / ".escalations.lock").exists()


def test_esc_summary_lists_escalations_and_stub_backlog_ids(tmp_path: pathlib.Path) -> None:
    stub = json.loads(
        _open(tmp_path, "7", "r1", "autonomous", "review_cycles", "--split-refused").stdout
    )
    _resolve(tmp_path, stub["escalation_id"], "stub_continue", "I-042")
    _open(tmp_path, "8")
    out = _run("esc-summary", "--bank", str(tmp_path), "--run-id", "r1").stdout
    assert "item=7" in out and "stub_continue" in out and "I-042" in out
    assert "item=8" in out and "open" in out


def test_work_md_esc_calls_carry_the_required_flags() -> None:
    import re

    text = (pathlib.Path(ADAPT).parents[1] / "commands" / "work.md").read_text(encoding="utf-8")
    calls = re.findall(r"`(esc-(?:resolve|open|clean|summary)\b[^`]*)`", text)
    assert calls
    for call in calls:
        if " " not in call or "…" in call:
            continue
        for flag in ("--bank", "--id" if "esc-resolve" in call else "--run-id"):
            assert flag in call, call
