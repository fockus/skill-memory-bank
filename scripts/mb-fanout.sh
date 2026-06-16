#!/usr/bin/env bash
# mb-fanout.sh — the stateless, agent-invoked fan-out helper (dynamic-flow Task 9).
#
# Takes N branch prompts + ONE per-agent sub-invocation command, runs the branches
# CONCURRENTLY via POSIX background jobs (`&`) + a single `wait`, captures each
# branch's stdout, parses it as JSON, and emits ONE aggregate JSON object. It is
# the fan-out's EXIT-CODE AUTHORITY: a failed or non-JSON branch is surfaced loud
# (exit 2 + a per-branch error marker), never silently dropped (REQ-DF-084, ADR-3).
#
# Statelessness (REQ-DF-081/085, ADR-1′): NO daemon, NO durable-execution journal,
# NO persisted cross-invocation process state, NO JS/TS on the path. The agent
# ALWAYS initiates. A `mktemp -d` workspace is the only scratch and is trap-cleaned
# on every exit; nothing is written into the bank.
#
# ─── SECURITY SEAM (READ THIS) ──────────────────────────────────────────────
#   `--cmd` is the per-agent sub-invoke command TEMPLATE. It is OPERATOR-supplied
#   and TRUSTED (e.g. an adapter's `codex exec …`) — it is run with `bash -c`.
#   Branch PROMPTS, by contrast, may be LESS trusted. They are therefore passed to
#   `--cmd` EXCLUSIVELY through exported environment variables:
#       MB_FANOUT_PROMPT        — this branch's prompt text
#       MB_FANOUT_BRANCH_INDEX  — this branch's 0-based index
#   A prompt is NEVER string-interpolated into the command and is NEVER `eval`'d.
#   This is the trust boundary: a prompt containing `$(...)`, backticks, quotes, or
#   `; rm -rf /` cannot break out, because the shell only ever sees it as the VALUE
#   of an env var, not as code.
# ────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   mb-fanout.sh [mb_path] --cmd <sub-invoke-command>
#                (--branch <prompt> | --branch-file <f>)...
#                [--max-branches N] [--cost-per-branch T] [--mb <path>]
#                [--dry-run] [-h|--help]
#
#   mb_path / --mb <p> : Memory Bank path (default via _lib.sh::mb_resolve_path).
#   --cmd <c>          : the per-agent sub-invoke command template (REQUIRED,
#                        trusted, run via `bash -c`). Each branch's prompt arrives
#                        through MB_FANOUT_PROMPT (NEVER interpolated into <c>).
#   --branch <p>       : add one branch with prompt <p>. Repeatable.
#   --branch-file <f>  : add one branch whose prompt is read from file <f>.
#                        Repeatable. Need ≥1 branch overall.
#   --max-branches N   : hard cap (default 16). N > cap → exit 2 BEFORE spawning.
#   --cost-per-branch T: per-branch token cost for the budget pre-check (opt-in).
#   --dry-run          : validate args + cap + budget, print the would-run plan as
#                        JSON, spawn NOTHING.
#
# Budget pre-check (opt-in — REUSES scripts/mb-work-budget.sh, never reimplements
#   its math beyond the N×cost comparison): if a budget is being TRACKED
#   (`mb-work-budget.sh status` succeeds) AND --cost-per-branch is given, compute
#   N × cost; if that exceeds the REMAINING budget (total − spent) → exit 2 BEFORE
#   spawning. If no budget is tracked, the check is a NO-OP (budget is opt-in).
#
# Output (stdout — ALWAYS exactly one JSON object):
#   {"branches":[{"index":0,"ok":true,"result":<parsed>,"error":null},
#                {"index":1,"ok":false,"result":null,"error":"<marker>"}, ...],
#    "ok":<all-true>, "count":N, "failed":M}
#   On --dry-run: {"dry_run":true,"count":N,"max_branches":C,
#                  "cost_per_branch":T|null,"plan":[{"index":i,"prompt":...}, ...]}
#   ALL diagnostics go to stderr. JSON is built via python3 json.dumps so control
#   characters / quotes in prompts or results are always escaped correctly.
#
# Exit codes (FAIL-LOUD — the exit-code authority; ADR-3 "broke dominates"):
#   0  every branch ran AND returned valid JSON (or a clean --dry-run).
#   2  ANY branch failed (non-zero exit) OR returned non-JSON, OR a usage error,
#      OR the branch-count cap was exceeded, OR the budget pre-check rejected the
#      run. There is NO exit 1 — for this helper any breach is the loud 2,
#      mirroring the firewall's "broke" dominance.
#
# Portability: POSIX/bash + _lib.sh; bash-3.2 safe (no mapfile, no associative
#   arrays, no `${v^^}`; every empty-array expansion guarded under set -u).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Injectable for tests; defaults to the real budget tracker (the SSOT for budget).
BUDGET_BIN="${MB_BUDGET_BIN:-$SCRIPT_DIR/mb-work-budget.sh}"

