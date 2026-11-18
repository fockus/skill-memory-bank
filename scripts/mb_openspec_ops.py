#!/usr/bin/env python3
"""``import`` / ``sync`` / ``list`` / ``status``: the bank-writing side of the adapter.

Nothing here writes outside the bank (REQ-003, NFR-002). A first import writes
the rendered triple; every later bank write (a re-``import`` or a ``sync``)
goes through the per-unit three-way merge (``mb_openspec_merge``) and the
per-unit splice (``mb_openspec_splice``), so bank-only content survives.
Write order (F7): design.md -> backlog orphans -> tasks.md -> sidecar ->
requirements.md (the hash) last, so a crash never finalizes a stale hash.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from mb_openspec_bank import Writer
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_bank import Writer

import mb_openspec_bank as bank_io
from mb_openspec_convert import convert
from mb_openspec_merge import bank_changes, plan_sync
from mb_openspec_parse import compute_source_hash, parse_change
from mb_openspec_publish import publish_topics, write_topic
from mb_openspec_splice import splice_design, splice_requirements, splice_tasks
from mb_openspec_sync import (
    SIDECAR_NAME,
    Triple,
    build_sidecar,
    insert_meta_lines,
    read_sidecar,
    sidecar_text,
    synthetic_sidecar,
)


def usable_sidecar(spec_dir: Path, stored_hash: str) -> dict | None:
    """The sidecar, unless missing, corrupt, or left behind by an interrupted write."""
    data = read_sidecar(spec_dir)
    if data is not None and data.get("openspec_hash") != stored_hash:
        print(
            f"[warn] {spec_dir / SIDECAR_NAME}: does not match requirements.md "
            "(interrupted write?); a baseline will be adopted",
            file=sys.stderr,
        )
        return None
    return data


def merge_topic(
    *,
    ch,
    mb_path: Path,
    spec_dir: Path,
    topic: str,
    bank: Triple,
    sidecar: dict | None,
    stored_hash: str,
    source: str,
    take: str | None,
    normalize: bool,
) -> dict[str, object]:
    """Plan a three-way merge of ``ch`` into the bank triple; writes nothing.

    ``sidecar`` is the usable baseline, or ``None`` to adopt one (AGR-105 Q5 B).
    Without a conflict the result carries ``_write`` (keyword arguments for
    :func:`write_topic`); :func:`apply_merge` performs it.
    """
    rendered = convert(ch, prior_triple=bank, normalize=normalize, topic=topic, mb_path=mb_path)
    adopted = sidecar is None
    if sidecar is None:
        sidecar = synthetic_sidecar(ch, bank, rendered, stored_hash=stored_hash)
    plan = plan_sync(sidecar, ch, bank, rendered, take=take)
    result: dict[str, object] = {
        "topic": topic,
        "adopted": adopted,
        "taken": plan.take,
        "candidates": plan.candidates,
    }
    if plan.conflicts:
        return {**result, "action": "conflict", "conflicts": plan.conflicts}
    req = splice_requirements(bank[0], rendered[0], plan.take, plan.renamed_from)
    req = bank_io.set_frontmatter_hash(insert_meta_lines(req, rendered[0]), source, ch.source_hash)
    design = insert_meta_lines(splice_design(bank[1], rendered[1], plan.take), rendered[1])
    tasks, orphans = splice_tasks(bank[2], rendered[2], plan.take, plan.checks)
    pending = {
        "mb_path": mb_path,
        "spec_dir": spec_dir,
        "topic": topic,
        "new": (req, design, tasks),
        "old": bank,
        "sidecar": sidecar_text(plan.sidecar),
        "orphans": orphans,
        "source_hash": ch.source_hash,
    }
    return {**result, "action": "synced", "orphaned_tasks": len(orphans), "_write": pending}


def apply_merge(result: dict[str, object], write: Writer) -> dict[str, object]:
    """Perform a planned merge's writes; returns the result without the plan."""
    pending = result.pop("_write", None)
    if isinstance(pending, dict):
        write_topic(**pending, write=write)
    return result


def _assert_linked_to(fm: dict[str, str], change_dir: Path, mb_path: Path, topic: str) -> None:
    """An existing topic may only be re-imported from the change it is linked to."""
    source = fm.get("openspec_source")
    if not source:
        raise RuntimeError(
            f"topic '{topic}' exists and is not linked to OpenSpec; import with --as <new topic>"
        )
    linked = bank_io.resolve_stored_source(source, mb_path).resolve()
    if linked != change_dir.resolve():
        raise RuntimeError(
            f"topic '{topic}' is linked to {source}, not to {change_dir}; "
            "import with --as <new topic>"
        )


