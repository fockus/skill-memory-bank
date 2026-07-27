#!/usr/bin/env bats

# Task 5 (svp-contract-test-loop) — C3a runner: mb-contract-gate.sh red|verify.
#
# The gate exists so that "the checkers were red before the implementation"
# is decided by an exit code rather than by the implementer's own report.
# Two refusals carry that weight:
#
#   fake_red        a checker that is GREEN before the code exists proves
#                   nothing; the contract task stays open (REQ-005).
#   foreign_failure a checker that failed for a reason other than the one it
#                   declared is not evidence either — `bats <missing>` exits 1
#                   exactly like a real failure, which is why the declared
#                   output_ere must match too.
#
# And one precondition: `verify` refuses to run at all unless every checker
# has a red-evidence whose command is byte-identical to the registry's. You
# cannot verify against a command whose red nobody ever observed.
#
# Every "it did not run" assertion is backed by a MARKER the checker writes
# when it starts — absence of a marker is observed, never assumed. Markers and
# banks live in a private mktemp dir: counting entries in a shared TMPDIR
# fails for unrelated reasons and passes while a real leak hides (I-155).

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GATE="$REPO_ROOT/scripts/mb-contract-gate.sh"
  WORK="$(mktemp -d)"
  REPO="$WORK/repo"
  BANK="$REPO/.memory-bank"
  SPEC="$BANK/specs/demo"
  MARKERS="$WORK/markers"
  mkdir -p "$SPEC" "$REPO/tests/checkers" "$MARKERS"
}

teardown() {
  [ -n "${WORK:-}" ] && [ -d "$WORK" ] && rm -rf "$WORK"
}

# ── fixture builders ─────────────────────────────────────────────────────────

# checker <name> <mode> — mode: fail | pass | foreign | slow
#   fail    exits 1 printing the signature its registry entry declares
#   pass    exits 0 (the shape that must be refused as fake_red before the
#           implementation exists, and required after it)
#   foreign exits 3 printing something else entirely
#   slow    records that it started, then blocks
checker() {
  # Separate declarations on purpose: in `local a="$1" b="$a"`, bash does NOT
  # make `a` visible to `b` — it resolved to the empty string here, every
  # checker was written to `.sh`, and every run exited 127. One test went GREEN
  # on that, because "exit 127 and no ERE match" is indistinguishable from the
  # foreign_failure it claimed to prove.
  local name="$1"
  local mode="$2"
  local path="$REPO/tests/checkers/$name.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'touch "%s/%s.ran"\n' "$MARKERS" "$name"
    case "$mode" in
      fail)    printf 'printf "%%s\\n" "%s: FAIL"\nexit 1\n' "$name" ;;
      pass)    printf 'printf "%%s\\n" "%s: OK"\nexit 0\n' "$name" ;;
      foreign) printf 'printf "%%s\\n" "unrelated crash"\nexit 3\n' ;;
      slow)    printf 'sleep 30\n' ;;
    esac
  } >"$path"
  chmod +x "$path"
}

ran() { [ -f "$MARKERS/$1.ran" ]; }

# registry <json-body> — write tasks.md with ONE contract task carrying it.
# An empty body writes the contract task with no registry block at all.
registry() {
  {
    printf '# Tasks: demo\n\n<!-- mb-task:1 -->\n## Task 1: contract checkers\n\n'
    printf '**Layer:** contract\n**Covers:** REQ-001\n**Role:** backend\n\n'
    printf '**What to do:**\n- declare and build the checkers.\n'
    if [ -n "$1" ]; then
      printf '\n```json Contract-checkers\n%s\n```\n' "$1"
    fi
    printf '\n**Testing (TDD — tests BEFORE implementation):**\n- checker unit tests.\n\n'
    printf '**DoD:**\n- [ ] checkers red against the product.\n<!-- /mb-task:1 -->\n'
  } >"$SPEC/tasks.md"
}

# one_checker <id> — the canonical single-entry registry for that checker.
one_checker() {
  printf '{"checkers": [
  {"id": "%s",
   "covers": ["REQ-001"],
   "path": "tests/checkers/%s.sh",
   "argv": ["bash", "tests/checkers/%s.sh"],
   "evidence": "tmp/contract-gate/demo/%s.{phase}.json",
   "output_ere": "%s: FAIL"}
]}' "$1" "$1" "$1" "$1" "$1"
}

