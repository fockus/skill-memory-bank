#!/usr/bin/env bash
# mb-goal-validate.sh — validate a goal.md before a Dynamic Flow run.
#
# This is a PRECONDITION GATE (REQ-DF-004), so fail-loud exit 1 is correct here.
# (ADR-3's "runners stay exit-0 + JSON" rule applies to the L5 check-runners,
# NOT to this validator — a malformed goal must physically stop the run.)
#
# A valid goal carries:
#   - a `## Acceptance criteria` section with >= 1 `- [ ]` / `- [x]` item
#     outside any Markdown code fence (the deterministic termination condition;
#     REQ-DF-001), AND
#   - a resolvable `progress_source` (REQ-DF-003), one of:
#       checklist | plan-stages | spec-tasks | tests | req-trace | composite
#     where `plan-stages`/`spec-tasks` must point at an existing file via
#     `linked_plan` / `linked_spec`.
#
# Adaptive goals (`mode: adaptive`) additionally require `replan_with`
# (REQ-DF-004). A goal that OMITS all adaptive fields (`mode`, `replan_with`,
# `linked_plans`) defaults to `mode: static` and validates with NO adaptive
# field required (REQ-DF-005) — behaviour stays byte-identical to today.
#
# Usage:
#   mb-goal-validate.sh [goal-path] [mb_path]
#     goal-path : optional explicit path to a goal.md
#                 (default: <mb>/goal.md, mb via mb_resolve_path)
#     mb_path   : optional explicit Memory Bank path (overrides mb_resolve_path)
#
# Output:
#   valid   → exit 0, JSON `{"ok":true}` on stdout
#   invalid → exit 1, JSON `{"ok":false,"errors":[...]}` on stdout
#             + one concrete fix-hint per problem on stderr
#   usage   → exit 2 (bad flags / arg count)
#
# Exit codes:
#   0 — goal is valid
#   1 — goal is invalid (errors named on stderr + JSON on stdout)
#   2 — usage error

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

GOAL_PATH=""
MB_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$GOAL_PATH" ]]; then
        GOAL_PATH="$1"
      elif [[ -z "$MB_ARG" ]]; then
        MB_ARG="$1"
      else
        echo "too many arguments: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

MB_PATH="$(mb_resolve_path "$MB_ARG")"
[[ -z "$GOAL_PATH" ]] && GOAL_PATH="$MB_PATH/goal.md"

# ---- error accumulation -----------------------------------------------------

ERRORS=()

