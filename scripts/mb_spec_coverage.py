#!/usr/bin/env python3
"""Whole-spec REQ coverage: every REQ of requirements.md with its text, covering tasks and naming tests.

Usage: mb_spec_coverage.py <spec-dir> [--tree D] [--json]

A task's `Covers:` line proves nothing about the code: a task can name REQ-028 and keep only part of its
text. This is the deterministic floor of plan-verifier's spec mode — per REQ:
  tested     a test file names the REQ (`REQ-028`, `test_..._req_028`), the verifier still reads it
  task-only  a task covers it, no test names it  → plan-verifier needs code + test evidence or CRITICAL
  uncovered  no task covers it
The REQ text is the bullet plus its indented continuation lines (acceptance criteria). REQ ids are per spec: an id
that a sibling spec also defines counts as tested only in a test file that names this spec's topic too
(`access:REQ-001`, or the word `access`).
Test files: `test_*`, `*_test.*`, `*.test.*`, `*.spec.*`, `*.bats`, or anything under a `tests`/`test`/
`__tests__` directory, under --tree (default: the spec's project root); hidden, vendor and node_modules
directories are skipped.

Exit: 0 every REQ tested · 1 a gap · 2 bad input (no requirements.md).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mb_req_id as rq  # noqa: E402
from mb_work_items import parse_work_items  # noqa: E402

TEST_NAME_RE = re.compile(r"^(test_.*|.*_test\.\w+|.*\.(test|spec)\.\w+|.*\.bats)$")
TEST_DIRS = {"tests", "test", "__tests__"}
SKIP_DIRS = {"node_modules", "vendor", "__pycache__"}
TEXT_SUFFIXES = {
    ".py",
    ".go",
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    ".rs",
    ".sh",
    ".bats",
    ".java",
    ".kt",
    ".rb",
    ".swift",
    ".cs",
    ".php",
}
MAX_BYTES = 1_000_000


def requirements(path: Path) -> dict[str, str]:
    reqs: dict[str, str] = {}
    current = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = rq.EARS_REQ_LINE_RE.match(line)
        if m:
            current = f"REQ-{m.group(1)}"
            reqs[current] = line.strip()
        elif current and line.startswith((" ", "\t")) and line.strip():
            reqs[current] += " " + line.strip()
        elif line.strip():  # a blank line keeps the REQ open for its indented acceptance criteria
            current = None
    return reqs


def covering_tasks(path: Path) -> dict[str, list[int]]:
    out: dict[str, list[int]] = {}
    for item in parse_work_items(path) if path.is_file() else []:
        for token in item.covers:
            req = rq.canon(token.split(":")[-1])
            out.setdefault(req, []).append(item.item_no)
    return out


def _is_test(rel: Path) -> bool:
    return bool(TEST_NAME_RE.match(rel.name)) or any(p in TEST_DIRS for p in rel.parts[:-1])


def test_refs(tree: Path, topic: str) -> dict[str, list[tuple[str, bool]]]:
    """REQ id → [(test file, whether the file names the spec topic)]."""
    out: dict[str, list[tuple[str, bool]]] = {}
    topic_re = re.compile(rf"(?<![\w-]){re.escape(topic)}(?![\w-])", re.I)
    for root, dirs, files in os.walk(tree):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS)
        for name in sorted(files):
            f = Path(root) / name
            rel = f.relative_to(tree)
            if f.suffix not in TEXT_SUFFIXES or not _is_test(rel) or f.stat().st_size > MAX_BYTES:
                continue
            text = f.read_text(encoding="utf-8", errors="ignore")
            for req in rq.find_test_ids(text):
                out.setdefault(rq.canon(req), []).append((rel.as_posix(), bool(topic_re.search(text))))
    return out


def shared_ids(spec: Path) -> set[str]:
    """REQ ids also defined by a sibling spec: REQ ids are per-spec, so a bare test reference is ambiguous."""
    ids: set[str] = set()
    for other in spec.parent.glob("*/requirements.md"):
        if other.parent != spec:
            ids |= set(requirements(other))
    return ids


def coverage(spec: Path, tree: Path) -> list[dict]:
    tasks, refs, ambiguous = covering_tasks(spec / "tasks.md"), test_refs(tree, spec.name), shared_ids(spec)
    tests = {req: [f for f, names_spec in found if names_spec or req not in ambiguous] for req, found in refs.items()}
    rows = []
    for req, text in requirements(spec / "requirements.md").items():
        status = "tested" if tests.get(req) else "task-only" if tasks.get(req) else "uncovered"
        rows.append(
            {
                "req": req,
                "status": status,
                "text": text,
                "tasks": tasks.get(req, []),
                "tests": tests.get(req, []),
            }
        )
    return rows


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="mb_spec_coverage.py")
    parser.add_argument("spec")
    parser.add_argument("--tree", default="")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    spec = Path(args.spec).resolve()
    if not (spec / "requirements.md").is_file():
        print(f"mb_spec_coverage: no requirements.md in {spec}", file=sys.stderr)
        return 2
    # <project>/.memory-bank/specs/<topic> → <project>
    tree = Path(args.tree).resolve() if args.tree else spec.parents[2]
    rows = coverage(spec, tree)
    if not rows:
        print(f"mb_spec_coverage: no `- **REQ-NNN**` bullet in {spec}/requirements.md", file=sys.stderr)
        return 2
    gaps = [r for r in rows if r["status"] != "tested"]
    if args.json:
        print(
            json.dumps(
                {"spec": str(spec), "tree": str(tree), "reqs": rows, "gaps": len(gaps)},
                ensure_ascii=False,
            )
        )
    else:
        for r in rows:
            where = (
                f" (task {', '.join(map(str, r['tasks']))})"
                if r["tasks"] and r["status"] != "tested"
                else ""
            )
            print(
                f"{r['req']} {r['status']}{where}"
                + (f" — {', '.join(r['tests'])}" if r["tests"] else "")
            )
        print(f"gaps: {len(gaps)} of {len(rows)}")
    return 1 if gaps else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
