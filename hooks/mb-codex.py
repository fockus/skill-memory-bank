#!/usr/bin/env python3
"""Translate native Codex hook inputs and reuse Memory Bank's checks."""
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

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
    if payload.get('agent_id') and event in ('Stop', 'SessionEnd', 'PreCompact'):
        return {}
    deadline = time.monotonic() + 2.5 if event == 'SessionEnd' else None
    cwd = Path(payload.get('cwd') or os.getcwd())
    if not cwd.is_dir():
        raise ValueError('hook cwd is not a directory')
    env = dict(os.environ, MB_AGENT='codex', MB_SKILLS_ROOT=str(ROOT),
               CLAUDE_PROJECT_DIR=str(cwd), MB_PROTECTED_MODE='deny')
    result = {}
    contexts = []

    def run(relative, data=None, args=(), strict=False, raw=None, command=None, timeout=30):
        remaining = deadline - time.monotonic() if deadline else timeout
        if remaining <= 0:
            return subprocess.CompletedProcess([], 0, '', '')
        command = command or [sys.executable if relative.endswith('.py') else 'bash',
                   str(ROOT/relative), *map(str, args)]
        p = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, cwd=cwd, env=env,
                             start_new_session=True)
        try:
            stdout, stderr = p.communicate(
                raw if raw is not None else json.dumps(data or payload), timeout=remaining)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            p.communicate()
            if strict or event in ('PreToolUse', 'PostToolUse'):
                raise
            print(f'[MB Codex] {relative}: timed out', file=sys.stderr)
            return subprocess.CompletedProcess(command, 0, '', '')
        p = subprocess.CompletedProcess(command, p.returncode, stdout, stderr)
        if p.stderr:
            print(p.stderr.rstrip(), file=sys.stderr)
        if p.returncode:
            if strict or (p.returncode == 2 and event in ('PreToolUse', 'PostToolUse', 'Stop')):
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
            context = out.get('hookSpecificOutput', {}).get('additionalContext') or out.get('additional_context')
            if context:
                contexts.append(context)
        return p

    def resolve_bank():
        # Source the shared resolver rather than reproducing storage rules.
        command = 'source "$1"; mb_hook_resolve_mb_path "$2"'
        resolved = run('hooks/_skill_root.sh', raw='', timeout=5,
                       command=['bash', '-c', command, 'mb-resolve',
                                str(ROOT/'hooks/_skill_root.sh'), str(cwd)])
        bank = Path(resolved.stdout.strip()) if resolved.returncode == 0 and resolved.stdout.strip() else None
        if bank and bank.is_dir():
            env['MB_PATH'] = str(bank)
            return bank
        return None

    def capture_session(bank: Path | None) -> None:
        if bank and env.get('MB_SESSION_CAPTURE', 'on') != 'off':
            captured = run('hooks/mb-codex-session.py', args=(bank,), timeout=2)
            try:
                changed = json.loads(captured.stdout).get('captured') is True
            except (ValueError, AttributeError):
                changed = False
            if changed:
                run('scripts/mb-session-recent-rebuild.sh', args=(bank,))

    def validate(path, content):
        if requirement_file(path):
            run('scripts/mb-ears-validate.sh', args=('-',), raw=content, strict=True)

    tool = payload.get('tool_name', '')
    inp = payload.get('tool_input') or {}
    if not isinstance(inp, dict):
        if tool in ('apply_patch', 'Bash', 'Write', 'Edit', 'spawn_agent', 'Agent', 'Task'):
            raise ValueError('tool_input must be an object')
        inp = {}
    if event == 'SubagentStart':
        bank = resolve_bank()
        if bank and env.get('MB_AUTOLOAD_CONTEXT', 'on') != 'off':
            run('hooks/mb-session-start-context.sh', dict(payload, workspace_roots=[str(cwd)]))
            pointers = [ROOT/'SKILL.md', ROOT/'rules/RULES.md', bank/'RULES.md']
            project = Path(env.get('MB_PROJECT_ROOT', cwd))
            pointers.extend(parent/'RULES.md' for parent in (project, *project.parents)
                            if parent != Path('/'))
            existing = list(dict.fromkeys(str(p) for p in pointers if p.is_file()))
            contexts.insert(0, 'Existing Memory Bank: ' + str(bank) +
                            '\nRead applicable instructions before implementation: ' +
                            ', '.join(existing) +
                            '\nChild completion reports to the parent; root plan closure belongs to the parent.')
    elif event == 'SessionStart':
        bank = resolve_bank()
        if bank and (bank/'session').is_dir():
            run('scripts/mb-session-recent-rebuild.sh', args=(bank,))
        run('hooks/mb-session-start-context.sh', dict(payload, workspace_roots=[str(cwd)]))
        run('hooks/mb-session-start.sh')
        if payload.get('source') == 'compact':
            run('hooks/mb-graph-nudge.sh', args=('--reset',))
        notice = run('hooks/mb-update-notify.sh')
        if notice.stdout.strip():
            result['systemMessage'] = '\n'.join(filter(None, (result.get('systemMessage'), notice.stdout.strip())))
    elif event == 'UserPromptSubmit':
        run('hooks/mb-semantic-recall.sh')
    elif event in ('PreCompact', 'SessionEnd'):
        bank = resolve_bank()
        capture_session(bank)
        run('hooks/mb-pre-compact.sh')
    elif event == 'Stop':
        bank = resolve_bank()
        capture_session(bank)
        for name in ('mb-flow-closure-guard.sh', 'mb-drive-resume-gate.sh', 'mb-core-cap-guard.sh'):
            run('hooks/' + name)
        if bank and not payload.get('stop_hook_active'):
            notice = run('scripts/mb-freshness.sh', args=('--stop-nudge', bank))
            if notice.stdout.startswith('[MEMORY BANK] [memory-bank-skill] drift:'):
                result['systemMessage'] = '\n'.join(filter(None, (result.get('systemMessage'), notice.stdout.strip())))
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
            if tool == 'Bash':
                run('hooks/block-dangerous.sh')
            run('hooks/mb-protected-paths-guard.sh')
            if tool == 'Write':
                run('hooks/mb-ears-pre-write.sh')
        elif tool in ('spawn_agent', 'Agent', 'Task'):
            mapped = dict(payload, tool_name='Agent', tool_input=dict(inp, prompt=inp.get('message', inp.get('prompt', ''))))
            run('hooks/mb-context-slim-pre-agent.sh', mapped)
            run('hooks/mb-sprint-context-guard.sh', mapped)
        run('hooks/mb-graph-nudge.sh')
    elif event == 'PostToolUse' and tool in ('apply_patch', 'Write', 'Edit'):
        paths = patch_files(inp.get('command', '')) if tool == 'apply_patch' else [inp.get('file_path', '')]
        spec_changed = False
        for name in paths:
            if not name:
                continue
            path = (cwd/name).resolve()
            mapped = dict(payload, tool_name='Write' if tool == 'Write' else 'Edit',
                          tool_input={'file_path': str(path)})
            run('hooks/file-change-log.sh', mapped)
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
        context = '\n\n'.join(contexts)
        if event == 'SubagentStart':
            context = context[:4000]
        result['hookSpecificOutput'] = {'hookEventName':event, 'additionalContext':context}
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
