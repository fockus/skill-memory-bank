#!/usr/bin/env python3
"""Pick the next active plan for `/mb work` with no target: plan status and depends_on decide.

Usage: mb_work_active.py <bank> <rel>...   (rels = the roadmap mb-active-plans links, in order)

A link is skipped when its plan's frontmatter says `status: paused|cancelled|done|blocked`, or a
`depends_on` entry is not closed (closed = in plans/done/, `status: done`, or every work item done;
an entry found nowhere stays open). A link without frontmatter (spec tasks.md) stays eligible.
Of the eligible links the only one wins; with several, the only `in_progress` one; otherwise none.
An absolute or `..` link is passed through unread — the resolver rejects it.

Exit: 0 pick printed · 1 nothing eligible · 2 several eligible (each case lists them on stderr).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mb_goal_evidence import plan_closed  # noqa: E402
from mb_work_plan_wrapper import fm_value, frontmatter  # noqa: E402

SKIP_STATUSES = ("paused", "cancelled", "done", "blocked")


def _fm(path: Path) -> str:
    try:
        return frontmatter(str(path)) or "" if path.is_file() else ""
    except (OSError, UnicodeDecodeError):
        return ""


def _closed(dep: str, bank: Path) -> bool:
    rel = dep if dep.startswith("plans/") else f"plans/{dep}"
    rel += "" if rel.endswith(".md") else ".md"
    if ".." in Path(rel).parts:
        return False
    if (bank / "plans" / "done" / Path(rel).name).is_file() or fm_value(
        _fm(bank / rel), "status"
    ) == "done":
        return True
    return plan_closed(rel, bank)[0]


def _deps(fm: str) -> list[str]:
    raw = str(fm_value(fm, "depends_on") or "").strip().strip("[]")
    return [d.strip().strip("\"'") for d in raw.split(",") if d.strip().strip("\"'")]


def select(bank: Path, rels: list[str]) -> dict:
    eligible, skipped = [], []
    for rel in rels:
        fm = "" if rel.startswith("/") or ".." in Path(rel).parts else _fm(bank / rel)
        status = fm_value(fm, "status")
        open_dep = next((d for d in _deps(fm) if not _closed(d, bank)), None)
        if status in SKIP_STATUSES:
            skipped.append((rel, f"status: {status}"))
        elif open_dep:
            skipped.append((rel, f"depends_on {open_dep} is not closed"))
        else:
            eligible.append((rel, status))
    active = [rel for rel, status in eligible if status == "in_progress"]
    pick = eligible[0][0] if len(eligible) == 1 else active[0] if len(active) == 1 else None
    return {"pick": pick, "eligible": eligible, "skipped": skipped}


def main(argv: list[str]) -> int:
    result = select(Path(argv[0]), argv[1:])
    for rel, reason in result["skipped"]:
        print(f"[work-resolve] skipped {rel} ({reason})", file=sys.stderr)
    if result["pick"]:
        print(result["pick"])
        return 0
    if not result["eligible"]:
        print(
            "[work-resolve] no eligible active plan (all paused, closed or waiting on depends_on)",
            file=sys.stderr,
        )
        return 1
    print("[work-resolve] multiple active plans (use explicit target):", file=sys.stderr)
    for rel, status in result["eligible"]:
        print(f"{rel}{f'  ({status})' if status else ''}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
