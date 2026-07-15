#!/usr/bin/env python3
"""Recall progressive-disclosure index — id / age / summary / fusion renderer.

Backs `hooks/mb-recall.sh` and `hooks/mb-semantic-recall.sh`: the shell pipes one JSON
request on stdin (raw semantic + lexical hits); this module derives a stable bounded id
per chunk, a human-readable age, a one-line summary, detects the
`[SUPERSEDED: date -> ref]` marker, fuses the two rankings via Reciprocal Rank Fusion
(single source of truth: ``memory_bank_skill.rrf``), ranks superseded hits last, and
renders one of: ``compact`` (default) · ``expand`` (one body, exit 3 if absent) · ``full``
· ``inject``. Fail-open: unreachable RRF degrades to semantic-first order. Stdlib only.

Request schema (stdin JSON)::

    {
      "mode":     "compact" | "expand" | "full" | "inject",
      "mb":       "/abs/path/to/.memory-bank", "expand_id": "<id>" | null, "limit": 10,
      "semantic": [{"source": "...", "text": "...", "score": 0.9, "anchor": "p0"}, ...],
      "lexical":  [{"source": "session/x.md", "line": 3, "text": "matched line"}]
    }

Exit codes: 0 ok · 2 bad request/no hits-but-clean · 3 unknown --expand id.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

SEP = " · "  # " · " — the compact-line field separator.
SUPERSEDED_LABEL = "⊘ superseded"  # "⊘ superseded"
_SUMMARY_MAX = 110  # cap a single summary; the line guard below trims further if needed
_LINE_MAX = 199  # hard ceiling per compact line — strictly under the 200-char budget
_SLUG_MAX = 24  # cap the human-readable slug portion of an id
_ANCHOR_MAX = 16  # cap the displayed anchor portion of an id
_HASH_LEN = 6  # short stable hash of (full source, anchor) — guarantees id uniqueness

# Real supersede marker only — the documented shape `[SUPERSEDED: YYYY-MM-DD -> <ref>]`
# (references/metadata.md § Supersede convention). A live chunk merely *mentioning*
# the `[SUPERSEDED` syntax (e.g. a how-to note) must NOT be flagged.
_SUPERSEDED_RE = re.compile(r"\[SUPERSEDED:\s*\d{4}-\d{2}-\d{2}\s*->\s*\S+.*?\]")


# RRF — single source of truth. Import the committed module; degrade fail-open.
def _load_rrf():
    """Return ``rrf_merge`` or ``None`` if the module cannot be located."""
    try:
        from memory_bank_skill.rrf import rrf_merge  # installed package

        return rrf_merge
    except Exception:
        pass
    try:
        import rrf  # flat sys.path (repo root / vendored beside lib)

        return rrf.rrf_merge
    except Exception:
        pass
    # Last resort: walk up from this file looking for memory_bank_skill/rrf.py
    here = Path(__file__).resolve()
    for parent in here.parents:
        cand = parent / "memory_bank_skill" / "rrf.py"
        if cand.is_file():
            sys.path.insert(0, str(parent))
            try:
                from memory_bank_skill.rrf import rrf_merge

                return rrf_merge
            except Exception:
                break
    return None


# Hit derivation
def _stem(source: str) -> str:
    """File stem of a source path (``notes/2026-06-02_token-store.md`` → stem)."""
    return Path(source).stem if source else "hit"


_SLUG_DROP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}[_-]?")  # drop a leading date prefix
_SLUG_SAFE_RE = re.compile(r"[^a-z0-9]+")  # collapse non-alnum runs to a single dash


def _slug(source: str) -> str:
    """Bounded, human-readable slug from a source stem (date prefix dropped, lowercased,
    non-alnum collapsed to ``-``, capped at ``_SLUG_MAX``). Uniqueness is the id hash's
    job, not the slug's — this is only a readable hint."""
    raw = _SLUG_DROP_RE.sub("", _stem(source))
    slug = _SLUG_SAFE_RE.sub("-", raw.lower()).strip("-")
    if len(slug) > _SLUG_MAX:
        slug = slug[:_SLUG_MAX].strip("-")
    return slug or "hit"


