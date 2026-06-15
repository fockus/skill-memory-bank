#!/usr/bin/env bash
# mb-done-gates.sh — mandatory /mb done gate set (handoff-v2 §5, GAP-4).
#
# Usage:
#   mb-done-gates.sh [--mb <path>] [--dir <repo>] [--force --reason "<line>"]
#                    [--out json|human|both]
#
# Runs three independent checks in sequence, each emitting one structured JSON
# line to stdout:
#   1. tests        — dispatch the test runner (scope=touched if a baseline commit
#                     is inferable, else scope=full). not_applicable (no stack)
#                     counts as PASS with a logged WARN.
#   2. rules        — scripts/mb-rules-check.sh on the working tree; CRITICAL = fail.
#   3. placeholders — scripts/mb-rules-check.sh --placeholders-only — scans staged +
#                     uncommitted source for the deny-list markers; any hit = fail.
#                     Deny list default: see MB_PLACEHOLDER_DENY_DEFAULT in mb_rules_check_lib.sh.
#
# Exit 0 only if every required gate passes; otherwise exit 2.
#
# Force semantics:
#   --force requires --reason "<one-line>" (refuse force without a reason).
#   On a forced run WITH failures: append a NOTE to progress.md under today's
#   date heading, store failure-detail JSON under <mb>/tmp/, then exit 0.
#
# Config (pipeline.yaml:done_gates): enabled / required / allow_force. If absent,
# defaults to enabled:true, required:[tests_pass,no_critical_violations,no_placeholders],
# allow_force:true. allow_force:false rejects --force outright.
#
# Stubbable for tests (offline/deterministic):
#   MB_TEST_RUNNER_CMD  — command emitting the test-runner JSON line (default: real path).
#   MB_RULES_CHECK_CMD  — rules-check command (default: scripts/mb-rules-check.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# Canonical placeholder deny default lives in the rules-check lib (single source).
# shellcheck source=mb_rules_check_lib.sh
source "$SCRIPT_DIR/mb_rules_check_lib.sh"

# ---- args -------------------------------------------------------------------

MB_ARG=""
DIR="."
FORCE=0
REASON=""
REASON_SET=0
OUT="human"

print_help() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mb)
      MB_ARG="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    --dir)
      DIR="${2:-.}"; shift; [[ $# -gt 0 ]] && shift ;;
    --force)
      FORCE=1; shift ;;
    --reason)
      # Guard: if --reason is the final arg (no value follows), treat as missing.
      if [[ $# -lt 2 ]]; then
        REASON=""; REASON_SET=1; shift
      else
        REASON="$2"; REASON_SET=1; shift 2
      fi ;;
    --out)
      OUT="${2:-human}"; shift; [[ $# -gt 0 ]] && shift ;;
    --help|-h)
      print_help; exit 0 ;;
    *)
      printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$OUT" in
  json|human|both) ;;
  *) printf 'invalid --out: %s (allowed: json|human|both)\n' "$OUT" >&2; exit 2 ;;
esac

MB="$(mb_resolve_path "$MB_ARG")"

# ---- config (pipeline.yaml:done_gates) --------------------------------------

DEFAULT_PIPELINE="$REPO_ROOT/references/pipeline.default.yaml"
PROJECT_PIPELINE="$MB/pipeline.yaml"
PIPELINE_PATH=""
if [[ -f "$PROJECT_PIPELINE" ]]; then
  PIPELINE_PATH="$PROJECT_PIPELINE"
elif [[ -f "$DEFAULT_PIPELINE" ]]; then
  PIPELINE_PATH="$DEFAULT_PIPELINE"
fi

