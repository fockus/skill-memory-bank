#!/usr/bin/env bats
# test_mb_work_state_eval_r3.bats — svp-sdd-core round-3 review fixes, split out of
# test_mb_work_state_eval.bats to keep every zone file within the 400-line
# contract (the same reason -lib/-eval and _r2 suites exist).
#
# Kept as a SEPARATE suite rather than trimmed: these are the regression tests
# for declaration binding, source containment and anchorless Evals, and deleting coverage to fit a line
# limit would be the wrong trade.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WS="$REPO_ROOT/scripts/mb-work-state.sh"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK"
  IMPL="$TMP/impl"          # external product marker: absent = red, present = green
  GATE="$TMP/gate.sh"       # the product under test, named by the DECLARED Eval
  DECLARED="bash $GATE"
  _spec_with_eval demo 1 "$DECLARED"
  bash "$WS" init demo 1 --mb "$BANK" >/dev/null
}

# The eval gate is bound to the task's declared Eval (review [2]), so every test
# needs a real spec declaring one. _spec_with_eval writes the minimal tasks.md.
_spec_with_eval() {
  local topic="$1" no="$2" cmd="$3"
  local dir="$BANK/specs/$topic"
  mkdir -p "$dir"
  cat >"$dir/tasks.md" <<TASKS
# Tasks: $topic

<!-- mb-task:$no -->
## Task $no: the gate

**Covers:** REQ-001
**Role:** backend
**Eval:** $cmd \u2014 red: gate fails; exit: 1; output~: not ok [0-9]+ foo_gate

**DoD:**
- [ ] gate works.
<!-- /mb-task:$no -->
TASKS
  python3 - "$dir/tasks.md" <<'PYFIX'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text(encoding="utf-8").replace("\\u2014", "\u2014"), encoding="utf-8")
PYFIX
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# A realistic eval command whose OUTCOME depends on external product state, not
# on editing the command itself (models `pytest test_foo.py` failing until the
# implementation exists). Absent IMPL → red (exit 1); present → green (exit 0).
# The cmd-file always carries exactly the DECLARED command; what varies is the
# product ($GATE) it runs — which is the real-world model (`pytest test_foo.py`
# failing until the implementation exists).
_cmd_file() { printf '#!/usr/bin/env bash\n%s\n' "$DECLARED" > "$1"; }
_flip_gate() {
  printf '#!/usr/bin/env bash\nif [ -f "%s" ]; then echo "ok 1 foo_gate"; exit 0; else echo "not ok 1 foo_gate"; exit 1; fi\n' "$IMPL" > "$GATE"
}
_red_gate()   { printf '#!/usr/bin/env bash\necho "not ok 1 foo_gate"\nexit 1\n' > "$GATE"; }
_green_gate() { printf '#!/usr/bin/env bash\necho "ok 1 foo_gate"\nexit 0\n'      > "$GATE"; }
_flip_cmd()  { _flip_gate;  _cmd_file "$1"; }
_red_cmd()   { _red_gate;   _cmd_file "$1"; }
_green_cmd() { _green_gate; _cmd_file "$1"; }
_eval_field() { python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('eval',{}).get(sys.argv[2]))" "$BANK/.work-state.json" "$1"; }

# ═══ r3 [2]: the source locator is contained in the bank ═══════════════════
#
# `init spec 1 --source-path <anywhere>` and `--source-topic ../../fake` were
# accepted and stored verbatim. An out-of-bank tasks.md is a file the bank does
# not own, so its declaration can change under the gate at will — which makes
# the [1] bypass reachable without editing a bank file at all.