def _make_id(source: str, anchor: str, hash_len: int = _HASH_LEN) -> str:
    """Deterministic bounded id ``<slug>-<hash>:<anchor>`` over the FULL pair.

    The hash keeps same-slug/same-anchor sources distinct even when the visible slug and
    anchor are length-capped. ``hash_len`` grows in ``_build_hits`` when ids collide.
    """
    anchor = anchor or "0"
    digest = hashlib.sha1(f"{source}\x00{anchor}".encode()).hexdigest()[:hash_len]
    shown_anchor = anchor if len(anchor) <= _ANCHOR_MAX else anchor[:_ANCHOR_MAX]
    return f"{_slug(source)}-{digest}:{shown_anchor}"


def _age(mb: Path, source: str, now: float) -> str:
    """Human-readable age from the source file's mtime; ``?`` when unknown."""
    try:
        mtime = (mb / source).stat().st_mtime
    except OSError:
        return "?"
    delta = max(0.0, now - mtime)
    minute, hour, day = 60.0, 3600.0, 86400.0
    week, month, year = 7 * day, 30 * day, 365 * day
    if delta < minute:
        return f"{int(delta)}s"
    if delta < hour:
        return f"{int(delta // minute)}m"
    if delta < day:
        return f"{int(delta // hour)}h"
    if delta < week:
        return f"{int(delta // day)}d"
    if delta < month:
        return f"{int(delta // week)}w"
    if delta < year:
        return f"{int(delta // month)}mo"
    return f"{int(delta // year)}y"


def _summary(text: str) -> str:
    """First meaningful line of a hit, collapsed and truncated for the index."""
    for raw in (text or "").splitlines():
        line = raw.strip().lstrip("#-*> ").strip()
        if line:
            line = " ".join(line.split())
            if len(line) > _SUMMARY_MAX:
                line = line[: _SUMMARY_MAX - 1].rstrip() + "…"
            return line
    return "(empty)"


def _is_superseded(text: str) -> bool:
    """True only for an actual `[SUPERSEDED: YYYY-MM-DD -> <ref>]` marker, not for a
    chunk that merely mentions the marker syntax."""
    return bool(_SUPERSEDED_RE.search(text or ""))


def _file_text(mb: Path, source: str) -> str:
    """Full body of a source file (frontmatter stripped) — used as the expand /
    full body for lexical-only hits, which carry only the matched grep line."""
    try:
        raw = (mb / source).read_text(errors="replace")
    except OSError:
        return ""
    if raw.startswith("---"):
        end = raw.find("\n---", 3)
        if end != -1:
            raw = raw[end + 4 :]
    return raw.strip()


