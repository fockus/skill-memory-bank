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
#
# Battery (C8.1–C8.5):
#   - Structural C8.1–C8.3, C8.5 are delegated to `mb-spec-validate.sh`
#     (v2 fields, gated `output~:` anchor, seam/cycle/role/scenario-parity,
#     cross-spec Blocked-by resolution). Its non-zero exit is a structural
#     violation.
#   - Behavioural Eval preflight C8.4 (the core of this task, REQ-054): for each
#     task the helper resolves the Eval command's target tokens (tokens that
#     contain `/` and do not start with `-`, per C1). When ALL targets exist the
#     helper runs the command and must OBSERVE the declared red anchor
#     (`output~:` ERE and, when declared, `exit:`) → `ready`. An already-green
#     command or a red that does not match the anchor → `invalid`. A missing
#     target → `pending_materialization` (an honest "eval not materialised yet",
#     NOT a failure). A missing runner tool at an existing target → `invalid`
#     with reason `tool_unavailable` (never `ready`, never counted as red).
#
# stdout : first line `self_check=ready|invalid`, then one
#          `eval.<task-id>=ready|pending_materialization|invalid` per task in
#          ascending task-id order.
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
structural_ok=1
set +e
if [ -n "$MB_BANK" ]; then
  "$SCRIPT_DIR/mb-spec-validate.sh" "$SPEC_ARG" "$MB_BANK" >/dev/null 2>&1
else
  "$SCRIPT_DIR/mb-spec-validate.sh" "$SPEC_ARG" >/dev/null 2>&1
fi
sv_exit=$?
set -e
if [ "$sv_exit" -eq 2 ]; then
  printf 'error=spec_validate_usage\n' >&2
  exit 2
fi
[ "$sv_exit" -eq 0 ] || structural_ok=0

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
# classify <cmd> <expected_exit> <output_re> → prints one status word.
classify_eval() {
  local cmd="$1" exp="$2" ore="$3"
  [ -n "$cmd" ] || { printf 'pending_materialization'; return; }
  # cmd 'none' (non-gated / waiver) — nothing to run behaviourally.
  case "$cmd" in
    none|None|NONE) printf 'pending_materialization'; return ;;
  esac
  # `exit: 0` contradicts the definition of a red (review [6]): reject the
  # declaration outright rather than letting it license a green-as-red.
  if [ -n "$exp" ] && [ "$exp" = "0" ]; then printf 'invalid'; return; fi

  # Shell-aware tokenisation (respects quotes, so a target path with a space is
  # resolved correctly — major #12). shlex mirrors how `eval "$cmd"` splits the
  # command at execution time. Emits a pre-verdict:
  #   PENDING  — no target token, or at least one target is missing
  #   TOOL     — all targets exist but the runner tool is unavailable
  #   MALFORMED— unbalanced quotes
  #   RUN      — all targets exist and the runner is available
  local pre
  pre="$(CMD="$cmd" RUN_ROOT="$RUN_ROOT" python3 - <<'PY'
import os, re, shlex, shutil, sys
cmd = os.environ["CMD"]
root = os.environ["RUN_ROOT"]
try:
    toks = shlex.split(cmd)
except ValueError:
    print("MALFORMED"); sys.exit(0)
if not toks:
    print("PENDING"); sys.exit(0)
targets = [t for t in toks if "/" in t and not t.startswith("-")]
if not targets:
    print("PENDING"); sys.exit(0)
for t in targets:
    if not (os.path.exists(os.path.join(root, t)) or os.path.exists(t)):
        print("PENDING"); sys.exit(0)
# `VAR=value cmd ...` is valid shell: the leading assignments are environment,
# not the runner. Treating `PYTHONPATH=src` as the tool made shutil.which fail
# and rejected a perfectly valid Eval as an unavailable tool (review [16]).
rest = list(toks)
while rest and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", rest[0]):
    rest.pop(0)
if not rest:
    print("MALFORMED"); sys.exit(0)
runner = rest[0]
if "/" not in runner and shutil.which(runner) is None:
    print("TOOL"); sys.exit(0)
print("RUN")
PY
)"
  case "$pre" in
    PENDING) printf 'pending_materialization'; return ;;
    TOOL|MALFORMED) printf 'invalid'; return ;;
    RUN) : ;;
    *) printf 'invalid'; return ;;
  esac

  # Run the command byte-identical from the run root, capture combined output.
  local out rc
  set +e
  out="$(cd "$RUN_ROOT" && eval "$cmd" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 127 ]; then printf 'invalid'; return; fi

  # Observe the DECLARED red: output must match output_re and (when declared)
  # the exit must equal the declared exit. Without any anchor a red cannot be
  # confirmed → invalid.
  # A red is by DEFINITION a failing run. Without this, a command that merely
  # printed the declared output~ anchor and exited 0 was recorded as `ready`,
  # which is precisely how a green command impersonates a red (review [6]).
  # `exit: 0` is rejected structurally below, so this cannot be declared away.
  local red=1
  [ "$rc" -ne 0 ] || red=0
  if [ -n "$ore" ]; then
    # `--` ends option parsing: a valid ERE starting with '-' (e.g. `-FAIL`) is
    # a pattern, not a grep flag. The validator already uses `grep -E --`, so
    # without this the two disagreed about the same declaration (review [21]).
    printf '%s\n' "$out" | grep -Eq -- "$ore" || red=0
  fi
  if [ -n "$exp" ]; then
    [ "$rc" -eq "$exp" ] || red=0
  fi
  if [ -z "$ore" ] && [ -z "$exp" ]; then red=0; fi

  if [ "$red" -eq 1 ]; then printf 'ready'; else printf 'invalid'; fi
}

any_invalid=0
EVAL_LINES=""
if [ -n "$TSV" ]; then
  # Ascending task-id order.
  while IFS="$(printf '\037')" read -r id cmd exp ore; do
    [ -n "$id" ] || continue
    status="$(classify_eval "$cmd" "$exp" "$ore")"
    case "$status" in invalid) any_invalid=1 ;; esac
    EVAL_LINES="${EVAL_LINES}eval.${id}=${status}"$'\n'
  done <<EOF
$(printf '%s\n' "$TSV" | sort -t"$(printf '\037')" -k1,1n)
EOF
fi

# --- Verdict ----------------------------------------------------------------
if [ "$structural_ok" -eq 1 ] && [ "$any_invalid" -eq 0 ]; then
  printf 'self_check=ready\n'
  verdict=0
else
  printf 'self_check=invalid\n'
  verdict=1
fi
printf '%s' "$EVAL_LINES"
exit "$verdict"
