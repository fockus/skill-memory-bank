#!/usr/bin/env bash
# mb-work-diff.sh — baseline-scoped diff for a /mb work run (I-094 T3). Plan:
#   .memory-bank/plans/2026-07-04_fix_mb-work-parallel-runs.md (Stage 4)
#
# Usage:
#   mb-work-diff.sh --run-id <id> [--files "p1 p2 ..."] [--baseline <ref>]
#                    [--name-only] [--mb <path>]
#
# Today the verifier/judge is handed the bare working-tree `git diff`
# (commands/work.md:356); nothing scopes it to a run's own baseline or the
# item's files, so a co-running run's edits leak into the judged diff. This
# scopes the diff to the run's `baseline_ref` (recorded by
# `mb-work-state.sh init`, I-094 S1) instead:
#   - non-empty baseline → `git diff [--name-only] <baseline> [-- <files>]`
#   - empty baseline      → `git diff [--name-only] [-- <files>]` (working tree,
#                            still scoped to <files> when given)
#
# Single-arg form deliberately, NOT `<baseline>..HEAD`: /mb work only commits
# a stage at step 5g (`done`), so verify/review (5c/5d) run against a stage
# whose work is still uncommitted. `<baseline>..HEAD` is commit-to-commit and
# would show an empty diff for in-progress work; `git diff <baseline>` diffs
# the baseline commit against the working tree, which sees both commits made
# since baseline AND uncommitted edits (I-094 S4-fix).
#
# --baseline overrides the run's recorded baseline_ref (ad-hoc use / testing).
# --files is a single space-separated string of paths; omitted ⇒ the full
# baseline range across all paths.
#
# Fail-safe by design — exit 0 on any syntactically valid invocation against a
# real repo: git missing, cwd not a repo, or the baseline commit unreachable
# (e.g. rebased away) all degrade to empty stdout + a one-line stderr note. A
# missing/corrupt run state degrades to an empty baseline (working-tree
# fallback above), never a crash.
#
# Exit codes: 0 always on valid usage (fail-safe) · 2 usage error (no --run-id).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

usage() {
  sed -n '2,24p' "$0" >&2
}

RUN_ID=""
FILES_ARG=""
BASELINE_OVERRIDE=""
NAME_ONLY=0
MB_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="${2:-}"; shift 2 ;;
    --run-id=*) RUN_ID="${1#--run-id=}"; shift ;;
    --files) FILES_ARG="${2:-}"; shift 2 ;;
    --files=*) FILES_ARG="${1#--files=}"; shift ;;
    --baseline) BASELINE_OVERRIDE="${2:-}"; shift 2 ;;
    --baseline=*) BASELINE_OVERRIDE="${1#--baseline=}"; shift ;;
    --name-only) NAME_ONLY=1; shift ;;
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "[work-diff] unknown argument '$1'" >&2
      usage
      exit 2
      ;;
  esac
done

[ -z "$RUN_ID" ] && RUN_ID="${MB_WORK_RUN_ID:-}"
if [ -z "$RUN_ID" ]; then
  echo "[work-diff] --run-id required" >&2
  exit 2
fi

BANK=$(mb_resolve_path "$MB_ARG")

BASELINE="$BASELINE_OVERRIDE"
if [ -z "$BASELINE" ]; then
  STATE=$(mbw_state_slot "$BANK" "$RUN_ID")
  BASELINE=$(mbw_read_field "$STATE" "baseline_ref")
fi

# Fail-safe: no git binary at all → empty diff, never crash.
if ! command -v git >/dev/null 2>&1; then
  echo "[work-diff] git not available; degrading to empty diff" >&2
  exit 0
fi

# Fail-safe: cwd is not inside a git work tree → empty diff, never crash.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[work-diff] not inside a git repository; degrading to empty diff" >&2
  exit 0
fi

# Split the space-separated --files string into an indexed array (bash 3.2
# safe — no mapfile/declare -A). Word-splitting is intentional here.
FILES=()
if [ -n "$FILES_ARG" ]; then
  # shellcheck disable=SC2086
  for f in $FILES_ARG; do
    FILES+=("$f")
  done
fi

GIT_ARGS=(diff)
[ "$NAME_ONLY" = "1" ] && GIT_ARGS+=(--name-only)

if [ -n "$BASELINE" ]; then
  # Fail-safe: the recorded/override baseline is no longer reachable (e.g.
  # rebased away) → empty diff, never a raw git error surfaced to the caller.
  if ! git rev-parse --verify --quiet "${BASELINE}^{commit}" >/dev/null 2>&1; then
    echo "[work-diff] baseline '$BASELINE' unreachable; degrading to empty diff" >&2
    exit 0
  fi
  GIT_ARGS+=("${BASELINE}")
fi

if [ "${#FILES[@]}" -gt 0 ]; then
  GIT_ARGS+=(--)
  GIT_ARGS+=("${FILES[@]}")
fi

ERR_FILE=$(mktemp)
OUTPUT=""
if ! OUTPUT=$(git "${GIT_ARGS[@]}" 2>"$ERR_FILE"); then
  echo "[work-diff] git diff failed: $(cat "$ERR_FILE" 2>/dev/null)" >&2
  rm -f "$ERR_FILE"
  exit 0
fi
rm -f "$ERR_FILE"

if [ -n "$OUTPUT" ]; then
  printf '%s\n' "$OUTPUT"
fi
exit 0
