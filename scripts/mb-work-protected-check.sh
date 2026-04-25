#!/usr/bin/env bash
# mb-work-protected-check.sh — match files against pipeline.yaml:protected_paths.
#
# Usage:
#   mb-work-protected-check.sh <file> [<file> ...] [--mb <path>]
#
# Exit codes:
#   0  no file matches any protected glob
#   1  at least one file matches (matches reported on stderr)
#   2  usage / config error

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

MB_ARG=""
files=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    -h|--help) sed -n '2,12p' "$0" >&2; exit 0 ;;
    *) files+=("$1"); shift ;;
  esac
done

if [ "${#files[@]}" -eq 0 ]; then
  exit 0
fi

PIPELINE_PATH=$(bash "$PIPELINE" path "$MB_ARG" 2>/dev/null || true)
if [ -z "$PIPELINE_PATH" ]; then
  PIPELINE_PATH="$SCRIPT_DIR/../references/pipeline.default.yaml"
fi

PIPELINE_YAML="$PIPELINE_PATH" python3 - "${files[@]}" <<'PY'
import os
import re
import sys

try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    globs = cfg.get("protected_paths") or []
    if not isinstance(globs, list):
        sys.stderr.write("[protected] protected_paths must be a list\n")
        sys.exit(2)
except Exception as exc:
    sys.stderr.write(f"[protected] failed to load pipeline.yaml: {exc}\n")
    sys.exit(2)

# Convert each glob to a regex.
# Rules: `**` → match any path segments (including separators);
#        `*`  → match any character except `/`;
#        `?`  → match a single char except `/`.
def glob_to_regex(g: str) -> re.Pattern:
    out = ["^"]
    i = 0
    while i < len(g):
        c = g[i]
        if c == "*":
            if i + 1 < len(g) and g[i + 1] == "*":
                # `**` — match any number of path segments
                out.append(".*")
                i += 2
                if i < len(g) and g[i] == "/":
                    i += 1  # consume trailing slash; .* covers it
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c in r".\+()|^$[]{}":
            out.append("\\" + c)
        else:
            out.append(c)
        i += 1
    out.append("$")
    return re.compile("".join(out))

regexes = [(g, glob_to_regex(g)) for g in globs]

matched = []
files = sys.argv[1:]
for f in files:
    if not f:
        continue
    for g, rx in regexes:
        if rx.match(f) or rx.match(os.path.basename(f)):
            matched.append((f, g))
            break

if matched:
    for f, g in matched:
        sys.stderr.write(f"[protected] {f} matches {g}\n")
    sys.exit(1)

sys.exit(0)
PY
