"""Stage 4: real native dispatch and declared-Eval /mb work completion, no paid provider."""

import importlib.util
import json
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlencode

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("native_fixture", ROOT / "tests/fixtures/opencode_v2_mock.py")
assert spec and spec.loader
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

PIPELINE = """roles:
  developer: {agent: mb-developer, model: fixture/team/coder#deep}
  verifier: {agent: plan-verifier, model: fixture/team/verifier#audit}
hosts:
  opencode: {preset: native-check, verify: stage}
workflow: {default: native-check}
workflows:
  native-check:
    steps: [implement, verify, done]
    verify: {cadence: stage}
qa: {enabled: false}
"""


def configure(runtime) -> None:
    models = {}
    for name, variant in (("parent", "parent"), ("coder", "deep"), ("verifier", "audit")):
        models[f"team/{name}"] = {
            "modelID": f"wire-{name}", "capabilities": {"tools": True, "input": ["text"], "output": ["text"]},
            "limit": {"context": 200000, "output": 8192},
            "variants": [{"id": variant, "body": {"fixture_variant": variant}}],
        }
    config = {"$schema": "https://opencode.ai/config.json", "model": "fixture/team/parent",
              "plugins": ["-opencode.provider.ollama", "-opencode.provider.lmstudio", "-opencode.provider.vllm",
                          "-opencode.websearch.*", "-opencode.wellknown"],
              "snapshots": False, "compaction": {"auto": False},
              "experimental": {"subagent_depth": 1},
              "policies": [{"action": "provider.use", "resource": "*", "effect": "deny"},
                           {"action": "provider.use", "resource": "fixture", "effect": "allow"}],
              "providers": {"fixture": {"name": "Loopback fixture", "package": "@opencode/ai/providers/openai-compatible",
                                        "settings": {"baseURL": f"http://127.0.0.1:{runtime.provider.server_port}/v1",
                                                     "timeout": 10000, "apiKey": "fixture-not-a-secret"}, "models": models}},
              "permissions": [{"action": "shell", "resource": "*", "effect": "allow"},
                              {"action": "edit", "resource": "*", "effect": "allow"},
                              {"action": "subagent", "resource": "*", "effect": "deny"},
                              {"action": "subagent", "resource": "mb-developer", "effect": "allow"},
                              {"action": "subagent", "resource": "plan-verifier", "effect": "allow"}]}
    (runtime.project / "opencode.json").write_text(json.dumps(config))


@pytest.mark.parametrize("override, failing, unpinned, legacy", [(False, False, False, False), (True, False, False, False),
                    (False, True, False, False), (False, False, True, False), (True, False, False, True)],
                    ids=["False-False-False", "True-False-False", "False-True-False", "False-False-True", "legacy-resume"])
