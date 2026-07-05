#!/usr/bin/env bash
# mb-work-contract.sh — per-work-item sprint contract: create + read + validate
# (work-loop-v2 design.md §4 "Sprint contract — format and lifecycle"; REQ-110).
#
# A "sprint contract" is a small markdown file, written by the generator
# role-agent BEFORE implementation starts, that scope-locks one plan/spec work
# item: what it delivers, its test plan, its DoD checkpoints, and — just as
# important — what it explicitly does NOT deliver. `mb-reviewer` (review_mode:
# contract) reviews it before the implement phase begins (see agents/mb-reviewer.md).
#
# Path convention (design.md §4, SINGLE source of truth — always derive via
# the `path` subcommand, never recompute inline):
#   <bank>/contracts/<plan-topic>_stage-<N>.md
# `<plan-topic>` is derived from --plan: for a spec task list
# (".../specs/<topic>/tasks.md") it is <topic>; otherwise it is the plan's
# basename with extension and the conventional `YYYY-MM-DD_<type>_` prefix
# (scripts/mb-plan.sh's own naming scheme) stripped, then filesystem-
# sanitized via `mb_sanitize_topic` (scripts/_lib.sh).
#
# Usage:
#   mb-work-contract.sh create --mb <bank> --plan <path> --stage <N>
#                        [--role <role>] [--title <title>]
#   mb-work-contract.sh read   --mb <bank> --plan <path> --stage <N>
#   mb-work-contract.sh path   --mb <bank> --plan <path> --stage <N>
#   mb-work-contract.sh validate <contract-file>
#   mb-work-contract.sh --help
#
# `create` is idempotent: if the contract file already exists it is NEVER
# clobbered — the existing path is printed and the command exits 0 (a second
# `create` call for the same plan/stage is a safe no-op, not a re-scaffold).
# Callers that need to force a fresh contract must remove/archive the file
# themselves first (archival policy is an open question, design.md §12 — out
# of scope here).
#
# `validate` is the scope-lock check a reviewer/gate calls before trusting a
# contract: ALL of the frontmatter keys (plan, stage, item_id, generator_role,
# created, status, contract_version) AND ALL six body section headings (In
# scope, Plan of attack, Test plan, DoD checkpoints, Out of scope, Open risks)
# must be present. Missing pieces are reported by name; nothing here ever
# raises a stack trace — missing/corrupt input is always a clean, named,
# non-zero exit.
#
# Exit codes:
#   0  success (create/read/path/validate all pass)
#   1  not found / validation failed (missing frontmatter key or section)
#   2  usage error (missing subcommand/flags, bad input)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,40p' "$0" >&2
}

is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# $1=plan path -> echoes the sanitized plan-topic slug (design.md §4).
plan_topic() {
  local plan="$1"
  local base dir_name

  base=$(basename "$plan")
  if [ "$base" = "tasks.md" ]; then
    dir_name=$(basename "$(dirname "$plan")")
    mb_sanitize_topic "$dir_name"
    return 0
  fi

  base="${base%.*}"
  # Strip the conventional plans/ filename prefix mb-plan.sh writes:
  # YYYY-MM-DD_<type>_<topic>.md -> <topic>. Plans not following this
  # convention (or already bare topics) pass through unchanged.
  base=$(printf '%s' "$base" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}_(feature|fix|refactor|experiment)_//')
  mb_sanitize_topic "$base"
}

# $1=bank $2=plan $3=stage -> echoes the deterministic contract path.
contract_path() {
  local bank="$1" plan="$2" stage="$3" topic
  topic=$(plan_topic "$plan")
  printf '%s/contracts/%s_stage-%s.md\n' "$bank" "$topic" "$stage"
}

# Shared flag parser for create/read/path. Sets PARSED_MB, PARSED_PLAN,
# PARSED_STAGE, PARSED_ROLE, PARSED_TITLE (role/title only meaningful for
# `create`; harmless no-ops elsewhere).
parse_common_flags() {
  PARSED_MB=""
  PARSED_PLAN=""
  PARSED_STAGE=""
  PARSED_ROLE=""
  PARSED_TITLE=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) PARSED_MB="${2:-}"; shift 2 ;;
      --mb=*) PARSED_MB="${1#--mb=}"; shift ;;
      --plan) PARSED_PLAN="${2:-}"; shift 2 ;;
      --plan=*) PARSED_PLAN="${1#--plan=}"; shift ;;
      --stage) PARSED_STAGE="${2:-}"; shift 2 ;;
      --stage=*) PARSED_STAGE="${1#--stage=}"; shift ;;
      --role) PARSED_ROLE="${2:-}"; shift 2 ;;
      --role=*) PARSED_ROLE="${1#--role=}"; shift ;;
      --title) PARSED_TITLE="${2:-}"; shift 2 ;;
      --title=*) PARSED_TITLE="${1#--title=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[work-contract] unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  if [ -z "$PARSED_PLAN" ] || [ -z "$PARSED_STAGE" ]; then
    echo "[work-contract] --plan and --stage are required" >&2
    exit 2
  fi
  if ! is_uint "$PARSED_STAGE"; then
    echo "[work-contract] --stage must be a non-negative integer" >&2
    exit 2
  fi
}

