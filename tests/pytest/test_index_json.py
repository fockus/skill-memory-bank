"""Tests for scripts/mb-index-json.py.

Contract:
    mb-index-json <mb_path> scans notes/ for frontmatter + lessons.md for
    ### markers and writes .memory-bank/index.json atomically.

    Entry shape:
      {
        "notes": [
          {"path": "notes/2026-04-19_auth.md", "type": "note",
           "tags": ["auth","bug"], "importance": "high",
           "summary": "first 2 lines without frontmatter"}
        ],
        "lessons": [
          {"id": "L-001", "title": "Lesson name"}
        ],
        "generated_at": "2026-04-19T12:00:00Z"
      }
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
INDEX_SCRIPT = REPO_ROOT / "scripts" / "mb-index-json.py"


def _load_index_module():
    spec = importlib.util.spec_from_file_location("mb_index_json", INDEX_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def index_mod():
    if not INDEX_SCRIPT.exists():
        pytest.skip("scripts/mb-index-json.py not implemented yet (TDD red)")
    return _load_index_module()


@pytest.fixture
def mb_path(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "notes").mkdir(parents=True)
    (mb / "lessons.md").write_text("# Lessons\n")
    return mb


def make_note(mb: Path, name: str, body: str) -> Path:
    f = mb / "notes" / name
    f.write_text(body)
    return f


def run_cli(mb: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(INDEX_SCRIPT), str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


# ═══════════════════════════════════════════════════════════════
# Frontmatter extraction
# ═══════════════════════════════════════════════════════════════


def test_valid_frontmatter_extracted(index_mod, mb_path):
    make_note(
        mb_path,
        "auth.md",
        textwrap_dedent(
            """
            ---
            type: note
            tags: [auth, bug]
            importance: high
            ---

            Bug fix description.
            Second line of summary.
            """
        ),
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    assert len(data["notes"]) == 1
    entry = data["notes"][0]
    assert entry["type"] == "note"
    assert set(entry["tags"]) == {"auth", "bug"}
    assert entry["importance"] == "high"


def test_missing_frontmatter_uses_defaults(index_mod, mb_path):
    make_note(mb_path, "plain.md", "No frontmatter here.\nJust text.\n")
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    entry = data["notes"][0]
    assert entry["type"] == "note"  # default
    assert entry["tags"] == []  # default
    assert entry.get("importance") in (None, "medium")


def test_malformed_frontmatter_does_not_crash(index_mod, mb_path):
    # Broken YAML inside fence — script must fall back to defaults.
    make_note(
        mb_path,
        "broken.md",
        "---\ntype: note\ntags: [unterminated\n---\n\nbody\n",
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    assert len(data["notes"]) == 1


def test_summary_is_first_two_non_empty_body_lines(index_mod, mb_path):
    make_note(
        mb_path,
        "summary.md",
        textwrap_dedent(
            """
            ---
            type: lesson
            ---

            First summary line.
            Second summary line.
            Third — not included.
            """
        ),
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    summary = data["notes"][0]["summary"]
    assert "First summary line." in summary
    assert "Second summary line." in summary
    assert "Third" not in summary


# ═══════════════════════════════════════════════════════════════
# lessons.md parsing
# ═══════════════════════════════════════════════════════════════


def test_lessons_h3_entries_extracted(index_mod, mb_path):
    (mb_path / "lessons.md").write_text(
        textwrap_dedent(
            """
            # Lessons

            ### L-001: Do not commit .env

            details...

            ### L-002: Validate migrations on staging

            details...
            """
        )
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    lessons = data["lessons"]
    assert len(lessons) == 2
    titles = [lesson["title"] for lesson in lessons]
    assert any("Do not commit .env" in t for t in titles)
    ids = [lesson["id"] for lesson in lessons]
    assert "L-001" in ids and "L-002" in ids


def test_no_lessons_yields_empty_list(index_mod, mb_path):
    (mb_path / "lessons.md").write_text("# Lessons\n\n(no lessons)\n")
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    assert data["lessons"] == []


# ═══════════════════════════════════════════════════════════════
# Atomic write
# ═══════════════════════════════════════════════════════════════


def test_atomic_write_no_tmp_leftover(index_mod, mb_path):
    make_note(mb_path, "a.md", "---\ntype: note\n---\nbody\n")
    index_mod.build_index(str(mb_path))

    leftovers = list(mb_path.glob("index.json.*"))
    assert leftovers == []


def test_atomic_rewrite_preserves_on_failure(index_mod, mb_path, monkeypatch):
    """Simulated write failure must leave previous index.json intact (or absent)."""
    # First, write a valid index
    make_note(mb_path, "a.md", "---\ntype: note\n---\nbody\n")
    index_mod.build_index(str(mb_path))
    original = (mb_path / "index.json").read_text()

    # Now patch os.replace to raise, then call build_index again
    import os

    original_replace = os.replace

    def failing_replace(*args, **kwargs):
        raise OSError("simulated replace failure")

    monkeypatch.setattr(os, "replace", failing_replace)
    with pytest.raises(OSError):
        index_mod.build_index(str(mb_path))

    # index.json either (a) still contains original content or (b) absent — but never corrupted
    if (mb_path / "index.json").exists():
        assert (mb_path / "index.json").read_text() == original
    # Restore
    monkeypatch.setattr(os, "replace", original_replace)


# ═══════════════════════════════════════════════════════════════
# Schema / meta
# ═══════════════════════════════════════════════════════════════


def test_index_has_generated_at(index_mod, mb_path):
    index_mod.build_index(str(mb_path))
    data = json.loads((mb_path / "index.json").read_text())
    assert "generated_at" in data
    # Rough ISO8601 format check
    assert "T" in data["generated_at"]


def test_cli_interface(mb_path):
    if not INDEX_SCRIPT.exists():
        pytest.skip("scripts/mb-index-json.py not implemented yet")
    result = run_cli(mb_path)
    assert result.returncode == 0, result.stderr
    assert (mb_path / "index.json").exists()


def test_cli_missing_mb_path_errors(tmp_path):
    if not INDEX_SCRIPT.exists():
        pytest.skip("scripts/mb-index-json.py not implemented yet")
    result = run_cli(tmp_path / "nonexistent")
    assert result.returncode != 0


def test_cli_usage_on_no_args():
    if not INDEX_SCRIPT.exists():
        pytest.skip("scripts/mb-index-json.py not implemented yet")
    result = subprocess.run(
        [sys.executable, str(INDEX_SCRIPT)], capture_output=True, text=True, check=False
    )
    assert result.returncode != 0
    assert "Usage" in result.stdout + result.stderr


# ═══════════════════════════════════════════════════════════════
# Coverage-driving: fallback YAML, edge cases
# ═══════════════════════════════════════════════════════════════


def test_tag_as_single_string_wrapped_in_list(index_mod, mb_path):
    make_note(mb_path, "one-tag.md", "---\ntype: note\ntags: solo\n---\nbody\n")
    index_mod.build_index(str(mb_path))
    data = json.loads((mb_path / "index.json").read_text())
    assert data["notes"][0]["tags"] == ["solo"]


def test_fallback_yaml_parse_without_pyyaml(index_mod, monkeypatch):
    """If PyYAML raises, _simple_yaml_parse handles common cases."""
    import builtins

    real_import = builtins.__import__

    def no_yaml(name, *args, **kwargs):
        if name == "yaml":
            raise ImportError("simulated — yaml unavailable")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", no_yaml)

    raw = "type: lesson\ntags: [a, b]\nimportance: high"
    meta, body = index_mod._parse_frontmatter(f"---\n{raw}\n---\nbody\n")
    assert meta["type"] == "lesson"
    assert meta["tags"] == ["a", "b"]
    assert meta["importance"] == "high"


def test_simple_yaml_handles_empty_list(index_mod):
    meta = index_mod._simple_yaml_parse("tags: []\ntype: note")
    assert meta["tags"] == []
    assert meta["type"] == "note"


def test_simple_yaml_skips_comment_and_blank(index_mod):
    meta = index_mod._simple_yaml_parse("# leading comment\n\ntype: note\n: no-key-line\n")
    assert meta == {"type": "note"}


def test_index_notes_empty_dir_returns_nothing(index_mod, tmp_path):
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "lessons.md").write_text("# L\n")
    index_mod.build_index(str(mb))
    data = json.loads((mb / "index.json").read_text())
    assert data["notes"] == []


def test_missing_lessons_file_handled(index_mod, tmp_path):
    mb = tmp_path / ".memory-bank"
    (mb / "notes").mkdir(parents=True)
    # no lessons.md
    index_mod.build_index(str(mb))
    data = json.loads((mb / "index.json").read_text())
    assert data["lessons"] == []


def test_frontmatter_with_yaml_list_not_dict(index_mod, mb_path):
    """Frontmatter containing a top-level YAML list → defaults."""
    make_note(mb_path, "weird.md", "---\n- item1\n- item2\n---\n\nbody\n")
    index_mod.build_index(str(mb_path))
    data = json.loads((mb_path / "index.json").read_text())
    # Should still record entry with defaults
    assert len(data["notes"]) == 1
    assert data["notes"][0]["tags"] == []


# ═══════════════════════════════════════════════════════════════
# PII markers — <private>...</private> (Stage 3 v2.1)
# ═══════════════════════════════════════════════════════════════


def test_private_block_excluded_from_summary(index_mod, mb_path):
    """Contents of <private>...</private> do not appear in the summary entry."""
    make_note(
        mb_path,
        "pii.md",
        textwrap_dedent(
            """
            ---
            type: note
            ---

            Discussion with client <private>Ivan Ivanov, +7-900-123</private>.
            Decision: migrate to the new API.
            """
        ),
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    summary = data["notes"][0]["summary"]
    assert "Ivanov" not in summary
    assert "123" not in summary
    # Surrounding context is preserved
    assert "client" in summary or "migrate" in summary


def test_has_private_flag_true_when_block_present(index_mod, mb_path):
    """Entry gets has_private: True when the body contains a <private> block."""
    make_note(
        mb_path,
        "secret.md",
        "---\ntype: note\n---\n\nthere was <private>something</private> in the text.\n",
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    assert data["notes"][0].get("has_private") is True


def test_has_private_flag_false_when_absent(index_mod, mb_path):
    """Entry without private blocks: has_private: False (or absent)."""
    make_note(mb_path, "clean.md", "---\ntype: note\n---\n\nclean text.\n")
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    assert data["notes"][0].get("has_private") in (False, None)


def test_multiple_private_blocks_all_excluded(index_mod, mb_path):
    """Multiple <private> blocks — all are redacted from the summary."""
    make_note(
        mb_path,
        "multi.md",
        textwrap_dedent(
            """
            ---
            type: note
            ---

            Client <private>A1-secret</private> and key <private>B2-token</private>.
            Public info OK.
            """
        ),
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    summary = data["notes"][0]["summary"]
    assert "A1-secret" not in summary
    assert "B2-token" not in summary
    assert data["notes"][0]["has_private"] is True


def test_unclosed_private_fence_graceful(index_mod, mb_path):
    """Unclosed <private> without </private> → parser does not crash, tail excluded."""
    make_note(
        mb_path,
        "broken.md",
        "---\ntype: note\n---\n\nsafe text <private>leak-must-be-excluded\n",
    )
    # Must not raise
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    summary = data["notes"][0]["summary"]
    assert "leak" not in summary
    assert data["notes"][0]["has_private"] is True


def test_nested_markdown_inside_private_excluded(index_mod, mb_path):
    """Markdown (lists, bold) inside <private> is removed correctly."""
    make_note(
        mb_path,
        "nested.md",
        textwrap_dedent(
            """
            ---
            type: note
            ---

            Project X.
            <private>
            - secret list item
            - **bold** secret
            </private>
            Continuation.
            """
        ),
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    summary = data["notes"][0]["summary"]
    assert "secret" not in summary
    assert "bold" not in summary


def test_private_in_tags_field_ignored(index_mod, mb_path):
    """Protective check: if a tag contains a <private> marker — ignore it."""
    make_note(
        mb_path,
        "paranoia.md",
        '---\ntype: note\ntags: [public, "<private>leak</private>"]\n---\n\nbody\n',
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    tags_json = json.dumps(data["notes"][0]["tags"])
    assert "<private>" not in tags_json
    assert "leak" not in tags_json


# ═══════════════════════════════════════════════════════════════
# Archived flag (notes/archive/)
# ═══════════════════════════════════════════════════════════════


def test_archived_flag_true_for_notes_archive_subdir(index_mod, mb_path):
    """notes/archive/X.md → entry.archived: True."""
    archive = mb_path / "notes" / "archive"
    archive.mkdir(parents=True, exist_ok=True)
    (archive / "old.md").write_text("---\ntype: note\nimportance: low\n---\n\nArchived summary.\n")
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    assert len(data["notes"]) == 1
    assert data["notes"][0]["archived"] is True
    assert data["notes"][0]["path"] == "notes/archive/old.md"


def test_archived_flag_false_for_regular_notes(index_mod, mb_path):
    """notes/X.md (not in archive) → archived: False."""
    make_note(
        mb_path,
        "active.md",
        "---\ntype: note\n---\n\nActive note.\n",
    )
    index_mod.build_index(str(mb_path))

    data = json.loads((mb_path / "index.json").read_text())
    assert data["notes"][0]["archived"] is False


# ═══════════════════════════════════════════════════════════════
# progress_chain round-trip preservation (handoff-v2 §6 / §9 risk row)
# ═══════════════════════════════════════════════════════════════


def test_rebuild_preserves_existing_progress_chain(index_mod, mb_path):
    """A rebuild MUST NOT clobber an existing index.json:progress_chain.

    The hash chain lives in index.json (handoff-v2 §6) but index.json is
    rebuilt by mb-index-json.py on every actualize. Design §9 risk row
    ("Hash chain lives in index.json which is rebuilt") requires round-trip.
    """
    make_note(mb_path, "a.md", "---\ntype: note\n---\nbody\n")
    chain = {
        "version": 1,
        "tail": [
            {"heading": "## 2026-06-12", "sha256": "a" * 64},
            {"heading": "## 2026-06-11", "sha256": "b" * 64},
        ],
        "last_synced_at": "2026-06-12T10:00:00Z",
    }
    # Seed an index.json that already carries a progress_chain.
    index_path = mb_path / "index.json"
    index_path.write_text(json.dumps({"notes": [], "lessons": [], "progress_chain": chain}))

    index_mod.build_index(str(mb_path))

    data = json.loads(index_path.read_text())
    assert data.get("progress_chain") == chain, "progress_chain must survive a rebuild"
    # And the rebuild still did its real job.
    assert len(data["notes"]) == 1


def test_rebuild_without_existing_chain_omits_key(index_mod, mb_path):
    """No prior chain → rebuild does not invent a progress_chain key."""
    make_note(mb_path, "a.md", "---\ntype: note\n---\nbody\n")
    index_mod.build_index(str(mb_path))
    data = json.loads((mb_path / "index.json").read_text())
    assert "progress_chain" not in data


def test_rebuild_preserves_chain_when_index_malformed_writes_bak(index_mod, mb_path):
    """build_index on a malformed existing index.json must write .bak and not crash.

    The corrupt file must be preserved as index.json.bak so post-mortem inspection
    is possible (mirrors progress_chain.rebuild_tail backup behaviour — finding #2
    residual in mb-index-json.py).
    """
    make_note(mb_path, "a.md", "---\ntype: note\n---\nbody\n")
    (mb_path / "index.json").write_text("{ this is not valid json")
    # Must not raise.
    index_mod.build_index(str(mb_path))
    data = json.loads((mb_path / "index.json").read_text())
    assert len(data["notes"]) == 1
    # .bak must have been written so the corrupt bytes are not silently discarded.
    assert (mb_path / "index.json.bak").exists(), (
        "build_index must write index.json.bak when the existing index is malformed"
    )


def test_rebuild_preserves_chain_when_index_malformed_chain_content_in_bak(index_mod, mb_path):
    """When a malformed index contains a valid progress_chain, the .bak preserves it.

    After a corrupt overwrite (e.g. partial disk write), the chain is recoverable
    from the .bak even though the new index starts fresh.
    """
    make_note(mb_path, "a.md", "---\ntype: note\n---\nbody\n")
    # Write an index that has valid chain data but truncated JSON overall.
    corrupt_with_chain = '{"progress_chain": {"version": 1, "tail": [{"heading": "## 2026-06-10", "sha256": "abc"}]}, "notes": ['
    (mb_path / "index.json").write_text(corrupt_with_chain)
    index_mod.build_index(str(mb_path))
    bak_path = mb_path / "index.json.bak"
    assert bak_path.exists(), "corrupt index must be saved to .bak"
    # .bak preserves original corrupt bytes — they contain the chain data.
    bak_content = bak_path.read_text()
    assert "progress_chain" in bak_content


# ═══════════════════════════════════════════════════════════════
# progress_chain module — malformed index handling (finding #2)
# ═══════════════════════════════════════════════════════════════

REPO_ROOT_FOR_CHAIN = Path(__file__).resolve().parents[2]


def _load_chain_module():
    """Load memory_bank_skill.progress_chain (sibling package)."""
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "progress_chain",
        REPO_ROOT_FOR_CHAIN / "memory_bank_skill" / "progress_chain.py",
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def chain_mod():
    try:
        return _load_chain_module()
    except Exception:
        pytest.skip("memory_bank_skill/progress_chain.py not importable")


def test_load_index_absent(chain_mod, tmp_path):
    """_load_index on a missing file → absent=True."""
    result = chain_mod._load_index(tmp_path / "nonexistent.json")
    assert result.absent is True
    assert result.malformed is False
    assert result.data is None


def test_load_index_malformed_truncated(chain_mod, tmp_path):
    """_load_index on truncated JSON → malformed=True."""
    f = tmp_path / "index.json"
    f.write_text('{"broken":')
    result = chain_mod._load_index(f)
    assert result.malformed is True
    assert result.absent is False


def test_load_index_malformed_empty(chain_mod, tmp_path):
    """_load_index on empty file → malformed=True."""
    f = tmp_path / "index.json"
    f.write_text("")
    result = chain_mod._load_index(f)
    assert result.malformed is True


def test_load_index_ok(chain_mod, tmp_path):
    """_load_index on valid JSON dict → data populated."""
    f = tmp_path / "index.json"
    f.write_text('{"notes": [], "progress_chain": {"version": 1}}')
    result = chain_mod._load_index(f)
    assert result.absent is False
    assert result.malformed is False
    assert result.data == {"notes": [], "progress_chain": {"version": 1}}


def test_verify_malformed_index_returns_index_malformed(chain_mod, tmp_path):
    """verify() on a malformed index.json → ok=False, error='index_malformed'."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- work\n")
    (mb / "index.json").write_text('{"incomplete":')
    report = chain_mod.verify(mb)
    assert report["ok"] is False
    assert report["error"] == "index_malformed"


