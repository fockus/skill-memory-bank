"""Capture never follows bank-owned links or reads unbounded stored memory."""
import pytest
from test_codex_session_capture import append_turn, load, setup


def test_linked_session_directory_never_writes_outside_bank(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    outside = tmp_path / 'outside'
    outside.mkdir()
    (bank / 'session').symlink_to(outside, target_is_directory=True)
    append_turn(transcript)
    assert load().capture(payload, bank) is None
    assert list(outside.iterdir()) == []


def test_linked_existing_part_never_imports_foreign_body(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    module = load()
    sf = module.capture(payload, bank)
    outside = tmp_path / 'foreign.md'
    outside.write_text(sf.read_text().replace('choose SQLite', 'FOREIGN_PRIVATE_BODY'))
    foreign = outside.read_bytes()
    sf.unlink()
    sf.symlink_to(outside)
    append_turn(transcript, 'next request', 'next answer', 'next')
    assert module.capture(payload, bank) is None
    assert sf.is_symlink() and outside.read_bytes() == foreign


def test_linked_lock_is_rejected_before_capture(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    module = load()
    sf = module.capture(payload, bank)
    original = sf.read_bytes()
    lock = next((bank / 'session').glob('.codex-*.lock'))
    lock.unlink()
    outside = tmp_path / 'foreign-lock'
    outside.write_text('outside lock')
    lock.symlink_to(outside)
    append_turn(transcript, 'next request', 'next answer', 'next')
    assert module.capture(payload, bank) is None
    assert sf.read_bytes() == original and outside.read_text() == 'outside lock'


def test_oversize_active_part_is_preserved_without_reading_whole_body(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    module = load()
    sf = module.capture(payload, bank)
    original = sf.read_text() + 'past memory ' * 100000
    sf.write_text(original)
    append_turn(transcript, 'new request', 'new answer', 'next')
    assert module.capture(payload, bank) is None
    assert sf.read_text() == original


def test_oversize_replay_part_preserves_all_existing_history(tmp_path, monkeypatch):
    bank, transcript, payload = setup(tmp_path)
    module = load()
    monkeypatch.setattr(module, 'MAX_SESSION_BYTES', 1800)
    append_turn(transcript, 'first decision ' + 'a' * 200, 'first result ' + 'b' * 200)
    module.capture(payload, bank)
    append_turn(transcript, 'second decision ' + 'c' * 200, 'second result ' + 'd' * 200, 'second')
    module.capture(payload, bank)
    parts = sorted((bank / 'session').glob('*.md'))
    parts[0].write_text(parts[0].read_text() + 'oversized foreign content ' * 50000)
    before = [p.read_bytes() for p in parts]
    saved = transcript.read_text()
    transcript.unlink()
    transcript.write_text(saved)
    assert module.capture(payload, bank) is None
    assert [p.read_bytes() for p in parts] == before


def test_default_index_symlink_never_creates_dirty_file_outside_bank(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    outside = tmp_path / 'outside-index'
    outside.mkdir()
    (bank / '.index').symlink_to(outside, target_is_directory=True)
    append_turn(transcript)
    load().capture(payload, bank)
    assert not (outside / '.dirty').exists()


def test_legacy_progress_optout_does_not_disable_rich_session_capture(tmp_path, monkeypatch):
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript)
    monkeypatch.setenv('MB_AUTO_CAPTURE', 'off')
    sf = load().capture(payload, bank)
    assert sf and 'SQLite' in sf.read_text()
    assert not (bank / 'progress.md').exists()


def test_extractive_summary_is_not_sent_to_shared_claude_catchup(tmp_path):
    import json
    import os
    import subprocess

    from test_codex_session_capture import ROOT
    bank, transcript, payload = setup(tmp_path)
    append_turn(transcript, '"quoted request matches Claude catchup selector', 'chosen local SQLite')
    sf = load().capture(payload, bank)
    assert 'summarized: true' in sf.read_text() and 'summary_mode: extractive' in sf.read_text()
    fake = tmp_path / 'summarizer.sh'
    calls = tmp_path / 'llm-calls'
    fake.write_text('#!/usr/bin/env bash\necho called >> "' + str(calls) + '"\n')
    proc = subprocess.run(['bash', str(ROOT / 'hooks/mb-session-catchup.sh')],
                          input=json.dumps({'cwd': str(tmp_path), 'session_id': 'different'}),
                          capture_output=True, text=True, check=True,
                          env={**os.environ, 'MB_PATH': str(bank), 'MB_SUMMARIZE_BIN': str(fake),
                               'MB_CATCHUP_FOREGROUND': '1'})
    assert proc.returncode == 0 and not calls.exists()


def test_explicit_bank_symlink_resolves_to_user_selected_root(tmp_path):
    bank, transcript, payload = setup(tmp_path)
    selected = tmp_path / 'selected-bank'
    selected.symlink_to(bank, target_is_directory=True)
    append_turn(transcript)
    sf = load().capture(payload, selected)
    assert sf and sf.parent == bank / 'session'


@pytest.mark.parametrize('user_text', ['a' * 1600, '😀' * 1600])
def test_pending_state_near_byte_cap_rotates_and_final_answer_survives(tmp_path, user_text):
    from test_codex_session_capture import msg, record
    bank, transcript, payload = setup(tmp_path)
    module = load()
    append_turn(transcript, 'older decision', 'older public answer')
    sf = module.capture(payload, bank)
    text = sf.read_text()
    padding = module.MAX_PART_READ_BYTES - 64 - len(text.encode())
    sf.write_text(text.replace('\n## Summary\n', '\n' + 'a' * padding + '\n## Summary\n'))
    previous = sf.read_bytes()
    with transcript.open('a') as stream:
        stream.write(record('event_msg', type='task_started', turn_id='astral'))
        stream.write(msg('user', user_text))
    assert module.capture(payload, bank) is None
    assert sf.read_bytes() == previous
    assert all(part.stat().st_size <= module.MAX_PART_READ_BYTES for part in (bank / 'session').glob('*.md'))
    with transcript.open('a') as stream:
        stream.write(msg('assistant', 'LATEST_ASTRAL_DECISION', phase='final_answer'))
    latest = module.capture(payload, bank)
    assert latest and 'LATEST_ASTRAL_DECISION' in latest.read_text()
    saved = transcript.read_text()
    transcript.unlink()
    transcript.write_text(saved)
    assert module.capture(payload, bank) is None
    live = '\n'.join(part.read_text().split('## Live log\n')[1].split('## Summary')[0]
                     for part in (bank / 'session').glob('*.md'))
    assert live.count('LATEST_ASTRAL_DECISION') == 1 and live.count('older public answer') == 1
