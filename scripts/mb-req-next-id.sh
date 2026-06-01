#!/usr/bin/env bash
# mb-req-next-id.sh — emit the next REQ-NNN identifier.
#
# Default (project-wide): scans the whole memory bank for any REQ-\d{3,}
# occurrences and prints `printf 'REQ-%03d\n' max+1`. Sources:
#   - `<mb>/specs/*/requirements.md`
#   - `<mb>/specs/*/design.md`
#   - `<mb>/context/*.md`
#
# With `--spec <name>` (per-spec-local numbering): scans ONLY that spec's own
# namespace and prints `max+1` within it. Sources:
#   - `<mb>/specs/<name>/requirements.md`
#   - `<mb>/specs/<name>/design.md`
#   - `<mb>/context/<name>.md`
# A brand-new spec (no files yet) therefore starts at `REQ-001`. This matches
# the per-spec-local REQ-ID convention: the same `REQ-NNN` may legitimately
# appear in different specs; traceability keys by `(spec, req_id)`. The
# `context/<name>.md` source keeps the `/mb discuss` → `/mb sdd` handoff on a
# single namespace (IDs minted while discussing carry into the spec).
#
# If no REQ-* identifier exists in the chosen scope, emits `REQ-001`. Numbering
# is monotonic within the scope — gaps in the existing sequence are NOT filled.
#
# Usage:
#   mb-req-next-id.sh [--spec <name>] [mb_path]
#   mb-req-next-id.sh --spec=<name> [mb_path]
#
# Exit codes:
#   0 — printed an ID to stdout
#   1 — `.memory-bank/` not found at resolved path
#   2 — usage error (unknown flag / missing --spec value)

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
mb-req-next-id.sh — emit the next REQ-NNN identifier.

Usage:
  mb-req-next-id.sh [--spec <name>] [mb_path]
  mb-req-next-id.sh --spec=<name> [mb_path]

Default (project-wide): max+1 across all specs + context.
--spec <name>:           per-spec-local — max+1 within
                         specs/<name>/{requirements,design}.md and
                         context/<name>.md only; a brand-new spec starts at
                         REQ-001.

Exit codes: 0 ok · 1 .memory-bank not found · 2 usage error
EOF
}

SPEC=""
MB_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)
      SPEC="${2:-}"
      [ -n "$SPEC" ] || { echo "[error] --spec requires a spec name" >&2; exit 2; }
      shift 2
      ;;
    --spec=*)
      SPEC="${1#--spec=}"
      [ -n "$SPEC" ] || { echo "[error] --spec requires a spec name" >&2; exit 2; }
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "[error] unknown flag: $1" >&2
      exit 2
      ;;
    *)
      MB_ARG="$1"
      shift
      ;;
  esac
done

MB_PATH=$(mb_resolve_path "$MB_ARG")

[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }

MB_PATH="$MB_PATH" REQ_SPEC="$SPEC" python3 - <<'PY'
import os
import re
from pathlib import Path

mb = Path(os.environ["MB_PATH"])
spec = os.environ.get("REQ_SPEC", "").strip()
pattern = re.compile(r"REQ-(\d{3,})")

candidates: list[Path] = []

if spec:
    # Per-spec-local scope: this spec's files + its same-named context file.
    spec_dir = mb / "specs" / spec
    for fname in ("requirements.md", "design.md"):
        f = spec_dir / fname
        if f.is_file():
            candidates.append(f)
    ctx = mb / "context" / f"{spec}.md"
    if ctx.is_file():
        candidates.append(ctx)
else:
    # Project-wide scope: every spec + every context file.
    specs_dir = mb / "specs"
    if specs_dir.is_dir():
        for spec_path in specs_dir.iterdir():
            if not spec_path.is_dir():
                continue
            for fname in ("requirements.md", "design.md"):
                f = spec_path / fname
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