def test_rebuild_tail_writes_bak_on_malformed_index(chain_mod, tmp_path):
    """rebuild_tail with a malformed existing index writes index.json.bak."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- work\n")
    (mb / "index.json").write_text("{bad json")
    chain_mod.rebuild_tail(mb)
    assert (mb / "index.json.bak").exists(), "corrupt index must be backed up"
    # New index must be valid.
    data = json.loads((mb / "index.json").read_text())
    assert "progress_chain" in data


# ═══════════════════════════════════════════════════════════════
# NEW MAJOR — stale tail: unique run found but not the suffix
# ═══════════════════════════════════════════════════════════════


def test_verify_suffix_match_is_clean_ok(chain_mod, tmp_path):
    """verify() when tail IS the exact suffix → ok=True, stale absent or False."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- alpha\n\n## 2026-06-11\n\n- beta\n")
    chain_mod.rebuild_tail(mb)
    report = chain_mod.verify(mb)
    assert report["ok"] is True
    assert report.get("stale") is not True, "exact-suffix match must not be stale"


def test_verify_stale_when_new_entry_appended_after_rebuild(chain_mod, tmp_path):
    """verify() when tail is a unique run but NOT the suffix → ok=True, stale=True.

    An append-only log is allowed to grow. The recorded tail is still a valid
    contiguous run (not tampered), but newer entries exist that are untracked.
    verify must return ok=true, stale=true, untracked_appends=N (NEW MAJOR finding).
    """
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- alpha\n\n## 2026-06-11\n\n- beta\n")
    chain_mod.rebuild_tail(mb)
    # Append a new entry — legitimate append-only growth.
    with (mb / "progress.md").open("a") as f:
        f.write("\n## 2026-06-12\n\n- gamma\n")
    report = chain_mod.verify(mb)
    assert report["ok"] is True, "append-only growth must not be tamper"
    assert report.get("stale") is True, "stale must be True when newer entries exist"
    assert report.get("untracked_appends", 0) >= 1, "must report count of untracked appends"


