"""D02-D06 native tool acceptance; only the loopback model boundary is simulated."""

import hashlib
import json
import os
import re
import shlex
import shutil
import time
from pathlib import Path

import pytest
from test_opencode_v2_native import PIPELINE, ROOT, configure, fixture


def scrub(text, secrets=()):
    text = re.sub(r"<private>.*?</private>", "[PRIVATE]", text, flags=re.S | re.I)
    text = re.sub(r"server password[^\n]*", "server password [REDACTED]", text, flags=re.I)
    for secret in secrets:
        text = text.replace(secret, "[REDACTED]")
    return text


class AcceptanceRuntime(fixture.NativeRuntime):
    """Keep the existing cleanup, but never serialize original conversation inputs."""

    def save_evidence(self, source=None):
        target = self.evidence_root / f"mb-stage4-{self.tag}-evidence.json"
        evidence = {"catalog": getattr(self, "catalog", None), "requests": len(self.requests),
                    "models": sorted({r["model"] for r in self.requests}), "provider_errors": self.errors,
                    "observations": self.observations, "source_sha256": self.source_hashes}
        target.write_text(scrub(json.dumps(evidence, indent=2), self.secrets))
        target.chmod(0o600)
        sessions, tools, compactions = [], {}, {}
        if self.server and self.server.poll() is None and hasattr(self, "url"):
            sessions = self.data("/api/session")
            for session in sessions:
                messages = self.data(f'/api/session/{session["id"]}/context')
                tools[session["id"]] = [{"tool": p.get("name", p.get("tool")), "status": p["state"]["status"],
                    "exit": p["state"].get("metadata", {}).get("exit")}
                    for m in messages if m["type"] == "assistant" for p in m["content"] if p["type"] == "tool"]
                compactions[session["id"]] = [{k: m[k] for k in ("id", "status", "reason")}
                    for m in messages if m["type"] == "compaction"]
        evidence.update({
            "sessions": [{k: s.get(k) for k in ("id", "parentID", "location", "model", "agent")} for s in sessions],
            "tools": tools, "compactions": compactions, "source_sha256": self.source_hashes,
        })
        target.write_text(scrub(json.dumps(evidence, indent=2), self.secrets))
        target.chmod(0o600)


@pytest.fixture
def native(tmp_path, monkeypatch):
    bundle = tmp_path / "bundle"
    bundle.mkdir(mode=0o700)
    ignored = shutil.ignore_patterns(".git", ".env*", ".memory-bank", "node_modules", "__pycache__")
    for name in ("adapters", "agents", "commands", "hooks", "scripts", "rules", "references",
                 "templates", "flow-templates", "settings", "memory_bank_skill"):
        shutil.copytree(ROOT / name, bundle / name, ignore=ignored, symlinks=True)
    for name in ("install.sh", "uninstall.sh", "VERSION", "SKILL.md"):
        shutil.copy2(ROOT / name, bundle / name)
    assert all(p.resolve().is_relative_to(bundle.resolve()) for p in bundle.rglob("*") if p.is_symlink()), "Bundle contains an external alias"
    exported = os.environ.get("MB_TEST_EVIDENCE_DIR")
    monkeypatch.delenv("MB_TEST_EVIDENCE_DIR", raising=False)
    monkeypatch.setattr(fixture, "ROOT", bundle)
    runtime = AcceptanceRuntime(tmp_path / "runtime", lambda _: {"content": "Public reply."},
                                evidence_root=tmp_path / "diagnostics")
    runtime.secrets, runtime.observations = [], {}
    runtime.source_hashes = {str(p.relative_to(bundle)): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in bundle.rglob("*") if p.is_file()}
    runtime.env.update({"CODEX_HOME": str(runtime.root / "codex"),
                        "MB_MANIFEST_PATH": str(runtime.root / "install-manifest.json"),
                        "MB_USER_RULES_AUTO_PROMPT": "off"})
    for name in ("XDG_RUNTIME_DIR", "XDG_CONFIG_DIRS", "XDG_DATA_DIRS"):
        runtime.env[name] = str(runtime.root / name.lower())
        Path(runtime.env[name]).mkdir(mode=0o700)
    try:
        runtime.install(PIPELINE)
        configure(runtime)
        yield runtime, bundle
    finally:
        try:
            runtime.close()
        finally:
            authorization = getattr(runtime, "authorization", "")
            secrets = [*runtime.secrets, authorization, authorization.removeprefix("Basic "), "fixture-not-a-secret"]
            secrets = [secret for secret in secrets if secret]
            log = runtime.root / "server.log"
            diagnostic_leak = log.exists() and any(s in log.read_text() for s in runtime.secrets)
            destination = Path(exported) / tmp_path.name if exported else tmp_path / "sanitized"
            destination.mkdir(parents=True, exist_ok=True, mode=0o700)
            for file in runtime.evidence_root.glob("*"):
                if file.is_file():
                    cleaned = scrub(file.read_text(), secrets)
                    file.write_text(cleaned)
                    file.chmod(0o600)
                    output = destination / file.name
                    output.write_text(cleaned)
                    output.chmod(0o600)
            if log.exists():
                log.write_text(scrub(log.read_text(), secrets))
                log.chmod(0o600)
            assert not diagnostic_leak, "Private input leaked into process diagnostics"
        assert len(runtime.errors) == 0, "Loopback model fixture contract failed"
        assert len(runtime.requests) <= 48