# Injectable for tests; defaults to the real per-agent sub-invoke resolver. Used
# ONLY when --cmd is omitted: it bakes the active agent's sub-invoke command
# (MB_SUBINVOKE_CMD override → built-in table). A resolved template is TRUSTED
# exactly as an operator --cmd is (Task 12, REQ-DF-082/051/052).
RESOLVE_BIN="${MB_SUBINVOKE_RESOLVE_BIN:-$SCRIPT_DIR/mb-subinvoke-resolve.sh}"

DEFAULT_MAX_BRANCHES=16

usage() {
  sed -n '2,82p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die_usage() {
  printf '[mb-fanout] %s\n' "$1" >&2
  exit 2
}

# Emit a strict-valid JSON aggregate marking ALL $1 branches ok:false. Used as a
# pure-bash fallback when the python3 aggregation step is itself unusable (e.g.
# python3 missing) — the aggregate-always contract (REQ-DF-084) must hold even
# then, and no branch may be silently dropped. Safe to assemble in bash because
# every field here is an integer or a FIXED ascii marker (no user-controlled
# strings flow in), so there is no JSON-escaping hazard.
emit_fallback_aggregate() {
  local n="$1" i=0 sep=""
  printf '{"branches":['
  while [ "$i" -lt "$n" ]; do
    printf '%s{"index":%s,"ok":false,"result":null,"error":"aggregation unavailable"}' "$sep" "$i"
    sep=","
    i=$((i + 1))
  done
  printf '],"ok":false,"count":%s,"failed":%s}\n' "$n" "$n"
}

# ---------------------------------------------------------------------------
# Arg parse
# ---------------------------------------------------------------------------
MB_ARG=""
CMD=""
CMD_SET=0
MAX_BRANCHES="$DEFAULT_MAX_BRANCHES"
COST_PER_BRANCH=""
DRY_RUN=0
# PROMPTS[i] is branch i's prompt text.
PROMPTS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --cmd)
      [ "$#" -ge 2 ] || die_usage "--cmd needs a value"
      CMD="$2"; CMD_SET=1; shift 2
      ;;
    --cmd=*) CMD="${1#--cmd=}"; CMD_SET=1; shift ;;
    --branch)
      [ "$#" -ge 2 ] || die_usage "--branch needs a value"
      PROMPTS+=("$2"); shift 2
      ;;
    --branch=*) PROMPTS+=("${1#--branch=}"); shift ;;
    --branch-file)
      [ "$#" -ge 2 ] || die_usage "--branch-file needs a value"
      [ -f "$2" ] || die_usage "--branch-file: no such file: $2"
      # Guard the read: a `cat` failure (unreadable file) inside `$(...)` would
      # otherwise trip set -e and abort with exit 1 — usage errors must be exit 2.
      _bf_prompt="$(cat "$2" 2>/dev/null)" || die_usage "--branch-file: cannot read file: $2"
      PROMPTS+=("$_bf_prompt"); shift 2
      ;;
    --branch-file=*)
      _bf="${1#--branch-file=}"; shift
      [ -f "$_bf" ] || die_usage "--branch-file: no such file: $_bf"
      _bf_prompt="$(cat "$_bf" 2>/dev/null)" || die_usage "--branch-file: cannot read file: $_bf"
      PROMPTS+=("$_bf_prompt")
      ;;
    --max-branches)
      [ "$#" -ge 2 ] || die_usage "--max-branches needs a value"
      MAX_BRANCHES="$2"; shift 2
      ;;
    --max-branches=*) MAX_BRANCHES="${1#--max-branches=}"; shift ;;
    --cost-per-branch)
      [ "$#" -ge 2 ] || die_usage "--cost-per-branch needs a value"
      COST_PER_BRANCH="$2"; shift 2
      ;;
    --cost-per-branch=*) COST_PER_BRANCH="${1#--cost-per-branch=}"; shift ;;
    --mb)
      [ "$#" -ge 2 ] || die_usage "--mb needs a value"
      MB_ARG="$2"; shift 2
      ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --)
      shift
      ;;
    -*)
      die_usage "unknown flag: $1"
      ;;
    *)
      if [ -z "$MB_ARG" ]; then
        MB_ARG="$1"
      else
        die_usage "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

