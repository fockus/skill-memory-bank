#!/usr/bin/env bats
# proportional-effort Sprint 2, Stage 2 — scenario: on a 3-item plan the full
# test suite runs exactly once.
#
# Replays the scriptable part of the /mb work verification path (no LLM):
#   1. mb-work-plan.sh --verify <cadence> emits per item `verify` / `final_verify`.
#   2. Per item the orchestrator (re)arms run-state with mb-work-state.sh init
#      and passes `baseline_ref` from `status` to the verifier as `Baseline ref:`
#      (commands/work.md steps 4, 5, 5c).
#   3. The verifier (agents/plan-verifier.md Step 3.5) runs
#        Final item: no  -> mb-test-run.sh --files <Item files>  (I-246: the
#                           item's Files: ∩ files changed since baseline_ref)
#        Final item: yes -> mb-test-run.sh --dir .
# A PATH shim around `bats` logs every runner invocation, so "full" is counted
# twice independently: by the JSON `selection` field and by the runner log.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  command -v jq >/dev/null || skip "jq required"
  command -v git >/dev/null || skip "git required"
  REAL_BATS="$(command -v bats)" || skip "bats required"
  # Temp HOME; keep PyYAML from the real user site-packages importable.
  PYTHONUSERBASE="$(python3 -m site --user-base)"
  export PYTHONUSERBASE
  TMPROOT="$(mktemp -d)"
  export HOME="$TMPROOT/home"
  mkdir -p "$HOME"
  REPO="$TMPROOT/repo"
  BANK="$TMPROOT/bank"
  RUNNER_LOG="$TMPROOT/runner.log"
  VERIFY_LOG="$TMPROOT/verify.log"
  : >"$RUNNER_LOG"
  : >"$VERIFY_LOG"

  # bats shim: one line per invocation with its file arguments.
  mkdir -p "$TMPROOT/bin"
  cat >"$TMPROOT/bin/bats" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$RUNNER_LOG"
exec "$REAL_BATS" "\$@"
EOF
  chmod +x "$TMPROOT/bin/bats"
  export PATH="$TMPROOT/bin:$PATH"

  make_fixture
}

teardown() {
  if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then rm -rf "$TMPROOT"; fi
}

# Fixture repo: scripts/<m>.sh -> tests/test_<m>.bats for alpha, beta, gamma.
# Fixture bank (outside the repo, so run-state never shows up in the diff):
# a 3-stage plan, each stage's **Files:** is one module + its test.
make_fixture() {
  local m n=0
  mkdir -p "$REPO/scripts" "$REPO/tests" "$BANK/plans"
  {
    printf -- '---\ntype: fix\n---\n\n# Three module plan\n\n'
  } >"$BANK/plans/three.md"
  for m in alpha beta gamma; do
    n=$((n + 1))
    printf '#!/usr/bin/env bash\necho %s\n' "$m" >"$REPO/scripts/$m.sh"
    printf '@test "%s base" { true; }\n' "$m" >"$REPO/tests/test_$m.bats"
    # shellcheck disable=SC2016  # literal markdown backticks
    printf '<!-- mb-stage:%d -->\n### Stage %d: %s\n\n**Files:** `scripts/%s.sh`, `tests/test_%s.bats`\n\n**DoD:**\n- [ ] %s done\n\n' \
      "$n" "$n" "$m" "$m" "$m" "$m" >>"$BANK/plans/three.md"
  done
  git -C "$REPO" init -q
  git -C "$REPO" -c user.email=t@t -c user.name=t add -A
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm base
}

# implement_item <module> — the implementer's edit for one stage (uncommitted:
# /mb work does not commit between items).
implement_item() {
  printf 'echo %s-changed\n' "$1" >>"$REPO/scripts/$1.sh"
  printf '@test "%s new" { true; }\n' "$1" >>"$REPO/tests/test_$1.bats"
}

