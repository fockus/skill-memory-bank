"""Long-session replay checkpoints make progress within each hook time budget."""
from test_codex_session_capture import append_turn, load, setup


def test_budgeted_replay_resumes_duplicate_scan_without_losing_new_decisions(tmp_path, monkeypatch):
    bank, transcript, payload = setup(tmp_path)
    module = load()
    monkeypatch.setattr(module, 'MAX_SESSION_BYTES', 1600)
    for n in range(12):
        append_turn(transcript, f'decision-{n} ' + 'a' * 200, f'result-{n} ' + 'b' * 200, f'part-{n}')
    module.capture(payload, bank)
    saved = transcript.read_text()
    transcript.unlink()
    transcript.write_text(saved)
    ticks = 0.0
    def clock():
        nonlocal ticks
        ticks += 0.2
        return ticks
    monkeypatch.setattr(module.time, 'monotonic', clock)
    for _ in range(100):
        module.capture(payload, bank)
    parts = list((bank / 'session').glob('*.md'))
    assert len(parts) == 12
    live = '\n'.join(p.read_text().split('## Live log\n')[1].split('## Summary')[0] for p in parts)
    for n in range(12):
        assert live.count(f'decision-{n} ') == 1
    append_turn(transcript, 'LATEST_NEW_DECISION', 'LATEST_NEW_RESULT', 'latest')
    changed = None
    for _ in range(50):
        changed = module.capture(payload, bank) or changed
    assert changed and 'LATEST_NEW_DECISION' in changed.read_text()


def test_nonobject_session_metadata_fails_open_without_bank_writes(tmp_path):
    import json
    bank, transcript, payload = setup(tmp_path)
    transcript.write_text(json.dumps(['invalid metadata']) + '\n')
    assert load().capture(payload, bank) is None
    assert list(bank.iterdir()) == []
