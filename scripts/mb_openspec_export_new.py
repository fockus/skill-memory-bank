#!/usr/bin/env python3
"""``export <topic> --new``: project a bank-authored spec into a new OpenSpec change.

``proposal.md`` gets Why / What Changes from the bank ``design.md``;
``specs/<cap>/spec.md`` gets every REQ as ADDED (name = its group title, plus
`` <k>`` when the group has several REQs) with the scenarios that cover it;
``tasks.md`` gets one ``## N.`` group per ``mb-task`` with its checkboxes as
``N.M``. The bank then gains ``openspec_source``, meta lines, anchors, task ids
and the sidecar, so the topic round-trips from then on (AGR-105 Q7 A). Refuses
when a different change exists or ``openspec/`` is missing; dry-run unless
``apply``. The change is built in a sibling temp dir and renamed into place;
a rerun after a crash finds the identical change and finishes the bank links.
"""

from __future__ import annotations

import contextlib
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

try:
    import mb_openspec_bank as bank_io
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mb_openspec_bank as bank_io

from mb_openspec_export import guard_change_dir, guard_target, print_diff
from mb_openspec_ids import anchor_safe
from mb_openspec_osfmt import scenario_lines
from mb_openspec_parse import parse_change
from mb_openspec_spans import GROUP_MARKER_RE, GROUP_TITLE_RE, design_spans
from mb_openspec_sync import SIDECAR_NAME, build_sidecar, sidecar_text
from mb_openspec_tasks import task_id

_REQ_RE = re.compile(r"^- \*\*(?P<id>REQ-\d{3,})\*\* \([^)]*\):\s*(?P<text>.*)$")
_GROUP_HEAD_RE = re.compile(r"^### (?:Requirement \d+: )?(?P<title>.+?)\s*$")
_SCENARIO_OPEN_RE = re.compile(r"^<!-- mb-scenario:\d+ -->$")
_STEP_RE = re.compile(r"^- (?P<kw>GIVEN|WHEN|THEN|AND|BUT) (?P<text>.*)$")
_CHECKBOX_RE = re.compile(r"^- \[(?P<mark>[ xX])\] (?P<text>.+)$")


def _requirements(lines: list[str]) -> list[tuple[int, str, str, str]]:
    """``(line, req_id, name, text)`` per REQ bullet, named after its group heading."""
    found: list[tuple[int, str, str, str | None]] = []
    title: str | None = None
    for i, line in enumerate(lines):
        if line.startswith("## "):
            title = None
        elif (head := _GROUP_HEAD_RE.match(line)) and line.startswith("### "):
            title = head.group("title")
        elif m := _REQ_RE.match(line):
            found.append((i, m.group("id"), m.group("text").strip(), title))
    counts: dict[str | None, int] = {}
    for *_rest, t in found:
        counts[t] = counts.get(t, 0) + 1
    out: list[tuple[int, str, str, str]] = []
    seen: set[str] = set()
    index: dict[str | None, int] = {}
    for k, (i, rid, text, t) in enumerate(found, start=1):
        index[t] = index.get(t, 0) + 1
        # REQ-IDs are bank-internal and never become an OpenSpec name (AGR-105 Q2 B).
        name = f"Requirement {k}"
        if t is not None and not re.search(r"REQ-\d", t):
            name = t if counts[t] == 1 else f"{t} {index[t]}"
        base, n = name, 1
        while name in seen:
            n += 1
            name = f"{base} ({n})"
        seen.add(name)
        out.append((i, rid, name, text))
    return out


def _scenarios(lines: list[str]) -> dict[str, list[tuple[str, list[tuple[str, str]]]]]:
    """``REQ-ID -> [(scenario name, steps)]`` from the bank's mb-scenario blocks."""
    out: dict[str, list] = {}
    current: tuple[str, list[tuple[str, str]], list[str]] | None = None
    for line in [*lines, "<!-- mb-scenario:0 -->"]:
        if _SCENARIO_OPEN_RE.match(line) or line.startswith("<!-- /mb-scenario:"):
            if current is not None:
                for rid in current[2]:
                    out.setdefault(rid, []).append((current[0], current[1]))
            current = ("", [], []) if _SCENARIO_OPEN_RE.match(line) else None
        elif current is not None:
            if line.startswith("### Scenario: "):
                current = (line[len("### Scenario: ") :].strip(), current[1], current[2])
            elif line.startswith("**Covers:**"):
                current[2].extend(re.findall(r"REQ-\d{3,}", line))
            elif step := _STEP_RE.match(line):
                current[1].append((step.group("kw"), step.group("text")))
    return out


def _tasks(lines: list[str]) -> list[tuple[str, str, list[tuple[int, bool, str]]]]:
    """``(N, title, [(line, checked, text with N.M id)])`` per numbered mb-task group."""
    groups: list[tuple[str, str, list[tuple[int, bool, str]]]] = []
    for i, line in enumerate(lines):
        if (m := GROUP_MARKER_RE.match(line)) and m.group("n").isdigit():
            groups.append((m.group("n"), "", []))
        elif groups and (t := GROUP_TITLE_RE.match(line)) and t.group("n") == groups[-1][0]:
            groups[-1] = (groups[-1][0], t.group("title").strip(), groups[-1][2])
        elif groups and (c := _CHECKBOX_RE.match(line)):
            n, _title, items = groups[-1]
            text = c.group("text").strip()
            text = text if task_id(text) else f"{n}.{len(items) + 1} {text}"
            items.append((i, c.group("mark").lower() == "x", text))
    return groups


def _section_text(design_md: str, key: str) -> str:
    lines = design_md.splitlines()
    span = design_spans(lines).get(key)
    text = "\n".join(lines[span.start : span.end]) if span else ""
    if not text:
        print(
            f"[warn] bank design.md has no {key} section; proposal gets a placeholder",
            file=sys.stderr,
        )
    return text or "(not provided)"


