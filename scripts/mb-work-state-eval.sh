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

# ── declaration binding (review [2]) ──────────────────────────────────────
# The Eval a task DECLARES is the only command this gate may run. Without this
# binding a caller could hand the helper an unrelated toggle-script that prints
# the anchor and exits 1, then exits 0 once an external marker flipped — both
# transitions "proven" while the declared Eval never ran.
#
# `eval_declared_cmd <bank> <source> <item_no>` echoes the declared Eval command
# for that task, or nothing when it cannot be resolved.
eval_declared_cmd() {
  local bank="$1" source_="$2" item_no="$3"
  MB_SD="$SCRIPT_DIR" BANK="$bank" SOURCE="$source_" ITEM_NO="$item_no" python3 - <<'PY'
import os, pathlib, sys
sys.path.insert(0, os.environ["MB_SD"])
src = os.environ["SOURCE"]
candidates = []
if src.endswith(".md"):
    candidates.append(pathlib.Path(src))
else:
    candidates.append(pathlib.Path(src) / "tasks.md")
    candidates.append(pathlib.Path(os.environ["BANK"]) / "specs" / src / "tasks.md")
for p in candidates:
    if not p.is_file():
        continue
    try:
        import mb_work_items as w
        for it in w.parse_work_items(p):
            if it.kind == "task" and str(it.item_no) == os.environ["ITEM_NO"]:
                cmd = (it.eval or {}).get("cmd") or ""
                if cmd and cmd != "none":
                    sys.stdout.write(cmd)
                sys.exit(0)
    except Exception:
        continue
PY
}

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
  source_=$(STATE="$state" python3 -c 'import json,os;print(json.load(open(os.environ["STATE"]))
.get("source",""))' 2>/dev/null || true)
  item_no=$(STATE="$state" python3 -c 'import json,os;print(json.load(open(os.environ["STATE"]))
.get("item_no",""))' 2>/dev/null || true)
  declared=$(eval_declared_cmd "$bank" "$source_" "$item_no")
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

# Helper-owned proof key. This is NOT a cryptographic secret against a
# determined adversary (it lives in the script) — it makes a hand-edited
# eval-object detectable, so a verdict cannot be forged by editing the state
# JSON. The proof binds the executed cmd snapshot + red-transition fields.
MBW_EVAL_PROOF_KEY="mb-work-state/eval-proof/v1"

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
  [ -n "$output_re" ] || { echo "[work-state] eval-red --output-re required" >&2; exit 2; }
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
  eval_require_binding "$state" "$cmd_file" "eval-red"

  # --output-re must compile as an ERE (grep -E exits 2 on a bad pattern).
  local gec
  set +e
  printf '' | grep -Eq -- "$output_re" 2>/dev/null
  gec=$?
  set -e
  if [ "$gec" -eq 2 ]; then
    echo "[work-state] eval-red: --output-re is not a valid ERE" >&2; exit 2
  fi

  # Snapshot the cmd-file BEFORE running so a self-modifying command cannot swap
  # itself for a green version mid-run (major #7): we execute the immutable
  # snapshot and later persist exactly that snapshot.
  local snap; snap=$(mktemp)
  cp "$cmd_file" "$snap"

  local run_root out rc mrc red_match=0
  run_root=$(eval_run_root)
  set +e
  out=$(cd "$run_root" && bash "$snap" 2>&1)
  rc=$?
  printf '%s\n' "$out" | grep -Eq -- "$output_re"
  mrc=$?
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
    PROOF_KEY="$MBW_EVAL_PROOF_KEY" python3 - <<'PY'
import json, os, datetime, hashlib
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
cmd = open(os.environ["SNAP"], encoding="utf-8").read()
cmd_hash = hashlib.sha256(cmd.encode("utf-8")).hexdigest()
rm = os.environ["RED_MATCH"] == "1"
red_exit = int(os.environ["RED_EXIT"])
signed = json.dumps(
    {"cmd_hash": cmd_hash, "red_exit": red_exit, "red_observed": rm, "red_match": rm},
    sort_keys=True, separators=(",", ":"),
)
sig = hashlib.sha256((os.environ["PROOF_KEY"] + "\0" + signed).encode("utf-8")).hexdigest()
data["eval"] = {
    "cmd": cmd,
    "cmd_hash": cmd_hash,
    "red_exit": red_exit,
    "red_observed": rm,
    "red_match": rm,
    "green_exit": None,
    "sig": sig,
}
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
  check=$(STATE="$state" CMD_FILE="$cmd_file" PROOF_KEY="$MBW_EVAL_PROOF_KEY" python3 - <<'PY'
import json, os, sys, hashlib
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
e = data.get("eval")
if not isinstance(e, dict) or "cmd" not in e or "sig" not in e:
    print("NOEVAL"); sys.exit(0)
signed = json.dumps(
    {"cmd_hash": e.get("cmd_hash"), "red_exit": e.get("red_exit"),
     "red_observed": e.get("red_observed"), "red_match": e.get("red_match")},
    sort_keys=True, separators=(",", ":"),
)
expect = hashlib.sha256((os.environ["PROOF_KEY"] + "\0" + signed).encode("utf-8")).hexdigest()
if expect != e.get("sig"):
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
  STATE="$state" TMP="$tmp" GREEN_EXIT="$rc" PROOF_KEY="$MBW_EVAL_PROOF_KEY" python3 - <<'PY'
import json, os, datetime, hashlib
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
e = data.setdefault("eval", {})
e["green_exit"] = int(os.environ["GREEN_EXIT"])
# Re-bind the proof so the (unchanged) red fields stay verifiable.
signed = json.dumps(
    {"cmd_hash": e.get("cmd_hash"), "red_exit": e.get("red_exit"),
     "red_observed": e.get("red_observed"), "red_match": e.get("red_match")},
    sort_keys=True, separators=(",", ":"),
)
e["sig"] = hashlib.sha256((os.environ["PROOF_KEY"] + "\0" + signed).encode("utf-8")).hexdigest()
data["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
  mv "$tmp" "$state"

  [ "$rc" -eq 0 ] && exit 0
  exit 1
}
