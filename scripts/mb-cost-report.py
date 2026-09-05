#!/usr/bin/env python3
"""Report Claude Code transcript cost per session / subagent role / work item.

Usage:
    mb-cost-report.py [--project <dir>] [--since N] [--json]

``--project`` defaults to this project's transcript store,
``~/.claude/projects/<cwd with '/' replaced by '-'>``. ``--json`` emits the
machine-readable report that the mb-work-cost-diet sprint gates diff against a
saved baseline; without it a plain text table is printed.

Parsing lives in ``memory_bank_skill/cost_report.py``; this file is argument
parsing and rendering only.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

try:
    from memory_bank_skill.cost_report import build_report
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill.cost_report import build_report

PROJECTS_ROOT = Path.home() / ".claude" / "projects"


def default_project_dir(cwd: Path | None = None) -> Path:
    """Map a working directory to its Claude Code transcript store."""
    cwd = (cwd or Path.cwd()).resolve()
    return PROJECTS_ROOT / str(cwd).replace("/", "-")


def _k(value: float) -> str:
    return f"{value / 1000:.1f}k" if value >= 1000 else f"{value:.0f}"


def render_table(report: dict[str, Any]) -> str:
    lines = [f"project: {report['project']}", ""]

    lines.append("sessions:")
    lines.append(
        "  {:<12} {:>6} {:>7} {:>6} {:>5} {:>9} {:>9} {:>7}".format(
            "session", "turns", "tools", "tasks", "subs", "out", "peak_ctx", "compact"
        )
    )
    for s in report["sessions"]:
        lines.append(
            "  {:<12} {:>6} {:>7} {:>6} {:>5} {:>9} {:>9} {:>7}".format(
                s["session"][:12],
                s["turns"],
                s["tool_calls"],
                s["tasks"],
                s.get("subagents", 0),
                _k(s["output_tokens"]),
                _k(s["peak_context"]),
                s["compactions"],
            )
        )

    lines += ["", "subagent roles:"]
    lines.append(
        "  {:<12} {:>4} {:>7} {:>7} {:>7} {:>9} {:>9} {:>8}".format(
            "role", "n", "turns", "tools", "tests", "out", "peak_ctx", "dur_min"
        )
    )
    for role, r in report["roles"].items():
        lines.append(
            "  {:<12} {:>4} {:>7.1f} {:>7.1f} {:>7.1f} {:>9} {:>9} {:>8.1f}".format(
                role,
                int(r["n"]),
                r["avg_turns"],
                r["avg_tool_calls"],
                r["avg_test_runs"],
                _k(r["avg_output_tokens"]),
                _k(r["avg_peak_context"]),
                r["avg_duration_min"],
            )
        )

    lines += ["", f"work items (init -> flip): {len(report['items'])}"]
    lines.append(
        "  {:<12} {:>8} {:>10} {:>6} {:>6} {:>7}".format(
            "session", "dur_min", "dispatches", "turns", "tests", "out"
        )
    )
    for item in report["items"]:
        lines.append(
            "  {:<12} {:>8.1f} {:>10} {:>6} {:>6} {:>7}".format(
                item["session"][:12],
                item["duration_min"],
                item["dispatches"],
                item["turns"],
                item["test_runs"],
                _k(item["output_tokens"]),
            )
        )
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mb-cost-report.py", description="Transcript cost report for /mb work sessions."
    )
    parser.add_argument(
        "--project", type=Path, default=None, help="transcript directory (default: cwd's store)"
    )
    parser.add_argument(
        "--since", type=int, default=None, metavar="N", help="only sessions newer than N days"
    )
    parser.add_argument("--json", action="store_true", help="emit JSON instead of a table")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    project = args.project or default_project_dir()
    if not project.is_dir():
        print(f"mb-cost-report: no transcript directory at {project}", file=sys.stderr)
        return 2

    report = build_report(project, since_days=args.since)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(render_table(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
