"""Governed work through native commands and public event-bus child execution."""

import json

import pytest
from test_pi_native_commands import bank, host


def project(
    tmp_path,
    steps="implement, verify, review, judge, done",
    named=False,
    model="opus",
    agent="mb-developer",
    backend="nico",
):
    mb = bank(tmp_path / ".memory-bank")
    (mb / "plans").mkdir()
    source = mb / "plans/2026-10-05_feature_sample.md"
    source.write_text(
        "---\ntitle: Sample\nstatus: in_progress\ntype: feature\n---\n\n<!-- mb-stage:1 -->\n## Stage 1: Sample\n\n**Role:** developer\n**Status:** pending\n\n- [ ] observable outcome\n"
    )
    yaml = f"""version: 1
roles:
  developer: {{agent: {agent}, model: {model}}}
  verifier: {{agent: plan-verifier}}
  reviewer: {{agent: mb-reviewer}}
  judge: {{agent: mb-judge, model: sonnet}}
workflow:
  default: sample-flow
workflows:
  sample-flow:
    steps: [{steps}]
    entrypoint: plan_or_spec
    loop: {{max_cycles: 2, returns_to: verify}}
review:
  enabled: {str("review" in steps).lower()}
  severity_gate: {{blocker: 0, major: 0, minor: 3}}
protected_paths: ['.env*']
"""
    path = mb / "pipeline.yaml"
    # This battery exercises the Nico contract; selection is by bank policy.
    config = f"pi_subagent_backend={backend}\n" if backend else ""
    if named:
        (mb / "pipelines").mkdir()
        path = mb / "pipelines/native-test.yaml"
        config += "pipeline=native-test\n"
    if config:
        (mb / ".mb-config").write_text(config)
    path.write_text(yaml)
    return mb, source


def evidence(mb):
    slots = list((mb / ".work-state").glob("*.json"))
    return [json.loads(p.read_text()) for p in slots]


@pytest.mark.parametrize(
    "named,steps,expected",
    [
        (False, "implement, verify, done", ["mb-developer", "plan-verifier"]),
        (
            True,
            "implement, verify, review, judge, done",
            ["mb-developer", "plan-verifier", "mb-reviewer", "mb-judge"],
        ),
    ],
)
def test_named_pipeline_dispatch_and_durable_outputs(tmp_path, named, steps, expected):
    mb, source = project(tmp_path, named=named, steps=steps)
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert not result.get("error"), result
    assert [row["agent"] for row in result["launches"]] == expected, result
    for row in result["launches"]:
        assert row["context"] == "fresh"
        assert row.get("model") is None, "Legacy aliases must inherit current provider/model"
        assert row["output"] and __import__("pathlib").Path(row["output"]).is_file()
    states = evidence(mb)
    assert len(states) == 1 and states[0]["phase"] == "done", states
    assert states[0]["source_path"] == str(source)
    assert states[0]["item_no"] == 1 and states[0]["source_topic"] == "feature_sample"
    assert states[0].get("eval_gate") != "verified:red_green"


@pytest.mark.parametrize(
    "step,verdict", [("verify", "FAIL"), ("review", "CHANGES_REQUESTED"), ("judge", "NO_GO")]
)
def test_negative_gate_retains_open_source_and_run(tmp_path, step, verdict):
    mb, source = project(tmp_path)
    result = host(
        tmp_path,
        tmp_path,
        args="work sample --range 1",
        negative={"step": step, "verdict": verdict},
    )
    assert result.get("error"), result
    assert evidence(mb) and all(s["phase"] != "done" for s in evidence(mb)), result
    assert "- [ ] observable outcome" in source.read_text()
    assert not any(row["key"].startswith("done") for row in result["launches"])


@pytest.mark.parametrize("step", ["verify", "review", "judge"])
def test_malformed_verdict_never_closes(tmp_path, step):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", malformed=step)
    assert result.get("error"), result
    assert evidence(mb) and all(s["phase"] != "done" for s in evidence(mb))
    assert "- [ ] observable outcome" in source.read_text()


