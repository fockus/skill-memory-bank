import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = Path(os.environ.get('MB_NATIVE_TEST_BUNDLE', ROOT))
RUNNER = ROOT / 'hooks/mb-codex.py'


class CodexLifecycleTests(unittest.TestCase):
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

    def test_child_start_restores_bank_and_rule_pointers(self):
        (self.bank/'status.md').write_text('Child must retain the milestone.\n')
        (self.bank/'RULES.md').write_text('Project rules.\n')
        (self.cwd/'RULES.md').write_text('Root rules.\n')
        r = self.hook('SubagentStart', agent_id='child', agent_type='mb-developer')
        self.assertEqual(r.returncode, 0, r.stderr)
        output = json.loads(r.stdout)['hookSpecificOutput']
        self.assertEqual(output['hookEventName'], 'SubagentStart')
        context = output['additionalContext']
        self.assertIn('Child must retain the milestone.', context)
        self.assertIn(str(self.bank), context)
        self.assertIn(str(BUNDLE/'SKILL.md'), context)
        self.assertIn(str(BUNDLE/'rules/RULES.md'), context)
        self.assertIn(str(self.bank/'RULES.md'), context)
        self.assertIn(str(self.cwd/'RULES.md'), context)
        self.assertLessEqual(len(context), 4000)

    def test_child_events_never_run_root_closure(self):
        self.env['MB_CORE_CAP'] = 'on'
        (self.bank/'status.md').write_text('Pending work.\n' * 70)
        for event in ('SubagentStop', 'Stop', 'SessionEnd'):
            with self.subTest(event=event):
                r = self.hook(event, agent_id='child', agent_type='mb-developer')
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertNotEqual(json.loads(r.stdout).get('decision'), 'block')
        self.assertFalse((self.bank/'handoff/latest.md').exists())

    def test_session_end_bounds_the_complete_fallback(self):
        slow = self.cwd/'slow-handoff.sh'
        marker = self.cwd/'orphan-wrote.txt'
        slow.write_text('#!/bin/bash\nsleep 4\nprintf orphan > "' + str(marker) + '"\n')
        self.env.update(MB_HANDOFF_SCRIPT=str(slow), MB_PRECOMPACT_BUDGET='20')
        started = time.monotonic()
        r = self.hook('SessionEnd')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertLess(time.monotonic() - started, 2.9)
        time.sleep(max(0, 4.4 - (time.monotonic() - started)))
        self.assertFalse(marker.exists())
        self.assertNotIn('summary', (self.bank/'progress.md').read_text()
                         if (self.bank/'progress.md').exists() else '')

    def test_session_end_slow_capture_fails_open_within_total_budget(self):
        bundle = self.cwd/'slow bundle'
        bundle.mkdir()
        for path in BUNDLE.iterdir():
            if path.name != 'hooks':
                (bundle/path.name).symlink_to(path, target_is_directory=path.is_dir())
        hooks = bundle/'hooks'
        hooks.mkdir()
        for path in (BUNDLE/'hooks').iterdir():
            if path.name != 'mb-codex-session.py':
                (hooks/path.name).symlink_to(path, target_is_directory=path.is_dir())
        marker = self.cwd/'capture-orphan.txt'
        (hooks/'mb-codex-session.py').write_text(
            'import time\nfrom pathlib import Path\ntime.sleep(4)\nPath(' +
            repr(str(marker)) + ').write_text("orphan")\n')
        self.env['MB_SKILLS_ROOT'] = str(bundle)
        started = time.monotonic()
        r = self.hook('SessionEnd', transcript_path=str(self.cwd/'unused'))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertLess(time.monotonic() - started, 2.9)
        self.assertIn('timed out', r.stderr)
        time.sleep(max(0, 4.4 - (time.monotonic() - started)))
        self.assertFalse(marker.exists())
        self.assertFalse((self.bank/'session').exists())

    def test_stop_surfaces_only_freshness_nudge(self):
        subprocess.run(['git', 'init', str(self.cwd)], check=True, capture_output=True)
        (self.bank/'status.md').write_text('Pending milestone.\n')
        self.env['MB_DRIFT_WARN_DIRTY_LINES'] = '1'
        r = self.hook('Stop')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('drift:', json.loads(r.stdout).get('systemMessage', ''))
        self.assertNotIn('hookSpecificOutput', json.loads(r.stdout))

    def transcript(self, sid):
        transcript = self.cwd/'rollout.jsonl'
        records = [
            {'type': 'session_meta', 'payload': {'id': sid}},
            {'type': 'event_msg', 'payload': {'type': 'task_started', 'turn_id': 'turn-1'}},
            {'type': 'response_item', 'payload': {'type': 'message', 'role': 'user',
             'content': [{'type': 'input_text', 'text': 'Which storage did we choose?'}]}},
            {'type': 'response_item', 'payload': {'type': 'message', 'role': 'assistant',
             'phase': 'final_answer', 'content': [{'type': 'output_text',
             'text': 'We chose SQLite for local persistence.'}]}},
        ]
        transcript.write_text(''.join(json.dumps(record) + '\n' for record in records))
        return transcript

    def test_each_root_lifecycle_event_captures_into_a_fresh_bank(self):
        sid = '0198c0de-aaaa-4c1d-9e8f-000000000001'
        transcript = self.transcript(sid)
        for event in ('Stop', 'PreCompact', 'SessionEnd'):
            with self.subTest(event=event):
                bank = self.cwd/('fresh-' + event)
                bank.mkdir()
                self.env['MB_PATH'] = str(bank)
                r = self.hook(event, session_id=sid, transcript_path=str(transcript))
                self.assertEqual(r.returncode, 0, r.stderr)
                records = [path for path in (bank/'session').glob('*.md') if path.name != '_recent.md']
                self.assertEqual(len(records), 1)
                self.assertIn('We chose SQLite', records[0].read_text())
                self.assertFalse((bank/'progress.md').exists())

    def test_session_end_cumulative_helpers_share_one_deadline(self):
        bundle = self.cwd/'delayed bundle'
        hooks = bundle/'hooks'
        hooks.mkdir(parents=True)
        marker = self.cwd/'cumulative-orphan.txt'
        (hooks/'_skill_root.sh').write_text(
            'mb_hook_resolve_mb_path() { sleep 0.9; printf "%s" "$MB_PATH"; }\n')
        (hooks/'mb-codex-session.py').write_text(
            'import time\ntime.sleep(0.9)\nprint("{}")\n')
        (hooks/'mb-pre-compact.sh').write_text(
            '#!/bin/bash\nsleep 0.9\nprintf orphan > "' + str(marker) + '"\n')
        self.env['MB_SKILLS_ROOT'] = str(bundle)
        started = time.monotonic()
        r = self.hook('SessionEnd')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertLess(time.monotonic() - started, 2.9)
        self.assertIn('mb-pre-compact.sh: timed out', r.stderr)
        # Observe beyond the scheduled write, not merely just after hook return.
        time.sleep(max(0, 3.2 - (time.monotonic() - started)))
        self.assertFalse(marker.exists())

    def test_root_capture_restores_conversation_in_the_next_chat(self):
        sid = '0198c0de-aaaa-4c1d-9e8f-000000000001'
        transcript = self.transcript(sid)
        self.env['MB_SEMANTIC_PY'] = sys.executable
        for event in ('Stop', 'PreCompact', 'SessionEnd'):
            with self.subTest(event=event):
                r = self.hook(event, session_id=sid, transcript_path=str(transcript))
                self.assertEqual(r.returncode, 0, r.stderr)
        sessions = list((self.bank/'session').glob('*.md'))
        record = next(path for path in sessions if path.name != '_recent.md')
        self.assertEqual(record.read_text().count('### Turn '), 1)
        # An end deadline can interrupt the derived recent index after capture.
        (self.bank/'session/_recent.md').unlink()
        r = self.hook('SessionStart', session_id='chat-b', source='compact')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('We chose SQLite', json.loads(r.stdout)['hookSpecificOutput']['additionalContext'])
        r = self.hook('UserPromptSubmit', session_id='chat-b', prompt='Which SQLite storage did we choose for local persistence?')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(record.name, r.stdout)
        self.assertFalse((self.bank/'progress.md').exists())

    def test_lifecycle_session_capture_optout_leaves_no_session_record(self):
        sid = '0198c0de-aaaa-4c1d-9e8f-000000000001'
        transcript = self.transcript(sid)
        self.env['MB_SESSION_CAPTURE'] = 'off'
        for event in ('Stop', 'PreCompact', 'SessionEnd'):
            r = self.hook(event, session_id=sid, transcript_path=str(transcript))
            self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((self.bank/'session').exists())

    def test_auto_capture_off_preserves_rich_session_memory_without_progress_stub(self):
        sid = '0198c0de-aaaa-4c1d-9e8f-000000000001'
        transcript = self.transcript(sid)
        self.env['MB_AUTO_CAPTURE'] = 'off'
        r = self.hook('Stop', session_id=sid, transcript_path=str(transcript))
        self.assertEqual(r.returncode, 0, r.stderr)
        records = [path for path in (self.bank/'session').glob('*.md') if path.name != '_recent.md']
        self.assertEqual(len(records), 1)
        self.assertIn('We chose SQLite', records[0].read_text())
        self.assertFalse((self.bank/'progress.md').exists())



if __name__ == '__main__':
    unittest.main()
