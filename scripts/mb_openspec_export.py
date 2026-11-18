#!/usr/bin/env python3
"""``export <topic>``: write the bank's changed units back to its OpenSpec change.

Only units the bank changed since the last sync are spliced into
``openspec/changes/<id>/`` (AGR-105 Q3 A, Q4 C); everything else keeps
OpenSpec's bytes. A dry-run diff is the default, ``--write`` applies through
the injected atomic writer. Export refuses when the OpenSpec change moved since
the last sync (run ``sync`` first; there is no ``--force``), deletes only with
``--allow-delete``, never deletes a file, and writes only ``proposal.md``,
``design.md``, ``tasks.md`` and ``specs/<cap>/spec.md`` inside the change.
"""

from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path

try:
    import mb_openspec_bank as bank_io
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mb_openspec_bank as bank_io

import mb_openspec_osfmt as osfmt
from mb_openspec_merge import bank_changes
from mb_openspec_parse import compute_source_hash, parse_change
from mb_openspec_spans import ANCHOR_RE, META_RE, task_spans
from mb_openspec_sync import (
    SIDECAR_NAME,
    Triple,
    bank_units,
    build_sidecar,
    read_sidecar,
    sidecar_text,
)

ALLOWED_FILES = ("proposal.md", "design.md", "tasks.md")
_SECTIONS = {"proposal:why": "Why", "proposal:what-changes": "What Changes"}


def guard_change_dir(change_dir: Path) -> Path:
    """The real change dir, refusing anything but a live ``openspec/changes/<id>``."""
    if Path(change_dir).is_symlink():
        raise RuntimeError(f"refusing to export through a symlinked change dir: {change_dir}")
    real = Path(change_dir).resolve()
    if "archive" in real.parts or "archive" in Path(change_dir).absolute().parts:
        raise RuntimeError(f"refusing to export under an archive directory: {real}")
    if real.parent.name != "changes" or real.parent.parent.name != "openspec":
        raise RuntimeError(f"refusing to export outside openspec/changes/<id>/: {real}")
    return real


def guard_target(change_dir: Path, target: Path) -> None:
    """Refuse any write but the four OpenSpec change files, or one through a symlink."""
    real_dir = guard_change_dir(change_dir)
    try:
        parts = Path(target).relative_to(change_dir).parts
    except ValueError:
        parts = ()
    is_spec = len(parts) == 3 and parts[0] == "specs" and parts[2] == "spec.md"
    if is_spec:
        try:
            bank_io.validate_topic_slug(parts[1])
        except RuntimeError:
            is_spec = False
    if not (is_spec or (len(parts) == 1 and parts[0] in ALLOWED_FILES)):
        raise RuntimeError(f"refusing to write {target}: not an OpenSpec change file")
    probe = Path(change_dir)
    for part in parts:
        probe = probe / part
        if probe.is_symlink():
            raise RuntimeError(f"refusing to write through a symlink: {probe}")
    try:
        Path(target).resolve().relative_to(real_dir)
    except ValueError as exc:
        raise RuntimeError(f"refusing to write outside {real_dir}: {target}") from exc


def _bank_meta(requirements_md: str) -> dict[str, dict[str, str]]:
    """``anchor -> {cap, kind, ...}`` from the meta line before each anchor."""
    out: dict[str, dict[str, str]] = {}
    lines = requirements_md.splitlines()
    for i, line in enumerate(lines):
        m = ANCHOR_RE.match(line)
        if m and i > 0 and META_RE.match(lines[i - 1]):
            body = lines[i - 1][len("<!-- openspec: ") : -len(" -->")]
            pairs = (p.split("=", 1) for p in body.split("; ") if "=" in p)
            out[m.group("name")] = {k.strip(): v.strip() for k, v in pairs}
    return out