# run_plan <cadence> [mb-work-plan.sh args...] — drive the orchestrator +
# verifier path for every item. Keeps the plan JSON Lines in PLAN_JSONL and
# appends one line per verifier test run to VERIFY_LOG:
#   <item_no> <targeted|full> <selected files...> | <reason>
run_plan() {
  local cadence="$1" lines line item verify final module baseline json run_id item_files
  shift
  lines="$(bash "$REPO_ROOT/scripts/mb-work-plan.sh" --target "$BANK/plans/three.md" \
    --mb "$BANK" --verify "$cadence" "$@")"
  [ "$(printf '%s\n' "$lines" | grep -c .)" -eq 3 ]
  PLAN_JSONL="$TMPROOT/plan.jsonl"
  printf '%s\n' "$lines" >"$PLAN_JSONL"
  cd "$REPO" || return 1
  while IFS= read -r line; do
    item="$(jq -r '.item_no' <<<"$line")"
    verify="$(jq -r '.verify' <<<"$line")"
    final="$(jq -r '.final_verify' <<<"$line")"
    module="$(jq -r '.heading' <<<"$line" | sed 's/.*: //')"
    bash "$REPO_ROOT/scripts/mb-work-state.sh" init plan "$item" \
      --source-path "$(jq -r '.source_path' <<<"$line")" \
      --source-topic "$(jq -r '.source_topic' <<<"$line")" --mb "$BANK" >/dev/null
    baseline="$(bash "$REPO_ROOT/scripts/mb-work-state.sh" status --mb "$BANK" | jq -r '.baseline_ref')"
    run_id="$(bash "$REPO_ROOT/scripts/mb-work-state.sh" status --mb "$BANK" | jq -r '.run_id')"
    [ -n "$baseline" ] && [ "$baseline" != "null" ]
    implement_item "$module"
    [ "$verify" = "true" ] || continue
    if [ "$final" = "true" ]; then
      json="$(bash "$REPO_ROOT/scripts/mb-test-run.sh" --dir . --out json)"
    else
      # commands/work.md 5c: Item files = the stage's Files: ∩ changed since baseline.
      item_files="$(bash "$REPO_ROOT/scripts/mb-work-diff.sh" --run-id "$run_id" --name-only --mb "$BANK" |
        grep -xE "scripts/$module\.sh|tests/test_$module\.bats" | paste -sd, -)"
      json="$(bash "$REPO_ROOT/scripts/mb-test-run.sh" --files "$item_files" --out json)"
    fi
    jq -e '.tests_pass == true' <<<"$json" >/dev/null
    jq -r --arg i "$item" '"\($i) \(.selection // "full") \((.selected // []) | join(" ")) | \(.reason // "")"' \
      <<<"$json" >>"$VERIFY_LOG"
  done <<<"$lines"
  cd "$BATS_TEST_DIRNAME" || return 1
}

count() { grep -c -- "$1" "$2" || true; }

# The full suite = one bats invocation over all three test files.
full_runner_calls() {
  grep -c 'tests/test_alpha.bats tests/test_beta.bats tests/test_gamma.bats' "$RUNNER_LOG" || true
}

@test "full-suite-once: cadence plan -> exactly 1 full run, 0 targeted, on the last item" {
  run_plan plan
  [ "$(count ' full ' "$VERIFY_LOG")" -eq 1 ]
  [ "$(count ' targeted ' "$VERIFY_LOG")" -eq 0 ]
  assert_substring "$(cat "$VERIFY_LOG")" "3 full"
  [ "$(full_runner_calls)" -eq 1 ]
  [ "$(grep -c . "$RUNNER_LOG")" -eq 1 ]
}

@test "full-suite-once: cadence stage -> 2 targeted + 1 full" {
  run_plan stage
  [ "$(count ' targeted ' "$VERIFY_LOG")" -eq 2 ]
  [ "$(count ' full ' "$VERIFY_LOG")" -eq 1 ]
  [ "$(full_runner_calls)" -eq 1 ]
  [ "$(grep -c . "$RUNNER_LOG")" -eq 3 ]
  # Each targeted run sees only its own item's tests (I-246): the baseline does
  # not move between uncommitted items, so the item's Files: ∩ changed scopes
  # it. Item 3 is the single full pass.
  assert_substring "$(sed -n 1p "$VERIFY_LOG")" "1 targeted tests/test_alpha.bats |"
  assert_substring "$(sed -n 2p "$VERIFY_LOG")" "2 targeted tests/test_beta.bats |"
  refute_substring "$(sed -n 2p "$VERIFY_LOG")" "test_alpha"
  refute_substring "$(sed -n 2p "$VERIFY_LOG")" "test_gamma"
  assert_substring "$(sed -n 3p "$VERIFY_LOG")" "3 full"
}

@test "full-suite-once: changed conftest.py makes a targeted request fall back to full with a reason (expected)" {
  local base
  base="$(git -C "$REPO" rev-parse HEAD)"
  implement_item alpha
  printf '' >"$REPO/conftest.py"
  run bash "$REPO_ROOT/scripts/mb-test-run.sh" --dir "$REPO" --changed-since "$base" --out json
  [ "$status" -eq 0 ]
  jq -e '.selection == "full" and .selected == [] and .tests_pass == true' <<<"$output" >/dev/null
  jq -e '.reason == "shared test infrastructure changed: conftest.py"' <<<"$output" >/dev/null
  [ "$(full_runner_calls)" -eq 1 ]
}