def until(predicate, label, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"Native acceptance timed out: {label}")


def new_root(runtime, **extra):
    return runtime.api("POST", "/api/session", {
        "location": {"directory": str(runtime.project)}, "title": "Public acceptance fixture",
        "model": {"providerID": "fixture", "id": "team/parent", "variant": "parent"}, **extra,
    })["data"]["id"]


def prompt(runtime, sid, text):
    before = runtime.data(f"/api/session/{sid}").get("time", {}).get("idle")
    runtime.api("POST", f"/api/session/{sid}/prompt", {"text": text})
    return runtime.wait(sid, after_idle=before)


def scripted(actions, final="Public native turn completed."):
    pending = iter(actions)

    def respond(request):
        if any("Return only the structured summary in the requested format." in str(m.get("content", ""))
               for m in request["messages"] if m["role"] == "user"):
            return {"content": "## Objective\n- Verify native continuation.\n\n## Work State\n### Active\n- Verify remaining native work.\n\n## Next Move\n1. Explicitly resume the canonical item."}
        if not request.get("tools"):
            return {"content": "## Objective\nPreserve public work.\n## Next Move\nContinue verification."}
        action = next(pending, None)
        return fixture.tool(request, *action) if action else {"content": final}

    return respond


def tool_states(runtime, sid):
    return [p["state"] for m in runtime.data(f"/api/session/{sid}/context")
            if m["type"] == "assistant" for p in m["content"] if p["type"] == "tool"]


def system_text(request):
    return "\n".join(str(m.get("content", "")) for m in request["messages"] if m["role"] == "system")


def observe(bundle, relative, receipt):
    original = bundle / relative
    saved = original.with_suffix(".observed.sh")
    original.rename(saved)
    original.write_text(f"#!/bin/bash\nprintf '%s\\n' {shlex.quote(relative)} >> {shlex.quote(str(receipt))}\n"
                        f"exec bash {shlex.quote(str(saved))} \"$@\"\n")
    original.chmod(0o755)


@pytest.mark.parametrize("kind", ["write", "shell"])
def test_native_guard_blocks_before_file_effect_then_allows_safe_action(native, kind):
    runtime, _ = native
    project, bank = runtime.project, runtime.project / ".memory-bank"
    selected = bank / "pipelines/fixture.yaml"
    selected.write_text(selected.read_text() + "\nprotected_paths: [secret/**]\n")
    (project / "secret").mkdir()
    denied, allowed = project / "secret/value.txt", project / "allowed.txt"
    denied.write_text("Original user bytes.\n")
    if kind == "write":
        actions = [({"path", "content"}, {"path": str(p), "content": "native effect\n"}) for p in (denied, allowed)]
    else:
        actions = [({"command"}, {"command": f"printf 'native effect\\n' > {shlex.quote(str(p))}",
                                  "workdir": str(project)}) for p in (denied, allowed)]
    runtime.respond = scripted(actions)
    runtime.start()
    sid = new_root(runtime)
    prompt(runtime, sid, "Attempt the forbidden action, then the safe control.")
    states = tool_states(runtime, sid)
    assert len(states) == 2 and [s["status"] for s in states] == ["error", "completed"]
    assert "BLOCKED" in json.dumps(states[0])
    assert denied.read_text() == "Original user bytes.\n"
    assert allowed.read_text() == "native effect\n"
    runtime.observations.update(guard=kind, forbidden_unchanged=True, safe_effect=True)


def test_native_budget_blocks_child_before_effect_then_allows_owned_child(native):
    runtime, _ = native
    spend = runtime.project / ".memory-bank/.session-spend.json"
    spend.write_text(json.dumps({"total_estimate_tokens": 100, "soft_warn_tokens": 1, "hard_stop_tokens": 2}))
    dispatch = ({"agent", "prompt"}, {"agent": "mb-developer", "description": "Owned child control",
                                    "prompt": "Write allowed-child.txt with public bytes."})
    root_reply = scripted([dispatch])
    child_reply = scripted([({"path", "content"}, {"path": str(runtime.project / "allowed-child.txt"), "content": "child executed\n"})])

    def respond(request):
        return child_reply(request) if "# MB Developer — Subagent Prompt" in system_text(request) else root_reply(request)

    runtime.respond = respond
    runtime.start()
    sid = new_root(runtime)
    prompt(runtime, sid, "Attempt the budget-protected child.")
    assert tool_states(runtime, sid)[0]["status"] == "error"
    assert "BLOCKED" in json.dumps(tool_states(runtime, sid)[0])
    assert not (runtime.project / "allowed-child.txt").exists()
    assert not any(s.get("parentID") == sid for s in runtime.data("/api/session"))
    assert not any("# MB Developer — Subagent Prompt" in system_text(r) for r in runtime.requests)
    spend.write_text(json.dumps({"total_estimate_tokens": 0, "soft_warn_tokens": 100000, "hard_stop_tokens": 200000}))
    root_reply = scripted([dispatch])
    prompt(runtime, sid, "Now run the same child with a sufficient budget.")
    assert tool_states(runtime, sid)[-1]["status"] == "completed"
    assert (runtime.project / "allowed-child.txt").read_text() == "child executed\n"
    runtime.observations.update(budget_refused_before_dispatch=True, allowed_child_effect=True)