def test_infrastructure_failure_is_explicit_no_inline(tmp_path):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", offline=True)
    assert result.get("error") and "RPC" in result["error"], result
    assert not result["launches"]
    assert not any(m["kind"] == "user" for m in result["messages"])
    assert "- [ ] observable outcome" in source.read_text()


@pytest.mark.parametrize(
    "model,authorization,allowed",
    [
        ("anthropic/claude-opus-4", "", False),
        ("anthropic/claude-opus-4", " --authorize-provider anthropic", True),
        ("anthropic/claude-opus-4", " --authorize-provider openai", False),
        ("anthropic/missing", " --authorize-provider anthropic", False),
        ("ambiguous-model", "", False),
    ],
)
def test_cross_provider_override_requires_run_specific_owner_authorization(
    tmp_path, model, authorization, allowed
):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args=f"work sample --range 1 --model {model}{authorization}")
    if allowed:
        assert not result.get("error"), result
        assert result["launches"] and all(row["model"] == model for row in result["launches"])
        identity = json.loads(
            next((mb / "reports/native-work").rglob("identity-1.json")).read_text()
        )
        assert identity["ownerAuthorization"] == {
            "runId": evidence(mb)[0]["run_id"],
            "provider": "anthropic",
        }
    else:
        assert result.get("error") and not result["launches"], result
        assert all(s["phase"] != "done" for s in evidence(mb))


def test_missing_agent_preflight_refuses_before_launch(tmp_path):
    project(tmp_path, agent="missing-agent")
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert result.get("error") and not result["launches"], result


def test_cancel_stops_owned_run_and_preserves_source(tmp_path):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", cancel=True)
    assert result.get("error") and result["cancelled"], result
    assert all(s["phase"] != "done" for s in evidence(mb))
    assert "- [ ] observable outcome" in source.read_text()


def test_concurrent_command_does_not_duplicate_steps(tmp_path):
    project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", concurrent=True)
    assert [row["agent"] for row in result["launches"]].count("mb-developer") == 1, result


def test_exhausted_fix_cycles_stay_open(tmp_path):
    mb, source = project(tmp_path, steps="implement, verify, review, judge, fix, done")
    result = host(
        tmp_path,
        tmp_path,
        args="work sample --range 1",
        negative={"step": "judge", "verdict": "NO_GO"},
    )
    assert result.get("error") and "cycle" in result["error"].lower(), result
    assert evidence(mb)[0]["phase"] != "done"
    assert evidence(mb)[0]["cycle"] >= 2
    assert sum(r["key"].startswith("fix-") for r in result["launches"]) == 2
    assert "- [ ] observable outcome" in source.read_text()


def test_protected_path_gate_is_not_dropped(tmp_path):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", protected=True)
    assert result.get("error") and ".env.secret" in result["error"], result
    assert all(s["phase"] != "done" for s in evidence(mb))


def test_budget_gate_is_not_dropped(tmp_path):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1 --budget 5", tokens=10)
    assert result.get("error") and "budget" in result["error"].lower(), result
    assert all(s["phase"] != "done" for s in evidence(mb))


def test_explicit_codex_cli_reviewer_receives_no_native_override(tmp_path):
    mb, source = project(tmp_path)
    pipeline = mb / "pipeline.yaml"
    pipeline.write_text(
        pipeline.read_text().replace(
            "agent: mb-reviewer", "agent: codex-cli, model: gpt-5.6-sol, thinking: xhigh"
        )
    )
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert not result.get("error"), result
    assert any(r["agent"] == "codex-cli" and "model" not in r for r in result["launches"]), result


def test_configured_main_review_requires_independent_receipt(tmp_path):
    mb, source = project(tmp_path)
    pipeline = mb / "pipeline.yaml"
    pipeline.write_text(
        pipeline.read_text().replace(
            "agent: mb-reviewer", "agent: mb-reviewer, parallel_with: main-agent"
        )
    )
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert result.get("error") and "main" in result["error"].lower(), result
    assert all(s["phase"] != "done" for s in evidence(mb))


def test_work_alias_executes_pipeline_not_prompt(tmp_path):
    project(tmp_path)
    result = host(tmp_path, tmp_path, command="work", args="sample --range 1")
    assert not result.get("error") and result["launches"], result
    assert not any(m["kind"] == "user" for m in result["messages"])


