"""Stage 5 — guard against `except BaseException:` swallowing signals.

`memory_bank_skill/_io.py::atomic_write` cleans up the temp file on failure,
but it must NOT swallow `KeyboardInterrupt` / `SystemExit` (subclasses of
`BaseException`, not `Exception`). The cleanup path should still run for
ordinary exceptions like `OSError`.
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest import mock

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill._io import atomic_write  # noqa: E402


def test_atomic_write_does_not_catch_keyboard_interrupt(tmp_path: Path) -> None:
    """KeyboardInterrupt must propagate immediately (otherwise Ctrl-C cannot stop).

    Contract: signals bypass the cleanup branch. A leftover tmp file in this
    case is acceptable — the process is being interrupted, callers must not
    rely on graceful cleanup. The target file MUST NOT have been replaced.
    """
    target = tmp_path / "out.txt"

    def boom_kbd(*_args: object, **_kwargs: object) -> None:
        raise KeyboardInterrupt

    with mock.patch("os.replace", side_effect=boom_kbd), pytest.raises(KeyboardInterrupt):
        atomic_write(target, "payload")

    assert not target.exists(), "target must not be written when os.replace fails"


def test_atomic_write_does_not_catch_system_exit(tmp_path: Path) -> None:
    """SystemExit must propagate so callers can `sys.exit()` cleanly."""
    target = tmp_path / "out.txt"

    def boom_exit(*_args: object, **_kwargs: object) -> None:
        raise SystemExit(2)

    with mock.patch("os.replace", side_effect=boom_exit), pytest.raises(SystemExit):
        atomic_write(target, "payload")


def test_atomic_write_still_catches_os_error_for_cleanup(tmp_path: Path) -> None:
    """OSError still triggers the temp-file cleanup path, then re-raises."""
    target = tmp_path / "out.txt"

    def boom_oserr(*_args: object, **_kwargs: object) -> None:
        raise OSError("disk full")

    with mock.patch("os.replace", side_effect=boom_oserr), pytest.raises(OSError, match="disk full"):
        atomic_write(target, "payload")

    leftovers = [p for p in tmp_path.iterdir() if p.name.startswith(".out.txt.")]
    assert leftovers == [], (
        f"temp file should be cleaned up on OSError, but found {leftovers}"
    )


def test_atomic_write_source_does_not_use_base_exception() -> None:
    """Static contract: `_io.py` must not contain `except BaseException`."""
    src = Path(__file__).resolve().parents[2] / "memory_bank_skill" / "_io.py"
    text = src.read_text(encoding="utf-8")
    assert "except BaseException" not in text, (
        "memory_bank_skill/_io.py must not catch BaseException — "
        "it swallows KeyboardInterrupt/SystemExit. Use `except Exception` "
        "or a narrow exception list instead."
    )


def test_atomic_write_happy_path_unchanged(tmp_path: Path) -> None:
    """Sanity: refactor must not break the success path."""
    target = tmp_path / "ok.txt"
    atomic_write(target, "hello")
    assert target.read_text(encoding="utf-8") == "hello"
    leftovers = [p for p in tmp_path.iterdir() if p.name.startswith(".ok.txt.")]
    assert leftovers == [], f"temp leftovers after success: {leftovers}"
