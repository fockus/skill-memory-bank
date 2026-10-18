"""Stage 4 review regressions across the real native API and shared work helpers."""

import json
import subprocess
from pathlib import Path
from urllib.parse import urlencode

import pytest
from test_opencode_v2_native import PIPELINE, ROOT, configure, fixture


@pytest.mark.parametrize("override, invalid", [(False, False), (True, False), (False, True)])
def test_s4_roles_native_selected_aspect_and_lead_override_stale_installed_pins(
    tmp_path: Path, override: bool, invalid: bool,
) -> None:
    counters = {"root": 0}
    runtime = fixture.NativeRuntime(tmp_path / "private", lambda request: respond(request), evidence_root=tmp_path / "evidence")
    try:
        pipeline = """roles:
  reviewer: {agent: codex-cli}
  reviewer_logic: {agent: mb-reviewer-logic, model: retired/old#deep}
  reviewer_security: {agent: mb-reviewer-security}
  reviewer_lead: {agent: mb-reviewer-lead, model: retired/old#deep}
workflow: {default: review-check}
workflows:
  review-check: {steps: [review, done], review_profile: ensemble}
review_ensemble:
  reviewers:
    - {role: reviewer_logic, focus: logic}
    - {role: reviewer_security, focus: security}
  lead_role: reviewer_lead
qa: {enabled: false}
"""
        runtime.install(pipeline)
        configure(runtime)
        config_path = runtime.project / "opencode.json"
        config = json.loads(config_path.read_text())
        config["providers"]["retired"] = {**config["providers"]["fixture"], "models": {
            "old": {"modelID": "wire-retired", "capabilities": {"tools": True, "input": ["text"], "output": ["text"]},
                    "limit": {"context": 200000, "output": 8192}, "variants": [{"id": "deep", "body": {"fixture_variant": "deep"}}]}}}
        config["policies"].append({"action": "provider.use", "resource": "retired", "effect": "allow"})
        config["permissions"] += [{"action": "subagent", "resource": role, "effect": "allow"}
                                  for role in ("mb-reviewer-logic", "mb-reviewer-lead")]
        config_path.write_text(json.dumps(config))
        bank = runtime.project / ".memory-bank"
        source = bank / "plans/review.md"
        source.parent.mkdir()
        source.write_text("<!-- mb-stage:1 -->\n### Stage 1\n- [ ] Review product\n")
        selected = pipeline.replace("{agent: codex-cli}", "{agent: codex-cli, model: opus}")
        selected = selected.replace("retired/old#deep", "opus" if invalid else "fixture/team/coder#deep", 1)
        selected = selected.replace("retired/old#deep", "fixture/team/verifier#audit")
        selected = selected.replace("{agent: mb-reviewer-security}", "{agent: mb-reviewer-security, model: opus}")
        (bank / "pipelines/fixture.yaml").write_text("agents: [opencode]\n" + selected)
        installed = {p: p.read_bytes() for p in (runtime.project / ".opencode/agent").glob("*.md")}

        def respond(request: dict) -> dict:
            system = str([m for m in request["messages"] if m["role"] == "system"])
            if "# MB Reviewer Logic" in system or "# MB Reviewer Lead" in system:
                return {"content": "Selected native review role observed."}
            step = counters["root"]
            counters["root"] += 1
            if step == 0:
                return fixture.tool(request, {"command"}, {"command": f'bash "{ROOT}/scripts/mb-work-state.sh" init plan 1 --source-path "{source}" --mb .memory-bank', "workdir": str(runtime.project)})
            if step < 3:
                agent = ("mb-reviewer-logic", "mb-reviewer-lead")[step - 1]
                return fixture.tool(request, {"agent", "prompt"}, {"agent": agent, "description": "Selected ensemble role",
                                                                     "prompt": "Review the scoped product; report your role."})
            return {"content": "Selected ensemble dispatch complete."}

        runtime.start()
        agents = runtime.data("/api/agent?" + urlencode({"location[directory]": str(runtime.project)}))
        assert all(a["model"] == {"providerID": "retired", "id": "old", "variant": "deep"}
                   for a in agents if a["id"] in ("mb-reviewer-logic", "mb-reviewer-lead"))
        root = runtime.api("POST", "/api/session", {"location": {"directory": str(runtime.project)}, "title": "Selected ensemble",
                                                   "model": {"providerID": "fixture", "id": "team/parent", "variant": "parent"}})["data"]
        args = "work review --lenses logic" + (" --step-model reviewer=inherit" if override else "")
        if invalid:
            with pytest.raises(RuntimeError, match="provider/model"):
                runtime.api("POST", f'/api/session/{root["id"]}/command', {"name": "mb", "text": args})
            assert runtime.requests == []
        else:
            runtime.api("POST", f'/api/session/{root["id"]}/command', {"name": "mb", "text": args})
            runtime.wait(root["id"])
            children = [s for s in runtime.data("/api/session?" + urlencode({"directory": str(runtime.project)}))
                        if s.get("parentID") == root["id"]]
            assert {s["agent"] for s in children} == {"mb-reviewer-logic", "mb-reviewer-lead"}
            for child in children:
                assert child["model"] == ({"providerID": "fixture", "id": "team/parent", "variant": "parent"} if override else {
                    "providerID": "fixture", "id": "team/coder" if child["agent"] == "mb-reviewer-logic" else "team/verifier",
                    "variant": "deep" if child["agent"] == "mb-reviewer-logic" else "audit"})
            assert all(p.read_bytes() == body for p, body in installed.items())
        assert runtime.errors == []
        assert all(r["model"] != "wire-retired" for r in runtime.requests)
        runtime.tag = f"ensemble-override-{override}-invalid-{invalid}"
        runtime.save_evidence(source)
    finally:
        runtime.close()


