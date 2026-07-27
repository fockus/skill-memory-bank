#!/usr/bin/env bash
# mb-quality-dod.sh — render the one canonical `## Quality DoD` block (C5/C6).
#
# The orchestrator runs this ONCE per item and gives the resulting file to all
# three receivers: the implementer (`commands/work.md` §5a), the reviewer
# (`mb-review.sh --emit-payload --quality-dod <path>`) and the judge (§5e).
# One render, one set of bytes — the criterion is shared only if the sha256 is.
#
# Usage:
#   mb-quality-dod.sh --spec <spec-dir> [--mb <bank>]
#   mb-quality-dod.sh --rules-json <path>
#   mb-quality-dod.sh --help
#
#   --spec        resolve the rules for that spec first (validation mode of
#                 mb-rules-resolve.sh: every source declared in the spec's
#                 `## Quality DoD` section must exist).
#   --rules-json  render from an already-resolved JSON.
#
# A declared rule source that does not exist is a LOUD stop (exit 1, REQ-017),
# never a silent fall back to the bank's rules: a review judged against rules
# nobody selected is worse than a review that did not run.
#
# stdout — the markdown block, and nothing else.
# stderr — diagnostics.
#
# Exit codes:
#   0  block rendered
#   1  a declared rule source is missing, or the resolved JSON is unusable
#   2  usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

SPEC=""
RULES_JSON=""
MB_ARG=""

require_value() {
  [ "$#" -ge 2 ] || { echo "[quality-dod] $1 requires a value" >&2; exit 2; }
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --spec) require_value "$@"; SPEC="$2"; shift 2 ;;
    --rules-json) require_value "$@"; RULES_JSON="$2"; shift 2 ;;
    --mb) require_value "$@"; MB_ARG="$2"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "[quality-dod] unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$SPEC" ] && [ -n "$RULES_JSON" ]; then
  echo "[quality-dod] --spec and --rules-json are mutually exclusive" >&2
  exit 2
fi
if [ -z "$SPEC" ] && [ -z "$RULES_JSON" ]; then
  echo "Usage: mb-quality-dod.sh --spec <spec-dir> [--mb <bank>] | --rules-json <path>" >&2
  exit 2
fi

CLEANUP=""
# shellcheck disable=SC2064  # the path is fixed at trap time, on purpose
trap 'if [ -n "$CLEANUP" ]; then rm -f "$CLEANUP"; fi' EXIT

if [ -n "$SPEC" ]; then
  [ -d "$SPEC" ] || { echo "[quality-dod] spec directory not found: $SPEC" >&2; exit 2; }
  CLEANUP=$(mktemp -t mb-quality-dod.XXXXXX)
  RESOLVE_STATUS=0
  if [ -n "$MB_ARG" ]; then
    bash "$SCRIPT_DIR/mb-rules-resolve.sh" --spec "$SPEC" --mb "$MB_ARG" --json \
      >"$CLEANUP" || RESOLVE_STATUS=$?
  else
    bash "$SCRIPT_DIR/mb-rules-resolve.sh" --spec "$SPEC" --json >"$CLEANUP" || RESOLVE_STATUS=$?
  fi
  if [ "$RESOLVE_STATUS" -ne 0 ]; then
    # The resolver already named the missing path on stderr; propagate its
    # verdict rather than inventing a second one.
    exit "$RESOLVE_STATUS"
  fi
  RULES_JSON="$CLEANUP"
fi

[ -f "$RULES_JSON" ] || { echo "[quality-dod] rules JSON not found: $RULES_JSON" >&2; exit 2; }

# NOT `exec`: exec replaces this process, the EXIT trap never runs, and the
# temp file from --spec mode leaks on every call.
RENDER_STATUS=0
python3 "$SCRIPT_DIR/mb_quality_dod.py" --rules-json "$RULES_JSON" || RENDER_STATUS=$?
exit "$RENDER_STATUS"
