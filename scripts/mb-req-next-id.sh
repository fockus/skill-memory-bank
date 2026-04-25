#!/usr/bin/env bash
# mb-req-next-id.sh — emit the next monotonic REQ-NNN identifier.
#
# Scans the memory bank for any REQ-\d{3,} occurrences and prints
# `printf 'REQ-%03d\n' max+1`. Sources:
#   - `<mb>/specs/*/requirements.md`
#   - `<mb>/specs/*/design.md`
#   - `<mb>/context/*.md`
#
# If no REQ-* identifier exists yet, emits `REQ-001`. Numbering is
# project-wide monotonic — gaps in the existing sequence are NOT filled.
#
# Usage:
#   mb-req-next-id.sh [mb_path]
#
# Exit codes:
#   0 — printed an ID to stdout
#   1 — `.memory-bank/` not found at resolved path

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MB_PATH=$(mb_resolve_path "${1:-}")

[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }

MB_PATH="$MB_PATH" python3 - <<'PY'
import os
import re
from pathlib import Path

mb = Path(os.environ["MB_PATH"])
pattern = re.compile(r"REQ-(\d{3,})")

candidates: list[Path] = []
specs_dir = mb / "specs"
if specs_dir.is_dir():
    for spec in specs_dir.iterdir():
        if not spec.is_dir():
            continue
        for fname in ("requirements.md", "design.md"):
            f = spec / fname
            if f.is_file():
                candidates.append(f)

context_dir = mb / "context"
if context_dir.is_dir():
    candidates.extend(p for p in context_dir.glob("*.md") if p.is_file())

max_id = 0
for path in candidates:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        continue
    for m in pattern.finditer(text):
        n = int(m.group(1))
        if n > max_id:
            max_id = n

print(f"REQ-{max_id + 1:03d}")
PY
