#!/usr/bin/env bash
# mb-plan.sh — create a plan file in Memory Bank.
#
# Usage:
#   mb-plan.sh <type> <topic> [--context <path>] [--sdd] [--tier small|standard|large|extra]
#              [--qa|--no-qa] [--spec <topic>] [mb_path]
#
# Types: feature, fix, refactor, experiment
#
# Phase 2 Sprint 2 (SDD-lite):
#   --context <path>  Explicit context file to link in the plan.
#   --sdd             Strict mode: fail unless context exists AND passes
#                     EARS validation (mb-ears-validate.sh exit 0).
#
# --tier adds `qa: on | off — <reason>` (rules: references/effort-tiers.md § QA declaration);
# --spec <topic> makes a wrapper plan with `linked_spec: specs/<topic>`.
#
# Auto-detect: without --context, `<mb>/context/<sanitized_topic>.md` is linked when present.
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
TIER="" QA_FLAG="" SPEC_TOPIC="" QA_DECL="" SPEC_SAFE=""

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
    --tier) TIER="${2:-}"; [ -n "$TIER" ] || { echo "[error] --tier requires small|standard|large|extra" >&2; exit 1; }; shift 2 ;;
    --qa|--no-qa) [ "$QA_FLAG" = "--no-qa" ] || QA_FLAG="$1"; shift ;; # --no-qa wins in any order
    --spec) SPEC_TOPIC="${2:-}"; [ -n "$SPEC_TOPIC" ] || { echo "[error] --spec requires a topic" >&2; exit 1; }; shift 2 ;;
    -h|--help)
      sed -n '2,19p' "$0"
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
  echo "Usage: mb-plan.sh <type> <topic> [--context <path>] [--sdd] [--tier T] [--qa|--no-qa] [--spec <topic>] [mb_path]. Types: feature, fix, refactor, experiment" >&2
  exit 1
fi

MB_PATH=$(mb_resolve_path "$MB_ARG")
PLANS_DIR="$MB_PATH/plans"

case "$TIER" in ""|small|standard|large|extra) ;; *) echo "[error] --tier must be small|standard|large|extra" >&2; exit 1 ;; esac

case "$TYPE" in
  feature|fix|refactor|experiment) ;;
  *) echo "Unknown type: $TYPE. Allowed: feature, fix, refactor, experiment" >&2; exit 1 ;;
esac

# Soft-warn (never block) on legacy Cyrillic Этап/Эпик/Спринт/Фаза in <topic>; canon is Phase/Sprint/Stage.
if printf '%s' "$TOPIC" | grep -qiE '\b(Этап|Эпик|Спринт|Фаза)\b'; then
  echo "[mb-plan] WARN: topic contains legacy Cyrillic naming; prefer Phase/Sprint/Stage. See references/templates.md." >&2
fi

SAFE_TOPIC=$(mb_sanitize_topic "$TOPIC")

if [[ -z "$SAFE_TOPIC" ]]; then
  echo "Topic contains only non-ASCII characters: $TOPIC" >&2
  exit 1
fi

# SDD-lite context resolution.
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

# QA declaration (first match wins). Plan time reads qa.enabled only.
if [ -n "$TIER" ]; then
  QA_ENABLED=$(awk '/^qa:/{f=1;next} /^[^ #]/{f=0} f && $1=="enabled:"{print $2; exit}' "$MB_PATH/pipeline.yaml" 2>/dev/null || true)
  if [ "$QA_FLAG" = "--no-qa" ] || [ "$QA_ENABLED" = "false" ]; then QA_DECL="off — disabled"
  elif [ "$TIER" = small ] && [ "$QA_FLAG" != "--qa" ] && [ "$QA_ENABLED" != "true" ]; then QA_DECL="off — small tier"
  elif [ ! -f "$MB_PATH/qa/README.md" ]; then QA_DECL="off — no QA target"; else QA_DECL="on"; fi
fi

if [ -n "$SPEC_TOPIC" ]; then
  SPEC_SAFE=$(mb_sanitize_topic "$SPEC_TOPIC")
  [ -f "$MB_PATH/specs/$SPEC_SAFE/tasks.md" ] || { echo "[error] --spec: specs/$SPEC_SAFE/tasks.md not found" >&2; exit 1; }
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
---
type: TYPE
topic: TOPIC
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: DATE_PLACEHOLDER
---
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

<!-- One stage by default. Add a stage only at a dependency, layer/owner, risk or parallel boundary (references/templates.md § Plan decomposition). -->

