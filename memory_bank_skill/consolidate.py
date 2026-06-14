"""Deterministic, LLM-free engine behind ``/mb consolidate`` (REQ-012..014).

``scripts/mb-consolidate.sh`` is a thin dispatcher (arg parsing + the verbatim
``mv``/``cat >>`` moves + the ``_recent.md`` rebuild); ALL decision logic lives here
as pure, directly-unit-testable functions — :func:`plan_consolidation` (windowed
sessions → SESSION/NOTE/POINTER/CLUSTER directives) and :func:`split_progress` (a
BYTE-PRESERVING partition of ``progress.md`` where a kept real entry stays
byte-identical and a moved stub slice equals the original bytes exactly). The
``plan`` / ``split`` CLI sub-commands wrap these via env-var transport. stdlib-only,
3.11/3.12-safe (``open(newline="")`` — NOT the 3.13-only ``read_text(newline=...)``).
"""

from __future__ import annotations

import base64
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Session:
    """A windowed session: filename ``name``/``sid8`` + its touched ``files`` & ``tokens``."""

    path: Path
    name: str
    sid8: str
    files: set[str]
    tokens: set[str]


def _recurring(members: list[Session], attr: str) -> list[str]:
    """Sorted ``attr`` (``files``/``tokens``) items in >=2 members — by occurrence count,
    not full intersection, so chained clusters (A/B share X, B/C share Y → empty
    intersection) still surface their shared items (finding #5)."""
    count: dict[str, int] = {}
    for m in members:
        for item in getattr(m, attr):
            count[item] = count.get(item, 0) + 1
    return sorted(k for k, c in count.items() if c >= 2)


# ── PLAN-pass lexical config ─────────────────────────────────────────────────
WORD_RE = re.compile(r"[0-9A-Za-zЀ-ӿ]+", re.UNICODE)
# Live-log bullet (hooks/mb-session-turn.sh):
#   - HH:MM — User: "<text>" · tools: <T> · files: <F> · <ok|err(N)>[ · +A/-B]
# The U+00B7 separator is " · " (space-middledot-space). The file list ends at the
# next such separator — the outcome/diffstat tail must NEVER leak into a path.
DOT_SEP = " · "
FILES_RE = re.compile(r"·\s*files:\s*(.+?)\s*$")
NAME_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})_([0-9a-f]+)$")

# Glue / generic words stripped so lexical overlap reflects the shared *subject*,
# not boilerplate that every auto-capture summary carries. Kept as a string (not a
# static ``"...".split()``) so ruff's SIM905 cannot explode it into a 60-line list.
_STOP_WORDS = (
    "the a an to of for and or in on at is are was were be with by from as it this"
    " that we now use uses used user tools files none session summary changed what"
    " decisions open questions live log added fixed patched completed updated edited"
    " и в на с по для не что это к о из"
)
STOP = frozenset(_STOP_WORDS.split())

MIN_LINES, MAX_LINES = 5, 15  # consolidated note window (5-15 line pattern format)


def tokenize(text: str) -> set[str]:
    """Lowercased content tokens (>=3 chars, non-stop, non-numeric) of ``text``."""
    toks: set[str] = set()
    for m in WORD_RE.finditer(text.lower()):
        w = m.group(0)
        if len(w) < 3 or w in STOP or w.isdigit():
            continue
        toks.add(w)
    return toks


def _section_body(lines: list[str], heading: str) -> list[str]:
    """Lines under the first ``## <heading>`` until the next top-level ``## ``."""
    out: list[str] = []
    grab = False
    for ln in lines:
        if ln.startswith(heading):
            grab = True
            continue
        if grab and ln.startswith("## "):
            break
        if grab:
            out.append(ln)
    return out


def summary_text(raw: str) -> str:
    """The ``## Summary`` body (schema v2) if non-empty, else the Live-log bullets."""
    lines = raw.splitlines()
    out = _section_body(lines, "## Summary")
    if not any(s.strip() for s in out):
        out = _section_body(lines, "## Live log")
    return "\n".join(out)


