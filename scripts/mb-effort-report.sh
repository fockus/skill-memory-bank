#!/usr/bin/env bash
# mb-effort-report.sh — effort metrics of real tasks from Claude Code transcripts
# and, optionally, the task's git range (proportional-effort Sprint 2, Stage 4).
#
# Usage:
#   mb-effort-report.sh [--json] [--repo <dir>] [--since <ref> [--until <ref>]] <session.jsonl>…
#
# Per session and in total:
#   tokens   input / output / cache-write / cache-read, summed over assistant
#            `message.usage`. Claude Code writes one API message as several
#            entries (thinking, text, each tool_use) that repeat the same usage,
#            so usage is counted once per `message.id`.
#   subagents  `<dir>/<session>/subagents/*.jsonl` next to the session file are
#            folded into the session (tokens, turns, tool calls, test runs).
#   duration first → last timestamp over the session and its subagents (minutes);
#            active_min sums only gaps ≤ 10 min, so a resumed session's idle
#            nights do not count.
#   written  test_cases_written = test cases added by Write content and by the
#            Edit/MultiEdit new_string − old_string delta; docs_touched = distinct
#            `*.md` paths outside `.memory-bank/` written or edited. Works when the
#            task's repo is not available (e.g. another VCS).
#   turns    assistant API messages; tool_calls = tool_use blocks;
#            dispatches = Task/Agent tool calls.
#   test_runs  Bash calls that invoke a test runner; full_suite_runs = those
#            without a file / `::` / -k / --files / --changed-since target.
# Git range (--since, --until defaults to HEAD; --repo defaults to cwd):
#   test files added, test cases added (`def test_`, `@test`, `func Test`,
#   `it(`/`test(`, `#[test]` in added lines), docs added/changed (`*.md` outside
#   `.memory-bank/`), doc lines, README/CHANGELOG lines, code lines changed
#   (added + deleted, non-.md files outside `.memory-bank/`).
#
# Read-only: reads the given files and runs `git diff`; no network, no telemetry.
# Exit codes: 0 ok; 2 usage error / missing transcript / bad git range.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

exec "${MB_PYTHON:-python3}" - "$SCRIPT_DIR" "$@" <<'PY'
import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]).resolve().parent))
from memory_bank_skill.cost_report import iter_records  # noqa: E402

# A runner counts only at command position of a shell segment (after env assignments
# and wrappers like `timeout 60`, `uv run`, `python -m`, `bash`, a path prefix), so
# `pgrep pytest` or a heredoc line that mentions a runner is not a run.
SEGMENT_SPLIT_RE = re.compile(r"&&|\|\||[;|\n]|\$\(")
TEST_RUNNER_RE = re.compile(
    r"^[\s(]*(?:\w+=\S*\s+)*"
    r"(?:(?:timeout\s+\d+\w?|uv\s+run(?:\s+-q)?|poetry\s+run|npx|pnpm\s+exec|bash|sh"
    r"|\S*python[\d.]*\s+-m)\s+)*(?:\S*/)?"
    r"(pytest|bats|go\s+test|cargo\s+test|vitest|jest|mb-test-run\.sh|make\s+test"
    r"|(?:npm|pnpm|yarn)(?:\s+run)?\s+test|ya\s+make\s+-t)(?=\s|$)"
)
# ponytail: one Bash call = one run; `pytest a.py && bats tests/` is one (full) run.
TARGETED_RE = re.compile(
    r"::|\s-k\s|\s-run\s|--filter|--files|--changed-since"
    r"|\S+\.(py|bats|go|ts|tsx|js|jsx|rs|swift|kt)\b"
)
TEST_FILE_RE = re.compile(
    r"(^|/)(test_[^/]*\.py|[^/]*_test\.(py|go)|[^/]*\.bats|[^/]*\.(test|spec)\.[^/]+"
    r"|[^/]*Tests?\.(swift|kt|java))$"
)
TEST_CASE_RE = re.compile(
    r"^\s*((async\s+)?def\s+test_\w*\s*\(|@test\s|func\s+Test\w*\(|(it|test)\s*\(|#\[test\])",
    re.M,
)
IDLE_GAP_SEC = 600
README_RE = re.compile(r"(^|/)(README|CHANGELOG)[^/]*$", re.I)
SESSION_KEYS = (
    "input_tokens", "output_tokens", "cache_creation_tokens", "cache_read_tokens",
    "total_tokens", "duration_min", "active_min", "turns", "tool_calls", "dispatches", "subagents",
    "test_runs", "full_suite_runs", "test_cases_written", "docs_touched",
)


