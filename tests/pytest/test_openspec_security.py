"""Codex GPT-5.5 release-gate review — exploit/regression tests for F1, F2,
F4, F7 (`scripts/mb-openspec.py` writer + `scripts/mb_openspec_normalize.py`
cache), plus the round-2 residual findings R1/R3/R4/R5 on those same fixes.

Each test reproduces the claimed defect first (must fail against the
pre-fix code) and guards the fix afterwards.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"
SCRIPT = REPO_ROOT / "scripts" / "mb-openspec.py"
FIXTURE = (
    REPO_ROOT / "tests" / "pytest" / "fixtures" / "openspec" / "changes" / "add-metadata-tracking"
)

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import mb_openspec_normalize as normalize_mod  # noqa: E402


def _load_openspec_module():
    """Load `scripts/mb-openspec.py` as an importable module (hyphenated
    filename can't be `import`ed directly) -- fresh instance per test so
    monkeypatching `atomic_write` on it never leaks across tests."""
    spec = importlib.util.spec_from_file_location("mb_openspec_cli_under_test", SCRIPT)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _run_import(
    bank: Path, *, topic: str, change_dir: Path = FIXTURE
) -> subprocess.CompletedProcess[str]:
    args = [
        sys.executable,
        str(SCRIPT),
        "import",
        str(change_dir),
        "--as",
        topic,
        "--mb",
        str(bank),
    ]
    return subprocess.run(args, capture_output=True, text=True, check=False)


# ---------------------------------------------------------------------------
# F1 -- `--as <topic>` path traversal
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("topic", ["..", "../evil", "foo/bar", ".", "a/../../evil", "a\\b"])
def test_import_rejects_path_traversal_topics(tmp_path: Path, topic: str) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()

    proc = _run_import(bank, topic=topic)

    assert proc.returncode != 0, f"topic {topic!r} must be rejected, got: {proc.stdout}"
    # Nothing must land outside `<bank>/specs/`.
    written = [p for p in tmp_path.rglob("*") if p.is_file()]
    for p in written:
        assert bank / "specs" in p.parents or p.parent == bank / "specs", (
            f"file written outside specs/: {p}"
        )
    # And specifically: nothing directly under the bank root, nothing outside it.
    assert not (bank / "requirements.md").exists()
    assert not (tmp_path / "evil").exists()


def test_import_accepts_a_normal_slug_topic(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    proc = _run_import(bank, topic="my-topic_1.2")
    assert proc.returncode == 0, proc.stderr
    assert (bank / "specs" / "my-topic_1.2" / "requirements.md").is_file()


# ---------------------------------------------------------------------------
# F2 -- NormalizeCache.flush() bypasses the bank-safe write guard
# ---------------------------------------------------------------------------


def test_normalize_cache_flush_refuses_to_write_through_a_symlink_escape(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    (bank / ".index").mkdir()
    os.symlink(outside, bank / ".index" / "openspec")

    cache = normalize_mod.NormalizeCache(bank)
    cache.set("deadbeef", {"text": "x", "scenario": None, "covers": []})
    cache.flush()  # must not raise -- fail-open, but must not write outside

    assert list(outside.rglob("*")) == []  # nothing escaped the bank


# ---------------------------------------------------------------------------
# F4 -- frontmatter stores a cwd-relative source path
# ---------------------------------------------------------------------------


def _write_demo_change(change_dir: Path) -> None:
    (change_dir / "specs" / "demo").mkdir(parents=True, exist_ok=True)
    (change_dir / "proposal.md").write_text(
        "## Why\n\nDemo change.\n\n## What Changes\n\n- Demo.\n", encoding="utf-8"
    )
    (change_dir / "specs" / "demo" / "spec.md").write_text(
        "## ADDED Requirements\n\n### Requirement: Demo Thing\nThe system SHALL do the thing.\n",
        encoding="utf-8",
    )
    (change_dir / "tasks.md").write_text("## 1. Setup\n- [ ] do it\n", encoding="utf-8")


def test_import_via_relative_path_then_status_from_a_different_cwd(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = tmp_path / "openspec" / "changes" / "demo"
    _write_demo_change(change_dir)

    rel_change_dir = os.path.relpath(change_dir, tmp_path)
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "import", rel_change_dir, "--as", "demo", "--mb", str(bank)],
        capture_output=True,
        text=True,
        check=False,
        cwd=str(tmp_path),
    )
    assert proc.returncode == 0, proc.stderr

    # Run `status` from a DIFFERENT cwd -- the stored source path must still
    # resolve to the real change directory, not a (now meaningless) relative
    # path resolved against the new cwd.
    other_cwd = tmp_path / "elsewhere"
    other_cwd.mkdir()
    status_proc = subprocess.run(
        [sys.executable, str(SCRIPT), "status", "demo", "--mb", str(bank.resolve())],
        capture_output=True,
        text=True,
        check=False,
        cwd=str(other_cwd),
    )
    assert status_proc.returncode == 0, status_proc.stderr
    assert "status: imported" in status_proc.stdout
    assert "source missing" not in status_proc.stderr


# ---------------------------------------------------------------------------
# F7 -- triple write order: requirements.md (with the new hash) must be
# written LAST so a crash mid-triple never leaves a stale hash "current".
# ---------------------------------------------------------------------------


def test_import_crash_after_first_write_never_finalizes_a_stale_hash(
    tmp_path: Path, monkeypatch
) -> None:
    mod = _load_openspec_module()

    calls = {"n": 0}
    orig_atomic_write = mod.atomic_write

    def flaky(path, content):
        calls["n"] += 1
        if calls["n"] == 2:
            raise RuntimeError("simulated crash mid-triple")
        return orig_atomic_write(path, content)

    monkeypatch.setattr(mod, "atomic_write", flaky)

    bank = tmp_path / ".memory-bank"
    bank.mkdir()

    with pytest.raises(RuntimeError, match="simulated crash mid-triple"):
        mod.run_import(change_dir=FIXTURE, mb_path=bank, topic="demo")

    # The hash-bearing requirements.md must not exist if the OTHER two files
    # of the triple never landed -- otherwise a future `sync`/`status` would
    # see "imported" (hash matches) on a half-written triple and no-op
    # forever, dropping REQ-017's orphan-move.
    req_path = bank / "specs" / "demo" / "requirements.md"
    design_path = bank / "specs" / "demo" / "design.md"
    tasks_path = bank / "specs" / "demo" / "tasks.md"
    if req_path.is_file():
        assert design_path.is_file() and tasks_path.is_file(), (
            "requirements.md (hash) landed while design.md/tasks.md are missing "
            "-- a future sync would wrongly treat this topic as up to date"
        )


# ---------------------------------------------------------------------------
# R1 (Codex round-2) -- orphan-to-backlog must be recorded BEFORE the
# hash-bearing requirements.md is finalized, and the append must be
# idempotent so a retried import never double-appends.
# ---------------------------------------------------------------------------


def _write_task_change(change_dir: Path, task_lines: list[str]) -> None:
    (change_dir / "specs" / "demo").mkdir(parents=True, exist_ok=True)
    (change_dir / "proposal.md").write_text(
        "## Why\n\nDemo change.\n\n## What Changes\n\n- Demo.\n", encoding="utf-8"
    )
    (change_dir / "specs" / "demo" / "spec.md").write_text(
        "## ADDED Requirements\n\n### Requirement: Demo Thing\nThe system SHALL do the thing.\n",
        encoding="utf-8",
    )
    (change_dir / "tasks.md").write_text(
        "## 1. Setup\n\n" + "\n".join(task_lines) + "\n", encoding="utf-8"
    )


def test_reimport_crash_during_backlog_write_never_finalizes_hash_without_orphan(
    tmp_path: Path, monkeypatch
) -> None:
    """R1: with the fixed ordering (design/tasks -> backlog append ->
    requirements.md LAST), a crash exactly inside the backlog.md write must
    happen BEFORE the hash-bearing requirements.md is updated to the NEW
    hash -- there must never be a window where the stored hash is "current"
    while the REQ-017 orphan was never recorded."""
    mod = _load_openspec_module()
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = tmp_path / "openspec" / "changes" / "demo"

    _write_task_change(change_dir, ["- [ ] keep this", "- [ ] drop this"])
    mod.run_import(change_dir=change_dir, mb_path=bank, topic="demo")

    _write_task_change(change_dir, ["- [ ] keep this"])  # "drop this" vanishes -> orphan
    new_hash = mod.compute_source_hash(change_dir)

    orig_atomic_write = mod.atomic_write

    def crash_on_backlog(path, content):
        if Path(path).name == "backlog.md":
            raise RuntimeError("simulated crash writing backlog.md")
        return orig_atomic_write(path, content)

    monkeypatch.setattr(mod, "atomic_write", crash_on_backlog)

    with pytest.raises(RuntimeError, match="simulated crash writing backlog.md"):
        mod.run_import(change_dir=change_dir, mb_path=bank, topic="demo")

    req_text = (bank / "specs" / "demo" / "requirements.md").read_text(encoding="utf-8")
    fm = mod._parse_frontmatter(req_text)
    assert fm.get("openspec_hash") != new_hash, (
        "requirements.md was finalized to the NEW hash even though the backlog "
        "append (REQ-017 orphan recording) crashed first -- a future sync would "
        "wrongly treat this topic as up to date, losing the orphan forever"
    )


def test_reimport_crash_right_after_tasks_write_then_retry_never_loses_orphan(
    tmp_path: Path, monkeypatch
) -> None:
    """Codex round-3: the OLD order (design -> tasks (orphan-stripped) ->
    backlog append -> requirements) has a crash window BETWEEN the tasks.md
    write and the backlog append. tasks.md is the only on-disk record of the
    prior task state; once it lands orphan-stripped, a crash right there --
    then a RETRY -- makes `_read_prior_triple` read the already-stripped
    tasks.md, so `merge_task_state` never re-detects the orphan on the
    retry and it is permanently, silently lost (REQ-017 violation).

    This test lets the tasks.md write actually land on disk (simulating the
    write committing) and THEN raises, i.e. the process dies exactly in the
    gap between "tasks.md committed" and "backlog.md appended". A second,
    healthy `run_import` call then simulates the process restarting and
    retrying the same import. The orphaned task must still end up in
    `backlog.md` -- it must never vanish across the crash+retry.

    Must FAIL against the pre-fix ordering (backlog append after tasks.md)
    and PASS once the backlog append is moved before the tasks.md write.
    """
    mod = _load_openspec_module()
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = tmp_path / "openspec" / "changes" / "demo"

    _write_task_change(change_dir, ["- [ ] keep this", "- [ ] drop this"])
    mod.run_import(change_dir=change_dir, mb_path=bank, topic="demo")

    _write_task_change(change_dir, ["- [ ] keep this"])  # "drop this" vanishes -> orphan

    orig_atomic_write = mod.atomic_write

    def crash_right_after_tasks_lands(path, content):
        if Path(path).name == "tasks.md":
            orig_atomic_write(path, content)  # the write COMMITS to disk...
            raise RuntimeError("simulated crash between tasks.md and backlog.md")
        return orig_atomic_write(path, content)

    monkeypatch.setattr(mod, "atomic_write", crash_right_after_tasks_lands)

    with pytest.raises(RuntimeError, match="simulated crash between tasks.md and backlog.md"):
        mod.run_import(change_dir=change_dir, mb_path=bank, topic="demo")

    # Process "restarts" and retries the same import with a healthy writer.
    monkeypatch.setattr(mod, "atomic_write", orig_atomic_write)
    mod.run_import(change_dir=change_dir, mb_path=bank, topic="demo")

    backlog_path = bank / "backlog.md"
    assert backlog_path.is_file(), (
        "orphaned task never reached backlog.md across the crash+retry -- lost"
    )
    backlog = backlog_path.read_text(encoding="utf-8")
    assert "drop this" in backlog, (
        "the orphaned task was permanently and silently lost across the "
        "crash+retry -- it never reached backlog.md (REQ-017 data loss)"
    )


def test_append_orphans_to_backlog_is_idempotent_for_same_topic_and_hash(
    tmp_path: Path,
) -> None:
    """R1: a retried append for the SAME topic+source_hash must not duplicate
    the orphan note -- keyed by the `<!-- openspec-orphans: ... -->` marker."""
    mod = _load_openspec_module()
    bank = tmp_path / ".memory-bank"
    bank.mkdir()

    mod._append_orphans_to_backlog(bank, "demo", ["- [ ] drop this"], "abc123def456")
    mod._append_orphans_to_backlog(bank, "demo", ["- [ ] drop this"], "abc123def456")

    backlog = (bank / "backlog.md").read_text(encoding="utf-8")
    assert backlog.count("drop this") == 1
    assert backlog.count(mod._orphan_backlog_marker("demo", "abc123def456")) == 1


# ---------------------------------------------------------------------------
# R2 (Codex round-2) -- see test_openspec_reimport.py for the disambiguated-
# anchor-collides-with-a-literal-name test (co-located with the F3 tests it
# extends).
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# R3 (Codex round-2) -- trailing-dot topic slug, and a symlinked
# `specs/<topic>/` escaping the bank, refused on import/status/sync.
# ---------------------------------------------------------------------------


def test_import_rejects_a_trailing_dot_topic(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    proc = _run_import(bank, topic="foo.")
    assert proc.returncode != 0, proc.stdout
    assert not (bank / "specs" / "foo.").exists()


def _plant_symlinked_topic_dir(bank: Path, topic: str) -> Path:
    """Plant `specs/<topic>` as a symlink pointing SOMEWHERE ELSE INSIDE the
    bank (``bank/elsewhere``), NOT outside the bank entirely -- the residual
    R3 case: `_assert_within(mb_path, spec_dir)` alone does not catch this
    (the resolved target still lives under `mb_path`), unlike a symlink
    escaping the bank root itself (already caught pre-R3)."""
    (bank / "specs").mkdir(parents=True, exist_ok=True)
    outside = bank / "elsewhere"
    outside.mkdir(parents=True, exist_ok=True)
    (outside / "requirements.md").write_text(
        "---\nopenspec_source: /nowhere\nopenspec_hash: deadbeef\n---\n\n# Requirements\n",
        encoding="utf-8",
    )
    os.symlink(outside, bank / "specs" / topic)
    return outside


def test_import_refuses_a_symlinked_topic_dir_escaping_specs(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    outside = _plant_symlinked_topic_dir(bank, "evil-topic")

    proc = _run_import(bank, topic="evil-topic")
    assert proc.returncode != 0, proc.stdout
    # Nothing must have been written through the symlink.
    assert (outside / "requirements.md").read_text(encoding="utf-8").count("openspec_source") == 1


def test_status_refuses_a_symlinked_topic_dir_escaping_specs(tmp_path: Path) -> None:
    mod = _load_openspec_module()
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    _plant_symlinked_topic_dir(bank, "evil-topic")

    with pytest.raises(RuntimeError, match="symlink"):
        mod.run_status(mb_path=bank, topic="evil-topic")


def test_sync_refuses_a_symlinked_topic_dir_escaping_specs(tmp_path: Path) -> None:
    mod = _load_openspec_module()
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    _plant_symlinked_topic_dir(bank, "evil-topic")

    with pytest.raises(RuntimeError, match="symlink"):
        mod.run_sync(mb_path=bank, topic="evil-topic")


def test_sync_all_topics_skips_a_symlinked_topic_dir_as_an_error_entry(
    tmp_path: Path,
) -> None:
    """`sync` with no explicit topic must not abort entirely because ONE
    discovered topic dir happens to be a symlink escape -- it degrades to a
    per-topic error entry, same as any other per-topic sync failure."""
    mod = _load_openspec_module()
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    _plant_symlinked_topic_dir(bank, "evil-topic")

    results = mod.run_sync(mb_path=bank, topic=None)
    assert len(results) == 1
    assert results[0]["topic"] == "evil-topic"
    assert results[0]["action"] == "error"
    assert "symlink" in results[0]["reason"]


# ---------------------------------------------------------------------------
# R4 (Codex round-2) -- NormalizeCache.flush() must fail-open on an OSError
# raised during path resolution too, not just a ValueError.
# ---------------------------------------------------------------------------


def test_normalize_cache_flush_oserror_during_resolve_warns_and_does_not_raise(
    tmp_path: Path, monkeypatch, capsys
) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    cache = normalize_mod.NormalizeCache(bank)
    cache.set("deadbeef", {"text": "x", "scenario": None, "covers": []})

    orig_resolve = Path.resolve

    def flaky_resolve(self, *args, **kwargs):
        if self.name == "normalize-cache.json":
            raise OSError("simulated resolve failure")
        return orig_resolve(self, *args, **kwargs)

    monkeypatch.setattr(Path, "resolve", flaky_resolve)

    cache.flush()  # must not raise -- fail-open

    captured = capsys.readouterr()
    assert "warn" in captured.err.lower()
    assert not (bank / ".index" / "openspec" / "normalize-cache.json").exists()


def test_cli_import_normalize_survives_cache_resolve_oserror_exits_zero(
    tmp_path: Path, monkeypatch
) -> None:
    """End-to-end: an OSError inside the cache's resolve-and-guard must never
    surface as an import failure -- the deterministic import still succeeds.

    ``default_llm_dispatch`` is stubbed to a fast, deterministic fake so this
    test stays hermetic/quick instead of shelling out to the real (slow,
    environment-dependent) sub-invoke resolver -- R4 is about the cache's own
    fail-open guard, not the LLM dispatch path.
    """
    mod = _load_openspec_module()
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    monkeypatch.setattr(
        normalize_mod,
        "default_llm_dispatch",
        lambda payload: {"text": payload["text"], "scenario": None, "covers": []},
    )

    orig_resolve = Path.resolve

    def flaky_resolve(self, *args, **kwargs):
        if self.name == "normalize-cache.json":
            raise OSError("simulated resolve failure")
        return orig_resolve(self, *args, **kwargs)

    monkeypatch.setattr(Path, "resolve", flaky_resolve)

    result = mod.run_import(change_dir=FIXTURE, mb_path=bank, topic="demo", normalize=True)
    assert result["topic"] == "demo"
    assert (bank / "specs" / "demo" / "requirements.md").is_file()


# ---------------------------------------------------------------------------
# R5 (Codex round-2) -- frontmatter must never leak an absolute local path;
# status/sync must stay cwd-independent; a repeated sync must be a
# byte-stable no-op.
# ---------------------------------------------------------------------------


def test_import_frontmatter_never_leaks_an_absolute_path(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = tmp_path / "openspec" / "changes" / "demo"
    _write_demo_change(change_dir)

    rel_change_dir = os.path.relpath(change_dir, tmp_path)
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "import", rel_change_dir, "--as", "demo", "--mb", str(bank)],
        capture_output=True,
        text=True,
        check=False,
        cwd=str(tmp_path),
    )
    assert proc.returncode == 0, proc.stderr

    req_text = (bank / "specs" / "demo" / "requirements.md").read_text(encoding="utf-8")
    fm_source = req_text.splitlines()[1].split(":", 1)[1].strip()
    assert not Path(fm_source).is_absolute(), (
        f"openspec_source stored as an absolute path ({fm_source!r}) -- leaks the "
        "local filesystem layout into a normally-committed file"
    )
    # Belt-and-braces environment-independent checks too (not just "not absolute").
    assert "/Users/" not in req_text
    home = os.path.expanduser("~")
    if home and home != "/":
        assert home not in req_text


def test_status_and_sync_are_cwd_independent_with_relative_frontmatter_path(
    tmp_path: Path,
) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change_dir = tmp_path / "openspec" / "changes" / "demo"
    _write_demo_change(change_dir)

    rel_change_dir = os.path.relpath(change_dir, tmp_path)
    import_proc = subprocess.run(
        [sys.executable, str(SCRIPT), "import", rel_change_dir, "--as", "demo", "--mb", str(bank)],
        capture_output=True,
        text=True,
        check=False,
        cwd=str(tmp_path),
    )
    assert import_proc.returncode == 0, import_proc.stderr

    req_text_after_import = (bank / "specs" / "demo" / "requirements.md").read_text(
        encoding="utf-8"
    )
    fm_source = req_text_after_import.splitlines()[1].split(":", 1)[1].strip()
    assert not Path(fm_source).is_absolute(), (
        f"openspec_source stored absolute ({fm_source!r}) instead of bank-relative"
    )

    other_cwd = tmp_path / "elsewhere"
    other_cwd.mkdir()

    status_proc = subprocess.run(
        [sys.executable, str(SCRIPT), "status", "demo", "--mb", str(bank.resolve())],
        capture_output=True,
        text=True,
        check=False,
        cwd=str(other_cwd),
    )
    assert status_proc.returncode == 0, status_proc.stderr
    assert "status: imported" in status_proc.stdout

    before = (bank / "specs" / "demo" / "requirements.md").read_text(encoding="utf-8")

    sync_proc = subprocess.run(
        [sys.executable, str(SCRIPT), "sync", "demo", "--mb", str(bank.resolve())],
        capture_output=True,
        text=True,
        check=False,
        cwd=str(other_cwd),
    )
    assert sync_proc.returncode == 0, sync_proc.stderr
    assert "up to date" in sync_proc.stdout  # a no-op, not a re-import

    after = (bank / "specs" / "demo" / "requirements.md").read_text(encoding="utf-8")
    assert after == before, "an unchanged source must sync to a byte-stable no-op"