def _build_hits(req: dict) -> list[dict]:
    """One entry per chunk, keyed by ``(source, anchor)`` — same-file chunks never
    collapse. Hit: ``{id, source, anchor, text, age, summary, superseded, sem, lex}``
    (``sem``/``lex`` = 1-based ranks, 0 = absent; lexical anchors are ``L<line>``).
    """
    mb = Path(req.get("mb") or ".")
    now = time.time()
    by_key: dict[tuple[str, str], dict] = {}
    order: list[tuple[str, str]] = []

    def _get(source: str, anchor: str) -> dict:
        key = (source, anchor)
        hit = by_key.get(key)
        if hit is None:
            hit = {
                "id": _make_id(source, anchor),
                "source": source,
                "anchor": anchor,
                "text": "",  # full body, used by --expand / --full
                "summary": "",  # first meaningful line, used by the compact index
                "age": _age(mb, source, now),
                "superseded": False,
                "sem": 0,
                "lex": 0,
            }
            by_key[key] = hit
            order.append(key)
        return hit

    for i, h in enumerate(req.get("semantic") or []):
        src = str(h.get("source", ""))
        if not src:
            continue
        anchor = str(h.get("anchor", "")) or "0"
        text = str(h.get("text", ""))
        hit = _get(src, anchor)
        if text:  # semantic chunk text is the best summary + body source
            hit["text"] = text
            hit["summary"] = _summary(text)
            hit["superseded"] = hit["superseded"] or _is_superseded(text)
        if hit["sem"] == 0:
            hit["sem"] = i + 1

    for i, h in enumerate(req.get("lexical") or []):
        src = str(h.get("source", ""))
        if not src:
            continue
        try:
            lineno = int(h.get("line") or 0)
        except (TypeError, ValueError):
            lineno = 0
        anchor = f"L{lineno}"  # deterministic lexical anchor → its own row + id
        match = str(h.get("text", ""))
        hit = _get(src, anchor)
        if not hit["summary"] and match:  # the matched line is what the user searched for
            hit["summary"] = _summary(match)
        hit["superseded"] = hit["superseded"] or _is_superseded(match)
        if hit["lex"] == 0:
            hit["lex"] = i + 1

    # Lexical-only hits carry only the matched grep line; load the real file body so
    # --expand / --full show the full entry (and catch a superseded marker off-line).
    for key in order:
        hit = by_key[key]
        if not hit["text"]:
            full = _file_text(mb, hit["source"])
            if full:
                hit["text"] = full
                hit["superseded"] = hit["superseded"] or _is_superseded(full)
                if not hit["summary"]:
                    hit["summary"] = _summary(full)
        if not hit["summary"]:
            hit["summary"] = "(empty)"

    hits = [by_key[k] for k in order]
    hits = [h for h in hits if not mb.is_dir() or (mb / h["source"]).exists()]  # prune gone
    # REQ-017: every id must be unique within the hit set. A short hash prefix can collide
    # for adversarial same-slug/same-anchor pairs — lengthen the colliders' hash field until
    # all ids differ ((source, anchor) keys are unique, so the full sha1 at n=40 separates).
    n = _HASH_LEN
    while len({h["id"] for h in hits}) < len(hits) and n < 40:
        n = min(n + 8, 40)
        counts: dict[str, int] = {}
        for h in hits:
            counts[h["id"]] = counts.get(h["id"], 0) + 1
        for h in hits:
            if counts[h["id"]] > 1:
                h["id"] = _make_id(h["source"], h["anchor"], n)
    return hits


# Fusion + ordering
def _rank(hits: list[dict]) -> list[dict]:
    """Order hits: non-superseded first (RRF-fused when both channels present),
    superseded last. Deterministic."""
    have_sem = any(h["sem"] for h in hits)
    have_lex = any(h["lex"] for h in hits)
    rrf_merge = _load_rrf() if (have_sem and have_lex) else None

    if rrf_merge is not None:
        sem_rank = [h["id"] for h in sorted((h for h in hits if h["sem"]), key=lambda h: h["sem"])]
        lex_rank = [h["id"] for h in sorted((h for h in hits if h["lex"]), key=lambda h: h["lex"])]
        fused = {hid: pos for pos, (hid, _) in enumerate(rrf_merge([sem_rank, lex_rank]))}
        key = lambda h: (fused.get(h["id"], len(fused)), h["id"])  # noqa: E731
    else:
        # Single channel (or RRF unreachable) → semantic first, then lexical,
        # both already in arrival order; stable original order is fine.
        index = {h["id"]: i for i, h in enumerate(hits)}
        key = lambda h: index[h["id"]]  # noqa: E731

    clean = sorted((h for h in hits if not h["superseded"]), key=key)
    supers = sorted((h for h in hits if h["superseded"]), key=key)
    return clean + supers


