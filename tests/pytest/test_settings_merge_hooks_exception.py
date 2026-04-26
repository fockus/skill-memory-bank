"""Stage 5 — same `BaseException` narrowing for `settings/merge-hooks.py`.

The cleanup branch in `merge_hooks` must let `KeyboardInterrupt`/`SystemExit`
propagate, while still removing the temp file for ordinary errors.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from unittest import mock

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MERGE_PATH = REPO_ROOT / "settings" / "merge-hooks.py"


def _load_merge_module():
    """Import `settings/merge-hooks.py` despite the hyphen in the filename."""
    spec = importlib.util.spec_from_file_location("_mb_merge_hooks_under_test", MERGE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["_mb_merge_hooks_under_test"] = module
    spec.loader.exec_module(module)
    return module


def _seed(tmp_path: Path) -> tuple[Path, Path]:
    settings = tmp_path / "settings.json"
    hooks = tmp_path / "hooks.json"
    settings.write_text(json.dumps({"hooks": {}}), encoding="utf-8")
    hooks.write_text(
        json.dumps({"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "echo [memory-bank-skill] x"}]}]}),
        encoding="utf-8",
    )
    return settings, hooks


def test_merge_hooks_does_not_catch_keyboard_interrupt(tmp_path: Path) -> None:
    """KeyboardInterrupt during os.replace must propagate immediately.

    Contract: signals bypass cleanup. A leftover .tmp file is acceptable —
    the process is being interrupted. Settings file MUST stay intact.
    """
    merge = _load_merge_module()
    settings, hooks = _seed(tmp_path)
    original = settings.read_text(encoding="utf-8")

    def boom(*_a: object, **_k: object) -> None:
        raise KeyboardInterrupt

    with mock.patch("os.replace", side_effect=boom), pytest.raises(KeyboardInterrupt):
        merge.merge_hooks(str(settings), str(hooks))

    assert settings.read_text(encoding="utf-8") == original, (
        "settings.json must remain unchanged when os.replace is interrupted"
    )


def test_merge_hooks_does_not_catch_system_exit(tmp_path: Path) -> None:
    """SystemExit must propagate."""
    merge = _load_merge_module()
    settings, hooks = _seed(tmp_path)

    with mock.patch("os.replace", side_effect=SystemExit(3)), pytest.raises(SystemExit):
        merge.merge_hooks(str(settings), str(hooks))


def test_merge_hooks_still_catches_os_error_for_cleanup(tmp_path: Path) -> None:
    """OSError still triggers the cleanup path, then re-raises."""
    merge = _load_merge_module()
    settings, hooks = _seed(tmp_path)

    def boom(*_a: object, **_k: object) -> None:
        raise OSError("disk full")

    with mock.patch("os.replace", side_effect=boom), pytest.raises(OSError, match="disk full"):
        merge.merge_hooks(str(settings), str(hooks))

    leftovers = [p.name for p in tmp_path.iterdir() if p.name.endswith(".tmp")]
    assert leftovers == [], (
        f"merge-hooks must clean up tmp file on OSError, but found {leftovers}"
    )


def test_merge_hooks_source_does_not_use_base_exception() -> None:
    """Static contract: `merge-hooks.py` must not contain `except BaseException`."""
    text = MERGE_PATH.read_text(encoding="utf-8")
    assert "except BaseException" not in text, (
        "settings/merge-hooks.py must not catch BaseException — "
        "use `except Exception` or a narrow exception list."
    )