def test_native_work_observes_models_and_real_eval_completion(override: bool, failing: bool, unpinned: bool, legacy: bool, tmp_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="mb-stage4-native-", dir=tmp_path) as tmp:
        runtime = fixture.NativeRuntime(Path(tmp), lambda request: respond(request), evidence_root=tmp_path / "evidence")
        try:
            assert runtime.root.is_relative_to(tmp_path), "S4-PORTABLE-6: runtime must belong to this pytest root"
            runtime.install(re.sub(r", model: [^}]+", "", PIPELINE) if unpinned else PIPELINE)
            configure(runtime)
            project = runtime.project
            bank = project / ".memory-bank"
            source = bank / "specs/greeting/tasks.md"
            source.parent.mkdir(parents=True)
            (source.parent / "requirements.md").write_text(
                "# Requirements\nREQ-001: When greeting is invoked, the product SHALL return hello native.\n")
            (source.parent / "design.md").write_text(
                "# Design\nA pure greeting function in product.py; check_product.py observes its returned value.\n")
            source.write_text("# Tasks: greeting\n\n<!-- mb-task:1 -->\n## Task 1: repair greeting\n"
                              "**Role:** developer\n**Covers:** REQ-001\n**Scope:** product.py\n"
                              "**Eval:** python3 check_product.py — red: greeting differs; exit: 1; output~: GREETING_RED\n"
                              "**DoD:**\n- [ ] Product returns the required greeting.\n<!-- /mb-task:1 -->\n")
            (project / "product.py").write_text("def greeting():\n    return 'broken'\n")
            (project / "check_product.py").write_text(
                "from product import greeting\nimport sys\n"
                "ok = greeting() == 'hello native'\nprint('GREETING_GREEN' if ok else 'GREETING_RED')\nsys.exit(0 if ok else 1)\n")
            (project / "eval.cmd").write_text("python3 check_product.py\n")
            state = f'bash "{ROOT}/scripts/mb-work-state.sh"'
            common = '--run-id "$(cat run-id)" --mb .memory-bank'
            if legacy:
                initialized = subprocess.run(["bash", str(ROOT / "scripts/mb-work-state.sh"), "init", "spec", "1", "--source-path", str(source),
                    "--run-id", "legacy-root", "--mb", str(bank)], cwd=project, env=runtime.env, capture_output=True, text=True, timeout=15)
                assert initialized.returncode == 0, initialized.stderr
                (project / "run-id").write_text(initialized.stdout)
            initialize = (f'{state} step implement {common} && test -f .memory-bank/.work-state.json && '
                          'test ! -e .memory-bank/.work-state/legacy-root.json && echo LEGACY_SLOT_UNCHANGED' if legacy else
                          f'{state} init spec 1 --source-path "{source}" --source-topic greeting --max-cycles 2 --mb .memory-bank > run-id')
            model_flags = " --model inherit --step-model verifier=inherit" if override else ""
            actions = [
                ("shell", {"command": f'bash "{ROOT}/scripts/mb-workflow.sh" --host opencode --mb .memory-bank --json && '
                           f'bash "{ROOT}/scripts/mb-work-plan.sh" --target greeting --host opencode --mb .memory-bank{model_flags} && '
                           f'{initialize} && '
                           f'{state} eval-red --cmd-file eval.cmd --output-re GREETING_RED --expected-exit 1 {common}',
                           "workdir": str(project)}),
                ("subagent", {"agent": "mb-developer", "description": "Implement greeting task",
                              "prompt": f"Implement only {source} task 1. "
                              + ("Failure fixture: leave the product red; run the actual check without editing." if failing else "Change product.py to return hello native. Run python3 check_product.py after editing.")
                              + " Do NOT edit DoD checkboxes."}),
                ("shell", {"command": f'{state} eval-green --cmd-file eval.cmd {common}', "workdir": str(project)}),
                ("subagent", {"agent": "plan-verifier", "description": "Independently verify greeting",
                              "prompt": f"Source file: {source}\nSkill path: {ROOT}\nRun python3 check_product.py yourself. "
                              "Inspect product.py. Report actual output and PASS only if it exits zero; do not edit source or state."}),
                ("shell", {"command": f'{state} done {common}; d=$?; '
                           f'bash "{ROOT}/scripts/mb-work-checkbox.sh" flip "{source}" 1 {common}; f=$?; '
                           + (f'{state} clear {common}; c=$?; {state} clear {common}; r=$?; '
                              f'printf "CLEAR_EXIT=%s REPEAT_CLEAR_EXIT=%s\\n" "$c" "$r"; '
                              f'{state} retained {common} > completed-state.json; ' if not failing else '')
                           +
                           'printf "DONE_EXIT=%s FLIP_EXIT=%s\\n" "$d" "$f"; '
                           f'{state} status {common}', "workdir": str(project)}),
            ]
            if override:
                actions.append(("subagent", {"agent": "mb-developer", "description": "Ordinary dispatch after grouped completion",
                                              "prompt": "Report only; do not edit files or run a workflow."}))
            counters = {"root": 0, "implementer": 0, "verifier": 0}

            def respond(request: dict) -> dict:
                system = "\n".join(str(m.get("content", "")) for m in request["messages"] if m["role"] == "system")
                role = "verifier" if "# Plan Verifier — Subagent Prompt" in system else "implementer" if "# MB Developer — Subagent Prompt" in system else "root"
                step = counters[role]
                counters[role] += 1
                if role == "root" and step < len(actions):
                    kind, values = actions[step]
                    return fixture.tool(request, {"command"} if kind == "shell" else {"agent", "prompt"}, values)
                if role == "implementer" and step == 0 and not failing:
                    return fixture.tool(request, {"path", "content"}, {"path": str(project / "product.py"), "content": "def greeting():\n    return 'hello native'\n"})
                if role in ("implementer", "verifier") and step == (1 if role == "implementer" and not failing else 0):
                    return fixture.tool(request, {"command"}, {"command": "python3 check_product.py", "workdir": str(project)})
                observed = str([m for m in request["messages"] if m["role"] == "tool"])
                if role != "root":
                    return {"content": "PASS: actual check printed GREETING_GREEN" if "GREETING_GREEN" in observed else "FAIL: actual check did not pass"}
                return {"content": "Workflow gate results are in the actual helper output."}

            runtime.start()
            installed = {p: p.read_bytes() for p in (project / ".opencode/agent").glob("*.md")}
            query = "?" + urlencode({"directory": str(project)})
            models = runtime.api("GET", "/api/model?" + urlencode({"location[directory]": str(project)}))["data"]
            assert {m["providerID"] for m in models} == {"fixture"}
            root = runtime.api("POST", "/api/session", {"location": {"directory": str(project)},
                                                       "title": "Native workflow fixture",
                                                       "model": {"providerID": "fixture", "id": "team/parent", "variant": "parent"}})["data"]
            args = "work greeting --verify stage" + (" --model inherit --step-model verifier=inherit" if override else "")
            args += " --run-id legacy-root" if legacy else ""
            assert runtime.api("POST", f'/api/session/{root["id"]}/command', {"name": "mb", "text": args}) is None
            runtime.wait(root["id"])
            assert runtime.errors == []
            if legacy:
                first = next(part["state"] for m in runtime.data(f'/api/session/{root["id"]}/context') if m["type"] == "assistant"
                             for part in m["content"] if part["type"] == "tool")
                assert first["metadata"]["exit"] == 0 and "LEGACY_SLOT_UNCHANGED" in str(first["content"])
            assert counters["implementer"] >= 2 and counters["verifier"] >= 2
            sessions = runtime.api("GET", "/api/session" + query)["data"]
            children = [s for s in sessions if s.get("parentID") == root["id"]]
            assert {s["agent"] for s in children} == {"mb-developer", "plan-verifier"}
            ordinary = max(children, key=lambda s: s["time"]["created"]) if override else None
            for child in children:
                expected = {"providerID": "fixture", "id": "team/coder", "variant": "deep"} if child is ordinary else {"providerID": "fixture", "id": "team/parent", "variant": "parent"} if override or unpinned else {
                    "providerID": "fixture", "id": "team/coder" if child["agent"] == "mb-developer" else "team/verifier",
                    "variant": "deep" if child["agent"] == "mb-developer" else "audit"}
                assert child["model"] == expected
                assert child["location"]["directory"] == str(project)
                if child is ordinary:
                    continue
                messages = runtime.data(f'/api/session/{child["id"]}/context')
                checks = [part["state"] for m in messages if m["type"] == "assistant"
                          for part in m["content"] if part["type"] == "tool"
                          and part["state"].get("input", {}).get("command") == "python3 check_product.py"]
                assert len(checks) == 1 and checks[0]["status"] == "completed"
                assert ("GREETING_RED" if failing else "GREETING_GREEN") in str(checks[0]["content"])
                assert checks[0]["metadata"]["exit"] == (1 if failing else 0)
            for request in runtime.requests:
                system = str([m for m in request["messages"] if m["role"] == "system"])
                assert "GLOBAL_NATIVE_RULE_SENTINEL" in system and "PROJECT_NATIVE_RULE_SENTINEL" in system
                assert request["fixture_variant"] == {"wire-parent": "parent", "wire-coder": "deep", "wire-verifier": "audit"}[request["model"]]
            result = runtime.states()[0] if failing else json.loads((project / "completed-state.json").read_text())
            assert bool(runtime.states()) is failing
            assert result["eval"]["red_observed"] is True
            assert result["eval"]["green_exit"] == (1 if failing else 0)
            assert result["phase"] == ("in-progress" if failing else "done")
            assert result["run_id"] == ("legacy-root" if legacy else (project / "run-id").read_text().strip())
            assert ("- [x]" in source.read_text()) is not failing
            context = str(runtime.api("GET", f'/api/session/{root["id"]}/context'))
            assert "pipelines/fixture.yaml" in context and '"name": "native-check"' in context
            assert ("DONE_EXIT=5 FLIP_EXIT=1" if failing else "DONE_EXIT=0 FLIP_EXIT=0") in context
            assert all(p.read_bytes() == content for p, content in installed.items())
            if failing:
                assert "eval_gate" not in result
            else:
                assert result["eval_gate"] == "verified:red_green"
                assert "CLEAR_EXIT=0 REPEAT_CLEAR_EXIT=0" in context
            runtime.sid = root["id"]
            runtime.tag = f"work-override-{override}-red-{failing}-unpinned-{unpinned}" + ("-legacy" if legacy else "")
            runtime.save_evidence()
            assert (runtime.evidence_root / f"mb-stage4-{runtime.tag}-evidence.json").is_file()
        finally:
            runtime.close()


