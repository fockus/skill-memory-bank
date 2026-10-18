"""D03-D05 durable memory, real compaction, explicit resume and bank isolation."""

import hashlib
import json
import shutil
import uuid

import pytest
from test_opencode_acceptance_native import (
    native as native,
)
from test_opencode_acceptance_native import (
    new_root,
    prompt,
    scripted,
    system_text,
    tool_states,
    until,
)


def records(bank):
    return sorted(p for p in (bank / "session").glob("*.md") if p.name != "_recent.md")


def primary_requests(runtime, start=0):
    return [r for r in runtime.requests[start:] if r.get("tools")]


def snapshot(bank):
    return {str(p.relative_to(bank)): (p.stat().st_mode, hashlib.sha256(p.read_bytes()).hexdigest())
            for p in bank.rglob("*") if p.is_file() and not p.name.startswith(".oc-") and ".tmp." not in p.name}


@pytest.mark.parametrize("present", [True, False], ids=["task-context", "absent"])
def test_native_root_and_child_receive_task_or_remain_absent(native, present):
    runtime, _ = native
    bank = runtime.project / ".memory-bank"
    (bank / "status.md").write_text("# Current task\nTASK_CONTEXT_NATIVE_SENTINEL repair the public greeting.\n")
    if not present:
        bank.rename(runtime.root / "bank-not-discoverable")
    root_reply = scripted([({"agent", "prompt"}, {"agent": "mb-developer", "description": "Observe native context",
                                                "prompt": "Report only; do not initialize memory or write files."})])

    def respond(request):
        if "# MB Developer — Subagent Prompt" in system_text(request):
            return {"content": "Child context observed without changes."}
        return root_reply(request)

    runtime.respond = respond
    runtime.start()
    sid = new_root(runtime)
    prompt(runtime, sid, "Inspect the current context through one native child.")
    children = [s for s in runtime.data("/api/session") if s.get("parentID") == sid]
    assert len(children) == 1
    requests = primary_requests(runtime)
    assert any("# MB Developer — Subagent Prompt" in system_text(r) for r in requests)
    for request in requests:
        system = system_text(request)
        assert "GLOBAL_NATIVE_RULE_SENTINEL" in system and "PROJECT_NATIVE_RULE_SENTINEL" in system
        assert ("TASK_CONTEXT_NATIVE_SENTINEL" in system) is present
        if not present:
            assert "Memory Bank restored context" not in system
    assert bank.exists() is present
    runtime.observations.update(bank_present=present, root_and_child_context_checked=True)


def test_native_private_memory_restores_fresh_root_and_reopened_session(native):
    runtime, _ = native
    runtime.env["MB_SEMANTIC"] = "auto"
    private, credential = "PRIVATE_" + uuid.uuid4().hex, "sk-" + uuid.uuid4().hex * 2
    runtime.secrets.extend([private, credential])
    bank = runtime.project / ".memory-bank"
    notes = bank / "notes"
    notes.mkdir()
    (notes / "resolver.md").write_text(f"# Native resolver reliability decision\nDecision: RECALL_ONLY_PUBLIC use lexical retrieval.\n<private>\n{private}\n</private>\nAPI_KEY={credential}\n")
    runtime.respond = scripted([], final=f"Decision: DURABLE_PUBLIC_DECISION keep the shared boundary.\nNext: DURABLE_PUBLIC_OPEN_WORK verify restoration.\n<private>\n{private}\n</private>\nAPI_KEY={credential}")
    runtime.start()
    sid = new_root(runtime)
    prompt(runtime, sid, "Record the public decision and unfinished work.")
    until(lambda: len(records(bank)) == 1 and (bank / "session/_recent.md").exists(), "durable completed turn")
    file = records(bank)[0]
    original = file.read_text()
    assert not any(secret in original for secret in runtime.secrets), "Private input leaked into memory"
    assert "DURABLE_PUBLIC_DECISION" in original and "DURABLE_PUBLIC_OPEN_WORK" in original
    state = json.loads(next(line[15:] for line in original.splitlines() if line.startswith("capture_state: ")))
    assert len(state["seen"]) == 1
    first_turn = state["seen"][0]
    for path in (file, bank / "session/_recent.md"):
        assert path.stat().st_mode & 0o777 == 0o600
    runtime.respond = scripted([], final="Public restored context acknowledged.")
    fresh = new_root(runtime)
    offset = len(runtime.requests)
    prompt(runtime, fresh, "Recall the native resolver reliability decision and remaining verification work.")
    restored = "\n".join(system_text(r) for r in primary_requests(runtime, offset))
    assert not any(secret in restored for secret in runtime.secrets), "Private input leaked into restored context"
    assert all(value in restored for value in ("DURABLE_PUBLIC_DECISION", "DURABLE_PUBLIC_OPEN_WORK", "RECALL_ONLY_PUBLIC"))
    runtime.api("POST", "/api/location/reload")
    runtime.catalogs()
    offset = len(runtime.requests)
    prompt(runtime, sid, "Reopen this persisted session and continue the remaining verification.")
    reopened = "\n".join(system_text(r) for r in primary_requests(runtime, offset))
    assert not any(secret in reopened for secret in runtime.secrets), "Private input leaked after reload"
    assert "DURABLE_PUBLIC_DECISION" in reopened and "DURABLE_PUBLIC_OPEN_WORK" in reopened
    until(lambda: 'turns: 2\n' in file.read_text(), "one new turn after reopen")
    captured = [p.read_text() for p in records(bank)] + [(bank / "session/_recent.md").read_text()]
    assert not any(secret in text for secret in runtime.secrets for text in captured), "Saved memory leaked private input"
    resumed_state = json.loads(next(line[15:] for line in file.read_text().splitlines() if line.startswith("capture_state: ")))
    assert resumed_state["seen"].count(first_turn) == 1
    assert not (bank / ".index").exists()
    runtime.observations.update(public_memory_restored=True, recall_restored=True, private_filtered=True,
                                original_turn_captured_once=True, memory_sha256=hashlib.sha256(file.read_bytes()).hexdigest())


