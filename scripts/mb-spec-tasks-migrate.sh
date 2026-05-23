#!/usr/bin/env bash
# mb-spec-tasks-migrate.sh — migrate legacy tasks.md to the mb-task marker format.
#
# Legacy format:  ## N. Title
# New format:     <!-- mb-task:N -->\n## Task N: Title
#
# Usage:
#   mb-spec-tasks-migrate.sh <topic|spec-dir|tasks-file> [--apply|--dry-run] [mb_path]
#
# Resolver (same as mb-spec-validate.sh):
#   - Existing directory → look for tasks.md inside.
#   - Existing file      → use directly.
#   - Else               → <mb>/specs/<safe-topic>/tasks.md.
#
# Modes:
#   --dry-run (default) Print planned output to stdout; touch no files.
#   --apply             Backup original → write new content atomically.
#
# Known limitation: the legacy-heading regex `^## (\d+)\. (.+)$` matches any
# such line regardless of fenced-code-block context. Bodies that contain
# example headings of that exact shape inside ``` fences will be split as
# if those examples were real tasks. Real-world risk is low for tasks.md
# files; rerun is non-destructive (idempotent + timestamped backup).
#
# Exit codes:
#   0 — success (apply, dry-run, idempotent no-op, or empty file)
#   1 — file/path not found or fundamental error
#   2 — usage error

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────────────────────────────

MODE="dry-run"
TARGET=""
MB_ARG=""

for arg in "$@"; do
  case "$arg" in
    --apply)   MODE="apply" ;;
    --dry-run) MODE="dry-run" ;;
    -h|--help)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$arg"
      else
        MB_ARG="$arg"
      fi
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: mb-spec-tasks-migrate.sh <topic|spec-dir|tasks-file> [--apply|--dry-run] [mb_path]" >&2
  exit 2
fi

# ─────────────────────────────────────────────────────────────────────────────
# Resolve tasks file path
# ─────────────────────────────────────────────────────────────────────────────

TASKS_FILE=""
if [ -d "$TARGET" ]; then
  TASKS_FILE="$TARGET/tasks.md"
elif [ -f "$TARGET" ]; then
  TASKS_FILE="$TARGET"
else
  MB_PATH=$(mb_resolve_path "$MB_ARG")
  if [ -z "$MB_PATH" ] || [ ! -d "$MB_PATH" ]; then
    echo "[error] memory bank not found at: ${MB_PATH:-<unset>}" >&2
    exit 2
  fi
  SAFE_TOPIC=$(mb_sanitize_topic "$TARGET")
  if [ -z "$SAFE_TOPIC" ]; then
    echo "[error] topic contains only non-ASCII characters: $TARGET" >&2
    exit 2
  fi
  TASKS_FILE="$MB_PATH/specs/$SAFE_TOPIC/tasks.md"
fi

if [ ! -f "$TASKS_FILE" ]; then
  echo "[error] tasks file not found: $TASKS_FILE" >&2
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Guard: empty file
# ─────────────────────────────────────────────────────────────────────────────

if [ ! -s "$TASKS_FILE" ]; then
  echo "[migrate] empty tasks.md, nothing to migrate"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Guard: idempotency — already has mb-task markers
# ─────────────────────────────────────────────────────────────────────────────

if grep -qF '<!-- mb-task:' "$TASKS_FILE"; then
  echo "[migrate] tasks.md already migrated: $TASKS_FILE"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Core transformation (Python writes directly to a tmp file — no $() round-trip)
# ─────────────────────────────────────────────────────────────────────────────

TMP_FILE="${TASKS_FILE}.new"
trap 'rm -f "$TMP_FILE"' EXIT

TASKS_FILE="$TASKS_FILE" python3 - >"$TMP_FILE" <<'PY'
import os
import re
import sys

tasks_file = os.environ["TASKS_FILE"]
text = open(tasks_file, encoding="utf-8").read()

# Match legacy headings: ## N. Title (no mb-task marker before them)
LEGACY_RE = re.compile(r"^## (\d+)\. (.+)$", re.MULTILINE)
COVERS_RE = re.compile(r"^\*\*covers:\*\*", re.IGNORECASE | re.MULTILINE)

matches = list(LEGACY_RE.finditer(text))
if not matches:
    # No legacy headings found; print as-is (caller handles idempotency)
    sys.stdout.write(text)
    sys.exit(0)

# Split text into preamble + per-task segments
segments = []
for idx, m in enumerate(matches):
    end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
    segments.append((m.group(1), m.group(2), text[m.end():end]))

# Build preamble (text before first heading)
preamble = text[:matches[0].start()]

output_parts = [preamble]

for num_str, title, body in segments:
    n = int(num_str)

    # Strip leading newlines for clean formatting; preserve trailing.
    body_stripped = body.lstrip("\n")

    # Insert **Covers:** placeholder if missing
    if not COVERS_RE.search(body_stripped):
        # Insert before **What to do:** if present, else at top of body
        what_re = re.compile(r"^(\*\*What to do:\*\*)", re.MULTILINE)
        m2 = what_re.search(body_stripped)
        if m2:
            insert_pos = m2.start()
            body_stripped = (
                body_stripped[:insert_pos]
                + "**Covers:** REQ-NNN\n\n"
                + body_stripped[insert_pos:]
            )
        else:
            body_stripped = "**Covers:** REQ-NNN\n\n" + body_stripped

    # Emit new-format block
    output_parts.append(
        f"<!-- mb-task:{n} -->\n"
        f"## Task {n}: {title}\n"
        f"\n"
        f"{body_stripped}"
    )

sys.stdout.write("".join(output_parts))
PY

# ─────────────────────────────────────────────────────────────────────────────
# Dry-run: print and exit (TMP_FILE cleaned by trap)
# ─────────────────────────────────────────────────────────────────────────────

if [ "$MODE" = "dry-run" ]; then
  echo "--- DRY RUN ---"
  cat "$TMP_FILE"
  echo "--- END ---"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Apply: backup → atomic mv (trap disarmed after successful mv)
# ─────────────────────────────────────────────────────────────────────────────

TS=$(date +%s)
BAK_FILE="${TASKS_FILE}.bak.${TS}"
cp -p "$TASKS_FILE" "$BAK_FILE"

mv "$TMP_FILE" "$TASKS_FILE"
trap - EXIT

echo "[migrate] applied: $TASKS_FILE (backup: $BAK_FILE)"
exit 0