@pytest.mark.parametrize("planning", [False, True])
def test_native_preview_or_completed_planning_admission_leaves_ordinary_pin(tmp_path: Path, planning: bool) -> None:
    counts = {"step": 0, "phase": 0, "children": 0}
    runtime = fixture.NativeRuntime(tmp_path / "private", lambda request: respond(request), evidence_root=tmp_path / "evidence")
    try:
        pipeline = PIPELINE + "\n"
        if planning:
            pipeline = pipeline.replace("  verifier:", "  planner: {agent: mb-architect, model: fixture/team/coder#deep}\n  verifier:")
            pipeline = pipeline.replace("steps: [implement, verify, done]", "steps: [plan]\n    entrypoint: freeform_or_topic")
        runtime.install(pipeline)
        configure(runtime)
        project, bank = runtime.project, runtime.project / ".memory-bank"
        source = bank / "plans/case.md"
        if planning:
            selected = bank / "pipelines/fixture.yaml"
            selected.write_text(selected.read_text().replace("planner: {agent: mb-architect, model: fixture/team/coder#deep}",
                                                             "planner: {agent: mb-architect, model: fixture/team/verifier#audit}"))
            config = json.loads((project / "opencode.json").read_text())
            config["permissions"].append({"action": "subagent", "resource": "mb-architect", "effect": "allow"})
            (project / "opencode.json").write_text(json.dumps(config))
        else:
            source.parent.mkdir()
            source.write_text("<!-- mb-stage:1 -->\n### Stage 1\n**Role:** developer\n- [ ] Product\n")
        installed = {p: p.read_bytes() for p in (project / ".opencode/agent").glob("*.md")}

        def respond(request: dict) -> dict:
            system = str([m for m in request["messages"] if m["role"] == "system"])
            if "# MB Architect — Subagent Prompt" in system or "# MB Developer — Subagent Prompt" in system:
                counts["children"] += 1
                return {"content": "Planning or ordinary native role observed."}
            step = counts["step"]
            counts["step"] += 1
            if step == 0 and (planning or counts["phase"]):
                return fixture.tool(request, {"agent", "prompt"}, {"agent": "mb-architect" if planning else "mb-developer",
                    "description": "Native lifetime check", "prompt": "Plan only, or report ordinary role; do not certify task completion."})
            if planning and not counts["phase"] and step == 1:
                return fixture.tool(request, {"command"}, {"command": f'bash "{ROOT}/scripts/mb-plan.sh" feature new-topic .memory-bank', "workdir": str(project)})
            return {"content": "The admitted planning or preview generation is complete."}

        runtime.start()
        root = runtime.api("POST", "/api/session", {"location": {"directory": str(project)}, "title": "Planning lifetime",
            "model": {"providerID": "fixture", "id": "team/parent", "variant": "parent"}})["data"]
        runtime.api("POST", f'/api/session/{root["id"]}/command', {"name": "mb", "text": "work new-topic" if planning else "work case --dry-run --model inherit"})
        completed = runtime.wait(root["id"])
        assert runtime.states() == [] and not (bank / ".work-completed").exists()
        counts.update(step=0, phase=1)
        runtime.api("POST", f'/api/session/{root["id"]}/prompt', {"text": "Ordinary role dispatch after that generation."})
        runtime.wait(root["id"], after_idle=completed["time"]["idle"])
        children = sorted([s for s in runtime.data("/api/session?" + urlencode({"directory": str(project)})) if s.get("parentID") == root["id"]], key=lambda s: s["time"]["created"])
        assert len(children) == (2 if planning else 1)
        assert children[-1]["model"] == {"providerID": "fixture", "id": "team/coder", "variant": "deep"}
        if planning:
            assert children[0]["model"] == {"providerID": "fixture", "id": "team/verifier", "variant": "audit"}
            source = next((bank / "plans").glob("*new-topic*.md"))
            assert "- [x]" not in source.read_text() and "- ✅" not in source.read_text()
        assert runtime.errors == [] and all(p.read_bytes() == body for p, body in installed.items())
        runtime.tag = f"planning-lifetime-{planning}"
        runtime.save_evidence(source)
    finally:
        runtime.close()


