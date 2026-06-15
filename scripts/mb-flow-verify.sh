#!/usr/bin/env bash
# mb-flow-verify.sh — THE firewall fan-out (dynamic-flow Task 5).
#
# The SOLE exit-code authority of the dynamic-flow firewall. It runs the
# route-relevant check runners, normalizes each runner's verdict into severity
# counts {blocker, major, minor}, hands those counts to the existing
# mb-work-severity-gate.sh comparator (the SSOT — severity logic is NEVER
# reimplemented here), and propagates 0/1/2 as ITS OWN exit code.
#
# Why a single exit-code authority (design ADR-3): the check runners
# (mb-lint-run.sh, mb-no-todo.sh, mb-diff-scope.sh, mb-goal-acceptance.sh,
# mb-test-run.sh, ...) are contracted to ALWAYS exit 0 and report pass/fail/skip
# ONLY through a JSON `ok` field. If we cloned that "exit 0" pattern in the
# firewall, a red check would return exit 0 and defeat the firewall. So the
# fan-out parses their JSON and OWNS the non-zero exit.
#
# Exit codes (REQ-DF-041 — test this trichotomy exhaustively):
#   exit 0  PASS  — every check is green (ok:true) or skipped (ok:null) AND the
#              severity-gate passes.
#   exit 1  FAIL  — at least one check is a CLEAN red (exit 0 + valid JSON + ok:false)
#              that raised the counts and the gate fails. stdout NAMES every
#              breaching check + its findings so the agent's repair-loop knows
#              what to fix (REQ-DF-044/060). A red result NEVER prints a
#              done/success signal.
#   exit 2  BROKE — a check SCRIPT ITSELF broke: it exited non-zero (a runner is
#              contracted to exit 0, so non-zero == it crashed), was missing,
#              or emitted output that is not a parseable JSON object carrying an
#              `ok` field. This is DISTINCT from a clean ok:false (which is exit 1).
#              broke (exit 2) DOMINATES a clean fail (exit 1) which dominates pass
#              (exit 0): a broken check is the loudest failure and is never
#              collapsed to exit 1 and certainly never swallowed as exit 0.
#
# Severity mapping (check name → severity when ok:false; conservative — under-
# counting a real breach is the worst outcome, so when in doubt escalate):
#   acceptance  → blocker   (the deterministic termination condition is unmet — REQ-DF-024)
#   tests       → blocker   (red tests mean the work is NOT done)
#   diff_scope  → blocker   (ADR-4 backstop: an out-of-scope/surgical-arch change is the
#                            most dangerous under-escalation case)
#   protected   → blocker   (a protected-path breach)
#   rules       → major     (a deterministic engineering-rule violation)
#   lint        → major     (a style/static-analysis finding)
#   no_todo     → major     (a residual placeholder shipped in code — conservative)
#   <other>     → major     (unknown check that reports red still MUST count; never 0)
#   A check that returns ok:null (skip) contributes ZERO to all counts.
#   A check that returns ok:true contributes ZERO to all counts.
#   build resolves to SKIP and is never run (REQ-DF-043 — no local build runner).
#
# Usage:
#   mb-flow-verify.sh [mb_path] [--phase <p>]
#                     [--check 'name=command ...'] ...
#                     [--workflow <name>] [--gate <json>]
#
#   mb_path        : Memory Bank path (default via _lib.sh::mb_resolve_path).
#   --phase  <p>   : route phase, informational/selection only (no router yet —
#                    Phase 2). Recorded in the summary; does not change the gate.
#   --check  'n=c' : run command `c` as check `n` instead of the default set.
#                    Repeatable. The default set (see below) is used when NO
#                    --check is given. Lets callers/tests drive the fan-out
#                    deterministically.
#   --workflow <n> : forwarded to mb-work-severity-gate.sh (gate selection).
#   --gate   <json>: forwarded to mb-work-severity-gate.sh (override the limits).
#
# Default check set (Phase 1 — no router, a sensible parameterizable default):
#   tests      → mb-test-run.sh        (wrapped: tests_pass → ok)
#   lint       → mb-lint-run.sh
#   no_todo    → mb-no-todo.sh
#   diff_scope → mb-diff-scope.sh      (ok:null unless a scope is configured)
#   acceptance → mb-goal-acceptance.sh
#   (build is intentionally absent — REQ-DF-043.)
#
# Output: a single structured JSON summary on stdout REGARDLESS of exit code —
#   { "phase": <p|null>,
#     "checks": [ {"name","ok","severity","findings","status"} ... ],
#     "totals": {"blocker":N,"major":N,"minor":N},
#     "gate": "PASS"|"FAIL",
#     "verdict": "pass"|"fail"|"broke" }
#   On a non-zero exit the breaches are ALSO named on stderr.
#
# Portability: POSIX/bash + _lib.sh; no new third-party runtime deps. bash-3.2
#   safe (guards empty-array expansion under set -u). Each check's exit code and
#   stdout are captured explicitly so a red/broken check can never abort the
#   fan-out before it is mapped (set -e is not allowed to swallow the verdict).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Injectable for tests; defaults to the real SSOT gate. The gate is contracted
# to return ONLY 0 (pass) / 1 (fail) / 2 (its own usage error); any OTHER code
# (e.g. 127 missing, a crash) means the gate itself broke → we treat as broke.
SEVERITY_GATE="${MB_SEVERITY_GATE:-$SCRIPT_DIR/mb-work-severity-gate.sh}"

