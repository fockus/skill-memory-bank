# shellcheck shell=bash
# mb-work-state-eval.sh — sourced eval-first layer for mb-work-state.sh
# (svp-sdd-core C6, REQ-008). Extracted so every file stays ≤400 lines.
# Not an executable entry point: no shebang, no `main`, no standalone exec
# path. Source it from mb-work-state.sh:
#   # shellcheck source=mb-work-state-eval.sh
#   source "$SCRIPT_DIR/mb-work-state-eval.sh"
#
# Public functions (each is a subcommand body and exits the process itself,
# exactly as it did inline — 0 red/green proven, 1 not proven, 2 usage):
#   cmd_eval_red     --cmd-file <path> --output-re <ERE> [--expected-exit N]
#                    [--run-id ID] [--mb <path>]
#   cmd_eval_green   --cmd-file <path> [--run-id ID] [--mb <path>]
#
# Depends on these helpers from the sourcing script: usage, state_path,
# require_valid_state, is_uint.
#
# The user-facing contract is documented once, in mb-work-state.sh's header
# (the block its `usage` prints) — do not restate it here, it will drift.
# The invariant this file exists to keep: it is the SOLE executor and judge of
# the Eval command, deriving red/green only from an observed run of an
# immutable snapshot, never from a caller-supplied verdict.

# Effective content of a cmd-file: the command lines only — shebang, comments
# and blank lines are formatting. This must equal the declared Eval EXACTLY, so
# a caller cannot smuggle an extra `; exit 0` past the gate.
eval_effective_cmd() {
  CMD_FILE="$1" python3 - <<'PY'
import os, sys
lines = []
for i, ln in enumerate(open(os.environ["CMD_FILE"], encoding="utf-8")):
    s = ln.strip()
    if not s or s.startswith("#"):
        continue
    lines.append(s)
sys.stdout.write("\n".join(lines))
PY
}

# Verifies the cmd-file against the task's declaration; exits 2 on any mismatch
# or when the declaration cannot be resolved (fail closed — an unbound eval gate
# proves nothing).
eval_require_binding() {
  local state="$1" cmd_file="$2" who="$3"
  local bank source_ item_no declared effective
  bank=$(mb_resolve_path "${PARSED_EVAL_MB:-}")
  source_=$(eval_state_field "$state" source)
  item_no=$(eval_state_field "$state" item_no)
  declared=$(eval_declared_cmd "$bank" "$(eval_state_field "$state" source_path)" \
    "$(eval_state_field "$state" source_topic)" "$item_no" "$source_")
  if [ -z "$declared" ]; then
    echo "[work-state] $who: no Eval declaration resolvable for $source_#$item_no (eval gate must be bound to a declared Eval)" >&2
    exit 2
  fi
  effective=$(eval_effective_cmd "$cmd_file")
  if [ "$effective" != "$declared" ]; then
    echo "[work-state] $who: cmd-file does not match the declared Eval for $source_#$item_no" >&2
    exit 2
  fi
}

# Repo root the byte-identical --cmd-file is executed from (git top-level, or
# MB_REPO_ROOT for tests, else the current directory).
eval_run_root() {
  if [ -n "${MB_REPO_ROOT:-}" ]; then
    printf '%s' "$MB_REPO_ROOT"; return
  fi
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$top" ]; then printf '%s' "$top"; else pwd; fi
}

# The proof payload/key lives in scripts/mb_work_eval_proof.py — one definition
# for all call sites (the inlined copies had drifted; green_exit was signed by
# none of them). Honest scope (AGR-026): checksum-grade integrity, NOT
# tamper-proofing — the key sits in the checkout, so anyone who can edit the
# state can forge a signature. It catches casual/accidental hand-editing only.

