import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = next(p for p in Path(__file__).resolve().parents if (p/'hooks/mb-codex.py').is_file())
BUNDLE = Path(os.environ.get('MB_NATIVE_TEST_BUNDLE', ROOT))
RUNNER = ROOT / 'hooks/mb-codex.py'
INSTALLER = ROOT / 'adapters/codex-native-hooks.py'


class CodexHooksTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cwd = Path(self.tmp.name)
        self.bank = self.cwd / '.memory-bank'
        (self.bank / 'context').mkdir(parents=True)
        self.env = dict(os.environ, MB_SKILLS_ROOT=str(BUNDLE),
                        MB_PATH=str(self.bank), MB_GRAPH_CATCHUP='off',
                        MB_UPDATE_CHECK='off', MB_CORE_CAP='off')

    def tearDown(self):
        self.tmp.cleanup()

    def hook(self, event, tool='', command='', **extra):
        payload = dict(cwd=str(self.cwd), session_id='native-test',
                       hook_event_name=event, tool_name=tool,
                       tool_input={'command': command}, **extra)
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
        (self.bank/'context').rmdir(); self.bank.rmdir()
        r = self.hook('SessionStart')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(self.bank.exists())

    def test_stop_recursion_guard_does_not_block(self):
        r = self.hook('Stop', stop_hook_active=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotEqual(json.loads(r.stdout or '{}').get('decision'), 'block')

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
        plans=self.bank/'plans';plans.mkdir()
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
        target = self.cwd/'.codex'; target.mkdir()
        f = target/'hooks.json'
        foreign = {'type':'command','command':'echo foreign'}
        f.write_text(json.dumps({'hooks':{'Stop':[{'hooks':[foreign]}]}}))
        config = target/'config.toml'; config.write_text('# existing\n')
        for _ in range(2):
            subprocess.run(['python3',str(INSTALLER),'install',str(target)], check=True, capture_output=True)
        d=json.loads(f.read_text())
        self.assertEqual(d['hooks']['Stop'][0]['hooks'],[foreign])
        self.assertEqual(sum(h.get('_mb_codex_native',False) for g in d['hooks']['Stop'] for h in g['hooks']),1)
        self.assertEqual(config.read_text(),'# existing\n')
        subprocess.run(['python3',str(INSTALLER),'uninstall',str(target)], check=True, capture_output=True)
        self.assertEqual(json.loads(f.read_text()),{'hooks':{'Stop':[{'hooks':[foreign]}]}})

    def test_invalid_existing_config_is_preserved(self):
        target=self.cwd/'.codex';target.mkdir()
        f=target/'hooks.json';f.write_text('{broken')
        r=subprocess.run(['python3',str(INSTALLER),'install',str(target)],capture_output=True)
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(f.read_text(),'{broken')


if __name__ == '__main__':
    unittest.main()
