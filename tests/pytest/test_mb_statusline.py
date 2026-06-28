"""Tests for scripts/mb-statusline.py — the context-window statusline."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "mb-statusline.py"


def _run(payload: dict) -> str:
    out = subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return re.sub(r"\x1b\[[0-9;]*m", "", out).strip()  # strip ANSI color


def _write_transcript(tmp_path: Path, *, sidechain_read: int, main_usage: dict) -> Path:
    tp = tmp_path / "transcript.jsonl"
    tp.write_text(
        json.dumps(
            {"isSidechain": True, "message": {"usage": {"cache_read_input_tokens": sidechain_read}}}
        )
        + "\n"
        + json.dumps({"message": {"usage": main_usage}})
        + "\n",
        encoding="utf-8",
    )
    return tp


def test_selfcheck_passes() -> None:
    subprocess.run([sys.executable, str(SCRIPT), "--selfcheck"], check=True)


def test_percentage_against_1m_window(tmp_path: Path) -> None:
    tp = _write_transcript(
        tmp_path,
        sidechain_read=999_999,
        main_usage={
            "input_tokens": 1000,
            "cache_creation_input_tokens": 4000,
            "cache_read_input_tokens": 65000,
        },
    )
    line = _run(
        {
            "model": {"display_name": "Opus 4.8 (1M context)", "id": "claude-opus-4-8[1m]"},
            "workspace": {"project_dir": str(tmp_path)},
            "transcript_path": str(tp),
        }
    )
    assert "7%" in line  # 70k / 1M
    assert "(70k/1M)" in line


def test_sidechain_usage_is_ignored(tmp_path: Path) -> None:
    """Subagent (sidechain) usage must not inflate the main-window count."""
    tp = _write_transcript(
        tmp_path,
        sidechain_read=900_000,
        main_usage={"cache_read_input_tokens": 20_000},
    )
    line = _run(
        {
            "model": {"id": "claude-sonnet-4-6"},  # 200k window
            "workspace": {"project_dir": str(tmp_path)},
            "transcript_path": str(tp),
        }
    )
    assert "10%" in line  # 20k / 200k, not 900k


def test_empty_session_is_zero_percent(tmp_path: Path) -> None:
    line = _run({"model": {"id": "claude-sonnet-4-6"}, "workspace": {"project_dir": str(tmp_path)}})
    assert "0%" in line and "(0/200k)" in line


def test_missing_transcript_does_not_crash(tmp_path: Path) -> None:
    line = _run(
        {
            "model": {"id": "claude-sonnet-4-6"},
            "workspace": {"project_dir": str(tmp_path)},
            "transcript_path": str(tmp_path / "nope.jsonl"),
        }
    )
    assert "0%" in line
