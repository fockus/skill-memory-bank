#!/usr/bin/env bats
# planning_qa: — planning-qa-sources Task 1. QA declaration at plan time (tier rule,
# opt-outs, qa.enabled auto|true|false), the --spec wrapper, the authoring prompts.
# Name convention: every @test starts with `planning_qa: ` (Eval red anchor).

load 'lib/assert'
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-plan.sh"
  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/plans" "$MB/qa"
  printf '# QA target\n' > "$MB/qa/README.md"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -q -m init)
  cd "$PROJECT"
  PLAN_MD="$REPO_ROOT/commands/plan.md"
  SDD_MD="$REPO_ROOT/commands/sdd.md"
  TIERS_MD="$REPO_ROOT/references/effort-tiers.md"
  QA_MD="$REPO_ROOT/agents/mb-qa.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("plan-dispatch|mb_section|3\\.5\\. QA test cases|dispatch .mb-qa. exactly once.*authoring mode|mb-qa|s/exactly once/at will/|REQ-005")
  MB_DISCUSS_CLAUSES+=("plan-skip|mb_section|3\\.5\\. QA test cases|only when the plan says .qa: on.|qa: on|s/only when/also when/|REQ-003")
  MB_DISCUSS_CLAUSES+=("plan-flags|mb_section|2\\. Scaffold the plan file|pass .--tier <tier>. and .--no-qa. when the user asks to skip QA|--tier|s/ and .--no-qa. when the user asks to skip QA//|REQ-003")
  MB_DISCUSS_CLAUSES+=("sdd-wrapper|mb_section|Plan wrapper [(]after Step 10[)]|create it without asking under .--auto. or when QA would be on|plan wrapper|s/without asking/after asking/|REQ-011")
  MB_DISCUSS_CLAUSES+=("tiers-standard|mb_section|standard|[*][*]QA:[*][*] on under .auto.|QA:|s/ on under / off under /|REQ-001")
  MB_DISCUSS_CLAUSES+=("tiers-small|mb_section|small|[*][*]QA:[*][*] off under .auto.|QA:|s/ off under / on under /|REQ-002")
  MB_DISCUSS_CLAUSES+=("tiers-decl|mb_section|QA declaration|absent .qa/README.md. declares .off — no QA target.|qa/README.md|s/declares/ignores/|REQ-004")
  MB_DISCUSS_CLAUSES+=("qa-outdir|mb_section|Test-case authoring mode|writes only under .qa/test_cases/<topic>/.|qa/test_cases|s/writes only under/may write outside/|REQ-005")
  MB_DISCUSS_CLAUSES+=("qa-fields|mb_section|Test-case authoring mode|frontmatter .id., .tags., .covers., .origin., .proof.|frontmatter|s/ .origin.,//|REQ-007")
  MB_DISCUSS_CLAUSES+=("qa-needs-spec|mb_section|Test-case authoring mode|marks .status: needs_spec. instead of inventing|needs_spec|s/instead of inventing/and invents/|REQ-008")
  MB_DISCUSS_CLAUSES+=("qa-count|mb_section|Test-case authoring mode|standard one case per key user path.*large or extra one per externally testable REQ|per key user path|s/large or extra/large/|REQ-006")
}

