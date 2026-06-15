"""Append-only physical integrity for ``progress.md`` — hash chain.

Design: ``.memory-bank/specs/handoff-v2/design.md`` §6 (GAP-8).

A hash chain of the last ``N=20`` ``## YYYY-MM-DD`` entries lives in
``index.json:progress_chain``::

    {
      "version": 1,
      "tail": [{"heading": "## 2026-06-12", "sha256": "..."}, ...],
      "last_synced_at": "<ISO-8601 UTC>"
    }

**Canonical entry form** (design §6).  Each entry spans from its
``## YYYY-MM-DD`` heading line (with optional trailing text) through the body
up to—but NOT including—the next such heading or EOF.  The sha256 is computed
over the canonical form, not raw bytes:

- Line endings normalised to ``\\n`` (CRLF → LF) — portable across macOS/Ubuntu.
- Trailing blank *separator* lines excluded — blank lines between adjacent dated
  entries belong to neither entry.  This keeps a historic entry's hash stable
  when a new dated entry is appended after it (legitimate append-only growth).
- All other whitespace (in-body spaces, tabs, mid-body blank lines) IS part of
  the entry's immutable content — any edit to them is detected as tamper.

**Verification model** (design §6 verify flow).  ``--verify`` recomputes the
full ordered ``(heading, sha256)`` list from ``progress.md`` and requires that
the recorded ``tail`` appears as a **unique contiguous run** within that list.
"Unique" is critical: if the recorded run matches at zero or more-than-one
positions, the result is ``ambiguous_match`` (exit 2).  Exactly one match →
walk the run entry-by-entry from the anchor and report any sha divergence
(``mismatches``) or run-short (``missing``).

Python 3.11/3.12-safe; standard library only.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

# A date heading: ``## 2026-06-12`` optionally followed by ` — trailing text`.
# Anchored at line start; the date must be a literal ``YYYY-MM-DD``.
DATE_HEADING_RE = re.compile(r"^## \d{4}-\d{2}-\d{2}(?:[ \t].*)?$")

TAIL_LEN = 20
CHAIN_VERSION = 1


def _iso_now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_entries(text: str) -> list[tuple[str, str]]:
    """Split ``progress.md`` text into ordered ``(heading, canonical_body)`` entries.

    ``canonical_body`` is the entry's heading line plus its non-separator body
    lines, with line endings normalised to ``\\n`` and trailing blank separator
    lines excluded.  Content before the first date heading is ignored.
    """
    lines = text.splitlines(keepends=True)
    # Indices of lines that open a dated entry.
    starts = [i for i, line in enumerate(lines) if DATE_HEADING_RE.match(line.rstrip("\r\n"))]
    entries: list[tuple[str, str]] = []
    for idx, start in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
        block = lines[start:end]
        # Trailing blank lines are inter-entry SEPARATORS — exclude them so that
        # a legitimate new-entry append does not change the preceding entry's sha.
        while block and block[-1].strip() == "":
            block.pop()
        # Normalise line endings to \n for macOS/Ubuntu portability — a CRLF↔LF
        # editor normalisation must not trigger a false-positive tamper alarm.
        body = "".join(line.rstrip("\r\n") + "\n" for line in block)
        heading = lines[start].rstrip("\r\n")
        entries.append((heading, body))
    return entries


def _sha256(body: str) -> str:
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def compute_tail(text: str, tail_len: int = TAIL_LEN) -> list[dict[str, str]]:
    """Return the last ``tail_len`` entries as ``{heading, sha256}`` rows."""
    entries = parse_entries(text)
    tail = entries[-tail_len:] if tail_len > 0 else []
    return [{"heading": heading, "sha256": _sha256(body)} for heading, body in tail]


def _read_progress(mb_path: Path) -> str:
    progress = mb_path / "progress.md"
    if not progress.is_file():
        return ""
    return progress.read_text(encoding="utf-8")


class _IndexResult:
    """Three-way outcome for index.json loading (absent / malformed / ok)."""

    __slots__ = ("data", "absent", "malformed")

    def __init__(
        self,
        *,
        data: dict[str, Any] | None = None,
        absent: bool = False,
        malformed: bool = False,
    ) -> None:
        self.data = data
        self.absent = absent
        self.malformed = malformed


def _load_index(index_path: Path) -> _IndexResult:
    """Load index.json with three-way discrimination: absent / malformed / ok.

    - absent  → file does not exist
    - malformed → file exists but is not valid JSON (or not a dict)
    - ok     → ``result.data`` is a dict (possibly ``{}``)
    """
    if not index_path.is_file():
        return _IndexResult(absent=True)
    try:
        raw = index_path.read_text(encoding="utf-8")
        data = json.loads(raw)
    except (OSError, ValueError):
        return _IndexResult(malformed=True)
    if not isinstance(data, dict):
        return _IndexResult(malformed=True)
    return _IndexResult(data=data)


def _atomic_write_json(index_path: Path, data: dict[str, Any]) -> None:
    index_path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False)
    fd, tmp = tempfile.mkstemp(
        dir=str(index_path.parent), prefix=f".{index_path.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(payload)
        os.replace(tmp, index_path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def rebuild_tail(mb_path: Path, tail_len: int = TAIL_LEN) -> dict[str, Any]:
    """Recompute the chain and write it into ``index.json:progress_chain``.

    Read-modify-write: every other ``index.json`` key is preserved.  Idempotent —
    re-running on an unchanged ``progress.md`` yields an identical ``tail`` (only
    ``last_synced_at`` is refreshed).

    If the existing ``index.json`` is **malformed** (present but not parseable),
    the corrupted file is preserved as ``index.json.bak`` before being overwritten,
    so the corruption is visible for post-mortem inspection.

    Returns the new ``progress_chain`` object.
    """
    mb_path = Path(mb_path)
    text = _read_progress(mb_path)
    chain: dict[str, Any] = {
        "version": CHAIN_VERSION,
        "tail": compute_tail(text, tail_len),
        "last_synced_at": _iso_now(),
    }
    index_path = mb_path / "index.json"
    result = _load_index(index_path)
    if result.malformed:
        # Preserve the corrupt file as a .bak before overwriting.
        bak = Path(str(index_path) + ".bak")
        with contextlib.suppress(OSError):  # best-effort; do not block the rebuild
            os.replace(str(index_path), str(bak))
        existing: dict[str, Any] = {}
    elif result.absent:
        existing = {}
    else:
        existing = result.data or {}

    existing["progress_chain"] = chain
    _atomic_write_json(index_path, existing)
    return chain


# ---------------------------------------------------------------------------
# Verification helpers
# ---------------------------------------------------------------------------


def _find_run_positions(
    current: list[dict[str, str]],
    recorded: list[dict[str, str]],
) -> list[int]:
    """Return the start-indices in ``current`` where ``recorded`` matches as a
    contiguous run (compared entry-by-entry on heading + sha256).

    Returns an empty list if no match, a single-element list for exactly one
    match, and a multi-element list when there are multiple matches (ambiguous).
    """
    n = len(recorded)
    m = len(current)
    positions: list[int] = []
    for i in range(m - n + 1):
        if all(
            current[i + j]["heading"] == recorded[j].get("heading")
            and current[i + j]["sha256"] == recorded[j].get("sha256")
            for j in range(n)
        ):
            positions.append(i)
    return positions


def verify(mb_path: Path) -> dict[str, Any]:
    """Verify the recorded chain against the current ``progress.md``.

    Returns a structured report ``{ok, error, mismatches, missing}``.
    ``ok`` is ``True`` when the recorded ``tail`` matches a **unique**
    contiguous run in the file's current ordered entry list (either exact-suffix
    or stale-but-intact).

    When ``ok`` is ``True`` and the matched run is NOT the suffix (new entries were
    appended since the last rebuild), the report additionally contains::

        "stale": true, "untracked_appends": <N>

    Stale is NOT tamper — callers must not treat it as a critical error.

    Error codes (``error`` field when ``ok`` is ``False``):
    - ``index_missing``  — ``index.json`` does not exist
    - ``index_malformed``— ``index.json`` exists but is not valid JSON / not a dict
    - ``chain_missing``  — ``index.json`` has no ``progress_chain`` key
    - ``chain_malformed``— ``progress_chain.tail`` is not a list, or contains a row
                           that is not a ``{heading: str, sha256: str}`` dict
    - ``ambiguous_match``— recorded tail matches at more than one position in the file
    - ``None``           — a normal mismatch/deletion (``mismatches``/``missing`` populated)
    """
    mb_path = Path(mb_path)
    index_path = mb_path / "index.json"

    result = _load_index(index_path)
    if result.absent:
        return {"ok": False, "error": "index_missing", "mismatches": [], "missing": []}
    if result.malformed:
        return {"ok": False, "error": "index_malformed", "mismatches": [], "missing": []}

    data = result.data or {}
    chain = data.get("progress_chain")
    if not isinstance(chain, dict) or "tail" not in chain:
        return {"ok": False, "error": "chain_missing", "mismatches": [], "missing": []}

    # Read the raw value BEFORE any truthiness coercion: a falsy non-list such as
    # null/false/0/"" is a CORRUPT chain, not an empty one.  `chain.get("tail") or []`
    # would silently turn those into [] and pass verification — disabling integrity
    # checks on a valid-JSON-but-corrupt index.  Distinguish them explicitly.
    recorded = chain.get("tail")
    if not isinstance(recorded, list):
        return {"ok": False, "error": "chain_malformed", "mismatches": [], "missing": []}

    # Validate every row BEFORE passing to _find_run_positions which assumes dicts.
    # A non-dict row (or a dict with a non-string heading/sha256) signals a corrupt
    # index.json — return chain_malformed immediately rather than crashing with
    # AttributeError (NEW MAJOR finding — malformed tail row).
    for row in recorded:
        if (
            not isinstance(row, dict)
            or not isinstance(row.get("heading"), str)
            or not isinstance(row.get("sha256"), str)
        ):
            return {"ok": False, "error": "chain_malformed", "mismatches": [], "missing": []}

    # An empty recorded tail (e.g. a freshly-initialised empty progress.md) makes
    # no integrity claim — nothing to verify, so it passes.
    if not recorded:
        return {"ok": True, "error": None, "mismatches": [], "missing": []}

    text = _read_progress(mb_path)
    entries = parse_entries(text)
    current = [{"heading": h, "sha256": _sha256(b)} for h, b in entries]

    # Locate the recorded run in the current entry list.  We require a UNIQUE
    # contiguous match — zero matches means deletion/tamper; more than one means
    # the anchor cannot be resolved without ambiguity (two identical-sha runs).
    positions = _find_run_positions(current, recorded)

    if len(positions) == 0:
        # Zero matches: the run as a whole is broken (entries edited, deleted, or
        # reordered).  Find the first-entry anchor independently so we can name it.
        rec_oldest_heading = recorded[0].get("heading") if isinstance(recorded[0], dict) else ""
        return {
            "ok": False,
            "error": None,
            "mismatches": [],
            "missing": [{"heading": rec_oldest_heading or "", "reason": "anchor_lost"}],
        }

    if len(positions) > 1:
        # More than one match: ambiguous — we cannot tell which run is "the one".
        return {
            "ok": False,
            "error": "ambiguous_match",
            "mismatches": [],
            "missing": [],
        }

    # Exactly one match — do a full per-entry comparison from the anchor to catch
    # partial mismatches that somehow survived the run-search (defensive).
    anchor = positions[0]
    mismatches: list[dict[str, str]] = []
    missing: list[dict[str, str]] = []
    n = len(recorded)

    for offset in range(n):
        rec = recorded[offset]
        rec_heading = rec.get("heading") if isinstance(rec, dict) else None
        rec_sha = rec.get("sha256") if isinstance(rec, dict) else None
        pos = anchor + offset
        if pos >= len(current):
            missing.append({"heading": rec_heading or "", "reason": "entry_deleted"})
            continue
        cur = current[pos]
        if cur["heading"] != rec_heading or cur["sha256"] != rec_sha:
            mismatches.append(
                {
                    "heading": rec_heading or "",
                    "expected_sha256": rec_sha or "",
                    "actual_heading": cur["heading"],
                    "actual_sha256": cur["sha256"],
                }
            )

    if mismatches or missing:
        return {"ok": False, "error": None, "mismatches": mismatches, "missing": missing}

    # Integrity check passed.  Detect whether the recorded tail is the SUFFIX of
    # the current entry list (exact-suffix) or a contiguous run that is followed by
    # newer untracked entries (stale).
    #
    # Stale is NOT tamper — append-only growth is expected behaviour.  Callers
    # (e.g. drift) must treat stale as informational, not critical.
    run_end = anchor + n  # index one past the last matched entry
    untracked = len(current) - run_end  # entries appended since last rebuild
    if untracked > 0:
        return {
            "ok": True,
            "error": None,
            "mismatches": [],
            "missing": [],
            "stale": True,
            "untracked_appends": untracked,
        }

    return {"ok": True, "error": None, "mismatches": [], "missing": []}


_USAGE = "usage: mb-progress-chain (--rebuild-tail | --verify) [mb_path]"


def main(argv: list[str]) -> int:
    args = argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(_USAGE, file=sys.stderr)
        return 0 if args and args[0] in ("-h", "--help") else 2

    mode = args[0]
    mb_path = Path(args[1]) if len(args) > 1 else Path(".memory-bank")

    if mode == "--rebuild-tail":
        chain = rebuild_tail(mb_path)
        print(json.dumps({"ok": True, "progress_chain": chain}, ensure_ascii=False))
        return 0

    if mode == "--verify":
        report = verify(mb_path)
        print(json.dumps(report, ensure_ascii=False))
        return 0 if report["ok"] else 2

    print(_USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
