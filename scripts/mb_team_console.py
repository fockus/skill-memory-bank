#!/usr/bin/env python3
"""orchestrator-console.md helpers (references/orchestrator-console.md).

Usage (through mb-console.sh):
  mb_team_console.py line <bank> <track> <status> <note>   # the caller holds the `console` lock
  mb_team_console.py check <bank>                          # exit 1 above MB_CONSOLE_MAX_LINES (default 40)

`line` keeps one line per MB Team track under HEAD, replaced in place, so `mb-team.sh track set`
keeps the console current without the orchestrator editing it by hand.
"""

from __future__ import annotations

import datetime as dt
import os
import sys
from pathlib import Path

HEAD = "## Tracks (auto: mb-team.sh track set)"


def console(bank: str) -> Path:
    return Path(bank) / "orchestrator-console.md"


def set_line(bank: str, track: str, status: str, note: str) -> None:
    path = console(bank)
    lines = (
        path.read_text(encoding="utf-8").splitlines()
        if path.exists()
        else ["# Orchestrator console"]
    )
    if HEAD not in lines:
        lines += ["", HEAD]
    start = lines.index(HEAD) + 1
    end = next((i for i in range(start, len(lines)) if lines[i].startswith("## ")), len(lines))
    entry = f"- {track} [{status} {dt.datetime.now().strftime('%m-%d %H:%M')}]: {' '.join(note.split())[:160]}"
    body = [ln for ln in lines[start:end] if ln.strip() and not ln.startswith(f"- {track} [")] + [
        entry
    ]
    tail = ([""] if end < len(lines) else []) + lines[end:]
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text("\n".join(lines[:start] + body + tail) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def check(bank: str) -> int:
    path = console(bank)
    cap = int(os.environ.get("MB_CONSOLE_MAX_LINES") or 40)
    count = len(path.read_text(encoding="utf-8").splitlines()) if path.exists() else 0
    if count <= cap:
        return 0
    print(
        f"[console] {path} has {count} lines (cap {cap}): move history — Done sections, finished tracks, "
        f"old decisions — to progress.md (mb-work-progress-append.sh or /mb done) and keep only live state",
        file=sys.stderr,
    )
    return 1


def main(argv: list[str]) -> int:
    if len(argv) == 5 and argv[0] == "line":
        set_line(*argv[1:])
        return 0
    if len(argv) == 2 and argv[0] == "check":
        return check(argv[1])
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
