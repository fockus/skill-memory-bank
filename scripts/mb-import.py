#!/usr/bin/env python3
"""Claude Code JSONL → Memory Bank bootstrap importer.

Usage:
    mb-import.py --project <proj_dir> [--since YYYY-MM-DD] [--apply] [mb_path]

Reads ``<proj_dir>/*.jsonl`` (Claude Code session transcripts) and extracts:
    - ``progress.md``: daily-grouped summaries (append-only, dedup by SHA256).
    - ``notes/``: heuristic architectural discussions (≥3 consecutive
      assistant messages > 1K chars).
    - ``lessons.md``: TODO (v2.2+) — debug-session pattern detection.

Safety:
    - ``--dry-run`` (default): no file changes, stdout summary only.
    - ``--apply``: writes progress + notes + ``.import-state.json``.
    - PII auto-wrap: email + API-key patterns wrapped in ``<private>…</private>``.
    - Dedup: SHA256(timestamp + first 500 chars of text) persisted across runs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

# ═══ PII patterns — conservative, low false-positive ═══
EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
# API keys: sk-..., sk-ant-..., Bearer <long>, gh[pousr]_<long>
APIKEY_RE = re.compile(
    r"\b(?:sk-(?:ant-)?[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{16,}|gh[pousr]_[A-Za-z0-9]{20,})\b"
)

NOTE_MIN_MSG_LEN = 1000
NOTE_MIN_CONSECUTIVE = 3


def iter_events(jsonl_path: Path) -> Iterator[dict[str, Any]]:
    """Yield parsed events from JSONL file. Skip broken lines with stderr warning."""
    try:
        with jsonl_path.open("r", encoding="utf-8") as f:
            for lineno, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    print(
                        f"[warn] {jsonl_path.name}:{lineno} — broken JSON, skipped",
                        file=sys.stderr,
                    )
    except OSError as e:
        print(f"[warn] cannot read {jsonl_path}: {e}", file=sys.stderr)


def event_text(event: dict[str, Any]) -> str:
    """Extract textual content from message.content — concatenate text blocks."""
    msg = event.get("message", {})
    content = msg.get("content", [])
    if isinstance(content, str):
        return content
    parts: list[str] = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
    return "\n".join(parts)


def event_hash(event: dict[str, Any]) -> str:
    """SHA256 of (timestamp + first 500 chars of text) — stable dedup key."""
    ts = event.get("timestamp", "")
    text = event_text(event)[:500]
    return hashlib.sha256(f"{ts}|{text}".encode()).hexdigest()[:16]


def wrap_pii(text: str) -> str:
    """Wrap email/API-key matches in <private>...</private> if not already."""
    def wrap(m: re.Match[str]) -> str:
        match = m.group(0)
        # Idempotent: if already inside <private>, leave alone (rough heuristic).
        start = m.start()
        prefix = text[:start]
        if prefix.rfind("<private>") > prefix.rfind("</private>"):
            return match
        return f"<private>{match}</private>"
    out = EMAIL_RE.sub(wrap, text)
    out = APIKEY_RE.sub(wrap, out)
    return out


def event_day(event: dict[str, Any]) -> str | None:
    """ISO date (YYYY-MM-DD) from timestamp, or None if missing."""
    ts = event.get("timestamp", "")
    if not ts or len(ts) < 10:
        return None
    return ts[:10]


def filter_since(events: list[dict[str, Any]], since: str | None) -> list[dict[str, Any]]:
    if not since:
        return events
    return [e for e in events if (event_day(e) or "") >= since]


def collect_arch_discussions(events: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    """Find runs of ≥N consecutive assistant messages with text > M chars."""
    runs: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []
    for e in events:
        if e.get("type") == "assistant" and len(event_text(e)) > NOTE_MIN_MSG_LEN:
            current.append(e)
        else:
            if len(current) >= NOTE_MIN_CONSECUTIVE:
                runs.append(current)
            current = []
    if len(current) >= NOTE_MIN_CONSECUTIVE:
        runs.append(current)
    return runs


def summarize_day(events: list[dict[str, Any]]) -> str:
    """1-line summary of a day's activity — user turns + assistant message counts."""
    users = sum(1 for e in events if e.get("type") == "user")
    assistants = sum(1 for e in events if e.get("type") == "assistant")
    # Snapshot of the first user query as a context anchor
    first_user = next((e for e in events if e.get("type") == "user"), None)
    if first_user:
        first_text = event_text(first_user)[:120].replace("\n", " ").strip()
    else:
        first_text = "(no user prompts)"
    return f"{users} user turns, {assistants} assistant replies. First prompt: {first_text}"


def _slugify(text: str, max_len: int = 40) -> str:
    slug = re.sub(r"[^\w\s-]", "", text.lower())
    slug = re.sub(r"[-\s]+", "-", slug).strip("-")
    return slug[:max_len] or "discussion"


