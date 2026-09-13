#!/usr/bin/env python3
"""Single reader/writer for `checklist.md` in the v2 format (one block per plan).

Subcommands (all take ``--checklist <path>``):

    plan     TSV of archivable blocks: `key<TAB>label<TAB>base64(text)`.
    apply    Fold v1 blocks into v2, drop `--drop KEY` blocks, enforce `--cap`.
    upsert   Add a plan's missing stages (used by mb-plan-sync.sh).
    flip     Mark one stage ✅ (mirrors a DoD flip made by mb-work-checkbox.sh).
    extract  Print one plan's block verbatim (used by mb-plan-done.sh).

`apply` writes a `.checklist.md.bak.<ts>` backup only when content changes, and
exits 3 when the result is still over the cap — the caller's signal that live
work does not fit, never a licence to cut it.

Parsing/rendering lives in ``memory_bank_skill/checklist_v2.py``.
"""

from __future__ import annotations

import argparse
import base64
import re
import sys
import time
from pathlib import Path

try:
    from memory_bank_skill import checklist_v2 as cl
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill import checklist_v2 as cl


def _read(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines()


def _write(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _titles(plans_dir: Path | None, plans: set[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    if plans_dir is None:
        return out
    for name in plans:
        for candidate in (plans_dir / name, plans_dir / "done" / name):
            if candidate.is_file():
                out[name] = cl.plan_title(candidate.read_text(encoding="utf-8"), name)
                break
    return out


def _is_closed(plans_dir: Path | None, plan: str) -> bool:
    """A plan is closed when its file sits in `plans/done/` and not in `plans/`."""
    if plans_dir is None:
        return False
    return (plans_dir / "done" / plan).is_file() and not (plans_dir / plan).is_file()


def _archivable(lines: list[str], plans_dir: Path | None) -> list[dict[str, str]]:
    blocks, legacy = cl.parse(lines)
    by_plan: dict[str, list[cl.PlanBlock]] = {}
    for b in blocks:
        by_plan.setdefault(b.plan, []).append(b)
    titles = _titles(plans_dir, set(by_plan))
    out: list[dict[str, str]] = []
    for plan, group in by_plan.items():
        title, stages, extra = cl.merge(group)
        if not stages or not _is_closed(plans_dir, plan):
            continue  # a plan still in plans/ is live work — never archived
        text = cl.render_block(plan, title or titles.get(plan) or plan, stages, extra)
        out.append({"key": f"plan:{plan}", "label": plan, "text": "\n".join(text)})
    for sec in legacy:
        text = cl.legacy_text(lines, sec)
        out.append({"key": cl.legacy_key(sec, text), "label": sec.heading, "text": text})
    return out


def _cap_report(lines: list[str], cap: int, moved: int) -> str:
    blocks, _ = cl.parse(lines)
    by_plan: dict[str, list[cl.PlanBlock]] = {}
    for b in blocks:
        by_plan.setdefault(b.plan, []).append(b)
    parts = []
    for plan, group in by_plan.items():
        _, stages, _ = cl.merge(group)
        open_n = sum(1 for s in stages.values() if not s.done)
        parts.append(f"{plan}: {open_n} open")
    tail = "nothing was moved" if moved == 0 else f"{moved} block(s) archived, still over cap"
    return (
        f"[error] over cap by {len(lines) - cap} lines: {len(by_plan)} plans in flight "
        f"({', '.join(parts)}) — pause or close plans, {tail}"
    )


def _sync_header_cap(lines: list[str], cap: int) -> list[str]:
    """Rewrite the file's own `cap ≤NNN lines` convention line to the resolved cap."""
    pattern = re.compile(r"(cap[^\n]*?≤\s*)\d+(\s*(?:lines|строк))", re.IGNORECASE)
    return [pattern.sub(rf"\g<1>{cap}\g<2>", ln) if "cap" in ln.lower() else ln for ln in lines]


def cmd_plan(args: argparse.Namespace) -> int:
    """One TSV line per archivable block: key, label, base64 of the verbatim text."""
    for entry in _archivable(_read(Path(args.checklist)), args.plans_dir):
        blob = base64.b64encode(entry["text"].encode("utf-8")).decode("ascii")
        print(f"{entry['key']}\t{entry['label']}\t{blob}")
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    path = Path(args.checklist)
    lines = _read(path)
    blocks, _ = cl.parse(lines)
    titles = _titles(args.plans_dir, {b.plan for b in blocks})
    new = cl.rewrite(lines, titles, drop=set(args.drop))
    if args.cap > 0:
        new = _sync_header_cap(new, args.cap)
    changed = new != lines
    if changed:
        path.with_name(f".{path.name}.bak.{int(time.time())}").write_text(
            "\n".join(lines) + "\n", encoding="utf-8"
        )
        _write(path, new)
    print(f"[checklist-v2] lines={len(new)} changed={'yes' if changed else 'no'} dropped={len(args.drop)}")
    if args.cap > 0 and len(new) > args.cap:
        print(_cap_report(new, args.cap, len(args.drop)), file=sys.stderr)
        return 3
    return 0


def cmd_upsert(args: argparse.Namespace) -> int:
    path, plan_path = Path(args.checklist), Path(args.plan)
    plan = plan_path.name
    stages = [(int(n), name) for n, name in (s.split("\t", 1) for s in sys.stdin.read().splitlines() if s.strip())]
    title = cl.plan_title(plan_path.read_text(encoding="utf-8"), plan) if plan_path.is_file() else plan
    new, added = cl.upsert(_read(path), plan, title, stages)
    _write(path, new)
    print(f"added={added}")
    return 0


def cmd_flip(args: argparse.Namespace) -> int:
    path = Path(args.checklist)
    new, ok = cl.flip(_read(path), args.plan_basename, args.stage)
    if not ok:
        print(f"[checklist-v2] no block for {args.plan_basename} stage {args.stage}", file=sys.stderr)
        return 1
    _write(path, new)
    return 0


def cmd_extract(args: argparse.Namespace) -> int:
    lines = _read(Path(args.checklist))
    group = [b for b in cl.parse(lines)[0] if b.plan == args.plan_basename]
    if not group:
        return 1
    title, stages, extra = cl.merge(group)
    if not stages:
        return 1
    titles = _titles(args.plans_dir, {args.plan_basename})
    text = cl.render_block(args.plan_basename, title or titles.get(args.plan_basename) or args.plan_basename, stages, extra)
    print("\n".join(text))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ("plan", "apply", "upsert", "flip", "extract"):
        p = sub.add_parser(name)
        p.add_argument("--checklist", required=True)
        p.add_argument("--plans-dir", type=Path, default=None)
        if name == "apply":
            p.add_argument("--drop", action="append", default=[])
            p.add_argument("--cap", type=int, default=0)
        if name == "upsert":
            p.add_argument("--plan", required=True)
        if name in ("flip", "extract"):
            p.add_argument("--plan-basename", required=True)
        if name == "flip":
            p.add_argument("--stage", type=int, required=True)
    args = parser.parse_args(argv)
    return {"plan": cmd_plan, "apply": cmd_apply, "upsert": cmd_upsert, "flip": cmd_flip, "extract": cmd_extract}[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
