#!/usr/bin/env bash
# mb-done-gates.sh — /mb done gate set: tests + rules + placeholders (exit 0/2).
# Usage: mb-done-gates.sh [--mb PATH] [--dir REPO] [--force --reason LINE] [--out json|human|both]
# Force: requires --reason; appends NOTE to progress.md + JSON under <mb>/tmp/.
# Config: pipeline.yaml done_gates / done_placeholders (defaults if absent).
# Stubs: MB_TEST_RUNNER_CMD, MB_RULES_CHECK_CMD.

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

# read_done_gates_config → enabled, allow_force, deny csv, required csv (TAB-separated).
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
  local out rc parse_line verdict not_applicable parse_ok
  if [[ -z "$runner_cmd" ]]; then
    runner_cmd="bash $SCRIPT_DIR/mb-test-run.sh --dir $DIR --out json"
  fi
  set +e
  out="$($runner_cmd 2>/dev/null)"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    emit_gate "tests" "false" "runner exited rc=$rc"
    return 0
  fi

  parse_line="$(printf '%s' "$out" | python3 -c \
    'import sys,json
raw=sys.stdin.read().strip()
if not raw:
    print("parse_ok=false verdict=null not_applicable=false")
    sys.exit(0)
v=None
na=False
parsed=False
for line in raw.splitlines():
    line=line.strip()
    if not line.startswith("{"):
        continue
    try:
        d=json.loads(line)
    except Exception:
        continue
    parsed=True
    if "tests_pass" in d:
        v=d.get("tests_pass")
    if d.get("not_applicable") is True:
        na=True
if not parsed:
    print("parse_ok=false verdict=null not_applicable=false")
elif v is True:
    print("parse_ok=true verdict=true not_applicable=%s" % ("true" if na else "false"))
elif v is False:
    print("parse_ok=true verdict=false not_applicable=%s" % ("true" if na else "false"))
else:
    print("parse_ok=true verdict=null not_applicable=%s" % ("true" if na else "false"))' 2>/dev/null || printf 'parse_ok=false verdict=null not_applicable=false')"

  parse_ok="$(printf '%s' "$parse_line" | awk '{for(i=1;i<=NF;i++) if($i~/^parse_ok=/) print substr($i,10)}')"
  verdict="$(printf '%s' "$parse_line" | awk '{for(i=1;i<=NF;i++) if($i~/^verdict=/) print substr($i,9)}')"
  not_applicable="$(printf '%s' "$parse_line" | awk '{for(i=1;i<=NF;i++) if($i~/^not_applicable=/) print substr($i,16)}')"

  if [[ "$parse_ok" != "true" ]]; then
    emit_gate "tests" "false" "runner output not valid JSON"
    return 0
  fi
  if [[ "$verdict" == "true" ]]; then
    emit_gate "tests" "true" "tests_pass=true"
    return 0
  fi
  if [[ "$not_applicable" == "true" ]]; then
    printf '[mb-done-gates][WARN] tests gate not_applicable (no stack/runner) — treated as PASS\n' >&2
    emit_gate "tests" "true" "not_applicable (WARN)"
    return 0
  fi
  if [[ "$verdict" == "null" ]]; then
    emit_gate "tests" "false" "tests_pass=null without not_applicable"
    return 0
  fi
  emit_gate "tests" "false" "tests_pass=false"
}

# ---- gate 2: rules (deterministic) ------------------------------------------

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

# ---- verdict (only REQUIRED gate failures block) ----
gate_to_required_name() {
  case "$1" in
    tests)        printf 'tests_pass' ;;
    rules)        printf 'no_critical_violations' ;;
    placeholders) printf 'no_placeholders' ;;
    *)            printf '%s' "$1" ;;
  esac
}

is_required() {
  local req_name="$1"
  local IFS=,
  local r
  for r in $REQUIRED_CSV; do
    [[ "${r// /}" == "$req_name" ]] && return 0
  done
  return 1
}

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