add_error() {
  # $1 = machine code, $2 = human fix-hint
  ERRORS+=("$1")
  echo "[goal] $2" >&2
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

emit_and_exit() {
  if [[ ${#ERRORS[@]} -eq 0 ]]; then
    printf '{"ok":true}\n'
    exit 0
  fi
  printf '{"ok":false,"errors":['
  local i
  for i in "${!ERRORS[@]}"; do
    (( i > 0 )) && printf ','
    json_escape "${ERRORS[$i]}"
  done
  printf ']}\n'
  exit 1
}

# ---- existence --------------------------------------------------------------

if [[ ! -f "$GOAL_PATH" ]]; then
  add_error "goal-missing" \
    "goal file not found: $GOAL_PATH — run \`/mb goal\` to scaffold .memory-bank/goal.md from templates/goal.md."
  emit_and_exit
fi

# ---- frontmatter extraction -------------------------------------------------
# Extract a single scalar YAML frontmatter field.
#
# Hardened rules (Finding #2):
#   - The opening `---` MUST be on line 1 of the file (NR==1).
#   - A closing `---` MUST exist; if none is found by EOF, all fields are
#     treated as missing (the function prints nothing → caller gets "").
#   - Body `---` horizontal rules after the first close are never re-entered.
#
# Implementation: two-pass via a single awk that accumulates lines inside
# the opening fence, then only prints the matched value WHEN a closing fence
# is seen. If EOF is reached with no closing fence, nothing is printed.
frontmatter_field() {
  local field="$1"
  awk -v key="$field" '
    BEGIN { in_fm = 0; found_close = 0; result = "" }
    NR == 1 {
      if ($0 ~ /^---[[:space:]]*$/) { in_fm = 1 }
      next
    }
    in_fm && /^---[[:space:]]*$/ {
      # Closing fence found — commit result and stop.
      found_close = 1
      in_fm = 0
      if (result != "") { print result }
      exit
    }
    in_fm && result == "" {
      line = $0
      if (match(line, "^[[:space:]]*" key "[[:space:]]*:")) {
        val = line
        sub("^[[:space:]]*" key "[[:space:]]*:[[:space:]]*", "", val)
        sub("[[:space:]]+$", "", val)
        gsub(/^"|"$/, "", val)
        gsub(/^\x27|\x27$/, "", val)
        result = val
        # Do NOT print yet — wait for the closing fence.
      }
    }
    END {
      # EOF without closing fence → nothing printed (treat fields as missing).
    }
  ' "$GOAL_PATH"
}

MODE="$(frontmatter_field mode)"
[[ -z "$MODE" ]] && MODE="static"   # REQ-DF-005: default to static when absent
PROGRESS_SOURCE="$(frontmatter_field progress_source)"
REPLAN_WITH="$(frontmatter_field replan_with)"
LINKED_PLAN="$(frontmatter_field linked_plan)"
LINKED_SPEC="$(frontmatter_field linked_spec)"

# ---- REQ-DF-001: acceptance criteria ----------------------------------------
# The body must carry a `## Acceptance criteria` heading followed by >= 1
# `- [ ]` / `- [x]` checkbox item OUTSIDE any Markdown code fence.
#
# Finding #1: track ``` and ~~~ fenced code blocks as a state machine; count
# checkbox lines only when NOT inside a fence AND under the active section.
acceptance_item_count() {
  awk '
    BEGIN {
      in_acc  = 0   # inside ## Acceptance criteria section
      in_fence = 0  # inside a ``` or ~~~ fenced block
      fence_marker = ""
      n = 0
    }

    # Toggle fenced-code-block state.
    # A fence starts/ends with a line that begins with ``` or ~~~
    # (optionally with an info string after the opening).
    /^[[:space:]]*(```|~~~)/ {
      if (!in_fence) {
        # Determine the marker (first 3+ chars of backtick or tilde run)
        match($0, /^[[:space:]]*(```+|~~~+)/)
        fence_marker = substr($0, RSTART, RLENGTH)
        # Trim leading spaces from marker for closing-fence match
        gsub(/^[[:space:]]+/, "", fence_marker)
        in_fence = 1
        next
      } else {
        # Closing fence must start with the same marker characters
        line = $0
        gsub(/^[[:space:]]+/, "", line)
        if (index(line, fence_marker) == 1) {
          in_fence = 0
          fence_marker = ""
          next
        }
      }
    }

    # Do not process anything else while inside a code fence.
    in_fence { next }

    # Heading: enter/exit the acceptance section.
    /^##[[:space:]]+[Aa]cceptance[[:space:]]+criteria[[:space:]]*$/ {
      in_acc = 1
      next
    }
    in_acc && /^#/ { in_acc = 0 }

    # Count real (outside-fence, inside-section) checkbox items.
    in_acc && /^[[:space:]]*-[[:space:]]+\[[ xX]\]/ { n++ }

    END { print n }
  ' "$GOAL_PATH"
}

ACC_COUNT="$(acceptance_item_count)"
if [[ "$ACC_COUNT" -lt 1 ]]; then
  add_error "acceptance-missing" \
    "no \`## Acceptance criteria\` items found in $GOAL_PATH — add a \`## Acceptance criteria\` section with at least one \`- [ ]\` checkbox outside any code fence (the deterministic termination condition)."
fi

# ---- REQ-DF-003: resolvable progress_source ---------------------------------
ALLOWED_SOURCES="checklist plan-stages spec-tasks tests req-trace composite"

source_allowed() {
  local s="$1" a
  for a in $ALLOWED_SOURCES; do
    [[ "$s" == "$a" ]] && return 0
  done
  return 1
}

