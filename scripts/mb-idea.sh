#!/usr/bin/env bash
# mb-idea.sh — capture a new idea in backlog.md with monotonic I-NNN.
#
# Usage:
#   mb-idea.sh [--force] [--] <title> [priority] [mb_path]
#     priority ∈ HIGH|MED|LOW (default MED), case-insensitive.
#     --force  (first argument only) bypasses ONLY the out-of-scope similarity
#              refusal; title idempotency and priority validation still apply.
#     --       ends option parsing (title may start with dashes).
#     Any other first argument starting with `--` → exit 2 before any mutation.
#
# Effect: append `### I-NNN — <title> [PRIORITY, NEW, YYYY-MM-DD]` plus a
# `**Type:** IDEA` line to the `## Ideas` section of backlog.md. Idempotent by
# title. The title `[SPEC:<group>] <child-topic>` registers a SPEC entry
# (Type/Group/Parent/Spec meta lines, prefix stripped) and skips similarity.
# The whole read → decide → write path runs under <bank>/.locks/backlog.lock;
# the id comes from mb_next_backlog_id (the single allocator).
#
# Exit: 0 OK, 1 missing backlog.md / lock timeout / similar out-of-scope entry,
# 2 invalid priority or usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
  shift
fi
if [ "${1:-}" = "--" ]; then
  shift
else
  case "${1:-}" in
    --*) echo "[error] unknown option: $1 (usage: mb-idea.sh [--force] [--] <title> [priority] [mb_path])" >&2; exit 2 ;;
  esac
fi

TITLE="${1:?Usage: mb-idea.sh [--force] [--] <title> [priority] [mb_path]}"
PRIO_RAW="${2:-}"
MB_PATH=$(mb_resolve_path "${3:-}")

BACKLOG="$MB_PATH/backlog.md"
[ -f "$BACKLOG" ] || { echo "[error] backlog.md not found: $BACKLOG" >&2; exit 1; }

# Normalize priority
if [ -z "$PRIO_RAW" ]; then
  PRIO="MED"
else
  PRIO=$(printf '%s' "$PRIO_RAW" | tr '[:lower:]' '[:upper:]')
fi
case "$PRIO" in
  HIGH|MED|LOW) ;;
  *) echo "[error] Invalid priority: $PRIO_RAW (expected HIGH|MED|LOW)" >&2; exit 2 ;;
esac

# Typed SPEC registration (C4): exact grammar or usage error BEFORE any lock/alloc.
SPEC_GROUP="" SPEC_TOPIC="" STORED_TITLE="$TITLE"
case "$TITLE" in
  "[SPEC:"*)
    if [[ "$TITLE" =~ ^\[SPEC:([a-z0-9][a-z0-9-]*)\]\ ([a-z0-9][a-z0-9-]*)$ ]]; then
      SPEC_GROUP="${BASH_REMATCH[1]}"
      SPEC_TOPIC="${BASH_REMATCH[2]}"
      STORED_TITLE="$SPEC_TOPIC"
    else
      echo "[error] malformed SPEC title: $TITLE (expected '[SPEC:<group>] <child-topic>', slugs [a-z0-9][a-z0-9-]*)" >&2
      exit 2
    fi
    ;;
esac

LOCK_DIR="$MB_PATH/.locks/backlog.lock"
mkdir -p "$MB_PATH/.locks"
if ! LOCK_TOKEN="$(mb_lock_acquire "$LOCK_DIR" "${MB_BACKLOG_LOCK_TIMEOUT:-10}" "${MB_BACKLOG_LOCK_TTL:-120}")"; then
  echo "[error] could not acquire backlog lock: $LOCK_DIR" >&2
  exit 1
fi
tmp=""
cleanup() {
  [ -n "$tmp" ] && rm -f "$tmp"
  mb_lock_release "$LOCK_DIR" "$LOCK_TOKEN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# existing_id <title> — id of the entry whose title equals <title> exactly
# (literal matching: regex metacharacters in a title must not misfire).
existing_id() {
  awk -v t=" — $1" '
    /^### I-[0-9]{3} — / {
      idx = index($0, t)
      if (idx == 0) next
      tail = substr($0, idx + length(t), 1)
      # Accept only when t is followed by space, "[", or end-of-line — avoids
      # matching a substring of a longer title.
      if (tail == "" || tail == " " || tail == "[") {
        match($0, /I-[0-9]{3}/)
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$BACKLOG"
}

# Idempotency (re-checked under the lock): the stored title, and for a SPEC the
# legacy prefixed form written before the typed writer existed.
id=$(existing_id "$STORED_TITLE")
if [ -z "$id" ] && [ -n "$SPEC_GROUP" ]; then
  id=$(existing_id "$TITLE")
fi
if [ -n "$id" ]; then
  echo "[idea] already present: $id — $TITLE" >&2
  printf '%s\n' "$id"
  exit 0
fi

# Similarity hook — IDEA entries only; --force bypasses it, nothing else does.
if [ -z "$SPEC_GROUP" ] && [ "$FORCE" -eq 0 ]; then
  sim=$("${MB_PYTHON:-python3}" "$SCRIPT_DIR/mb_backlog_similar.py" "$BACKLOG" "$TITLE") || exit $?
  if [ -n "$sim" ]; then
    echo "similar_out_of_scope=${sim% *} score=${sim#* }" >&2
    exit 1
  fi
fi

ID=$(mb_next_backlog_id "$MB_PATH") || exit 1
TODAY=$(date +%Y-%m-%d)
ENTRY="### ${ID} — ${STORED_TITLE} [${PRIO}, NEW, ${TODAY}]"
if [ -n "$SPEC_GROUP" ]; then
  ENTRY="${ENTRY}
**Type:** SPEC
**Group:** ${SPEC_GROUP}
**Parent:** none
**Spec:** ${SPEC_TOPIC}"
else
  ENTRY="${ENTRY}
**Type:** IDEA"
fi

# Insert at the end of the `## Ideas` section, or append the section at EOF.
tmp=$(mktemp "$MB_PATH/.backlog.XXXXXX")
cp -p "$BACKLOG" "$tmp"
if grep -qE '^## Ideas[[:space:]]*$' "$BACKLOG"; then
  ENTRY="$ENTRY" awk '
    BEGIN { inserted=0; in_ideas=0; entry=ENVIRON["ENTRY"] }
    /^## Ideas[[:space:]]*$/ { print; in_ideas=1; next }
    in_ideas && /^## / {
      print ""
      print entry
      print ""
      inserted=1
      in_ideas=0
      print
      next
    }
    { print }
    END {
      if (in_ideas && !inserted) {
        print ""
        print entry
      }
    }
  ' "$BACKLOG" > "$tmp"
else
  { cat "$BACKLOG"; printf '\n## Ideas\n\n%s\n' "$ENTRY"; } > "$tmp"
fi

mv "$tmp" "$BACKLOG"
tmp=""
printf '%s\n' "$ID"
