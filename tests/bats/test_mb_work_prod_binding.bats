#!/usr/bin/env bats
# svp-sdd-core round-2 review [9] + [11] — the PRODUCTION path.
#
# Round 1's eval gates were green in their own suite and dead in a real
# `/mb work`, because the binding they depend on never resolved:
#
#   [9]  mb-work-plan.sh emits `"source": "spec"` — the CATEGORY, not the spec
#        topic. `init <source>` therefore stores "spec", and the eval lookup
#        targets `<bank>/specs/spec/tasks.md`, which never exists. Every
#        declaration-bound gate silently degraded to "no Eval resolvable".
#   [11] `done` wrote `phase: done` unconditionally — no eval gate at all, so a
#        bare `init` + `done` certified a task that never ran its Eval.
#
# These tests drive the real scripts through the documented call sequence, so a
# fix that is green only in the unit suites cannot pass them.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WS="$REPO_ROOT/scripts/mb-work-state.sh"
  PLAN="$REPO_ROOT/scripts/mb-work-plan.sh"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK"
  TOPIC="binding-demo"
  GATE="$TMP/gate.sh"
  DECLARED="bash $GATE"
  _spec_with_eval "$TOPIC" 1 "$DECLARED"
}

teardown() {
  rm -rf "$TMP"
}