_init_spec() {   # _init_spec <bank> <args...>  → prints rc
  local bank="$1"; shift
  local rc=0
  bash "$WS" init spec 1 --mb "$bank" "$@" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

@test "work_state_eval: --source-path outside the bank is refused" {
  local out="$TMP/outside"; mkdir -p "$out"
  cp "$BANK/specs/demo/tasks.md" "$out/tasks.md"
  local b2="$TMP/b2/.memory-bank"; mkdir -p "$b2/specs/demo"
  cp "$BANK/specs/demo/tasks.md" "$b2/specs/demo/tasks.md"
  [ "$(_init_spec "$b2" --source-path "$out/tasks.md")" = "2" ] \
    || { echo "out-of-bank source-path accepted"; false; }
  [ ! -e "$b2/.work-state.json" ] || { echo "state written for a refused init"; false; }
}

@test "work_state_eval: --source-topic with traversal is refused" {
  local b2="$TMP/b3/.memory-bank"; mkdir -p "$b2/specs/demo"
  cp "$BANK/specs/demo/tasks.md" "$b2/specs/demo/tasks.md"
  [ "$(_init_spec "$b2" --source-topic '../../fake')" = "2" ]
  [ ! -e "$b2/.work-state.json" ]
}

@test "work_state_eval: --source-topic with a slash or dot segment is refused" {
  local b2="$TMP/b4/.memory-bank"; mkdir -p "$b2/specs/demo"
  cp "$BANK/specs/demo/tasks.md" "$b2/specs/demo/tasks.md"
  [ "$(_init_spec "$b2" --source-topic 'a/b')" = "2" ]
  [ "$(_init_spec "$b2" --source-topic '.')" = "2" ]
  [ "$(_init_spec "$b2" --source-topic '')" = "2" ]
}

@test "work_state_eval: a symlinked spec dir escaping the bank is refused" {
  local out="$TMP/escape"; mkdir -p "$out"
  cp "$BANK/specs/demo/tasks.md" "$out/tasks.md"
  local b2="$TMP/b5/.memory-bank"; mkdir -p "$b2/specs"
  ln -s "$out" "$b2/specs/evil"
  [ "$(_init_spec "$b2" --source-topic evil)" = "2" ] \
    || { echo "symlink escape accepted"; false; }
}

@test "work_state_eval: the canonical spec topic is accepted and normalised" {
  local b2="$TMP/b6/.memory-bank"; mkdir -p "$b2/specs/demo"
  cp "$BANK/specs/demo/tasks.md" "$b2/specs/demo/tasks.md"
  [ "$(_init_spec "$b2" --source-topic demo)" = "0" ]
  run python3 -c "import json;d=json.load(open('$b2/.work-state.json'));print(d['source_path'])"
  [ "$status" -eq 0 ]
  # The resolver stores the PHYSICAL path (realpath), so compare physically —
  # on macOS $TMPDIR is /var -> /private/var.
  local expect; expect="$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$b2/specs/demo/tasks.md")"
  [ "$output" = "$expect" ] \
    || { echo "source_path not normalised to the canonical path: $output != $expect"; false; }
}

@test "work_state_eval: --source-path equal to the canonical path is accepted" {
  local b2="$TMP/b7/.memory-bank"; mkdir -p "$b2/specs/demo"
  cp "$BANK/specs/demo/tasks.md" "$b2/specs/demo/tasks.md"
  [ "$(_init_spec "$b2" --source-topic demo --source-path "$b2/specs/demo/tasks.md")" = "0" ]
}

# ═══ r3 [1]: the DECLARATION is bound at init, not re-read at done ═════════
#
# `done` re-read the declaration from the live tasks.md, so swapping a real
# `**Eval:**` for `none — waiver: temporary` between init and done produced
# rc=0 and eval_gate='waived:eval_none' without a single Eval run. Round 2
# snapshotted the eval COMMAND; presence and waiver status stayed mutable.

_swap_decl() {   # _swap_decl <tasks.md> <new Eval line>
  python3 - "$1" "$2" <<'PY'
import re, sys
p, new = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s = re.sub(r"^\*\*Eval:\*\*.*$", new, s, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PY
}

@test "work_state_eval: swapping the declaration to a waiver after init is refused" {
  # Drive a full red->green FIRST, so the refusal is attributable to the
  # declaration binding and not merely to "no eval was ever run".
  local c="$TMP/cmd.sh"; _flip_cmd "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK" >/dev/null
  : > "$IMPL"
  bash "$WS" eval-green --cmd-file "$c" --mb "$BANK" >/dev/null
  _swap_decl "$BANK/specs/demo/tasks.md" '**Eval:** none — waiver: temporary'
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 5 ] || { echo "declaration swap certified a done (rc=$status): $output"; false; }
  run python3 -c "import json;print(json.load(open('$BANK/.work-state.json')).get('phase'))"
  [ "$output" != "done" ] || { echo "phase flipped to done anyway"; false; }
}

