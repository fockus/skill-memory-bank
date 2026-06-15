#!/usr/bin/env bash
# mb-rules-check.sh — deterministic rules enforcement dispatcher.
#
# Usage:
#   mb-rules-check.sh --files <csv> [--diff-files <csv>] [--out json|human|both]
#                     [--srp-threshold <N>] [--profile <path>]
#
# Rules implemented:
#   - solid/srp
#   - clean_arch/direction
#   - tdd/delta
#   - stack.go.context-propagation
#   - stack.go.goroutine-context
#   - stack.python.type-hints
#   - stack.python.no-business-mocks
#   - stack.typescript.no-any
#   - stack.javascript.strict-equality
#   - architecture.fsd.import-direction

# shellcheck disable=SC1091,SC2034
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=mb_rules_check_lib.sh
source "$SCRIPT_DIR/mb_rules_check_lib.sh"
# shellcheck source=mb_rules_check_profile.sh
source "$SCRIPT_DIR/mb_rules_check_profile.sh"
# shellcheck source=mb_rules_check_baseline.sh
source "$SCRIPT_DIR/mb_rules_check_baseline.sh"
# shellcheck source=mb_rules_check_stack.sh
source "$SCRIPT_DIR/mb_rules_check_stack.sh"

FILES_CSV=""
DIFF_CSV=""
OUT="json"
SRP_THRESHOLD="${MB_SRP_THRESHOLD:-300}"
PROFILE_PATH="${MB_PROFILE:-}"
PLACEHOLDERS_ONLY=0

print_help() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files) FILES_CSV="${2:-}"; shift 2 ;;
    --diff-files) DIFF_CSV="${2:-}"; shift 2 ;;
    --out) OUT="${2:-json}"; shift 2 ;;
    --srp-threshold) SRP_THRESHOLD="${2:-300}"; shift 2 ;;
    --profile) PROFILE_PATH="${2:-}"; shift 2 ;;
    --placeholders-only) PLACEHOLDERS_ONLY=1; shift ;;
    --help|-h) print_help; exit 0 ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$OUT" in
  json|human|both) ;;
  *) printf 'invalid --out: %s (allowed: json|human|both)\n' "$OUT" >&2; exit 2 ;;
esac

START_MS="$(now_ms)"
VIOLATIONS=()
CHECKS_RUN=0
FILES=()
DIFF_FILES=()

split_csv "$FILES_CSV" FILES
split_csv "$DIFF_CSV" DIFF_FILES

# --placeholders-only: scan-only mode (§5 gate 3). Skip the structural/profile
# suite entirely; scan FILES[] for placeholder markers. Exit 1 on any hit.
if [[ "$PLACEHOLDERS_ONLY" -eq 1 ]]; then
  PLACEHOLDER_HITS=0
  scan_placeholders
  END_MS="$(now_ms)"
  DURATION=$((END_MS - START_MS))
  PROFILE_JSON='{"role":"backend","stack":"generic","architecture":"clean","delivery":"tdd","strictness":"block","sources":{},"prompt_summary":""}'
  case "$OUT" in
    json) emit_json ;;
    human) emit_human ;;
    both) emit_human; emit_json ;;
  esac
  [[ "$PLACEHOLDER_HITS" -gt 0 ]] && exit 1
  exit 0
fi

load_profile
PROFILE_STACK="$(profile_field stack)"
PROFILE_ARCH="$(profile_field architecture)"
PROFILE_STRICTNESS="$(profile_field strictness)"

check_srp
check_clean_arch
check_tdd_delta

case "$PROFILE_STACK" in
  go) check_stack_go ;;
  python) check_stack_python ;;
  typescript) check_stack_typescript ;;
  javascript) check_stack_javascript ;;
esac

case "$PROFILE_ARCH" in
  fsd) check_arch_fsd ;;
esac

END_MS="$(now_ms)"
DURATION=$((END_MS - START_MS))

EXIT_CODE=0
if [[ "$PROFILE_STRICTNESS" == "block" ]]; then
  for v in "${VIOLATIONS[@]+"${VIOLATIONS[@]}"}"; do
    if [[ "$v" == *'"severity":"CRITICAL"'* ]]; then
      EXIT_CODE=1
      break
    fi
  done
fi

case "$OUT" in
  json) emit_json ;;
  human) emit_human ;;
  both) emit_human; emit_json ;;
esac

exit "$EXIT_CODE"