def compact(runtime, sid):
    before = {m["id"] for m in runtime.data(f"/api/session/{sid}/context")}
    runtime.api("POST", f"/api/session/{sid}/compact", {})
    return until(lambda: [m for m in runtime.data(f"/api/session/{sid}/context")
                          if m["type"] == "compaction" and m["id"] not in before and m["status"] == "completed"],
                 "completed public compaction", timeout=70)


def observe_native_events(runtime):
    target = runtime.evidence_root / "native-event-shapes.jsonl"
    plugin = runtime.project / ".opencode/plugins/acceptance-event-observer.js"
    plugin.write_text("import * as fs from 'node:fs/promises';\nexport default {id: 'acceptance-event-observer', async setup(ctx) {\n"
        f"const file = {json.dumps(str(target))};\n"
        "const record = value => fs.appendFile(file, JSON.stringify(value) + '\\n', {mode: 0o600});\n"
        "await record({kind: 'context', location: ctx.location});\n"
        "const abort = new AbortController();\n"
        "const pending = (async () => {try {for await (const event of ctx.event.subscribe({signal: abort.signal})) {\n"
        "await record({kind: 'event', type: event.type, location: event.location, fields: Object.keys(event.data || {}), sessionID: event.data?.sessionID, status: event.data?.status?.type});\n"
        "}} catch (error) {if (!abort.signal.aborted) await record({kind: 'subscription-error', name: error.name});}})();\n"
        "return async () => {abort.abort(); await pending;};\n}};\n")


