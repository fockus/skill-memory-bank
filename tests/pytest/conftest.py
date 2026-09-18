"""Shared pytest guards.

Keeps the suite hermetic against the one step that reaches outside the process:
``mb-codegraph.py --apply`` spawns a detached embedding builder when a semantic
venv exists (``~/.claude/hooks/.venv``). Left alone, every apply-mode test on a
developer machine would fork a real fastembed child — and on a cold machine each
one would try to download the model. Tests that want the builder set
``MB_SEMANTIC_PY`` themselves.
"""

from __future__ import annotations

import pytest


@pytest.fixture(autouse=True)
def _no_background_embedder(monkeypatch, tmp_path_factory):
    monkeypatch.setenv("MB_SEMANTIC_PY", str(tmp_path_factory.getbasetemp() / "absent-python"))