evidence_path() { printf '%s/tmp/contract-gate/demo/%s.%s.json' "$BANK" "$1" "$2"; }

# evidence_keys <file> — the object's key set, sorted, one line. Compared as a
# whole so an EXTRA key fails just as loudly as a missing one.
evidence_keys() {
  python3 -c "
import json, sys
print(','.join(sorted(json.load(open(sys.argv[1])))))
" "$1"
}

KEYS_CPR_A='checker_id,cmd,cmd_sha256,exit,output_match,phase,topic,verdict,version'

# green_red <id> — drive a checker through a legitimate red run, leaving the
# evidence `verify` insists on. Used by the verify-phase fixtures.
green_red() {
  checker "$1" fail
  registry "$(one_checker "$1")"
  bash "$GATE" red --spec "$SPEC" --mb "$BANK" >/dev/null 2>&1
}

# ── red phase ────────────────────────────────────────────────────────────────

@test "contract_gate_fake_red_fails: a checker green before the implementation is not evidence" {
  checker persist_gate pass
  registry "$(one_checker persist_gate)"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "fake_red"
  ran persist_gate || { echo "the checker was never executed"; false; }
}

@test "contract_gate_foreign_failure_rejected: failed, but not for the declared reason" {
  checker persist_gate foreign
  registry "$(one_checker persist_gate)"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "foreign_failure"
}

@test "contract_gate_red_all_matched_passes: every checker red for the reason it declared" {
  checker persist_gate fail
  registry "$(one_checker persist_gate)"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" '"verdict":"pass"'
}

@test "contract_gate_red_one_bad_checker_fails_the_run: a single fake_red sinks the verdict" {
  checker good_gate fail
  checker lazy_gate pass
  registry "$(printf '{"checkers": [
  {"id": "good_gate", "covers": ["REQ-001"], "path": "tests/checkers/good_gate.sh",
   "argv": ["bash", "tests/checkers/good_gate.sh"],
   "evidence": "tmp/contract-gate/demo/good_gate.{phase}.json",
   "output_ere": "good_gate: FAIL"},
  {"id": "lazy_gate", "covers": ["REQ-001"], "path": "tests/checkers/lazy_gate.sh",
   "argv": ["bash", "tests/checkers/lazy_gate.sh"],
   "evidence": "tmp/contract-gate/demo/lazy_gate.{phase}.json",
   "output_ere": "lazy_gate: FAIL"}
]}')"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "fake_red"
}

# ── evidence ─────────────────────────────────────────────────────────────────

@test "contract_gate_evidence_exact_schema: evidence carries exactly the nine CPR-A fields" {
  checker persist_gate fail
  registry "$(one_checker persist_gate)"
  bash "$GATE" red --spec "$SPEC" --mb "$BANK" >/dev/null 2>&1
  ev="$(evidence_path persist_gate red)"
  [ -f "$ev" ] || { echo "no evidence at $ev"; false; }
  run python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
want = {'version','topic','checker_id','phase','cmd','cmd_sha256','exit','output_match','verdict'}
print('extra=%s missing=%s' % (sorted(set(d) - want), sorted(want - set(d))))
print('cmd=%s' % d['cmd'])
print('sha_len=%d' % len(d['cmd_sha256']))
print('types_ok=%s' % (isinstance(d['exit'], int) and isinstance(d['output_match'], bool)))
" "$ev"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" "extra=[] missing=[]"
  assert_substring "$output" 'cmd=["bash","tests/checkers/persist_gate.sh"]'
  assert_substring "$output" "sha_len=64"
  assert_substring "$output" "types_ok=True"
}

@test "contract_gate_evidence_cmd_sha256_matches_cmd: the digest is of the canonical argv" {
  checker persist_gate fail
  registry "$(one_checker persist_gate)"
  bash "$GATE" red --spec "$SPEC" --mb "$BANK" >/dev/null 2>&1
  run python3 -c "
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
print('match=%s' % (hashlib.sha256(d['cmd'].encode()).hexdigest() == d['cmd_sha256']))
" "$(evidence_path persist_gate red)"
  assert_substring "$output" "match=True"
}