def test_native_child_and_moved_foreign_bank_cannot_modify_parent_memory(native):
    runtime, _ = native
    runtime.env["MB_AUTO_CAPTURE"] = "auto"
    config_file = runtime.project / "opencode.json"
    config = json.loads(config_file.read_text())
    config["compaction"] = {"auto": False, "keep": {"tokens": 0}}
    config_file.write_text(json.dumps(config))
    runtime.respond = scripted([], final="Decision: PARENT_ONLY_PUBLIC keep the original bank.")
    runtime.start()
    parent = new_root(runtime)
    prompt(runtime, parent, "Persist the parent bank before isolation checks.")
    bank = runtime.project / ".memory-bank"
    until(lambda: records(bank) and (bank / "session/_recent.md").exists(), "parent capture before isolation")
    until(lambda: "Auto-capture" in (bank / "progress.md").read_text(), "parent legacy stub before isolation")
    before = snapshot(bank)
    child = runtime.api("POST", "/api/session", {"parentID": parent, "agent": "mb-developer",
        "model": {"providerID": "fixture", "id": "team/coder", "variant": "deep"}})["data"]["id"]
    runtime.respond = scripted([], final="Decision: CHILD_ONLY_PUBLIC never append this to parent memory.")
    prompt(runtime, child, "Complete a child-only public turn.")
    compact(runtime, child)
    runtime.api("DELETE", f"/api/session/{child}")
    assert snapshot(bank) == before, "Child completion/compaction/deletion changed the parent bank"
    foreign = runtime.root / "foreign-project"
    foreign.mkdir()
    shutil.copy2(runtime.project / "opencode.json", foreign / "opencode.json")
    shutil.copytree(runtime.project / ".opencode/plugins", foreign / ".opencode/plugins")
    other = foreign / ".memory-bank"
    other.mkdir()
    for name in ("status", "progress", "checklist", "roadmap"):
        (other / f"{name}.md").write_text(f"# Foreign {name}\nFOREIGN_BANK_PUBLIC_CONTEXT\n")
    runtime.api("POST", f"/api/session/{parent}/move", {"directory": str(foreign)})
    until(lambda: runtime.data(f"/api/session/{parent}")["location"]["directory"] == str(foreign), "foreign location move")
    runtime.respond = scripted([], final="Decision: FOREIGN_ONLY_PUBLIC stay in the moved bank.")
    offset = len(runtime.requests)
    prompt(runtime, parent, "Continue only in the new foreign project bank.")
    until(lambda: records(other) and (other / "session/_recent.md").exists(), "foreign-bank capture")
    compact(runtime, parent)
    until(lambda: (other / "handoff/latest.md").exists(), "foreign-bank handoff")
    assert snapshot(bank) == before, "Moved foreign activity appended to or closed the old bank"
    assert any("FOREIGN_BANK_PUBLIC_CONTEXT" in system_text(r) for r in primary_requests(runtime, offset))
    assert all("CHILD_ONLY_PUBLIC" not in p.read_text() and "FOREIGN_ONLY_PUBLIC" not in p.read_text() for p in records(bank))
    runtime.observations.update(child_isolated=True, foreign_bank_isolated=True, foreign_capture_and_handoff=True)


def test_native_completed_compaction_then_explicit_work_resume_keeps_run_source_item(native):
    runtime, bundle = native
    project, bank = runtime.project, runtime.project / ".memory-bank"
    config_file = project / "opencode.json"
    config = json.loads(config_file.read_text())
    config["compaction"] = {"auto": False, "keep": {"tokens": 0}}
    config_file.write_text(json.dumps(config))
    source = bank / "plans/continuation.md"
    source.parent.mkdir()
    source.write_text("# Public continuation\n<!-- mb-stage:1 -->\n### Stage 1: Persist unfinished work\n**Role:** developer\n- [ ] Verify remaining native work\n<!-- mb-stage:2 -->\n### Stage 2: Later work\n**Role:** developer\n- [ ] Leave the next item untouched\n")
    (bank / "checklist.md").write_text("# Checklist\n- [ ] Verify remaining native work\n")
    state = f'bash "{bundle}/scripts/mb-work-state.sh"'
    common = '--mb .memory-bank'
    runtime.respond = scripted([({"command"}, {"command": f'{state} init plan 1 --source-path "{source}" {common} && {state} step implement {common}',
                                             "workdir": str(project)})],
                              final="Decision: Keep this canonical run.\nNext: Verify remaining native work.")
    observe_native_events(runtime)
    runtime.start()
    sid = new_root(runtime)
    arguments = "work continuation --model inherit"
    runtime.api("POST", f"/api/session/{sid}/command", {"name": "mb", "text": arguments})
    runtime.wait(sid)
    assert tool_states(runtime, sid)[0]["metadata"]["exit"] == 0
    original_state = runtime.states()[0]
    assert original_state["run_id"] and original_state["item_no"] == 1
    common = f'--run-id "{original_state["run_id"]}" --mb .memory-bank'
    arguments += f' --run-id {original_state["run_id"]}'
    original_source = source.read_bytes()
    runtime.respond = scripted([], final="Next: Verify remaining native work without certifying completion.")
    prompt(runtime, sid, "Keep the current item unfinished before compaction.")
    compact(runtime, sid)
    handoff = bank / "handoff/latest.md"
    until(handoff.exists, "durable compaction handoff")
    assert "Verify remaining native work" in handoff.read_text()
    assert handoff.stat().st_mode & 0o777 == 0o600
    handoff_before = handoff.read_bytes()
    entered = project / "interrupt-entered"
    runtime.respond = scripted([({"command"}, {"command": "printf active > interrupt-entered; sleep 20", "workdir": str(project)})])
    idle_before = runtime.data(f"/api/session/{sid}")["time"].get("idle")
    runtime.api("POST", f"/api/session/{sid}/prompt", {"text": "Pause this bounded action for a controlled interruption."})
    until(entered.exists, "native shell entered before interruption")
    assert runtime.api("POST", f"/api/session/{sid}/interrupt?resume=false")["interrupted"] is True
    runtime.wait(sid, after_idle=idle_before)
    runtime.api("POST", "/api/location/reload")
    runtime.catalogs()
    proof = project / "resumed-state.json"
    runtime.respond = scripted([({"command"}, {"command": f'{state} status {common} > "{proof}"', "workdir": str(project)})])
    idle_before = runtime.data(f"/api/session/{sid}")["time"].get("idle")
    runtime.api("POST", f"/api/session/{sid}/command", {"name": "mb", "text": arguments})
    runtime.wait(sid, after_idle=idle_before)
    resumed = json.loads(proof.read_text())
    for key in ("run_id", "source", "source_path", "item_no"):
        assert resumed[key] == original_state[key]
    assert resumed["source_path"] == str(source) and resumed["phase"] == "in-progress"
    assert source.read_bytes() == original_source and handoff.read_bytes() == handoff_before
    assert len(runtime.states()) == 1 and not list((bank / ".work-completed").glob("*.json"))
    assert resumed.get("eval_gate") is None
    assert tool_states(runtime, sid)[-1]["metadata"]["exit"] == 0
    runtime.observations.update(compaction_completed=True, handoff_retained=True, explicit_resume=True,
                                run_id=resumed["run_id"], item_no=resumed["item_no"], source_unchanged=True)


