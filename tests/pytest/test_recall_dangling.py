"""Recall must never render a dangling hit whose source file was pruned/moved.

Regression: the incremental semantic indexer never prunes embeddings for a
source file that was deleted or moved, so `_build_hits` could still surface a
hit pointing at a gone file. `_age` degrades that to an `age: "?"` row instead
of raising, so the dangling entry slipped straight into `render_compact` /
`render_inject` output. Fix: `_build_hits` drops a hit whose ``(mb / source)``
does not exist, but ONLY when ``mb`` itself resolves — an unresolvable/bogus
``mb`` must fail open and keep every hit.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "hooks" / "lib"))

from recall_index import _build_hits, render_compact, render_inject  # noqa: E402


def _hit(source: str, text: str) -> dict:
    return {"source": source, "text": text, "score": 0.9, "anchor": "p0"}


def test_build_hits_missing_source_is_dropped(tmp_path):
    mb = tmp_path / ".memory-bank"
    (mb / "notes").mkdir(parents=True)
    (mb / "notes" / "present.md").write_text("present note body", encoding="utf-8")

    req = {
        "mb": str(mb),
        "semantic": [
            _hit("notes/present.md", "present note body"),
            _hit("notes/gone.md", "gone note body"),
        ],
    }

    hits = _build_hits(req)
    sources = {h["source"] for h in hits}
    assert sources == {"notes/present.md"}

    compact = render_compact(hits, limit=10)
    inject = render_inject(hits, limit=10)
    for out in (compact, inject):
        assert "gone" not in out
        assert "age: ?" not in out
        assert '"?"' not in out


def test_build_hits_present_source_is_kept(tmp_path):
    mb = tmp_path / ".memory-bank"
    (mb / "notes").mkdir(parents=True)
    (mb / "notes" / "present.md").write_text("present note body", encoding="utf-8")

    req = {
        "mb": str(mb),
        "semantic": [_hit("notes/present.md", "present note body")],
    }

    hits = _build_hits(req)
    assert any(h["source"] == "notes/present.md" for h in hits)


def test_build_hits_unresolvable_mb_keeps_all():
    req = {
        "mb": "/nonexistent/bogus/path/xyz",
        "semantic": [
            _hit("notes/one.md", "one note body"),
            _hit("notes/two.md", "two note body"),
        ],
    }

    hits = _build_hits(req)
    sources = {h["source"] for h in hits}
    assert sources == {"notes/one.md", "notes/two.md"}
