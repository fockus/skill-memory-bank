"""OpenCode handled I/O: a retained preimage must not depend on privileges the user lacks."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ADAPTERS = Path(__file__).resolve().parents[2] / "adapters"
sys.path.insert(0, str(ADAPTERS))

import opencode_install_io as io  # noqa: E402


def test_prepare_with_unsettable_group_retains_preimage_and_rolls_back(tmp_path, monkeypatch):
    # Arrange: a managed file whose group the user cannot hand to a new file. On macOS a
    # file under /private/tmp inherits group wheel, which an ordinary user is not in, so
    # the kernel refuses chown of the retained copy with EPERM.
    root = tmp_path / "opencode"
    root.mkdir()
    target = root / "AGENTS.md"
    target.write_text("original\n")
    record = root / ".mb-manifest.json"
    record.write_text("{}")
    context = tmp_path / "recovery"
    context.mkdir(mode=0o700)

    def refuse(*_args, **_kwargs):
        raise PermissionError(1, "Operation not permitted")

    monkeypatch.setattr(os, "chown", refuse)
    spec = json.dumps([{"path": str(target)}])

    # Act: prepare the operation, mutate the file, then roll back.
    io.prepare(context, str(record), str(root), spec)
    target.write_text("rewritten\n")
    io.mark(context)
    io.abort(context)

    # Assert: the original bytes are back and the operation is closed.
    assert target.read_text() == "original\n"
    assert not (context / "pending.json").exists()