@test "full-suite-once: work.md 5c and plan-verifier Step 3.5 hand a non-final item its Files ∩ changed (I-246)" {
  assert_substring "$(cat "$REPO_ROOT/commands/work.md")" 'Item files: <'
  assert_substring "$(cat "$REPO_ROOT/agents/plan-verifier.md")" 'mb-test-run.sh" --files <Item files>'
}

# pipeline-presets-cost-tiers Stage 5 — each complexity preset at cost tier
# `optimal` on claude-code, clean path (no fix cycles). Resolution follows
# commands/work.md steps 1-3: mb-workflow.sh -> verify_cadence ->
# mb-work-plan.sh --verify=<cadence> --cost --host. Dispatches are counted the
# way 5a-5e issue them: 1 implementer per item; 1 plan-verifier per
# `verify: true` item; review = 1 reviewer (single) or every
# review_ensemble.reviewers entry + lead_role (ensemble); judge = 1.
review_dispatches() {
  "${MB_PYTHON:-python3}" - "$(bash "$REPO_ROOT/scripts/mb-pipeline.sh" path "$BANK")" "$1" <<'PY'
import sys
import yaml

cfg = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
wf = cfg["workflows"][sys.argv[2]]
print(len(cfg["review_ensemble"]["reviewers"]) + 1 if wf.get("review_profile") == "ensemble" else 1)
PY
}

# assert_preset <preset> <cadence> <dispatches/item> <verifier runs> <full-suite runs>
assert_preset() {
  local preset="$1" cadence="$2" per_item="$3" verifies="$4" full="$5"
  local wf steps items per=1 measured row
  wf="$(bash "$REPO_ROOT/scripts/mb-workflow.sh" --workflow "$preset" --host claude-code --mb "$BANK" --json)"
  [ "$(jq -r .verify_cadence <<<"$wf")" = "$cadence" ]
  steps=" $(jq -r '.steps | join(" ")' <<<"$wf") "
  run_plan "$cadence" --workflow "$preset" --cost optimal --host claude-code

  if [[ "$steps" == *" review "* ]]; then per=$((per + $(review_dispatches "$preset"))); fi
  if [[ "$steps" == *" judge "* ]]; then per=$((per + 1)); fi
  items="$(grep -c . "$PLAN_JSONL")"
  measured=$((items * per + $(jq -s '[.[] | select(.verify)] | length' "$PLAN_JSONL")))
  printf '%s dispatches=%s verify=%s full=%s\n' "$preset" "$measured" \
    "$(grep -c . "$VERIFY_LOG" || true)" "$(full_runner_calls)" >&3

  [ "$per" -eq "$per_item" ]
  [ "$measured" -eq $((3 * per_item + verifies)) ]
  [ "$(grep -c . "$VERIFY_LOG" || true)" -eq "$verifies" ]
  [ "$(full_runner_calls)" -eq "$full" ]
  [ "$(grep -c . "$RUNNER_LOG" || true)" -eq "$full" ]

  # Cheap hands, expensive eyes (references/pipeline.default.yaml cost_tiers.optimal):
  # implementer + verifier mid (sonnet), reviewer + judge premium (opus).
  jq -se 'all(.model == "sonnet" and .model_source == "profile" and .cost == "optimal"
    and .host == "claude-code"
    and .step_models == {"verifier": "sonnet", "reviewer": "opus", "judge": "opus"})' \
    "$PLAN_JSONL" >/dev/null

  # The same numbers are what commands/work.md § Cost ladder promises.
  row="$(awk -F'|' -v p="\`$preset\`" 'index($2, p) == 2 {print $3}' "$REPO_ROOT/commands/work.md")"
  assert_substring "$row" " $per_item "
  if [ "$verifies" -eq 1 ]; then
    assert_substring "$row" "+1 verifier per plan"
  else
    refute_substring "$row" "verifier"
  fi
}

@test "preset-matrix: simple + optimal -> 3 dispatches, 0 verifier, 0 full suite" {
  assert_preset simple off 1 0 0
}

@test "preset-matrix: medium + optimal -> 4 dispatches, 1 verifier, 1 full suite" {
  assert_preset medium plan 1 1 1
}

@test "preset-matrix: complex + optimal -> 7 dispatches, 1 verifier, 1 full suite" {
  assert_preset complex plan 2 1 1
}

@test "preset-matrix: governed + optimal -> 25 dispatches, 1 verifier, 1 full suite" {
  assert_preset governed plan 8 1 1
}