# Resolve a possibly-relative linked path against the bank, then cwd.
# Returns the resolved absolute path on stdout. Returns non-zero if not found.
resolve_linked() {
  local rel="$1"
  if [[ "$rel" = /* && -e "$rel" ]]; then
    printf '%s\n' "$rel"; return 0
  fi
  if [[ -e "$MB_PATH/$rel" ]]; then
    printf '%s\n' "$MB_PATH/$rel"; return 0
  fi
  if [[ -e "$rel" ]]; then
    printf '%s\n' "$rel"; return 0
  fi
  return 1
}

if [[ -z "$PROGRESS_SOURCE" ]]; then
  add_error "progress_source-missing" \
    "\`progress_source\` is missing in $GOAL_PATH — add one of: ${ALLOWED_SOURCES// /, } (REQ-DF-003)."
elif ! source_allowed "$PROGRESS_SOURCE"; then
  add_error "progress_source-invalid" \
    "\`progress_source: $PROGRESS_SOURCE\` is not allowed — use one of: ${ALLOWED_SOURCES// /, }."
else
  case "$PROGRESS_SOURCE" in
    plan-stages)
      # Finding #3: requires `linked_plan` to resolve to an existing *.md FILE
      # (not a directory). A directory with a plan inside would be ambiguous and
      # is a sign of a misconfigured field.
      if [[ -z "$LINKED_PLAN" ]]; then
        add_error "progress_source-unresolvable" \
          "\`progress_source: plan-stages\` requires a \`linked_plan:\` pointing at an existing plan .md file (REQ-DF-003)."
      else
        resolved_plan="$(resolve_linked "$LINKED_PLAN" 2>/dev/null || true)"
        if [[ -z "$resolved_plan" ]]; then
          add_error "progress_source-unresolvable" \
            "\`progress_source: plan-stages\` cannot resolve \`linked_plan: $LINKED_PLAN\` — no such file under $MB_PATH."
        elif [[ -d "$resolved_plan" ]]; then
          add_error "progress_source-unresolvable" \
            "\`progress_source: plan-stages\` requires \`linked_plan:\` to point at a .md plan FILE, not a directory: $LINKED_PLAN resolves to a directory."
        elif [[ "$resolved_plan" != *.md ]]; then
          add_error "progress_source-unresolvable" \
            "\`progress_source: plan-stages\` requires \`linked_plan:\` to point at a .md file: $LINKED_PLAN does not end in .md."
        fi
      fi
      ;;
    spec-tasks)
      # Finding #3: requires `linked_spec` to resolve to a DIRECTORY that
      # contains tasks.md (or directly to a tasks.md file). A plain file that
      # is not tasks.md is not a valid spec location.
      if [[ -z "$LINKED_SPEC" ]]; then
        add_error "progress_source-unresolvable" \
          "\`progress_source: spec-tasks\` requires a \`linked_spec:\` pointing at an existing spec directory (with tasks.md) or directly at tasks.md (REQ-DF-003)."
      else
        resolved_spec="$(resolve_linked "$LINKED_SPEC" 2>/dev/null || true)"
        if [[ -z "$resolved_spec" ]]; then
          add_error "progress_source-unresolvable" \
            "\`progress_source: spec-tasks\` cannot resolve \`linked_spec: $LINKED_SPEC\` — no such spec under $MB_PATH."
        elif [[ -f "$resolved_spec" ]]; then
          # Caller pointed at a file directly — only valid if it IS tasks.md
          if [[ "$(basename "$resolved_spec")" != "tasks.md" ]]; then
            add_error "progress_source-unresolvable" \
              "\`progress_source: spec-tasks\` with \`linked_spec: $LINKED_SPEC\` resolves to a file that is not tasks.md — point at the spec directory instead."
          fi
        elif [[ -d "$resolved_spec" ]]; then
          # Must contain tasks.md
          if [[ ! -f "$resolved_spec/tasks.md" ]]; then
            add_error "progress_source-unresolvable" \
              "\`progress_source: spec-tasks\` with \`linked_spec: $LINKED_SPEC\` resolves to a directory with no tasks.md inside — add tasks.md or correct the path."
          fi
        else
          add_error "progress_source-unresolvable" \
            "\`progress_source: spec-tasks\` cannot resolve \`linked_spec: $LINKED_SPEC\` — resolved path is neither file nor directory."
        fi
      fi
      ;;
    checklist)
      # Finding #4: checklist source requires checklist.md to exist.
      # Without it the progress computation has no input.
      if [[ ! -f "$MB_PATH/checklist.md" ]]; then
        add_error "progress_source-unresolvable" \
          "\`progress_source: checklist\` requires \`$MB_PATH/checklist.md\` to exist — run \`/mb init\` or create the file first."
      fi
      ;;
    req-trace)
      # Finding #4: req-trace source requires traceability.md to exist.
      # Without it there is no coverage data to compute progress from.
      if [[ ! -f "$MB_PATH/traceability.md" ]]; then
        add_error "progress_source-unresolvable" \
          "\`progress_source: req-trace\` requires \`$MB_PATH/traceability.md\` to exist — run \`bash scripts/mb-traceability-gen.sh\` first."
      fi
      ;;
    tests|composite)
      # tests: progress is computed dynamically at run-time by mb-test-run.sh;
      # no static file to check — the bank just needs to exist.
      # composite: a blend of multiple sources; requires the bank dir but
      # individual sub-sources are validated at resolution-time, not here.
      if [[ ! -d "$MB_PATH" ]]; then
        add_error "progress_source-unresolvable" \
          "\`progress_source: $PROGRESS_SOURCE\` needs a Memory Bank at $MB_PATH — none found."
      fi
      ;;
  esac
fi

# ---- REQ-DF-004: adaptive goals require replan_with -------------------------
# REQ-DF-005: a static goal (default) must NOT require any adaptive field.
if [[ "$MODE" == "adaptive" ]]; then
  if [[ -z "$REPLAN_WITH" ]]; then
    add_error "replan_with-missing" \
      "\`mode: adaptive\` requires a \`replan_with:\` field (e.g. \`replan_with: analyze-task\`) so the run can re-route mid-flight (REQ-DF-004)."
  fi
elif [[ "$MODE" != "static" ]]; then
  add_error "mode-invalid" \
    "\`mode: $MODE\` is not recognized — use \`static\` (default) or \`adaptive\`."
fi

emit_and_exit