@test "work_state_eval: deleting tasks.md after init is refused, not NOFILE" {
  # Drive a full red->green FIRST, so the refusal is attributable to the
  # declaration binding and not merely to "no eval was ever run".
  local c="$TMP/cmd.sh"; _flip_cmd "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK" >/dev/null
  : > "$IMPL"
  bash "$WS" eval-green --cmd-file "$c" --mb "$BANK" >/dev/null
  rm -f "$BANK/specs/demo/tasks.md"
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 5 ] || { echo "vanished declaration treated as NOFILE (rc=$status)"; false; }
}

@test "work_state_eval: changing the declared COMMAND after init is refused" {
  local c="$TMP/cmd.sh"; _flip_cmd "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK" >/dev/null
  : > "$IMPL"
  bash "$WS" eval-green --cmd-file "$c" --mb "$BANK" >/dev/null
  # Sanity: without any tampering this state is done-able.
  _swap_decl "$BANK/specs/demo/tasks.md" '**Eval:** bash /tmp/other.sh — red: gate fails; exit: 1; output~: not ok [0-9]+ foo_gate'
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 5 ]
}

@test "work_state_eval: changing the declared ANCHORS after init is refused" {
  local c="$TMP/cmd.sh"; _flip_cmd "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK" >/dev/null
  : > "$IMPL"
  bash "$WS" eval-green --cmd-file "$c" --mb "$BANK" >/dev/null
  # Sanity: without any tampering this state is done-able.
  _swap_decl "$BANK/specs/demo/tasks.md" "**Eval:** bash $GATE — red: gate fails; exit: 1; output~: something else"
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 5 ]
}

@test "work_state_eval: a declaration bound as WAIVED still allows done" {
  local b2="$TMP/w1/.memory-bank"; mkdir -p "$b2/specs/demo"
  printf '# Tasks\n\n<!-- mb-task:1 -->\n## Task 1\n**Eval:** none — waiver: agreed\n<!-- /mb-task:1 -->\n' \
    > "$b2/specs/demo/tasks.md"
  bash "$WS" init spec 1 --source-topic demo --mb "$b2" >/dev/null
  run bash "$WS" done --mb "$b2"
  [ "$status" -eq 0 ] || { echo "a genuinely waived task was refused: $output"; false; }
  run python3 -c "import json;print(json.load(open('$b2/.work-state.json')).get('eval_gate'))"
  [ "$output" = "waived:eval_none" ]
}

@test "work_state_eval: a declaration that APPEARS after a NOFILE init is refused" {
  # Bound NOFILE, live CMD: the gate must not silently start applying a
  # declaration that did not exist when the run was bound.
  local b2="$TMP/w2/.memory-bank"; mkdir -p "$b2"
  bash "$WS" init plan 1 --source-topic ghost --mb "$b2" >/dev/null 2>&1 || true
  if [ -e "$b2/.work-state.json" ]; then
    mkdir -p "$b2/specs/ghost"
    cp "$BANK/specs/demo/tasks.md" "$b2/specs/ghost/tasks.md"
    run bash "$WS" done --mb "$b2"
    [ "$status" -eq 5 ] || { echo "late-appearing declaration accepted (rc=$status)"; false; }
  fi
}

@test "work_state_eval: an untouched declaration still completes red→green→done" {
  # The whole point: binding must not break the legitimate path.
  local c="$TMP/cmd.sh"; _flip_cmd "$c"
  run bash "$WS" eval-red --cmd-file "$c" \
    --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "red failed: $output"; false; }
  : > "$IMPL"
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "green failed: $output"; false; }
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "done failed: $output"; false; }
  run python3 -c "import json;print(json.load(open('$BANK/.work-state.json')).get('eval_gate'))"
  [ "$output" = "verified:red_green" ]
}

# ═══ r3 [3]: the normative anchorless (non-gated) Eval ═════════════════════
#
# design.md C1: `exit:` and `output~:` are BOTH optional for a task that does
# not cover a gated (SHALL/MUST) REQ; C6 then records `red_anchor: none` and
# judges red by `exit != 0`. The implementation demanded --output-re (exit 2)
# and, worse, ACCEPTED a caller-invented `--output-re '.*'` — certifying a red
# against an anchor the declaration never contained.

_spec_anchorless() {   # <bank> <topic> <no> <cmd>
  local dir="$1/specs/$2"; mkdir -p "$dir"
  printf '# Tasks\n\n<!-- mb-task:%s -->\n## Task %s\n**Eval:** %s \xe2\x80\x94 red: exits non-zero\n<!-- /mb-task:%s -->\n' \
    "$3" "$3" "$4" "$3" > "$dir/tasks.md"
}

