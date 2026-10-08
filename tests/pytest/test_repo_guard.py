"""The session-wide repo guard in conftest.py."""

from __future__ import annotations

import os
from pathlib import Path

from conftest import REPO_ROOT


def test_manifest_path_defaults_outside_the_repo_checkout():
    # install.sh writes its manifest to $MB_MANIFEST_PATH; without it, next to
    # itself — the owner's live install manifest in this checkout.
    manifest = Path(os.environ["MB_MANIFEST_PATH"])
    assert REPO_ROOT not in manifest.parents
    assert not manifest.exists()


def test_manifest_path_can_still_be_unset_per_test(monkeypatch):
    monkeypatch.delenv("MB_MANIFEST_PATH")
    assert "MB_MANIFEST_PATH" not in os.environ
