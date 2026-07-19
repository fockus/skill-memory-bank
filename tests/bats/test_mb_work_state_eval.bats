#!/usr/bin/env bats
# work_state_eval: — svp-sdd-core C6 eval-red/eval-green subcommands on the
# authoritative durable writer scripts/mb-work-state.sh (REQ-008, closes F-010).
#
# The helper is the SOLE executor and judge: it snapshots + runs the --cmd-file
# itself and derives red/green from OBSERVED state. A red requires an actual
# non-zero exit AND an output match; eval-green requires a PROVEN completed red
# transition (valid helper-owned `sig`, red_observed=true, red_match=true) plus
# byte-identical cmd — so a verdict cannot be spoofed via CLI or a hand-edited
# state object. Old subcommands must stay byte-identical.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WS="$REPO_ROOT/scripts/mb-work-state.sh"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK"
  bash "$WS" init demo 1 --mb "$BANK" >/dev/null
  IMPL="$TMP/impl"          # external product marker: absent = red, present = green
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# A realistic eval command whose OUTCOME depends on external product state, not
# on editing the command itself (models `pytest test_foo.py` failing until the
# implementation exists). Absent IMPL → red (exit 1); present → green (exit 0).
_flip_cmd() {
  printf '#!/usr/bin/env bash\nif [ -f "%s" ]; then echo "ok 1 foo_gate"; exit 0; else echo "not ok 1 foo_gate"; exit 1; fi\n' "$IMPL" > "$1"
}
_red_cmd()   { printf '#!/usr/bin/env bash\necho "not ok 1 foo_gate"\nexit 1\n' > "$1"; }
_green_cmd() { printf '#!/usr/bin/env bash\necho "ok 1 foo_gate"\nexit 0\n'      > "$1"; }
_eval_field() { python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('eval',{}).get(sys.argv[2]))" "$BANK/.work-state.json" "$1"; }

@test "work_state_eval: eval-red on observed red → exit 0, records signed eval object" {
  local c="$TMP/cmd.sh"; _red_cmd "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(_eval_field red_observed)" = "True" ]
  [ "$(_eval_field red_exit)" = "1" ]
  [ "$(_eval_field green_exit)" = "None" ]
  [ "$(_eval_field sig)" != "None" ] && [ -n "$(_eval_field sig)" ]
  [ "$(_eval_field cmd_hash)" != "None" ] && [ -n "$(_eval_field cmd_hash)" ]
}

@test "work_state_eval: spoofing impossible — a green command never yields red_observed=true" {
  local c="$TMP/cmd.sh"; _green_cmd "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 1 ]
  [ "$(_eval_field red_observed)" = "False" ]
}

@test "work_state_eval: green command (matching stdout) but exit 0 is NOT a red (major #6)" {
  local c="$TMP/cmd.sh"; printf '#!/usr/bin/env bash\necho "not ok 1 foo_gate"\nexit 0\n' > "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --mb "$BANK"
  [ "$status" -eq 1 ]
  [ "$(_eval_field red_observed)" = "False" ]
}

@test "work_state_eval: --expected-exit 0 is rejected (a red never exits 0)" {
  local c="$TMP/cmd.sh"; _red_cmd "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'x' --expected-exit 0 --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "work_state_eval: foreign failure (output mismatch) → exit 1, red not observed" {
  local c="$TMP/cmd.sh"; printf '#!/usr/bin/env bash\necho "different error"\nexit 1\n' > "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 1 ]
  [ "$(_eval_field red_observed)" = "False" ]
}

@test "work_state_eval: expected-exit mismatch → exit 1 even if output matches" {
  local c="$TMP/cmd.sh"; printf '#!/usr/bin/env bash\necho "not ok 1 foo_gate"\nexit 4\n' > "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "work_state_eval: uncompilable ERE → exit 2" {
  local c="$TMP/cmd.sh"; _red_cmd "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re '[' --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "work_state_eval: self-modifying cmd-file is rejected by eval-red → exit 2 (major #7)" {
  local c="$TMP/cmd.sh"
  printf '#!/usr/bin/env bash\necho "not ok 1 foo_gate"\nprintf "#!/usr/bin/env bash\\nexit 0\\n" > "%s"\nexit 1\n' "$c" > "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "work_state_eval: legitimate red→green (external product flip) → eval-green exit 0" {
  local c="$TMP/cmd.sh"; _flip_cmd "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 0 ]
  touch "$IMPL"     # implementation lands; cmd-file stays byte-identical
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$(_eval_field green_exit)" = "0" ]
}

@test "work_state_eval: eval-green REFUSES after a failed eval-red (no valid red) → exit 2" {
  local c="$TMP/cmd.sh"; _green_cmd "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --mb "$BANK" || true  # fails red
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 2 ]
  [ "$(_eval_field green_exit)" = "None" ]     # green never ran
}

@test "work_state_eval: eval-green REJECTS a hand-forged eval object → exit 2 (proof invalid)" {
  local c="$TMP/cmd.sh"; _green_cmd "$c"
  python3 - "$BANK/.work-state.json" "$c" <<'PY'
import json, sys, hashlib
p, g = sys.argv[1], sys.argv[2]
d = json.load(open(p)); c = open(g).read()
# forge a "passed red" by hand — no valid helper signature.
d["eval"] = {"cmd": c, "cmd_hash": hashlib.sha256(c.encode()).hexdigest(),
             "red_exit": 1, "red_observed": True, "red_match": True,
             "green_exit": None, "sig": "forged"}
open(p, "w").write(json.dumps(d))
PY
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "work_state_eval: eval-green on a still-red command → exit 1" {
  local c="$TMP/cmd.sh"; _red_cmd "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK" || true
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "work_state_eval: eval-green detects cmd drift after a valid red → exit 1" {
  local c="$TMP/cmd.sh"; _flip_cmd "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  touch "$IMPL"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$c"   # drift the file vs the recorded snapshot
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "work_state_eval: eval-red without init → exit 2" {
  local fresh="$TMP/fresh"; mkdir -p "$fresh"
  local c="$TMP/cmd.sh"; _red_cmd "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'x' --mb "$fresh"
  [ "$status" -eq 2 ]
}

@test "work_state_eval: per-run isolation via --run-id" {
  export MB_WORK_PARALLEL=1
  local rid; rid="$(bash "$WS" new-run-id)"
  bash "$WS" init demo 2 --run-id "$rid" --mb "$BANK" >/dev/null
  local c="$TMP/cmd.sh"; _red_cmd "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --run-id "$rid" --mb "$BANK"
  [ "$status" -eq 0 ]
  [ -f "$BANK/.work-state/$rid.json" ]
}

@test "work_state_eval: regression — old subcommands still behave (init/step/cycle/status/done)" {
  local b2="$TMP/b2"; mkdir -p "$b2"
  local rid; rid="$(bash "$WS" init src 7 --mb "$b2")"
  [ -n "$rid" ]
  bash "$WS" step implemented --mb "$b2"
  run bash "$WS" status --mb "$b2"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 7'
  echo "$output" | grep -q '"steps": \["implemented"\]'
  bash "$WS" cycle --mb "$b2"
  run bash "$WS" status --mb "$b2"
  echo "$output" | grep -q '"cycle": 1'
  bash "$WS" done --mb "$b2"
  run bash "$WS" status --mb "$b2"
  echo "$output" | grep -q '"phase": "done"'
}

@test "work_state_eval: shellcheck (style) clean" {
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
  run shellcheck -S style "$WS"
  [ "$status" -eq 0 ]
}