_anchorless_bank() {   # echoes a bank whose task 1 declares an anchorless Eval
  local b="$TMP/al/.memory-bank"
  rm -rf "$TMP/al"; mkdir -p "$b"
  _spec_anchorless "$b" demo 1 "bash $GATE"
  bash "$WS" init spec 1 --source-topic demo --mb "$b" >/dev/null
  printf '%s' "$b"
}

@test "work_state_eval: anchorless declaration accepts eval-red with NO --output-re" {
  local b; b="$(_anchorless_bank)"
  _red_gate
  local c="$TMP/cmd.sh"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --mb "$b"
  [ "$status" -eq 0 ] || { echo "anchorless red refused: $output"; false; }
}

@test "work_state_eval: anchorless red records red_anchor=none" {
  local b; b="$(_anchorless_bank)"
  _red_gate
  local c="$TMP/cmd.sh"; _cmd_file "$c"
  bash "$WS" eval-red --cmd-file "$c" --mb "$b" >/dev/null
  run python3 -c "import json;print(json.load(open('$b/.work-state.json'))['eval'].get('red_anchor'))"
  [ "$output" = "none" ] || { echo "red_anchor not recorded as none: $output"; false; }
}

@test "work_state_eval: anchorless judges red purely by a non-zero exit" {
  local b; b="$(_anchorless_bank)"
  _green_gate                       # exits 0 → NOT a red, even with no anchor
  local c="$TMP/cmd.sh"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --mb "$b"
  [ "$status" -eq 1 ] || { echo "exit 0 accepted as red (rc=$status)"; false; }
}

@test "work_state_eval: a caller-invented anchor on an anchorless task is refused" {
  # The sharp end: `--output-re '.*'` used to return 0 and be recorded as the
  # anchor this red was judged against.
  local b; b="$(_anchorless_bank)"
  _red_gate
  local c="$TMP/cmd.sh"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re '.*' --mb "$b"
  [ "$status" -eq 2 ] || { echo "invented anchor accepted (rc=$status): $output"; false; }
  # Exit 2 alone is not enough: several unrelated failures also exit 2, so the
  # refusal must be attributable to THIS rule.
  echo "$output" | grep -q 'declares no output~ anchor' \
    || { echo "rejected for some other reason: $output"; false; }
}

@test "work_state_eval: a caller-invented --expected-exit on an anchorless task is refused" {
  local b; b="$(_anchorless_bank)"
  _red_gate
  local c="$TMP/cmd.sh"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --expected-exit 1 --mb "$b"
  [ "$status" -eq 2 ] || { echo "invented exit anchor accepted (rc=$status)"; false; }
  echo "$output" | grep -q 'declares no exit: anchor' \
    || { echo "rejected for some other reason: $output"; false; }
}

@test "work_state_eval: anchorless completes red→green→done" {
  local b; b="$(_anchorless_bank)"
  _flip_gate
  local c="$TMP/cmd.sh"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --mb "$b"
  [ "$status" -eq 0 ] || { echo "red failed: $output"; false; }
  : > "$IMPL"
  run bash "$WS" eval-green --cmd-file "$c" --mb "$b"
  [ "$status" -eq 0 ] || { echo "green failed: $output"; false; }
  run bash "$WS" done --mb "$b"
  [ "$status" -eq 0 ] || { echo "done failed: $output"; false; }
  run python3 -c "import json;print(json.load(open('$b/.work-state.json')).get('eval_gate'))"
  [ "$output" = "verified:red_green" ]
}

@test "work_state_eval: a GATED task still requires its declared anchor" {
  # The converse guard: making output-re optional must not weaken gated tasks.
  _red_gate
  local c="$TMP/cmd.sh"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'something else' --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "wrong anchor accepted on a gated task"; false; }
}

@test "work_state_eval: a gated task with no --output-re falls back to the DECLARED anchor" {
  _red_gate
  local c="$TMP/cmd.sh"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "declared anchor not used as the default: $output"; false; }
  run python3 -c "import json;print(json.load(open('$BANK/.work-state.json'))['eval'].get('output_re'))"
  [ "$output" = "not ok [0-9]+ foo_gate" ]
}