usage() {
  sed -n '2,90p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# Arg parse
# ---------------------------------------------------------------------------
MB_ARG=""
PHASE=""
WORKFLOW_NAME=""
GATE_JSON=""
# Parallel arrays: CHECK_NAMES[i] ↔ CHECK_CMDS[i]. Populated by --check; left
# empty → the default set is assembled later.
CHECK_NAMES=()
CHECK_CMDS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --phase)
      [ "$#" -ge 2 ] || { printf '[mb-flow-verify] --phase needs a value\n' >&2; exit 2; }
      PHASE="$2"; shift 2
      ;;
    --phase=*) PHASE="${1#--phase=}"; shift ;;
    --workflow)
      [ "$#" -ge 2 ] || { printf '[mb-flow-verify] --workflow needs a value\n' >&2; exit 2; }
      WORKFLOW_NAME="$2"; shift 2
      ;;
    --workflow=*) WORKFLOW_NAME="${1#--workflow=}"; shift ;;
    --gate)
      [ "$#" -ge 2 ] || { printf '[mb-flow-verify] --gate needs a value\n' >&2; exit 2; }
      GATE_JSON="$2"; shift 2
      ;;
    --gate=*) GATE_JSON="${1#--gate=}"; shift ;;
    --check)
      [ "$#" -ge 2 ] || { printf '[mb-flow-verify] --check needs a value\n' >&2; exit 2; }
      _spec="$2"; shift 2
      case "$_spec" in
        *=*) : ;;
        *) printf '[mb-flow-verify] --check must be name=command, got: %s\n' "$_spec" >&2; exit 2 ;;
      esac
      CHECK_NAMES+=("${_spec%%=*}")
      CHECK_CMDS+=("${_spec#*=}")
      ;;
    --check=*)
      _spec="${1#--check=}"; shift
      case "$_spec" in
        *=*) : ;;
        *) printf '[mb-flow-verify] --check must be name=command, got: %s\n' "$_spec" >&2; exit 2 ;;
      esac
      CHECK_NAMES+=("${_spec%%=*}")
      CHECK_CMDS+=("${_spec#*=}")
      ;;
    --)
      shift
      ;;
    -*)
      printf '[mb-flow-verify] unknown flag: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -z "$MB_ARG" ]; then
        MB_ARG="$1"
      else
        printf '[mb-flow-verify] unexpected argument: %s\n' "$1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

MB_PATH="$(mb_resolve_path "$MB_ARG")"

# The default checks (lint, no_todo, diff_scope) must inspect the TARGET project,
# not whatever cwd the firewall was invoked from — else a real breach in the repo
# is silently missed and the firewall false-PASSes. Resolve the project root once.
#
# For a LOCAL bank (<project>/.memory-bank) the parent IS the project root. For a
# GLOBAL-storage bank the resolver returns an external registry path whose parent
# is NOT the repo; the real repo path is recorded as `project_root=` in the bank's
# `.mb-config` (written by mb-init-bank.sh). Honor that first, then fall back.
PROJECT_ROOT=""
_mb_cfg="$MB_PATH/.mb-config"
if [ -f "$_mb_cfg" ]; then
  # A LOCAL bank's .mb-config carries only storage_mode/lang (no project_root), so
  # the grep MUST be non-fatal: under `set -euo pipefail` a no-match (grep→1) would
  # otherwise abort the firewall before it can emit any verdict. `|| true` keeps it
  # an empty-string lookup that simply falls through to the parent-dir derivation.
  _cfg_root="$(grep '^project_root=' "$_mb_cfg" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  if [ -n "$_cfg_root" ] && [ -d "$_cfg_root" ]; then
    PROJECT_ROOT="$(cd "$_cfg_root" && pwd)"
  fi
