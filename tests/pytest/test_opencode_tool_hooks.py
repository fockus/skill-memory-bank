"""Shared post-write logging must remain host-isolated for OpenCode."""

import errno
import importlib.util
import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def test_opencode_file_change_log_respects_xdg_even_with_cursor_alias(tmp_path: Path) -> None:
    home = tmp_path / "home"
    xdg = tmp_path / "custom config"
    (home / ".cursor/skills/memory-bank").mkdir(parents=True)
    target = tmp_path / "source.py"
    target.write_text("value = 1\n")
    payload = {"cwd": str(tmp_path), "tool_name": "Write", "tool_input": {"file_path": str(target)}}
    result = subprocess.run(
        ["bash", str(ROOT / "hooks/file-change-log.sh")], input=json.dumps(payload),
        text=True, capture_output=True, check=False,
        env={**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(xdg), "MB_AGENT": "opencode"},
    )
    assert result.returncode == 0
    log = xdg / "opencode/file-changes.log"
    assert str(target) in log.read_text()
    assert log.stat().st_mode & 0o777 == 0o600
    assert not (home / ".cursor/file-changes.log").exists()
    assert not (home / ".claude/file-changes.log").exists()


@pytest.mark.parametrize("failure_code", [errno.EIO, errno.EINTR])
def test_atomic_capture_failure_keeps_old_record_and_retries_message_ids(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, failure_code: int) -> None:
    spec = importlib.util.spec_from_file_location("oc_memory", ROOT / "adapters/opencode_memory.py")
    assert spec and spec.loader
    memory = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(memory)
    monkeypatch.delenv("MB_SESSION_CAPTURE", raising=False)
    monkeypatch.delenv("MB_CAPTURE_SUBPROCESS", raising=False)
    bank = tmp_path / ".memory-bank"
    bank.mkdir()

    def messages(suffix: str) -> list[dict]:
        return [
            {"id": f"u{suffix}", "type": "user", "text": "Continue native work"},
            {"id": f"a{suffix}", "type": "assistant", "finish": "stop", "time": {"completed": 1},
             "content": [{"type": "text", "text": "Decision: Keep the durable record.\nNext: Verify retries."}]},
        ]

    first = memory.capture(bank, "root", messages("1"))
    file = Path(first["file"])
    before = file.read_bytes()
    replace = memory.os.replace

    def fail_replace(*args, **kwargs) -> None:
        raise OSError(failure_code, "simulated I/O failure")

    monkeypatch.setattr(memory.os, "replace", fail_replace)
    with pytest.raises(OSError):
        memory.capture(bank, "root", messages("2"))
    assert file.read_bytes() == before
    assert not list((bank / "session").glob("*.tmp"))
    monkeypatch.setattr(memory.os, "replace", replace)
    assert memory.capture(bank, "root", messages("2"))["changed"] is True
    assert "turns: 2\n" in file.read_text()
    assert memory.capture(bank, "root", messages("2"))["changed"] is False