class _Export:
    """Builds the new OpenSpec file texts in memory; nothing is written here."""

    def __init__(self, change_dir: Path, sidecar: dict, bank: Triple, allow_delete: bool) -> None:
        self.dir, self.base, self.allow_delete = change_dir, sidecar["units"], allow_delete
        self.ours, self.meta = bank_units(bank), _bank_meta(bank[0])
        self.spans = task_spans(bank[2].splitlines())
        self.old: dict[str, str] = {}
        self.new: dict[str, str] = {}
        self.skipped: list[str] = []
        caps = {e.get("cap") for k, e in self.base.items() if k.startswith("req:") and e.get("cap")}
        self.default_cap = caps.pop() if len(caps) == 1 else None

    def text(self, rel: str) -> str:
        if rel not in self.new:
            path = self.dir / rel
            guard_target(self.dir, path)  # before any read: a bad cap or a symlink never leaks
            self.old[rel] = path.read_text(encoding="utf-8") if path.is_file() else ""
            self.new[rel] = self.old[rel]
        return self.new[rel]

    def skip(self, key: str, why: str) -> None:
        print(f"[warn] {key}: {why}; not exported", file=sys.stderr)
        self.skipped.append(key)

    def run(self, changes: dict[str, str]) -> None:
        added_groups: set[str] = set()
        for key, change in changes.items():
            if change == "delete" and not self.allow_delete:
                self.skip(key, "deleted in the bank; pass --allow-delete to delete it in OpenSpec")
            elif key.startswith(("req:", "removed:")):
                self._requirement(key, change)
            elif key in _SECTIONS or key == "design":
                self._section(key, change)
            elif key.startswith("group:"):
                self._group(key, change, added_groups)
            elif self.spans.get(key) is None or self.spans[key].group not in added_groups:
                self._task(key, change)

    def _requirement(self, key: str, change: str) -> None:
        entry, anchor = self.base.get(key, {}), key.split(":", 1)[1]
        meta = self.meta.get(anchor, {})
        removed = key.startswith("removed:")
        kind = "removed" if removed else entry.get("kind") or meta.get("kind") or "added"
        name = entry.get("name") or anchor.replace("&lt;!--", "<!--").replace("--&gt;", "-->")
        cap = entry.get("cap") or meta.get("cap") or self.default_cap
        if kind == "renamed":
            return self.skip(key, "a RENAMED requirement is edited in OpenSpec only")
        if not removed and "#" in anchor and name != anchor:
            return self.skip(key, "duplicate requirement name; edit it in OpenSpec")
        if not cap:
            return self.skip(key, "no capability; add `<!-- openspec: cap=<cap>; kind=added -->`")
        rel = f"specs/{cap}/spec.md"
        text = self.text(rel)
        kinds = {"removed"} if removed else {kind, "added", "modified"}
        span = osfmt.find_requirement(text, name, kinds)
        if change == "delete":
            self.new[rel] = osfmt.delete_block(text, span) if span else text
            return None
        unit = self.ours[key]["mb"]
        block = osfmt.removed_block(name, unit) if removed else osfmt.requirement_block(name, unit)
        if not removed and not re.search(r"\b(SHALL|MUST)\b", block):
            print(
                f"[warn] {key}: no SHALL/MUST; `openspec validate` will reject it", file=sys.stderr
            )
        if span is not None:
            self.new[rel] = osfmt.replace_block(text, span, block)
        elif change == "add":
            self.new[rel] = osfmt.insert_requirement(text, kind, block)
        else:
            self.skip(key, f"not found in {rel}")
        return None

    def _section(self, key: str, change: str) -> None:
        body = self.ours.get(key, {}).get("mb", "")
        if change == "delete" or body.strip() == "(not provided)":
            return self.skip(key, "export never deletes an OpenSpec section or file")
        if key == "design":
            self.text("design.md")
            self.new["design.md"] = osfmt.promote_headings(body).strip() + "\n"
        else:
            self.new["proposal.md"] = osfmt.replace_section(
                self.text("proposal.md"), _SECTIONS[key], body
            )
        return None

    def _group(self, key: str, change: str, added: set[str]) -> None:
        group = key.split(":", 1)[1]
        title = None if change == "delete" else self.ours[key]["mb"]
        items = [
            (s.checked, s.body[0])
            for k, s in self.spans.items()
            if s.group == group and k in self.ours
        ]
        if change == "add":
            if not group.isdigit():
                return self.skip(key, "OpenSpec task groups are numbered")
            added.add(group)
            items = [(c, t) for c, t in items if c is not None]
        self.new["tasks.md"] = osfmt.set_group(self.text("tasks.md"), group, title, items)
        return None

    def _task(self, key: str, change: str) -> None:
        text, span = self.text("tasks.md"), self.spans.get(key)
        if change == "delete":
            self.new["tasks.md"] = osfmt.edit_task(text, key, None, None) or text
            return None
        assert span is not None and span.group is not None
        done = osfmt.edit_task(text, key, span.body[0], span.checked)
        if done is None and change == "add":
            done = osfmt.add_task(text, span.group, span.body[0], span.checked)
        if done is None:
            return self.skip(key, "not found in tasks.md")
        self.new["tasks.md"] = done
        return None


