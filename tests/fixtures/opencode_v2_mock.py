"""Private V2 HTTP runtime; only the external model boundary is simulated."""

from __future__ import annotations

import base64
import contextlib
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[2]
CLI = shutil.which("opencode")


class NativeRuntime:
    """Own HOME/XDG/db, finite model requests, private loopback listener and process group."""

    def __init__(self, root: Path, respond: Callable[[dict], dict], *, evidence_root: Path | None = None) -> None:
        self.root, self.project = root, root / "home/project"
        self.project.mkdir(parents=True)
        self.evidence_root = evidence_root or root
        if override := os.environ.get("MB_TEST_EVIDENCE_DIR"):
            self.evidence_root = Path(override) / self.evidence_root.parent.name
        self.evidence_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.requests: list[dict] = []
        self.errors: list[str] = []
        self.respond = respond
        self.tag = "native"
        self.env = {"HOME": str(root / "home"), "PATH": os.pathsep.join([str(Path(sys.executable).parent), os.environ.get("PATH", os.defpath)]),
                    "LANG": "en_US.UTF-8", "SHELL": "/bin/bash", "TMPDIR": str(root),
                    "MB_UPDATE_NOTIFY": "off", "MB_AUTO_REFRESH": "off", "MB_SEMANTIC": "off",
                    "MB_GRAPH_AUTOUPDATE": "off", "MB_GRAPH_CATCHUP": "off", "MB_AUTO_CAPTURE": "off",
                    "MB_AGENT": "opencode", "MB_PIPELINE_HOST": "opencode",
                    "OPENCODE_DB": str(root / "private.db"), "OPENCODE_LOG_LEVEL": "error"}
        for key in ("CONFIG", "DATA", "STATE", "CACHE"):
            self.env[f"XDG_{key}_HOME"] = str(root / key.lower())
        self.server: subprocess.Popen | None = None
        self.owned: set[int] = set()
        self.stop_observer = threading.Event()
        self.observer: threading.Thread | None = None
        self.log = None
        self.provider = self._provider()

    def _provider(self) -> ThreadingHTTPServer:
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args) -> None:
                return

            def do_POST(self) -> None:
                try:
                    self.connection.settimeout(10)
                    if self.path != "/v1/chat/completions":
                        raise AssertionError(f"unexpected provider path {self.path}")
                    size = int(self.headers.get("Content-Length", "0"))
                    if size > 2_000_000 or len(owner.requests) >= 48:
                        raise AssertionError("fixture request budget exhausted")
                    request = json.loads(self.rfile.read(size))
                    owner.requests.append(request)
                    answer = owner.respond(request)
                    packet = {"id": f"fixture-{len(owner.requests)}", "object": "chat.completion.chunk",
                              "created": 1, "model": request["model"], "choices": [
                                  {"index": 0, "delta": answer,
                                   "finish_reason": "tool_calls" if "tool_calls" in answer else "stop"}]}
                    data = f"data: {json.dumps(packet)}\n\ndata: [DONE]\n\n".encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except Exception as exc:
                    owner.errors.append(str(exc))
                    self.send_error(400, "fixture contract refused")

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server

    def install(self, pipeline: str) -> None:
        bank = self.project / ".memory-bank"
        bank.mkdir(exist_ok=True)
        (bank / "pipelines").mkdir()
        (bank / "pipelines/fixture.yaml").write_text("agents: [opencode]\n" + pipeline)
        (bank / "pipeline.yaml").write_text(pipeline.replace("fixture/team/coder#deep", "unselected/model"))
        (bank / "status.md").write_text("# Native fixture task: repair the greeting\n")
        (bank / "progress.md").write_text("# Progress\n")
        (bank / "checklist.md").write_text("# Checklist\n")
        (self.project / "AGENTS.md").write_text(
            "# Project fixture instructions\nPROJECT_NATIVE_RULE_SENTINEL\n")
        config = Path(self.env["XDG_CONFIG_HOME"]) / "opencode"
        config.mkdir(parents=True)
        (config / "AGENTS.md").write_text(
            "<!-- mb-key-rules:start -->\nGLOBAL_NATIVE_RULE_SENTINEL\n<!-- mb-key-rules:end -->\n")
        result = subprocess.run(
            ["bash", str(ROOT / "adapters/opencode.sh"), "install", str(self.project)],
            env={**self.env, "MB_OC_PARITY_ACCEPTED": "1"}, capture_output=True, text=True, timeout=60,
        )
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def start(self) -> None:
        assert CLI, "OpenCode V2 is required; no native acceptance without it"
        # Ordinary discovery walks to /. Refuse unexpected ancestor inputs, never read/copy them.
        for ancestor in self.project.parents:
            for name in ("opencode.json", "opencode.jsonc", ".opencode", "AGENTS.md"):
                if ancestor != self.root / "home" and (ancestor / name).exists():
                    raise AssertionError(f"unexpected ancestor discovery input: {ancestor / name}")
        self.log = (self.root / "server.log").open("w")
        self.server = subprocess.Popen(
            [CLI, "serve", "--hostname", "127.0.0.1", "--port", "0"], cwd=self.project,
            env=self.env, stdout=self.log, stderr=self.log, start_new_session=True,
        )
        self.owned.add(self.server.pid)
        self.observer = threading.Thread(target=self.observe, daemon=True)
        self.observer.start()
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            text = (self.root / "server.log").read_text()
            found = re.search(r"http://127\.0\.0\.1:\d+", text)
            password = re.search(r"server password[: ]+(\S+)", text)
            if found and password:
                self.url = found[0]
                self.authorization = "Basic " + base64.b64encode(f"opencode:{password[1]}".encode()).decode()
                info = self.api("GET", "/api/info")
                assert isinstance(info, dict) and isinstance(info.get("pid"), int) and info["pid"] > 1
                self.owned.add(info["pid"])
                self.version = info["version"]
                self.catalogs()
                return
            if self.server.poll() is not None:
                raise AssertionError(f"private server failed: {text[-2000:]}")
            time.sleep(0.1)
        detail = re.sub(r"server password[^\n]*", "server password [REDACTED]", (self.root / "server.log").read_text())
        (self.evidence_root / "mb-stage4-startup-error.log").write_text(detail)
        raise AssertionError(f"private server startup timed out: {detail[-2000:]}")

    def observe(self) -> None:
        # Same accepted limit as bundled hooks: groups plus observed ancestry, not an OS sandbox.
        while not self.stop_observer.is_set():
            result = subprocess.run(["ps", "-ax", "-o", "pid=,ppid="], capture_output=True, text=True, timeout=1)
            rows = [tuple(map(int, line.split())) for line in result.stdout.splitlines()]
            for _ in range(len(rows)):
                found = {child for child, parent in rows if parent in self.owned}
                if found <= self.owned:
                    break
                self.owned.update(found)
            self.stop_observer.wait(0.05)

    def catalogs(self) -> None:
        query = "?" + urlencode({"location[directory]": str(self.project)})
        expected_roles = {p.stem for p in (ROOT / "agents").glob("*.md")
                          if not re.search(r"(?mi)^partial:\s*true\s*$", p.read_text().split("\n---\n", 1)[0])}
        expected_commands = {p.stem for p in (ROOT / "commands").glob("*.md")}
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            plugins = self.data("/api/plugin" + query)
            agents = self.data("/api/agent" + query)
            commands = self.data("/api/command" + query)
            active = any(p["id"] == "memory-bank" and p["state"]["status"] == "active" for p in plugins)
            bound = all(any(c["name"] == name and c.get("description", "").startswith("[MB native]") for c in commands) for name in ("mb", "work"))
            if active and bound and expected_roles <= {a["id"] for a in agents} and expected_commands <= {c["name"] for c in commands}:
                assert len({a["id"] for a in agents}) == len(agents)
                assert len({c["name"] for c in commands}) == len(commands)
                for agent in agents:
                    if agent["id"] not in expected_roles:
                        continue
                    rendered = (self.project / ".opencode/agent" / f"{agent['id']}.md").read_text()
                    color = re.search(r'^color: "(#[0-9a-fA-F]{6})"$', rendered, re.M)
                    if color:
                        assert agent["color"] == color[1]
                self.catalog = {"roles": len(expected_roles), "commands": len(expected_commands), "plugin": "active", "binding": "native", "version": self.version}
                return
            time.sleep(0.1)
        raise AssertionError("native discovery/binding exceeded 15s; expected source roster and native command descriptions")

    def data(self, path: str):
        result = self.api("GET", path)
        if not isinstance(result, dict) or "data" not in result:
            raise AssertionError(f"missing native data envelope: {path}")
        return result["data"]

    def api(self, method: str, path: str, data: dict | None = None):
        request = urllib.request.Request(self.url + path, method=method,
                                         data=json.dumps(data).encode() if data is not None else None,
                                         headers={"Content-Type": "application/json", "Authorization": self.authorization})
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request, timeout=20) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"private API {exc.code}: {exc.read(4000).decode()}") from None

    def wait(self, sid: str, *, after_idle=None) -> dict:
        deadline = time.monotonic() + 70
        while time.monotonic() < deadline:
            info = self.data(f"/api/session/{sid}")
            idle = info.get("time", {}).get("idle")
            if idle and idle != after_idle:
                return info
            if self.errors:
                raise AssertionError(self.errors)
            time.sleep(0.1)
        raise AssertionError("native session exceeded 70s budget")

    def states(self) -> list[dict]:
        result = subprocess.run(["bash", str(ROOT / "scripts/mb-work-state.sh"), "status", "--all", "--mb", str(self.project / ".memory-bank")],
                                cwd=self.project, env=self.env, capture_output=True, text=True, check=True, timeout=10)
        return json.loads(result.stdout)

    def save_evidence(self, source: Path | None = None) -> None:
        if self.server:
            query = "?" + urlencode({"directory": str(self.project)})
            sessions = self.data("/api/session" + query)
            contexts = {s["id"]: self.data(f'/api/session/{s["id"]}/context') for s in sessions}
            (self.evidence_root / f"{self.tag}-contexts.json").write_text(json.dumps(contexts, indent=2))
            live = self.states()
            completed = self.project / "completed-state.json"
            source = source or self.project / ".memory-bank/specs/greeting/tasks.md"
            evidence = {"catalog": self.catalog, "sessions": sessions,
                        "model_requests": [{"model": r["model"], "variant_option": r.get("fixture_variant"),
                                            "tools": [t["function"]["name"] for t in r.get("tools", [])],
                                            "global_rule": "GLOBAL_NATIVE_RULE_SENTINEL" in str(r["messages"]),
                                            "project_rule": "PROJECT_NATIVE_RULE_SENTINEL" in str(r["messages"])} for r in self.requests],
                        "tool_messages": {sid: [m for m in messages if m["type"] == "assistant"] for sid, messages in contexts.items()},
                         "work_state": json.loads(completed.read_text()) if completed.exists() and completed.read_text().strip() else live[0] if len(live) == 1 else None,
                         "live_states": live,
                         "retained_states": [json.loads(p.read_text()) for p in (self.project / ".memory-bank/.work-completed").glob("*.json")],
                         "files": {str(p.relative_to(self.project)): {"sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "text": p.read_text()} for p in
                                   [source, source.parent / "requirements.md", source.parent / "design.md", *[self.project / name for name in ("product.py", "check_product.py", "eval.cmd", "first.py", "second.py", "check_first.py", "check_second.py", "run-id", "completed-state.json")]] if p.is_file()},
                         "tasks": source.read_text() if source.exists() else None}
            (self.evidence_root / f"mb-stage4-{self.tag}-evidence.json").write_text(json.dumps(evidence, indent=2))

    def close(self) -> None:
        if hasattr(self, "catalog") and not (self.evidence_root / f"mb-stage4-{self.tag}-evidence.json").exists():
            try:
                self.save_evidence()
            except Exception as exc:
                (self.evidence_root / "snapshot-error.txt").write_text(type(exc).__name__)
        if self.server:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(self.server.pid, signal.SIGTERM)
            try:
                self.server.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(self.server.pid, signal.SIGKILL)
                self.server.wait(timeout=4)
        self.stop_observer.set()
        if self.observer:
            self.observer.join(timeout=2)
            assert not self.observer.is_alive(), "fixture ancestry observer did not stop"
        for pid in self.owned:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(pid, signal.SIGKILL)
            with contextlib.suppress(ProcessLookupError):
                os.kill(pid, signal.SIGKILL)
        self.provider.shutdown()
        self.provider.server_close()
        if self.log:
            self.log.close()
            text = re.sub(r"server password[^\n]*", "server password [REDACTED]", (self.root / "server.log").read_text())
            (self.evidence_root / f"{self.tag}-server.log").write_text(text)
        (self.evidence_root / f"{self.tag}-cleanup.json").write_text(json.dumps({"owned_pids": sorted(self.owned),
            "observer_stopped": not self.observer or not self.observer.is_alive(), "server_exit": self.server.returncode if self.server else None}))


def tool(request: dict, fields: set[str], values: dict) -> dict:
    """Choose from the actual requested tool schemas, not a guessed namespace prefix."""
    candidates = []
    for item in request.get("tools", []):
        function = item.get("function", {})
        properties = function.get("parameters", {}).get("properties", {})
        if fields <= properties.keys():
            candidates.append(function["name"])
    if len(candidates) != 1:
        raise AssertionError(f"no unique native tool for {sorted(fields)}; catalog="
                             f"{[t.get('function', {}).get('name') for t in request.get('tools', [])]}")
    return {"tool_calls": [{"index": 0, "id": f"call-{time.monotonic_ns()}", "type": "function",
                            "function": {"name": candidates[0], "arguments": json.dumps(values)}}]}