def _moment(record):
    raw = record.get("timestamp")
    if not isinstance(raw, str):
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _test_cases(text):
    return len(TEST_CASE_RE.findall(str(text or "")))


def _written(name, args, acc, docs):
    path = str(args.get("file_path") or "")
    if path.endswith(".md") and "/.memory-bank/" not in f"/{path}":
        docs.add(path)
    if name == "Write":
        acc["test_cases_written"] += _test_cases(args.get("content"))
        return
    edits = args.get("edits") if name == "MultiEdit" else [args]
    for edit in edits if isinstance(edits, list) else []:
        if isinstance(edit, dict):
            delta = _test_cases(edit.get("new_string")) - _test_cases(edit.get("old_string"))
            acc["test_cases_written"] += max(delta, 0)


def _fold(path, acc, moments, docs):
    usage_by_msg = {}
    for record in iter_records(path):
        moment = _moment(record)
        if moment:
            moments.append(moment)
        if record.get("type") != "assistant":
            continue
        message = record.get("message") or {}
        key = message.get("id") or f"_anon{len(usage_by_msg)}"
        usage_by_msg[key] = message.get("usage") or {}
        content = message.get("content")
        for block in content if isinstance(content, list) else []:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            acc["tool_calls"] += 1
            name = block.get("name")
            if name in ("Task", "Agent"):
                acc["dispatches"] += 1
            elif name in ("Write", "Edit", "MultiEdit"):
                _written(name, block.get("input") or {}, acc, docs)
            elif name == "Bash":
                command = str((block.get("input") or {}).get("command") or "")
                runs = [
                    seg for seg in SEGMENT_SPLIT_RE.split(command) if TEST_RUNNER_RE.match(seg)
                ]
                if runs:
                    acc["test_runs"] += 1
                    if any(not TARGETED_RE.search(seg) for seg in runs):
                        acc["full_suite_runs"] += 1
    for usage in usage_by_msg.values():
        acc["turns"] += 1
        acc["input_tokens"] += int(usage.get("input_tokens") or 0)
        acc["output_tokens"] += int(usage.get("output_tokens") or 0)
        acc["cache_creation_tokens"] += int(usage.get("cache_creation_input_tokens") or 0)
        acc["cache_read_tokens"] += int(usage.get("cache_read_input_tokens") or 0)


def session_report(path):
    acc = dict.fromkeys(SESSION_KEYS, 0)
    moments = []
    docs = set()
    _fold(path, acc, moments, docs)
    subs = sorted((path.parent / path.stem / "subagents").glob("*.jsonl"))
    acc["subagents"] = len(subs)
    for sub in subs:
        _fold(sub, acc, moments, docs)
    acc["docs_touched"] = len(docs)
    acc["total_tokens"] = sum(
        acc[k] for k in ("input_tokens", "output_tokens", "cache_creation_tokens", "cache_read_tokens")
    )
    start, end = (min(moments), max(moments)) if moments else (None, None)
    acc["duration_min"] = round((end - start).total_seconds() / 60, 2) if moments else 0
    moments.sort()
    gaps = ((b - a).total_seconds() for a, b in zip(moments, moments[1:], strict=False))
    acc["active_min"] = round(sum(g for g in gaps if g <= IDLE_GAP_SEC) / 60, 2)
    return {
        "session": path.stem,
        "path": str(path),
        "started_at": start.isoformat() if start else None,
        "ended_at": end.isoformat() if end else None,
        **acc,
    }


