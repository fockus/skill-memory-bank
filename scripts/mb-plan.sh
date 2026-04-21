#!/usr/bin/env bash
# mb-plan.sh — create a plan file in Memory Bank.
# Usage: mb-plan.sh <type> <topic> [mb_path]
# Types: feature, fix, refactor, experiment
# Creates `plans/YYYY-MM-DD_<type>_<topic>.md` from a template (DoD, TDD, risks, gate).
# `<!-- mb-stage:N -->` markers in the template are used by `mb-plan-sync.sh`.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

TYPE="${1:?Usage: mb-plan.sh <type> <topic> [mb_path]. Types: feature, fix, refactor, experiment}"
TOPIC="${2:?Usage: mb-plan.sh <type> <topic> [mb_path]}"
MB_PATH=$(mb_resolve_path "${3:-}")
PLANS_DIR="$MB_PATH/plans"

case "$TYPE" in
  feature|fix|refactor|experiment) ;;
  *) echo "Unknown type: $TYPE. Allowed: feature, fix, refactor, experiment" >&2; exit 1 ;;
esac

SAFE_TOPIC=$(mb_sanitize_topic "$TOPIC")

if [[ -z "$SAFE_TOPIC" ]]; then
  echo "Topic contains only non-ASCII characters: $TOPIC" >&2
  exit 1
fi

DATE=$(date +"%Y-%m-%d")
FILENAME="${DATE}_${TYPE}_${SAFE_TOPIC}.md"
FILEPATH=$(mb_collision_safe_filename "$PLANS_DIR/$FILENAME")

mkdir -p "$PLANS_DIR"

cat > "$FILEPATH" << 'TEMPLATE'
# Plan: TYPE — TOPIC

## Context

**Problem:** <!-- What triggered creation of this plan -->

**Expected result:** <!-- What should be achieved -->

**Related files:**
- <!-- links to code, specs, experiments -->

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: <!-- title -->

**What to do:**
- <!-- concrete actions -->

**Testing (TDD — tests BEFORE implementation):**
- <!-- unit tests: what they verify, edge cases -->
- <!-- integration tests: which components interact -->

**DoD (Definition of Done):**
- [ ] <!-- concrete, measurable criterion (SMART) -->
- [ ] tests pass
- [ ] lint clean

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

<!-- mb-stage:2 -->
### Stage 2: <!-- title -->

**What to do:**
-

**Testing (TDD):**
-

**DoD:**
- [ ]

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| <!-- risk --> | <!-- H/M/L --> | <!-- how to prevent it --> |

## Gate (plan success criterion)

<!-- When the plan is considered fully complete -->
TEMPLATE

# Substitute type and topic into the title (portable `sed`: macOS vs GNU)
if sed --version >/dev/null 2>&1; then
  sed -i "s|TYPE|$TYPE|g; s|TOPIC|$SAFE_TOPIC|g" "$FILEPATH"
else
  sed -i '' "s|TYPE|$TYPE|g; s|TOPIC|$SAFE_TOPIC|g" "$FILEPATH"
fi

echo "$FILEPATH"