# ── done gate (review [11]) ───────────────────────────────────────────────
# `done` used to write phase=done unconditionally, so `init` + `done` certified
# a task whose Eval never ran. A task that DECLARES a non-waived Eval may only
# be marked done on a proven red→green transition: a valid helper-owned proof
# (so a hand-edited state is rejected), an observed red, and an actual
# green_exit == 0. Verdicts and their handling:
#
#   CMD    → require the proof above
#   WAIVED → allowed; the spec explicitly waived its Eval
#   NOITEM → refused; the state points at a real tasks.md that lacks this item,
#            i.e. the binding is broken — exactly the round-1 failure mode
#   NOFILE → allowed; a plain plan stage has no declaration surface to gate
# shellcheck disable=SC2034  # MBW_DONE_GATE is consumed by cmd_done (parent file)
eval_require_done_proof() {
  local state="$1"
  local bank verdict item_no source_ live_decl
  bank=$(mb_resolve_path "${PARSED_EVAL_MB:-}")
  item_no=$(eval_state_field "$state" item_no)
  source_=$(eval_state_field "$state" source)

  # Decided on the BOUND snapshot, never a fresh read of the live file (r3 [1]):
  # swapping a real Eval for `none — waiver:` between init and done used to give
  # rc=0 + eval_gate=waived:eval_none with no Eval run. Check: eval_bound_verdict.
  verdict=$(eval_bound_verdict "$state" "$bank" "$item_no" "$source_")

  case "$verdict" in
    UNBOUND)
      echo "[work-state] done: this run predates declaration binding; re-run 'init' so the Eval declaration is bound before certifying" >&2
      exit 5 ;;
    DECLTAMPERED)
      echo "[work-state] done: bound Eval declaration is invalid (state tampered); refusing to certify" >&2
      exit 5 ;;
    DECLCHANGED)
      echo "[work-state] done: the Eval declaration changed since init (command, anchors, waiver status or the file itself); refusing to certify — re-run 'init' if the change is intended" >&2
      exit 5 ;;
  esac

  # MBW_DONE_GATE is the honest record of WHY this done was allowed. `done`
  # writes it into the state and echoes it, so a green done can never again be
  # mistaken for a verified one when it was merely unverifiable (AGR-013).
  case "$verdict" in
    WAIVED) MBW_DONE_GATE="waived:eval_none"; return 0 ;;
    NOFILE) MBW_DONE_GATE="unverified:no_declaration_surface"; return 0 ;;
    NOITEM)
      echo "[work-state] done: task #$item_no not found in the declared source for '$source_' (eval binding broken; refusing to certify)" >&2
      exit 5 ;;
  esac

  local check
  set +e
  check=$(STATE="$state" MB_SD="$SCRIPT_DIR" python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["MB_SD"])
import mb_work_eval_proof as proof
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
e = data.get("eval")
if not isinstance(e, dict) or "sig" not in e:
    print("NOEVAL"); sys.exit(0)
if not proof.verify(e):
    print("TAMPERED"); sys.exit(0)
if not (e.get("red_observed") is True and e.get("red_match") is True):
    print("NORED"); sys.exit(0)
if e.get("green_exit") != 0:
    print("NOGREEN"); sys.exit(0)
print("OK")
PY
)
  set -e
  case "$check" in
    OK) MBW_DONE_GATE="verified:red_green"; return 0 ;;
    NOEVAL)   echo "[work-state] done: task #$item_no declares an Eval that never ran (no eval record; run eval-red then eval-green)" >&2; exit 5 ;;
    TAMPERED) echo "[work-state] done: eval proof invalid (state tampered); refusing to certify" >&2; exit 5 ;;
    NORED)    echo "[work-state] done: no proven red transition for the declared Eval" >&2; exit 5 ;;
    NOGREEN)  echo "[work-state] done: declared Eval is not green (green_exit != 0)" >&2; exit 5 ;;
    *)        echo "[work-state] done: unexpected eval verification state" >&2; exit 5 ;;
  esac
}