# --- validate required inputs ------------------------------------------------
# DoD#2 (Task 12, REQ-DF-082/051/052): if --cmd was omitted, RESOLVE the active
# agent's sub-invoke command (MB_SUBINVOKE_CMD override → built-in table) via the
# resolver. An operator-supplied --cmd ALWAYS wins (we never resolve when CMD is
# set). Invariants preserved EXACTLY:
#   • the resolved template is TRUSTED identically to an operator --cmd (run via
#     `bash -c "$CMD"` below) — the resolver only emits env-prompt templates that
#     carry the literal $MB_FANOUT_PROMPT token, never an interpolated prompt;
#   • the prompt STILL flows ONLY through MB_FANOUT_PROMPT (unchanged downstream);
#   • a FAILURE to resolve takes the SAME die_usage path → exit 2 (NEVER exit 1):
#     `set +e` brackets the resolver call so its non-zero rc can't trip set -e,
#     and `die_usage` is the contracted loud exit 2;
#   • still STATELESS — the resolver only reads env + prints a template, writes
#     nothing to the bank.
if [ "$CMD_SET" -ne 1 ]; then
  set +e
  CMD="$(bash "$RESOLVE_BIN" 2>/dev/null)"
  _resolve_rc=$?
  set -e
  if [ "$_resolve_rc" -ne 0 ] || [ -z "$CMD" ]; then
    die_usage "--cmd omitted and no sub-invoke command resolvable for the active agent (set --cmd / MB_SUBINVOKE_CMD / MB_AGENT)"
  fi
  CMD_SET=1
fi

N="${#PROMPTS[@]}"
[ "$N" -ge 1 ] || die_usage "need at least one --branch / --branch-file"

# Both numeric flags must be digits-only AND fit a 64-bit integer (≤18 digits).
# Rejecting an absurdly long digit string here keeps a later bash `-gt`/Python
# `int()` from overflowing or raising (Python 3.11+ caps int<->str conversion),
# which would surface as the forbidden exit 1 instead of a clean usage exit 2.
case "$MAX_BRANCHES" in
  ''|*[!0-9]*) die_usage "--max-branches must be a non-negative integer: $MAX_BRANCHES" ;;
esac
[ "${#MAX_BRANCHES}" -le 18 ] || die_usage "--max-branches out of range (too many digits): $MAX_BRANCHES"
if [ -n "$COST_PER_BRANCH" ]; then
  case "$COST_PER_BRANCH" in
    ''|*[!0-9]*) die_usage "--cost-per-branch must be a non-negative integer: $COST_PER_BRANCH" ;;
  esac
  [ "${#COST_PER_BRANCH}" -le 18 ] || die_usage "--cost-per-branch out of range (too many digits): $COST_PER_BRANCH"
fi

MB_PATH="$(mb_resolve_path "$MB_ARG")"

# ---------------------------------------------------------------------------
# Branch-count cap — BEFORE spawning (REQ-DF: fail-loud pre-check).
# ---------------------------------------------------------------------------
if [ "$N" -gt "$MAX_BRANCHES" ]; then
  printf '[mb-fanout] branch-count cap exceeded: %s branches > --max-branches %s (refusing to spawn)\n' \
    "$N" "$MAX_BRANCHES" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Budget pre-check — BEFORE spawning. Opt-in: only when a budget is being tracked