# Emit (on stdout) four TAB-separated fields the shell consumes:
#   enabled<TAB>allow_force<TAB>placeholder_deny_csv<TAB>required_csv
#
# Fail-closed policy for allow_force (MAJOR #2):
#   - No project pipeline.yaml at all → fall back to defaults (allow_force=true).
#   - Project pipeline.yaml exists but CANNOT be parsed → treat allow_force=false
#     (fail closed) and log a WARN to stderr. Do NOT silently apply defaults.
#   - Project pipeline.yaml parsed OK → honour its values; absent keys use defaults.
#   - Default pipeline.yaml (no project override) → always use defaults.
#
# The Python script receives three env vars:
#   PIPELINE_PATH        — path to the resolved pipeline file (may be "" if none)
#   PROJECT_PIPELINE_EXISTS — "1" when a PROJECT (not default) pipeline.yaml was found
#   MB_PLACEHOLDER_DENY_DEFAULT — canonical deny default from the lib
read_done_gates_config() {
  PIPELINE_PATH="${PIPELINE_PATH:-}" \
  PROJECT_PIPELINE_EXISTS="${PROJECT_PIPELINE_EXISTS:-0}" \
  MB_PLACEHOLDER_DENY_DEFAULT="$MB_PLACEHOLDER_DENY_DEFAULT" python3 - <<'PY'
import os, sys
path = os.environ.get("PIPELINE_PATH", "")
is_project = os.environ.get("PROJECT_PIPELINE_EXISTS", "0") == "1"
enabled, allow_force = "true", "true"
deny = os.environ.get("MB_PLACEHOLDER_DENY_DEFAULT", "")
required = "tests_pass,no_critical_violations,no_placeholders"

data = None  # None = "not attempted" or "parse failed"
if path:
    try:
        import yaml  # type: ignore
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception as exc:
        if is_project:
            # Project config exists but is unparseable → fail closed on force.
            sys.stderr.write(
                f"[mb-done-gates][WARN] project pipeline.yaml parse error: {exc} "
                f"— treating allow_force=false (fail closed)\n"
            )
            # Emit a sentinel that the shell checks separately.
            print("\t".join([enabled, "false", deny, required]))
            sys.exit(0)
        else:
            data = {}

if data is not None:
    dg = data.get("done_gates") or {}
    if isinstance(dg, dict):
        if "enabled" in dg:
            enabled = "true" if dg.get("enabled") else "false"
        if "allow_force" in dg:
            allow_force = "true" if dg.get("allow_force") else "false"
        req = dg.get("required")
        if isinstance(req, list) and req:
            required = ",".join(str(r) for r in req)
    dp = data.get("done_placeholders") or {}
    if isinstance(dp, dict):
        d = dp.get("deny")
        if isinstance(d, list) and d:
            deny = ",".join(str(x) for x in d)

print("\t".join([enabled, allow_force, deny, required]))
PY
}

# Track whether a project-level (not default) pipeline.yaml was found, so the
# Python reader can apply the fail-closed policy correctly (MAJOR #2).
PROJECT_PIPELINE_EXISTS=0
[[ -f "$PROJECT_PIPELINE" ]] && PROJECT_PIPELINE_EXISTS=1

CFG="$(PROJECT_PIPELINE_EXISTS="$PROJECT_PIPELINE_EXISTS" read_done_gates_config)"
GATES_ENABLED="$(printf '%s' "$CFG" | cut -f1)"
ALLOW_FORCE="$(printf '%s' "$CFG" | cut -f2)"
PLACEHOLDER_DENY="$(printf '%s' "$CFG" | cut -f3)"
REQUIRED_CSV="$(printf '%s' "$CFG" | cut -f4)"

# ---- force pre-flight validation --------------------------------------------

if [[ "$FORCE" -eq 1 ]]; then
  if [[ "$ALLOW_FORCE" != "true" ]]; then
    printf '[mb-done-gates] --force rejected: allow_force is disabled in pipeline.yaml\n' >&2
    exit 2
  fi
  if [[ "$REASON_SET" -ne 1 || -z "$REASON" ]]; then
    printf '[mb-done-gates] --force requires --reason "<one-line>"; refusing.\n' >&2
    exit 2
  fi
  # MAJOR #6: --reason must be a single line (no CR or LF). An embedded newline
  # allows injecting fake headings into the append-only progress.md audit log.
  # Reject BEFORE any side-effect (no file writes, no JSON, no progress.md touch).
  if [[ "$REASON" == *$'\n'* || "$REASON" == *$'\r'* ]]; then
    printf '[mb-done-gates] --force rejected: --reason must be a single line (no CR/LF).\n' >&2
    exit 2
  fi
fi

# ---- gate JSON emit helper --------------------------------------------------