@pytest.mark.parametrize("ownership", [False, True])
def test_native_root_identity_and_missing_state_refusal_then_owned_reinit(tmp_path: Path, ownership: bool) -> None:
    counts = {"step": 0, "phase": 0, "child": 0, "foreign": 0}
    runtime = fixture.NativeRuntime(tmp_path / "private", lambda request: respond(request), evidence_root=tmp_path / "evidence")
    try:
        pipeline = PIPELINE.replace("verifier: {agent: plan-verifier", "verifier: {agent: mb-developer")
        if ownership:
            runtime.env["MB_PIPELINE_HOST"] = "codex"
            pipeline = pipeline.replace("  verifier:", "  planner: {agent: mb-architect}\n  verifier:")
            pipeline = pipeline.replace("steps: [implement, verify, done]", "steps: [plan, implement, done]\n    entrypoint: freeform_or_topic")
        runtime.install(pipeline)
        configure(runtime)
        project, bank = runtime.project, runtime.project / ".memory-bank"
        source = bank / "plans/case.md"
        source.parent.mkdir()
        source.write_text("<!-- mb-stage:1 -->\n### Stage 1\n**Role:** developer\n- [ ] Product\n")
        state = f'bash "{ROOT}/scripts/mb-work-state.sh"'
        init = f'{state} init plan 1 --source-path "{source}" --mb .memory-bank'
        foreign = bank / "plans/foreign.md"
        foreign.write_text(source.read_text())
        if ownership:
            result = subprocess.run(["bash", str(ROOT / "scripts/mb-work-state.sh"), "init", str(foreign), "1", "--source-path", str(foreign),
                "--run-id", "prior-root", "--mb", str(bank)], cwd=project, env={**runtime.env, "MB_WORK_PARALLEL": "1"}, capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, result.stderr
        first = [] if ownership else [f'{init} > run-id; {state} status --mb .memory-bank > premature-state.json; {state} clear --mb .memory-bank']
        second = ([f'bash "{ROOT}/scripts/mb-plan.sh" feature new-topic .memory-bank; '
                   f'SRC=$(bash "{ROOT}/scripts/mb-work-resolve.sh" new-topic --mb .memory-bank); '
                   f'{state} init plan 1 --source-path "$SRC" --mb .memory-bank > run-id; {state} step implement --mb .memory-bank'] if ownership else
                  [f'{init} > run-id; {state} step implement --mb .memory-bank'])

        def respond(request: dict) -> dict:
            system = str([m for m in request["messages"] if m["role"] == "system"])
            if "# MB Developer — Subagent Prompt" in system:
                counts["child"] += 1
                return {"content": "Owned current-item model observed."}
            if "FOREIGN_OWNER" in str([m for m in request["messages"] if m["role"] == "user"]):
                counts["foreign"] += 1
                if counts["foreign"] == 1:
                    other = bank / "plans/new-foreign.md"
                    return fixture.tool(request, {"command"}, {"command": 'python3 -c "import os; assert not os.environ.get(\'MB_WORK_RUN_ID\'); assert os.environ[\'MB_PIPELINE_HOST\'] == \'opencode\'; print(\'FOREIGN_NOT_BOUND\')"; '
                        f'export MB_WORK_PARALLEL=1; {state} step implement --run-id prior-root --mb .memory-bank; '
                        f'cp "{foreign}" "{other}"; {state} init "{other}" 1 --source-path "{other}" --run-id new-foreign-root --mb .memory-bank', "workdir": str(project)})
                return {"content": "Foreign canonical state updated without acquiring another root binding."}
            step = counts["step"]
            counts["step"] += 1
            commands = second if counts["phase"] else first
            if counts["phase"] and ownership and step == 0:
                return fixture.tool(request, {"agent", "prompt"}, {"agent": "mb-developer", "description": "Reject foreign adoption", "prompt": "This must refuse before owned planning initialization."})
            offset = 1 if counts["phase"] and ownership else 0
            if step - offset < len(commands):
                return fixture.tool(request, {"command"}, {"command": commands[step - offset], "workdir": str(project)})
            if step - offset == len(commands):
                return fixture.tool(request, {"agent", "prompt"}, {"agent": "mb-developer", "description": "Current owned item", "prompt": "Report only; use the current canonical item assignment."})
            return {"content": "Pause without certifying any execution item."}

        runtime.start()
        root = runtime.api("POST", "/api/session", {"location": {"directory": str(project)}, "title": "Owning root",
            "model": {"providerID": "fixture", "id": "team/parent", "variant": "parent"}})["data"]
        runtime.api("POST", f'/api/session/{root["id"]}/command', {"name": "mb", "text": f'work {"new-topic" if ownership else "case"} --model inherit'})
        paused = runtime.wait(root["id"])
        assert counts["child"] == 0
        if ownership:
            other = runtime.api("POST", "/api/session", {"location": {"directory": str(project)}, "title": "Foreign root",
                "model": {"providerID": "fixture", "id": "team/parent", "variant": "parent"}})["data"]
            runtime.api("POST", f'/api/session/{other["id"]}/prompt', {"text": "FOREIGN_OWNER: update only the foreign canonical slots."})
            runtime.wait(other["id"])
            assert {s["run_id"] for s in runtime.states()} == {"prior-root", "new-foreign-root"}
            assert "FOREIGN_NOT_BOUND" in str(runtime.data(f'/api/session/{other["id"]}/context'))
        else:
            assert runtime.states() == []
        counts.update(step=0, phase=1)
        runtime.api("POST", f'/api/session/{root["id"]}/prompt', {"text": "Continue only this root's owned initialization."})
        runtime.wait(root["id"], after_idle=paused["time"]["idle"])
        children = [s for s in runtime.data("/api/session?" + urlencode({"directory": str(project)})) if s.get("parentID") == root["id"]]
        assert len(children) == counts["child"] == 1
        assert children[0]["model"] == {"providerID": "fixture", "id": "team/parent", "variant": "parent"}
        current = next(s for s in runtime.states() if s["run_id"] == (project / "run-id").read_text().strip())
        assert current["phase"] == "in-progress" and "eval_gate" not in current
        if not ownership:
            assert current["run_id"] == json.loads((project / "premature-state.json").read_text())["run_id"]
        source = Path(current["source_path"])
        assert runtime.errors == [] and all(r["model"] == "wire-parent" for r in runtime.requests)
        runtime.tag = f"root-ownership-{ownership}"
        runtime.save_evidence(source)
    finally:
        runtime.close()


@pytest.mark.parametrize("override", [False, True])
def test_s4_item_and_run_native_current_item_models_then_expired_override(tmp_path: Path, override: bool) -> None:
    counters = {"root": 0, "child": 0}
    runtime = fixture.NativeRuntime(tmp_path / "private", lambda request: respond(request), evidence_root=tmp_path / "evidence")
    try:
        pipeline = PIPELINE.replace("  verifier:", "  backend: {agent: mb-developer, model: fixture/team/verifier#audit}\n  verifier:")
        pipeline = pipeline.replace("steps: [implement, verify, done]", "steps: [implement, done]")
        runtime.install(pipeline)
        configure(runtime)
        project = runtime.project
        source = project / ".memory-bank/plans/sequential.md"
        source.parent.mkdir()
        source.write_text("<!-- mb-stage:1 -->\n### Stage 1\n**Role:** developer\n- [ ] First product\n"
                          "<!-- mb-stage:2 -->\n### Stage 2\n**Role:** backend\n- [ ] Second product\n")
        state = f'bash "{ROOT}/scripts/mb-work-state.sh"'
        common = '--run-id "$(cat run-id)" --mb .memory-bank'
        def shell(command: str) -> tuple:
            return ("shell", {"command": command, "workdir": str(project)})

        def dispatch(prompt: str, model: str = "") -> tuple:
            return ("subagent", {"agent": "mb-developer", "description": prompt, "prompt": prompt,
                                 **({"model": model} if model else {})})
        actions = [
            shell(f'{state} init plan 1 --source-path "{source}" --max-cycles 2 --mb .memory-bank > run-id'),
            dispatch("Wrong future item model must refuse", "fixture/team/verifier#audit"),
            dispatch("First native item: write first.py with value first; run its actual check."),
            None,
            shell(f'{state} done {common} && bash "{ROOT}/scripts/mb-work-checkbox.sh" flip "{source}" 1 {common}'),
            shell(f'{state} init plan 2 --source-path "{source}" {common}'),
            dispatch("Second native item: write second.py with value second; run its actual check."),
            shell(f'{state} done {common} && bash "{ROOT}/scripts/mb-work-checkbox.sh" flip "{source}" 2 {common}'),
            shell(f'{state} clear {common}'),
            dispatch("Ordinary dispatch after completion: report without edits."),
        ]
        for name in ("first", "second"):
            (project / f"check_{name}.py").write_text(f"from {name} import value\nassert value == '{name}'\nprint('{name.upper()}_GREEN')\n")

        def respond(request: dict) -> dict:
            system = str([m for m in request["messages"] if m["role"] == "system"])
            if "# MB Developer — Subagent Prompt" in system:
                index = counters["child"]
                counters["child"] += 1
                if index < 6:
                    name = "first" if index < 3 else "second"
                    if index % 3 == 0:
                        return fixture.tool(request, {"path", "content"}, {"path": str(project / f"{name}.py"), "content": f"value = '{name}'\n"})
                    if index % 3 == 1:
                        return fixture.tool(request, {"command"}, {"command": f"python3 check_{name}.py", "workdir": str(project)})
                return {"content": "Actual native item check complete."}
            index = counters["root"]
            counters["root"] += 1
            action = actions[index] if index < len(actions) else None
            if action:
                kind, values = action
                return fixture.tool(request, {"command"} if kind == "shell" else {"agent", "prompt"}, values)
            return {"content": "Pause without clearing work state." if index == 3 else "Canonical run complete."}

        runtime.start()
        root = runtime.api("POST", "/api/session", {"location": {"directory": str(project)}, "title": "Sequential items",
                                                   "model": {"providerID": "fixture", "id": "team/parent", "variant": "parent"}})["data"]
        runtime.api("POST", f'/api/session/{root["id"]}/command', {"name": "mb", "text": "work sequential" + (" --model inherit" if override else "")})
        paused = runtime.wait(root["id"])
        assert counters["root"] == 4 and counters["child"] == 3
        assert runtime.states()[0]["phase"] == "in-progress"
        runtime.api("POST", f'/api/session/{root["id"]}/prompt', {"text": "Continue the same canonical run, then ordinary dispatch."})
        runtime.wait(root["id"], after_idle=paused["time"]["idle"])
        assert counters["child"] == 7 and runtime.states() == []
        assert source.read_text().count("- [x]") == 2
        children = [s for s in runtime.data("/api/session?" + urlencode({"directory": str(project)})) if s.get("parentID") == root["id"]]
        assert len(children) == 3 and all(s["agent"] == "mb-developer" for s in children)
        children.sort(key=lambda s: s["time"]["created"])
        models = [s["model"] for s in children]
        inherited = {"providerID": "fixture", "id": "team/parent", "variant": "parent"}
        coder = {"providerID": "fixture", "id": "team/coder", "variant": "deep"}
        verifier = {"providerID": "fixture", "id": "team/verifier", "variant": "audit"}
        assert models == ([inherited, inherited, coder] if override else [coder, verifier, coder])
        context = str(runtime.data(f'/api/session/{root["id"]}/context'))
        assert ("must inherit the exact parent" if override else "requires fixture/team/coder#deep") in context
        for child in children[:2]:
            checks = [p["state"] for m in runtime.data(f'/api/session/{child["id"]}/context') if m["type"] == "assistant"
                      for p in m["content"] if p["type"] == "tool" and "check_" in p["state"].get("input", {}).get("command", "")]
            assert len(checks) == 1 and checks[0]["status"] == "completed" and checks[0]["metadata"]["exit"] == 0
        assert runtime.errors == []
        runtime.tag = f"sequential-override-{override}"
        runtime.save_evidence(source)
    finally:
        runtime.close()
