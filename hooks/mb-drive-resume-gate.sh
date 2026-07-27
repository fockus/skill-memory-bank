#!/usr/bin/env bash
# mb-drive-resume-gate.sh — Claude Code Stop-hook resume-gate for the drive
# loop (drive-loop Task 4, REQ-DR-032; design ADR-5).
#
# WHAT IT DOES
#   When a drive loop is running (`mb-drive-stop.sh arm`), a stop is only
#   legitimate if the goal is done or a stop condition fired. This hook blocks
#   any other stop, so the loop resumes instead of ending early. On every other
#   session it is completely INERT.
#
# COST CONTRACT (backlog I-131 — the reason this is NOT folded into
# hooks/mb-flow-closure-guard.sh)
#   The decision is made by READING FILES ONLY: the drive-state slot, the
#   `mb-flow` fence, the work-state slot, and goal.md through
#   scripts/mb-goal-acceptance.sh (a single-file parse). It NEVER runs
#   mb-flow-verify.sh, a test battery, or an LLM. The closure guard does run
#   the full firewall on every Stop, which wedges a session for minutes on a
#   large repo; this hook must never repeat that. A bats test greps this file
#   to keep the constraint honest, and a second one poisons the firewall to
#   prove a blocking decision never invokes it.
#
# CC Stop-hook contract (mirrors mb-flow-closure-guard.sh)
#   - JSON object on STDIN (fields incl. `stop_hook_active`, `cwd`).
#   - BLOCK: print {"decision":"block","reason":"<text>"} on stdout, exit 0.
#   - ALLOW: exit 0 with no decision.
#   - LOOP-GUARD: `stop_hook_active: true` means the host is RE-entering after
#     a prior block — allow immediately, or the session wedges in a stop loop.
#
# DECISION (first match wins; every branch but the last ALLOWS)
#   1. kill-switch MB_DRIVE_RESUME_GATE=off, or the re-entry sentinel  -> allow
#   2. unparseable stdin / not a JSON object                            -> allow
#   3. stop_hook_active                                                 -> allow
#   4. no bank / no goal.md                                             -> allow
#   5. no drive armed for this run (status != driving)                  -> allow
#   6. this run already recorded a stop (stop_reason set)               -> allow
#   7. a stop_reason in the mb-flow fence (singleton mode only, see below) -> allow
#   8. acceptance 100% (goal done) or unmeasurable (no criteria)        -> allow
#   9. work-state cycle >= max_cycles (the max-cycle stop condition)    -> allow
#  10. otherwise: goal not done AND no stop condition                   -> BLOCK
#
# RUN SCOPING (REQ-DR-034)
#   Under MB_WORK_PARALLEL=1 the drive state is keyed per run
#   (<bank>/.drive-state/<run_id>.json, reusing I-094's dirs) and $MB_WORK_RUN_ID
#   selects it. The `mb-flow` fence, by contrast, is bank-global: a parallel
#   sibling's stop reason lives in the same fence. Consulting it in a run-scoped
#   context would let run A's stop release run B — exactly the cross-run
#   contamination REQ-DR-034 forbids. So step 7 applies ONLY in singleton mode;
#   when a run_id is in play the per-run slot is the sole authority.
#
# HOOKLESS HOSTS (design ADR-5)
#   Pi/Codex/OpenCode expose no Stop event, so this gate cannot exist there.
#   The contract degrades honestly in two layers: (a) the `/mb drive` loop
#   contract in AGENTS.md tells the agent not to stop early, and (b)
#   adapters/git-hooks-fallback.sh catches the observable symptom at commit
#   time — a false "done" with no commit is caught by the pre-commit closure
#   guard on the next commit (dynamic-flow REQ-DF-062). Belt-and-suspenders,
#   no daemon; a killed drive resumes for free because all state is in files.
#
# FAIL-SAFE
#   ANY infrastructure problem (empty/garbage stdin, missing jq AND python3,
#   missing/corrupt state, missing acceptance helper, an acceptance run that
#   times out) resolves to ALLOW. A gate that cannot prove a drive is live must
#   never hold a session hostage.

set -u

# Re-entry sentinel (mirrors mb-session-turn.sh / mb-flow-closure-guard.sh).
[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && exit 0

allow() {
  exit 0
}

# Emit the CC block JSON (a block is still exit 0).
block() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
  else
    local esc="$reason"
    esc="${esc//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    printf '{"decision":"block","reason":"%s"}\n' "$esc"
  fi
  exit 0
}

