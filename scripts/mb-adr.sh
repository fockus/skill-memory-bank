#!/usr/bin/env bash
# mb-adr.sh — capture an Architecture Decision Record in backlog.md.
#
# Usage:
#   mb-adr.sh <title> [mb_path]
#
# Effect: append to `## ADR` section in backlog.md:
#   ### ADR-NNN — <title> [YYYY-MM-DD]
#   **Context:** …
#   **Options:**
#   - …
#   **Decision:** …
#   **Rationale:** …
#   **Consequences:** …
#
# Exit: 0 OK, 1 missing backlog.md.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

TITLE="${1:?Usage: mb-adr.sh <title> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")

BACKLOG="$MB_PATH/backlog.md"
[ -f "$BACKLOG" ] || { echo "[error] backlog.md not found: $BACKLOG" >&2; exit 1; }

max_id=$(grep -Eo 'ADR-[0-9]{3}' "$BACKLOG" 2>/dev/null | awk -F- '{print $2+0}' | sort -n | tail -1 || true)
next=$(printf '%03d' $(( ${max_id:-0} + 1 )))
ID="ADR-${next}"
TODAY=$(date +%Y-%m-%d)

# Skeleton — double-space indent on Options bullet is intentional for nested readability.
SKELETON=$(cat <<EOF

### ${ID} — ${TITLE} [${TODAY}]

**Context:** <!-- what problem triggered this decision -->

**Options:**
- A: <!-- option A --> — <!-- pros / cons -->
- B: <!-- option B --> — <!-- pros / cons -->

**Decision:** <!-- chosen option and short why -->

**Rationale:** <!-- deeper reasoning -->

**Consequences:** <!-- what changes because of this decision -->
EOF
)

tmp=$(mktemp)
skel_file=$(mktemp)
printf '%s\n' "$SKELETON" > "$skel_file"

if grep -qE '^## ADR[[:space:]]*$' "$BACKLOG"; then
  # Insert SKELETON before the next `## ` after `## ADR`, or at EOF if ADR is last.
  awk -v skel_file="$skel_file" '
    BEGIN {
      skel=""
      while ((getline line < skel_file) > 0) {
        skel = skel line "\n"
      }
      close(skel_file)
      in_adr=0
      done=0
    }
    /^## ADR[[:space:]]*$/ { print; in_adr=1; next }
    in_adr && /^## / && !/^## ADR/ {
      printf "%s", skel
      print ""
      in_adr=0
      done=1
      print
      next
    }
    { print }
    END {
      if (in_adr && !done) {
        printf "%s", skel
      }
    }
  ' "$BACKLOG" > "$tmp"
  mv "$tmp" "$BACKLOG"
else
  # `## ADR` heading missing — append a new ADR section.
  {
    cat "$BACKLOG"
    printf '\n## ADR\n'
    cat "$skel_file"
  } > "$tmp"
  mv "$tmp" "$BACKLOG"
fi

rm -f "$skel_file"

printf '%s\n' "$ID"
