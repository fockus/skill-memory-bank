#!/usr/bin/env bats
# Pipeline validator — runtime-block schema + duplicate-key rejection (I-086 Stage 1).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-pipeline-validate.sh"
  DEFAULT="$REPO_ROOT/references/pipeline.default.yaml"
  TMPDIR="${BATS_TMPDIR:-/tmp}"
  export PATH="$REPO_ROOT/.venv/bin:${PATH}"
  if ! python3 -c "import yaml" 2>/dev/null; then
    skip "PyYAML required for pipeline validate tests"
  fi
}

write_from_default() {
  local dest="$1"
  cp "$DEFAULT" "$dest"
}

patch_yaml() {
  local dest="$1" path="$2" raw="$3"
  DEFAULT="$DEFAULT" PATCH_PATH="$path" PATCH_VALUE="$raw" python3 - "$dest" <<'PY'
import os, sys, yaml
dest = sys.argv[1]
with open(os.environ["DEFAULT"], encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
path = os.environ["PATCH_PATH"]
value = yaml.safe_load(os.environ["PATCH_VALUE"])
cur = data
parts = path.split(".")
for idx, part in enumerate(parts):
    if idx == len(parts) - 1:
        cur[part] = value
    else:
        cur = cur.setdefault(part, {})
with open(dest, "w", encoding="utf-8") as fh:
    yaml.dump(data, fh, default_flow_style=False, sort_keys=False, allow_unicode=True)
PY
}

@test "validate: rejects review.severity_gate bad enum key" {
  local f="$TMPDIR/pv-bad-sg-$$.yaml"
  write_from_default "$f"
  patch_yaml "$f" "review.severity_gate" '{critical: 0, blocker: 0, major: 0, minor: 0}'
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"review.severity_gate"* ]]
}

@test "validate: rejects review.on_max_cycles bad value" {
  local f="$TMPDIR/pv-bad-omc-$$.yaml"
  write_from_default "$f"
  patch_yaml "$f" "review.on_max_cycles" 'foo'
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"review.on_max_cycles"* ]]
}

@test "validate: rejects judge.decisions scalar" {
  local f="$TMPDIR/pv-bad-jd-$$.yaml"
  write_from_default "$f"
  patch_yaml "$f" "judge.decisions" 'GO'
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"judge.decisions"* ]]
}

@test "validate: rejects done_gates.required unknown token" {
  local f="$TMPDIR/pv-bad-dg-$$.yaml"
  write_from_default "$f"
  patch_yaml "$f" "done_gates.required" '[tests_pass, bogus]'
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"done_gates.required"* ]]
}

@test "validate: rejects dispatch.priority unknown transport" {
  local f="$TMPDIR/pv-bad-dp-$$.yaml"
  write_from_default "$f"
  patch_yaml "$f" "dispatch.priority" '[pi, nope]'
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dispatch.priority"* ]]
}

@test "validate: rejects dispatch.on_none_available bad value" {
  local f="$TMPDIR/pv-bad-dona-$$.yaml"
  write_from_default "$f"
  patch_yaml "$f" "dispatch.on_none_available" 'maybe'
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dispatch.on_none_available"* ]]
}

@test "validate: rejects stage enabled non-bool" {
  local f="$TMPDIR/pv-bad-en-$$.yaml"
  write_from_default "$f"
  patch_yaml "$f" "review.enabled" 'yes-please'
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"review.enabled"* ]]
}

@test "validate: rejects duplicate top-level key" {
  local f="$TMPDIR/pv-dup-$$.yaml"
  cp "$DEFAULT" "$f"
  printf '\njudge:\n  enabled: true\n' >> "$f"
  run bash "$VALIDATE" "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate key"* ]]
}

@test "validate: accepts clean default pipeline" {
  run bash "$VALIDATE" "$DEFAULT"
  [ "$status" -eq 0 ]
}

@test "validate: runtime parser rejects duplicate keys via mb-pipeline.sh" {
  local f="$TMPDIR/pv-dup-budget-$$.yaml"
  cp "$DEFAULT" "$f"
  printf '\nbudget:\n  default_limit: 1\n' >> "$f"
  run bash "$REPO_ROOT/scripts/mb-pipeline.sh" validate "$f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate key"* ]]
}

@test "validate: project pipeline has exactly one roles.judge entry" {
  local pf="$REPO_ROOT/.memory-bank/pipeline.yaml"
  [ -f "$pf" ]
  run grep -c '^  judge:' "$pf"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}