def test_native_optional_recall_failure_does_not_block_real_write(native):
    runtime, bundle = native
    runtime.env["MB_SEMANTIC"] = "auto"
    notes = runtime.project / ".memory-bank/notes"
    notes.mkdir()
    (notes / "public.md").write_text("# Native resolver reliability decision\nKeep the shared resolver.\n")
    helper = bundle / "adapters/opencode_memory.py"
    original = helper.with_suffix(".real.py")
    helper.rename(original)
    attempts = runtime.root / "memory-helper-attempts.jsonl"
    helper.write_text("import json, os, sys\n"
                      f"with open({str(attempts)!r}, 'a') as stream: stream.write(json.dumps(sys.argv[1]) + '\\n')\n"
                      "if sys.argv[1] == 'recall': raise SystemExit(75)\n"
                      f"os.execv(sys.executable, [sys.executable, {str(original)!r}, *sys.argv[1:]])\n")
    helper.chmod(0o755)
    target = runtime.project / "recall-failure-control.txt"
    runtime.respond = scripted([({"path", "content"}, {"path": str(target), "content": "safe progress\n"})])
    runtime.start()
    sid = new_root(runtime)
    prompt(runtime, sid, "Recall the native resolver reliability decision and continue safe work.")
    assert target.read_text() == "safe progress\n"
    assert tool_states(runtime, sid)[0]["status"] == "completed"
    until(lambda: attempts.exists() and '"capture"' in attempts.read_text(), "real capture delegation after recall failure")
    actions = [json.loads(line) for line in attempts.read_text().splitlines()]
    assert actions.count("recall") == 1
    assert {"filter", "restore", "capture"} <= set(actions)
    assert not (runtime.project / ".memory-bank/.index").exists()
    runtime.observations.update(optional_recall_failure_allowed_effect=True, recall_attempts=1,
                                other_memory_actions_delegated=sorted(set(actions) - {"recall"}))


def test_native_multifile_patch_syncs_both_plans_and_finalizes_once(native):
    runtime, bundle = native
    config_file = runtime.project / "opencode.json"
    config = json.loads(config_file.read_text())
    model = dict(config["providers"]["fixture"]["models"]["team/parent"], modelID="gpt-5")
    config["providers"]["fixture"]["models"]["gpt-5"] = model
    config_file.write_text(json.dumps(config))
    bank = runtime.project / ".memory-bank"
    (bank / "plans").mkdir()
    (bank / "roadmap.md").write_text("# Roadmap\n")
    plans = [bank / "plans" / f"2026-10-17_feature_{name}.md" for name in ("first", "second")]
    for plan in plans:
        plan.write_text(f"---\nstatus: in_progress\n---\n# {plan.stem}\n<!-- mb-stage:1 -->\n### Stage 1: Work\n- [ ] Verify native output\n")
    receipt = runtime.root / "sync-receipt"
    for relative in ("hooks/mb-plan-sync-post-write.sh", "scripts/mb-plan-sync.sh",
                     "scripts/mb-roadmap-sync.sh", "scripts/mb-traceability-gen.sh"):
        observe(bundle, relative, receipt)
    patch = "*** Begin Patch\n" + "".join(f"*** Update File: {p}\n@@\n-### Stage 1: Work\n+### Stage 1: Native output\n" for p in plans) + "*** End Patch"
    runtime.respond = scripted([({"patchText"}, {"patchText": patch})])
    runtime.start()
    sid = new_root(runtime, model={"providerID": "fixture", "id": "gpt-5"})
    prompt(runtime, sid, "Apply this one multi-file native patch.")
    assert tool_states(runtime, sid)[0]["status"] == "completed"
    assert all("### Stage 1: Native output" in p.read_text() for p in plans)
    checklist = (bank / "checklist.md").read_text()
    assert all(f"mb-plan:{p.name}" in checklist for p in plans)
    assert checklist.count("- ⬜ Stage 1 — Native output") == 2
    assert receipt.read_text().splitlines() == ["hooks/mb-plan-sync-post-write.sh", "scripts/mb-plan-sync.sh",
                                               "scripts/mb-plan-sync.sh", "scripts/mb-roadmap-sync.sh", "scripts/mb-traceability-gen.sh"]
    assert all(p.stem in (bank / "roadmap.md").read_text() for p in plans)
    assert "# Traceability Matrix" in (bank / "traceability.md").read_text()
    runtime.observations.update(plans_synced=2, shared_chain_passes=1,
                                patch_sha256=hashlib.sha256(patch.encode()).hexdigest())