def files_touched(raw: str) -> set[str]:
    """Files-touched paths from the Live-log bullets + the ``### Files`` list (schema v2)."""
    found: set[str] = set()
    lines = raw.splitlines()
    for ln in lines:
        m = FILES_RE.search(ln)
        if m:
            # The modern bullet appends ``· <outcome> · <diffstat>``; the file list
            # ends at the first ``· `` (U+00B7) — paths never contain it (finding #4).
            chunk = m.group(1).strip().split(DOT_SEP, 1)[0].strip()
            found.update(f.strip() for f in chunk.split(",") if f.strip() not in ("", "(none)"))
    # Also pick up the schema-v2 ``### Files`` section bullets (until the next heading).
    grab = False
    for ln in lines:
        if ln.startswith("### Files"):
            grab = True
        elif grab and (ln.startswith("### ") or ln.startswith("## ")):
            grab = False
        elif grab:
            s = ln.strip()
            if s.startswith("- ") and s[2:].strip() not in ("", "(none)"):
                found.add(s[2:].strip())
    return found


def jaccard(a: set[str], b: set[str]) -> float:
    """Jaccard similarity of two token sets (0.0 when either is empty)."""
    union_ct = len(a | b)
    return len(a & b) / union_ct if (a and b and union_ct) else 0.0


