#!/usr/bin/env bash
# mb-sdd.sh — create a hybrid Kiro spec triple under specs/<topic>/.
#
# Files created:
#   specs/<topic>/requirements.md  — User Stories + EARS acceptance criteria
#   specs/<topic>/design.md        — Architecture / Interfaces / Decisions / Risks
#   specs/<topic>/tasks.md         — numbered task checkboxes (refs to REQ-IDs)
#
# requirements.md uses the HYBRID format: each requirement is one Kiro User Story
# ("As a <role>, I want <feature>, so that <benefit>") followed by its EARS
# acceptance criteria (the REQ-NNN bullets). EARS validation (mb-ears-validate.sh)
# checks only the REQ bullets; the User-Story lines are ignored, so the two layers
# coexist. The spec triple stays Kiro/Kilo-exportable.
#
# If `<mb>/context/<topic>.md` exists, the `## Functional Requirements (EARS)`
# section is copied verbatim into the acceptance criteria (preserving REQ-IDs).
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
  REQ_BODY="<!-- Add EARS-formatted requirements. Use scripts/mb-req-next-id.sh --spec ${SAFE_TOPIC} to assign per-spec-local IDs. -->"$'\n'
  REQ_BODY+="<!-- Patterns: Ubiquitous / Event-driven / State-driven / Optional / Unwanted. -->"$'\n'
  REQ_BODY+=$'\n'
  REQ_BODY+="- **REQ-NNN**: THE SYSTEM SHALL ..."$'\n'
fi

cat > "$SPEC_DIR/requirements.md" <<EOF
# Requirements: ${SAFE_TOPIC}

> Spec triple — see also: design.md, tasks.md.
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        \`THE SYSTEM SHALL <response>\`
> - Event-driven:      \`WHEN <trigger> THE SYSTEM SHALL <response>\`
> - State-driven:      \`WHILE <state> THE SYSTEM SHALL <response>\`
> - Optional feature:  \`WHERE <feature> THE SYSTEM SHALL <response>\`
> - Unwanted:          \`IF <trigger> THEN THE SYSTEM SHALL <response>\`

## Requirements (EARS)

<!-- Hybrid SDD format: each requirement = ONE Kiro User Story + its EARS acceptance -->
<!-- criteria. Group the REQ-NNN bullets below under user stories; split into multiple -->
<!-- ### Requirement N blocks as the topic needs. REQ-IDs stay unique and EARS-valid   -->
<!-- (mb-ears-validate.sh validates only REQ bullets; User-Story lines are ignored).   -->

### Requirement 1: <!-- short title -->

**User Story:** As a <role>, I want <feature>, so that <benefit>.

#### Acceptance Criteria

${REQ_BODY}

## Scenarios

<!-- OPTIONAL but recommended: GIVEN/WHEN/THEN acceptance scenarios.            -->
<!-- Each scenario links to its REQ(s) via **Covers:** and becomes a test-plan  -->
<!-- item (scripts/mb-scenario-extract.py) that /mb work turns into a real test -->
<!-- in the project's own stack. Enforce "every REQ has a scenario" with         -->
<!-- mb-spec-validate.sh --require-scenarios (off by default).                   -->

<!-- mb-scenario:1 -->
### Scenario: <name>
**Covers:** REQ-NNN

- GIVEN <initial state>
- WHEN <action taken>
- THEN <observable outcome>
- AND <additional outcome — optional>
<!-- /mb-scenario:1 -->
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

<!-- Define the ports/interfaces that anchor contract tests, in the project's   -->
<!-- own language (Go interface, TypeScript interface, Python Protocol/ABC, ...).-->
<!-- Keep dependencies pointing inward (Clean Arch); list inputs, outputs, and   -->
<!-- error conditions — not step-by-step implementation.                         -->

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
> REQ-IDs it satisfies via the Covers field.

<!-- mb-task:1 -->
## Task 1: <!-- task title -->

**Covers:** REQ-NNN
**Role:** developer

**What to do:**
- <!-- concrete implementation step -->

**Testing (TDD — tests BEFORE implementation):**
- <!-- unit or integration test to write first -->

**DoD:**
- [ ] <!-- concrete acceptance criterion -->
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:2 -->
## Task 2: <!-- next task title -->

**Covers:** REQ-NNN
**Role:** developer

**What to do:**
- <!-- implementation step -->

**Testing (TDD — tests BEFORE implementation):**
- <!-- test to write first -->

**DoD:**
- [ ] <!-- acceptance criterion -->
- [ ] tests pass
- [ ] lint clean
EOF

echo "$SPEC_DIR/requirements.md"
echo "$SPEC_DIR/design.md"
echo "$SPEC_DIR/tasks.md"
