#!/usr/bin/env python3
"""Merge skill hooks into ~/.claude/settings.json idempotently.

Guarantees a deterministic final state:
  1. Remove ALL existing memory-bank managed hook entries (marker-based +
     legacy-pattern-based) from every event. This prevents duplicates when
     re-installing with a new marker scheme or a different language.
  2. Append the fresh entries from hooks.json.

Net effect: any number of repeated installs produces exactly the same hook
block — no creep, no stale language variants, no unmarked legacy copies.
"""

import json
import os
import re
import sys
import tempfile

MARKER = "[memory-bank-skill]"

# Legacy signatures — commands that previous installer versions wrote WITHOUT
# the [memory-bank-skill] marker. Matched as plain substrings against the
# first hook's command. Keep these in sync with anything that ever shipped.
LEGACY_PATTERNS: list[str] = [
    "[SYSTEM] \u041f\u0440\u043e\u0447\u0438\u0442\u0430\u0439 ~/.claude/CLAUDE.md",  # Setup (legacy localized, unmarked)
    "[SYSTEM] Read ~/.claude/CLAUDE.md",              # Setup (en, unmarked)
    "'[PRE-WRITE] TDD",                               # PreToolUse echo (legacy localized, unmarked)
    "'[PRE-WRITE] no TODO",                           # PreToolUse echo (en, unmarked)
    "[COMPACTION] \u041f\u0435\u0440\u0435\u0434 compaction",  # PreCompact (legacy localized, unmarked)
    "[COMPACTION] Before compaction",                 # PreCompact (en, unmarked)
    "[MEMORY BANK] \u0420\u0435\u043a\u043e\u043c\u0435\u043d\u0434\u0430\u0446\u0438\u044f",  # Stop (legacy localized, unmarked)
    "[MEMORY BANK] Recommendation",                   # Stop (en, unmarked)
    '"Claude Code \u0436\u0434\u0451\u0442 \u0432\u043d\u0438\u043c\u0430\u043d\u0438\u044f"',  # Notification (legacy localized, unmarked)
    '"Claude Code needs attention"',                  # Notification (en, unmarked)
]

# Bare-path hooks owned by the skill. Matched via exact equality to support
# the common case of a user having their own hook at the same path — we only
# strip the standalone bare form, never anything with extra wrapping.
LEGACY_BARE_PATHS: set[str] = {
    "~/.claude/hooks/block-dangerous.sh",
    "~/.claude/hooks/file-change-log.sh",
    "~/.claude/hooks/session-end-autosave.sh",
    "~/.claude/hooks/mb-compact-reminder.sh",
}

_STRIP_MARKER_RE = re.compile(r"\s*#\s*\[memory-bank-skill\]\s*$")


def _first_cmd(entry: object) -> str:
    if not isinstance(entry, dict):
        return ""
    hooks = entry.get("hooks")
    if not isinstance(hooks, list) or not hooks:
        return ""
    first = hooks[0]
    if not isinstance(first, dict):
        return ""
    return first.get("command", "") or ""


def _is_mb_managed(cmd: str) -> bool:
    """True if a hook command is owned by the memory-bank skill."""
    if MARKER in cmd:
        return True
    stripped = _STRIP_MARKER_RE.sub("", cmd).strip()
    if stripped in LEGACY_BARE_PATHS:
        return True
    return any(pat in cmd for pat in LEGACY_PATTERNS)


def _strip_mb_managed(entries: list) -> list:
    return [e for e in entries if not _is_mb_managed(_first_cmd(e))]


def merge_hooks(settings_path: str, hooks_path: str) -> None:
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except FileNotFoundError:
        settings = {}

    with open(hooks_path) as f:
        new_hooks = json.load(f)

    existing_hooks = settings.setdefault("hooks", {})

    # Idempotent: strip every MB-managed entry first, then append fresh copies.
    for event in list(existing_hooks.keys()):
        cleaned = _strip_mb_managed(existing_hooks[event])
        if cleaned:
            existing_hooks[event] = cleaned
        else:
            # Drop empty event arrays so we don't leave "Foo": [] behind.
            del existing_hooks[event]

    for event, entries in new_hooks.items():
        existing_hooks.setdefault(event, []).extend(entries)

    settings["hooks"] = existing_hooks

    tmp_fd, tmp_path = tempfile.mkstemp(
        dir=os.path.dirname(settings_path) or ".",
        suffix=".tmp",
    )
    try:
        with os.fdopen(tmp_fd, "w") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, settings_path)
    except BaseException:
        os.unlink(tmp_path)
        raise


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <settings.json> <hooks.json>")
        sys.exit(1)
    merge_hooks(sys.argv[1], sys.argv[2])