fi
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(cd "$MB_PATH/.." 2>/dev/null && pwd)"
  [ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$MB_PATH/.."
fi

# ---------------------------------------------------------------------------
# Adapter: mb-test-run.sh is a REUSED existing check (REQ-DF-042) whose JSON
# carries `tests_pass` (true|false|null), NOT the {name,ok,findings} runner
# shape. Normalize it here so the fan-out sees one uniform contract:
#   tests_pass true  → ok:true   tests_pass false → ok:false (findings=failures)
#   tests_pass null  → ok:null (no tests / unsupported stack → skip).
# Stays exit-0 itself; the fan-out owns the exit code (ADR-3).
#
# Eval-safe shell-quote. The default check strings are re-parsed by `eval`, so
# each interpolated path must survive a SECOND parse as a literal. `printf %q`
# escapes spaces/`$`/backticks/backslashes/`"`, but on /bin/bash 3.2 (macOS) it
# leaves a LEADING `~` unescaped — and eval tilde-expands a leading `~` to $HOME,
# which would silently retarget a check at the wrong path. Backslash-prefix a
# leading tilde so eval keeps it literal. (bash 5.x already emits `\~`, which
# starts with `\` not `~`, so the guard is a no-op there — never double-escapes.)
# shellcheck disable=SC2329
_shq() {
  local q
  q="$(printf '%q' "$1")"
  case "$q" in
    '~'*) q="\\$q" ;;
  esac
  printf '%s' "$q"
}

# Invoked indirectly through `eval` in the default check set (shellcheck can't
# see that call site).
# shellcheck disable=SC2329
_flow_tests_check() {
  local dir="$1" raw rc
  # mb-test-run.sh ALWAYS exits 0 for any test OUTCOME (pass/fail/no-tests — the
  # verdict rides in `tests_pass`). A non-zero exit therefore means it crashed,
  # is missing (→127), or hit a usage error → the check itself BROKE. Do NOT
  # `|| true` that away: swallowing it would mis-report a broken test runner as
  # a clean skip and let the firewall exit 0 (violates ADR-3 / REQ-DF-060).
  raw="$("${MB_TEST_RUN_BIN:-$SCRIPT_DIR/mb-test-run.sh}" --dir "$dir" --out json 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    return 2
  fi
  MB_TESTRUN_JSON="$raw" python3 - <<'PY'
import json
import os
import sys

raw = os.environ.get("MB_TESTRUN_JSON", "")
try:
    obj = json.loads(raw)
except Exception:
    obj = None
# A malformed / non-object payload, one missing `tests_pass`, or a tests_pass
# that is not exactly true/false/null means the reused runner malfunctioned →
# BROKE (exit 2), NOT a clean skip. Only a valid tests_pass:null is a skip.
if not isinstance(obj, dict) or "tests_pass" not in obj:
    sys.stderr.write("[mb-flow-verify] tests adapter: mb-test-run.sh output is not a JSON object carrying tests_pass\n")
    sys.exit(2)
tp = obj.get("tests_pass")
findings = []
if tp is True:
    ok = "true"
elif tp is False:
    ok = "false"
    for f in obj.get("failures") or []:
        nm = f.get("name") or ""
        fl = f.get("file") or ""
        head = f.get("error_head") or ""
        findings.append(f"{fl}::{nm} — {head}".strip())
    if not findings:
        failed = obj.get("tests_failed")
        findings.append(f"{failed} test(s) failed" if failed else "tests failed")
elif tp is None:
    ok = "null"
else:
    sys.stderr.write("[mb-flow-verify] tests adapter: tests_pass must be true/false/null\n")
    sys.exit(2)
parts = []
for f in findings:
    parts.append(json.dumps(f))
print('{"name":"tests","ok":%s,"findings":[%s]}' % (ok, ",".join(parts)))
PY
}