# A minimal but REAL v2 spec triple: mb-work-plan.sh parses tasks.md through
# mb_work_items.py, so the fixture must satisfy that parser, not a stub.
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
**Blocked-by:** none
**Scope:** scripts/**
**Budget:** 100000

**What to do:**
- wire the gate

**Eval:** \`$cmd\` — red: not implemented; exit: 1; output~: \`GATE-RED\`

**DoD:**
- [ ] gate wired
TASKS
}

# The product under test: red until the marker file exists, green after.
_write_gate() {
  cat >"$GATE" <<GATESH
#!/usr/bin/env bash
if [ -f "$TMP/impl" ]; then echo GATE-GREEN; exit 0; fi
echo GATE-RED
exit 1
GATESH
}

_cmd_file() {
  printf '%s\n' "$DECLARED" > "$TMP/cmd.sh"
  printf '%s' "$TMP/cmd.sh"
}

# ── [9] the plan → init → eval binding must resolve end to end ──────────────

@test "prod_binding [9]: plan JSON carries the spec topic, not just the category" {
  run bash "$PLAN" --target "$TOPIC" --range 1 --mb "$BANK"
  [ "$status" -eq 0 ]
  # `source` stays the category (documented contract) ...
  echo "$output" | grep -q '"source": "spec"'
  # ... and the topic/path travel in their own fields, so init can bind them.
  echo "$output" | grep -q "\"source_topic\": \"$TOPIC\""
  echo "$output" | grep -q '"source_path": ".*tasks\.md"'
}

@test "prod_binding [9]: init records the topic so eval-red resolves the declaration" {
  _write_gate
  local sp
  sp=$(bash "$PLAN" --target "$TOPIC" --range 1 --mb "$BANK" \
        | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["source_path"])')
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  # The regression: this used to die with "no Eval declaration resolvable for spec#1".
  run bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 1
  [ "$status" -eq 0 ]
  run bash "$WS" status --mb "$BANK"
  echo "$output" | grep -q '"red_match": true'
}

@test "prod_binding [9]: bare category source is refused, never silently ungated" {
  # The refusal now happens at `init` (see the gap tests below) rather than
  # later at eval-red: the category form never produces a state at all, so the
  # window in which the gate could evaporate is closed instead of narrowed.
  _write_gate
  run bash "$WS" init spec 1 --mb "$BANK"
  [ "$status" -ne 0 ]
  [ ! -f "$BANK/.work-state.json" ]
  # A state built with a topic that does not resolve still fails eval-red closed.
  bash "$WS" init ghost-topic 1 --mb "$BANK" >/dev/null
  run bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 1
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'no Eval declaration resolvable'
}

# ── [11] done must not certify a task whose Eval never went red→green ───────

@test "prod_binding [11]: init then done is refused with no eval at all" {
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  run bash "$WS" done --mb "$BANK"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'eval'
  run bash "$WS" status --mb "$BANK"
  echo "$output" | grep -q '"phase": "in-progress"'
}

@test "prod_binding [11]: done is refused when red proved but green still red" {
  _write_gate
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 1
  # green run still fails (impl marker absent) → green_exit != 0
  run bash "$WS" eval-green --mb "$BANK" --cmd-file "$TMP/cmd.sh"
  [ "$status" -ne 0 ]
  run bash "$WS" done --mb "$BANK"
  [ "$status" -ne 0 ]
  run bash "$WS" status --mb "$BANK"
  echo "$output" | grep -q '"phase": "in-progress"'
}

@test "prod_binding [11]: done succeeds only after a real red then green" {
  _write_gate
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 1
  touch "$TMP/impl"   # implement the product
  run bash "$WS" eval-green --mb "$BANK" --cmd-file "$TMP/cmd.sh"
  [ "$status" -eq 0 ]
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 0 ]
  run bash "$WS" status --mb "$BANK"
  echo "$output" | grep -q '"phase": "done"'
}

@test "prod_binding [11]: a hand-edited green_exit does not buy a done" {
  _write_gate
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 1
  python3 - "$BANK/.work-state.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["eval"]["green_exit"] = 0          # forge the green without running it
json.dump(d, open(p, "w"))
PY
  run bash "$WS" done --mb "$BANK"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'proof\|tamper'
}

# ── the waiver and the no-declaration-surface cases stay usable ─────────────

@test "prod_binding [11]: an Eval:none waiver still allows done" {
  local dir="$BANK/specs/waived"
  mkdir -p "$dir"
  cat >"$dir/tasks.md" <<'TASKS'
# Tasks: waived

<!-- mb-task:1 -->
## Task 1: docs only

**Covers:** REQ-001
**Role:** developer
**Blocked-by:** none
**Scope:** docs/**
**Budget:** 100000

**What to do:**
- write docs

**Eval:** none — waiver: documentation-only task

**DoD:**
- [ ] docs written
TASKS
  bash "$WS" init spec 1 --mb "$BANK" \
    --source-path "$dir/tasks.md" --source-topic waived >/dev/null
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "prod_binding [11]: a source with no declaration surface stays ungated" {
  # Legacy/ad-hoc sources (plain plan stages) declare no Eval anywhere; the
  # gate must not invent one for them.
  local b2="$TMP/b2"; mkdir -p "$b2"
  bash "$WS" init src 7 --mb "$b2" >/dev/null
  run bash "$WS" done --mb "$b2"
  [ "$status" -eq 0 ]
  run bash "$WS" status --mb "$b2"
  echo "$output" | grep -q '"phase": "done"'
}

@test "prod_binding [11]: a resolvable source missing the item fails closed" {
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 99 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  run bash "$WS" done --mb "$BANK"
  [ "$status" -ne 0 ]
}

# ── [10] the red anchors must come from the DECLARATION, not the caller ─────

@test "prod_binding [10]: caller cannot substitute its own output-re for the declared one" {
  _write_gate
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  # The task declares output~ `GATE-RED` and exit 1. A caller passing a DIFFERENT
  # anchor could certify an unrelated failure as this task's genuine red.
  run bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE' --expected-exit 1
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'anchor\|output~\|declared'
}

@test "prod_binding [10]: caller cannot substitute its own expected-exit" {
  _write_gate
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  run bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 2
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'anchor\|exit\|declared'
}

@test "prod_binding [10]: the declared anchors are accepted" {
  _write_gate
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  run bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 1
  [ "$status" -eq 0 ]
}

@test "prod_binding [10]: the proof records the declared anchors" {
  _write_gate
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 1
  run bash "$WS" status --mb "$BANK"
  echo "$output" | grep -q 'GATE-RED'
  # Tampering with the recorded anchor must invalidate the proof.
  python3 - "$BANK/.work-state.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["eval"]["output_re"] = "anything"
json.dump(d, open(p, "w"))
PY
  run bash "$WS" eval-green --mb "$BANK" --cmd-file "$TMP/cmd.sh"
  [ "$status" -ne 0 ]
}

# ── round-2 verification gap: a green `done` must state whether it was checked ─
#
# The [11] gate held with locators but evaporated on `init spec 1`, and the
# resulting `done` was indistinguishable from a verified one: rc=0, phase=done,
# no marker, no message. Two changes close it:
#   (a) `init` refuses the bare CATEGORY form outright — `spec`/`plan` are not
#       locators, and a spec task always lives in a tasks.md, so there is no
#       legitimate call. Closing beats labelling when the input is invalid.
#   (b) every `done` records `eval_gate`, so paths that CANNOT be closed
#       (unresolvable topic, legacy state, plan stage) degrade honestly per
#       AGR-013 rather than passing as verified.

@test "prod_binding gap: init refuses the bare category 'spec' with no locator" {
  run bash "$WS" init spec 1 --mb "$BANK"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'locator\|--source-topic\|--source-path'
}

@test "prod_binding gap: init refuses the bare category 'plan' with no locator" {
  run bash "$WS" init plan 1 --mb "$BANK"
  [ "$status" -ne 0 ]
}

@test "prod_binding gap: a real topic passed positionally still works" {
  # Guards over-correction: only the CATEGORY literals are refused.
  run bash "$WS" init "$TOPIC" 1 --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "prod_binding gap: a verified done is marked verified" {
  _write_gate
  local sp="$BANK/specs/$TOPIC/tasks.md"
  bash "$WS" init spec 1 --mb "$BANK" --source-path "$sp" --source-topic "$TOPIC" >/dev/null
  bash "$WS" eval-red --mb "$BANK" --cmd-file "$(_cmd_file)" \
        --output-re 'GATE-RED' --expected-exit 1
  touch "$TMP/impl"
  bash "$WS" eval-green --mb "$BANK" --cmd-file "$TMP/cmd.sh"
  bash "$WS" done --mb "$BANK"
  run bash "$WS" status --mb "$BANK"
  echo "$output" | grep -q '"eval_gate": "verified:red_green"'
}

@test "prod_binding gap: a waived done is marked waived, not verified" {
  local dir="$BANK/specs/waived"
  mkdir -p "$dir"
  cat >"$dir/tasks.md" <<'TASKS'
# Tasks: waived

<!-- mb-task:1 -->
## Task 1: docs only

**Covers:** REQ-001
**Role:** developer
**Blocked-by:** none
**Scope:** docs/**
**Budget:** 100000

**What to do:**
- write docs

**Eval:** none — waiver: documentation-only task

**DoD:**
- [ ] docs written
TASKS
  bash "$WS" init spec 1 --mb "$BANK" \
    --source-path "$dir/tasks.md" --source-topic waived >/dev/null
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'waiv'
  run bash "$WS" status --mb "$BANK"
  echo "$output" | grep -q '"eval_gate": "waived:eval_none"'
}

@test "prod_binding gap: an unresolvable source degrades HONESTLY, not silently" {
  # A topic that resolves to no tasks.md cannot be gated. It must say so —
  # in the state AND on stdout — instead of looking like a checked pass.
  bash "$WS" init ghost-topic 1 --mb "$BANK" >/dev/null
  run bash "$WS" done --mb "$BANK"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'unverified\|not verified\|no declaration'
  run bash "$WS" status --mb "$BANK"
  echo "$output" | grep -q '"eval_gate": "unverified:no_declaration_surface"'
}

@test "prod_binding gap: INVARIANT — no done is ever recorded without an eval_gate" {
  # The regression the reviewer asked for: whatever path produced phase=done,
  # the state must carry either a verified proof or an explicit unverified mark.
  local b="$TMP/inv"; mkdir -p "$b"
  bash "$WS" init ghost-topic 3 --mb "$b" >/dev/null
  bash "$WS" done --mb "$b" >/dev/null
  run bash "$WS" status --mb "$b"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"phase": "done"'
  # must be one of the three honest verdicts — never absent, never empty
  echo "$output" | grep -qE '"eval_gate": "(verified:red_green|waived:eval_none|unverified:[a-z_]+)"'
}