def test_verify_stale_multiple_untracked(chain_mod, tmp_path):
    """verify() reports correct untracked_appends count for multiple new entries."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- alpha\n")
    chain_mod.rebuild_tail(mb)
    with (mb / "progress.md").open("a") as f:
        f.write("\n## 2026-06-11\n\n- beta\n")
        f.write("\n## 2026-06-12\n\n- gamma\n")
        f.write("\n## 2026-06-13\n\n- delta\n")
    report = chain_mod.verify(mb)
    assert report["ok"] is True
    assert report.get("stale") is True
    assert report.get("untracked_appends") == 3


# ═══════════════════════════════════════════════════════════════
# NEW MAJOR — malformed tail row causes AttributeError in verify
# ═══════════════════════════════════════════════════════════════


def test_verify_chain_malformed_non_dict_tail_row(chain_mod, tmp_path):
    """verify() when a tail row is not a dict → chain_malformed error, not crash.

    A valid-JSON index whose tail contains a non-object item (e.g. a string or int)
    previously caused AttributeError in _find_run_positions. Must return structured
    {ok: false, error: 'chain_malformed'} and exit 2.
    """
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- work\n")
    # Write an index with a non-dict tail row (string item).
    index_data = {
        "progress_chain": {
            "version": 1,
            "tail": [{"heading": "## 2026-06-10", "sha256": "abc"}, "INVALID_ROW"],
            "last_synced_at": "2026-06-10T00:00:00Z",
        }
    }
    (mb / "index.json").write_text(json.dumps(index_data))
    report = chain_mod.verify(mb)
    assert report["ok"] is False
    assert report["error"] == "chain_malformed"


def test_verify_chain_malformed_missing_sha_field(chain_mod, tmp_path):
    """verify() when a tail row is a dict but missing 'sha256' → chain_malformed."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- work\n")
    index_data = {
        "progress_chain": {
            "version": 1,
            "tail": [{"heading": "## 2026-06-10"}],  # missing sha256
            "last_synced_at": "2026-06-10T00:00:00Z",
        }
    }
    (mb / "index.json").write_text(json.dumps(index_data))
    report = chain_mod.verify(mb)
    assert report["ok"] is False
    assert report["error"] == "chain_malformed"


