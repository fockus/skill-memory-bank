#!/usr/bin/env python3
"""Plan frontmatter parsing + collection for mb-roadmap-sync.sh.

Split out of the shell heredoc so scripts/mb-roadmap-sync.sh stays under the
400-line project gate (S4 review finding 10). Pure stdlib, no side effects on
import; every helper here is directly unit-testable.

``collect_plans`` is the single entry point: it scans ``plans/*.md`` (never
``plans/done/``), parses the YAML-ish frontmatter of each and returns one plain
dict per plan. Warnings about malformed frontmatter go to stderr and never fail
the run — the roadmap must still render for the plans that ARE well-formed.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from mb_roadmap_order import ice_is_block_style, parse_ice_score, parse_pin

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)

BLOCK_LIST_RE = re.compile(
    r"^(depends_on|linked_specs):\s*$\n(\s+-\s+)",
    re.MULTILINE,
)

_DATE_PREFIX_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})_")

_TRUE_TOKENS = {"true", "yes", "on", "1"}
_FALSE_TOKENS = {"false", "no", "off", "0", ""}


def parse_frontmatter(text):
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        out[k.strip()] = v.strip()
    return out


def parse_list(raw):
    """Parse a YAML flow-style list like `[a, b, c]` or `[]`. Returns [] on failure."""
    raw = raw.strip()
    if not (raw.startswith("[") and raw.endswith("]")):
        return []
    inner = raw[1:-1].strip()
    if not inner:
        return []
    return [item.strip().strip("\"'") for item in inner.split(",") if item.strip()]


def plan_title(path, text):
    for line in text.splitlines():
        if line.startswith("# "):
            title = line[2:].strip()
            # Strip a leading `Type:` prefix if any
            title = re.sub(r"^[A-Za-zА-Яа-я][\w\s/-]*:[\s　]*", "", title)
            return title or path.name
    return path.name


def parse_bool(raw, key, plan_rel):
    v = raw.strip().lower()
    if v in _TRUE_TOKENS:
        return True
    if v in _FALSE_TOKENS:
        return False
    print(
        f"[warn] plan {plan_rel}: {key}='{raw}' is not a recognized boolean; treating as false",
        file=sys.stderr,
    )
    return False


def detect_block_style_keys(text):
    """Return frontmatter keys that use block-style YAML lists."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return []
    raw = m.group(1)
    return [match.group(1) for match in BLOCK_LIST_RE.finditer(raw + "\n")]


def _warn_invalid_ice(rel, text):
    if ice_is_block_style(text):
        print(
            f"[warn] plan {rel}: ice uses block-style mapping; "
            "use flow-style {impact: N, confidence: N, ease: N}",
            file=sys.stderr,
        )
    else:
        print(
            f"[warn] plan {rel}: ice is not a valid flow-mapping "
            "{impact: N, confidence: N, ease: N} with integer components "
            "1..10; ignoring",
            file=sys.stderr,
        )


def collect_plans(plans_dir):
    """Return one dict per well-formed plan under ``plans_dir`` (not ``done/``).

    ICE-component parsing and priority ordering live in the pure, unit-tested
    module mb_roadmap_order.py (design.md C1/C2) — reused, never reimplemented.
    """
    plans = []
    for path in sorted(Path(plans_dir).glob("*.md")):
        if path.parent.name == "done":
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        fm = parse_frontmatter(text)
        if not fm:
            print(f"[warn] skipping plan without frontmatter: {path}", file=sys.stderr)
            continue
        for key in detect_block_style_keys(text):
            print(
                f"[warn] plan {path}: {key} uses block-style list; use flow-style [a, b]",
                file=sys.stderr,
            )
        rel = f"plans/{path.name}"
        ice_present = "ice" in fm
        ice_score = parse_ice_score(fm.get("ice", "")) if ice_present else None
        if ice_present and ice_score is None:
            _warn_invalid_ice(rel, text)
        dm = _DATE_PREFIX_RE.match(path.name)
        plans.append(
            {
                "path": path,
                "rel": rel,
                "status": fm.get("status", "").strip(),
                "depends_on": parse_list(fm.get("depends_on", "[]")),
                "parallel_safe": parse_bool(fm.get("parallel_safe", "false"), "parallel_safe", rel),
                "linked_specs": parse_list(fm.get("linked_specs", "[]"))
                + ([fm["linked_spec"].strip()] if fm.get("linked_spec", "").strip() else []),
                "topic": fm.get("topic", path.stem).strip(),
                "sprint": fm.get("sprint", "").strip(),
                "phase_of": fm.get("phase_of", "").strip(),
                "title": plan_title(path, text),
                "ice_score": ice_score,
                "pin": parse_pin(fm.get("pin", "")) if "pin" in fm else None,
                "ice_confirmed": fm.get("ice_confirmed", "").strip().lower() == "true",
                "created": dm.group(1) if dm else None,
            }
        )
    return plans