# ---------------------------------------------------------------------------
# Default check set — used only when the caller passed NO --check.
# Each command emits the canonical runner JSON {name, ok, findings} and exits 0.
# build is deliberately absent (REQ-DF-043 — build resolves to skip).
# ---------------------------------------------------------------------------
if [ "${#CHECK_NAMES[@]}" -eq 0 ]; then
  CHECK_NAMES=( tests lint no_todo diff_scope acceptance )
  # Every check is scoped to the bank's project root (PROJECT_ROOT), never the
  # caller's cwd. lint/diff_scope take an explicit dir flag; no_todo keeps its
  # git-diff semantics so it must RUN from the project root (a subshell cd).
  #
  # These strings are re-parsed by `eval` in the fan-out, so EVERY interpolated
  # path is run through `_shq` first. Plain double-quoting only stops word
  # splitting; `_shq` (printf %q + a leading-tilde guard) additionally neutralizes
  # `$`, backticks, backslashes, `"` AND a leading `~`, so an install/repo/bank
  # path with ANY shell metacharacter survives the second parse as a literal.
  _q_pr="$(_shq "$PROJECT_ROOT")"
  _q_mb="$(_shq "$MB_PATH")"
  _q_lint="$(_shq "$SCRIPT_DIR/mb-lint-run.sh")"
  _q_todo="$(_shq "$SCRIPT_DIR/mb-no-todo.sh")"
  _q_scope="$(_shq "$SCRIPT_DIR/mb-diff-scope.sh")"
  _q_accept="$(_shq "$SCRIPT_DIR/mb-goal-acceptance.sh")"
  CHECK_CMDS=(
    "_flow_tests_check $_q_pr"
    "bash $_q_lint --dir $_q_pr"
    "( cd $_q_pr && bash $_q_todo )"
    "bash $_q_scope --repo $_q_pr"
    "bash $_q_accept '' $_q_mb"
  )
fi

# ---------------------------------------------------------------------------
# Fan out: run each check, capturing BOTH its exit code and stdout. set -e must
# NOT abort the fan-out when a check exits non-zero — we map that to BROKE.
# Each per-check record is written as one line to a temp file:
#   <name>\t<exit>\t<stdout-base64>
# (base64 keeps arbitrary/multiline check output on a single record line).
# ---------------------------------------------------------------------------
RECORDS="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$RECORDS'" EXIT

