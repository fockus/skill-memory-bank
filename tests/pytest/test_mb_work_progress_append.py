"""`scripts/mb-work-progress-append.sh` — locked, atomic, append-only progress.md writer.

Confirmed gap (I-094 S6): the /mb work loop appends to `progress.md` via free-form
edits (commands/work.md 5d/end-of-run); under intra-plan self-claim there is no
single-writer primitive, so two concurrent appends can interleave/clobber.

Contract under test:
  - append-only: prior content is never rewritten or removed
  - atomic: builds the new content in a temp file (mktemp), then `mv`s over
    progress.md — no partial state is ever visible
  - serialized: an owner-token mkdir lock at `<bank>/.work-progress.lock`
    (mirrors scripts/mb-handoff.sh) makes N concurrent writers race safely
  - fail-safe: a lock that cannot be acquired within the timeout degrades to a
    stderr warning + exit 0 — this helper must never wedge a /mb work loop
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-progress-append.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(
    *args: str, mb: Path, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    import os

    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
        env=full_env,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_append_adds_entry_to_progress(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    progress = mb / "progress.md"
    progress.write_text("# Progress Log\n\n## 2026-01-01\n\n- prior entry\n")

    r = _run("--text", "### NOTE x", mb=mb)
    assert r.returncode == 0, r.stderr

    content = progress.read_text()
    assert content.startswith("# Progress Log\n\n## 2026-01-01\n\n- prior entry\n")
    assert content.rstrip("\n").endswith("### NOTE x")


def test_append_is_append_only(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    progress = mb / "progress.md"
    progress.write_text("# Progress Log\n")

    r1 = _run("--text", "### FIRST entry", mb=mb)
    assert r1.returncode == 0, r1.stderr
    r2 = _run("--text", "### SECOND entry", mb=mb)
    assert r2.returncode == 0, r2.stderr

    content = progress.read_text()
    assert "### FIRST entry" in content
    assert "### SECOND entry" in content
    # both present, in order — the second append never rewrites/removes the first
    assert content.index("### FIRST entry") < content.index("### SECOND entry")


def test_concurrent_appends_do_not_interleave(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    progress = mb / "progress.md"
    progress.write_text("# Progress Log\n")

    n = 8
    procs = []
    for i in range(n):
        block = f"### CONC-{i}\nline-a-{i}\nline-b-{i}\nline-c-{i}"
        procs.append(
            subprocess.Popen(
                ["bash", str(SCRIPT), "--text", block, "--mb", str(mb)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        )

    results = [p.communicate() for p in procs]
    for i, (p, (_out, err)) in enumerate(zip(procs, results, strict=True)):
        assert p.returncode == 0, f"append {i} failed: {err}"

    content = progress.read_text()

    # Each block must appear fully intact and self-consistent — no torn writes,
    # no merged/interleaved lines from a different writer's block.
    pattern = re.compile(r"### CONC-(\d+)\nline-a-(\d+)\nline-b-(\d+)\nline-c-(\d+)")
    matches = pattern.findall(content)
    assert len(matches) == n, f"expected {n} intact entries, found {len(matches)} in:\n{content}"
    seen_ids = set()
    for m in matches:
        assert len(set(m)) == 1, f"torn/interleaved entry: {m}"
        seen_ids.add(m[0])
    assert seen_ids == {str(i) for i in range(n)}

    # append-only: the original header survives untouched.
    assert content.startswith("# Progress Log\n")


def test_append_creates_file_if_missing(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    progress = mb / "progress.md"
    assert not progress.exists()

    r = _run("--text", "### NEW file entry", mb=mb)
    assert r.returncode == 0, r.stderr
    assert progress.is_file()
    assert "### NEW file entry" in progress.read_text()


def test_lock_timeout_degrades_to_warn_exit_0(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    progress = mb / "progress.md"
    progress.write_text("# Progress Log\n")

    lock = mb / ".work-progress.lock"
    lock.mkdir()
    (lock / "owner").write_text("someone-else-1234")

    r = _run(
        "--text",
        "### should not land",
        mb=mb,
        env={"MB_PROGRESS_APPEND_LOCK_TIMEOUT": "1"},
    )

    assert r.returncode == 0, r.stderr
    assert r.stderr.strip() != ""
    # never wedges: fails safely without mutating progress.md
    assert "### should not land" not in progress.read_text()
    # the held lock is left alone — we don't own it, so we must not break it
    assert lock.is_dir()


# ── Edge cases (DoD) ────────────────────────────────────────────────────────


def test_empty_text_is_usage_error_and_writes_nothing(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    progress = mb / "progress.md"
    progress.write_text("# Progress Log\n")

    r = _run("--text", "", mb=mb)
    assert r.returncode == 2
    assert progress.read_text() == "# Progress Log\n"


def test_missing_text_and_file_args_is_usage_error(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run(mb=mb)
    assert r.returncode == 2


def test_append_from_file_source(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    src = tmp_path / "note.txt"
    src.write_text("### FROM file\nbody line")

    r = _run("--file", str(src), mb=mb)
    assert r.returncode == 0, r.stderr
    content = (mb / "progress.md").read_text()
    assert "### FROM file" in content
    assert "body line" in content