def _same_change(change_dir: Path, files: dict[str, str]) -> bool:
    """True when ``change_dir`` holds exactly ``files`` (a crashed run to resume)."""
    if change_dir.is_symlink() or not change_dir.is_dir():
        return False
    found = {p.relative_to(change_dir).as_posix() for p in change_dir.rglob("*") if p.is_file()}
    return found == set(files) and all(
        (change_dir / rel).read_text(encoding="utf-8") == text for rel, text in files.items()
    )


def _create_change(change_dir: Path, files: dict[str, str], write) -> None:
    """Write the change into a sibling temp dir, then rename it into place atomically."""
    change_dir.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=f".{change_dir.name}.", dir=change_dir.parent))
    reserved = False
    try:
        for rel, text in files.items():
            guard_target(tmp, tmp / rel)
            write(tmp / rel, text)
        try:
            os.mkdir(change_dir)  # exclusive reservation: rename may replace an empty dir
        except FileExistsError as exc:
            raise RuntimeError(f"OpenSpec change already exists: {change_dir}") from exc
        reserved = True
        os.rename(tmp, change_dir)  # replaces only our own empty reservation
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        if reserved:
            with contextlib.suppress(OSError):
                change_dir.rmdir()
        raise


def run_export_new(
    *, mb_path: Path, topic: str, change_id, cap, openspec_root, apply: bool, write
) -> int:
    mb_path = Path(mb_path)
    bank_io.validate_topic_slug(topic)
    specs_dir = mb_path / "specs"
    spec_dir = specs_dir / topic
    bank_io.assert_topic_dir_not_symlink_escape(spec_dir, specs_dir)
    bank = bank_io.read_prior_triple(spec_dir)
    if bank is None:
        raise FileNotFoundError(f"topic needs requirements.md and tasks.md: {spec_dir}")
    if "openspec_source" in bank_io.parse_frontmatter(bank[0]):
        raise RuntimeError(f"topic '{topic}' is already linked to OpenSpec; use `export {topic}`")
    change_id, cap = change_id or topic, cap or topic
    for value in (change_id, cap):
        bank_io.validate_topic_slug(value)
    root = Path(openspec_root) if openspec_root else mb_path.resolve().parent
    if not (root / "openspec").is_dir():
        raise RuntimeError(f"no openspec/ directory under {root}; run `openspec init` first")
    change_dir = root / "openspec" / "changes" / change_id
    guard_change_dir(change_dir)

    req_lines, task_lines = bank[0].splitlines(), bank[2].splitlines()
    reqs, scenarios, groups = _requirements(req_lines), _scenarios(req_lines), _tasks(task_lines)
    blocks = []
    for _i, rid, name, text in reqs:
        block = [f"### Requirement: {name}", text]
        for sname, steps in scenarios.get(rid, []):
            block += scenario_lines(sname, steps)
        blocks.append("\n".join(block))
    files = {
        "proposal.md": f"## Why\n\n{_section_text(bank[1], 'proposal:why')}\n\n"
        f"## What Changes\n\n{_section_text(bank[1], 'proposal:what-changes')}\n",
        f"specs/{cap}/spec.md": "## ADDED Requirements\n\n" + "\n\n".join(blocks) + "\n",
        "tasks.md": "\n\n".join(
            f"## {n}. {title}\n\n" + "\n".join(f"- [{'x' if c else ' '}] {t}" for _i, c, t in items)
            for n, title, items in groups
        )
        + "\n",
    }
    for i, _rid, name, _text in reversed(reqs):
        req_lines[i:i] = [
            f"<!-- openspec: cap={cap}; kind=added -->",
            f"<!-- openspec-req: {anchor_safe(name)} -->",
        ]
    for _n, _title, items in groups:
        for i, checked, text in items:
            task_lines[i] = f"- [{'x' if checked else ' '}] {text}"
    new_req, new_tasks = "\n".join(req_lines) + "\n", "\n".join(task_lines) + "\n"
    resume = change_dir.exists() or change_dir.is_symlink()
    if resume and not _same_change(change_dir, files):
        raise RuntimeError(f"OpenSpec change already exists: {change_dir}")
    if resume:
        print(f"{topic}: {change_dir.name} already holds this projection; only the bank is linked")
    else:
        print_diff(f"openspec/changes/{change_id}", {}, files)
    print_diff(
        f"specs/{topic}",
        {"requirements.md": bank[0], "tasks.md": bank[2]},
        {"requirements.md": new_req, "tasks.md": new_tasks},
    )
    if not apply:
        print(f"{topic}: dry run, nothing written; re-run with --write to create {change_dir.name}")
        return 0
    if bank_io.read_prior_triple(spec_dir) != bank:  # re-read under the bank lock
        raise RuntimeError(f"{spec_dir} changed during export --new; nothing written")
    if not resume:
        _create_change(change_dir, files, write)
    ch = parse_change(change_dir)
    source = bank_io.stable_source_path(change_dir, mb_path)
    new_req = bank_io.set_frontmatter_hash(new_req, source, ch.source_hash)
    data = build_sidecar(ch, (new_req, bank[1], new_tasks))
    data["units"] = {k: e for k, e in data["units"].items() if e.get("os") is not None}
    for name, text in (
        ("tasks.md", new_tasks),
        (SIDECAR_NAME, sidecar_text(data)),
        ("requirements.md", new_req),
    ):
        bank_io.assert_within(mb_path, spec_dir / name)
        write(spec_dir / name, text)
    print(f"{topic}: created openspec/changes/{change_dir.name}/ and linked the topic to it")
    return 0