def test_verify_chain_malformed_non_string_heading(chain_mod, tmp_path):
    """verify() when heading is not a string → chain_malformed."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- work\n")
    index_data = {
        "progress_chain": {
            "version": 1,
            "tail": [{"heading": 42, "sha256": "abc"}],  # int heading
            "last_synced_at": "2026-06-10T00:00:00Z",
        }
    }
    (mb / "index.json").write_text(json.dumps(index_data))
    report = chain_mod.verify(mb)
    assert report["ok"] is False
    assert report["error"] == "chain_malformed"


def test_verify_chain_integer_item_no_crash(chain_mod, tmp_path):
    """verify() with integer tail row does not traceback — returns structured error."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- work\n")
    index_data = {
        "progress_chain": {
            "version": 1,
            "tail": [42],  # integer — no .get() method
            "last_synced_at": "2026-06-10T00:00:00Z",
        }
    }
    (mb / "index.json").write_text(json.dumps(index_data))
    # Must not raise AttributeError.
    report = chain_mod.verify(mb)
    assert isinstance(report, dict)
    assert report["ok"] is False
    assert report["error"] == "chain_malformed"


# ═══════════════════════════════════════════════════════════════
# NEW MAJOR — falsy non-list tail (null/false/0/"") must be chain_malformed,
# NOT silently coerced to [] and treated as a valid empty chain.
# ═══════════════════════════════════════════════════════════════


