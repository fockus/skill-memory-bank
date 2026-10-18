#!/usr/bin/env python3
"""Private, atomic completed-turn records; shared privacy and recent-file contracts."""
from __future__ import annotations

import contextlib
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "hooks/lib"))
from redact import redact_secrets  # noqa: E402

from memory_bank_skill.private import strip_private  # noqa: E402
from memory_bank_skill.semantic_search import Bm25Retriever  # noqa: E402

MAX = 1024 * 1024


def clean(text: str, limit: int = 8000) -> str:
    text = redact_secrets(strip_private(text)[0])
    return text[:limit]


def safe_read(file: Path, limit: int = 8000, *, base: Path) -> str:
    try:
        with contextlib.ExitStack() as stack:
            parent = os.open(base, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            stack.callback(os.close, parent)
            parts = file.relative_to(base).parts
            for part in parts[:-1]:
                parent = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                stack.callback(os.close, parent)
            fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            with os.fdopen(fd, "rb") as stream:
                info = os.fstat(stream.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_size > MAX:
                    return ""
                data = stream.read(MAX + 1)
                return clean(data.decode("utf-8"), limit) if len(data) <= MAX else ""
    except (OSError, UnicodeError, ValueError):
        return ""


def facts(text: str, *, fallback: bool = True) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {k: [] for k in ("What changed", "Decisions", "Open questions")}
    section = ""
    for line in text.splitlines():
        heading = re.match(r"^#{1,4}\s+(What changed|Decisions|Open questions)\s*$", line)
        if heading:
            section = heading[1]
            continue
        if line.startswith("#"):
            section = ""
        match = re.match(r"^\s*(?:[-*]\s*)?(Changed|What changed|Decision|Decided|Next|Pending|Open question|Unfinished|Решение|Решили|Осталось|Далее):\s*(.+)", line, re.I)
        if match:
            label = match[1].lower()
            key = "Decisions" if label in {"decision", "decided", "решение", "решили"} else "What changed" if label in {"changed", "what changed"} else "Open questions"
            result[key].append(match[2][:500])
        elif section and line.lstrip().startswith(("- ", "* ")):
            result[section].append(line.lstrip()[2:][:500])
    if fallback and not result["What changed"] and text.strip():
        result["What changed"].append("Assistant reported: " + re.sub(r"\s+", " ", text.strip())[:400])
    return result


def render(sid: str, state: dict, live: str) -> str:
    lines = ["---", "agent: opencode", f"session_id: {sid}", "transcript:",
             f"started: {state['started']}", "branch: -", f"turns: {len(state['seen'])}",
             f"last_turn: {state['seen'][-1]}", f"ended: {state['ended']}",
             "summarized: true", "summary_schema: v2", "summary_mode: extractive",
             "capture_state: " + json.dumps(state, ensure_ascii=True, separators=(",", ":")),
             "---", "", "## Live log", live, "", "## Summary",
             "Extracted public statements; no model call or inferred decisions."]
    for heading in ("What changed", "Decisions", "Open questions", "Files"):
        lines += ["", "### " + heading]
        lines += ["- " + value for value in state["facts"].get(heading, [])] or ["- (none)"]
    return "\n".join(lines) + "\n"


def recent_context(text: str, limit: int) -> str:
    headings = ("What changed", "Decisions", "Open questions", "Files")
    sections: dict[str, list[str]] = {key: [] for key in headings}
    blocks = re.split(r"(?m)^### (What changed|Decisions|Open questions|Files)\s*$", text)
    if len(blocks) == 1:
        return text[:limit]
    for i in range(1, len(blocks), 2):
        body = blocks[i + 1].split("\n## ", 1)[0]
        bullets = [line for line in body.splitlines() if line.startswith("- ")]
        sections[blocks[i]].extend(reversed(bullets))
    # Reserve each section independently; latest explicit work must outlive verbose changes.
    budget = (limit - sum(len(f"### {key}\n\n") for key in headings)) // len(headings)
    return "\n\n".join(f"### {key}\n" + "\n".join(dict.fromkeys(sections[key]))[:budget] for key in headings)


def recall(bank: Path, query: str) -> str:
    documents: list[dict] = []
    remaining = MAX // 2
    visited = 0
    for directory in ("notes", "session"):
        for file in (bank / directory).rglob("*.md"):
            visited += 1
            if visited > 1000 or remaining <= 0:
                return ""
            text = safe_read(file, min(8000, remaining), base=bank)
            if text:
                documents.append({"id": str(file.relative_to(bank)), "text": text})
                remaining -= len(text.encode())
    retriever = Bm25Retriever()
    retriever.index(documents)  # In-memory only; automatic recall never creates a persistent index.
    bodies = {doc["id"]: doc["text"] for doc in documents}
    return clean("\n\n".join(f"## {hit['id']}\n{bodies[hit['id']]}" for hit in retriever.search(query, k=3)))


def capture(bank: Path, sid: str, messages: list) -> dict:
    if os.environ.get("MB_SESSION_CAPTURE") == "off" or os.environ.get("MB_CAPTURE_SUBPROCESS"):
        return {"changed": False}
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", sid):
        raise ValueError("invalid session identity")
    bank_fd = os.open(bank, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    with contextlib.ExitStack() as stack:
        stack.callback(os.close, bank_fd)
        with contextlib.suppress(FileExistsError):
            os.mkdir("session", 0o700, dir_fd=bank_fd)
        directory = os.open("session", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=bank_fd)
        stack.callback(os.close, directory)
        digest = hashlib.sha256(sid.encode()).hexdigest()[:16]
        lock = os.open(f".oc-{digest}.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory)
        stack.callback(os.close, lock)
        if not stat.S_ISREG(os.fstat(lock).st_mode):
            raise ValueError("invalid lock")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        matches = [name for name in os.listdir(directory) if re.fullmatch(r"\d{4}-\d{2}-\d{2}_\d{4}_" + digest + r"\.md", name)]
        if len(matches) > 1:
            raise ValueError("ambiguous existing record")
        now = datetime.now(UTC).isoformat()
        name = matches[0] if matches else datetime.now(UTC).strftime("%Y-%m-%d_%H%M_") + digest + ".md"
        state = {"started": now, "ended": now, "seen": [], "facts": {}}
        live = ""
        if matches:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
            with os.fdopen(fd, "rb") as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode) or os.fstat(stream.fileno()).st_size > MAX:
                    raise ValueError("invalid record")
                original = stream.read(MAX + 1).decode("utf-8")
            head, body = original.split("\n---\n", 1)
            state = json.loads(next(line[15:] for line in head.splitlines() if line.startswith("capture_state: ")))
            live = body.split("## Live log\n", 1)[1].split("\n## Summary\n", 1)[0].strip("\n")
        changed = False
        user = None
        files: list[str] = []
        tools: list[str] = []
        turn_facts: dict[str, list[str]] = {}
        errors = 0
        for message in messages:
            if message.get("type") == "user":
                user = message
                files, tools, errors = [], [], 0
                turn_facts = facts(clean(message.get("text", "")), fallback=False)
            elif message.get("type") == "assistant" and user:
                raw = "\n".join(p.get("text", "") for p in message.get("content", []) if p.get("type") == "text")
                if len(raw) <= 65536:
                    for key, values in facts(clean(raw)).items():
                        turn_facts[key] = list(dict.fromkeys(turn_facts.get(key, []) + values))[-24:]
                files.extend(f for f in message.get("snapshot", {}).get("files", []) if isinstance(f, str))
                for part in message.get("content", []):
                    if part.get("type") == "tool" and isinstance(part.get("name"), str):
                        tools.append(clean(part["name"], 100))
                        tool_state = part.get("state", {})
                        status = tool_state.get("status")
                        errors += status == "error"
                        if status == "completed" and part["name"] in {"write", "edit"}:
                            target = tool_state.get("input", {}).get("path")
                            if isinstance(target, str):
                                files.append(target)
                            files.extend(item["file"] for item in tool_state.get("metadata", {}).get("files", [])
                                         if isinstance(item, dict) and isinstance(item.get("file"), str))
                if not message.get("time", {}).get("completed") or message.get("finish") not in {"stop", "length"}:
                    continue
                identity = message.get("id")
                if not isinstance(identity, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", identity) or identity in state["seen"]:
                    user = None
                    continue
                if len(raw) > 65536 or len(user.get("text", "")) > 65536:
                    continue
                answer, question = clean(raw), clean(user.get("text", ""), 400)
                if not question.strip() or (not answer.strip() and not files and not tools):
                    continue
                if not answer.strip():
                    answer = "(no public assistant text; native turn ended)"
                    turn_facts.setdefault("What changed", []).append("Native turn ended; file evidence is listed below.")
                extracted = turn_facts
                extracted["Files"] = list(dict.fromkeys(value for f in files if not re.search(r"(^|/)(\.env|credentials)(/|$|\.)", f) and (value := clean(f, 240))))[:24]
                for key, values in extracted.items():
                    state["facts"][key] = list(dict.fromkeys(state["facts"].get(key, []) + values))[-24:]
                outcome = f"err({errors})" if errors else "ok"
                entry = f'- {datetime.now(UTC):%H:%M} — User: "{question}" · Assistant: "{answer[:1200]}" · tools: {", ".join(dict.fromkeys(tools)) or "(none)"} · files: {", ".join(extracted["Files"]) or "(none)"} · {outcome}'
                live += ("\n" if live else "") + re.sub(r"\s+", " ", entry)
                state["seen"].append(identity)
                state["ended"] = now
                changed = True
                user = None
        if not changed:
            return {"changed": False}
        # ponytail: a 1 MiB per-session ceiling; add indexed parts before supporting longer sessions.
        text = render(sid, state, live)
        if len(text.encode()) > MAX:
            raise ValueError("session capacity reached")
        temporary = ".oc-" + uuid.uuid4().hex + ".tmp"
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(text)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
            os.fsync(directory)
        finally:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(temporary, dir_fd=directory)
        return {"changed": True, "file": str(bank / "session" / name)}


def main() -> int:
    try:
        action = sys.argv[1]
        if action == "filter":
            text = sys.stdin.read(512 * 1024 + 1)
            if len(text) > 512 * 1024:
                raise ValueError("oversize filter input")
            print(clean(text))
        elif action == "restore":
            bank = Path(sys.argv[2])
            for name, cap in (("session/_recent.md", 4000), ("handoff/latest.md", 1500)):
                text = safe_read(bank / name, MAX if name.startswith("session/") else cap, base=bank)
                if name.startswith("session/"):
                    text = recent_context(text, cap)
                if text:
                    print(f"## {name}\n{text}")
        elif action == "capture":
            data = json.loads(sys.stdin.read(512 * 1024 + 1))
            if not isinstance(data, list) or len(data) > 128:
                raise ValueError("invalid capture batch")
            print(json.dumps(capture(Path(sys.argv[2]), sys.argv[3], data)))
        elif action == "recall":
            print(recall(Path(sys.argv[2]), clean(sys.stdin.read(501), 500)))
        else:
            raise ValueError("unknown memory operation")
    except (OSError, ValueError, TypeError, KeyError, StopIteration, IndexError):
        print('{"changed":false,"error":"Memory Bank capture unavailable; retry after checking storage and limits."}')
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