def cluster_sessions(windowed: list[Session]) -> dict[int, list[int]]:
    """Cluster (union-find): link two sessions sharing a touched file OR Jaccard>0.2.

    Returns ``root → member indices``; the root is the lowest member index (deterministic).
    """
    parent = list(range(len(windowed)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(windowed)):
        for j in range(i + 1, len(windowed)):
            if (
                windowed[i].files & windowed[j].files
                or jaccard(windowed[i].tokens, windowed[j].tokens) > 0.2
            ):
                ri, rj = find(i), find(j)
                if ri != rj:
                    parent[max(ri, rj)] = min(ri, rj)
    clusters: dict[int, list[int]] = {}
    for i in range(len(windowed)):
        clusters.setdefault(find(i), []).append(i)
    return clusters


def build_note_body(
    slug_src: str,
    n_members: int,
    span: str,
    shared_files: list[str],
    recurring: list[str],
    member_names: list[str],
) -> str:
    """Render a consolidated pattern note, clamped to the 5-15 line window."""
    body_lines = [
        f"# Consolidated: {slug_src}",
        "",
        f"Recurring pattern across {n_members} archived sessions ({span}).",
    ]
    if shared_files:
        body_lines.append(f"- Shared files: {', '.join(shared_files[:3])}")
    if recurring:
        body_lines.append(f"- Recurring topic: {', '.join(recurring[:6])}")
    for name in member_names:
        body_lines.append(f"- Session {name[:-3]} touched this area")
    body_lines.append(
        "- Full session records archived under session/archive/; see progress-archive.md."
    )

    # Clamp to the window: drop middle bullets first, keep head + archive-pointer tail.
    head = body_lines[:3]
    tail = [body_lines[-1]]
    middle = body_lines[3:-1]
    while len(head) + len(middle) + len(tail) > MAX_LINES and middle:
        middle.pop()
    body_lines = head + middle + tail
    while len(body_lines) < MIN_LINES:
        body_lines.append("")
    return "\n".join(body_lines) + "\n"


def collect_windowed_sessions(session_dir: Path, cutoff: float) -> list[Session]:
    """Well-formed ``session/*.md`` older than ``cutoff`` → ``Session`` rows, name-sorted."""
    windowed: list[Session] = []
    if not session_dir.is_dir():
        return windowed
    for p in sorted(session_dir.glob("*.md")):
        if not p.is_file() or p.name == "_recent.md":
            continue
        nm = NAME_RE.match(p.stem)
        if not nm:
            continue  # only well-formed session files
        try:
            if p.stat().st_mtime >= cutoff:
                continue  # too recent → outside the window
            raw = p.read_text(errors="replace")
        except OSError:
            continue
        # sid8 == filename group == the stub's `(session <sid8>)`.
        windowed.append(
            Session(p, p.name, nm.group(4), files_touched(raw), tokenize(summary_text(raw)))
        )
    return windowed


def plan_consolidation(mb: Path, days: int) -> list[tuple[str, ...]]:
    """Windowed sessions → ordered directives (the shell's TAB line protocol).

    Kinds: ``SESSION`` (archive verbatim), ``NOTE`` (b64 body), ``POINTER``, ``CLUSTER``
    (dry-run only). Fail-open: <2 windowed sessions or nothing clusters → EMPTY list
    (bank untouched). Deterministic: inputs sorted, note bodies from sorted facts.
    """
    session_dir = mb / "session"
    notes_dir = mb / "notes"
    cutoff = time.time() - days * 86400

    windowed = collect_windowed_sessions(session_dir, cutoff)
    if len(windowed) < 2:
        return []  # fail-open: a recurring fact needs >=2 sessions

    clusters = cluster_sessions(windowed)
    directives: list[tuple[str, ...]] = []
    archived_names: set[str] = set()

    for root in sorted(clusters, key=lambda r: windowed[r].name):
        members = [windowed[i] for i in sorted(clusters[root], key=lambda i: windowed[i].name)]
        if len(members) < 2:
            continue  # a recurring fact needs >=2 sessions

        shared_files = _recurring(members, "files")
        recurring = _recurring(members, "tokens")
        # A note needs a recurring fact (shared file OR topical token); else coincidental.
        if not shared_files and not recurring:
            continue

        dates = sorted(m.name[:10] for m in members)
        span = f"{dates[0]} … {dates[-1]}" if dates[0] != dates[-1] else dates[0]
        slug_src = shared_files[0] if shared_files else recurring[0]
        slug = re.sub(r"[^a-z0-9]+", "-", slug_src.lower()).strip("-") or "sessions"
        note_name = f"{dates[-1]}_consolidated-{slug}.md"
        member_names = [m.name for m in members]

        body = build_note_body(slug_src, len(members), span, shared_files, recurring, member_names)
        b64 = base64.b64encode(body.encode("utf-8")).decode("ascii")
        directives.append(("NOTE", str(notes_dir / note_name), b64))
        files_label = ", ".join(shared_files) or "lexical overlap"
        directives.append(
            ("CLUSTER", f"{note_name}  ←  {', '.join(member_names)}  [files: {files_label}]")
        )
        # Carry the sid8 so --apply scopes the stub move to exactly these sessions (finding #1).
        for m in members:
            archived_names.add(m.name)
            directives.append(("SESSION", str(m.path), m.sid8))

    # Nothing clustered into a recurring fact → fail-open, no writes.
    if not archived_names:
        return []

    pointer = (
        f"Consolidated {len(archived_names)} session(s) → session/archive/ + "
        f"progress-archive.md (see /mb consolidate)"
    )
    directives.append(("POINTER", pointer))
    return directives


# ── SPLIT pass: byte-preserving partition of progress.md ─────────────────────
HEAD_RE = re.compile(r"^## ")
FENCE_RE = re.compile(r"^[ \t]*(```|~~~)")
STUB_HEAD_RE = re.compile(r"^### Auto-capture .* \(session ([0-9a-zA-Z-]+)\)\s*$")
DATE_HEAD_RE = re.compile(r"^## \d{4}-\d{2}-\d{2}\s*$")
# The two exact hook bullet lines (hooks/session-end-autosave.sh:98-99).
BULLET1 = "- Session ended without an explicit /mb done"
BULLET2 = (
    "- Summary auto-captured to session/ "
    "(searchable via /mb recall); core files were not actualized"
)


def _partition_blocks(lines: list[str]) -> list[list[str]]:
    """Top-level ``## `` blocks as line-slices (fence-aware; preamble is its own block).

    ``## ``-looking lines inside a fenced block are NOT boundaries; ``"".join`` over
    all blocks reproduces the input byte-for-byte."""
    ranges: list[tuple[int, int]] = []
    in_fence = False
    cur: int | None = None
    for idx, ln in enumerate(lines):
        body = ln.rstrip("\r\n")
        if HEAD_RE.match(body) and not in_fence:
            if cur is not None:
                ranges.append((cur, idx))
            else:
                ranges.append((0, idx) if idx else (0, 0))  # preamble slot
            cur = idx
        if FENCE_RE.match(body):
            in_fence = not in_fence
    if cur is not None:
        ranges.append((cur, len(lines)))
    elif lines:
        ranges.append((0, len(lines)))  # no heading at all → all preamble
    # Drop a zero-length preamble placeholder if the file starts with a heading.
    return [lines[s:e] for (s, e) in ranges if e > s]


def is_movable_stub(blk_lines: list[str], archived: set[str]) -> bool:
    """True iff the block is EXACTLY the canonical hook stub (``## <date>`` + Auto-capture
    heading + the 2 hook bullets, nothing else) for a sid in ``archived``. Extra content
    → not a pure stub (finding #3); a non-archived sid is kept (finding #1)."""
    # The 4 non-blank lines: date heading, autocapture heading, the 2 hook bullets.
    meaningful = [c for c in (ln.rstrip("\r\n") for ln in blk_lines) if c.strip()]
    if len(meaningful) != 4 or not DATE_HEAD_RE.match(meaningful[0]):
        return False
    m = STUB_HEAD_RE.match(meaningful[1])
    if not m or m.group(1) not in archived:
        return False
    return meaningful[2] == BULLET1 and meaningful[3] == BULLET2


def split_progress(text: str, archived_sids: set[str]) -> tuple[str, str]:
    """Partition ``progress.md`` into byte-exact ``(kept_text, moved_stubs_text)``.

    ``splitlines(keepends=True)`` keeps each terminator so every block re-emits its
    original bytes (kept real entry byte-identical; moved stub slice equals the
    original bytes). Only ``## <date>`` blocks whose WHOLE body is the canonical hook
    stub with a sid in ``archived_sids`` move; everything else is kept.
    """
    kept_parts: list[str] = []
    moved_parts: list[str] = []
    for blk_lines in _partition_blocks(text.splitlines(keepends=True)):
        first = blk_lines[0].rstrip("\r\n") if blk_lines else ""
        movable = DATE_HEAD_RE.match(first) and is_movable_stub(blk_lines, archived_sids)
        (moved_parts if movable else kept_parts).append("".join(blk_lines))
    return "".join(kept_parts), "".join(moved_parts)


# ── CLI sub-commands (thin env/stdout transport for the shell) ───────────────
def _cmd_plan() -> int:
    """``plan``: env ``MB_PATH`` / ``MB_DAYS`` → tab-separated directives on stdout."""
    mb = Path(os.environ["MB_PATH"])
    try:
        days = int(os.environ.get("MB_DAYS", "30"))
    except ValueError:
        days = 30
    directives = plan_consolidation(mb, days)
    out = "".join("\t".join(d) + "\n" for d in directives)
    sys.stdout.write(out)
    return 0


# Byte-exact I/O: ``newline=""`` keeps terminators verbatim (3.11/3.12-safe — NOT the
# 3.13-only ``read_text(newline=...)``), so the round-trip stays byte-identical.
_OPEN = {"encoding": "utf-8", "errors": "surrogateescape", "newline": ""}


def _cmd_split() -> int:
    """``split``: env progress/keep/stubs/flag/archived-sids → byte-exact KEEP+STUBS slices."""
    archived = {s for s in os.environ.get("MB_ARCHIVED_SIDS", "").split("\n") if s}
    with Path(os.environ["MB_PROGRESS"]).open("r", **_OPEN) as fh:
        text = fh.read()
    kept_text, moved_text = split_progress(text, archived)
    with Path(os.environ["MB_KEEP"]).open("w", **_OPEN) as fh:
        fh.write(kept_text)
    with Path(os.environ["MB_STUBS"]).open("w", **_OPEN) as fh:
        fh.write(moved_text)
    Path(os.environ["MB_MOVEDFLAG"]).write_text("1" if moved_text else "0", encoding="utf-8")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    cmd = args[0] if args else ""
    if cmd == "plan":
        return _cmd_plan()
    if cmd == "split":
        return _cmd_split()
    sys.stderr.write("consolidate.py: expected sub-command 'plan' or 'split'\n")
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
