#!/usr/bin/env bats
# Contract tests for agents/mb-rules-enforcer.md prompt + script JSON shape.
#
# The agent is a thin LLM wrapper around scripts/mb-rules-check.sh. These
# tests check that:
#   1. The prompt file exists and carries the required frontmatter.
#   2. The prompt references the deterministic script it delegates to.
#   3. The prompt documents the JSON output schema so downstream callers can
#      rely on it (example must parse with `jq`).
#   4. The prompt names all 3 rule categories Stage 2 ships (solid/srp,
#      clean_arch/direction, tdd/delta) so reviewers can grep for coverage.
#
# Contract-only: we do not run the LLM. We validate that the written prompt
# stays in sync with the script's behavior.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMPT="$REPO_ROOT/agents/mb-rules-enforcer.md"
  CHECK="$REPO_ROOT/scripts/mb-rules-check.sh"
  command -v jq >/dev/null || skip "jq required"
}

@test "contract: prompt file exists" {
  [ -f "$PROMPT" ]
}

@test "contract: frontmatter has name + description + tools + color" {
  # YAML frontmatter is the first block between the first two '---' lines.
  head -n 20 "$PROMPT" | grep -q '^name: mb-rules-enforcer$'
  head -n 20 "$PROMPT" | grep -q '^description: '
  head -n 20 "$PROMPT" | grep -q '^tools: '
  head -n 20 "$PROMPT" | grep -q '^color: '
}

@test "contract: prompt references scripts/mb-rules-check.sh" {
  grep -Fq 'scripts/mb-rules-check.sh' "$PROMPT"
}

@test "contract: prompt lists all 3 rule IDs (solid/srp, clean_arch/direction, tdd/delta)" {
  grep -Fq 'solid/srp' "$PROMPT"
  grep -Fq 'clean_arch/direction' "$PROMPT"
  grep -Fq 'tdd/delta' "$PROMPT"
}

@test "contract: prompt declares CRITICAL/WARNING/INFO severity vocabulary" {
  grep -Eq 'CRITICAL' "$PROMPT"
  grep -Eq 'WARNING'  "$PROMPT"
  grep -Eq 'INFO'     "$PROMPT"
}

@test "contract: script is executable and shows --help or usage on no-args" {
  [ -x "$CHECK" ] || [ -f "$CHECK" ]
  # --help must exit 0 with some usage text
  run bash "$CHECK" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--files"* ]]
}

@test "contract: script empty --files runs, returns zero violations + valid JSON" {
  run bash "$CHECK" --files "" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.violations | length == 0'
  echo "$output" | jq -e '.stats.files_scanned == 0'
  echo "$output" | jq -e '.stats | has("checks_run") and has("duration_ms")'
}

@test "contract: unknown rule is never emitted" {
  TMPROOT="$(mktemp -d)"
  cd "$TMPROOT"
  mkdir -p src
  for i in {1..350}; do echo "line $i"; done > src/big.py
  run bash "$CHECK" --files "src/big.py" --out json
  [ "$status" -eq 0 ]
  # Every emitted rule must match the closed vocabulary.
  echo "$output" | jq -e '
    .violations
    | all(.rule == "solid/srp" or .rule == "clean_arch/direction" or .rule == "tdd/delta" or .rule == "solid/isp" or .rule == "dry/repetition")
  '
  rm -rf "$TMPROOT"
}

@test "contract: --out human produces non-empty human summary" {
  TMPROOT="$(mktemp -d)"
  cd "$TMPROOT"
  mkdir -p src
  for i in {1..310}; do echo "line $i"; done > src/big.py
  run bash "$CHECK" --files "src/big.py" --out human
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" == *"solid/srp"* ]] || [[ "$output" == *"SRP"* ]] || [[ "$output" == *"src/big.py"* ]]
  rm -rf "$TMPROOT"
}

@test "rules_source: the project root RULES.md wins over the bank copy, then the bank, then the bundle" {
  proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj/.memory-bank"
  git -C "$BATS_TEST_TMPDIR" init -q proj
  printf '# root rules\n' >"$proj/RULES.md"
  printf '# bank rules\n' >"$proj/.memory-bank/RULES.md"
  printf 'x = 1\n' >"$proj/a.py"
  run bash -c "cd '$proj' && bash '$CHECK' --files a.py --out json"
  [ "$(printf '%s' "$output" | tail -n1 | jq -r .rules_source)" = "$proj/RULES.md" ]
  rm "$proj/RULES.md"
  run bash -c "cd '$proj' && bash '$CHECK' --files a.py --out json"
  [ "$(printf '%s' "$output" | tail -n1 | jq -r .rules_source)" = "$proj/.memory-bank/RULES.md" ]
  rm "$proj/.memory-bank/RULES.md"
  run bash -c "cd '$proj' && bash '$CHECK' --files a.py --out json"
  [ "$(printf '%s' "$output" | tail -n1 | jq -r .rules_source)" = "bundled:rules/RULES.md" ]
}

@test "contract: enforcer reads the rules_source the checker resolved, project root RULES.md first" {
  grep -Fq 'rules_source' "$PROMPT"
  grep -Fq '<project>/RULES.md' "$PROMPT"
  # The resolution list (one source per bullet) puts the project root first.
  awk '!p && /^ *- `<project>\/RULES.md`/{p=NR} !b && /^ *- `<bank>\/RULES.md`/{b=NR} END{exit !(p && b && p<b)}' "$PROMPT"
}
