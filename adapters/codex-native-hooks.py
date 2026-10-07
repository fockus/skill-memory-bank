#!/usr/bin/env python3
"""Install only Memory Bank hooks; preserve Codex settings and foreign hooks."""
import argparse
import json
from pathlib import Path
import shlex
import shutil
import tempfile


OWNER = '_mb_codex_native'
EVENTS = ('SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PreCompact', 'Stop', 'SessionEnd')


def install(action, target):
    target = target.expanduser().resolve()
    path = target/'hooks.json'
    data = json.loads(path.read_text()) if path.exists() else {'hooks':{}}
    if not isinstance(data, dict) or not isinstance(data.get('hooks'), dict):
        raise ValueError('existing hooks.json must contain a hooks object')
    for groups in data['hooks'].values():
        if not isinstance(groups, list) or any(not isinstance(g, dict) or not isinstance(g.get('hooks'), list) for g in groups):
            raise ValueError('existing hook groups are malformed; nothing changed')
    for event, groups in list(data['hooks'].items()):
        kept = []
        for group in groups:
            hooks = [h for h in group['hooks'] if not h.get(OWNER)]
            if hooks or not group['hooks']:
                kept.append(dict(group, hooks=hooks))
        if kept:
            data['hooks'][event] = kept
        else:
            del data['hooks'][event]
    if action == 'install':
        runner = Path(__file__).resolve().parents[1]/'hooks/mb-codex.py'
        if not runner.is_file():
            raise ValueError(f'missing runner: {runner}')
        for event in EVENTS:
            hook = {'type':'command', 'command':'python3 '+shlex.quote(str(runner)),
                    'timeout':3 if event == 'SessionEnd' else 60,
                    'statusMessage':'Memory Bank: '+event, OWNER:True}
            data['hooks'].setdefault(event, []).append({'hooks':[hook]})
    content = json.dumps(data, ensure_ascii=False, indent=2)+'\n'
    if path.exists() and path.read_text() == content:
        print(f'unchanged: {path}'); return
    target.mkdir(parents=True, exist_ok=True)
    backup = path.with_name('hooks.json.pre-mb-native')
    if path.exists() and not backup.exists():
        shutil.copy2(path, backup)
    with tempfile.NamedTemporaryFile(mode='w', dir=target, delete=False) as f:
        f.write(content); tmp = Path(f.name)
    tmp.replace(path)
    if action == 'install' and not (target/'config.toml').exists():
        (target/'config.toml').write_text('# Memory Bank native hooks are in adjacent hooks.json.\n')
    print(f'{action}: {path}; review and trust the current definitions in Codex /hooks')


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=('install','uninstall'))
    p.add_argument('codex_dir', type=Path, help='Project .codex directory, or ~/.codex for user scope')
    args=p.parse_args()
    install(args.action, args.codex_dir)
