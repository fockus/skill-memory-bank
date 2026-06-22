#!/usr/bin/env python3
"""mb-settings-ensure-timeout.py — surgically ensure the SessionEnd `mb-session-end.sh`
hook command carries a per-command `timeout` (seconds).

Why: Claude Code's default SessionEnd hook window is ~60s. The Memory Bank summarizer
spawns `claude -p` (Haiku) which needs 30-90s on a real session (measured 76s for a
64-turn Live log), so it is SIGKILLed before writing `## Summary` → `summarized:false`
on every session. This injects a generous timeout so the synchronous summary path can
finish (a safety-net alongside the SessionStart lazy catch-up).

Design: a TEXT-surgical edit (not a jq/json round-trip) so a large user `settings.json`
keeps its original formatting and the diff is a single added line. Idempotent: if the
hook already has a `timeout`, it is a no-op.

Usage: mb-settings-ensure-timeout.py <settings.json> [seconds=240]
Exit:  0 = applied or already present; non-zero = missing file / invalid JSON / not found.
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile

ANCHOR = "mb-session-end.sh"
# A "command" line whose value names the summarizer hook AND ends at the closing quote
# (i.e. it is the last key in its object, with no trailing comma yet).
LINE_RE = re.compile(r'^(\s*)"command"\s*:\s*".*' + re.escape(ANCHOR) + r'.*"\s*$')


def _session_end_groups(data: dict) -> list:
    """SessionEnd hook groups, supporting both shapes: a full settings file
    (`{"hooks": {"SessionEnd": [...]}}`) and a bare hooks fragment
    (`{"SessionEnd": [...]}`, as shipped in the skill's settings/hooks.json)."""
    nested = (data.get("hooks", {}) or {}).get("SessionEnd")
    if nested:
        return nested
    return data.get("SessionEnd", []) or []


def _find_hook_timeout(data: dict) -> bool:
    """True if the SessionEnd mb-session-end hook already carries a `timeout` key."""
    for group in _session_end_groups(data):
        for hook in group.get("hooks", []) or []:
            cmd = hook.get("command", "")
            if ANCHOR in cmd and "timeout" in hook:
                return True
    return False


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        sys.stderr.write("usage: mb-settings-ensure-timeout.py <settings.json> [seconds]\n")
        return 2
    path = argv[1]
    seconds = int(argv[2]) if len(argv) > 2 else 240
    if not os.path.isfile(path):
        sys.stderr.write(f"[timeout] settings file not found: {path}\n")
        return 1

    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"[timeout] invalid JSON in {path}: {exc}\n")
        return 1

    if _find_hook_timeout(data):
        print("[timeout] already present — no-op")
        return 0

    lines = text.splitlines(keepends=True)
    out, done = [], False
    for line in lines:
        m = LINE_RE.match(line.rstrip("\n"))
        if m and not done:
            indent = m.group(1)
            nl = "\n" if line.endswith("\n") else ""
            body = line.rstrip("\n")
            out.append(body + "," + nl)  # add trailing comma
            out.append(f'{indent}"timeout": {seconds}{nl}')  # inject timeout line
            done = True
        else:
            out.append(line)

    if not done:
        sys.stderr.write(f"[timeout] anchor command line ({ANCHOR}) not found in {path}\n")
        return 1

    new_text = "".join(out)
    # Verify the result is valid JSON and the timeout actually landed.
    check = json.loads(new_text)
    if not _find_hook_timeout(check):
        sys.stderr.write("[timeout] post-edit verification failed\n")
        return 1

    d = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".settings.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(new_text)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    print(f"[timeout] applied timeout={seconds} to SessionEnd mb-session-end hook")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