**Files:** <!-- files this stage edits; /mb work computes parallel waves from these lines -->

**What to do:**
- <!-- concrete actions -->

**Testing (TDD — tests BEFORE implementation):**
- <!-- tests for the plan as a whole: behavior, edge cases -->

**DoD (Definition of Done):**
- [ ] <!-- concrete, measurable criterion (SMART) -->
- [ ] tests pass
- [ ] lint clean

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

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
  sed -i "s|TYPE|$TYPE|g; s|TOPIC|$SAFE_TOPIC|g; s|BASELINE_COMMIT_PLACEHOLDER|$BASELINE_COMMIT|g; s|DATE_PLACEHOLDER|$DATE|g" "$FILEPATH"
else
  sed -i '' "s|TYPE|$TYPE|g; s|TOPIC|$SAFE_TOPIC|g; s|BASELINE_COMMIT_PLACEHOLDER|$BASELINE_COMMIT|g; s|DATE_PLACEHOLDER|$DATE|g" "$FILEPATH"
fi

# QA declaration and spec wrapper: frontmatter lines, the QA DoD item, the single wrapper stage.
if [ -n "$QA_DECL" ] || [ -n "$SPEC_SAFE" ]; then
  PLAN_FILE="$FILEPATH" QA_DECL="$QA_DECL" SPEC_SAFE="$SPEC_SAFE" TOPIC_SAFE="$SAFE_TOPIC" python3 - <<'PY'
import os
e = os.environ
text = open(e["PLAN_FILE"], encoding="utf-8").read()
fm = ("linked_spec: specs/%s\n" % e["SPEC_SAFE"] if e["SPEC_SAFE"] else "") + ("qa: %s\n" % e["QA_DECL"] if e["QA_DECL"] else "")
text = text.replace("linked_specs: []\n", "linked_specs: []\n" + fm, 1)
if e["SPEC_SAFE"]:
    t = e["SPEC_SAFE"]
    text = text.replace("### Stage 1: <!-- title -->", "### Stage 1: Execute specs/" + t, 1)
    text = text.replace("- <!-- concrete actions -->", "**Run:** `/mb work <this plan>` — `specs/" + t + "/tasks.md` is the source of truth.", 1)
if e["QA_DECL"] == "on":
    text = text.replace("- [ ] lint clean\n", "- [ ] lint clean\n- [ ] QA: `/mb qa run @%s` passes qa.gate (no open critical or major bug)\n" % e["TOPIC_SAFE"], 1)
open(e["PLAN_FILE"], "w", encoding="utf-8").write(text)
PY
fi

# Inject `## Linked context` after the Context block when a context file was resolved.
if [ -n "$RESOLVED_CONTEXT" ]; then
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

# Scenario test-plan link: if the topic has an SDD spec with GIVEN/WHEN/THEN
# scenarios, surface them in the plan so each stage maps tests to scenario IDs.
SPEC_REQ="$MB_PATH/specs/$SAFE_TOPIC/requirements.md"
SCEN_SCRIPT="$(dirname "$0")/mb-scenario-extract.py"
if [ -f "$SPEC_REQ" ] && [ -f "$SCEN_SCRIPT" ]; then
  SCEN_JSONL=$(python3 "$SCEN_SCRIPT" "$SPEC_REQ" 2>/dev/null || true)
  if [ -n "$SCEN_JSONL" ]; then
    PLAN_FILE="$FILEPATH" SCEN_DATA="$SCEN_JSONL" SPEC_REL="specs/$SAFE_TOPIC/requirements.md" \
      python3 - <<'PY'
import json, os
plan = os.environ["PLAN_FILE"]
rel = os.environ["SPEC_REL"]
rows = []
for line in os.environ.get("SCEN_DATA", "").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        s = json.loads(line)
    except json.JSONDecodeError:
        continue
    covers = ", ".join(s.get("covers") or []) or "—"
    rows.append(f"- `{s.get('test_id','?')}` ({covers}) — {s.get('name','')}")
if rows:
    block = (
        "\n## Linked scenarios (test-plan)\n\n"
        f"From [{rel}]({rel}). Each stage's **Testing** writes one test per "
        "scenario below (Arrange=GIVEN, Act=WHEN, Assert=THEN), named after its id:\n\n"
        + "\n".join(rows) + "\n"
    )
    with open(plan, "a", encoding="utf-8") as fh:
        fh.write(block)
PY
  fi
fi

echo "$FILEPATH"