def _compress_arch_run(run: list[dict[str, Any]]) -> str:
    """First 150 chars of first message + '...' + first 150 chars of last message."""
    first = event_text(run[0])[:150].strip()
    last = event_text(run[-1])[:150].strip()
    if len(run) == 1:
        return first
    return f"{first}\n\n…\n\n{last}"


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def _load_state(mb_path: Path) -> dict[str, Any]:
    state_file = mb_path / ".import-state.json"
    if not state_file.exists():
        return {"seen_hashes": [], "last_run": None}
    try:
        return json.loads(state_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"seen_hashes": [], "last_run": None}


def _save_state(mb_path: Path, state: dict[str, Any]) -> None:
    state_file = mb_path / ".import-state.json"
    _atomic_write(state_file, json.dumps(state, indent=2, ensure_ascii=False))


def run_import(
    *,
    mb_path: str,
    project_dir: str,
    mode: str = "dry-run",
    since: str | None = None,
) -> dict[str, Any]:
    """Main import entry. Returns summary dict with counts."""
    mb = Path(mb_path)
    proj = Path(project_dir)
    if not mb.is_dir():
        raise FileNotFoundError(f"mb_path not found: {mb}")
    if not proj.is_dir():
        raise FileNotFoundError(f"project_dir not found: {proj}")

    jsonls = sorted(proj.glob("*.jsonl"))
    if not jsonls:
        return {"jsonls": 0, "events": 0, "days": 0, "notes": 0, "mode": mode}

    state = _load_state(mb) if mode == "apply" else {"seen_hashes": [], "last_run": None}
    seen = set(state.get("seen_hashes", []))

    # Collect all events across all JSONL files, apply dedup + since
    all_events: list[dict[str, Any]] = []
    for jsonl in jsonls:
        for ev in iter_events(jsonl):
            if ev.get("type") not in ("user", "assistant"):
                continue
            if not event_day(ev):
                continue
            h = event_hash(ev)
            if h in seen:
                continue
            all_events.append(ev)
    all_events = filter_since(all_events, since)

    # Group by day
    by_day: dict[str, list[dict[str, Any]]] = {}
    for ev in all_events:
        day = event_day(ev)
        if day is None:
            continue
        by_day.setdefault(day, []).append(ev)

    # Architectural discussions (per day, so they do not merge together)
    notes_to_write: list[tuple[str, str]] = []  # (filename, content)
    for day, events in by_day.items():
        runs = collect_arch_discussions(events)
        for i, run in enumerate(runs):
            first_text = event_text(run[0])
            topic = _slugify(first_text[:60])
            fname = f"{day}_{i+1:02d}_{topic}.md"
            body = _compress_arch_run(run)
            body = wrap_pii(body)
            note_content = (
                "---\n"
                "type: note\n"
                "tags: [imported, discussion]\n"
                "importance: medium\n"
                "---\n\n"
                f"<!-- imported from JSONL {datetime.now(UTC).strftime('%Y-%m-%d')} -->\n"
                f"{body}\n"
            )
            notes_to_write.append((fname, note_content))

    summary = {
        "jsonls": len(jsonls),
        "events": len(all_events),
        "days": len(by_day),
        "notes": len(notes_to_write),
        "mode": mode,
    }

    print(f"jsonls={summary['jsonls']}")
    print(f"events={summary['events']}")
    print(f"days={summary['days']}")
    print(f"notes={summary['notes']}")
    print(f"mode={mode}")

    if mode != "apply":
        return summary

    # Apply: append progress + write notes + save state
    progress_file = mb / "progress.md"
    current_progress = progress_file.read_text(encoding="utf-8") if progress_file.exists() else ""
    new_sections: list[str] = []
    for day in sorted(by_day.keys()):
        day_events = by_day[day]
        summary_line = summarize_day(day_events)
        summary_line = wrap_pii(summary_line)
        section_header = f"## {day} (imported)"
        # Idempotency: skip if the header already exists with the "imported" marker
        if section_header in current_progress:
            continue
        new_sections.append(f"\n{section_header}\n\n- {summary_line}\n")

    if new_sections:
        _atomic_write(progress_file, current_progress + "".join(new_sections))

    notes_dir = mb / "notes"
    notes_dir.mkdir(exist_ok=True)
    for fname, content in notes_to_write:
        dest = notes_dir / fname
        if dest.exists():
            continue
        _atomic_write(dest, content)

    # Update state with new hashes
    new_hashes = [event_hash(e) for e in all_events]
    state["seen_hashes"] = list(set(state.get("seen_hashes", [])) | set(new_hashes))
    state["last_run"] = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    _save_state(mb, state)

    return summary


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Claude Code JSONL → Memory Bank import")
    parser.add_argument("--project", required=True, help="Path to ~/.claude/projects/<slug>/")
    parser.add_argument("--since", help="ISO date YYYY-MM-DD — skip earlier events")
    parser.add_argument("--apply", action="store_true",
                        help="Actually write files (default: dry-run)")
    parser.add_argument("mb_path", nargs="?", default=".memory-bank",
                        help="Target .memory-bank path (default: ./.memory-bank)")
    args = parser.parse_args(argv[1:])

    mode = "apply" if args.apply else "dry-run"
    try:
        run_import(
            mb_path=args.mb_path,
            project_dir=args.project,
            mode=mode,
            since=args.since,
        )
    except FileNotFoundError as e:
        print(f"[error] {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