# ── path ────────────────────────────────────────────────────────────────
cmd_path() {
  parse_common_flags "$@"
  local bank
  bank=$(mb_resolve_path "$PARSED_MB")
  contract_path "$bank" "$PARSED_PLAN" "$PARSED_STAGE"
}

# ── create ──────────────────────────────────────────────────────────────
cmd_create() {
  parse_common_flags "$@"
  local bank contract
  bank=$(mb_resolve_path "$PARSED_MB")
  contract=$(contract_path "$bank" "$PARSED_PLAN" "$PARSED_STAGE")

  # Idempotent: never clobber an existing contract.
  if [ -f "$contract" ]; then
    printf '%s\n' "$contract"
    return 0
  fi

  mkdir -p "$(dirname "$contract")"

  local role="$PARSED_ROLE"
  [ -n "$role" ] || role="unassigned"

  local topic title created tmp
  topic=$(plan_topic "$PARSED_PLAN")
  title="$PARSED_TITLE"
  [ -n "$title" ] || title="$topic stage $PARSED_STAGE"
  created=$(date -u +%FT%TZ)

  tmp=$(mktemp)
  PLAN="$PARSED_PLAN" STAGE="$PARSED_STAGE" ROLE="$role" TITLE="$title" \
    CREATED="$created" TMP_FILE="$tmp" python3 - <<'PY'
import os

template = """---
plan: {plan}
stage: {stage}
item_id: stage-{stage}
generator_role: {role}
created: {created}
status: draft
contract_version: 1
---

# Contract: {title}

## In scope (what THIS item delivers)
-

## Plan of attack (ordered, mechanical)
1.

## Test plan
- Unit:
- Integration:
- E2E (if applicable):

## DoD checkpoints (echoes plan, with how-to-verify)
- [ ]

## Out of scope (explicit non-deliverables)
-

## Open risks (acknowledged at contract time)
-
"""

content = template.format(
    plan=os.environ["PLAN"],
    stage=os.environ["STAGE"],
    role=os.environ["ROLE"],
    created=os.environ["CREATED"],
    title=os.environ["TITLE"],
)
with open(os.environ["TMP_FILE"], "w", encoding="utf-8") as fh:
    fh.write(content)
PY
  mv "$tmp" "$contract"
  printf '%s\n' "$contract"
}

# ── read ────────────────────────────────────────────────────────────────
cmd_read() {
  parse_common_flags "$@"
  local bank contract
  bank=$(mb_resolve_path "$PARSED_MB")
  contract=$(contract_path "$bank" "$PARSED_PLAN" "$PARSED_STAGE")

  if [ ! -f "$contract" ]; then
    echo "[work-contract] no contract at $contract; run 'create' first" >&2
    exit 1
  fi
  cat "$contract"
}

# ── validate ────────────────────────────────────────────────────────────
# $1 = contract file. Fails closed on missing/unreadable input; reports every
# missing frontmatter key / section by name (not just the first one) so a
# caller can fix everything in one pass.
cmd_validate() {
  local file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *)
        if [ -z "$file" ]; then file="$1";
        else echo "[work-contract] validate: unexpected extra arg '$1'" >&2; exit 2;
        fi
        shift ;;
    esac
  done
  if [ -z "$file" ]; then
    echo "[work-contract] validate <contract-file> required" >&2
    exit 2
  fi
  if [ ! -f "$file" ]; then
    echo "[work-contract] validate FAILED: file not found: $file" >&2
    exit 1
  fi

  local content
  if ! content=$(cat "$file" 2>/dev/null); then
    echo "[work-contract] validate FAILED: unable to read $file" >&2
    exit 1
  fi

  local missing=0 key

  for key in plan stage item_id generator_role created status contract_version; do
    if ! printf '%s\n' "$content" | grep -qE "^${key}:"; then
      echo "[work-contract] validate FAILED: missing frontmatter key '$key' in $file" >&2
      missing=1
    fi
  done

  # Body sections, in design.md §4 order. Each entry: "<heading-regex>|<label>".
  local checks="^## In scope|in-scope
^## Plan of attack|plan-of-attack
^## Test plan|test-plan
^## DoD checkpoints|dod-checkpoints
^## Out of scope|out-of-scope
^## Open risks|open-risks"

  local line regex label
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    regex="${line%%|*}"
    label="${line##*|}"
    if ! printf '%s\n' "$content" | grep -qE "$regex"; then
      echo "[work-contract] validate FAILED: missing section '$label' in $file" >&2
      missing=1
    fi
  done <<EOF
$checks
EOF

  if ! printf '%s\n' "$content" | grep -qE '^# Contract:'; then
    echo "[work-contract] validate FAILED: missing title heading '# Contract: <title>' in $file" >&2
    missing=1
  fi

  if [ "$missing" -ne 0 ]; then
    exit 1
  fi

  echo "[work-contract] validate OK: $file"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
    exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    create) shift; cmd_create "$@" ;;
    read) shift; cmd_read "$@" ;;
    path) shift; cmd_path "$@" ;;
    validate) shift; cmd_validate "$@" ;;
    *) echo "[work-contract] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