@test "contract_gate_evidence_atomic_no_partial: nothing is published before the checker returns" {
  # A torn write cannot be forced deterministically, so what is proven here is
  # the pair of properties that make temp+mv worth having: (1) the declared
  # path holds nothing while the checker is still running, and (2) a completed
  # run publishes a COMPLETE object and leaves no debris beside it.
  checker persist_gate slow
  registry "$(one_checker persist_gate)"
  bash "$GATE" red --spec "$SPEC" --mb "$BANK" >/dev/null 2>&1 &
  gate_pid=$!
  for _ in $(seq 1 100); do ran persist_gate && break; sleep 0.1; done
  ran persist_gate || { echo "checker never started"; kill "$gate_pid" 2>/dev/null; false; }
  kill "$gate_pid" 2>/dev/null
  wait "$gate_pid" 2>/dev/null || true
  refute_file "$(evidence_path persist_gate red)"

  # positive control: the same fixture, allowed to finish, does publish
  rm -f "$MARKERS/persist_gate.ran"
  checker persist_gate fail
  bash "$GATE" red --spec "$SPEC" --mb "$BANK" >/dev/null 2>&1
  ev="$(evidence_path persist_gate red)"
  [ "$(evidence_keys "$ev")" = "$KEYS_CPR_A" ] || { echo "incomplete: $(evidence_keys "$ev")"; false; }
  leftovers="$(find "$BANK/tmp/contract-gate/demo" -type f ! -name '*.red.json' ! -name '*.verify.json' | wc -l | tr -d ' ')"
  [ "$leftovers" -eq 0 ] || { echo "temp debris left: $(find "$BANK/tmp/contract-gate/demo" -type f)"; false; }
}

# ── registry schema — refused BEFORE anything is executed ────────────────────

@test "contract_gate_missing_registry_exits_2: no registry block at all" {
  checker persist_gate fail
  registry ""
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_invalid_schema_exits_2: an unknown key stops the run before it starts" {
  checker persist_gate fail
  registry "$(one_checker persist_gate | sed 's/"path":/"pathx": "x", "path":/')"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  assert_substring "$output" "pathx"
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_evidence_outside_topic_exits_2: evidence must stay under the topic dir" {
  checker persist_gate fail
  registry "$(one_checker persist_gate | sed 's#tmp/contract-gate/demo/#tmp/elsewhere/#')"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_evidence_dotdot_exits_2: a traversal is refused before execution" {
  checker persist_gate fail
  registry "$(one_checker persist_gate | sed 's#demo/persist_gate#demo/../persist_gate#')"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_evidence_symlink_escape_exits_2: a symlinked topic dir cannot smuggle the path out" {
  # `..` and a leading `/` are string-level checks; a symlink defeats both and
  # only shows up once the path is resolved against the real bank.
  checker persist_gate fail
  registry "$(one_checker persist_gate)"
  mkdir -p "$BANK/tmp/contract-gate" "$WORK/outside"
  ln -s "$WORK/outside" "$BANK/tmp/contract-gate/demo"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_bad_ere_exits_2: an output_ere grep -E refuses" {
  checker persist_gate fail
  registry "$(one_checker persist_gate | sed 's/persist_gate: FAIL/persist_gate: [FAIL/')"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_empty_argv_exits_2: argv must be a non-empty array of strings" {
  checker persist_gate fail
  registry "$(one_checker persist_gate | sed 's#\["bash", "tests/checkers/persist_gate.sh"\]#[]#')"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  assert_substring "$output" "argv"
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_argv_runs_shell_false: registry text is an argument, never shell syntax" {
  # `argv` is executed shell=false. A metacharacter in an argument must reach
  # the process as data; if it were handed to a shell it would redirect.
  # The witness file lives in the PRIVATE work dir, never in /tmp: an assertion
  # about a shared path fails because of someone else and passes when a real
  # escape is masked by a leftover (I-155).
  checker persist_gate fail
  registry "$(one_checker persist_gate | sed "s#\\[\"bash\", \"tests/checkers/persist_gate.sh\"\\]#[\"bash\", \"tests/checkers/persist_gate.sh\", \"; touch $WORK/pwned\"]#")"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  refute_file "$WORK/pwned"
}

