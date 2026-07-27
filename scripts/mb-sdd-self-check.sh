#!/usr/bin/env bash
# mb-sdd-self-check.sh — deterministic executor of the C8 generation self-check
# battery (svp-sdd-core design C8/C8a, REQ-054). Runs the whole battery over a
# published (draft) spec triple so `commands/sdd.md` can decide draft→ready by
# the helper's exit instead of prompt judgement. This is a pure CHECKER: it
# writes, moves, and deletes nothing; the requirements.md status is changed by
# the orchestrator per the C7 §Status state machine, based on this exit code.
#
# Usage:
#   mb-sdd-self-check.sh --spec <topic|spec-dir> [--mb <bank>]
#                        [--phase generation|done]      (default: generation)
#
# PHASES (AGR-037). The battery used to have exactly one rule — every Eval must
# be RED — while C7 made its exit 0 the only route to `status: ready`. Those two
# together made `ready` reachable ONLY for an unimplemented spec: the moment the
# code lands its Evals turn green and the gate closes forever, which is the
# opposite of what the word means. Measured on the spec that defines the gate:
# nine `eval.N=invalid` while its own suites reported `33 passed`.
#
#   --phase generation  the DECLARED red must be observable — a task that
#                       changes nothing cannot pass. `pending_materialization`
#                       is honest here: D-05 defers eval code to the first step
#                       of `/mb work`, so an absent target is expected.
#   --phase done        the Eval must be actually GREEN. `pending_materialization`
#                       is IMPOSSIBLE here: after implementation an absent target
#                       is a task that never materialised its contract →
#                       `invalid` with reason `target_missing`.
#
# The default is `generation` (the phase `commands/sdd.md` calls at Step 7). It
# is named on the verdict line — `self_check=<verdict> phase=<phase>` — because
# `self_check=invalid` means opposite things in the two phases and must never be
# readable without knowing which one produced it.
#
# Battery (C8.1–C8.5):
#   - Structural C8.1–C8.3, C8.5 are delegated to `mb-spec-validate.sh`
#     (v2 fields, gated `output~:` anchor, seam/cycle/role/scenario-parity,
#     cross-spec Blocked-by resolution). Its non-zero exit is a structural
#     violation and SHORT-CIRCUITS the battery (round-4 review [1]): the verdict
#     can no longer change, and a spec already known to be malformed must not
#     have its declared Eval commands executed — running a user-supplied command
#     on behalf of an artifact the battery has just rejected is an unreviewed
#     execution path, not a check. The violations are re-emitted on stderr so the
#     short-circuit stays diagnosable.
#   - Behavioural Eval preflight C8.4 (the core of this task, REQ-054): for each
#     task the helper resolves the Eval command's target tokens (tokens that
#     contain `/` and do not start with `-`, per C1) and runs the command from
#     the run root, judging the result by the phase above.
#
# stdout : first line `self_check=ready|invalid phase=generation|done`, then one
#          `eval.<task-id>=ready|pending_materialization|invalid` per task in
#          ascending task-id order, each followed by
#          `eval.<task-id>.reason=<reason>` whenever the verdict is not
#          self-explanatory. EVERY `invalid` carries one (I-172): the class had
#          at least four distinguishable causes and emitted no diagnosis at all,
#          so nine identical `invalid` lines cost four source-reading steps to
#          tell apart. Reason vocabulary:
#            waived              — `Eval: none — waiver: …`, nothing to run
#            no_declaration      — legacy task with no `**Eval:**` line (D-26)
#            target_absent       — generation: a declared target does not exist
#            no_target_token     — generation: the command names no target path
#            target_missing      — done: a declared target does not exist
#            tool_unavailable    — the runner is not installed / exit 127
#            malformed_command   — unbalanced quotes, or no runner after env vars
#            exit_zero_declared  — `exit: 0` in the declaration (a red never is)
#            already_green       — generation: the command exits 0
#            anchor_mismatch     — actual output does not match `output~:`
#            exit_mismatch       — actual exit ≠ declared `exit:`
#            not_green           — done: the command does not exit 0
# exit   : 0 = no `invalid` and structural checks passed (ready);
#          1 = any structural or behavioural violation (`eval.*=invalid`,
#              Blocked-by cycle, spec-validate / parity / role failure);
#          2 = usage / unresolvable topic / malformed input.
#
# A missing target or missing runner tool is NEVER treated as an observed red —
# the actual behavioural red stays a mandatory C6 gate in `/mb work` AFTER the
# eval code is materialised (D-05); this preflight neither replaces nor weakens
# it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage_error() { printf 'error=usage\n' >&2; exit 2; }

