#!/usr/bin/env python3
"""Fence handling, bootstrap transfer and atomic publish for mb-roadmap-sync.sh.

Split out of the shell heredoc so scripts/mb-roadmap-sync.sh stays under the
400-line project gate (S4 review finding 10). Pure stdlib, no side effects on
import; every function here is directly unit-testable.

Responsibilities:
  * ``normalize_spec_slug`` — one spelling for the several legacy shapes a
    ``linked_specs`` entry takes in real banks (finding 2).
  * ``find_fence`` — parse EXACTLY one well-formed autosync fence pair and
    reject malformed/duplicate/reordered markers (finding 6).
  * ``strip_bootstrap_groups`` — remove a manual out-of-fence Group block,
    including the decorated legacy header form, without touching unrelated
    bytes (findings 1 and 5).
  * ``atomic_write`` — publish through a sibling temp + fsync + os.replace so a
    failed write can never truncate the roadmap (finding 4).
"""

from __future__ import annotations

import contextlib
import os
import re
import stat
import tempfile

FENCE_OPEN = "<!-- mb-roadmap-auto -->"
FENCE_CLOSE = "<!-- /mb-roadmap-auto -->"


class FenceError(Exception):
    """roadmap.md carries a malformed / ambiguous autosync fence.

    The consumer must exit non-zero WITHOUT writing: with a broken fence we
    cannot tell which bytes are generated and which are the user's, so any
    rewrite risks destroying hand-written content.
    """


def normalize_spec_slug(raw):
    """Reduce a ``linked_specs`` entry to its bare topic slug.

    Real banks carry at least three spellings for the same spec::

        foo   ·   specs/foo   ·   specs/foo/design.md

    All three must resolve to ``foo`` so that ``specs/<slug>/tasks.md`` exists
    and REQ-002 progress is real instead of a silent ``total=0`` (finding 2).
    This is the same normalization mb-traceability-gen.sh already applies to
    ``linked_spec`` / ``spec_reference``, kept behaviourally identical here.
    """
    slug = (raw or "").strip().strip("\"'").replace("\\", "/")
    if not slug:
        return ""
    if slug.startswith("specs/"):
        slug = slug[len("specs/") :]
    return slug.split("/")[0]


def find_fence(text):
    """Return ``(start, end)`` byte offsets of the single autosync fence pair.

    Returns ``None`` when the file carries no fence at all (the caller then
    injects one). Raises :class:`FenceError` for anything ambiguous: a lone
    marker, a duplicated marker, or a closing marker preceding its opening one
    (finding 6). Previously only the PRESENCE of both markers was checked, so a
    close-before-open file silently regenerated nothing and ``--check``
    reported "up to date".
    """
    n_open = text.count(FENCE_OPEN)
    n_close = text.count(FENCE_CLOSE)
    if n_open == 0 and n_close == 0:
        return None
    if n_open != 1 or n_close != 1:
        raise FenceError(
            f"code=malformed_fence open={n_open} close={n_close} "
            "detail=expected exactly one opening and one closing marker"
        )
    start = text.index(FENCE_OPEN)
    close_at = text.index(FENCE_CLOSE)
    if close_at < start:
        raise FenceError(
            "code=malformed_fence open=1 close=1 detail=closing marker precedes the opening marker"
        )
    end = close_at + len(FENCE_CLOSE)
    if text[end : end + 1] == "\n":
        end += 1
    return start, end


def _legacy_group_header_re(slug):
    """Match a manual ``## [decoration] Group: <slug>[ trailing prose]`` header.

    The live bank writes the header decorated, e.g.::

        ## 🧭 Group: sdd-vision-pipeline (2026-07-17, AGR-017) — main track

    Matching only the bare ``## Group: <slug>`` form left that block outside the
    fence and produced two headers for one group (finding 1). Decoration is
    restricted to tokens that START with a non-word character (emoji, ✅, 🔥) so
    ordinary prose headings that merely mention "Group:" are not swallowed.
    """
    return re.compile(
        r"(?m)^##[ \t]+(?:[^\w\s][^\s]*[ \t]+)*Group:[ \t]*"
        + re.escape(slug)
        + r"(?![\w-])[^\n]*\n"
    )


# A manual Group block ends at the next H1/H2 or at either fence marker. Nested
# H3+ sections and tables BELONG to the block and are removed with it.
_BLOCK_END_RE = re.compile(
    r"(?m)^(?:#{1,2}[ \t]|" + re.escape(FENCE_OPEN) + r"|" + re.escape(FENCE_CLOSE) + r")"
)


def strip_bootstrap_groups(text, discovered_slugs):
    """Drop out-of-fence manual ``Group:`` blocks for slugs now rendered inside.

    Manual blocks for NON-discovered slugs are left untouched (S4-A-02) — they
    are the user's prose, not registry data.

    Bytes outside the removed blocks are preserved exactly. The earlier
    implementation ran ``re.sub(r"\\n{3,}", "\\n\\n", ...)`` over the whole
    out-of-fence text, silently reflowing unrelated user sections and breaking
    the byte-identical promise (finding 5); a block is now cut precisely from
    its header up to the following heading, which needs no reflow at all.
    """
    if not discovered_slugs:
        return text
    fence = find_fence(text)
    if fence is None:
        return text
    start, end = fence
    head, fenced, tail = text[:start], text[start:end], text[end:]
    return _scrub(head, discovered_slugs) + fenced + _scrub(tail, discovered_slugs)


def _scrub(segment, discovered_slugs):
    for slug in sorted(discovered_slugs):
        header_re = _legacy_group_header_re(slug)
        while True:
            m = header_re.search(segment)
            if m is None:
                break
            tail_at = m.end()
            nxt = _BLOCK_END_RE.search(segment, tail_at)
            block_end = nxt.start() if nxt else len(segment)
            segment = segment[: m.start()] + segment[block_end:]
    return segment


def atomic_write(path, text, encoding="utf-8"):
    """Publish ``text`` to ``path`` atomically.

    Writes a sibling temp file in the SAME directory (so ``os.replace`` stays a
    same-filesystem rename), flushes and fsyncs it, then renames over the
    target. A plain ``write_text`` truncates the target first, so an ENOSPC or a
    kill mid-write leaves the roadmap empty or half-written (finding 4). The
    temp file is removed on any failure, and the original file's permission bits
    are carried over so publishing never silently tightens them to 0600.
    """
    directory = os.path.dirname(os.path.abspath(str(path))) or "."
    try:
        mode = stat.S_IMODE(os.stat(str(path)).st_mode)
    except OSError:
        mode = None
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".mb-roadmap-sync.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding=encoding, newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, str(path))
    except BaseException:
        # Best-effort cleanup: the original file is already safe (untouched),
        # so a failure to remove the temp must not mask the real exception.
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise
