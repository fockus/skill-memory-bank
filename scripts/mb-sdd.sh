#!/usr/bin/env bash
# mb-sdd.sh — create a Kiro-style spec triple under specs/<topic>/.
#
# Files created:
#   specs/<topic>/requirements.md  — EARS-only REQ list
#   specs/<topic>/design.md        — Architecture / Interfaces / Decisions / Risks
#   specs/<topic>/tasks.md         — numbered task checkboxes (refs to REQ-IDs)
#
# If `<mb>/context/<topic>.md` exists, the `## Functional Requirements (EARS)`
# section is copied verbatim into requirements.md (preserving REQ-IDs).
#
# Usage:
#   mb-sdd.sh <topic> [--force] [mb_path]
#   mb-sdd.sh --force <topic> [mb_path]
#
# Exit codes:
#   0 — created (or overwritten with --force)
#   1 — usage error / topic missing / target exists without --force / mb path bad
#   2 — internal error during EARS extraction

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

FORCE=0
TOPIC=""
MB_ARG=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TOPIC" ]; then
        TOPIC="$arg"
      else
        MB_ARG="$arg"
      fi
      ;;
  esac
done

if [ -z "$TOPIC" ]; then
  echo "Usage: mb-sdd.sh <topic> [--force] [mb_path]" >&2
  exit 1
fi

MB_PATH=$(mb_resolve_path "$MB_ARG")
SAFE_TOPIC=$(mb_sanitize_topic "$TOPIC")

if [ -z "$SAFE_TOPIC" ]; then
  echo "[error] Topic contains only non-ASCII characters: $TOPIC" >&2
  exit 1
fi

SPEC_DIR="$MB_PATH/specs/$SAFE_TOPIC"
CONTEXT_FILE="$MB_PATH/context/${SAFE_TOPIC}.md"

if [ -d "$SPEC_DIR" ] && [ "$FORCE" -eq 0 ]; then
  echo "[error] spec already exists: $SPEC_DIR" >&2
  echo "[hint]  use --force to overwrite" >&2
  exit 1
fi

mkdir -p "$SPEC_DIR"

# ───────────────────────────────────────────────────────────────────────
# requirements.md
# ───────────────────────────────────────────────────────────────────────
EARS_BLOCK=""
if [ -f "$CONTEXT_FILE" ]; then
  EARS_BLOCK=$(CTX="$CONTEXT_FILE" python3 - <<'PY' || echo ""
import os
import re

text = open(os.environ["CTX"], encoding="utf-8").read()
# Capture content between `## Functional Requirements (EARS)` and the next
# top-level `## ` heading or EOF.
pattern = re.compile(
    r"^##\s+Functional\s+Requirements\s*\(EARS\)\s*\n(.*?)(?=^##\s|\Z)",
    re.MULTILINE | re.DOTALL,
)
m = pattern.search(text)
if not m:
    raise SystemExit(0)
block = m.group(1).strip("\n")
# Keep only `- **REQ-...** ...` lines (drop loose prose)
keep = []
for line in block.splitlines():
    if re.match(r"^\s*-\s*\*\*REQ-\d{3,}\*\*", line):
        keep.append(line)
print("\n".join(keep))
PY
)
fi

REQ_BODY=""
if [ -n "$EARS_BLOCK" ]; then
  REQ_BODY="${EARS_BLOCK}"$'\n'
else
  REQ_BODY="<!-- Add EARS-formatted requirements. Use scripts/mb-req-next-id.sh to assign IDs. -->"$'\n'
  REQ_BODY+="<!-- Patterns: Ubiquitous / Event-driven / State-driven / Optional / Unwanted. -->"$'\n'
  REQ_BODY+=$'\n'
  REQ_BODY+="- **REQ-NNN** (ubiquitous): The system shall ..."$'\n'
fi

cat > "$SPEC_DIR/requirements.md" <<EOF
# Requirements: ${SAFE_TOPIC}

> Spec triple — see also: design.md, tasks.md.
>
> EARS patterns:
> - Ubiquitous:        \`The <system> shall <response>\`
> - Event-driven:      \`When <trigger>, the <system> shall <response>\`
> - State-driven:      \`While <state>, the <system> shall <response>\`
> - Optional feature:  \`Where <feature>, the <system> shall <response>\`
> - Unwanted:          \`If <trigger>, then the <system> shall <response>\`

## Requirements (EARS)

${REQ_BODY}
EOF

# ───────────────────────────────────────────────────────────────────────
# design.md
# ───────────────────────────────────────────────────────────────────────
cat > "$SPEC_DIR/design.md" <<EOF
# Design: ${SAFE_TOPIC}

> Architecture, interfaces, and decisions backing requirements.md.

## Architecture

<!-- Diagrams, layering, data flow. Keep dependencies pointing inward (Clean Arch). -->

## Interfaces

<!-- Protocol/ABC/interface definitions that anchor contract tests. -->

\`\`\`python
# Example placeholder — replace with the real Protocol / ABC.
from typing import Protocol

class Foo(Protocol):
    def bar(self, x: int) -> str: ...
\`\`\`

## Decisions

<!-- ADR-style entries: Context / Options / Decision / Rationale / Consequences. -->

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
|      | H/M/L       | H/M/L  |            |
EOF

# ───────────────────────────────────────────────────────────────────────
# tasks.md
# ───────────────────────────────────────────────────────────────────────
cat > "$SPEC_DIR/tasks.md" <<EOF
# Tasks: ${SAFE_TOPIC}

> Numbered, checkbox-tracked work items. Each task references the
> REQ-IDs it satisfies (covers_requirements: [...]).

## 1. <!-- task title -->

**Covers:** REQ-NNN

- [ ] <!-- concrete sub-step -->
- [ ] tests pass
- [ ] lint clean

## 2. <!-- next task -->

**Covers:** REQ-NNN

- [ ]
EOF

echo "$SPEC_DIR/requirements.md"
echo "$SPEC_DIR/design.md"
echo "$SPEC_DIR/tasks.md"
