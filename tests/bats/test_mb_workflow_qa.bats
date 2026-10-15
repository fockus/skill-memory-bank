#!/usr/bin/env bats
# qa-pipeline-integration Stage 1 (AGR-098) — the `qa:` contract: resolver JSON,
# per-item `qa` flags by cadence, the qa-cycle budget, and byte-identity when QA is off.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/scripts/mb-workflow.sh"
  WORK_PLAN="$REPO_ROOT/scripts/mb-work-plan.sh"
  STATE="$REPO_ROOT/scripts/mb-work-state.sh"
  GOLDEN="$REPO_ROOT/tests/bats/fixtures/qa-golden"
  export PATH="$REPO_ROOT/.venv/bin:${PATH}"
  python3 -c "import yaml" 2>/dev/null || skip "PyYAML required"
  TMP="$BATS_TEST_TMPDIR"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/plans/done" "$MB/specs"
  printf '# Checklist\n' > "$MB/checklist.md"
  printf '# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n' > "$MB/roadmap.md"
  cp "$REPO_ROOT/references/pipeline.default.yaml" "$MB/pipeline.yaml"
  _plan p1
  _plan p2
}

_plan() {  # <name> → three-stage plan in the bank
  {
    printf -- '---\ntype: feature\ntopic: %s\nstatus: in-progress\n---\n\n# Plan %s\n\n' "$1" "$1"
    for n in 1 2 3; do
      printf '<!-- mb-stage:%s -->\n## Stage %s: step %s\n\n- ⬜ DoD bit\n\n' "$n" "$n" "$n"
    done
  } > "$MB/plans/$1.md"
}

_set() {  # <dotted.key> <json value> → set it in the bank pipeline.yaml
  python3 - "$MB/pipeline.yaml" "$1" "$2" <<'PY'
import json, sys, yaml
path, key, value = sys.argv[1], sys.argv[2].split("."), json.loads(sys.argv[3])
cfg = yaml.safe_load(open(path, encoding="utf-8"))
node = cfg
for k in key[:-1]:
    node = node.setdefault(k, {})
node[key[-1]] = value
yaml.safe_dump(cfg, open(path, "w", encoding="utf-8"), sort_keys=False)
PY
}

_norm() { sed "s#$(cd "$TMP" && pwd -P)#@TMP@#g; s#$TMP#@TMP@#g"; }

_qa_flags() {  # work-plan JSONL on stdin → "<plan>:<stage>=<qa>" per line
  python3 -c '
import json, sys
for o in map(json.loads, sys.stdin):
    print("%s:%s=%s" % (o["plan"], o["stage_no"], o.get("qa")))'
}

DEFAULT_QA='{"enabled": true, "cadence": "plan", "position": "before_review", "selector": "all", "prepare": "", "gate": {"critical": 0, "major": 0}, "max_cycles": 3, "on_max_cycles": "stop_for_human"}'

_qa_json() { python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("qa"), sort_keys=True))'; }
_sorted() { python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]), sort_keys=True))' "$1"; }

# ── byte-identity with QA off (goldens captured at the baseline, before the first edit) ──

@test "workflow JSON with QA off is byte-identical to the baseline golden" {
  bash "$WORKFLOW" --mb "$MB" --host claude-code --json > "$TMP/wf.json"
  cmp -s "$GOLDEN/workflow.json" "$TMP/wf.json"
}

@test "work-plan JSONL with QA off is byte-identical to the baseline golden" {
  bash "$WORK_PLAN" --mb "$MB" --host claude-code --target p1 | _norm > "$TMP/plan.jsonl"
  diff "$GOLDEN/plan.jsonl" "$TMP/plan.jsonl"
  bash "$WORK_PLAN" --mb "$MB" --host claude-code --target p1 --target p2 --verify=run | _norm > "$TMP/run.jsonl"
  diff "$GOLDEN/plan-run.jsonl" "$TMP/run.jsonl"
}

# ── resolver ──

@test "--qa adds the resolved qa block with defaults" {
  run bash "$WORKFLOW" --mb "$MB" --host claude-code --qa --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _qa_json)" = "$(_sorted "$DEFAULT_QA")" ]
}

