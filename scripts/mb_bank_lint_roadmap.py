#!/usr/bin/env python3
"""Roadmap-side checks of mb-bank-lint.sh (design.md C5, REQ-004, REQ-012).

Scans the frontmatter that feeds the roadmap (``plans/*.md`` and
``specs/*/requirements.md``): ``ice``, ``ice_confirmed``, ``pin``, ``group``,
``blocked_by``, plus fence group headers and the sync ``--check`` verdict.
Read-only. A finding is ``(severity, code, path, line, detail)``.
"""

import re
import subprocess
from pathlib import Path

from mb_roadmap_group import GroupOrderingError, _parse_blocked_by_strict
from mb_roadmap_order import parse_ice_score, parse_pin

FM_RE = re.compile(r"^---\s*\n(.*?)\n---\s*(?:\n|$)", re.DOTALL)
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
FENCE_OPEN, FENCE_CLOSE = "<!-- mb-roadmap-auto -->", "<!-- /mb-roadmap-auto -->"


def frontmatter(text):
    """{key: (value, 1-based file line)} for the leading frontmatter, first key wins."""
    m = FM_RE.match(text)
    if not m:
        return None
    out = {}
    for i, line in enumerate(m.group(1).splitlines(), start=2):
        if ":" not in line or line[:1] in (" ", "\t", "#"):
            continue
        key, _, val = line.partition(":")
        out.setdefault(key.strip(), (val.strip(), i))
    return out


def check_element(path, fm, require_ice, findings):
    """Per-element checks; ``require_ice`` enables the no_ice warning."""
    ice = fm.get("ice")
    confirmed = fm.get("ice_confirmed")
    if ice is None:
        if require_ice:
            findings.append(("warning", "no_ice", path, 1, "element has no ice"))
    elif parse_ice_score(ice[0]) is None:
        findings.append(("error", "invalid_ice", path, ice[1], f"ice must be a flow-mapping {{impact, confidence, ease}} of 1..10; got {ice[0]!r}"))
    elif confirmed is None or confirmed[0] == "false":
        findings.append(("warning", "ice_unconfirmed", path, ice[1], "ice not confirmed (ice_confirmed: true missing)"))
    if confirmed is not None and confirmed[0] not in ("true", "false"):
        findings.append(("error", "invalid_ice_confirmed", path, confirmed[1], f"ice_confirmed must be true|false; got {confirmed[0]!r}"))
    pin = fm.get("pin")
    if pin is not None and parse_pin(pin[0]) is None:
        findings.append(("error", "invalid_pin", path, pin[1], f"pin must be a base-10 integer > 0; got {pin[0]!r}"))
    group = fm.get("group")
    if group is not None and not SLUG_RE.match(group[0]):
        findings.append(("error", "invalid_group", path, group[1], f"group must match [a-z0-9][a-z0-9-]*; got {group[0]!r}"))
    blocked = fm.get("blocked_by")
    if blocked is not None:
        try:
            _parse_blocked_by_strict(blocked[0], path)
        except GroupOrderingError:
            findings.append(("error", "invalid_blocked_by", path, blocked[1], f"blocked_by must be a flow-list of unique slugs; got {blocked[0]!r}"))


def duplicate_pins(entries, findings):
    """entries: (section_key, path, pin_value, line) — warn on a repeated valid pin."""
    seen = {}
    for section, path, raw, line in entries:
        n = parse_pin(raw)
        if n is None:
            continue
        first = seen.setdefault((section, n), path)
        if first != path:
            findings.append(("warning", "duplicate_pin", path, line, f"pin {n} already used by {first} in {section}"))


def scan_files(bank, rel_of):
    """Collect findings from plans and spec requirements; return (findings, group slugs)."""
    findings, pins, groups = [], [], set()
    sources = [(p, False) for p in sorted((bank / "plans").glob("*.md"))]
    sources += [(p, True) for p in sorted((bank / "specs").glob("*/requirements.md"))]
    for path, is_spec in sources:
        try:
            fm = frontmatter(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError):
            continue
        if fm is None:
            continue
        rel = rel_of(path)
        if is_spec and "group" in fm and SLUG_RE.match(fm["group"][0]):
            groups.add(fm["group"][0])
        check_element(rel, fm, require_ice=(not is_spec) or "group" in fm, findings=findings)
        if "pin" in fm:
            section = f"group {fm['group'][0]}" if is_spec and "group" in fm else f"status {fm.get('status', ('?',))[0]}"
            pins.append((section, rel, fm["pin"][0], fm["pin"][1]))
    duplicate_pins(pins, findings)
    return findings, groups


def fence_findings(bank, rel_of, groups, script_dir):
    """orphan_group for fence headers without a spec; progress_mismatch via sync --check."""
    findings, roadmap = [], bank / "roadmap.md"
    if not roadmap.is_file():
        return findings
    lines = roadmap.read_text(encoding="utf-8").split("\n")
    inside = False
    for i, ln in enumerate(lines, start=1):
        if FENCE_OPEN in ln:
            inside = True
        elif FENCE_CLOSE in ln:
            inside = False
        elif inside:
            m = re.match(r"^## Group: (\S+)\s*$", ln)
            if m and m.group(1) not in groups:
                findings.append(("warning", "orphan_group", rel_of(roadmap), i, f"group {m.group(1)} has no specs/*/requirements.md"))
    if (bank / "plans").is_dir():
        res = subprocess.run(
            ["bash", str(Path(script_dir) / "mb-roadmap-sync.sh"), "--check", str(bank)],
            capture_output=True, text=True, check=False,
        )
        if res.returncode == 1:
            findings.append(("error", "progress_mismatch", rel_of(roadmap), 0, "roadmap autosync block is stale; run mb-roadmap-sync.sh"))
    return findings
