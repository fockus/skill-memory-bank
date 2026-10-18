#!/usr/bin/env python3
"""Normalize only OpenCode metadata after shared agent composition/model rendering."""

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

from opencode_models import assignments

spec = importlib.util.spec_from_file_location(
    "mb_agent_render", Path(__file__).resolve().parents[1] / "scripts/mb-agent-render.py"
)
assert spec and spec.loader
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)

COLORS = {"red": "#ef4444", "blue": "#3b82f6", "green": "#22c55e",
          "yellow": "#eab308", "purple": "#a855f7", "magenta": "#d946ef",
          "cyan": "#06b6d4", "orange": "#f97316"}
TOOLS = {"Bash": "bash", "Read": "read", "Grep": "grep", "Glob": "glob",
         "Edit": "edit", "Write": "edit", "WebFetch": "webfetch", "WebSearch": "websearch"}


def render(src: Path, skill_dir: Path, pipeline: Path | None = None) -> str:
    settings = assignments(pipeline) if pipeline else {}
    role = next((spec for spec in settings.values() if spec["agent"] == src.stem), {})
    text = shared.render(src, skill_dir, "opencode")
    parts = shared.split_frontmatter(text)
    if parts is None:
        return text
    frontmatter, body = parts
    lines: list[str] = []
    tools: list[str] = []
    for line in frontmatter:
        key, _, value = line.partition(":")
        value = value.strip().strip("\"'")
        if key == "tools":
            tools = [t.strip() for t in value.split(",") if t.strip()]
        elif key == "color":
            color = value if re.fullmatch(r"#[0-9a-fA-F]{6}", value) else COLORS.get(value, "#06b6d4")
            lines.append(f"color: {json.dumps(color)}")
        elif key not in {"name", "mode"}:
            lines.append(line)
    lines.append("mode: subagent")
    if role.get("native"):
        model, _, variant = role["native"].partition("#")
        # V2's Markdown compatibility reader drops a combined model#variant reference.
        lines.append(f"model: {model}")
        if variant:
            lines.append(f"variant: {json.dumps(variant)}")
    permissions = dict.fromkeys(TOOLS[t] for t in tools if t in TOOLS)
    if tools:
        lines.append("permission:")
        lines.extend(f"  {tool}: allow" for tool in permissions)
        if "edit" not in permissions:
            lines.append("  edit: deny")
    return "---\n" + "\n".join(lines) + "\n---\n" + body


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("src", type=Path)
    parser.add_argument("--skill-dir", type=Path, required=True)
    parser.add_argument("--pipeline", type=Path)
    args = parser.parse_args()
    try:
        sys.stdout.write(render(args.src, args.skill_dir, args.pipeline))
    except (OSError, ValueError) as exc:
        print(f"opencode-resources: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