# AND --cost-per-branch is given. REUSES mb-work-budget.sh `status` (its own
# `total=… spent=…` line is the SSOT); we only do the N×cost ≤ remaining compare.
#
# "Tracked" is decided by the STATE FILE's existence, NOT by status's exit code.
# A budget that EXISTS but is unreadable/corrupt MUST fail-CLOSED (exit 2) — a
# non-zero `status` here means "inconclusive", never "no budget" (that would be
# a fail-OPEN spawn past the cap). Genuine no-budget = no state file → no-op.
# ---------------------------------------------------------------------------
if [ -n "$COST_PER_BRANCH" ]; then
  _budget_state="$MB_PATH/.work-budget.json"
  # "Tracked" = the state path EXISTS in any form (regular file, dir, valid OR
  # dangling symlink). `[ -e ]` follows a symlink (false for a dangling one), so
  # OR `[ -L ]` to also catch a dangling link. A path that exists but is NOT a
  # regular readable file is INCONCLUSIVE → fail-CLOSED, never a fail-open spawn.
  if [ -e "$_budget_state" ] || [ -L "$_budget_state" ]; then
    if [ ! -f "$_budget_state" ] || [ ! -r "$_budget_state" ]; then
      printf '[mb-fanout] budget pre-check inconclusive: state path %s exists but is not a regular readable file — refusing to spawn\n' \
        "$_budget_state" >&2
      exit 2
    fi
    set +e
    BUDGET_STATUS="$(bash "$BUDGET_BIN" status --mb "$MB_PATH" 2>/dev/null)"
    BUDGET_RC=$?
    set -e
    # A tracked budget that cannot be read is INCONCLUSIVE → refuse to spawn.
    if [ "$BUDGET_RC" -ne 0 ] || [ -z "$BUDGET_STATUS" ]; then
      printf '[mb-fanout] budget pre-check inconclusive: a budget is tracked (%s) but the status check failed (rc=%s) — refusing to spawn\n' \
        "$_budget_state" "$BUDGET_RC" >&2
      exit 2
    fi
    # Pull total= and spent= scalars from the status line. Each must be an EXACT
    # `<key>=<digits>` whole token — `awk -F=` with `NF==2` rejects a malformed
    # `total=100=garbage` (NF==3) that a naive `cut -d= -f2` would mis-read as
    # `100` and fail-OPEN. The parser keeps the FIRST match (`!f` guard) but reads
    # ALL input and prints at END — it must NOT `exit` early, or the upstream
    # `printf|tr` would take SIGPIPE under pipefail and abort the script with 141
    # instead of the contracted exit 2. awk emits nothing (rc 0) on no match, so a
    # missing field → empty → the inconclusive exit 2 below; never a forbidden 1.
    _total="$(printf '%s\n' "$BUDGET_STATUS" | tr '[:space:]' '\n' \
      | awk -F= '$1=="total" && NF==2 && $2 ~ /^[0-9]+$/ && !f {v=$2; f=1} END{if(f) print v}')"
    _spent="$(printf '%s\n' "$BUDGET_STATUS" | tr '[:space:]' '\n' \
      | awk -F= '$1=="spent" && NF==2 && $2 ~ /^[0-9]+$/ && !f {v=$2; f=1} END{if(f) print v}')"
    if [ -z "$_total" ] || [ -z "$_spent" ]; then
      printf '[mb-fanout] budget pre-check inconclusive: tracked budget has missing/malformed total/spent — refusing to spawn\n' >&2
      exit 2
    fi
    # The N×cost comparison runs in Python integer arithmetic — bash $(( ))
    # would overflow a 2^63 cost into a NEGATIVE need (silently bypassing the
    # cap → fail-OPEN spawn) and would choke on a leading-zero ("08") value as
    # octal. Python ints are arbitrary-precision and base-10. Exit 2 on reject.
    set +e
    MB_FAN_N="$N" MB_FAN_COST="$COST_PER_BRANCH" \
    MB_FAN_TOTAL="$_total" MB_FAN_SPENT="$_spent" python3 - <<'PY'
import os
import sys

n = int(os.environ["MB_FAN_N"])
cost = int(os.environ["MB_FAN_COST"])
total = int(os.environ["MB_FAN_TOTAL"])
spent = int(os.environ["MB_FAN_SPENT"])

remaining = total - spent
if remaining < 0:
    remaining = 0
need = n * cost
if need > remaining:
    sys.stderr.write(
        "[mb-fanout] budget pre-check rejected: need %d (%d branches x %d) "
        "> remaining %d (refusing to spawn)\n" % (need, n, cost, remaining)
    )
    sys.exit(2)
sys.exit(0)
PY
    _budget_rc=$?
    set -e
    [ "$_budget_rc" -eq 0 ] || exit 2
  fi
fi