# Kill-switch (I-131 defect (b): a Stop-path hook must be disable-able).
case "${MB_DRIVE_RESUME_GATE:-}" in
  off|OFF|0|false|FALSE|no|NO) allow ;;
  *) : ;;
esac

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || allow

# Global-aware bank resolver + skill-script locator.
if [ -f "$HOOK_DIR/_skill_root.sh" ]; then
  # shellcheck source=hooks/_skill_root.sh
  . "$HOOK_DIR/_skill_root.sh"
fi

# ---------------------------------------------------------------------------
# Parse stdin. Empty / non-object → allow BEFORE any path resolution, so a
# parse failure can never drive a decision off $PWD.
# ---------------------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"

STOP_ACTIVE="false"
CWD=""
PARSE_OK="false"

if [ -n "$INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    if printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
      PARSE_OK="true"
      STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
      CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    # A heredoc nested in $(...) mis-parses on /bin/bash 3.2 — route through a
    # temp file (same gotcha the firewall and the closure guard document).
    _pjson="$(mktemp 2>/dev/null || echo "/tmp/mb-drive-gate-parse.$$")"
    MB_GATE_INPUT="$INPUT" python3 - >"$_pjson" 2>/dev/null <<'PY' || true
import json
import os

try:
    obj = json.loads(os.environ.get("MB_GATE_INPUT", ""))
    if not isinstance(obj, dict):
        raise ValueError
except Exception:
    print("FAIL\t")
else:
    active = "true" if obj.get("stop_hook_active") is True else "false"
    print("OK\t" + active + "\t" + (obj.get("cwd") or ""))
PY
    _parsed="$(head -n1 "$_pjson" 2>/dev/null || true)"
    rm -f "$_pjson"
    case "$_parsed" in
      OK*)
        PARSE_OK="true"
        _rest="${_parsed#OK	}"
        STOP_ACTIVE="${_rest%%	*}"
        CWD="${_rest#*	}"
        [ "$STOP_ACTIVE" = "true" ] || STOP_ACTIVE="false"
        ;;
      *) PARSE_OK="false" ;;
    esac
  fi
fi

[ "$PARSE_OK" = "true" ] || allow

# LOOP-GUARD: a re-entrant Stop must ALWAYS allow.
[ "$STOP_ACTIVE" = "true" ] && allow

[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

# ---------------------------------------------------------------------------
# Resolve the bank (MB_PATH → <cwd>/.memory-bank → registry).
# ---------------------------------------------------------------------------
BANK=""
if command -v mb_hook_resolve_mb_path >/dev/null 2>&1; then
  BANK="$(mb_hook_resolve_mb_path "$CWD" 2>/dev/null || true)"
else
  if [ -n "${MB_PATH:-}" ]; then
    BANK="$MB_PATH"
  elif [ -d "$CWD/.memory-bank" ]; then
    BANK="$CWD/.memory-bank"
  fi
fi

[ -n "$BANK" ] || allow
[ -d "$BANK" ] || allow
[ -f "$BANK/goal.md" ] || allow

# ---------------------------------------------------------------------------
# Slot resolution reuses the I-094 helper family (mbw_drive_slot /
# mbw_state_slot / mbw_read_field) so drive state is keyed exactly like
# work-state and budget. If the lib is unreachable, fail safe: allow.
# ---------------------------------------------------------------------------
SLOTS_LIB="$HOOK_DIR/../scripts/mb-work-slots.sh"
if [ ! -f "$SLOTS_LIB" ] && command -v mb_skill_script_path >/dev/null 2>&1; then
  _resolved="$(mb_skill_script_path "mb-work-slots.sh" "$HOOK_DIR" 2>/dev/null || true)"
  [ -n "$_resolved" ] && SLOTS_LIB="$_resolved"
fi
[ -f "$SLOTS_LIB" ] || allow
# shellcheck source=scripts/mb-work-slots.sh
. "$SLOTS_LIB" 2>/dev/null || allow
command -v mbw_drive_slot >/dev/null 2>&1 || allow

RUN_ID="${MB_WORK_RUN_ID:-}"
DRIVE_SLOT="$(mbw_drive_slot "$BANK" "$RUN_ID" 2>/dev/null || true)"
[ -n "$DRIVE_SLOT" ] || allow
[ -f "$DRIVE_SLOT" ] || allow   # no drive armed for this run → inert

# Armed predicate: a corrupt/unreadable slot reads as "" → not armed → allow.
DRIVE_STATUS="$(mbw_read_field "$DRIVE_SLOT" "status" 2>/dev/null || true)"
[ "$DRIVE_STATUS" = "driving" ] || allow

# This run already recorded a stop → the loop ended legitimately.
DRIVE_REASON="$(mbw_read_field "$DRIVE_SLOT" "stop_reason" 2>/dev/null || true)"
[ -z "$DRIVE_REASON" ] || allow

# ---------------------------------------------------------------------------
# The bank-global `mb-flow` fence. Singleton mode ONLY (see § RUN SCOPING):
# under a run_id this field may belong to a parallel sibling.
# ---------------------------------------------------------------------------
if [ -z "$RUN_ID" ] && [ -f "$BANK/status.md" ]; then
  FENCE_REASON="$(grep -m1 '^stop_reason: ' "$BANK/status.md" 2>/dev/null || true)"
  FENCE_REASON="${FENCE_REASON#stop_reason: }"
  case "$FENCE_REASON" in
    ''|'-') : ;;
    *) allow ;;
  esac