@test "FLAG_QA=on in the environment enables QA like --qa" {
  run env FLAG_QA=on bash "$WORKFLOW" --mb "$MB" --host claude-code --json
  [ "$(printf '%s' "$output" | _qa_json)" = "$(_sorted "$DEFAULT_QA")" ]
}

@test "qa.enabled: true in the pipeline emits the same resolved block" {
  _set qa.enabled true
  run bash "$WORKFLOW" --mb "$MB" --host claude-code --json
  [ "$(printf '%s' "$output" | _qa_json)" = "$(_sorted "$DEFAULT_QA")" ]
}

@test "--qa with a pipeline that has no qa block uses the bundled defaults" {
  python3 -c 'import sys,yaml; p=sys.argv[1]; c=yaml.safe_load(open(p)); c.pop("qa",None); yaml.safe_dump(c,open(p,"w"))' "$MB/pipeline.yaml"
  run bash "$WORKFLOW" --mb "$MB" --host claude-code --qa --json
  [ "$(printf '%s' "$output" | _qa_json)" = "$(_sorted "$DEFAULT_QA")" ]
}

@test "hosts.<host>.qa overrides the qa block for that host only" {
  _set hosts.pi '{"qa": {"enabled": true, "cadence": "stage"}}'
  run bash "$WORKFLOW" --mb "$MB" --host pi --json
  printf '%s' "$output" | python3 -c 'import json,sys; q=json.load(sys.stdin)["qa"]; assert q["cadence"]=="stage" and q["max_cycles"]==3, q'
  run bash "$WORKFLOW" --mb "$MB" --host claude-code --json
  [ "$(printf '%s' "$output" | _qa_json)" = "null" ]
}

# ── per-item qa flags ──

@test "cadence stage marks every item for QA" {
  _set qa '{"enabled": true, "cadence": "stage"}'
  output=$(bash "$WORK_PLAN" --mb "$MB" --host claude-code --target p1 | _qa_flags)
  [ "$output" = "$(printf 'p1.md:1=True\np1.md:2=True\np1.md:3=True')" ]
}

@test "cadence plan marks only the last pending item" {
  python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); i=s.rindex("- ⬜"); open(p,"w").write(s[:i]+"- ✅"+s[i+len("- ⬜"):])' "$MB/plans/p1.md"
  output=$(bash "$WORK_PLAN" --mb "$MB" --host claude-code --target p1 --qa | _qa_flags)
  [ "$output" = "$(printf 'p1.md:1=False\np1.md:2=True\np1.md:3=False')" ]
}

@test "cadence run marks only the last item of the last target" {
  _set qa '{"enabled": true, "cadence": "run"}'
  output=$(bash "$WORK_PLAN" --mb "$MB" --host claude-code --target p1 --target p2 | _qa_flags)
  [ "$output" = "$(printf 'p1.md:1=False\np1.md:2=False\np1.md:3=False\np2.md:1=False\np2.md:2=False\np2.md:3=True')" ]
}

@test "QA cadence is independent from the verify cadence" {
  _set qa '{"enabled": true, "cadence": "stage"}'
  run bash "$WORK_PLAN" --mb "$MB" --host claude-code --target p1 --verify=off
  printf '%s\n' "$output" | python3 -c 'import json,sys; o=[json.loads(l) for l in sys.stdin]; assert [x["qa"] for x in o]==[True]*3 and not any(x["verify"] for x in o), o'
}

# ── qa-cycle budget ──

@test "qa-cycle counts separately from cycle and exits 3 past --max" {
  bash "$STATE" init plan 1 --mb "$MB" --source-path "$MB/plans/p1.md" --source-topic p1 --max-cycles 5 >/dev/null
  run bash "$STATE" qa-cycle --max 2 --mb "$MB"
  [ "$status" -eq 0 ]
  run bash "$STATE" qa-cycle --max 2 --mb "$MB"
  [ "$status" -eq 0 ]
  run bash "$STATE" qa-cycle --max 2 --mb "$MB"
  [ "$status" -eq 3 ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["qa_cycle"]==3 and d.get("cycle",0)==0, d' "$MB/.work-state.json"
  run bash "$STATE" cycle --mb "$MB"
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["qa_cycle"]==3 and d["cycle"]==1, d' "$MB/.work-state.json"
}