# ── eval-red ──────────────────────────────────────────────────────────────
cmd_eval_red() {
  local cmd_file="" output_re="" expected_exit="" run_id="" mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cmd-file) cmd_file="${2:-}"; shift 2 ;;
      --cmd-file=*) cmd_file="${1#--cmd-file=}"; shift ;;
      --output-re) output_re="${2:-}"; shift 2 ;;
      --output-re=*) output_re="${1#--output-re=}"; shift ;;
      --expected-exit) expected_exit="${2:-}"; shift 2 ;;
      --expected-exit=*) expected_exit="${1#--expected-exit=}"; shift ;;
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[work-state] eval-red: unexpected arg '$1'" >&2; exit 2 ;;
    esac
  done
  [ -z "$run_id" ] && run_id="${MB_WORK_RUN_ID:-}"
  [ -n "$cmd_file" ] || { echo "[work-state] eval-red --cmd-file required" >&2; exit 2; }
  # --output-re is NOT required here: C1 makes both anchors optional for a
  # non-gated task; legality is decided by the DECLARATION, resolved below.
  { [ -f "$cmd_file" ] && [ -r "$cmd_file" ]; } || { echo "[work-state] eval-red: cmd-file not found" >&2; exit 2; }
  if [ -n "$expected_exit" ]; then
    # A red exit is by definition non-zero; --expected-exit only refines WHICH
    # non-zero code is expected. Reject --expected-exit 0 as a contradiction.
    if ! is_uint "$expected_exit"; then
      echo "[work-state] eval-red --expected-exit must be a non-negative integer" >&2; exit 2
    fi
    if [ "$expected_exit" -eq 0 ]; then
      echo "[work-state] eval-red --expected-exit must be non-zero (a red never exits 0)" >&2; exit 2
    fi
  fi

  local state; state=$(state_path "$mb_arg" "$run_id")
  require_valid_state "$state"
  PARSED_EVAL_MB="$mb_arg"

  # Snapshot FIRST, then bind/hash/execute only the snapshot (review [12]).
  # The old order read the caller's path for the declaration check and re-opened
  # it for `cp`, leaving a window in which an atomic rename could show the
  # declared bytes at binding time and a different command at snapshot time —
  # the post-run cmp then compared the already-stable substitute and passed.
  local snap; snap=$(mktemp)
  cp "$cmd_file" "$snap"
  eval_require_binding "$state" "$snap" "eval-red"

  # The red anchors must be the DECLARED ones, not whatever the caller passed
  # (review [10]): otherwise a foreign failure matching a caller-chosen pattern
  # is certified as this task's genuine red.
  local anchors declared_exit declared_ore
  anchors=$(eval_declared_anchors "$(mb_resolve_path "$mb_arg")" \
    "$(eval_state_field "$state" source_path)" \
    "$(eval_state_field "$state" source_topic)" \
    "$(eval_state_field "$state" item_no)" "$(eval_state_field "$state" source)")
  declared_exit=${anchors%%$'\037'*}
  declared_ore=${anchors#*$'\037'}
  # Declared anchors are authoritative in BOTH directions (eval_reconcile_anchors).
  local _rec
  _rec=$(eval_reconcile_anchors "$output_re" "$expected_exit" "$declared_ore" "$declared_exit") || {
    rm -f "$snap"
    case "$_rec" in
      ORE_MISMATCH) echo "[work-state] eval-red: --output-re does not match the declared output~ anchor for this task" >&2 ;;
      ORE_UNDECLARED) echo "[work-state] eval-red: this task declares no output~ anchor; --output-re is not accepted for it" >&2 ;;
      EXIT_MISMATCH) echo "[work-state] eval-red: --expected-exit does not match the declared exit: anchor for this task" >&2 ;;
      *) echo "[work-state] eval-red: this task declares no exit: anchor; --expected-exit is not accepted for it" >&2 ;;
    esac
    exit 2; }
  output_re=${_rec%%$'\037'*}
  _rec=${_rec#*$'\037'}
  expected_exit=${_rec%%$'\037'*}
  local red_anchor=${_rec#*$'\037'}

  # --output-re must compile as an ERE (grep -E exits 2 on a bad pattern).
  if [ -n "$output_re" ]; then
    local gec
    set +e
    printf '' | grep -Eq -- "$output_re" 2>/dev/null
    gec=$?
    set -e
    if [ "$gec" -eq 2 ]; then
      rm -f "$snap"
      echo "[work-state] eval-red: --output-re is not a valid ERE" >&2; exit 2
    fi
  fi

  local run_root out rc mrc red_match=0
  run_root=$(eval_run_root)
  set +e
  out=$(cd "$run_root" && bash "$snap" 2>&1)
  rc=$?
  if [ -n "$output_re" ]; then
    printf '%s\n' "$out" | grep -Eq -- "$output_re"
    mrc=$?
  else
    mrc=0                      # anchorless: nothing to match, exit decides
  fi
  set -e

  # Reject a cmd-file that modified itself during the run (the executed version
  # would no longer be the one on disk).
  if ! cmp -s "$cmd_file" "$snap"; then
    rm -f "$snap"
    echo "[work-state] eval-red: cmd-file changed during execution (self-modifying)" >&2
    exit 2
  fi

  # red_match requires: output matched the anchor AND an actual non-zero exit
  # (major #6 — a green exit 0 is never a red) AND, when given, the exact code.
  if [ "$mrc" -eq 0 ] && [ "$rc" -ne 0 ]; then red_match=1; fi
  if [ -n "$expected_exit" ] && [ "$rc" -ne "$expected_exit" ]; then red_match=0; fi

  local tmp; tmp=$(mktemp)
  STATE="$state" TMP="$tmp" SNAP="$snap" RED_EXIT="$rc" RED_MATCH="$red_match" \
    OUTPUT_RE="$output_re" EXPECTED_EXIT="$expected_exit" RED_ANCHOR="$red_anchor" \
    MB_SD="$SCRIPT_DIR" python3 - <<'PY'
import json, os, datetime, hashlib, sys
sys.path.insert(0, os.environ["MB_SD"])
import mb_work_eval_proof as proof
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
cmd = open(os.environ["SNAP"], encoding="utf-8").read()
cmd_hash = hashlib.sha256(cmd.encode("utf-8")).hexdigest()
rm = os.environ["RED_MATCH"] == "1"
red_exit = int(os.environ["RED_EXIT"])
e = {
    "cmd": cmd,
    "cmd_hash": cmd_hash,
    "red_exit": red_exit,
    "red_observed": rm,
    "red_match": rm,
    "green_exit": None,
    # The declared anchors this red was judged against (review [10]).
    "output_re": os.environ.get("OUTPUT_RE", ""),
    "expected_exit": os.environ.get("EXPECTED_EXIT", ""),
    # "none" when C1 declared neither anchor (red judged by exit != 0 alone).
    "red_anchor": os.environ.get("RED_ANCHOR", "declared"),
}
e["sig"] = proof.sign(e)
data["eval"] = e
data["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
  mv "$tmp" "$state"
  rm -f "$snap"

  [ "$red_match" -eq 1 ] && exit 0
  exit 1
}

# ── eval-green ────────────────────────────────────────────────────────────
cmd_eval_green() {
  local cmd_file="" run_id="" mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cmd-file) cmd_file="${2:-}"; shift 2 ;;
      --cmd-file=*) cmd_file="${1#--cmd-file=}"; shift ;;
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[work-state] eval-green: unexpected arg '$1'" >&2; exit 2 ;;
    esac
  done
  [ -z "$run_id" ] && run_id="${MB_WORK_RUN_ID:-}"
  [ -n "$cmd_file" ] || { echo "[work-state] eval-green --cmd-file required" >&2; exit 2; }
  { [ -f "$cmd_file" ] && [ -r "$cmd_file" ]; } || { echo "[work-state] eval-green: cmd-file not found" >&2; exit 2; }

  local state; state=$(state_path "$mb_arg" "$run_id")
  require_valid_state "$state"
  PARSED_EVAL_MB="$mb_arg"
  eval_require_binding "$state" "$cmd_file" "eval-green"

  # Precondition (blockers #2): a valid, completed, PROVEN red transition must
  # exist. Verify the helper-owned proof (rejects a hand-edited eval object),
  # require red_observed=true AND red_match=true, and confirm the cmd-file is
  # byte-identical (content + hash) to the executed red snapshot.
  local check
  set +e
  check=$(STATE="$state" CMD_FILE="$cmd_file" MB_SD="$SCRIPT_DIR" python3 - <<'PY'
import json, os, sys, hashlib
sys.path.insert(0, os.environ["MB_SD"])
import mb_work_eval_proof as proof
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
e = data.get("eval")
if not isinstance(e, dict) or "cmd" not in e or "sig" not in e:
    print("NOEVAL"); sys.exit(0)
if not proof.verify(e):
    print("TAMPERED"); sys.exit(0)
if not (e.get("red_observed") is True and e.get("red_match") is True):
    print("NORED"); sys.exit(0)
cur = open(os.environ["CMD_FILE"], encoding="utf-8").read()
if cur != e["cmd"] or hashlib.sha256(cur.encode("utf-8")).hexdigest() != e.get("cmd_hash"):
    print("DRIFT"); sys.exit(0)
print("OK")
PY
)
  set -e
  case "$check" in
    NOEVAL)   echo "[work-state] eval-green: no eval recorded (run eval-red first)" >&2; exit 2 ;;
    TAMPERED) echo "[work-state] eval-green: eval proof invalid (state tampered)" >&2; exit 2 ;;
    NORED)    echo "[work-state] eval-green: no valid red transition (red_observed/red_match not true)" >&2; exit 2 ;;
    DRIFT)    exit 1 ;;
    OK)       : ;;
    *)        echo "[work-state] eval-green: unexpected verification state" >&2; exit 2 ;;
  esac

  # Execute the PROVEN snapshot from state, never a second read of the caller's
  # path (review [2]): the old code hashed $cmd_file and then re-opened it to
  # run it, leaving a window in which the verified bytes could be swapped.
  local run_root rc gsnap
  gsnap=$(mktemp)
  STATE="$state" SNAP="$gsnap" python3 - <<'PYSNAP'
import json, os
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
open(os.environ["SNAP"], "w", encoding="utf-8").write(data["eval"]["cmd"])
PYSNAP
  run_root=$(eval_run_root)
  set +e
  ( cd "$run_root" && bash "$gsnap" ) >/dev/null 2>&1
  rc=$?
  set -e
  rm -f "$gsnap"

  local tmp; tmp=$(mktemp)
  STATE="$state" TMP="$tmp" GREEN_EXIT="$rc" MB_SD="$SCRIPT_DIR" python3 - <<'PY'
import json, os, datetime, sys
sys.path.insert(0, os.environ["MB_SD"])
import mb_work_eval_proof as proof
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
e = data.setdefault("eval", {})
e["green_exit"] = int(os.environ["GREEN_EXIT"])
# Re-bind the proof: green_exit is part of the signed payload, so only a green
# this helper actually observed can satisfy the `done` gate (review [11]).
e["sig"] = proof.sign(e)
data["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
  mv "$tmp" "$state"

  [ "$rc" -eq 0 ] && exit 0
  exit 1
}