GATE_LINES=()      # structured JSON lines, one per gate
FAILED_GATES=()    # names of gates that failed

emit_gate() {
  local gate="$1" pass="$2" detail="$3"
  local line
  line="$(printf '{"gate":"%s","pass":%s,"detail":"%s"}' \
    "$gate" "$pass" "$(json_escape_raw "$detail")")"
  GATE_LINES+=("$line")
  printf '%s\n' "$line"
  [[ "$pass" == "true" ]] || FAILED_GATES+=("$gate")
}

# Minimal JSON string-body escape (no surrounding quotes).
json_escape_raw() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

# ---- gate 1: tests ----------------------------------------------------------

run_tests_gate() {
  local runner_cmd="${MB_TEST_RUNNER_CMD:-}"
  local out verdict not_applicable
  if [[ -z "$runner_cmd" ]]; then
    runner_cmd="bash $SCRIPT_DIR/mb-test-run.sh --dir $DIR --out json"
  fi
  # The runner exits 0 even on failure; the verdict lives in tests_pass.
  out="$($runner_cmd 2>/dev/null || true)"
  verdict="$(printf '%s' "$out" | python3 -c \
    'import sys,json
raw=sys.stdin.read().strip()
v=None
for line in raw.splitlines():
    line=line.strip()
    if not line.startswith("{"):
        continue
    try:
        d=json.loads(line)
    except Exception:
        continue
    if "tests_pass" in d:
        v=d.get("tests_pass")
print("null" if v is None else ("true" if v is True else "false"))' 2>/dev/null || printf 'null')"
  not_applicable="$(printf '%s' "$out" | python3 -c \
    'import sys,json
raw=sys.stdin.read().strip()
na=False
for line in raw.splitlines():
    line=line.strip()
    if not line.startswith("{"):
        continue
    try:
        d=json.loads(line)
    except Exception:
        continue
    if d.get("not_applicable") is True:
        na=True
print("true" if na else "false")' 2>/dev/null || printf 'false')"

  if [[ "$verdict" == "true" ]]; then
    emit_gate "tests" "true" "tests_pass=true"
  elif [[ "$not_applicable" == "true" || "$verdict" == "null" ]]; then
    # No stack / runner missing / zero tests → PASS with a WARN (§9 risk row).
    printf '[mb-done-gates][WARN] tests gate not_applicable (no stack/runner) — treated as PASS\n' >&2
    emit_gate "tests" "true" "not_applicable (WARN)"
  else
    emit_gate "tests" "false" "tests_pass=false"
  fi
}

# ---- gate 2: rules (deterministic) ------------------------------------------

# Build the CSV of changed source files (staged + uncommitted) in DIR. Empty
# string when git is unavailable or there is no repo.
changed_files_csv() {
  if git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    {
      git -C "$DIR" diff --name-only 2>/dev/null || true
      git -C "$DIR" diff --staged --name-only 2>/dev/null || true
      git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u | paste -sd, -
  fi
}

run_rules_gate() {
  local rules_cmd="${MB_RULES_CHECK_CMD:-}"
  [[ -z "$rules_cmd" ]] && rules_cmd="bash $SCRIPT_DIR/mb-rules-check.sh"
  local files_csv out rc
  files_csv="$(changed_files_csv)"

  set +e
  # MAJOR #3: pass changed files as BOTH --files AND --diff-files so that
  # check_tdd_delta (which keys off DIFF_FILES) fires on source-without-test changes.
  out="$($rules_cmd --files "$files_csv" --diff-files "$files_csv" --out json 2>/dev/null)"
  rc=$?
  set -e

  # CRITICAL violation present? Check both exit code and JSON severity.
  if [[ "$rc" -ne 0 ]] || printf '%s' "$out" | grep -q '"severity":"CRITICAL"'; then
    emit_gate "rules" "false" "critical rules violation"
  else
    emit_gate "rules" "true" "no critical violations"
  fi
}

# ---- gate 3: placeholders ---------------------------------------------------

run_placeholders_gate() {
  local rules_cmd="${MB_RULES_CHECK_CMD:-}"
  [[ -z "$rules_cmd" ]] && rules_cmd="bash $SCRIPT_DIR/mb-rules-check.sh"
  local files_csv rc
  files_csv="$(changed_files_csv)"

  set +e
  MB_PLACEHOLDER_DENY="$PLACEHOLDER_DENY" \
    $rules_cmd --placeholders-only --files "$files_csv" --out json >/dev/null 2>&1
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    emit_gate "placeholders" "false" "placeholder marker found"
  else
    emit_gate "placeholders" "true" "no placeholders"
  fi
}

# ---- run gates --------------------------------------------------------------

if [[ "$GATES_ENABLED" != "true" ]]; then
  printf '[mb-done-gates] done_gates disabled in config — skipping all gates\n' >&2
  exit 0
fi

run_tests_gate
run_rules_gate
run_placeholders_gate

# ---- verdict (MAJOR #1: only REQUIRED gate failures block) ------------------

# Map gate internal name → required-list name (from pipeline.yaml:done_gates.required).
gate_to_required_name() {
  case "$1" in
    tests)        printf 'tests_pass' ;;
    rules)        printf 'no_critical_violations' ;;
    placeholders) printf 'no_placeholders' ;;
    *)            printf '%s' "$1" ;;
  esac
}