teardown() { [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"; }

_decl() { grep -m1 '^qa: ' "$1"; }
_has_qa_item() { grep -qF '/mb qa run @checkout' "$1"; }
_set_qa() { printf 'qa:\n  enabled: %s\n  cadence: plan\n' "$1" > "$MB/pipeline.yaml"; }

@test "planning_qa: standard tier with a QA target declares on and adds the QA DoD item last" {
  run bash "$SCRIPT" feature checkout --tier standard "$MB"
  [ "$status" -eq 0 ]
  [ "$(_decl "$output")" = "qa: on" ]
  _has_qa_item "$output"
  grep -A1 '^- \[ \] lint clean$' "$output" | tail -1 | grep -q 'qa.gate'
}

@test "planning_qa: small tier declares off small tier without the QA item" {
  run bash "$SCRIPT" feature checkout --tier small "$MB"
  [ "$status" -eq 0 ]
  [ "$(_decl "$output")" = "qa: off — small tier" ]
  ! _has_qa_item "$output"
}

@test "planning_qa: small tier with --qa declares on" {
  run bash "$SCRIPT" feature checkout --tier small --qa "$MB"
  [ "$(_decl "$output")" = "qa: on" ]
  _has_qa_item "$output"
}

@test "planning_qa: --no-qa and both flags declare off disabled" {
  run bash "$SCRIPT" feature checkout --tier large --no-qa "$MB"
  [ "$(_decl "$output")" = "qa: off — disabled" ]
  refute_cmd _has_qa_item "$output"
  run bash "$SCRIPT" feature checkout --tier large --qa --no-qa "$MB"
  [ "$(_decl "$output")" = "qa: off — disabled" ]
}

@test "planning_qa: project qa.enabled false declares off disabled even with --qa" {
  _set_qa false
  run bash "$SCRIPT" feature checkout --tier standard --qa "$MB"
  [ "$(_decl "$output")" = "qa: off — disabled" ]
  ! _has_qa_item "$output"
}

@test "planning_qa: qa.enabled true turns small tier on and --no-qa still wins" {
  _set_qa true
  run bash "$SCRIPT" feature checkout --tier small "$MB"
  [ "$(_decl "$output")" = "qa: on" ]
  run bash "$SCRIPT" feature checkout --tier small --no-qa "$MB"
  [ "$(_decl "$output")" = "qa: off — disabled" ]
}

@test "planning_qa: qa.enabled auto in the project file follows the tier rule" {
  _set_qa auto
  run bash "$SCRIPT" feature checkout --tier small "$MB"
  [ "$(_decl "$output")" = "qa: off — small tier" ]
}

@test "planning_qa: missing qa README declares off no QA target and exits 0" {
  rm "$MB/qa/README.md"
  run bash "$SCRIPT" feature checkout --tier large "$MB"
  [ "$status" -eq 0 ]
  [ "$(_decl "$output")" = "qa: off — no QA target" ]
  ! _has_qa_item "$output"
}

@test "planning_qa: unknown tier exits 1" {
  run bash "$SCRIPT" feature checkout --tier huge "$MB"
  [ "$status" -eq 1 ]
}

@test "planning_qa: without --tier the scaffold has no qa line and no QA item" {
  run bash "$SCRIPT" feature checkout "$MB"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2,8p "$output" | tr '\n' '|')" = "type: feature|topic: checkout|status: in_progress|depends_on: []|parallel_safe: false|linked_specs: []|created: $(date +%Y-%m-%d)|" ]
  ! grep -qi 'qa' "$output"
}

_spec() {
  mkdir -p "$MB/specs/$1"
  { printf '# Tasks\n\n'
    for n in 1 2 3; do
      printf '<!-- mb-task:%s -->\n## Task %s: t%s\n\n**Covers:** REQ-001\n**Role:** developer\n**Blocked-by:** none\n**Scope:** x\n**Budget:** 1000\n\n**DoD:**\n- [ ] ok\n<!-- /mb-task:%s -->\n\n' "$n" "$n" "$n" "$n"
    done; } > "$MB/specs/$1/tasks.md"
}

@test "planning_qa: --spec refuses a topic without tasks.md" {
  run bash "$SCRIPT" feature demo --spec demo --tier large "$MB"
  [ "$status" -eq 1 ]
}

@test "planning_qa: --spec wrapper links the spec, declares qa and flows through work-plan and plan-sync" {
  _spec demo
  plan="$(bash "$SCRIPT" feature demo --spec demo --tier large "$MB")"
  grep -qx 'linked_spec: specs/demo' "$plan"
  [ "$(_decl "$plan")" = "qa: on" ]
  grep -q '^### Stage 1: Execute specs/demo$' "$plan"
  grep -q 'specs/demo/tasks.md. is the source of truth' "$plan"
  printf '# Checklist\n' > "$MB/checklist.md"
  printf '# Roadmap\n' > "$MB/roadmap.md"
  run bash "$REPO_ROOT/scripts/mb-plan-sync.sh" "$plan" "$MB"
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/scripts/mb-work-plan.sh" --target "$plan" --mb "$MB" --dry-run
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '"kind": "task"')" -eq 3 ]
}