@pytest.mark.parametrize(
    ("tail_value", "label"),
    [
        (None, "null"),
        (False, "false"),
        (0, "zero"),
        ("", "empty_string"),
    ],
)
def test_verify_falsy_tail_is_chain_malformed_not_empty(chain_mod, tmp_path, tail_value, label):
    """A present-but-falsy `tail` is a corrupt chain, not an empty one.

    `chain.get("tail") or []` would coerce null/false/0/"" into [] and return ok:true,
    silently disabling chain verification on a valid-JSON-but-corrupt index. Each of
    these must instead return {ok: false, error: 'chain_malformed'} and exit 2.
    """
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- work\n")
    index_data = {
        "progress_chain": {
            "version": 1,
            "tail": tail_value,
            "last_synced_at": "2026-06-10T00:00:00Z",
        }
    }
    (mb / "index.json").write_text(json.dumps(index_data))
    report = chain_mod.verify(mb)
    assert report["ok"] is False, f"falsy tail {label!r} must NOT be accepted as empty"
    assert report["error"] == "chain_malformed"


def test_verify_empty_list_tail_still_ok(chain_mod, tmp_path):
    """A genuinely empty list tail (fresh bank) remains a valid no-op — ok:true."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "progress.md").write_text("## 2026-06-10\n\n- work\n")
    index_data = {
        "progress_chain": {
            "version": 1,
            "tail": [],
            "last_synced_at": "2026-06-10T00:00:00Z",
        }
    }
    (mb / "index.json").write_text(json.dumps(index_data))
    report = chain_mod.verify(mb)
    assert report["ok"] is True
    assert report["error"] is None


# ═══════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════


def textwrap_dedent(text: str) -> str:
    import textwrap

    return textwrap.dedent(text).lstrip("\n")