# ---------------------------------------------------------------------------
# --dry-run — validate done; print the plan, spawn NOTHING.
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  # Guard the plan-printer: a missing python3 (127) or any raise must surface as
  # the contracted loud exit 2, never a bare 1/127 leaking to the caller.
  set +e
  MB_FANOUT_N="$N" \
  MB_FANOUT_MAX="$MAX_BRANCHES" \
  MB_FANOUT_COST="$COST_PER_BRANCH" \
  python3 - "${PROMPTS[@]}" <<'PY'
import json
import os
import sys

prompts = sys.argv[1:]
cost = os.environ.get("MB_FANOUT_COST", "")
obj = {
    "dry_run": True,
    "count": int(os.environ["MB_FANOUT_N"]),
    "max_branches": int(os.environ["MB_FANOUT_MAX"]),
    "cost_per_branch": int(cost) if cost else None,
    "plan": [{"index": i, "prompt": p} for i, p in enumerate(prompts)],
}
print(json.dumps(obj, separators=(",", ":")))
PY
  _dry_rc=$?
  set -e
  if [ "$_dry_rc" -ne 0 ]; then
    printf '[mb-fanout] dry-run plan generation failed (python3 rc=%s)\n' "$_dry_rc" >&2
    exit 2
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Stateless scratch workspace — the ONLY persisted state, trap-cleaned on exit.
# Nothing is ever written into the bank. A failed `mktemp` (e.g. an unwritable
# TMPDIR) must be the contracted loud exit 2, never a bare set -e exit 1.
# ---------------------------------------------------------------------------
if ! WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/mb-fanout.XXXXXX" 2>/dev/null)"; then
  printf '[mb-fanout] could not create a scratch workspace (mktemp failed under TMPDIR=%s) — aborting\n' \
    "${TMPDIR:-/tmp}" >&2
  exit 2
fi
# Clean up via a function with a QUOTED expansion — a literal single-quote in
# WORKDIR (e.g. TMPDIR=/tmp/a'b) would break a `trap "rm -rf '$WORKDIR'"` string
# and leak the workspace. A function defers expansion safely.
# shellcheck disable=SC2329  # invoked indirectly via `trap _cleanup EXIT`
_cleanup() { rm -rf -- "$WORKDIR"; }
trap _cleanup EXIT

# ---------------------------------------------------------------------------
# Fan out: spawn each branch as a background job. The branch PROMPT is exported
# (the security seam — never interpolated into CMD, never eval'd); CMD is run with
# `bash -c` (operator-trusted). Per-branch stdout → out.<i>; exit code → rc.<i>.
# set -e must NOT abort on a branch's non-zero exit; that is recorded, not fatal.
# ---------------------------------------------------------------------------
i=0
while [ "$i" -lt "$N" ]; do
  prompt="${PROMPTS[$i]}"
  out_file="$WORKDIR/out.$i"
  rc_file="$WORKDIR/rc.$i"
  # Subshell so a branch that calls `exit`/`set -e` can never hijack our exit
  # authority — only the subshell's status escapes (recorded to rc.<i>).
  (
    set +e
    MB_FANOUT_PROMPT="$prompt" MB_FANOUT_BRANCH_INDEX="$i" \
      bash -c "$CMD" >"$out_file" 2>/dev/null
    printf '%s' "$?" >"$rc_file"
  ) &
  i=$((i + 1))
done

# Single barrier: wait for every background branch to finish.
wait

# ---------------------------------------------------------------------------
# Aggregate (python3 — robust JSON parse + json.dumps escaping). The fan-out is
# the exit-code authority: a branch that exited non-zero OR did not emit a valid
# JSON object is a FAILURE (ok:false + error marker); it is NEVER silently dropped
# (REQ-DF-084). Exit 2 if ANY branch failed; 0 only if ALL ran AND returned JSON.
# The whole invocation is wrapped (set +e) so a missing python3 (127) or an
# unexpected interpreter failure is normalized to the contracted loud exit 2 —
# never a bare 1/127 leaking to the caller.
# ---------------------------------------------------------------------------
set +e
MB_FANOUT_N="$N" MB_FANOUT_WORK="$WORKDIR" python3 - <<'PY'
import json
import math
import os
import sys


def _reject_constant(token):
    # json.loads accepts the NON-standard constants NaN / Infinity / -Infinity by
    # default; reject them so such output is a loud failure and the aggregate stays
    # strict-valid JSON.
    raise ValueError("non-standard JSON constant: %s" % token)