@pytest.mark.parametrize("arguments, reason", [
    ("MB_PIPELINE=missing", "named pipeline not found"),
    ("--model opus", "provider/model"),
    ("--model fixture/team/coder#unknown", "supported variant"),
    ("--model fixture/wire-coder", "catalog ID"),
])
def test_native_work_invalid_selection_stops_before_any_model_request(arguments: str, reason: str, tmp_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="mb-stage4-reject-", dir=tmp_path) as tmp:
        runtime = fixture.NativeRuntime(Path(tmp), lambda _: {"content": "must not run"}, evidence_root=tmp_path / "evidence")
        try:
            assert runtime.root.is_relative_to(tmp_path), "S4-PORTABLE-6: runtime must belong to this pytest root"
            runtime.install(PIPELINE)
            configure(runtime)
            if arguments.startswith("MB_PIPELINE="):
                runtime.env["MB_PIPELINE"] = arguments.split("=", 1)[1]
                arguments = ""
            source = runtime.project / ".memory-bank/specs/greeting/tasks.md"
            source.parent.mkdir(parents=True)
            source.write_text("# Tasks\n<!-- mb-task:1 -->\n## Task 1\n**Role:** developer\n**DoD:**\n- [ ] Works\n")
            runtime.start()
            root = runtime.api("POST", "/api/session", {"location": {"directory": str(runtime.project)},
                                                       "title": "Rejected work", "model": {"providerID": "fixture", "id": "team/parent"}})["data"]
            with pytest.raises(RuntimeError, match=re.escape(reason)):
                runtime.api("POST", f'/api/session/{root["id"]}/command', {"name": "mb", "text": f"work greeting {arguments}"})
            assert runtime.requests == []
            assert not (runtime.project / ".memory-bank/.work-state.json").exists()
        finally:
            runtime.close()