def test_native_completed_tools_persist_real_files_names_and_errors(native: tuple) -> None:
    runtime, _ = native
    project, bank = runtime.project, runtime.project / ".memory-bank"
    selected = bank / "pipelines/fixture.yaml"
    selected.write_text(selected.read_text() + "\nprotected_paths: [blocked-native.txt]\n")
    target, blocked = project / "written-native.txt", project / "blocked-native.txt"
    runtime.respond = scripted([
        ({"path", "content"}, {"path": str(target), "content": "TOOL_BODY_NOT_MEMORY original\n"}),
        ({"path", "oldString", "newString"}, {"path": str(target), "oldString": "original", "newString": "edited"}),
        ({"path", "content"}, {"path": str(project / "second-native.txt"), "content": "SECOND_BODY_NOT_MEMORY\n"}),
        ({"path", "content"}, {"path": str(blocked), "content": "FAILED_INPUT_NOT_MEMORY\n"}),
    ], final="Public native tool sequence completed.")
    runtime.start()
    sid = new_root(runtime)
    prompt(runtime, sid, "Perform the four bounded file actions and preserve only completed public evidence.")
    messages = runtime.data(f"/api/session/{sid}/context")
    tools = [p for m in messages if m["type"] == "assistant" for p in m["content"] if p["type"] == "tool"]
    runtime.observations["native_tool_input_fields"] = {t["function"]["name"]: sorted(t["function"]["parameters"].get("properties", {}))
        for t in primary_requests(runtime)[0]["tools"] if t["function"]["name"] in {"write", "edit", "patch", "execute"}}
    runtime.observations["native_tool_contract"] = [{
        "name": p.get("name"), "legacy_tool_field": "tool" in p, "status": p["state"]["status"],
        "input_keys": sorted(p["state"]["input"]), "metadata_keys": sorted(p["state"].get("metadata", {})),
        "metadata_list_shapes": {key: [sorted(v) if isinstance(v, dict) else type(v).__name__ for v in value[:8]]
                                 for key, value in p["state"].get("metadata", {}).items() if isinstance(value, list)},
    } for p in tools]
    runtime.observations["assistant_snapshot_shapes"] = [sorted(m.get("snapshot", {})) for m in messages if m["type"] == "assistant"]
    assert [p["name"] for p in tools] == ["write", "edit", "write", "write"]
    assert [p["state"]["status"] for p in tools] == ["completed", "completed", "completed", "error"]
    assert target.read_text() == "TOOL_BODY_NOT_MEMORY edited\n" and not blocked.exists()
    assert (project / "second-native.txt").read_text() == "SECOND_BODY_NOT_MEMORY\n"
    until(lambda: records(bank) and (bank / "session/_recent.md").exists(), "native tool memory capture")
    text = "\n".join(p.read_text() for p in records(bank))
    for file in ("written-native.txt", "second-native.txt"):
        assert file in text, f"Completed native file missing from memory: {file}"
    assert "tools: write, edit" in text and "err(1)" in text
    assert "blocked-native.txt" not in text
    assert all(value not in text for value in ("TOOL_BODY_NOT_MEMORY", "SECOND_BODY_NOT_MEMORY", "FAILED_INPUT_NOT_MEMORY"))
    runtime.observations.update(real_file_effects=True, completed_tool_memory=True, failed_write_excluded=True,
                                raw_tool_bodies_excluded=True)
