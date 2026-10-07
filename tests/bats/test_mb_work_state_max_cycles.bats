#!/usr/bin/env bats
# resolve_max_cycles reads workflows.governed (pipeline-presets-cost-tiers
# Stage 2 rename), falling back to the legacy governed-execution block, then 2.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PATH="$REPO_ROOT/.venv/bin:${PATH}"
  python3 -c "import yaml" 2>/dev/null || skip "PyYAML required"
  MB="$BATS_TEST_TMPDIR/.memory-bank"
  mkdir -p "$MB"
  SCRIPT_DIR="$REPO_ROOT/scripts"
  # shellcheck source=../../scripts/mb-work-state-lib.sh
  source "$SCRIPT_DIR/mb-work-state-lib.sh"
}

_pipeline() {  # <workflow-name> <max_cycles> ...
  printf 'version: 1\nworkflows:\n' > "$MB/pipeline.yaml"
  while [ "$#" -gt 1 ]; do
    printf '  %s:\n    steps: [implement, verify, review, judge, fix, done]\n    loop: {max_cycles: %s}\n' "$1" "$2" >> "$MB/pipeline.yaml"
    shift 2
  done
}

@test "max_cycles comes from workflows.governed" {
  _pipeline governed 5
  run resolve_max_cycles "$MB"
  [ "$output" = "5" ]
}

@test "governed wins over a legacy governed-execution block" {
  _pipeline governed 4 governed-execution 7
  run resolve_max_cycles "$MB"
  [ "$output" = "4" ]
}

@test "legacy governed-execution still feeds max_cycles" {
  _pipeline governed-execution 6
  run resolve_max_cycles "$MB"
  [ "$output" = "6" ]
}

@test "no governed block falls back to 2" {
  _pipeline medium 9
  run resolve_max_cycles "$MB"
  [ "$output" = "2" ]
}
