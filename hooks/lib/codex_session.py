"""Bounded, model-free Codex rollout capture into an existing Memory Bank."""
from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import stat
import sys
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from redact import redact_secrets  # noqa: E402

try:
    import fcntl
except ImportError:
    fcntl = None

MAX_PART_READ_BYTES = 1024 * 1024
# Reserve space for bounded pending text and replay checkpoints between turns.
MAX_SESSION_BYTES = MAX_PART_READ_BYTES - 8192

from memory_bank_skill.private import strip_private  # noqa: E402


def sanitize(text: str) -> str:
    """Strip private spans and fenced bulk before redaction and truncation."""
    text = redact_secrets(strip_private(text)[0])
    text = re.sub(r'```.*?(?:```|\Z)', '[code omitted]', text, flags=re.S)
    text = re.sub(r'\s+', ' ', text).strip()
    return text if len(text) <= 1600 else text[:1600] + ' [truncated]'


def _atomic_write(path: Path, text: str, directory_fd: int) -> None:
    if len(text.encode()) > MAX_PART_READ_BYTES:
        raise ValueError('oversize capture write')
    try:
        existing = os.stat(path.name, dir_fd=directory_fd, follow_symlinks=False)
        if not stat.S_ISREG(existing.st_mode):
            raise ValueError('capture part is not a regular file')
    except FileNotFoundError:
        pass
    name = '.codex-' + uuid.uuid4().hex + '.tmp'
    fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path.name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(name, dir_fd=directory_fd)


def _load(path: Path, directory_fd: int) -> tuple[dict, str]:
    try:
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
    except FileNotFoundError:
        return {}, ''
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_PART_READ_BYTES:
            raise ValueError('invalid capture part')
        data = stream.read(MAX_PART_READ_BYTES + 1)
        if len(data) > MAX_PART_READ_BYTES:
            raise ValueError('oversize capture part')
    text = data.decode('utf-8')
    head, body = text.split('\n---\n', 1)
    state = json.loads(next(line[15:] for line in head.splitlines() if line.startswith('capture_state: ')))
    if not isinstance(state, dict) or not all(key in state for key in ('offset', 'inode', 'seen', 'started')):
        raise ValueError('invalid capture state')
    live = body.split('## Live log\n', 1)[1].split('\n## Summary\n', 1)[0]
    return state, live


