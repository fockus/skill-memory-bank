#!/usr/bin/env bash
# mb-plan.sh — create a plan file in Memory Bank.
#
# Usage:
#   mb-plan.sh <type> <topic> [--context <path>] [--sdd] [mb_path]
#
# Types: feature, fix, refactor, experiment
#
# Phase 2 Sprint 2 (SDD-lite):
#   --context <path>  Explicit context file to link in the plan.
#   --sdd             Strict mode: fail unless context exists AND passes
#                     EARS validation (mb-ears-validate.sh exit 0).
#
# Auto-detect: when --context is omitted, mb-plan.sh checks
# `<mb>/context/<sanitized_topic>.md`; if present, the plan gets a
# `## Linked context` section with a Markdown link.
#
# Creates `plans/YYYY-MM-DD_<type>_<topic>.md` from a template (DoD, TDD, risks, gate).
# `<!-- mb-stage:N -->` markers in the template are used by `mb-plan-sync.sh`.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

TYPE=""
TOPIC=""
CONTEXT_PATH=""
SDD_STRICT=0
MB_ARG=""

# Hand-rolled arg parsing (positional + optional flags interleaved).
while [ $# -gt 0 ]; do
  case "$1" in
    --context)
      CONTEXT_PATH="${2:-}"
      [ -n "$CONTEXT_PATH" ] || { echo "[error] --context requires a path" >&2; exit 1; }
      shift 2
      ;;
    --sdd)
      SDD_STRICT=1
      shift
      ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TYPE" ]; then
        TYPE="$1"
      elif [ -z "$TOPIC" ]; then
        TOPIC="$1"
      elif [ -z "$MB_ARG" ]; then
        MB_ARG="$1"
      else
        echo "[error] unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$TYPE" ] || [ -z "$TOPIC" ]; then
  echo "Usage: mb-plan.sh <type> <topic> [--context <path>] [--sdd] [mb_path]. Types: feature, fix, refactor, experiment" >&2
  exit 1
fi

MB_PATH=$(mb_resolve_path "$MB_ARG")
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

# Phase 2 Sprint 2: SDD-lite context resolution.
# Order: explicit --context wins; otherwise auto-detect <mb>/context/<safe_topic>.md.
RESOLVED_CONTEXT=""
if [ -n "$CONTEXT_PATH" ]; then
  if [ -f "$CONTEXT_PATH" ]; then
    RESOLVED_CONTEXT="$CONTEXT_PATH"
  else
    echo "[error] --context file not found: $CONTEXT_PATH" >&2
    exit 1
  fi
else
  AUTO_CONTEXT="$MB_PATH/context/${SAFE_TOPIC}.md"
  [ -f "$AUTO_CONTEXT" ] && RESOLVED_CONTEXT="$AUTO_CONTEXT"
fi

if [ "$SDD_STRICT" -eq 1 ]; then
  if [ -z "$RESOLVED_CONTEXT" ]; then
    echo "[error] --sdd requires a context file (none found at context/${SAFE_TOPIC}.md)" >&2
    exit 1
  fi
  EARS_VALIDATE="$(dirname "$0")/mb-ears-validate.sh"
  if [ -x "$EARS_VALIDATE" ]; then
    if ! bash "$EARS_VALIDATE" "$RESOLVED_CONTEXT" >&2; then
      echo "[error] --sdd: EARS validation failed for $RESOLVED_CONTEXT" >&2
      exit 1
    fi
  fi
fi

DATE=$(date +"%Y-%m-%d")
FILENAME="${DATE}_${TYPE}_${SAFE_TOPIC}.md"
FILEPATH=$(mb_collision_safe_filename "$PLANS_DIR/$FILENAME")

# Capture baseline git commit at plan-creation time. plan-verifier uses this as
# the diff base (`git diff <baseline>...HEAD`) so the audit sees exactly the
# code written after the plan was drafted — no dependence on `HEAD~N` guesses.
# When the caller is not inside a git repo or has no commits, write `unknown`
# so the prompt can degrade gracefully via its documented fallback.
BASELINE_COMMIT=$(git rev-parse HEAD 2>/dev/null || true)
if [[ -z "$BASELINE_COMMIT" ]]; then
  BASELINE_COMMIT="unknown"
fi

mkdir -p "$PLANS_DIR"

cat > "$FILEPATH" << 'TEMPLATE'
# Plan: TYPE — TOPIC

**Baseline commit:** BASELINE_COMMIT_PLACEHOLDER

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

# Substitute type, topic, and baseline commit into the title (portable `sed`: macOS vs GNU)
if sed --version >/dev/null 2>&1; then
  sed -i "s|TYPE|$TYPE|g; s|TOPIC|$SAFE_TOPIC|g; s|BASELINE_COMMIT_PLACEHOLDER|$BASELINE_COMMIT|g" "$FILEPATH"
else
  sed -i '' "s|TYPE|$TYPE|g; s|TOPIC|$SAFE_TOPIC|g; s|BASELINE_COMMIT_PLACEHOLDER|$BASELINE_COMMIT|g" "$FILEPATH"
fi

# Phase 2 Sprint 2 (SDD-lite): inject `## Linked context` section right after
# the Context block when a context file was resolved.
if [ -n "$RESOLVED_CONTEXT" ]; then
  # Render path relative to MB_PATH for portability across moves
  REL_CONTEXT="${RESOLVED_CONTEXT#"$MB_PATH/"}"
  PLAN_FILE="$FILEPATH" REL_CTX="$REL_CONTEXT" python3 - <<'PY'
import os
path = os.environ["PLAN_FILE"]
rel = os.environ["REL_CTX"]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
block = (
    "\n## Linked context\n\n"
    f"- [{rel}]({rel}) — see for EARS-validated requirements (REQ-IDs).\n"
)
# Insert immediately before the FIRST `---` separator line (which closes
# the Context block in the template).
marker = "\n---\n"
idx = text.find(marker)
if idx == -1:
    out = text + block
else:
    out = text[:idx] + block + text[idx:]
with open(path, "w", encoding="utf-8") as fh:
    fh.write(out)
PY
fi

echo "$FILEPATH"