@test "contract_gate_no_contract_task_exits_2: a spec with no contract task" {
  checker persist_gate fail
  printf '# Tasks: demo\n\n<!-- mb-task:1 -->\n## Task 1: build it\n\n**Covers:** REQ-001\n**Role:** backend\n\n**Testing:**\n- x\n\n**DoD:**\n- [ ] x\n<!-- /mb-task:1 -->\n' >"$SPEC/tasks.md"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_two_contract_tasks_exit_2: the registry must have one owner" {
  checker persist_gate fail
  registry "$(one_checker persist_gate)"
  sed 's/mb-task:1/mb-task:2/g' "$SPEC/tasks.md" >>"$SPEC/tasks.md.2"
  cat "$SPEC/tasks.md.2" >>"$SPEC/tasks.md"
  rm -f "$SPEC/tasks.md.2"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_usage_errors_exit_2: an unknown phase is a usage error" {
  registry "$(one_checker persist_gate)"
  run bash "$GATE" sideways --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
}

# ── verify phase — red-evidence precondition (CPR-A) ─────────────────────────

@test "contract_gate_verify_missing_red_evidence_exits_2: no red was ever observed" {
  checker persist_gate pass
  registry "$(one_checker persist_gate)"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_verify_malformed_evidence_exits_2: an unreadable red-evidence is not evidence" {
  green_red persist_gate
  printf 'not json at all' >"$(evidence_path persist_gate red)"
  rm -f "$MARKERS/persist_gate.ran"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_verify_cmd_drift_exits_2: the registry changed after the red run" {
  green_red persist_gate
  # same checker id, different command — the observed red belongs to the old one
  registry "$(one_checker persist_gate | sed 's#\["bash", "tests/checkers/persist_gate.sh"\]#["bash", "-c", "bash tests/checkers/persist_gate.sh"]#')"
  rm -f "$MARKERS/persist_gate.ran"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_verify_non_pass_red_evidence_exits_2: a fake_red run does not unlock verify" {
  checker persist_gate pass
  registry "$(one_checker persist_gate)"
  # exits 1 by design — the point is that it still FILES evidence, and that the
  # filed fake_red must not be mistaken for an observed red.
  bash "$GATE" red --spec "$SPEC" --mb "$BANK" >/dev/null 2>&1 || true
  # Asserted explicitly: a failed run still records what happened. Without
  # this, "verify refused" is equally consistent with "evidence was never
  # written at all", and the test could not tell the two apart.
  run python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['verdict'])" \
    "$(evidence_path persist_gate red)"
  assert_substring "$output" "fake_red"
  rm -f "$MARKERS/persist_gate.ran"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_verify_incomplete_evidence_exits_2: valid JSON is not a valid evidence" {
  # Distinct from the malformed case: this parses fine and only fails the
  # CLOSED schema, which is the branch a `json.loads` guard alone never reaches.
  green_red persist_gate
  ev="$(evidence_path persist_gate red)"
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
del d['version']
json.dump(d, open(sys.argv[1], 'w'))
" "$ev"
  rm -f "$MARKERS/persist_gate.ran"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_verify_evidence_of_another_checker_exits_2: identity is checked, not just shape" {
  green_red persist_gate
  ev="$(evidence_path persist_gate red)"
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
d['checker_id'] = 'someone_else'
json.dump(d, open(sys.argv[1], 'w'))
" "$ev"
  rm -f "$MARKERS/persist_gate.ran"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_verify_all_green_passes: the implementation landed and every checker returns 0" {
  green_red persist_gate
  checker persist_gate pass          # the implementation now exists
  rm -f "$MARKERS/persist_gate.ran"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ran persist_gate || { echo "verify never executed the checker"; false; }
}

@test "contract_gate_verify_red_checker_fails: a checker still red at verify fails verification" {
  green_red persist_gate             # checker stays `fail`
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "red_checker"
}

@test "contract_gate_verify_writes_separate_evidence: the red run is not overwritten" {
  green_red persist_gate
  snapshot "$(evidence_path persist_gate red)" "$WORK/red.before"
  checker persist_gate pass
  bash "$GATE" verify --spec "$SPEC" --mb "$BANK" >/dev/null 2>&1
  assert_unchanged "$(evidence_path persist_gate red)" "$WORK/red.before"
  run python3 -c "
import json, sys
print('phase=%s' % json.load(open(sys.argv[1]))['phase'])
" "$(evidence_path persist_gate verify)"
  assert_substring "$output" "phase=verify"
}