def _mark_dirty(bank: Path) -> None:
    explicit = os.environ.get('MB_INDEX_DIR')
    index = Path(explicit).resolve() if explicit else bank / '.index'
    with contextlib.suppress(OSError):
        fd = os.open(index, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            dirty = os.open('.dirty', os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=fd)
            try:
                if stat.S_ISREG(os.fstat(dirty).st_mode):
                    os.utime(dirty)
            finally:
                os.close(dirty)
        finally:
            os.close(fd)


def _render(sid: str, transcript: Path, state: dict, live: str) -> str:
    # Keep metadata single-line; never persist raw pending transcript text.
    summary = '\n'.join(line for line in live.splitlines() if line.startswith(('User:', 'Assistant:')))[-4000:]
    return ('---\nagent: codex\nsession_id: ' + sid + '\ntranscript: ' + json.dumps(str(transcript))
            + '\nstarted: ' + state['started'] + '\nbranch: -\nturns: ' + str(state.get('turns_total', len(state['seen'])))
            + '\nsummarized: true\nsummary_mode: extractive\ncapture_state: '
            + json.dumps(state, ensure_ascii=True, separators=(',', ':'))
            + '\n---\n\n## Live log\n' + live + '\n## Summary\n'
            + 'Extractive conversation memory (no model-generated summary).\n' + summary + '\n')


def _message(payload: dict) -> str:
    content = payload.get('content', [])
    if not isinstance(content, list):
        return ''
    return '\n'.join(block['text'] for block in content if isinstance(block, dict)
                     and block.get('type') in ('input_text', 'output_text') and isinstance(block.get('text'), str)
                     and not (payload.get('role') == 'user' and block['text'].lstrip().startswith(
                         ('# AGENTS.md instructions', '<environment_context>', '<INSTRUCTIONS>'))))


def _ingest(row: dict, state: dict, known: set[str], previous: list[Path], deadline: float, directory_fd: int) -> tuple[str, str] | None:
    payload = row.get('payload')
    if not isinstance(payload, dict):
        return None
    if row.get('type') == 'event_msg' and payload.get('type') == 'task_started':
        state.update(turn=hashlib.sha256(str(payload.get('turn_id') or '').encode()).hexdigest(), user='')
    if row.get('type') != 'response_item' or payload.get('type') != 'message':
        return None
    role, text = payload.get('role'), _message(payload)
    if role == 'user':
        if not text:
            return None
        state['user'] = sanitize(text)
        if not state.get('turn'):
            state['turn'] = hashlib.sha256(str(payload.get('id') or row.get('ordinal') or text).encode()).hexdigest()
    elif role == 'assistant' and payload.get('phase') in ('final_answer', 'final'):
        answer = sanitize(text)
        user = state.get('user', '')
        if not user or not answer:
            return None
        identity = state.get('turn') or payload.get('id') or row.get('ordinal')
        key = hashlib.sha256(str(identity).encode()).hexdigest()
        if key in known:
            state.pop('replay_scan', None)
            return None
        if state.get('replaying'):
            scan = state.get('replay_scan', {})
            start = scan.get('index', 0) if scan.get('key') == key else 0
            for index in range(start, len(previous)):
                if time.monotonic() >= deadline:
                    state.update(replay_scan={'key': key, 'index': index}, deferred=True)
                    return None
                previous_state, _ = _load(previous[index], directory_fd)
                if key in previous_state['seen']:
                    state.pop('replay_scan', None)
                    return None
            state.pop('replay_scan', None)
        state['seen'].append(key)
        known.add(key)
        return user, answer
    return None


def capture(payload: dict, bank: Path) -> Path | None:
    """Return the session path only if a new public final turn was persisted."""
    if os.environ.get('MB_SESSION_CAPTURE') == 'off':
        return None
    if fcntl is None or os.open not in os.supports_dir_fd:
        return None
    if os.environ.get('MB_CAPTURE_SUBPROCESS') or payload.get('agent_id'):
        return None
    try:
        sid = str(uuid.UUID(payload.get('session_id', '')))
        raw_path = payload.get('transcript_path')
        if not raw_path or not isinstance(raw_path, str) or '\n' in raw_path:
            return None
        transcript = Path(raw_path)
        bank = Path(bank).resolve(strict=True)
        if not bank.is_dir() or not transcript.is_file():
            return None
        return _capture(payload, bank, transcript, sid)
    except (OSError, ValueError, TypeError, KeyError, IndexError, StopIteration):
        return None


def _capture(payload: dict, bank: Path, transcript: Path, sid: str) -> Path | None:
    started = time.monotonic()
    budget = max(0.01, min(2.0, float(os.environ.get('MB_CODEX_CAPTURE_BUDGET', '1'))))
    max_bytes = max(128, min(4 * 1024 * 1024, int(os.environ.get('MB_CODEX_CAPTURE_MAX_BYTES', str(512 * 1024)))))
    fd = os.open(transcript, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            return None
        first = stream.readline(max_bytes)
        metadata = json.loads(first)
        if not isinstance(metadata, dict):
            return None
        meta = metadata.get('payload', {})
        if metadata.get('type') != 'session_meta' or not isinstance(meta, dict):
            return None
        if str(meta.get('id') or meta.get('session_id')) != sid or meta.get('parent_thread_id'):
            return None
        if isinstance(meta.get('source'), dict) and 'subagent' in meta['source']:
            return None
        directory = bank / 'session'
        with contextlib.ExitStack() as handles:
            bank_fd = os.open(bank, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            handles.callback(os.close, bank_fd)
            with contextlib.suppress(FileExistsError):
                os.mkdir('session', dir_fd=bank_fd)
            directory_fd = os.open('session', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=bank_fd)
            handles.callback(os.close, directory_fd)
            return _capture_locked(stream, bank, directory, directory_fd, transcript, sid, started, budget, max_bytes)


def _capture_locked(stream, bank, directory, directory_fd, transcript, sid, started, budget, max_bytes) -> Path | None:
    identity = hashlib.sha256(sid.encode()).hexdigest()[:16]
    lock = directory / ('.codex-' + identity + '.lock')
    fd = os.open(lock.name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory_fd)
    with os.fdopen(fd, 'a') as guard:
        if not stat.S_ISREG(os.fstat(guard.fileno()).st_mode):
            return None
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return None
        matches = sorted(directory / name for name in os.listdir(directory_fd)
                         if re.fullmatch(r'[0-9-]+_[0-9]+_' + identity + r'(?:[0-9a-f]{8})?\.md', name))
        stamp = datetime.now(UTC)
        sf = matches[-1] if matches else directory / (stamp.strftime('%Y-%m-%d_%H%M_') + identity + '.md')
        state, live = _load(sf, directory_fd)
        old_state = json.dumps(state, sort_keys=True)
        transcript_stat = os.fstat(stream.fileno())
        inode = str(transcript_stat.st_dev) + ':' + str(transcript_stat.st_ino)
        if not state:
            state = dict(offset=0, inode=inode, seen=[], turn='', user='', started=stamp.isoformat(), turns_total=0)
        matches = matches or [sf]
        if state['inode'] != inode or transcript_stat.st_size < state['offset']:
            state.update(offset=0, inode=inode, turn='', user='', skipping=False, replaying=True)
        known = set(state['seen'])
        stream.seek(state['offset'])
        consumed = 0
        changed = False
        captured_sf = None
        while consumed < max_bytes and time.monotonic() - started < budget:
            offset = stream.tell()
            line = stream.readline(max_bytes - consumed)
            if not line:
                break
            consumed += len(line)
            if not line.endswith(b'\n'):
                # A large complete record can be skipped in bounded slices. A
                # trailing partial record is retried from its original offset.
                if len(line) == max_bytes and stream.tell() < transcript_stat.st_size:
                    state.update(offset=stream.tell(), skipping=True)
                break
            state['offset'] = stream.tell()
            if state.pop('skipping', False):
                continue
            try:
                row = json.loads(line)
            except (ValueError, UnicodeDecodeError):
                continue
            if not isinstance(row, dict):
                continue
            turn = _ingest(row, state, known, matches[:-1], started + budget, directory_fd)
            if state.pop('deferred', False):
                state['offset'] = offset
                break
            if turn:
                user, answer = turn
                state['turns_total'] = state.get('turns_total', len(state['seen']) - 1) + 1
                entry = f'\n### Turn {state["turns_total"]}\nUser: {user}\nAssistant: {answer}\n'
                if live and len(_render(sid, transcript, state, live + entry).encode()) > MAX_SESSION_BYTES:
                    part = len(matches) if matches else 1
                    sf = directory / (sf.name.split('_')[0] + '_' + sf.name.split('_')[1] + '_'
                                      + identity + f'{part:08x}.md')
                    matches.append(sf)
                    state['seen'] = state['seen'][-1:]
                    live = ''
                live += entry
                _atomic_write(sf, _render(sid, transcript, state, live), directory_fd)
                captured_sf = sf
                _mark_dirty(bank)
                changed = True
        if state['offset'] >= transcript_stat.st_size:
            state.pop('replaying', None)
        if json.dumps(state, sort_keys=True) != old_state:
            rendered = _render(sid, transcript, state, live)
            if len(rendered.encode()) > MAX_PART_READ_BYTES:
                part = len(matches)
                sf = directory / (sf.name.split('_')[0] + '_' + sf.name.split('_')[1] + '_'
                                  + identity + f'{part:08x}.md')
                state['seen'] = []
                live = ''
                rendered = _render(sid, transcript, state, live)
            _atomic_write(sf, rendered, directory_fd)
        return captured_sf if changed else None