def run_import(
    *, change_dir: Path, mb_path: Path, topic: str | None, normalize: bool = False, write: Writer
) -> dict[str, object]:
    """Import one change. An existing topic must already be linked to this change
    and is three-way merged; a conflict writes nothing (``action == "conflict"``)."""
    change_dir, mb_path = Path(change_dir), Path(mb_path)
    if not change_dir.is_dir():
        raise FileNotFoundError(f"OpenSpec change dir not found: {change_dir}")
    if not mb_path.is_dir():
        raise FileNotFoundError(f"memory bank not found: {mb_path}")
    ch = parse_change(change_dir)
    resolved = topic or bank_io.slugify(ch.change_id)
    bank_io.validate_topic_slug(resolved)
    specs_dir = mb_path / "specs"
    spec_dir = specs_dir / resolved
    bank_io.assert_within(mb_path, spec_dir)
    bank_io.assert_topic_dir_not_symlink_escape(spec_dir, specs_dir)
    source = bank_io.stable_source_path(change_dir, mb_path)
    prior = bank_io.read_prior_triple(spec_dir)
    summary = {"topic": resolved, "spec_dir": str(spec_dir), "source_hash": ch.source_hash}
    if spec_dir.exists():  # any existing topic, complete or not, must be linked to this change
        req_path = spec_dir / "requirements.md"
        fm = bank_io.parse_frontmatter(req_path.read_text("utf-8")) if req_path.is_file() else {}
        _assert_linked_to(fm, change_dir, mb_path, resolved)
        if prior is None:
            raise RuntimeError(
                f"topic '{resolved}' is incomplete (needs requirements.md and tasks.md)"
            )
    if prior is not None:
        stored = fm.get("openspec_hash", "")
        result = merge_topic(
            ch=ch,
            mb_path=mb_path,
            spec_dir=spec_dir,
            topic=resolved,
            bank=prior,
            sidecar=usable_sidecar(spec_dir, stored),
            stored_hash=stored,
            source=source,
            take=None,
            normalize=normalize,
        )
        return {**summary, **apply_merge(result, write), "reimport": True}
    req, design, tasks = convert(ch, None, normalize, topic=resolved, mb_path=mb_path)
    write_topic(
        mb_path=mb_path,
        spec_dir=spec_dir,
        topic=resolved,
        new=(bank_io.inject_frontmatter(req, source, ch.source_hash), design, tasks),
        old=None,
        sidecar=sidecar_text(build_sidecar(ch, (req, design, tasks))),
        orphans=[],
        source_hash=ch.source_hash,
        write=write,
    )
    return {**summary, "reimport": False, "orphaned_tasks": 0}


def _sync_topic(
    mb_path: Path, topic: str, *, take: str | None, normalize: bool
) -> dict[str, object]:
    try:
        spec_dir, fm, change_dir = bank_io.load_topic(mb_path, topic)
    except (FileNotFoundError, RuntimeError) as exc:
        return {"topic": topic, "action": "error", "reason": str(exc)}
    stored = fm["openspec_hash"]
    bank = bank_io.read_prior_triple(spec_dir)
    if bank is None:
        return {"topic": topic, "action": "error", "reason": "spec triple incomplete"}
    sidecar = usable_sidecar(spec_dir, stored)
    if sidecar is not None and compute_source_hash(change_dir) == stored:
        return {
            "topic": topic,
            "action": "up-to-date",
            "candidates": list(bank_changes(sidecar, bank)),
        }
    return merge_topic(
        ch=parse_change(change_dir),
        mb_path=mb_path,
        spec_dir=spec_dir,
        topic=topic,
        bank=bank,
        sidecar=sidecar,
        stored_hash=stored,
        source=fm["openspec_source"],
        take=take,
        normalize=normalize,
    )


def run_sync(
    *,
    mb_path: Path,
    topic: str | None,
    normalize: bool = False,
    take: str | None = None,
    write: Writer,
) -> list[dict[str, object]]:
    """Three-way sync of one topic (or every imported topic); writes only the bank.

    All or nothing: every topic is planned first, and when any topic conflicts
    or errors no topic is written (the others are reported as ``held``).
    """
    if topic is not None:
        bank_io.validate_topic_slug(topic)
        specs_dir = mb_path / "specs"
        bank_io.assert_topic_dir_not_symlink_escape(specs_dir / topic, specs_dir)
        if not (specs_dir / topic / "requirements.md").is_file():
            raise FileNotFoundError(f"topic not found or never imported: {topic}")
        topics = [topic]
    else:
        topics = [name for name, _dir, _fm in bank_io.iter_imported_topics(mb_path)]
    results = [_sync_topic(mb_path, t, take=take, normalize=normalize) for t in topics]
    failed = any(r["action"] in ("conflict", "error") for r in results)
    pending = [w for r in results if isinstance(w := r.pop("_write", None), dict)]
    if failed:
        for r in results:
            r["action"] = "held" if r["action"] == "synced" else r["action"]
        return results
    publish_topics(pending, write)
    return results
