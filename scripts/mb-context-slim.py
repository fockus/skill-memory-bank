#!/usr/bin/env python3
"""mb-context-slim — trim agent prompt to active stage + DoD + REQs + git diff.

Reads the full agent prompt from stdin and emits a slim version on stdout
that includes only:

* the active stage block (between <!-- mb-stage:N --> markers in the plan)
* the DoD bullets from that stage
* the `covers_requirements` REQ list from the plan's frontmatter
* optional `git diff --staged` output (when --diff is passed)

If the plan does not contain a `<!-- mb-stage:N -->` marker for the requested
stage, the script falls back to echoing the input prompt unchanged
(zero-cost fallback so a slim mode never breaks a session).

Usage:
  mb-context-slim.py --plan <path> --stage <N> [--diff] [--mb <bank>]

Exit codes:
  0  success
  1  plan missing / stage out of range / usage error
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Trim agent prompt to active stage.")
    parser.add_argument("--plan", required=True, help="path to plan markdown")
    parser.add_argument("--stage", required=True, type=int, help="active stage number")
    parser.add_argument("--diff", action="store_true", help="include git diff --staged")
    parser.add_argument("--mb", default="", help="bank path (for diff --staged repo discovery)")
    args = parser.parse_args()

    plan_path = Path(args.plan)
    if not plan_path.is_file():
        print(f"[context-slim] plan not found: {plan_path}", file=sys.stderr)
        return 1

    full_prompt = sys.stdin.read()
    plan_text = plan_path.read_text(encoding="utf-8")

    # Frontmatter → covers_requirements
    fm_match = re.match(r"^---\n(.*?)\n---\n", plan_text, re.S)
    covers: list[str] = []
    if fm_match:
        cov_match = re.search(r"^covers_requirements:\s*\[([^\]]*)\]\s*$", fm_match.group(1), re.M)
        if cov_match:
            covers = [c.strip() for c in cov_match.group(1).split(",") if c.strip()]

    # Stage block extraction
    pattern = re.compile(
        rf"<!--\s*mb-stage:{args.stage}\s*-->\s*\n(##\s+Stage\s+{args.stage}[^\n]*)\n(.*?)(?=<!--\s*mb-stage:\d+\s*-->|\Z)",
        re.S,
    )
    m = pattern.search(plan_text)
    if not m:
        # Stage not present at all
        all_stages = sorted({int(s) for s in re.findall(r"<!--\s*mb-stage:(\d+)\s*-->", plan_text)})
        if not all_stages:
            # No stages — fallback to full prompt
            sys.stdout.write(full_prompt)
            return 0
        if args.stage not in all_stages:
            print(f"[context-slim] stage {args.stage} not in plan (have {all_stages})", file=sys.stderr)
            return 1
        # Defensive: marker present but pattern failed — emit full
        sys.stdout.write(full_prompt)
        return 0

    heading = m.group(1).strip()
    body = m.group(2).rstrip()

    # DoD lines = bullets with ✅ or ⬜
    dod = re.findall(r"^\s*-\s+[✅⬜][^\n]*", body, re.M)

    out: list[str] = []
    out.append(f"## Active stage: {args.stage}")
    out.append("")
    out.append(heading)
    out.append("")
    out.append(body)
    out.append("")
    if dod:
        out.append("## DoD requirements")
        out.append("")
        out.extend(dod)
        out.append("")
    if covers:
        out.append("## Covered requirements")
        out.append("")
        out.append(", ".join(covers))
        out.append("")
    if args.diff:
        out.append("## Git diff (staged)")
        out.append("")
        try:
            cwd = Path(args.mb).resolve().parent if args.mb else plan_path.resolve().parent.parent
            diff = subprocess.run(
                ["git", "-C", str(cwd), "diff", "--staged"],
                capture_output=True, text=True, check=False, timeout=10,
            )
            diff_out = diff.stdout.strip()
            out.append(diff_out if diff_out else "(no staged changes)")
        except Exception as exc:
            out.append(f"(diff unavailable: {exc})")
        out.append("")

    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
