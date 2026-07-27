#!/usr/bin/env bats
# pipeline_sdd_layers_* — svp-contract-test-loop C1, the `sdd.layers` defaults in
# pipeline config and their validation (Task 2).
#
# THE INLINE MAP IS A REQUIREMENT, NOT A STYLE. `mb-pipeline-validate.sh` reads
# `sdd` through `parse_simple_mapping`, which only takes `indent == 2` lines, so
# a NESTED block yields `layers: None` in the PyYAML-optional fallback while
# PyYAML yields a full dict. The two branches would then disagree about whether
# the layers are configured at all — and a validator that silently sees no
# layers is the "ran against nothing and reported success" shape. The inline
# form parses identically in both branches, which is what these tests pin.

bats_require_minimum_version 1.5.0
load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-pipeline-validate.sh"
  DEFAULT="$REPO_ROOT/references/pipeline.default.yaml"
  WORK="$BATS_TEST_TMPDIR/pipeline.yaml"
}

# parse_layers <file> <branch:pyyaml|fallback> — what that branch sees at sdd.layers.
parse_layers() {
  if [ "$2" = "fallback" ]; then
    python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/scripts')
from mb_pipeline_minimal_yaml import minimal_pipeline_load
cfg = minimal_pipeline_load(open('$1').read())
print(repr((cfg.get('sdd') or {}).get('layers')))"
  else
    python3 -c "
import yaml
cfg = yaml.safe_load(open('$1'))
print(repr((cfg.get('sdd') or {}).get('layers')))"
  fi
}

@test "pipeline_sdd_layers_inline_map_parses_in_both_paths" {
  # The shipped default must be readable identically with and without PyYAML.
  local with_yaml without_yaml
  with_yaml="$(parse_layers "$DEFAULT" pyyaml)"
  without_yaml="$(parse_layers "$DEFAULT" fallback)"
  [ "$with_yaml" = "$without_yaml" ]
  assert_substring "$with_yaml" "contract_first"
  assert_substring "$with_yaml" "integration_tests"
  assert_substring "$with_yaml" "e2e_tests"
}

@test "pipeline_sdd_layers_inline_map_parses_in_both_paths_nested_form_diverges" {
  # The measurement C1 rests on, kept executable: written as a NESTED block the
  # two branches disagree. If a future edit reformats the default to nested,
  # this test says why that is not a cosmetic change.
  printf 'version: 1\nsdd:\n  layers:\n    contract_first: true\n    e2e_tests: true\n' > "$WORK"
  local with_yaml without_yaml
  with_yaml="$(parse_layers "$WORK" pyyaml)"
  without_yaml="$(parse_layers "$WORK" fallback)"
  [ "$with_yaml" != "$without_yaml" ]
  [ "$without_yaml" = "None" ]
}

@test "pipeline_sdd_layers_nested_block_is_rejected" {
  # The previous test proves the two PARSERS disagree about a nested block. This
  # one proves the VALIDATOR refuses it — without that, a user who writes the
  # nested form gets the divergence silently: PyYAML sees three layers, the
  # fallback sees none, and the gates run against whichever happens to be
  # installed. Rejecting the shape is what keeps the two branches honest.
  cp "$DEFAULT" "$WORK"
  python3 - "$WORK" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    "  layers: {contract_first: true, integration_tests: true, e2e_tests: true}",
    "  layers:\n    contract_first: true\n    integration_tests: true\n    e2e_tests: true")
open(p, "w", encoding="utf-8").write(s)
PY
  [ "$(parse_layers "$WORK" fallback)" = "None" ]
  run "$VALIDATE" "$WORK"
  [ "$status" -ne 0 ]
  assert_substring "$output" "sdd.layers: must be an inline mapping"
}

@test "pipeline_sdd_layers_default_ships_all_three_enabled" {
  # REQ-012: defaults come from here, and unset means enabled.
  local got
  got="$(parse_layers "$DEFAULT" fallback)"
  assert_substring "$got" "'contract_first': True"
  assert_substring "$got" "'integration_tests': True"
  assert_substring "$got" "'e2e_tests': True"
}

@test "pipeline_sdd_layers_non_boolean_fails" {
  cp "$DEFAULT" "$WORK"
  python3 - "$WORK" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    "layers: {contract_first: true, integration_tests: true, e2e_tests: true}",
    "layers: {contract_first: sometimes, integration_tests: true, e2e_tests: true}")
open(p, "w", encoding="utf-8").write(s)
PY
  assert_grep -qF -e 'contract_first: sometimes' "$WORK"
  run "$VALIDATE" "$WORK"
  [ "$status" -ne 0 ]
  assert_substring "$output" "layers"
}

@test "pipeline_sdd_layers_unknown_key_fails" {
  cp "$DEFAULT" "$WORK"
  python3 - "$WORK" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    "layers: {contract_first: true, integration_tests: true, e2e_tests: true}",
    "layers: {contract_first: true, smoke_tests: true}")
open(p, "w", encoding="utf-8").write(s)
PY
  run "$VALIDATE" "$WORK"
  [ "$status" -ne 0 ]
  assert_substring "$output" "layers"
}

@test "pipeline_sdd_layers_absent_block_is_ok" {
  # An absent block means "use the built-in defaults", not a config error —
  # every pipeline.yaml written before S8 has no such block.
  cp "$DEFAULT" "$WORK"
  python3 - "$WORK" <<'PY'
import sys
p = sys.argv[1]
lines = [l for l in open(p, encoding="utf-8").read().split("\n")
         if not l.strip().startswith("layers:")]
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
  # Assert on what the PARSER sees, not on the literal text: the config's own
  # explanatory comment mentions `layers:`, so a text grep answers a different
  # question than the one this precondition is asking.
  [ "$(parse_layers "$WORK" fallback)" = "None" ]
  [ "$(parse_layers "$WORK" pyyaml)" = "None" ]
  run "$VALIDATE" "$WORK"
  [ "$status" -eq 0 ]
}

@test "pipeline_sdd_layers_shipped_default_still_validates" {
  # The file we ship must pass its own validator.
  run "$VALIDATE" "$DEFAULT"
  [ "$status" -eq 0 ]
}

@test "pipeline_sdd_layers_live_pipeline_still_validates" {
  # Adding the block must not invalidate the bank's real pipeline.yaml.
  #
  # No `if -f ... else` fallback here, deliberately. The else branch was dead —
  # the guard is always true in this repo — so its assertion certified nothing
  # while reading as coverage, and if the file ever went missing the test would
  # have quietly validated a different file and still passed. Assert the
  # precondition instead, so an absent bank config fails loudly.
  [ -f "$REPO_ROOT/.memory-bank/pipeline.yaml" ]
  run "$VALIDATE" "$REPO_ROOT/.memory-bank/pipeline.yaml"
  [ "$status" -eq 0 ]
}