fi

# ---------------------------------------------------------------------------
# Acceptance — a single-file parse of goal.md, wrapped in a hard timeout so a
# pathological goal.md can never wedge the Stop path (I-131 defect (c)).
# ---------------------------------------------------------------------------
ACCEPT_BIN="${MB_GOAL_ACCEPTANCE_BIN:-$HOOK_DIR/../scripts/mb-goal-acceptance.sh}"
# An EXPLICIT override wins outright: re-resolving it through the skill-root
# locator would silently defeat the seam (and any deliberate isolation).
if [ -z "${MB_GOAL_ACCEPTANCE_BIN:-}" ] && [ ! -f "$ACCEPT_BIN" ] &&
  command -v mb_skill_script_path >/dev/null 2>&1; then
  _resolved="$(mb_skill_script_path "mb-goal-acceptance.sh" "$HOOK_DIR" 2>/dev/null || true)"
  [ -n "$_resolved" ] && ACCEPT_BIN="$_resolved"
fi
[ -f "$ACCEPT_BIN" ] || allow

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

if [ -n "$TIMEOUT_BIN" ]; then
  ACCEPT_JSON="$("$TIMEOUT_BIN" "${MB_DRIVE_GATE_TIMEOUT:-10}" bash "$ACCEPT_BIN" "" "$BANK" 2>/dev/null || true)"
else
  ACCEPT_JSON="$(bash "$ACCEPT_BIN" "" "$BANK" 2>/dev/null || true)"
fi

# ok=true → goal done · ok=null → nothing measurable · anything unparseable →
# cannot prove the goal is unfinished. All three allow; only an explicit
# ok=false means "not done".
case "$ACCEPT_JSON" in
  *'"ok":false'*|*'"ok": false'*) : ;;
  *) allow ;;
esac

# ---------------------------------------------------------------------------
# Cheap stop conditions from the durable work-state slot (already run-keyed).
# max_cycles exhaustion IS a stop condition — the loop is allowed to end there.
# ---------------------------------------------------------------------------
STATE_SLOT="$(mbw_state_slot "$BANK" "$RUN_ID" 2>/dev/null || true)"
if [ -n "$STATE_SLOT" ] && [ -f "$STATE_SLOT" ]; then
  CYCLE="$(mbw_read_field "$STATE_SLOT" "cycle" 2>/dev/null || true)"
  MAXC="$(mbw_read_field "$STATE_SLOT" "max_cycles" 2>/dev/null || true)"
  case "$CYCLE" in ''|*[!0-9]*) CYCLE="" ;; esac
  case "$MAXC" in ''|*[!0-9]*) MAXC="" ;; esac
  if [ -n "$CYCLE" ] && [ -n "$MAXC" ] && [ "$CYCLE" -ge "$MAXC" ]; then
    allow
  fi
fi

# ---------------------------------------------------------------------------
# Nothing released the loop: the goal is not done and no stop condition fired.
# ---------------------------------------------------------------------------
block "Drive-loop resume-gate: the goal is NOT done (acceptance criteria remain unchecked) and no stop condition fired — this stop is premature (REQ-DR-032). Call \`scripts/mb-drive.sh next --bank <bank>\` and execute the action it returns; keep looping until it prints a stop_* action. If you are ending deliberately, record it first with \`scripts/mb-drive-stop.sh record --bank <bank> --action \"<the stop_* action>\"\`."