def test_resume_reverifies_without_resetting_prior_run(tmp_path):
    mb, source = project(tmp_path)
    first = host(
        tmp_path,
        tmp_path,
        args="work sample --range 1",
        negative={"step": "verify", "verdict": "FAIL"},
    )
    assert first.get("error")
    run = evidence(mb)[0]
    second = host(tmp_path, tmp_path, args=f"work sample --range 1 --resume-run {run['run_id']}")
    assert not second.get("error"), second
    assert [r["agent"] for r in second["launches"]] == ["plan-verifier", "mb-reviewer", "mb-judge"]
    assert len(evidence(mb)) == 1 and evidence(mb)[0]["phase"] == "done"
    assert first["launches"][-1]["output"] != second["launches"][0]["output"]
    assert evidence(mb)[0]["steps"].count("implement") == 1


def test_runtime_usage_not_child_prose_controls_budget(tmp_path):
    mb, source = project(tmp_path)
    result = host(
        tmp_path, tmp_path, args="work sample --range 1 --budget 5", tokens=0, runtimeTokens=10
    )
    assert result.get("error") and "budget" in result["error"].lower(), result
    assert all(s["phase"] != "done" for s in evidence(mb))


def test_late_terminal_failure_cannot_approve_output(tmp_path):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", failedChild=True)
    assert result.get("error"), result
    assert all(s["phase"] != "done" for s in evidence(mb))


def test_same_source_live_slot_refuses_new_command(tmp_path):
    mb, source = project(tmp_path)
    host(
        tmp_path,
        tmp_path,
        args="work sample --range 1",
        negative={"step": "verify", "verdict": "FAIL"},
    )
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert result.get("error") and "claimed" in result["error"], result
    assert not result["launches"]
    assert len(evidence(mb)) == 1


def test_paused_child_cannot_close_even_with_exit_zero(tmp_path):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", pausedChild=True)
    assert result.get("error"), result
    assert all(s["phase"] != "done" for s in evidence(mb))


def test_judge_go_with_failed_acceptance_never_closes(tmp_path):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", judgeUnmet=True)
    assert result.get("error"), result
    assert all(s["phase"] != "done" for s in evidence(mb))


def test_go_with_backlog_registers_before_done(tmp_path):
    mb, source = project(tmp_path)
    (mb / "backlog.md").write_text("# Backlog\n\n## Ideas\n")
    result = host(tmp_path, tmp_path, args="work sample --range 1", backlog=True)
    assert not result.get("error"), result
    assert "Native follow-up" in (mb / "backlog.md").read_text()
    assert evidence(mb)[0]["phase"] == "done"


def test_unbound_main_review_receipt_cannot_close(tmp_path):
    mb, source = project(tmp_path)
    pipeline = mb / "pipeline.yaml"
    pipeline.write_text(
        pipeline.read_text().replace(
            "agent: mb-reviewer", "agent: mb-reviewer, parallel_with: main-agent"
        )
    )
    receipt = tmp_path / "main.json"
    receipt.write_text(
        json.dumps(
            {"verdict": "APPROVED", "counts": {"blocker": 0, "major": 0, "minor": 0}, "issues": []}
        )
    )
    result = host(tmp_path, tmp_path, args=f"work sample --range 1 --main-review {receipt}")
    assert result.get("error"), result
    assert all(s["phase"] != "done" for s in evidence(mb))


def test_ensemble_profile_is_not_silently_reduced_to_single_review(tmp_path):
    mb, source = project(tmp_path)
    pipeline = mb / "pipeline.yaml"
    pipeline.write_text(
        pipeline.read_text().replace(
            "    entrypoint: plan_or_spec",
            "    review_profile: ensemble\n    entrypoint: plan_or_spec",
        )
    )
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert result.get("error") and "ensemble" in result["error"].lower(), result
    assert not result["launches"]


def test_cancel_during_spawn_retains_and_stops_child_identity(tmp_path):
    mb, source = project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", cancelDuringSpawn=True)
    assert result.get("error") and result["cancelled"], result
    assert list((mb / "reports/native-work").rglob("*.launch.json"))
    assert all(s["phase"] != "done" for s in evidence(mb))