# Renderers
def _truncate(value: str, budget: int) -> str:
    """Trim ``value`` to at most ``budget`` characters, ellipsised when cut."""
    if budget <= 0:
        return ""
    if len(value) <= budget:
        return value
    if budget == 1:
        return "…"
    return value[: budget - 1].rstrip() + "…"


def _compact_line(hit: dict) -> str:
    """Render one compact line, strictly under the 200-char budget — trims the summary
    first, then the displayed source if the id+age+source skeleton still overflows."""
    summary = hit["summary"]
    if hit["superseded"]:
        summary = f"{SUPERSEDED_LABEL} {summary}"
    source = hit["source"]
    line = SEP.join([hit["id"], hit["age"], summary, source])
    if len(line) <= _LINE_MAX:
        return line

    # Skeleton = everything except the summary (id + age + source + 3 separators).
    skeleton = len(line) - len(summary)
    keep = _LINE_MAX - skeleton - 1  # -1 reserves the summary ellipsis
    if keep > 0:
        summary = _truncate(summary, keep + 1)
        line = SEP.join([hit["id"], hit["age"], summary, source])
        if len(line) <= _LINE_MAX:
            return line

    # The summary alone cannot save it — the id + source skeleton is too long.
    # Drop the summary to a bare ellipsis and truncate the displayed source as needed.
    summary = "…"
    fixed = len(hit["id"]) + len(hit["age"]) + len(summary) + 3 * len(SEP)
    source = _truncate(source, _LINE_MAX - fixed)
    return SEP.join([hit["id"], hit["age"], summary, source])


def render_compact(hits: list[dict], limit: int) -> str:
    ranked = _rank(hits)[:limit]
    if not ranked:
        return ""
    return "\n".join(_compact_line(h) for h in ranked)


def render_inject(hits: list[dict], limit: int) -> str:
    body = render_compact(hits, limit)
    if not body:
        return ""
    header = "# Relevant Memory\n\n(from past sessions — compact index; `/mb recall --expand <id>` for full)\n"
    return header + body


def render_full(hits: list[dict], limit: int) -> str:
    ranked = _rank(hits)[:limit]
    if not ranked:
        return ""
    blocks = []
    for h in ranked:
        tag = f" {SUPERSEDED_LABEL}" if h["superseded"] else ""
        body = (h["text"] or "").strip()
        blocks.append(f"### {h['id']} ({h['age']}){tag}\n{h['source']}\n{body}")
    return "\n\n".join(blocks)


def render_expand(hits: list[dict], expand_id: str) -> tuple[str, int]:
    for h in hits:
        if h["id"] == expand_id:
            body = (h["text"] or "").strip()
            tag = f" {SUPERSEDED_LABEL}" if h["superseded"] else ""
            out = f"# {h['id']} ({h['age']}){tag}\nsource: {h['source']}\n\n{body}"
            return out, 0
    return "", 3


# Entrypoint
def main(argv=None) -> int:
    try:
        req = json.loads(sys.stdin.read() or "{}")
    except (ValueError, TypeError):
        sys.stderr.write("recall-index: invalid request JSON\n")
        return 2

    mode = req.get("mode", "compact")
    limit = int(req.get("limit") or os.environ.get("MB_RECALL_LIMIT", "10"))
    hits = _build_hits(req)

    if mode == "expand":
        expand_id = req.get("expand_id") or ""
        if not expand_id:
            sys.stderr.write("recall-index: --expand requires an id\n")
            return 2
        out, code = render_expand(hits, expand_id)
        if code != 0:
            sys.stderr.write(
                f"recall: unknown id '{expand_id}' — run /mb recall without "
                "--expand to list valid ids\n"
            )
            return code
        print(out)
        return 0

    if mode == "full":
        out = render_full(hits, limit)
    elif mode == "inject":
        out = render_inject(hits, limit)
    else:
        out = render_compact(hits, limit)

    if out:
        print(out)
        return 0
    return 2  # no hits — caller prints its own "no matches" message


if __name__ == "__main__":
    sys.exit(main())
