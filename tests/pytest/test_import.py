"""Tests for scripts/mb-import.py — Claude Code JSONL → Memory Bank bootstrap.

Contract:
    mb-import.py [--since YYYY-MM-DD] [--project <path>] [--dry-run] [--apply] [mb_path]

    Reads ~/.claude/projects/<slug>/*.jsonl, extracts:
      - progress.md: daily-grouped summaries (append-only)
      - notes/: architectural discussion heuristics (≥3 consecutive assistant messages)
      - lessons.md: debug-session patterns (error → fix → explain)
      - status.md: seed only if empty

    Dedup: SHA256(timestamp + first 500 chars) → skip if already in index.
    Resume: .memory-bank/.import-state.json (last processed session/event).
    PII auto-wrap: email + API-key regex → <private>...</private>.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
IMPORT_SCRIPT = REPO_ROOT / "scripts" / "mb-import.py"


def _load_import_module():
    spec = importlib.util.spec_from_file_location("mb_import", IMPORT_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def import_mod():
    if not IMPORT_SCRIPT.exists():
        pytest.skip("scripts/mb-import.py not implemented yet (TDD red)")
    return _load_import_module()


@pytest.fixture
def mb_path(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "notes").mkdir(parents=True)
    for name in ("status.md", "roadmap.md", "checklist.md", "progress.md",
                 "lessons.md", "research.md", "backlog.md"):
        (mb / name).write_text("")
    return mb


@pytest.fixture
def jsonl_project(tmp_path: Path) -> Path:
    """Create ~/.claude/projects/<slug>/*.jsonl fixture with sample events."""
    proj = tmp_path / "projects" / "-tmp-test-project"
    proj.mkdir(parents=True)
    jsonl = proj / "session-1.jsonl"

    events = [
        {"type": "permission-mode", "sessionId": "session-1",
         "permissionMode": "default"},
        {"type": "user", "sessionId": "session-1",
         "timestamp": "2026-04-18T10:00:00.000Z",
         "message": {"role": "user",
                     "content": [{"type": "text", "text": "Help me understand the auth flow"}]},
         "uuid": "u1"},
        {"type": "assistant", "sessionId": "session-1",
         "timestamp": "2026-04-18T10:00:30.000Z",
         "message": {"role": "assistant",
                     "content": [{"type": "text",
                                  "text": "Auth consists of an OAuth2 PKCE flow with refresh tokens. " * 40}]},
         "uuid": "a1"},
        {"type": "assistant", "sessionId": "session-1",
         "timestamp": "2026-04-18T10:01:00.000Z",
         "message": {"role": "assistant",
                     "content": [{"type": "text",
                                  "text": "Next, let's review session management and scope enforcement. " * 40}]},
         "uuid": "a2"},
        {"type": "assistant", "sessionId": "session-1",
         "timestamp": "2026-04-18T10:01:30.000Z",
         "message": {"role": "assistant",
                     "content": [{"type": "text",
                                  "text": "Finally, token rotation and the revocation list during logout. " * 40}]},
         "uuid": "a3"},
        {"type": "user", "sessionId": "session-1",
         "timestamp": "2026-04-19T14:00:00.000Z",
         "message": {"role": "user",
                     "content": [{"type": "text", "text": "A different task on the next day"}]},
         "uuid": "u2"},
    ]
    with jsonl.open("w", encoding="utf-8") as f:
        for e in events:
            f.write(json.dumps(e) + "\n")
    return proj


def _run_cli(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(IMPORT_SCRIPT), *args],
        capture_output=True, text=True, check=False,
    )


# ═══════════════════════════════════════════════════════════════
# JSONL parsing
# ═══════════════════════════════════════════════════════════════


def test_parses_user_and_assistant_events(import_mod, jsonl_project):
    """Reader returns a list of events with normalized fields."""
    jsonl = next(jsonl_project.glob("*.jsonl"))
    events = list(import_mod.iter_events(jsonl))
    assert len(events) >= 6
    kinds = {e.get("type") for e in events}
    assert "user" in kinds
    assert "assistant" in kinds


def test_broken_jsonl_line_skipped_with_warning(import_mod, tmp_path, capsys):
    """Broken line → warning on stderr, remaining events still process."""
    jsonl = tmp_path / "broken.jsonl"
    jsonl.write_text(
        '{"type":"user","sessionId":"s","timestamp":"2026-04-19T00:00:00Z",'
        '"message":{"role":"user","content":[{"type":"text","text":"ok"}]}}\n'
        "not valid json{{\n"
        '{"type":"assistant","sessionId":"s","timestamp":"2026-04-19T00:00:05Z",'
        '"message":{"role":"assistant","content":[{"type":"text","text":"reply"}]}}\n'
    )
    events = list(import_mod.iter_events(jsonl))
    assert len(events) == 2


# ═══════════════════════════════════════════════════════════════
# Dry-run vs apply
# ═══════════════════════════════════════════════════════════════


def test_dry_run_zero_file_changes(import_mod, mb_path, jsonl_project):
    """--dry-run: progress.md does not change, notes/ are not created."""
    before_progress = (mb_path / "progress.md").read_text()
    before_notes_count = len(list((mb_path / "notes").glob("*.md")))

    import_mod.run_import(
        mb_path=str(mb_path),
        project_dir=str(jsonl_project),
        mode="dry-run",
    )

    assert (mb_path / "progress.md").read_text() == before_progress
    assert len(list((mb_path / "notes").glob("*.md"))) == before_notes_count


def test_apply_writes_progress_entries(import_mod, mb_path, jsonl_project):
    """--apply: progress.md receives daily-grouped sections."""
    import_mod.run_import(
        mb_path=str(mb_path),
        project_dir=str(jsonl_project),
        mode="apply",
    )
    progress = (mb_path / "progress.md").read_text()
    # Dates from the fixture should be present (2026-04-18, 2026-04-19)
    assert "2026-04-18" in progress
    assert "2026-04-19" in progress


# ═══════════════════════════════════════════════════════════════
# Dedup / idempotency
# ═══════════════════════════════════════════════════════════════


def test_apply_idempotent_two_runs(import_mod, mb_path, jsonl_project):
    """Two consecutive runs → 0 duplicate entries in progress.md."""
    import_mod.run_import(mb_path=str(mb_path), project_dir=str(jsonl_project), mode="apply")
    first_size = (mb_path / "progress.md").stat().st_size
    import_mod.run_import(mb_path=str(mb_path), project_dir=str(jsonl_project), mode="apply")
    second_size = (mb_path / "progress.md").stat().st_size
    assert first_size == second_size


def test_event_hash_deterministic(import_mod):
    """Dedup hash is deterministic for the same (timestamp + first 500 chars)."""
    e1 = {"timestamp": "2026-04-18T10:00:00Z",
          "message": {"content": [{"type": "text", "text": "same body"}]}}
    e2 = {"timestamp": "2026-04-18T10:00:00Z",
          "message": {"content": [{"type": "text", "text": "same body"}]}}
    assert import_mod.event_hash(e1) == import_mod.event_hash(e2)


# ═══════════════════════════════════════════════════════════════
# --since filter
# ═══════════════════════════════════════════════════════════════


def test_since_filter_excludes_earlier_events(import_mod, mb_path, jsonl_project):
    """--since 2026-04-19 → events from 2026-04-18 are not imported."""
    import_mod.run_import(
        mb_path=str(mb_path),
        project_dir=str(jsonl_project),
        mode="apply",
        since="2026-04-19",
    )
    progress = (mb_path / "progress.md").read_text()
    assert "2026-04-18" not in progress
    assert "2026-04-19" in progress


# ═══════════════════════════════════════════════════════════════
# Notes extraction — heuristic
# ═══════════════════════════════════════════════════════════════


def test_architectural_discussion_creates_note(import_mod, mb_path, jsonl_project):
    """≥3 consecutive assistant messages >1K chars → note in notes/."""
    import_mod.run_import(mb_path=str(mb_path), project_dir=str(jsonl_project), mode="apply")
    notes = list((mb_path / "notes").glob("*.md"))
    # fixture contains 3 consecutive long assistant messages
    assert len(notes) >= 1


# ═══════════════════════════════════════════════════════════════
# PII auto-wrap
# ═══════════════════════════════════════════════════════════════


def test_email_autowrapped_in_private(import_mod, tmp_path, mb_path):
    """Email in user message → wrap in <private>...</private>."""
    proj = tmp_path / "projects" / "-email-test"
    proj.mkdir(parents=True)
    jsonl = proj / "s.jsonl"
    jsonl.write_text(json.dumps({
        "type": "user", "sessionId": "s1",
        "timestamp": "2026-04-19T00:00:00Z",
        "message": {"role": "user",
                    "content": [{"type": "text",
                                 "text": "Write to test.user@example.com or support@company.io"}]},
        "uuid": "u"
    }) + "\n")
    import_mod.run_import(mb_path=str(mb_path), project_dir=str(proj), mode="apply")
    progress = (mb_path / "progress.md").read_text()
    # Email must be wrapped
    assert "test.user@example.com" not in progress or "<private>" in progress
    # If it appears, it must only appear inside private
    if "test.user@example.com" in progress:
        # There must be at least one <private> before the email
        idx = progress.index("test.user@example.com")
        prefix = progress[:idx]
        assert "<private>" in prefix


def test_api_key_autowrapped_in_private(import_mod, tmp_path, mb_path):
    """API key pattern (sk-... / Bearer ...) → <private> wrap."""
    proj = tmp_path / "projects" / "-apikey-test"
    proj.mkdir(parents=True)
    jsonl = proj / "s.jsonl"
    jsonl.write_text(json.dumps({
        "type": "user", "sessionId": "s1",
        "timestamp": "2026-04-19T00:00:00Z",
        "message": {"role": "user",
                    "content": [{"type": "text",
                                 "text": "key: sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"}]},
        "uuid": "u"
    }) + "\n")
    import_mod.run_import(mb_path=str(mb_path), project_dir=str(proj), mode="apply")
    progress = (mb_path / "progress.md").read_text()
    if "sk-ant-api03" in progress:
        idx = progress.index("sk-ant-api03")
        prefix = progress[:idx]
        assert "<private>" in prefix


# ═══════════════════════════════════════════════════════════════
# Resume state
# ═══════════════════════════════════════════════════════════════


def test_import_state_written_on_apply(import_mod, mb_path, jsonl_project):
    """.memory-bank/.import-state.json is written after apply."""
    import_mod.run_import(mb_path=str(mb_path), project_dir=str(jsonl_project), mode="apply")
    assert (mb_path / ".import-state.json").exists()
    state = json.loads((mb_path / ".import-state.json").read_text())
    assert "last_run" in state
    assert "seen_hashes" in state


def test_dry_run_does_not_write_state(import_mod, mb_path, jsonl_project):
    """dry-run does not create the state file."""
    import_mod.run_import(mb_path=str(mb_path), project_dir=str(jsonl_project), mode="dry-run")
    assert not (mb_path / ".import-state.json").exists()


# ═══════════════════════════════════════════════════════════════
# CLI interface
# ═══════════════════════════════════════════════════════════════


def test_cli_requires_project_argument(import_mod):
    """CLI without --project → error exit."""
    result = _run_cli([])
    assert result.returncode != 0


def test_cli_dry_run_default(import_mod, mb_path, jsonl_project):
    """CLI without --apply = dry-run by default (no file changes)."""
    before = (mb_path / "progress.md").read_text()
    result = _run_cli(["--project", str(jsonl_project), str(mb_path)])
    assert result.returncode == 0
    assert (mb_path / "progress.md").read_text() == before


def test_cli_apply_flag_triggers_writes(import_mod, mb_path, jsonl_project):
    """CLI --apply → progress.md updated."""
    result = _run_cli(["--project", str(jsonl_project), "--apply", str(mb_path)])
    assert result.returncode == 0
    assert (mb_path / "progress.md").read_text() != ""


def test_cli_missing_project_dir(import_mod, mb_path):
    """Nonexistent --project → error exit."""
    result = _run_cli(["--project", "/nonexistent/fake/path", "--apply", str(mb_path)])
    assert result.returncode != 0


# ═══════════════════════════════════════════════════════════════
# Empty / edge cases
# ═══════════════════════════════════════════════════════════════


def test_empty_project_dir_noop(import_mod, mb_path, tmp_path):
    """Project without JSONL files → noop, exit 0."""
    empty_proj = tmp_path / "projects" / "-empty"
    empty_proj.mkdir(parents=True)
    import_mod.run_import(mb_path=str(mb_path), project_dir=str(empty_proj), mode="apply")
    assert (mb_path / "progress.md").read_text() == ""
