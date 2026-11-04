"""Pre-hash OpenCode records: listing proves provenance only, and only for the listed kind."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

FILES = Path(__file__).resolve().parents[2] / "adapters" / "opencode_files.py"


def run(action, path, record, root, *extra, home):
    env = {**os.environ, "HOME": str(home), "PYTHONDONTWRITEBYTECODE": "1"}
    return subprocess.run(
        [sys.executable, str(FILES), action, str(path), str(record), str(root), *map(str, extra)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.fixture
def tree(tmp_path):
    root = tmp_path / "opencode"
    (root / "commands").mkdir(parents=True)
    command = root / "commands" / "adr.md"
    command.write_text("Legacy command with a user edit\n")
    return root, command, root / ".mb-manifest.json"


def record(path, files, hashes=None, **extra):
    data = {"files": [str(f) for f in files], **extra}
    if hashes is not None:
        data["file_sha256"] = {str(f): h for f, h in hashes.items()}
    path.write_text(json.dumps(data))


@pytest.mark.parametrize(
    ("state", "expected"),
    [
        ("listed-unhashed", 0),
        ("listed-hashed-unchanged", 1),
        ("listed-hashed-modified", 1),
        ("unlisted", 1),
        ("listed-empty-hash", 1),
    ],
)
def test_legacy_owned_admits_only_listed_paths_without_a_hash(tree, tmp_path, state, expected):
    root, command, manifest = tree
    digest = hashlib.sha256(command.read_bytes()).hexdigest()
    files = [] if state == "unlisted" else [command]
    hashes = {
        "listed-hashed-unchanged": {command: digest},
        "listed-hashed-modified": {command: "0" * 64},
        "listed-empty-hash": {command: ""},
    }.get(state)
    record(manifest, files, hashes)
    assert run("legacy-owned", command, manifest, root, home=tmp_path).returncode == expected


def test_legacy_owned_refuses_a_symlink_listed_as_a_regular_file(tree, tmp_path):
    root, command, manifest = tree
    target = tmp_path / "private-target"
    target.write_text("Foreign bytes\n")
    command.unlink()
    command.symlink_to(target)
    record(manifest, [command])
    result = run("legacy-owned", command, manifest, root, home=tmp_path)
    assert result.returncode == 1
    assert target.read_text() == "Foreign bytes\n"


def test_legacy_alias_requires_the_recorded_home(tree, tmp_path):
    root, _, manifest = tree
    alias = root / "skills" / "memory-bank"
    alias.parent.mkdir()
    alias.symlink_to(tmp_path)
    record(manifest, [alias], home=str(tmp_path / "other-home"))
    assert run("legacy-owned-alias", alias, manifest, root, home=tmp_path).returncode == 1
    record(manifest, [alias], home=str(tmp_path))
    assert run("legacy-owned-alias", alias, manifest, root, home=tmp_path).returncode == 0


def test_quarantine_moves_a_legacy_file_and_keeps_its_bytes(tree, tmp_path):
    root, command, manifest = tree
    backup = root / ".memory-bank-backups" / "commands__adr.md.pre-mb-backup.1"
    backup.parent.mkdir()
    record(manifest, [command])
    assert run("quarantine", command, manifest, root, backup, home=tmp_path).returncode == 0
    assert not command.exists()
    assert backup.read_text() == "Legacy command with a user edit\n"


@pytest.mark.parametrize("case", ["hashed", "destination-exists", "outside-root"])
def test_quarantine_refuses_without_legacy_authority_or_a_fresh_contained_destination(
    tree, tmp_path, case
):
    root, command, manifest = tree
    backup = root / ".memory-bank-backups" / "commands__adr.md.pre-mb-backup.1"
    backup.parent.mkdir()
    record(
        manifest,
        [command],
        {command: hashlib.sha256(command.read_bytes()).hexdigest()} if case == "hashed" else None,
    )
    if case == "destination-exists":
        backup.write_text("Earlier quarantine\n")
    if case == "outside-root":
        backup = tmp_path / "outside-backup"
    result = run("quarantine", command, manifest, root, backup, home=tmp_path)
    assert result.returncode == 1
    assert command.read_text() == "Legacy command with a user edit\n"
    assert case != "destination-exists" or backup.read_text() == "Earlier quarantine\n"
    assert case != "outside-root" or not backup.exists()
