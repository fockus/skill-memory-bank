#!/usr/bin/env python3
"""Install only Memory Bank hooks; preserve Codex settings and foreign hooks."""

import argparse
import json
import shlex
import shutil
import tempfile
from pathlib import Path

OWNER = "_mb_codex_native"
EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact", "Stop", "SessionEnd", "SubagentStart")


def owned(hook):
    return hook.get(OWNER) is True or hook.get("_mb_owned") is True


def install(action, target):
    target = target.expanduser().resolve()
    path = target / "hooks.json"
    if action == "uninstall" and not path.exists():
        return
    original = json.loads(path.read_text()) if path.exists() else {"hooks": {}}
    if not isinstance(original, dict) or not isinstance(original.get("hooks"), dict):
        raise ValueError("existing hooks.json must contain a hooks object; nothing changed")
    data = dict(original, hooks={})
    for event, groups in original["hooks"].items():
        if not isinstance(groups, list):
            raise ValueError("existing hook groups are malformed; nothing changed")
        kept = []
        for group in groups:
            if not isinstance(group, dict):
                raise ValueError("existing hook groups are malformed; nothing changed")
            if event == "userpromptsubmit":
                if not owned(group):
                    kept.append(group)
                continue
            hooks = group.get("hooks")
            if not isinstance(hooks, list) or any(not isinstance(h, dict) for h in hooks):
                raise ValueError("existing hook entries are malformed; nothing changed")
            remaining = [h for h in hooks if not owned(h)]
            if remaining or not hooks:
                kept.append(dict(group, hooks=remaining))
        if kept or not groups:
            data["hooks"][event] = kept
    if action == "install":
        # Keep the installed skill alias: resolving it embeds the source checkout.
        runner = Path(__file__).absolute().parents[1] / "hooks/mb-codex.py"
        if not runner.is_file():
            raise ValueError(f"missing runner: {runner}")
        for event in EVENTS:
            hook = {"type": "command", "command": "python3 " + shlex.quote(str(runner)),
                    "timeout": 3 if event == "SessionEnd" else 60,
                    "statusMessage": "Memory Bank: " + event, OWNER: True}
            data["hooks"].setdefault(event, []).append({"hooks": [hook]})
    target.mkdir(parents=True, exist_ok=True)
    if action == "install" and not (target / "config.toml").exists():
        (target / "config.toml").write_text("# Memory Bank native hooks are in adjacent hooks.json.\n")
    if data == original:
        print(f"unchanged: {path}")
        return
    backup = path.with_name("hooks.json.pre-mb-native")
    if path.exists() and not backup.exists():
        shutil.copy2(path, backup)
    with tempfile.NamedTemporaryFile(mode="w", dir=target, delete=False) as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        tmp = Path(stream.name)
    tmp.replace(path)
    print(f"{action}: {path}; review and trust the current definitions in Codex /hooks")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "uninstall"))
    parser.add_argument("codex_dir", type=Path, help="Project .codex directory, or CODEX_HOME for user scope")
    args = parser.parse_args()
    install(args.action, args.codex_dir)