def print_diff(prefix: str, old: dict[str, str], new: dict[str, str]) -> list[str]:
    """Print a unified diff per changed file under ``prefix``; returns the changed paths."""
    changed = sorted(rel for rel in new if new[rel] != old.get(rel, ""))
    for rel in changed:
        before = old.get(rel, "")
        diff = difflib.unified_diff(
            before.splitlines(keepends=True),
            new[rel].splitlines(keepends=True),
            "/dev/null" if not before else f"a/{prefix}/{rel}",
            f"b/{prefix}/{rel}",
        )
        sys.stdout.writelines(diff)
    return changed


def run_export(*, mb_path: Path, topic: str, apply: bool, allow_delete: bool, write) -> int:
    spec_dir, fm, change_dir = bank_io.load_topic(Path(mb_path), topic)
    guard_change_dir(change_dir)
    stored = fm["openspec_hash"]
    if compute_source_hash(change_dir) != stored:
        raise RuntimeError(
            f"OpenSpec change {change_dir.name} changed since the last sync; "
            f"run `sync {topic}` first (export never overwrites OpenSpec edits)"
        )
    sidecar = read_sidecar(spec_dir)
    bank = bank_io.read_prior_triple(spec_dir)
    if sidecar is None or sidecar.get("openspec_hash") != stored or bank is None:
        raise RuntimeError(f"no usable sync baseline for '{topic}'; run `sync {topic}` first")
    job = _Export(change_dir, sidecar, bank, allow_delete)
    job.run(bank_changes(sidecar, bank))
    changed = print_diff(f"openspec/changes/{change_dir.name}", job.old, job.new)
    if not changed:
        print(f"{topic}: nothing to export")
        return 0
    if not apply:
        print(f"{topic}: dry run, nothing written; re-run with --write to apply")
        return 0
    for rel in changed:
        guard_target(change_dir, change_dir / rel)
    _assert_unchanged(change_dir, stored, job.old, spec_dir, bank)
    for rel in changed:
        write(change_dir / rel, job.new[rel])
    rebaseline(Path(mb_path), spec_dir, change_dir, bank, sidecar, job.skipped, fm, write)
    print(f"{topic}: exported to openspec/changes/{change_dir.name}/ ({', '.join(changed)})")
    return 0


def _assert_unchanged(change_dir: Path, stored: str, old: dict, spec_dir: Path, bank) -> None:
    """Compare-and-swap: abort when OpenSpec or the bank moved since the diff was built."""
    for rel, text in old.items():
        path = change_dir / rel
        if (path.read_text(encoding="utf-8") if path.is_file() else "") != text:
            raise RuntimeError(f"{path} changed during export; nothing written, run sync")
    if compute_source_hash(change_dir) != stored:
        raise RuntimeError(f"{change_dir} changed during export; nothing written, run sync")
    if bank_io.read_prior_triple(spec_dir) != bank:
        raise RuntimeError(f"{spec_dir} changed during export; nothing written, run export again")


def rebaseline(mb_path, spec_dir, change_dir, bank, old_sidecar, skipped, fm, write) -> None:
    """New baseline after a write: exported units match, skipped ones stay candidates.

    A bank edited while OpenSpec was being written is never overwritten with the
    stale copy: the baseline stays old, and the next ``sync`` reconciles.
    """
    if bank_io.read_prior_triple(spec_dir) != bank:
        raise RuntimeError(f"{spec_dir} changed during export; OpenSpec written, run sync")
    ch = parse_change(change_dir)
    data = build_sidecar(ch, bank)
    units = {k: e for k, e in data["units"].items() if e.get("os") is not None}
    for key in skipped:
        units.pop(key, None)
        if key in old_sidecar["units"]:
            units[key] = old_sidecar["units"][key]
    data["units"] = units
    write(spec_dir / SIDECAR_NAME, sidecar_text(data))
    req = bank_io.set_frontmatter_hash(bank[0], fm["openspec_source"], ch.source_hash)
    bank_io.assert_within(mb_path, spec_dir / "requirements.md")
    write(spec_dir / "requirements.md", req)