def _reject_float(token):
    # parse_constant only catches the literal NaN/Infinity TOKENS. A numeric
    # literal that overflows to +/-inf (e.g. 1e9999) reaches parse_float instead;
    # reject any non-finite float so it can't slip through to ok:true and then
    # blow up the strict (allow_nan=False) dumps with no aggregate emitted.
    value = float(token)
    if not math.isfinite(value):
        raise ValueError("non-finite JSON float: %s" % token)
    return value


n = int(os.environ["MB_FANOUT_N"])
work = os.environ["MB_FANOUT_WORK"]

branches = []
failed = 0

for i in range(n):
    out_path = os.path.join(work, f"out.{i}")
    rc_path = os.path.join(work, f"rc.{i}")

    # Read the recorded exit code (missing/garbage → treat as a crash).
    try:
        with open(rc_path, encoding="utf-8") as fh:
            rc_raw = fh.read().strip()
        rc = int(rc_raw)
    except (OSError, ValueError):
        rc = 1

    # Read stdout as BYTES so invalid UTF-8 can never crash the aggregator
    # (a UnicodeDecodeError here would defeat the exit-code authority: no
    # aggregate + a forbidden exit 1). Invalid UTF-8 is simply not valid JSON.
    try:
        with open(out_path, "rb") as fh:
            raw = fh.read()
    except OSError:
        raw = b""

    if rc != 0:
        # A branch sub-invocation FAILED (non-zero exit). Surface it loud.
        failed += 1
        branches.append({
            "index": i,
            "ok": False,
            "result": None,
            "error": f"exit {rc}",
        })
        sys.stderr.write(
            f"[mb-fanout] branch {i} FAILED: sub-invocation exited {rc}\n"
        )
        continue

    # Exit 0 → require a parseable JSON value. Decode + parse defensively; ANY
    # exception (UnicodeDecodeError, JSON error, RecursionError on pathologically
    # deep input, etc.) → the branch is a loud failure, never a crash of the
    # aggregator. NaN/Infinity are rejected via parse_constant.
    parsed = None
    error = None
    try:
        parsed = json.loads(
            raw.decode("utf-8"),
            parse_constant=_reject_constant,
            parse_float=_reject_float,
        )
    except Exception:  # noqa: BLE001 — any parse failure is a loud branch failure
        error = "non-JSON"
    else:
        # A branch RESULT must be a JSON OBJECT — a downstream pattern reads
        # fields off it. A bare top-level null/number/string/bool/array is NOT
        # a usable result and must fail loud, never pass as ok:true.
        if not isinstance(parsed, dict):
            parsed = None
            error = "non-object JSON"

    if error is not None:
        failed += 1
        branches.append({
            "index": i,
            "ok": False,
            "result": None,
            "error": error,
        })
        sys.stderr.write(
            f"[mb-fanout] branch {i} FAILED: {error}\n"
        )
        continue

    branches.append({
        "index": i,
        "ok": True,
        "result": parsed,
        "error": None,
    })

summary = {
    "branches": branches,
    "ok": failed == 0,
    "count": n,
    "failed": failed,
}
# allow_nan=False keeps the aggregate STRICT-valid JSON (defensive — NaN/Infinity
# were already rejected at parse, so a result can never carry a non-finite float).
print(json.dumps(summary, separators=(",", ":"), allow_nan=False))

# Fan-out exit-code authority: any breach → loud exit 2; else 0.
sys.exit(2 if failed else 0)
PY
_agg_rc=$?
set -e
# The python is the authority (0 = all ok, 2 = some branch failed). Any OTHER
# code (127 missing python3, a signal, an unexpected raise) is normalized to the
# contracted loud exit 2 — never a bare 1/127 to the caller.
case "$_agg_rc" in
  0|2) ;;
  *)
    # The aggregation python crashed BEFORE its single print (rc not 0/2), so
    # stdout is empty. Emit a bash fallback aggregate so the always-an-aggregate
    # contract still holds, then fail loud with exit 2.
    printf '[mb-fanout] aggregation step failed (python3 rc=%s) — emitting fallback aggregate\n' "$_agg_rc" >&2
    emit_fallback_aggregate "$N"
    _agg_rc=2
    ;;
esac
exit "$_agg_rc"