# ── output channels ──────────────────────────────────────────────────────────

@test "contract_gate_json_flag_keeps_stderr_empty: the machine channel stays clean" {
  # A FAILING run on purpose: on a clean run there is no diagnostic to suppress,
  # so empty stderr would hold with the suppression deleted.
  checker persist_gate pass
  registry "$(one_checker persist_gate)"
  bash "$GATE" red --spec "$SPEC" --mb "$BANK" --json >"$WORK/out.json" 2>"$WORK/err.txt" || true
  [ ! -s "$WORK/err.txt" ] || { echo "stderr leaked:"; cat "$WORK/err.txt"; false; }
  run python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print('phase=%s verdict=%s n=%d' % (d['phase'], d['verdict'], len(d['checkers'])))
" "$WORK/out.json"
  assert_substring "$output" "phase=red verdict=fake_red n=1"
}

@test "contract_gate_diagnostics_on_stderr_by_default: a human run explains the refusal" {
  checker persist_gate pass
  registry "$(one_checker persist_gate)"
  bash "$GATE" red --spec "$SPEC" --mb "$BANK" >"$WORK/out.json" 2>"$WORK/err.txt" || true
  assert_grep -q 'fake_red' "$WORK/err.txt"
  run python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['verdict'])" "$WORK/out.json"
  assert_substring "$output" "fake_red"
}

# ── the canonical stage order is untouched ───────────────────────────────────

@test "contract_gate_stage_order_unchanged: pipeline validation still passes" {
  # The spec's testing note says `bash scripts/mb-pipeline-validate.sh`, but a
  # bare invocation is a USAGE error (exit 2) — it takes the config path. A
  # check that can only ever exit 2 proves nothing, so the real configs are
  # validated instead: this task must leave the canonical stage order alone.
  run bash "$REPO_ROOT/scripts/mb-pipeline-validate.sh" "$REPO_ROOT/references/pipeline.default.yaml"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash "$REPO_ROOT/scripts/mb-pipeline-validate.sh" "$REPO_ROOT/.memory-bank/pipeline.yaml"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "contract_gate_verify_self_inconsistent_evidence_exits_2: pass with exit 0 is impossible" {
  # `run_checker` can only produce verdict=pass for a RED phase when the
  # checker exited non-zero AND matched its ERE. A record claiming
  # verdict=pass alongside exit=0/output_match=false was never produced by
  # this runner, so accepting it means the closed schema's own fields are
  # decorative — they exist to make the record self-checking and nothing read
  # them.
  green_red persist_gate
  ev="$(evidence_path persist_gate red)"
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
d['exit'] = 0
d['output_match'] = False
json.dump(d, open(sys.argv[1], 'w'))
" "$ev"
  rm -f "$MARKERS/persist_gate.ran"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_verify_evidence_verdict_must_match_its_fields: red_checker cannot be a red" {
  green_red persist_gate
  ev="$(evidence_path persist_gate red)"
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
d['output_match'] = False          # failed, but not for the declared reason
json.dump(d, open(sys.argv[1], 'w'))
" "$ev"
  rm -f "$MARKERS/persist_gate.ran"
  run bash "$GATE" verify --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_registry_path_must_match_argv: a field nothing reads is a field nothing means" {
  # `path` was validated only as a non-empty string: never compared with the
  # argv that actually runs, never checked against the disk, read by no
  # consumer. It could name any file in the world and the gate would agree.
  checker persist_gate fail
  registry "$(one_checker persist_gate | sed 's#"path": "tests/checkers/persist_gate.sh"#"path": "tests/checkers/does_not_exist.sh"#')"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  assert_substring "$output" "path"
  refute_file "$MARKERS/persist_gate.ran"
}

@test "contract_gate_registry_path_missing_on_disk_exits_2: it must actually be there" {
  checker persist_gate fail
  rm -f "$REPO/tests/checkers/persist_gate.sh"
  registry "$(one_checker persist_gate)"
  run bash "$GATE" red --spec "$SPEC" --mb "$BANK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  assert_substring "$output" "path"
}
