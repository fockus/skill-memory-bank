#!/usr/bin/env bats

# Direct tests for adapters/_framework.sh and adapters/_contract.sh.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FRAMEWORK="$REPO_ROOT/adapters/_framework.sh"
  CONTRACT="$REPO_ROOT/adapters/_contract.sh"
  TMPDIR="$(mktemp -d)"
  MANIFEST="$TMPDIR/manifest.json"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

@test "framework: adapter_write_manifest writes schema_version and preserves file order" {
  # shellcheck source=/dev/null
  source "$FRAMEWORK"

  files_json='["/tmp/a","/tmp/b","/tmp/c"]'
  extra_json='{"hooks_events":["sessionEnd"],"agents_md_owned":true}'

  run adapter_write_manifest "$MANIFEST" "cursor" "1.2.3" "$files_json" "$extra_json"
  [ "$status" -eq 0 ]
  jq -e '.schema_version == 1' "$MANIFEST" >/dev/null
  jq -e '.adapter == "cursor"' "$MANIFEST" >/dev/null
  jq -e '.files == ["/tmp/a","/tmp/b","/tmp/c"]' "$MANIFEST" >/dev/null
  jq -e '.hooks_events == ["sessionEnd"]' "$MANIFEST" >/dev/null
}

# ═══ A22 (CDX-I11): atomic manifest write ═══
#
# adapter_write_manifest used to redirect `jq ... > "$manifest_path"` directly
# — a plain redirect TRUNCATES the target before jq even runs, so a failed jq
# invocation (or an interrupted process) left a corrupt/empty manifest behind
# instead of leaving the previous, still-valid one in place.

@test "framework: adapter_write_manifest is atomic — a failed write does not corrupt the existing manifest" {
  # shellcheck source=/dev/null
  source "$FRAMEWORK"

  echo '{"schema_version":1,"adapter":"cursor","files":["/tmp/old"]}' > "$MANIFEST"

  # An invalid --argjson value makes jq fail before producing any output. A
  # non-atomic `> "$manifest_path"` write truncates the target regardless;
  # tmp+mv never touches the real path until jq has already succeeded.
  run adapter_write_manifest "$MANIFEST" "cursor" "1.2.3" 'not-valid-json' '{}'
  [ "$status" -ne 0 ]

  jq -e '.files == ["/tmp/old"]' "$MANIFEST" >/dev/null
}

@test "framework: adapter_write_manifest leaves no stray tmp files behind on success" {
  # shellcheck source=/dev/null
  source "$FRAMEWORK"

  run adapter_write_manifest "$MANIFEST" "cursor" "1.2.3" '["/tmp/a"]' '{}'
  [ "$status" -eq 0 ]
  ! find "$TMPDIR" -maxdepth 1 -name '*.XXXXXX' 2>/dev/null | grep -q .
  ! find "$TMPDIR" -maxdepth 1 -name "$(basename "$MANIFEST").*" 2>/dev/null | grep -q .
}