# ── prompt clauses ──
_pair() {
  run assert_clause "$1" "$2"; [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$1" "$2"; [ "$status" -eq 0 ]
}

@test "planning_qa: plan.md dispatches mb-qa once on qa on and may use Task" {
  _pair "$PLAN_MD" plan-dispatch
  _pair "$PLAN_MD" plan-skip
  _pair "$PLAN_MD" plan-flags
  run assert_tool_allowed "$PLAN_MD" Task; [ "$status" -eq 0 ]
}

@test "planning_qa: sdd.md offers and creates the plan wrapper" {
  _pair "$SDD_MD" sdd-wrapper
  [ "$(wc -l < "$SDD_MD")" -le 400 ]
}

@test "planning_qa: effort-tiers carries a QA line per tier and the declaration paragraph" {
  [ "$(grep -c '^- [*][*]QA:[*][*]' "$TIERS_MD")" -eq 5 ]
  _pair "$TIERS_MD" tiers-standard
  _pair "$TIERS_MD" tiers-small
  _pair "$TIERS_MD" tiers-decl
}

@test "planning_qa: mb-qa authoring mode names the output dir, fields, needs_spec and count rule" {
  _pair "$QA_MD" qa-outdir
  _pair "$QA_MD" qa-fields
  _pair "$QA_MD" qa-needs-spec
  _pair "$QA_MD" qa-count
}

# ── pipeline: qa.enabled auto | true | false ──
_pipe() {  # <qa.enabled> <hosts.claude-code.qa.enabled|-> → file path
  local f="$BATS_TEST_TMPDIR/p-$1-$2.yaml"
  sed -E "/^qa:/,/^[a-z_]+:/ s/^  enabled: [^ ]+/  enabled: $1/" "$REPO_ROOT/references/pipeline.default.yaml" > "$f"
  [ "$2" = "-" ] || printf '\nhosts:\n  claude-code:\n    qa:\n      enabled: %s\n' "$2" >> "$f"
  printf '%s' "$f"
}

_validate() { bash "$REPO_ROOT/scripts/mb-pipeline-validate.sh" "$1"; }

@test "planning_qa: bundled default ships qa.enabled auto and validates" {
  grep -Eq '^  enabled: auto( |$)' "$REPO_ROOT/references/pipeline.default.yaml"
  run _validate "$(_pipe auto -)"
  [ "$status" -eq 0 ]
}

@test "planning_qa: validator accepts auto true false and rejects maybe, with and without PyYAML" {
  local shim="$BATS_TEST_TMPDIR/shim"; mkdir -p "$shim"
  printf "raise ModuleNotFoundError('yaml')\n" > "$shim/yaml.py"
  local v
  for v in auto true false; do
    run _validate "$(_pipe $v -)"; [ "$status" -eq 0 ]
    run _validate "$(_pipe auto $v)"; [ "$status" -eq 0 ]
    PYTHONPATH="$shim" run _validate "$(_pipe $v -)"; [ "$status" -eq 0 ]
    PYTHONPATH="$shim" run _validate "$(_pipe auto $v)"; [ "$status" -eq 0 ]
  done
  run _validate "$(_pipe maybe -)"; [ "$status" -eq 1 ]
  run _validate "$(_pipe auto maybe)"; [ "$status" -eq 1 ]
  PYTHONPATH="$shim" run _validate "$(_pipe maybe -)"; [ "$status" -eq 1 ]
}

@test "planning_qa: workflow JSON with the bundled auto default equals the QA-off golden" {
  python3 -c "import yaml" 2>/dev/null || skip "PyYAML required"
  mkdir -p "$MB/specs"
  cp "$REPO_ROOT/references/pipeline.default.yaml" "$MB/pipeline.yaml"
  run bash "$REPO_ROOT/scripts/mb-workflow.sh" --mb "$MB" --host claude-code --json
  [ "$status" -eq 0 ]
  [[ "$output" != *'"qa"'* ]]
  bash "$REPO_ROOT/scripts/mb-workflow.sh" --mb "$MB" --host claude-code --json > "$BATS_TEST_TMPDIR/wf.json"
  cmp -s "$REPO_ROOT/tests/bats/fixtures/qa-golden/workflow.json" "$BATS_TEST_TMPDIR/wf.json"
}

@test "planning_qa: --tier without a value is a loud usage error (I-286)" {
  run bash "$SCRIPT" feature checkout --tier
  [ "$status" -eq 1 ]
  [[ "$output" == *"--tier requires"* ]]
}