SPEC_ARG=""
MB_BANK=""
# Default: generation — the phase `commands/sdd.md` Step 7 calls. Documented in
# the usage block above and printed on the verdict line, so a default can never
# be an unstated assumption of whoever reads the output.
PHASE="generation"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --spec)
      [ "$#" -ge 2 ] || usage_error
      [ -z "$SPEC_ARG" ] || usage_error
      SPEC_ARG="$2"; shift
      ;;
    --mb)
      [ "$#" -ge 2 ] || usage_error
      MB_BANK="$2"; shift
      ;;
    --phase)
      # An unknown phase is a usage error, never a silent fallback to the
      # default: the two phases demand OPPOSITE outcomes of the same command.
      [ "$#" -ge 2 ] || usage_error
      case "$2" in generation|done) PHASE="$2" ;; *) usage_error ;; esac
      shift
      ;;
    *) usage_error ;;
  esac
  shift
done
[ -n "$SPEC_ARG" ] || usage_error

# --- Resolve the spec dir + tasks.md ---------------------------------------
if [ -d "$SPEC_ARG" ]; then
  SPEC_DIR="$SPEC_ARG"
elif [ -f "$SPEC_ARG" ]; then
  SPEC_DIR="$(dirname "$SPEC_ARG")"
else
  # Topic-only mode must RESOLVE the bank (local / registered global / legacy)
  # rather than hardcoding `.memory-bank`, which silently failed to find any
  # spec in a global-storage project (review [15]).
  if [ -n "$MB_BANK" ]; then
    bank="$MB_BANK"
  else
    # shellcheck source=_lib.sh
    bank="$(. "$SCRIPT_DIR/_lib.sh" >/dev/null 2>&1 && mb_resolve_path "" 2>/dev/null || true)"
    [ -n "$bank" ] || bank=".memory-bank"
  fi
  SPEC_DIR="$bank/specs/$SPEC_ARG"
fi
TASKS="$SPEC_DIR/tasks.md"
if [ ! -f "$TASKS" ] || [ ! -r "$TASKS" ]; then
  printf '%s:0:unresolvable\n' "$SPEC_ARG" >&2
  exit 2
fi

# --- Behavioural run root (repo root that Eval targets are relative to) -----
# Override for tests; otherwise the bank's parent (local-mode `.memory-bank`),
# matching how `mb-spec-validate.sh` derives the repo root.
if [ -n "${MB_REPO_ROOT:-}" ]; then
  RUN_ROOT="$MB_REPO_ROOT"