# A14 (L-3): an empty bash array fed through `printf '%s\n' "${arr[@]}"` still
# emits one bare newline (printf always applies its format at least once),
# which used to slurp into `[""]` instead of `[]`.
@test "framework: adapter_json_array_from_lines on truly empty input yields []" {
  run bash -c '
    source "'"$FRAMEWORK"'"
    printf "" | adapter_json_array_from_lines
  '
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "framework: adapter_json_array_from_lines on an empty bash array (printf degenerate case) yields []" {
  # shellcheck source=/dev/null
  source "$FRAMEWORK"

  run bash -c '
    source "'"$FRAMEWORK"'"
    arr=()
    printf "%s\n" "${arr[@]}" | adapter_json_array_from_lines
  '
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "framework: adapter_json_array_from_lines preserves real entries and drops blank lines" {
  run bash -c '
    source "'"$FRAMEWORK"'"
    printf "a\n\nb\n" | adapter_json_array_from_lines
  '
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c .)" = '["a","b"]' ]
}

@test "contract: missing required functions fails with clear message" {
  # shellcheck source=/dev/null
  source "$CONTRACT"

  run adapter_contract_require_functions install_missing uninstall_missing
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required adapter function"* ]]
}

@test "contract: present required functions passes" {
  # shellcheck source=/dev/null
  source "$CONTRACT"

  install_ok() { :; }
  uninstall_ok() { :; }

  run adapter_contract_require_functions install_ok uninstall_ok
  [ "$status" -eq 0 ]
}

# ═══ C5 (CDX-8): artifact-level checks ═══
#
# adapter_contract_require_functions only proves the adapter DECLARES
# install_*/uninstall_* functions (declare -F) — it says nothing about
# whether calling install_* actually produces artifacts on disk. A "broken
# parity" adapter (functions exist, but install is a no-op) used to pass the
# contract cleanly, giving false-green test suites. These tests pin down a
# new adapter_contract_require_artifacts that reads a manifest's `files[]`
# and verifies every declared path exists.

@test "contract: broken-parity stub (declares functions, installs nothing) fails artifact check" {
  # shellcheck source=/dev/null
  source "$FRAMEWORK"
  # shellcheck source=/dev/null
  source "$CONTRACT"

  install_broken() { :; }     # declares the function contract...
  uninstall_broken() { :; }

  # ...but "installs" a manifest that CLAIMS artifacts it never wrote.
  local files_json
  files_json="$(printf '%s\n' "$TMPDIR/commands/fake.md" "$TMPDIR/rules/fake.md" | adapter_json_array_from_lines)"
  adapter_write_manifest "$MANIFEST" "broken" "9.9.9" "$files_json" '{}'

  # Function-level contract still (misleadingly) passes.
  run adapter_contract_require_functions install_broken uninstall_broken
  [ "$status" -eq 0 ]

  # Artifact-level contract must catch the broken parity.
  run adapter_contract_require_artifacts "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "contract: real artifacts on disk pass the artifact check" {
  # shellcheck source=/dev/null
  source "$FRAMEWORK"
  # shellcheck source=/dev/null
  source "$CONTRACT"

  mkdir -p "$TMPDIR/commands" "$TMPDIR/rules"
  echo "# fake command" > "$TMPDIR/commands/fake.md"
  echo "# fake rule" > "$TMPDIR/rules/fake.md"

  local files_json
  files_json="$(printf '%s\n' "$TMPDIR/commands/fake.md" "$TMPDIR/rules/fake.md" | adapter_json_array_from_lines)"
  adapter_write_manifest "$MANIFEST" "ok" "9.9.9" "$files_json" '{}'

  run adapter_contract_require_artifacts "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "contract: missing manifest fails the artifact check with a clear message" {
  # shellcheck source=/dev/null
  source "$CONTRACT"

  run adapter_contract_require_artifacts "$TMPDIR/does-not-exist.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest"* ]]
}

@test "contract: platform-limited hosts can declare optional artifacts without failing" {
  # A host with a documented degradation (e.g. Codex without statusline)
  # passes an explicit skip-list of optional artifact categories instead of
  # silently omitting them from files[] — honest degradation, not a failure.
  # shellcheck source=/dev/null
  source "$FRAMEWORK"
  # shellcheck source=/dev/null
  source "$CONTRACT"

  mkdir -p "$TMPDIR/commands"
  echo "# fake command" > "$TMPDIR/commands/fake.md"

  local files_json
  files_json="$(printf '%s\n' "$TMPDIR/commands/fake.md" | adapter_json_array_from_lines)"
  adapter_write_manifest "$MANIFEST" "codex" "9.9.9" "$files_json" \
    '{"platform_limited": ["statusline"]}'

  run adapter_contract_require_artifacts "$MANIFEST"
  [ "$status" -eq 0 ]
}