b64() {
  # Portable single-line base64 (macOS `base64` wraps at 76 cols; -w0 is GNU).
  if base64 -w0 </dev/null >/dev/null 2>&1; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

i=0
n="${#CHECK_NAMES[@]}"
while [ "$i" -lt "$n" ]; do
  name="${CHECK_NAMES[$i]}"
  cmd="${CHECK_CMDS[$i]}"
  out_tmp="$(mktemp)"
  # Capture exit code without tripping set -e; capture stdout (stderr → /dev/null
  # so a runner's diagnostic WARNs don't pollute the parsed JSON). The eval runs
  # in a SUBSHELL so a check that calls `exit`/`set -e` inline can never hijack
  # this firewall's own 0/1/2 exit-code authority — only the subshell's status
  # escapes (captured as rc → broke), exactly like a child process exiting.
  set +e
  ( eval "$cmd" ) >"$out_tmp" 2>/dev/null
  rc=$?
  set -e
  enc="$(b64 <"$out_tmp")"
  rm -f "$out_tmp"
  printf '%s\t%s\t%s\n' "$name" "$rc" "$enc" >>"$RECORDS"
  i=$((i + 1))
done

# ---------------------------------------------------------------------------
# Normalize + aggregate (Python: robust JSON parse). Writes to a temp file (NOT
# captured via $(...) — bash 3.2 mis-parses apostrophes in a quoted heredoc body
# nested inside command substitution; a temp file sidesteps that entirely).
# Emitted lines:
#   line 1 : the structured JSON summary (totals + per-check) — minus gate/verdict
#   then   : control lines  BROKE\t...  COUNTS\t...  BREACHES\t...
# A "broke" verdict short-circuits the gate (the firewall already failed loud).
# Counts go to the severity-gate (the SSOT) which decides pass/fail.
# ---------------------------------------------------------------------------
AGG_OUT="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$RECORDS' '$AGG_OUT'" EXIT
MB_PHASE="$PHASE" python3 - "$RECORDS" >"$AGG_OUT" <<'PY'
import base64
import json
import os
import sys

records_path = sys.argv[1]
phase = os.environ.get("MB_PHASE", "") or None

# check name → severity bucket when ok:false. Conservative: unknown → major.
SEVERITY = {
    "acceptance": "blocker",
    "tests": "blocker",
    "diff_scope": "blocker",
    "protected": "blocker",
    "rules": "major",
    "lint": "major",
    "no_todo": "major",
}

totals = {"blocker": 0, "major": 0, "minor": 0}
checks = []
broke = []          # names of checks whose SCRIPT broke
breaches = []       # human-readable "name: finding" lines for a clean red

with open(records_path, encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.rstrip("\n")
        if not raw:
            continue
        parts = raw.split("\t", 2)
        name = parts[0]
        rc = parts[1] if len(parts) > 1 else "0"
        enc = parts[2] if len(parts) > 2 else ""
        try:
            stdout = base64.b64decode(enc).decode("utf-8", "replace") if enc else ""
        except Exception:
            stdout = ""

        # --- BROKE detection (ADR-3 distinction) -----------------------------
        # 1. Non-zero exit: a runner is contracted to ALWAYS exit 0, so any
        #    non-zero exit (crash, missing command → 127, timeout) is a broke.
        try:
            rc_int = int(rc)
        except ValueError:
            rc_int = 1
        if rc_int != 0:
            broke.append(name)
            checks.append({
                "name": name, "ok": None, "severity": None,
                "findings": [], "status": "broke",
                "detail": f"check exited {rc_int} (runners must exit 0)",
            })
            continue

        # 2. Unparseable / non-object / missing `ok`: the runner's output is not
        #    a valid verdict → the script is malfunctioning, not cleanly red.
        obj = None
        try:
            obj = json.loads(stdout)
        except (ValueError, json.JSONDecodeError):
            obj = None
        if not isinstance(obj, dict) or "ok" not in obj:
            broke.append(name)
            checks.append({
                "name": name, "ok": None, "severity": None,
                "findings": [], "status": "broke",
                "detail": "output is not a JSON object carrying an `ok` field",
            })
            continue

        ok = obj.get("ok")
        findings = obj.get("findings") or []
        if not isinstance(findings, list):
            findings = [str(findings)]

        # --- clean verdicts --------------------------------------------------
        if ok is True:
            checks.append({
                "name": name, "ok": True, "severity": None,
                "findings": [], "status": "pass",
            })
        elif ok is None:
            # skip / N/A → contributes ZERO to all counts.
            checks.append({
                "name": name, "ok": None, "severity": None,
                "findings": [], "status": "skip",
            })
        elif ok is False:
            sev = SEVERITY.get(name, "major")
            totals[sev] += 1
            checks.append({
                "name": name, "ok": False, "severity": sev,
                "findings": findings, "status": "fail",
            })
            if findings:
                for f in findings:
                    breaches.append(f"{name}: {f}")
            else:
                breaches.append(f"{name}: (red, no finding text)")
        else:
            # `ok` present but not one of true/false/null → malformed verdict.
            broke.append(name)
            checks.append({
                "name": name, "ok": None, "severity": None,
                "findings": [], "status": "broke",
                "detail": f"`ok` must be true/false/null, got {ok!r}",
            })

summary = {
    "phase": phase,
    "checks": checks,
    "totals": totals,
}

# The summary JSON is what callers introspect (printed regardless of exit code).
print(json.dumps(summary, separators=(",", ":")))

# Control channel for the shell, on its own lines.
if broke:
    print("BROKE\t" + "|".join(broke))
    # Name the broken checks on stderr too.
    for b in broke:
        sys.stderr.write(f"[mb-flow-verify] BROKE: check '{b}' malfunctioned (not a clean fail)\n")
else:
    print("BROKE\t")

print("COUNTS\t" + json.dumps(totals, separators=(",", ":")))

if breaches:
    print("BREACHES\t" + "\x1f".join(breaches))
    for line in breaches:
        sys.stderr.write(f"[mb-flow-verify] FAIL: {line}\n")
else:
    print("BREACHES\t")
PY

# Split the aggregator output into the summary line + control lines.
SUMMARY_JSON="$(sed -n '1p' "$AGG_OUT")"
BROKE_LINE="$(grep '^BROKE	' "$AGG_OUT" | head -n1 || true)"
COUNTS_LINE="$(grep '^COUNTS	' "$AGG_OUT" | head -n1 || true)"
BREACH_LINE="$(grep '^BREACHES	' "$AGG_OUT" | head -n1 || true)"

BROKE_NAMES="${BROKE_LINE#BROKE	}"
COUNTS_JSON="${COUNTS_LINE#COUNTS	}"
BREACHES="${BREACH_LINE#BREACHES	}"
[ -z "$COUNTS_JSON" ] && COUNTS_JSON='{"blocker":0,"major":0,"minor":0}'

# ---------------------------------------------------------------------------
# Exit-code authority. broke (2) DOMINATES fail (1) DOMINATES pass (0).
# ---------------------------------------------------------------------------
emit_summary() {
  # Append the final gate/verdict to the summary JSON so callers see one object.
  # SUMMARY_JSON is passed via the environment (NOT a pipe): `python3 - <<PY`
  # already reads its PROGRAM from stdin, so the data must not also come from a
  # pipe (the two would collide).
  local gate="$1" verdict="$2"
  MB_SUMMARY_JSON="$SUMMARY_JSON" python3 - "$gate" "$verdict" <<'PY'
import json
import os
import sys

obj = json.loads(os.environ["MB_SUMMARY_JSON"])
obj["gate"] = sys.argv[1]
obj["verdict"] = sys.argv[2]
print(json.dumps(obj, separators=(",", ":")))
PY
}

# 2 — a check script itself broke. Loudest failure: never collapse to 1/0.
if [ -n "$BROKE_NAMES" ]; then
  emit_summary "FAIL" "broke"
  printf '[mb-flow-verify] BROKE: %s — a check script malfunctioned; cannot certify.\n' \
    "$(printf '%s' "$BROKE_NAMES" | tr '|' ' ')" >&2
  exit 2
fi

# All checks reported cleanly → delegate the severity ARITHMETIC to the SSOT gate.
# BUT the firewall is its OWN exit authority — NOT an opt-in code review. The
# work-loop severity-gate treats a bank whose resolved pipeline.yaml declares no
# `review.severity_gate` as a PASS no-op (review is opt-in), so it would map a
# clean red (a check raised blocker/major) to exit 0 — the EXACT failure the
# firewall exists to prevent. So unless the caller passed an explicit --gate,
# force a STRICT firewall gate: ANY raised count fails. An explicit --gate still
# wins for callers that deliberately want tolerance.
FW_GATE_JSON="$GATE_JSON"
if [ -z "$FW_GATE_JSON" ]; then
  FW_GATE_JSON='{"blocker":0,"major":0,"minor":0}'
fi
# --ignore-approval: the firewall is a CLOSURE gate, not a code review. It sends
# raw counts with no reviewer verdict, so it must never inherit the work-loop's
# approval_required policy — otherwise an all-green run on a governed bank (whose
# default workflow loop sets approval_required: true) would wrongly fail with
# "verdict=<missing>". The gate still applies the severity ARITHMETIC strictly.
GATE_ARGS=( --counts "$COUNTS_JSON" --mb "$MB_PATH" --gate "$FW_GATE_JSON" --ignore-approval )
[ -n "$WORKFLOW_NAME" ] && GATE_ARGS+=( --workflow "$WORKFLOW_NAME" )

set +e
GATE_OUT="$(bash "$SEVERITY_GATE" "${GATE_ARGS[@]}" 2>&1)"
GATE_RC=$?
set -e

# The severity-gate is contracted to return ONLY 0 (pass) / 1 (fail) / 2 (its own
# usage/parse error). A clean fail is EXACTLY rc==1. Anything else non-zero — a 2
# (gate usage error), a 127 (gate missing), a 126/137 (crash/signal) — means the
# load-bearing gate ITSELF broke; that must surface as broke (exit 2), never be
# mistaken for a clean breach. Only rc==1 maps to a clean red.
if [ "$GATE_RC" -ne 0 ] && [ "$GATE_RC" -ne 1 ]; then
  emit_summary "FAIL" "broke"
  printf '[mb-flow-verify] BROKE: severity-gate malfunctioned (exit %s): %s\n' "$GATE_RC" "$GATE_OUT" >&2
  exit 2
fi

if [ "$GATE_RC" -ne 0 ]; then
  # 1 — clean red. Name every breach so the repair-loop knows what to fix.
  emit_summary "FAIL" "fail"
  if [ -n "$BREACHES" ]; then
    printf '%s\n' "$BREACHES" | tr '\037' '\n' | while IFS= read -r line; do
      [ -n "$line" ] && printf '[mb-flow-verify] breach → %s\n' "$line" >&2
    done
  fi
  printf '%s\n' "$GATE_OUT" >&2
  exit 1
fi

# 0 — pass.
emit_summary "PASS" "pass"
exit 0
