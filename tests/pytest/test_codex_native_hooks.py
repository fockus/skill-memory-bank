import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = Path(os.environ.get('MB_NATIVE_TEST_BUNDLE', ROOT))
RUNNER = ROOT / 'hooks/mb-codex.py'
INSTALLER = ROOT / 'adapters/codex-native-hooks.py'


class CodexHooksTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cwd = Path(self.tmp.name).resolve()
        self.bank = self.cwd / '.memory-bank'
        (self.bank / 'context').mkdir(parents=True)
        self.home = self.cwd / 'home'
        self.home.mkdir()
        self.env = dict(os.environ, MB_SKILLS_ROOT=str(BUNDLE),
                        HOME=str(self.home),
                        CODEX_HOME=str(self.home/'.codex'),
                        MB_PATH=str(self.bank), MB_GRAPH_CATCHUP='off',
                        MB_UPDATE_CHECK='off', MB_CORE_CAP='off')

    def tearDown(self):
        self.tmp.cleanup()

    def hook(self, event, tool='', command='', **extra):
        payload = dict(cwd=str(self.cwd), session_id='native-test',
                       hook_event_name=event, tool_name=tool,
                       tool_input={'command': command})
        payload.update(extra)
        return subprocess.run(['python3', str(RUNNER)], input=json.dumps(payload),
                              text=True, capture_output=True, env=self.env, cwd=self.cwd)

    def test_invalid_requirement_is_blocked_before_patch(self):
        r = self.hook('PreToolUse', 'apply_patch',
                      '*** Begin Patch\n*** Add File: .memory-bank/context/test.md\n+- **REQ-001**: vague wish\n*** End Patch')
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn('EARS', r.stderr)

    def test_valid_requirement_is_allowed_before_patch(self):
        r = self.hook('PreToolUse', 'apply_patch',
                      '*** Begin Patch\n*** Add File: .memory-bank/context/test.md\n+- **REQ-001**: The system shall preserve user files.\n*** End Patch')
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_dangerous_shell_command_is_blocked(self):
        r = self.hook('PreToolUse', 'Bash', 'rm -rf /')
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn('root/home', r.stderr)

    def test_safe_shell_command_is_allowed(self):
        r = self.hook('PreToolUse', 'Bash', 'echo safe')
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_unrelated_tool_accepts_arbitrary_json_input(self):
        for value in ('query', ['query'], 1, True):
            with self.subTest(value=value):
                r = self.hook('PreToolUse', 'mcp__example__search', tool_input=value)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(json.loads(r.stdout), {})

    def test_source_patch_logs_in_codex_marks_graph_and_redacts_warning(self):
        codex = self.cwd/'custom codex'
        self.env['CODEX_HOME'] = str(codex)
        (self.home/'.cursor/skills/memory-bank').mkdir(parents=True)
        source = self.cwd/'example.py'
        source.write_text('api_key = "live-sensitive-value"  # TODO: rotate\n')
        graph = self.bank/'codebase'
        graph.mkdir()
        (graph/'graph.json').write_text('{}')
        r = self.hook('PostToolUse', 'apply_patch',
                      '*** Begin Patch\n*** Add File: example.py\n+x\n*** End Patch')
        self.assertEqual(r.returncode, 0, r.stderr)
        log = codex/'file-changes.log'
        self.assertIn(str(source), log.read_text())
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        self.assertFalse((self.home/'.cursor/file-changes.log').exists())
        self.assertFalse((self.home/'.claude/file-changes.log').exists())
        self.assertIn(str(source), (graph/'.graph-dirty').read_text())
        self.assertIn('Placeholders found', r.stderr)
        self.assertIn('[REDACTED]', r.stderr)
        self.assertNotIn('live-sensitive-value', r.stderr)

    def test_knowledge_edits_mark_only_existing_semantic_index(self):
        notes = self.bank/'notes'
        notes.mkdir()
        note = notes/'decision.md'
        note.write_text('A recorded decision.\n')
        index = self.bank/'.index'
        patch = '*** Begin Patch\n*** Update File: .memory-bank/notes/decision.md\n+x\n*** End Patch'
        r = self.hook('PostToolUse', 'apply_patch', patch)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(index.exists())
        index.mkdir()
        self.env['MB_PATH'] = '.memory-bank'
        for tool in ('apply_patch', 'Write', 'Edit'):
            with self.subTest(tool=tool):
                r = self.hook('PostToolUse', tool, patch,
                              tool_input={'command': patch, 'file_path': str(note)})
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertTrue((index/'.dirty').exists())
                (index/'.dirty').unlink()
        ordinary = self.cwd/'ordinary.md'
        ordinary.write_text('Ordinary project documentation.\n')
        r = self.hook('PostToolUse', 'Edit', tool_input={'file_path': str(ordinary)})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((index/'.dirty').exists())

    def test_move_to_protected_path_is_blocked(self):
        r = self.hook('PreToolUse', 'apply_patch',
                      '*** Begin Patch\n*** Update File: ordinary.txt\n*** Move to: .env\n@@\n-old\n+new\n*** End Patch')
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn('protected', r.stderr.lower())

    def test_post_patch_checks_actual_file_including_unchanged_lines(self):
        (self.bank/'context/test.md').write_text('- **REQ-001**: vague wish\n')
        r = self.hook('PostToolUse', 'apply_patch',
                      '*** Begin Patch\n*** Update File: .memory-bank/context/test.md\n@@\n-old\n+new\n*** End Patch')
        self.assertEqual(r.returncode, 2, r.stderr)

    def test_no_bank_does_not_create_one(self):
        self.env.pop('MB_PATH')
        (self.bank/'context').rmdir()
        self.bank.rmdir()
        for event in ('SessionStart', 'UserPromptSubmit', 'PreCompact', 'SessionEnd', 'Stop', 'SubagentStart'):
            with self.subTest(event=event):
                r = self.hook(event)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertFalse(self.bank.exists())

    def test_session_start_restores_core_without_recent_sessions(self):
        (self.bank/'status.md').write_text('# Status\nRestore the current milestone.\n')
        (self.bank/'checklist.md').write_text('- [ ] Finish the integration.\n')
        r = self.hook('SessionStart')
        self.assertEqual(r.returncode, 0, r.stderr)
        output = json.loads(r.stdout).get('hookSpecificOutput', {})
        self.assertEqual(output.get('hookEventName'), 'SessionStart')
        self.assertIn('Restore the current milestone.', output.get('additionalContext', ''))
        self.assertIn('Finish the integration.', output.get('additionalContext', ''))

    def test_session_start_bounds_core_context(self):
        (self.bank/'status.md').write_text('# Status\n' + 'current milestone ' * 1000)
        r = self.hook('SessionStart')
        self.assertEqual(r.returncode, 0, r.stderr)
        context = json.loads(r.stdout).get('hookSpecificOutput', {}).get('additionalContext', '')
        self.assertIn('current milestone', context)
        self.assertLessEqual(len(context), 2500)

    def test_session_start_context_respects_opt_out(self):
        self.env['MB_AUTOLOAD_CONTEXT'] = 'off'
        (self.bank/'status.md').write_text('Do not inject this core context.\n')
        r = self.hook('SessionStart')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('Do not inject', r.stdout)

    def test_session_start_surfaces_available_update_notice(self):
        resolver = self.cwd/'cached-version.sh'
        resolver.write_text("#!/bin/sh\nprintf '%s\\n' "
                            "'{\"update_available\":true,\"current\":\"5.3.1\","
                            "\"latest\":\"5.3.2\",\"source\":\"cache\","
                            "\"upgrade_command\":\"memory-bank upgrade\"}'\n")
        resolver.chmod(0o700)
        self.env.update(MB_UPDATE_CHECK='on', MB_VERSION_CHECK_BIN=str(resolver), MB_AUTO_UPDATE='off')
        (self.bank/'status.md').write_text('Retain current project context.\n')
        r = self.hook('SessionStart')
        self.assertEqual(r.returncode, 0, r.stderr)
        output = json.loads(r.stdout)
        self.assertIn('5.3.1 -> 5.3.2', output.get('systemMessage', ''))
        self.assertIn('memory-bank upgrade', output.get('systemMessage', ''))
        self.assertIn('Retain current project context.', output['hookSpecificOutput']['additionalContext'])

    def test_compaction_handoff_is_restored_on_compact_session_start(self):
        (self.bank/'checklist.md').write_text('- [ ] Resume the unfinished integration.\n')
        r = self.hook('PreCompact')
        self.assertEqual(r.returncode, 0, r.stderr)
        capsule = (self.bank/'handoff/latest.md').read_text()
        self.assertIn('Resume the unfinished integration.', capsule)
        (self.bank/'checklist.md').write_text('- [ ] Current checklist has changed.\n')
        r = self.hook('SessionStart', source='compact')
        self.assertEqual(r.returncode, 0, r.stderr)
        context = json.loads(r.stdout).get('hookSpecificOutput', {}).get('additionalContext', '')
        self.assertIn('Handoff capsule', context)
        self.assertIn('Resume the unfinished integration.', context)

    def test_session_start_restores_explicit_bank_outside_project(self):
        external = self.cwd/'external-bank'
        self.bank.rename(external)
        self.env['MB_PATH'] = str(external)
        (external/'status.md').write_text('Restore externally stored project memory.\n')
        r = self.hook('SessionStart')
        self.assertEqual(r.returncode, 0, r.stderr)
        context = json.loads(r.stdout).get('hookSpecificOutput', {}).get('additionalContext', '')
        self.assertIn('Restore externally stored project memory.', context)
        self.assertFalse(self.bank.exists())

    def test_session_start_restores_registered_global_bank(self):
        external = self.home/'global-bank'
        self.bank.rename(external)
        self.env.pop('MB_PATH')
        registry = self.home/'.codex/memory-bank/registry.json'
        registry.parent.mkdir(parents=True)
        registry.write_text(json.dumps({'projects': {str(self.cwd.resolve()): {'bank_path': str(external)}}}))
        (external/'status.md').write_text('Restore the registered global bank.\n')
        r = self.hook('SessionStart')
        self.assertEqual(r.returncode, 0, r.stderr)
        context = json.loads(r.stdout).get('hookSpecificOutput', {}).get('additionalContext', '')
        self.assertIn('Restore the registered global bank.', context)
        self.assertFalse(self.bank.exists())

    def test_stop_recursion_guard_does_not_block(self):
        self.env['MB_CORE_CAP'] = 'on'
        (self.bank/'status.md').write_text('# Status\n' + 'Active work must be retained.\n' * 70)
        r = self.hook('Stop', stop_hook_active=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotEqual(json.loads(r.stdout or '{}').get('decision'), 'block')
        self.assertFalse((self.bank/'.core-cap.nudged.native-test').exists())
        r = self.hook('Stop')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout).get('decision'), 'block')
        self.assertIn('core-cap', json.loads(r.stdout).get('reason', ''))

    def test_partial_requirement_update_is_checked_after_write(self):
        patch='*** Begin Patch\n*** Update File: .memory-bank/context/test.md\n@@\n-- **REQ-001**: The old system\n+- **REQ-001**: The system\n*** End Patch'
        r=self.hook('PreToolUse','apply_patch',patch)
        self.assertEqual(r.returncode,0,r.stderr)
        (self.bank/'context/test.md').write_text('- **REQ-001**: The system\n  shall preserve user files.\n')
        r=self.hook('PostToolUse','apply_patch',patch)
        self.assertEqual(r.returncode,0,r.stderr)

    def test_binary_file_does_not_trigger_text_validation(self):
        (self.cwd/'image.png').write_bytes(b'\xff\x00\x89')
        r=self.hook('PostToolUse','apply_patch','*** Begin Patch\n*** Add File: image.png\n+x\n*** End Patch')
        self.assertEqual(r.returncode,0,r.stderr)

    def test_plan_write_updates_checklist_via_real_script(self):
        plans=self.bank/'plans'
        plans.mkdir()
        (self.bank/'checklist.md').write_text('# Checklist\n')
        (self.bank/'roadmap.md').write_text('# Roadmap\n')
        (plans/'2026-10-02_fix_example.md').write_text('---\ntype: fix\ntopic: example\nstatus: in_progress\n---\n# Example\n\n<!-- mb-stage:1 -->\n### Stage 1: Real check\n\n**DoD:**\n- [ ] Files survive restart.\n')
        r=self.hook('PostToolUse','apply_patch','*** Begin Patch\n*** Add File: .memory-bank/plans/2026-10-02_fix_example.md\n+x\n*** End Patch')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('Real check',(self.bank/'checklist.md').read_text())

    def test_deleted_spec_refreshes_traceability(self):
        (self.bank/'traceability.md').write_text('Old REQ-001 must disappear\n')
        (self.bank/'roadmap.md').write_text('# Roadmap\n')
        r=self.hook('PostToolUse','apply_patch','*** Begin Patch\n*** Delete File: .memory-bank/specs/example/requirements.md\n*** End Patch')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertNotIn('Old REQ-001',(self.bank/'traceability.md').read_text())

    def test_install_is_idempotent_and_preserves_foreign_hooks(self):
        target = self.cwd/'.codex'
        target.mkdir()
        f = target/'hooks.json'
        foreign = {'type':'command','command':'echo foreign'}
        f.write_text(json.dumps({'hooks':{'Stop':[{'hooks':[foreign]}]}}))
        config = target/'config.toml'
        config.write_text('# existing\n')
        for _ in range(2):
            subprocess.run(['python3',str(INSTALLER),'install',str(target)], check=True, capture_output=True)
        d=json.loads(f.read_text())
        self.assertEqual(d['hooks']['Stop'][0]['hooks'],[foreign])
        self.assertEqual(sum(h.get('_mb_codex_native',False) for g in d['hooks']['Stop'] for h in g['hooks']),1)
        self.assertEqual(config.read_text(),'# existing\n')
        subprocess.run(['python3',str(INSTALLER),'uninstall',str(target)], check=True, capture_output=True)
        self.assertEqual(json.loads(f.read_text()),{'hooks':{'Stop':[{'hooks':[foreign]}]}})

    def test_invalid_existing_config_is_preserved(self):
        target=self.cwd/'.codex'
        target.mkdir()
        f=target/'hooks.json'
        f.write_text('{broken')
        r=subprocess.run(['python3',str(INSTALLER),'install',str(target)],capture_output=True)
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(f.read_text(),'{broken')


if __name__ == '__main__':
    unittest.main()
