#!/usr/bin/env bash
# mb-bank-lint.sh — read-only lint of roadmap inputs and backlog.md (design.md C5).
#
# Usage:
#   mb-bank-lint.sh <roadmap|backlog|all> [--mb PATH]
#
# One line per finding, sorted by file, line, code:
#   severity=<warning|error> code=<code> file=<JSON> line=<int> detail=<JSON>
# Warnings: no_ice ice_unconfirmed orphan_group duplicate_pin legacy_state.
# Errors: invalid_ice invalid_ice_confirmed invalid_pin invalid_group
# invalid_blocked_by progress_mismatch invalid_state ready_without_brief
# wontfix_without_reason parent_cycle duplicate_id. Legacy (pre-migration) entries without any
# v2 meta line are grandfathered for ready_without_brief / wontfix_without_reason.
#
# Exit: 0 no errors, 1 at least one error, 2 invalid invocation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

SCOPE=""
MB_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    --mb) [ "$#" -ge 2 ] || { echo "[error] --mb requires a path" >&2; exit 2; }; MB_ARG="$2"; shift 2 ;;
    roadmap|backlog|all) [ -z "$SCOPE" ] || { echo "[error] only one section allowed" >&2; exit 2; }; SCOPE="$1"; shift ;;
    *) echo "[error] unknown argument: $1 (expected roadmap|backlog|all [--mb PATH])" >&2; exit 2 ;;
  esac
done
[ -n "$SCOPE" ] || { echo "Usage: mb-bank-lint.sh <roadmap|backlog|all> [--mb PATH]" >&2; exit 2; }

MB_PATH=$(mb_resolve_path "$MB_ARG")
[ -d "$MB_PATH" ] || { echo "[error] bank not found: $MB_PATH" >&2; exit 2; }

exec "${MB_PYTHON:-python3}" "$SCRIPT_DIR/mb_bank_lint.py" "$SCOPE" "$MB_PATH"
