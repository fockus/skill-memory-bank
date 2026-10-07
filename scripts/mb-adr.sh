#!/usr/bin/env bash
# mb-adr.sh — capture an Architecture Decision Record in the ADR registry adr.md.
#
# Usage:
#   mb-adr.sh <title> [mb_path]
#
# Effect: append to <bank>/adr.md (created with `# Architecture Decision Records`
# when missing):
#   ### ADR-NNN — <title> [YYYY-MM-DD] · status: accepted
#   **Context:** / **Decision:** / **Alternatives:** / **Consequences:**
#
# NNN = max ADR id over adr.md AND backlog.md + 1 — banks whose old ADRs still
# sit in backlog.md (not yet migrated by mb-adr-migrate.sh) get no collisions.
# backlog.md is only read, never written. Format: references/templates.md § ADR.
#
# Exit: 0 OK, 1 bank directory missing.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

TITLE="${1:?Usage: mb-adr.sh <title> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")
[ -d "$MB_PATH" ] || { echo "[error] memory bank not found: $MB_PATH" >&2; exit 1; }

ADR_FILE="$MB_PATH/adr.md"
BACKLOG="$MB_PATH/backlog.md"

max_id=$(cat "$ADR_FILE" "$BACKLOG" 2>/dev/null | grep -Eo 'ADR-[0-9]{3,}' | awk -F- '{print $2+0}' | sort -n | tail -1 || true)
ID=$(printf 'ADR-%03d' $(( ${max_id:-0} + 1 )))
TODAY=$(date +%Y-%m-%d)

[ -f "$ADR_FILE" ] || printf '# Architecture Decision Records\n' > "$ADR_FILE"

cat >> "$ADR_FILE" <<EOF

### ${ID} — ${TITLE} [${TODAY}] · status: accepted

**Context:** <!-- 1–2 sentences: the problem that forced a decision -->
**Decision:** <!-- 1–2 sentences: what was chosen and the one main reason -->
**Alternatives:** <!-- 1–2 sentences: what was rejected and why -->
**Consequences:** <!-- 1–2 sentences: what becomes easier / more expensive -->
EOF

printf '%s\n' "$ID"