# Check if a required-name is in the REQUIRED_CSV (comma-separated list).
is_required() {
  local req_name="$1"
  local IFS=,
  local r
  for r in $REQUIRED_CSV; do
    [[ "${r// /}" == "$req_name" ]] && return 0
  done
  return 1
}

# Collect REQUIRED failures (for exit code + force summary); non-required
# failures still appear in every gate JSON line but do not block.
REQUIRED_FAILED_GATES=()
for g in "${FAILED_GATES[@]+"${FAILED_GATES[@]}"}"; do
  if is_required "$(gate_to_required_name "$g")"; then
    REQUIRED_FAILED_GATES+=("$g")
  fi
done

if [[ "${#REQUIRED_FAILED_GATES[@]}" -eq 0 ]]; then
  exit 0
fi

GATES_SUMMARY="$(IFS=,; printf '%s' "${REQUIRED_FAILED_GATES[*]}")"

if [[ "$FORCE" -ne 1 ]]; then
  printf '[mb-done-gates] FAIL — required gates failed: %s (use --force --reason "<line>" to override)\n' \
    "$GATES_SUMMARY" >&2
  exit 2
fi

# Forced run with required failures: record the override and exit 0.
TS="$(date -u +%Y%m%dT%H%M%SZ)"
TMP_DIR="$MB/tmp"
mkdir -p "$TMP_DIR"
FAILURE_JSON="$TMP_DIR/done-gate-failure-$TS.json"

{
  printf '{"forced_at":"%s","reason":"%s","required_failed_gates":[' "$TS" "$(json_escape_raw "$REASON")"
  for i in "${!REQUIRED_FAILED_GATES[@]}"; do
    (( i > 0 )) && printf ','
    printf '"%s"' "${REQUIRED_FAILED_GATES[$i]}"
  done
  printf '],"all_failed_gates":['
  for i in "${!FAILED_GATES[@]}"; do
    (( i > 0 )) && printf ','
    printf '"%s"' "${FAILED_GATES[$i]}"
  done
  printf '],"gates":['
  for i in "${!GATE_LINES[@]}"; do
    (( i > 0 )) && printf ','
    printf '%s' "${GATE_LINES[$i]}"
  done
  printf ']}\n'
} > "$FAILURE_JSON"

# Append the NOTE to progress.md under today's date heading (create if missing).
PROGRESS="$MB/progress.md"
TODAY="$(date +%Y-%m-%d)"
[[ -f "$PROGRESS" ]] || printf '# Progress\n' > "$PROGRESS"

if ! grep -qF "## $TODAY" "$PROGRESS"; then
  printf '\n## %s\n' "$TODAY" >> "$PROGRESS"
fi
printf '\n### NOTE: /mb done --force — gates failed: %s: %s\n' \
  "$GATES_SUMMARY" "$REASON" >> "$PROGRESS"

printf '[mb-done-gates] FORCED past required failed gates (%s). NOTE appended to progress.md; detail: %s\n' \
  "$GATES_SUMMARY" "$FAILURE_JSON" >&2
exit 0
