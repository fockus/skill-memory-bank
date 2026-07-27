#!/usr/bin/env bash
# mb-contract-gate.sh — execute the Contract-checkers registry of a spec
# (svp-contract-test-loop C3a; REQ-004/005/006/020/021).
#
# The registry is a fenced ```json Contract-checkers``` block in the body of the
# spec's `**Layer:** contract` task. Each entry names a checker, the argv that
# runs it, the ERE its genuine failure prints, and where its evidence is filed.
#
# Usage:
#   mb-contract-gate.sh red    --spec <spec-dir> [--mb <bank>] [--json]
#   mb-contract-gate.sh verify --spec <spec-dir> [--mb <bank>] [--json]
#   mb-contract-gate.sh --help
#
#   red     step 5 of the contract task. Every checker MUST fail, and fail for
#           the reason it declared: non-zero exit AND a match on `output_ere`.
#             exit 0 before the code exists → verdict=fake_red        (REQ-005)
#             failed, but output_ere missed → verdict=foreign_failure
#           Both are LOCAL hard stops (C7): the item stays open, the checkbox
#           is not flipped, and business implementation is not dispatched. They
#           are NOT routed into S5's complexity_escalation — that envelope
#           describes a task's difficulty, not a checker that proves nothing.
#
#   verify  the verify stage. Refuses to start unless EVERY checker has a
#           stored red evidence with verdict=pass whose cmd/cmd_sha256 is
#           byte-identical to the registry's current argv (CPR-A). Then every
#           checker must return 0; any other exit fails verification (REQ-021).
#
# argv is executed shell=false from the repo root, so registry text is never
# shell syntax; a caller who wants a shell writes ["bash","-lc","…"] explicitly.
#
# Output:
#   stdout  exactly one JSON object:
#           {"phase":…,"checkers":[{"id":…,"exit":…,"match":…,"verdict":…}],"verdict":…}
#   stderr  human diagnostics; SILENT under --json, so a machine caller reading
#           stderr as its error channel is not misled by an explanation.
#   Evidence per checker at its declared path, published temp-file + rename:
#   {version, topic, checker_id, phase, cmd, cmd_sha256, exit, output_match, verdict}
#
# Exit codes:
#   0 — gate passed
#   1 — contract failure (fake_red / foreign_failure / a red checker at verify)
#   2 — usage, missing or invalid registry, or a failed red-evidence gate;
#       in every exit-2 case NO checker is executed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

PHASE=""
SPEC=""
MB_ARG=""
JSON_FLAG=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      sed -n '2,47p' "$0"
      exit 0
      ;;
    --json) JSON_FLAG="--json" ;;
    --spec)
      [ $# -ge 2 ] || { echo "[contract-gate] --spec needs a value" >&2; exit 2; }
      SPEC="$2"; shift
      ;;
    --mb)
      [ $# -ge 2 ] || { echo "[contract-gate] --mb needs a value" >&2; exit 2; }
      MB_ARG="$2"; shift
      ;;
    -*)
      echo "[contract-gate] unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [ -z "$PHASE" ]; then
        PHASE="$1"
      else
        echo "[contract-gate] unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
  shift
done

case "$PHASE" in
  red|verify) ;;
  "")
    echo "Usage: mb-contract-gate.sh red|verify --spec <spec-dir> [--mb <bank>] [--json]" >&2
    exit 2
    ;;
  *)
    echo "[contract-gate] unknown phase: $PHASE (expected red|verify)" >&2
    exit 2
    ;;
esac

if [ -z "$SPEC" ]; then
  echo "[contract-gate] --spec <spec-dir> is required" >&2
  exit 2
fi

# The bank is resolved the same way every other command resolves it, so a
# local, global or legacy bank all reach the same evidence root.
MB_PATH=$(mb_resolve_path "$MB_ARG")
if [ -z "$MB_PATH" ] || [ ! -d "$MB_PATH" ]; then
  echo "[contract-gate] memory bank not found at: ${MB_PATH:-<unset>}" >&2
  exit 2
fi

exec python3 "$SCRIPT_DIR/mb_contract_gate.py" "$PHASE" \
  --spec "$SPEC" --mb "$MB_PATH" ${JSON_FLAG:+"$JSON_FLAG"}
