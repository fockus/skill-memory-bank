"""Model-free Codex capture persists public final answers across chat resumes."""
import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SID = '0198c0de-aaaa-4c1d-9e8f-000000000001'


def load():
    spec = importlib.util.spec_from_file_location('codex_session', ROOT / 'hooks/lib/codex_session.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def record(kind, **payload):
    return json.dumps({'type': kind, 'payload': payload}) + '\n'


def msg(role, text, **extra):
    return record('response_item', type='message', role=role,
                  content=[{'type': 'input_text' if role == 'user' else 'output_text', 'text': text}], **extra)


def setup(tmp_path, **meta):
    bank = tmp_path / 'bank'
    bank.mkdir()
    transcript = tmp_path / 'rollout.jsonl'
    transcript.write_text(record('session_meta', id=SID, **meta))
    return bank, transcript, {'session_id': SID, 'transcript_path': str(transcript)}


def append_turn(transcript, request='choose SQLite', answer='We chose SQLite for local storage.', turn='turn-1'):
    with transcript.open('a') as f:
        f.write(record('event_msg', type='task_started', turn_id=turn))
        f.write(msg('user', request, id='user-' + turn))
        f.write(msg('assistant', 'Internal commentary', phase='commentary'))
        f.write(record('response_item', type='reasoning', encrypted_content='hidden'))
        f.write(msg('assistant', answer, phase='final_answer', id='answer-' + turn))
        f.write(record('event_msg', type='task_complete', turn_id=turn, last_agent_message=answer))


def test_capture_repeats_resume_and_rotation_keep_exactly_once_public_turns(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    capture = load().capture
    sf = capture(payload, bank)
    original = sf.read_text()
    assert 'choose SQLite' in original and 'We chose SQLite for local storage.' in original
    assert 'Internal commentary' not in original and 'hidden' not in original
    assert 'summary_mode: extractive' in original and 'agent: codex' in original
    assert capture(payload, bank) is None
    assert sf.read_text() == original
    append_turn(transcript, 'enable WAL', 'WAL is enabled.', 'turn-2')
    assert capture(payload, bank) == sf
    assert sf.read_text().count('### Turn ') == 2
    saved = transcript.read_text()
    transcript.unlink()
    transcript.write_text(saved)
    assert capture(payload, bank) is None
    assert sf.read_text().count('### Turn ') == 2
    transcript.write_text(record('session_meta', id=SID))
    capture(payload, bank)
    append_turn(transcript, 'third request', 'Third answer.', 'turn-3')
    capture(payload, bank)
    assert sf.read_text().count('### Turn ') == 3


def test_private_nested_unclosed_and_secrets_never_reach_disk(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    secret = 'sk-' + 's' * 30
    append_turn(transcript, f'public <private>outer private phrase <private>nested private phrase</private> hidden private phrase</private> {secret}',
                'decision\n```python\nraw_bulk_code\n```\n<private>unclosed sensitive private phrase')
    sf = load().capture(payload, bank)
    text = sf.read_text()
    for value in ['outer private phrase', 'nested private phrase', 'hidden private phrase', secret, 'sensitive private phrase', 'raw_bulk_code']:
        assert value not in text
    assert 'public' in text and 'decision' in text and '[REDACTED]' in text


def test_pending_partial_lines_resume_and_malformed_records_are_skipped(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    with transcript.open('a') as f:
        f.write(record('event_msg', type='task_started', turn_id='partial'))
        f.write(msg('user', 'retain pending decision'))
        f.write('not-json\n')
        answer = msg('assistant', 'pending decision persisted', phase='final_answer')
        f.write(answer[:len(answer)//2])
    capture = load().capture
    assert capture(payload, bank) is None
    with transcript.open('a') as f:
        f.write(answer[len(answer)//2:])
    sf = capture(payload, bank)
    assert 'retain pending decision' in sf.read_text() and 'pending decision persisted' in sf.read_text()
    assert capture(payload, bank) is None


@pytest.mark.parametrize('env', ['MB_SESSION_CAPTURE'])
def test_capture_optouts_leave_bank_untouched(tmp_path, monkeypatch, env):
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    monkeypatch.setenv(env, 'off')
    assert load().capture(payload, bank) is None
    assert list(bank.iterdir()) == []


@pytest.mark.parametrize('meta', [{'id': 'other'}, {'parent_thread_id': 'parent'}, {'source': {'subagent': {}}}])
def test_mismatch_and_children_never_capture_inherited_parent_messages(tmp_path, meta):
    bank, transcript, payload = setup(tmp_path)
    transcript.write_text(record('session_meta', **({'id': SID} | meta)))
    append_turn(transcript, 'parent private work', 'parent answer')
    assert load().capture(payload, bank) is None
    assert list(bank.iterdir()) == []


def test_missing_transcript_bank_and_bad_sid_create_nothing(tmp_path):
    capture = load().capture
    missing = tmp_path / 'missing'
    assert capture({'session_id': SID, 'transcript_path': str(missing)}, missing) is None
    assert not missing.exists()
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    assert capture(payload | {'session_id': '../../unsafe'}, bank) is None
    assert capture(payload | {'transcript_path': str(missing)}, bank) is None
    assert list(bank.iterdir()) == []


def test_capture_is_bounded_and_marks_existing_index_dirty(tmp_path, monkeypatch):
    bank, transcript, payload = setup(tmp_path)
    index = bank / '.index'
    index.mkdir()
    for n in range(8):
        append_turn(transcript, f'request {n}', 'answer ' + str(n), f'turn-{n}')
    monkeypatch.setenv('MB_CODEX_CAPTURE_MAX_BYTES', '800')
    capture = load().capture
    sf = None
    for _ in range(20):
        sf = capture(payload, bank) or sf
    assert sf.read_text().count('### Turn ') == 8
    assert (index / '.dirty').exists()


def test_persisted_text_has_explicit_size_cap(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript, 'request ' + 'a' * 5000, 'answer ' + 'b' * 5000)
    text = load().capture(payload, bank).read_text()
    assert '[truncated]' in text and 'a' * 2000 not in text and 'b' * 2000 not in text


def test_lock_contention_preserves_previously_captured_data(tmp_path):
    import fcntl
    import hashlib
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    capture = load().capture
    sf = capture(payload, bank)
    original = sf.read_bytes()
    append_turn(transcript, 'later request', 'later answer', 'later')
    lock = bank / 'session' / ('.codex-' + hashlib.sha256(SID.encode()).hexdigest()[:16] + '.lock')
    with lock.open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert capture(payload, bank) is None
        assert sf.read_bytes() == original
    assert capture(payload, bank) == sf
    assert 'later answer' in sf.read_text()


def test_synthetic_user_instructions_and_nonfinal_messages_are_excluded(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    with transcript.open('a') as stream:
        stream.write(record('event_msg', type='task_started', turn_id='real'))
        stream.write(msg('user', '# AGENTS.md instructions\nsynthetic project policy'))
        stream.write(msg('assistant', 'unsolicited final', phase='final_answer'))
        stream.write(msg('user', 'human request'))
        stream.write(msg('developer', 'developer private policy'))
        stream.write(msg('assistant', 'public answer', phase='final_answer'))
    text = load().capture(payload, bank).read_text()
    assert 'human request' in text and 'public answer' in text
    assert 'synthetic project policy' not in text and 'unsolicited final' not in text
    assert 'developer private policy' not in text


def test_cli_reports_metadata_only_and_bad_input_fails_open(tmp_path):
    import subprocess
    import sys
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    command = [sys.executable, str(ROOT / 'hooks/mb-codex-session.py'), str(bank)]
    proc = subprocess.run(command, input=json.dumps(payload), text=True, capture_output=True, check=True)
    result = json.loads(proc.stdout)
    assert result['captured'] and Path(result['session_file']).is_file()
    assert 'SQLite' not in proc.stdout and proc.stderr == ''
    proc = subprocess.run(command, input='not-json', text=True, capture_output=True, check=True)
    assert json.loads(proc.stdout) == {'captured': False, 'error': 'invalid_capture_input'}


def test_large_ignored_records_do_not_stall_incremental_capture(tmp_path, monkeypatch):
    bank, transcript, payload = setup(tmp_path)
    with transcript.open('a') as stream:
        stream.write(record('response_item', type='function_call_output', output='bulk' * 10000))
    append_turn(transcript)
    monkeypatch.setenv('MB_CODEX_CAPTURE_MAX_BYTES', '1000')
    capture = load().capture
    sf = None
    for _ in range(50):
        sf = capture(payload, bank) or sf
    assert sf and 'SQLite' in sf.read_text() and 'bulk' not in sf.read_text()


def test_damaged_existing_capture_state_is_preserved(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    capture = load().capture
    sf = capture(payload, bank)
    damaged = sf.read_text().replace('capture_state: {', 'capture_state: null\nignored: {')
    sf.write_text(damaged)
    append_turn(transcript, 'second user', 'second answer', 'second')
    assert capture(payload, bank) is None
    assert sf.read_text() == damaged


def test_session_parts_preserve_long_session_decisions_and_replay_dedup(tmp_path, monkeypatch):
    bank, transcript, payload = setup(tmp_path)
    module = load()
    monkeypatch.setattr(module, 'MAX_SESSION_BYTES', 1800)
    append_turn(transcript, 'first decision ' + 'a' * 200, 'first result ' + 'b' * 200)
    module.capture(payload, bank)
    append_turn(transcript, 'second decision ' + 'c' * 200, 'second result ' + 'd' * 200, 'second')
    sf = module.capture(payload, bank)
    parts = sorted((bank / 'session').glob('*.md'))
    assert len(parts) == 2
    assert 'first decision' in parts[0].read_text() and 'second decision' in parts[1].read_text()
    assert module.capture(payload, bank) is None
    saved = transcript.read_text()
    transcript.unlink()
    transcript.write_text(saved)
    assert module.capture(payload, bank) is None
    live = '\n'.join(part.read_text().split('## Live log\n')[1].split('## Summary')[0] for part in parts)
    assert live.count('first decision') == 1 and live.count('second decision') == 1
    append_turn(transcript, 'third decision', 'third result', 'third')
    assert module.capture(payload, bank)
    assert 'third decision' in sf.read_text() or any('third decision' in part.read_text() for part in (bank / 'session').glob('*.md'))


def test_multiple_part_rollovers_never_overwrite_earlier_decisions(tmp_path, monkeypatch):
    bank, transcript, payload = setup(tmp_path)
    module = load()
    monkeypatch.setattr(module, 'MAX_SESSION_BYTES', 1600)
    for n in range(5):
        append_turn(transcript, f'decision-{n} ' + 'a' * 200, f'result-{n} ' + 'b' * 200, f'part-{n}')
    module.capture(payload, bank)
    parts = list((bank / 'session').glob('*.md'))
    assert len(parts) == 5
    live = '\n'.join(p.read_text().split('## Live log\n')[1].split('## Summary')[0] for p in parts)
    for n in range(5):
        assert live.count(f'decision-{n}') == 1
    assert module.capture(payload, bank) is None


def test_interrupted_part_rollover_retries_unwritten_final_turn(tmp_path, monkeypatch):
    bank, transcript, payload = setup(tmp_path)
    module = load()
    monkeypatch.setattr(module, 'MAX_SESSION_BYTES', 1800)
    append_turn(transcript, 'first decision ' + 'a' * 200, 'first result ' + 'b' * 200)
    module.capture(payload, bank)
    append_turn(transcript, 'second decision ' + 'c' * 200, 'second result ' + 'd' * 200, 'second')
    original = module._atomic_write
    count = 0
    def interrupted(path, text, directory_fd):
        nonlocal count
        count += 1
        if count == 1:
            raise OSError('simulated disk interruption')
        original(path, text, directory_fd)
    monkeypatch.setattr(module, '_atomic_write', interrupted)
    assert module.capture(payload, bank) is None
    monkeypatch.setattr(module, '_atomic_write', original)
    assert module.capture(payload, bank)
    live = '\n'.join(p.read_text().split('## Live log\n')[1].split('## Summary')[0]
                     for p in (bank / 'session').glob('*.md'))
    assert live.count('first decision') == 1 and live.count('second decision') == 1


def test_mixed_synthetic_context_blocks_do_not_hide_human_request(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    with transcript.open('a') as stream:
        stream.write(record('event_msg', type='task_started', turn_id='mixed'))
        stream.write(record('response_item', type='message', role='user', content=[
            {'type': 'input_text', 'text': '# AGENTS.md instructions\nsynthetic policy'},
            {'type': 'input_text', 'text': '<environment_context>synthetic environment</environment_context>'},
            {'type': 'input_text', 'text': 'real human decision'}]))
        stream.write(msg('assistant', 'real public answer', phase='final_answer'))
    sf = load().capture(payload, bank)
    assert sf and 'real human decision' in sf.read_text()
    assert 'synthetic policy' not in sf.read_text() and 'synthetic environment' not in sf.read_text()
