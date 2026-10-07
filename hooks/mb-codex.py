#!/usr/bin/env python3
"""Translate native Codex hook inputs and reuse Memory Bank's checks."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(os.environ.get('MB_SKILLS_ROOT', Path(__file__).resolve().parents[1]))


def patch_files(command):
    """Return touched paths and added lines; never execute or apply a patch."""
    files = {}
    path = None
    for line in command.splitlines():
        match = re.fullmatch(r'\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)', line)
        if match:
            path = match[1]
            files.setdefault(path, [])
        elif path and line.startswith('+'):
            files[path].append(line[1:])
    return files


def requirement_file(path):
    name = '/' + str(path).replace('\\', '/')
    return name.endswith('.md') and ('/context/' in name or re.search(r'/specs/[^/]+/requirements\.md$', name))


def main(payload):
    event = payload.get('hook_event_name', '')
    cwd = Path(payload.get('cwd') or os.getcwd())
    if not cwd.is_dir():
        raise ValueError('hook cwd is not a directory')
    env = dict(os.environ, MB_AGENT='codex', MB_SKILLS_ROOT=str(ROOT),
               CLAUDE_PROJECT_DIR=str(cwd), MB_PROTECTED_MODE='deny')
    result = {}
    contexts = []

    def run(relative, data=None, args=(), strict=False, raw=None):
        p = subprocess.run(['bash', str(ROOT/relative), *map(str, args)],
                           input=raw if raw is not None else json.dumps(data or payload),
                           text=True, capture_output=True, cwd=cwd, env=env, timeout=30)
        if p.stderr:
            print(p.stderr.rstrip(), file=sys.stderr)
        if p.returncode:
            if strict or p.returncode == 2:
                raise RuntimeError(p.stderr.strip() or p.stdout.strip() or relative)
            print(f'[MB Codex] {relative}: exit {p.returncode}', file=sys.stderr)
        try:
            out = json.loads(p.stdout or '{}')
        except ValueError:
            return p
        if isinstance(out, dict):
            if out.get('decision') == 'block':
                result.update(decision='block', reason=out.get('reason', 'Memory Bank check failed'))
            if out.get('systemMessage'):
                result['systemMessage'] = out['systemMessage']
            context = out.get('hookSpecificOutput', {}).get('additionalContext')
            if context:
                contexts.append(context)
        return p

    def validate(path, content):
        if requirement_file(path):
            run('scripts/mb-ears-validate.sh', args=('-',), raw=content, strict=True)

    tool = payload.get('tool_name', '')
    inp = payload.get('tool_input') or {}
    if not isinstance(inp, dict):
        raise ValueError('tool_input must be an object')
    if event == 'SessionStart':
        run('hooks/mb-session-start.sh')
        if payload.get('source') == 'compact':
            run('hooks/mb-graph-nudge.sh', args=('--reset',))
        run('hooks/mb-update-notify.sh')
    elif event == 'UserPromptSubmit':
        run('hooks/mb-semantic-recall.sh')
    elif event in ('PreCompact', 'SessionEnd'):
        # No Claude CLI summaries: the portable capsule needs no model call.
        run('hooks/mb-pre-compact.sh')
    elif event == 'Stop':
        for name in ('mb-flow-closure-guard.sh', 'mb-drive-resume-gate.sh', 'mb-core-cap-guard.sh'):
            run('hooks/' + name)
    elif event == 'PreToolUse':
        if tool == 'apply_patch':
            for path, added in patch_files(inp.get('command', '')).items():
                mapped = dict(payload, tool_name='Edit', tool_input={'file_path':path})
                run('hooks/mb-protected-paths-guard.sh', mapped)
                # Updates can omit unchanged continuation lines. Check their full
                # content after the patch instead of inventing a second patch engine.
                if '*** Add File: '+path in inp.get('command', '').splitlines():
                    validate(path, '\n'.join(added))
        elif tool in ('Bash', 'Write', 'Edit'):
            run('hooks/mb-protected-paths-guard.sh')
            if tool == 'Write':
                run('hooks/mb-ears-pre-write.sh')
        elif tool in ('spawn_agent', 'Agent', 'Task'):
            mapped = dict(payload, tool_name='Agent', tool_input=dict(inp, prompt=inp.get('message', inp.get('prompt', ''))))
            run('hooks/mb-context-slim-pre-agent.sh', mapped)
            run('hooks/mb-sprint-context-guard.sh', mapped)
        run('hooks/mb-graph-nudge.sh')
    elif event == 'PostToolUse' and tool == 'apply_patch':
        paths = patch_files(inp.get('command', ''))
        spec_changed = False
        for name in paths:
            path = (cwd/name).resolve()
            spec_changed |= '/specs/' in str(path)
            if path.is_file():
                if requirement_file(path):
                    validate(path, path.read_text())
                if path.suffix == '.md' and path.parent.name == 'plans':
                    run('scripts/mb-plan-sync.sh', args=(path,), strict=True)
        if spec_changed:
            run('scripts/mb-roadmap-sync.sh')
            run('scripts/mb-traceability-gen.sh')
    if contexts:
        result['hookSpecificOutput'] = {'hookEventName':event, 'additionalContext':'\n\n'.join(contexts)}
    return result


if __name__ == '__main__':
    try:
        data = json.load(sys.stdin)
        if not isinstance(data, dict):
            raise ValueError('hook input must be an object')
        print(json.dumps(main(data), ensure_ascii=False))
    except RuntimeError as exc:
        print(f'[MB Codex] {exc}', file=sys.stderr)
        sys.exit(2)
    except (ValueError, OSError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({'systemMessage':f'Memory Bank hook could not complete: {exc}'}))
        sys.exit(1)
