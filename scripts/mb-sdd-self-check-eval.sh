#!/usr/bin/env bash
# mb-sdd-self-check-eval.sh — the per-declaration half of the C8a battery:
# how ONE `**Eval:**` declaration is classified in a given phase.
#
# Sourced by `mb-sdd-self-check.sh`, which owns the other half — resolving the
# triple, delegating the structural battery, parsing tasks, ordering the output
# and owning the exit code. The split follows the boundary the code already had
# (one declaration vs. the whole battery) and the convention this repo already
# uses for the same reason: `mb-work-state.sh` → `mb-work-state-eval.sh`.
# Prompted by the S2 zone's 400-line contract (AGR-035), cut at the seam rather
# than at the line number.
#
# Contract with the caller:
#   in  : $RUN_ROOT — the directory Eval commands are executed from (the caller
#         resolves it: local bank → its parent checkout, global bank → the
#         working checkout).
#   call: classify_eval <cmd> <expected_exit> <output_re> <phase>
#   out : `status` optionally followed by <US>(\037) and an attributable reason.
#         Statuses: ready | pending_materialization | invalid.
#
# The reason vocabulary and the phase semantics are documented in
# `mb-sdd-self-check.sh`'s header, which is the single place a reader is sent to.
#
# shellcheck shell=bash

# --- Behavioural Eval preflight (C8.4) --------------------------------------
# classify_eval <cmd> <expected_exit> <output_re> <phase>
#   → prints `status` optionally followed by <US> and an attributable reason.
classify_eval() {
  local cmd="$1" exp="$2" ore="$3" phase="$4"
  # Nothing to run, in EITHER phase. Reported as `ready` with a reason rather
  # than `pending_materialization`, because "this task waived its Eval" and
  # "this task's eval is not written yet" are different facts — and in
  # phase=done the second one is a failure while the first stays legitimate.
  # Before AGR-037 both printed the same word and were indistinguishable.
  [ -n "$cmd" ] || { printf 'ready\037no_declaration'; return; }
  case "$cmd" in
    none|None|NONE) printf 'ready\037waived'; return ;;
  esac
  # `exit: 0` contradicts the definition of a red (review [6]): reject the
  # declaration outright rather than letting it license a green-as-red.
  if [ -n "$exp" ] && [ "$exp" = "0" ]; then printf 'invalid\037exit_zero_declared'; return; fi

  # Shell-aware tokenisation (respects quotes, so a target path with a space is
  # resolved correctly — major #12). shlex mirrors how `eval "$cmd"` splits the
  # command at execution time. Emits a pre-verdict:
  #   PENDING  — at least one declared target is missing
  #   NOTARGET — the command names no target path at all (nothing to resolve;
  #              kept apart from PENDING because in phase=done a command with no
  #              path token is still runnable, while a MISSING target is a
  #              failure — one word for both would have merged the two)
  #   TOOL     — targets resolve but the runner tool is unavailable
  #   MALFORMED— unbalanced quotes, or no runner left after env assignments
  #   RUN      — everything resolves; run it
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
    print("MALFORMED"); sys.exit(0)
targets = [t for t in toks if "/" in t and not t.startswith("-")]
missing = [
    # RUN_ROOT only: the command is executed from there, so that is the sole
    # place a repo-relative target can be said to exist. Consulting the cwd of
    # the CALLER let a same-named local file flip pending_materialization to RUN.
    t for t in targets if not os.path.exists(os.path.join(root, t))
]
if missing:
    # Precedence preserved from before AGR-037: a missing target outranks an
    # unavailable runner, so an absent-target task keeps reporting the state
    # that describes it rather than a tool problem it never reached.
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
print("RUN" if targets else "NOTARGET")
PY
)"
  case "$pre" in
    PENDING)
      # The one place the two phases disagree about an absent target: before
      # implementation it is expected (D-05), after it is a task that never
      # materialised its own contract.
      if [ "$phase" = "done" ]; then
        printf 'invalid\037target_missing'
      else
        printf 'pending_materialization\037target_absent'
      fi
      return ;;
    NOTARGET)
      # Nothing to resolve. In generation there is no way to tell an unwritten
      # eval from a written one, so the honest answer is still "not observed";
      # in done the command is simply run and judged by its exit.
      if [ "$phase" = "done" ]; then
        :
      else
        printf 'pending_materialization\037no_target_token'; return
      fi
      ;;
    TOOL) printf 'invalid\037tool_unavailable'; return ;;
    MALFORMED) printf 'invalid\037malformed_command'; return ;;
    RUN) : ;;
    *) printf 'invalid\037classify_failed'; return ;;
  esac

  # Run the command byte-identical from the run root, capture combined output.
  local out rc
  set +e
  out="$(cd "$RUN_ROOT" && eval "$cmd" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 127 ]; then printf 'invalid\037tool_unavailable'; return; fi

  # phase=done: the only question is whether the Eval actually passes. The red
  # anchors are irrelevant here — they describe the state BEFORE the code
  # existed, and demanding them after implementation is exactly the trap
  # AGR-037 closes.
  if [ "$phase" = "done" ]; then
    if [ "$rc" -eq 0 ]; then printf 'ready'; else printf 'invalid\037not_green'; fi
    return
  fi

  # phase=generation: the DECLARED red must be observed, and each way of
  # failing that names itself (I-172) instead of collapsing into a bare
  # `invalid` that costs a source read to interpret.
  #
  # A red is by DEFINITION a failing run. Without this first check, a command
  # that merely printed the declared `output~:` anchor and exited 0 was recorded
  # as `ready` — precisely how a green command impersonates a red (review [6]).
  if [ "$rc" -eq 0 ]; then printf 'invalid\037already_green'; return; fi
  if [ -n "$ore" ]; then
    # `--` ends option parsing: a valid ERE starting with '-' (e.g. `-FAIL`) is
    # a pattern, not a grep flag. The validator already uses `grep -E --`, so
    # without this the two disagreed about the same declaration (review [21]).
    if ! printf '%s\n' "$out" | grep -Eq -- "$ore"; then
      printf 'invalid\037anchor_mismatch'; return
    fi
  fi
  if [ -n "$exp" ] && [ "$rc" -ne "$exp" ]; then
    printf 'invalid\037exit_mismatch'; return
  fi
  # An ANCHORLESS declaration is valid by C1 — anchors are mandatory only for a
  # task covering a gated REQ (REQ-055, enforced structurally above), and for a
  # non-gated one «red считается по exit != 0» (review [7]). The `rc != 0`
  # check above is what still keeps a green command from impersonating a red.
  printf 'ready'
}