def _git(repo, *args):
    proc = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"mb-effort-report: git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def _is_doc(path):
    return path.endswith(".md")


def git_report(repo, since, until):
    rng = (since, until)
    out = {
        "range": f"{since}..{until}", "files_changed": 0, "code_lines_changed": 0,
        "test_files_added": 0, "test_cases_added": 0, "docs_added": 0, "docs_changed": 0,
        "docs_lines_changed": 0, "readme_changelog_lines": 0,
    }
    for line in _git(repo, "diff", "--no-renames", "--numstat", *rng).splitlines():
        added, deleted, path = line.split("\t", 2)
        out["files_changed"] += 1
        if path.startswith(".memory-bank/") or added == "-":
            continue
        lines = int(added) + int(deleted)
        if _is_doc(path):
            out["docs_lines_changed"] += lines
        else:
            out["code_lines_changed"] += lines
        if README_RE.search(path):
            out["readme_changelog_lines"] += lines
    for line in _git(repo, "diff", "--no-renames", "--name-status", *rng).splitlines():
        status, path = line.split("\t", 1)
        if path.startswith(".memory-bank/"):
            continue
        if status == "A" and TEST_FILE_RE.search(path):
            out["test_files_added"] += 1
        if _is_doc(path) and status in ("A", "M"):
            out["docs_added" if status == "A" else "docs_changed"] += 1
    current = ""
    for line in _git(repo, "diff", "--no-renames", "-U0", *rng).splitlines():
        if line.startswith("+++ "):
            current = line[6:] if line.startswith("+++ b/") else ""
        elif (
            line.startswith("+")
            and not current.startswith(".memory-bank/")
            and TEST_CASE_RE.match(line[1:])
        ):
            out["test_cases_added"] += 1
    return out


def render(report):
    cols = ("session", "dur_min", "act_min", "turns", "tools", "subs", "disp", "tests",
            "full", "tcases", "docs", "input", "output", "cache_w", "cache_r", "total")
    keys = ("duration_min", "active_min", "turns", "tool_calls", "subagents", "dispatches",
            "test_runs", "full_suite_runs", "test_cases_written", "docs_touched", "input_tokens", "output_tokens", "cache_creation_tokens",
            "cache_read_tokens", "total_tokens")
    fmt = "{:<14}" + " {:>8}" * len(keys)
    lines = [fmt.format(*cols)]
    for row in [*report["sessions"], {"session": "TOTAL", **report["total"]}]:
        lines.append(fmt.format(row["session"][:14], *(row[k] for k in keys)))
    git = report["git"]
    if git:
        lines += [
            "",
            f"git {git['range']}: {git['files_changed']} files, code lines ±{git['code_lines_changed']}",
            f"  tests +{git['test_files_added']} files / +{git['test_cases_added']} cases",
            f"  docs +{git['docs_added']} new / {git['docs_changed']} changed"
            f" ({git['docs_lines_changed']} lines; README/CHANGELOG {git['readme_changelog_lines']})",
        ]
    return "\n".join(lines)


def main(argv):
    parser = argparse.ArgumentParser(prog="mb-effort-report.sh")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--since")
    parser.add_argument("--until")
    parser.add_argument("sessions", nargs="+", type=Path)
    args = parser.parse_args(argv)
    if args.until and not args.since:
        parser.error("--until requires --since")
    for path in args.sessions:
        if not path.is_file():
            parser.error(f"transcript not found: {path}")
    sessions = [session_report(p) for p in args.sessions]
    total = {k: round(sum(s[k] for s in sessions), 2) for k in SESSION_KEYS}
    git = git_report(args.repo, args.since, args.until or "HEAD") if args.since else None
    report = {"sessions": sessions, "total": total, "git": git}
    print(json.dumps(report, indent=2) if args.json else render(report))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[2:]))
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(exc.code, file=sys.stderr)
            sys.exit(2)
        raise
PY