else
  if [ -n "$MB_BANK" ]; then _bank="$MB_BANK"; else _bank="$SPEC_DIR/../.."; fi
  _bank_abs="$(cd "$_bank" 2>/dev/null && pwd || true)"
  RUN_ROOT=""
  # A LOCAL bank (`<repo>/.memory-bank`) sits inside its checkout, so the parent
  # IS the run root. A registered GLOBAL bank does not — its parent is an
  # agent-config directory, where no Eval target can exist, so every already-green
  # command was mis-reported as pending_materialization (review [9]). There the
  # checkout is resolved from the working directory instead.
  #
  # A registered global bank also ends in `.memory-bank`, so the basename alone
  # cannot separate the two (review [15]). Detect GLOBAL positively — the bank
  # lives under the agent-config dir — and otherwise keep the parent-is-the-repo
  # rule, which is what keeps banks outside any checkout (fixtures) working.
  _agent_cfg="$(. "$SCRIPT_DIR/_lib.sh" >/dev/null 2>&1 && mb_agent_config_dir "${MB_AGENT:-}" 2>/dev/null || true)"
  _is_global=0
  case "${_agent_cfg:+${_bank_abs:-$_bank}}" in
    "$_agent_cfg"/*) [ -n "$_agent_cfg" ] && _is_global=1 ;;
  esac
  if [ "$_is_global" -eq 0 ] && [ "$(basename "${_bank_abs:-$_bank}")" = ".memory-bank" ]; then
    RUN_ROOT="$(cd "$_bank/.." 2>/dev/null && pwd || true)"
  else
    RUN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$RUN_ROOT" ] || RUN_ROOT="$(cd "$_bank/.." 2>/dev/null && pwd || true)"
  fi
  [ -n "$RUN_ROOT" ] || RUN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# --- C8.1–C8.3, C8.5: delegate structural battery to mb-spec-validate.sh ----
# This runs FIRST and, on any violation, terminates the battery before a single
# Eval command is executed (review [1]).
set +e
if [ -n "$MB_BANK" ]; then
  sv_out="$("$SCRIPT_DIR/mb-spec-validate.sh" "$SPEC_ARG" "$MB_BANK" 2>&1)"
else
  sv_out="$("$SCRIPT_DIR/mb-spec-validate.sh" "$SPEC_ARG" 2>&1)"
fi
sv_exit=$?
set -e
if [ "$sv_exit" -eq 2 ]; then
  [ -z "$sv_out" ] || printf '%s\n' "$sv_out" >&2
  printf 'error=spec_validate_usage\n' >&2
  exit 2
fi
if [ "$sv_exit" -ne 0 ]; then
  # Short-circuit: no task parsing, no Eval execution, no behavioural verdict
  # invented for a battery that never ran. The structural violations themselves
  # go to stderr — a silent `self_check=invalid` would trade one blind spot for
  # another.
  [ -z "$sv_out" ] || printf '%s\n' "$sv_out" >&2
  printf 'self_check=invalid phase=%s\n' "$PHASE"
  exit 1
fi

# --- Parse tasks → TSV (id, cmd, exit, output_re) via the authoritative parser
TSV="$(
  MB_SD="$SCRIPT_DIR" TASKS_PATH="$TASKS" python3 - <<'PY'
import os, sys, pathlib
sys.path.insert(0, os.environ["MB_SD"])
import mb_work_items as w
try:
    items = w.parse_work_items(pathlib.Path(os.environ["TASKS_PATH"]))
except w.MalformedTaskField:
    sys.exit(2)
except Exception:
    sys.exit(2)
rows = []
for it in items:
    if it.kind != "task":
        continue
    ev = it.eval or {}
    cmd = ev.get("cmd") or ""
    ex = ev.get("exit")
    ore = ev.get("output_re") or ""
    # US (\x1f) separates fields, never TAB: tab is IFS *whitespace*, so bash
    # `read` collapses two adjacent tabs into one. An Eval with output~ but no
    # exit: emits an empty middle field, and the collapse shifted the regex into
    # the exit slot — `[: integer expected` (review [10]). \x1f is not IFS
    # whitespace, so empty fields survive.
    rows.append("\x1f".join([str(it.item_no), cmd, "" if ex is None else str(ex), ore]))
sys.stdout.write("\n".join(rows))
PY
)" || { printf 'error=malformed\n' >&2; exit 2; }

# --- Behavioural Eval preflight (C8.4) --------------------------------------
# How ONE declaration is classified lives in its own file — see its header for
# the caller contract ($RUN_ROOT in, status+reason out).
# shellcheck source=mb-sdd-self-check-eval.sh
source "$SCRIPT_DIR/mb-sdd-self-check-eval.sh"

any_invalid=0
EVAL_LINES=""
if [ -n "$TSV" ]; then
  # Ascending task-id order.
  while IFS="$(printf '\037')" read -r id cmd exp ore; do
    [ -n "$id" ] || continue
    # classify_eval returns `status` optionally followed by <US> and a reason.
    # A plain variable could not carry it: the function runs inside $( ), so
    # anything it assigns dies with the subshell.
    raw="$(classify_eval "$cmd" "$exp" "$ore" "$PHASE")"
    status="${raw%%$'\037'*}"
    reason=""
    case "$raw" in *$'\037'*) reason="${raw#*$'\037'}" ;; esac
    case "$status" in invalid) any_invalid=1 ;; esac
    EVAL_LINES="${EVAL_LINES}eval.${id}=${status}"$'\n'
    # A reason line is emitted only where C8 names one, so a reason is always
    # attributable rather than a generic restatement of `invalid`.
    if [ -n "$reason" ]; then
      EVAL_LINES="${EVAL_LINES}eval.${id}.reason=${reason}"$'\n'
    fi
  done <<EOF
$(printf '%s\n' "$TSV" | sort -t"$(printf '\037')" -k1,1n)
EOF
fi

# --- Verdict ----------------------------------------------------------------
# Structural violations already exited above, so only the behavioural half is
# left to decide.
# The phase is part of the verdict LINE, not a separate one: `self_check=invalid`
# means opposite things in the two phases (a red that never appeared vs. a green
# that never appeared), so a reader must not be able to consume the verdict
# without it (AGR-037).
if [ "$any_invalid" -eq 0 ]; then
  printf 'self_check=ready phase=%s\n' "$PHASE"
  verdict=0
else
  printf 'self_check=invalid phase=%s\n' "$PHASE"
  verdict=1
fi
printf '%s' "$EVAL_LINES"
exit "$verdict"
