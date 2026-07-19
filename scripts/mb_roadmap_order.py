#!/usr/bin/env python3
"""Pure ICE-component parsing + priority ordering for mb-roadmap-sync.sh.

Extracted from the roadmap-sync embedded script (spec svp-roadmap-backlog-db,
design.md C1/C2) so the ordering contract is unit-testable in isolation and the
shell script stays under the 400-line SRP gate. This module has ZERO filesystem
side-effects — it operates on plain item dicts and returns ordered lists.

Item dict keys consumed here:
    name        str  — the plan file basename (e.g. "2026-01-01_feature_x.md")
    rel         str  — repo-relative path (e.g. "plans/…")
    topic       str  — frontmatter topic
    depends_on  list — flow-style dependency tokens (names / rels)
    ice_score   int | None — precomputed I×C×E product, or None (absent/invalid)
    pin         int | None — positive-int manual override, or None
    created     str | None — YYYY-MM-DD tie-break key, or None

`path` (a pathlib object) is accepted as an alias for `name` so the embedded
caller can pass its existing item dicts unchanged.

Public API
----------
parse_ice_score(raw)            -> int | None
ice_is_block_style(text)        -> bool
parse_pin(raw)                  -> int | None
has_priority(item)              -> bool
priority_key(item)              -> tuple
priority_order(items, warn=...) -> list
"""

from __future__ import annotations

import re
import sys

_INT_RE = re.compile(r"^-?\d+$")
_ICE_BLOCK_RE = re.compile(r"(?m)^ice:[ \t]*$\n[ \t]+\w+[ \t]*:")
_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)

# Canonical cycle warning grammar (byte-identical to the legacy DFS warning).
CYCLE_WARNING = "[warn] dependency cycle while sorting roadmap near {name}; keeping stable order"


def parse_ice_score(raw):
    """Compute score = impact*confidence*ease from a flow-mapping ice value.

    The value MUST be a flow-mapping ``{impact: N, confidence: N, ease: N}`` with
    EXACTLY those three keys (any order, no duplicates), each an integer 1..10.
    Returns the integer product on success, else None for every malformed shape
    (not a mapping, wrong/duplicate/extra keys, non-integer or out-of-range
    component, plain-int, empty). Never raises.
    """
    raw = (raw or "").strip()
    if not (raw.startswith("{") and raw.endswith("}")):
        return None
    inner = raw[1:-1].strip()
    if not inner:
        return None
    comp = {}
    for part in inner.split(","):
        part = part.strip()
        if not part or ":" not in part:
            return None
        k, _, v = part.partition(":")
        k = k.strip()
        v = v.strip()
        if k in comp:
            return None
        comp[k] = v
    if set(comp) != {"impact", "confidence", "ease"}:
        return None
    score = 1
    for key in ("impact", "confidence", "ease"):
        v = comp[key]
        if not _INT_RE.match(v):
            return None
        try:
            n = int(v)
        except ValueError:
            # Oversized run of digits (past CPython int_max_str_digits): the
            # regex matched but int() refuses it — degrade to invalid, never
            # crash the sync (C1). A valid component is only 1..10 anyway.
            return None
        if n < 1 or n > 10:
            return None
        score *= n
    return score


def ice_is_block_style(text):
    """True when the frontmatter of ``text`` carries a block-style ice mapping."""
    m = _FRONTMATTER_RE.match(text or "")
    if not m:
        return False
    return bool(_ICE_BLOCK_RE.search(m.group(1) + "\n"))


def parse_pin(raw):
    """Return a positive integer pin, or None when absent/invalid."""
    raw = (raw or "").strip()
    if not raw or not _INT_RE.match(raw):
        return None
    try:
        n = int(raw)
    except ValueError:
        # Oversized run of digits (past CPython int_max_str_digits) ⇒ invalid
        # pin, not a crash (C1).
        return None
    return n if n > 0 else None


def _name(item):
    p = item.get("path")
    if p is not None:
        return p.name
    return item.get("name", "")


def has_priority(item):
    """True when the item carries a valid ice score OR a pin (⇒ priority mode)."""
    return item.get("ice_score") is not None or item.get("pin") is not None


def priority_key(item):
    """Total-order comparator: pin↑ → score↓ → created↑ → topic↑ → rel↑."""
    pin = item.get("pin")
    pin_key = pin if pin is not None else float("inf")
    score = item.get("ice_score")
    score_key = -score if score is not None else float("inf")
    created = item.get("created") or "9999-12-31"
    return (pin_key, score_key, str(created), str(item.get("topic", "")), str(item.get("rel", "")))


def priority_order(items, warn=None):
    """Round-based Kahn with the priority comparator (design.md C2 priority mode).

    Each round: the frontier (all deps already emitted) splits into `prioritized`
    (valid ice OR pin, sorted by priority_key) and `legacy_tail` (neither, in
    original relative order); prioritized emit first. A cycle prints the legacy
    cycle-warning grammar naming the first remaining item and emits the rest in
    original order. Dependencies outside the item set are ignored.
    """
    if warn is None:

        def warn(msg):
            print(msg, file=sys.stderr)

    by_key = {}
    for item in items:
        name = _name(item)
        by_key[name] = item
        by_key[str(item.get("rel", ""))] = item
        by_key["plans/" + name] = item

    def dep_names(item):
        result = []
        for dep in item.get("depends_on", []) or []:
            dn = str(dep).strip().strip("\"'")
            di = by_key.get(dn) or by_key.get(
                dn[len("plans/") :] if dn.startswith("plans/") else dn
            )
            if di is not None:
                result.append(_name(di))
        return result

    remaining = list(items)
    emitted = set()
    out = []
    while remaining:
        frontier = [it for it in remaining if all(d in emitted for d in dep_names(it))]
        if not frontier:
            warn(CYCLE_WARNING.format(name=_name(remaining[0])))
            out.extend(remaining)
            break
        prioritized = sorted([it for it in frontier if has_priority(it)], key=priority_key)
        legacy_tail = [it for it in frontier if not has_priority(it)]
        for it in prioritized + legacy_tail:
            out.append(it)
            emitted.add(_name(it))
        remaining = [it for it in remaining if _name(it) not in emitted]
    return out
