"""Tests for `scripts/mb-openspec.py import` — one-way writer + safety guard.

Contract (design.md, T3 tasks.md):
    mb-openspec.py import <change_dir> [--as <topic>] [--mb <bank>]

    - Writes the spec triple under `<bank>/specs/<topic>/`.
    - `requirements.md` carries `openspec_source` + `openspec_hash` frontmatter (REQ-014).
    - Never writes anything outside `<bank>/` — the OpenSpec tree is read-only (REQ-003, NFR-002).
    - Re-running `import` on unchanged source is a content no-op.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-openspec.py"
FIXTURE = (
    REPO_ROOT / "tests" / "pytest" / "fixtures" / "openspec" / "changes" / "add-metadata-tracking"
)


def _run_import(bank: Path, *, topic: str | None = None) -> subprocess.CompletedProcess[str]:
    args = [sys.executable, str(SCRIPT), "import", str(FIXTURE), "--mb", str(bank)]
    if topic:
        args += ["--as", topic]
    return subprocess.run(args, capture_output=True, text=True, check=False)


def _snapshot(root: Path) -> dict[Path, bytes]:
    return {p.relative_to(root): p.read_bytes() for p in root.rglob("*") if p.is_file()}


def test_import_writes_triple_under_bank_specs_topic(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    proc = _run_import(bank)
    assert proc.returncode == 0, proc.stderr

    spec_dir = bank / "specs" / "add-metadata-tracking"
    assert (spec_dir / "requirements.md").is_file()
    assert (spec_dir / "design.md").is_file()
    assert (spec_dir / "tasks.md").is_file()


def test_import_topic_defaults_to_change_id_slug(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    _run_import(bank)
    assert (bank / "specs" / "add-metadata-tracking").is_dir()


def test_import_as_flag_overrides_topic(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    proc = _run_import(bank, topic="custom-topic")
    assert proc.returncode == 0, proc.stderr
    assert (bank / "specs" / "custom-topic" / "requirements.md").is_file()
    assert not (bank / "specs" / "add-metadata-tracking").exists()


def test_import_writes_source_and_hash_frontmatter(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    _run_import(bank)
    content = (bank / "specs" / "add-metadata-tracking" / "requirements.md").read_text(
        encoding="utf-8"
    )
    assert content.startswith("---\n")
    assert f"openspec_source: {FIXTURE}" in content
    assert "openspec_hash: " in content
    # 64 lower-hex chars — a sha256 digest, not a truncated/placeholder value.
    hash_line = next(line for line in content.splitlines() if line.startswith("openspec_hash: "))
    digest = hash_line.split(": ", 1)[1].strip()
    assert len(digest) == 64
    assert all(c in "0123456789abcdef" for c in digest)


def test_import_never_writes_outside_the_bank_directory(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    before = _snapshot(FIXTURE)
    _run_import(bank)
    after = _snapshot(FIXTURE)
    assert before == after  # zero writes anywhere under the OpenSpec change tree


def test_import_rerun_on_unchanged_source_is_a_content_noop(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    _run_import(bank)
    spec_dir = bank / "specs" / "add-metadata-tracking"
    first = _snapshot(spec_dir)

    proc = _run_import(bank)
    assert proc.returncode == 0, proc.stderr
    second = _snapshot(spec_dir)

    assert first == second


def test_import_missing_change_dir_fails_with_nonzero_exit(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    args = [
        sys.executable,
        str(SCRIPT),
        "import",
        str(FIXTURE.parent / "does-not-exist"),
        "--mb",
        str(bank),
    ]
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    assert proc.returncode != 0
    assert "not found" in proc.stderr


def test_import_missing_bank_fails_with_nonzero_exit(tmp_path: Path) -> None:
    missing_bank = tmp_path / "no-such-bank"
    proc = _run_import(missing_bank)
    assert proc.returncode != 0
    assert "not found" in proc.stderr


def test_import_unknown_action_is_a_usage_error() -> None:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "bogus-action"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode != 0
