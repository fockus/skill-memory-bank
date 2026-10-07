#!/usr/bin/env bats
# `/mb config init --host` templates and the `/mb config show` role matrix
# (plan pipeline-presets-cost-tiers, Stage 4; AGR-074).
#
#   mb-pipeline.sh init --host <h> [--preset P] [--cost C] [--model-premium X] [--model-mid Y] [--force] [mb]
#   mb-pipeline.sh matrix [--host H] [--cost C] [--preset P] [--verify V] [mb]
#
# Host config files are faked under a temp HOME; the real ~/.pi,
# ~/.config/opencode and ~/.codex are never read or written.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PIPE="$REPO_ROOT/scripts/mb-pipeline.sh"
  VALIDATE="$REPO_ROOT/scripts/mb-pipeline-validate.sh"
  TMPROOT="$(mktemp -d)"
  PROJ="$TMPROOT/proj"
  BANK="$PROJ/.memory-bank"
  mkdir -p "$BANK" "$TMPROOT/home"
  # Keep a user-site PyYAML importable after HOME moves.
  PYTHONUSERBASE="$(python3 -m site --user-base)"
  export PYTHONUSERBASE
  export HOME="$TMPROOT/home"
  unset XDG_CONFIG_HOME OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT MB_PATH MB_PIPELINE \
        MB_PIPELINE_HOST MB_AGENT CLAUDECODE CLAUDE_CODE_ENTRYPOINT OPENCODE OPENCODE_BIN \
        CODEX_SANDBOX CODEX_HOME CURSOR_TRACE_ID CURSOR_AGENT WINDSURF_AGENT PI_AGENT || true
  cd "$PROJ" || return 1
}

teardown() {
  [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

pi_settings() {  # $1 = file, $2 = provider, $3 = model
  mkdir -p "$(dirname "$1")"
  printf '{"defaultProvider": "%s", "defaultModel": "%s", "defaultThinkingLevel": "max"}\n' "$2" "$3" >"$1"
}

# ═══ init: one valid template per host ═══

@test "config init --host claude-code: valid, opus/sonnet profile, optimal" {
  run bash "$PIPE" init --host claude-code "$BANK"
  [ "$status" -eq 0 ]
  run bash "$VALIDATE" "$BANK/pipeline.yaml"
  [ "$status" -eq 0 ]
  assert_grep -q '^  claude-code: {premium: opus, mid: sonnet}$' "$BANK/pipeline.yaml"
  assert_grep -q '^cost: optimal$' "$BANK/pipeline.yaml"
}

@test "config init --host codex --preset complex --cost economy: valid, codex ids, preset and cost written" {
  run bash "$PIPE" init --host codex --preset complex --cost economy "$BANK"
  [ "$status" -eq 0 ]
  run bash "$VALIDATE" "$BANK/pipeline.yaml"
  [ "$status" -eq 0 ]
  assert_grep -q '^  codex: {premium: gpt-6-astra, mid: gpt-6.1-sol}$' "$BANK/pipeline.yaml"
  assert_grep -q '^  default: complex$' "$BANK/pipeline.yaml"
  assert_grep -q '^cost: economy$' "$BANK/pipeline.yaml"
}

@test "config init --host cursor: valid, Anthropic pair, static-model note" {
  run bash "$PIPE" init --host cursor "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "static"
  assert_grep -q '^  cursor: {premium: claude-opus-5-5, mid: claude-sonnet-5-5}$' "$BANK/pipeline.yaml"
  run bash "$VALIDATE" "$BANK/pipeline.yaml"
  [ "$status" -eq 0 ]
}

@test "config init --host pi: premium from ~/.pi settings, mid from flag, valid" {
  pi_settings "$HOME/.pi/agent/settings.json" anthropic claude-opus-5-5
  run bash "$PIPE" init --host pi --model-mid anthropic/claude-sonnet-5-5 "$BANK"
  [ "$status" -eq 0 ]
  assert_grep -q '^  pi: {premium: anthropic/claude-opus-5-5, mid: anthropic/claude-sonnet-5-5}$' "$BANK/pipeline.yaml"
  run bash "$VALIDATE" "$BANK/pipeline.yaml"
  [ "$status" -eq 0 ]
}

@test "config init --host pi: project .pi/settings.json beats the global one" {
  pi_settings "$HOME/.pi/agent/settings.json" anthropic claude-opus-5-5
  pi_settings "$PROJ/.pi/settings.json" openai gpt-6-astra
  run bash "$PIPE" init --host pi --model-mid openai/gpt-6.1-sol "$BANK"
  [ "$status" -eq 0 ]
  assert_grep -q '^  pi: {premium: openai/gpt-6-astra, mid: openai/gpt-6.1-sol}$' "$BANK/pipeline.yaml"
}

@test "config init --host pi: no detectable model and no --model-premium → exit 2, nothing written" {
  run bash "$PIPE" init --host pi --model-mid anthropic/claude-sonnet-5-5 "$BANK"
  [ "$status" -eq 2 ]
  assert_substring "$output" "--model-premium"
  refute_file "$BANK/pipeline.yaml"
}

@test "config init --host pi: --model-mid from another provider → exit 2" {
  pi_settings "$HOME/.pi/agent/settings.json" anthropic claude-opus-5-5
  run bash "$PIPE" init --host pi --model-mid openai/gpt-6.1-sol "$BANK"
  [ "$status" -eq 2 ]
  assert_substring "$output" "provider"
  refute_file "$BANK/pipeline.yaml"
}

@test "config init --host pi: missing --model-mid → exit 2 (no placeholder)" {
  pi_settings "$HOME/.pi/agent/settings.json" anthropic claude-opus-5-5
  run bash "$PIPE" init --host pi "$BANK"
  [ "$status" -eq 2 ]
  assert_substring "$output" "--model-mid"
  refute_file "$BANK/pipeline.yaml"
}

@test "config init --host opencode: premium from opencode.json model (never small_model), valid" {
  mkdir -p "$HOME/.config/opencode"
  printf '{"model": "openai/gpt-6-astra", "small_model": "openai/gpt-6-luna"}\n' >"$HOME/.config/opencode/opencode.json"
  run bash "$PIPE" init --host opencode --model-mid openai/gpt-6.1-sol "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "static"
  assert_grep -q '^  opencode: {premium: openai/gpt-6-astra, mid: openai/gpt-6.1-sol}$' "$BANK/pipeline.yaml"
  refute_grep -q 'gpt-6-luna' "$BANK/pipeline.yaml"
  run bash "$VALIDATE" "$BANK/pipeline.yaml"
  [ "$status" -eq 0 ]
}

@test "config init --host opencode: project opencode.json beats the global one" {
  mkdir -p "$HOME/.config/opencode"
  printf '{"model": "openai/gpt-6-astra"}\n' >"$HOME/.config/opencode/opencode.json"
  printf '{"model": "anthropic/claude-opus-5-5"}\n' >"$PROJ/opencode.json"
  run bash "$PIPE" init --host opencode --model-mid anthropic/claude-sonnet-5-5 "$BANK"
  [ "$status" -eq 0 ]
  assert_grep -q '^  opencode: {premium: anthropic/claude-opus-5-5, mid: anthropic/claude-sonnet-5-5}$' "$BANK/pipeline.yaml"
}

@test "config init --host opencode: no config and no --model-premium → exit 2" {
  run bash "$PIPE" init --host opencode --model-mid openai/gpt-6.1-sol "$BANK"
  [ "$status" -eq 2 ]
  assert_substring "$output" "--model-premium"
  refute_file "$BANK/pipeline.yaml"
}

@test "config init: shipped default carries no pi/opencode placeholder profiles" {
  refute_grep -qE '^  (pi|opencode):' "$REPO_ROOT/references/pipeline.default.yaml"
}

# ═══ init: overwrite guard and usage errors ═══

@test "config init --host without --force keeps project edits and prints the keys to add" {
  bash "$PIPE" init --host claude-code "$BANK"
  printf '\n# project edit\ncustom_marker: true\n' >>"$BANK/pipeline.yaml"
  snapshot "$BANK/pipeline.yaml" BEFORE
  run bash "$PIPE" init --host codex --cost economy "$BANK"
  [ "$status" -eq 1 ]
  assert_substring "$output" "--force"
  assert_substring "$output" "codex: {premium: gpt-6-astra, mid: gpt-6.1-sol}"
  assert_unchanged "$BANK/pipeline.yaml" BEFORE
}

@test "config init --host --force rewrites from the template" {
  printf 'custom: true\n' >"$BANK/pipeline.yaml"
  run bash "$PIPE" init --host codex --force "$BANK"
  [ "$status" -eq 0 ]
  refute_grep -q '^custom: true' "$BANK/pipeline.yaml"
  run bash "$VALIDATE" "$BANK/pipeline.yaml"
  [ "$status" -eq 0 ]
}

@test "config init: unknown host / cost / preset → exit 2" {
  run bash "$PIPE" init --host vscode "$BANK"
  [ "$status" -eq 2 ]
  run bash "$PIPE" init --host codex --cost cheap "$BANK"
  [ "$status" -eq 2 ]
  run bash "$PIPE" init --host codex --preset nope "$BANK"
  [ "$status" -eq 2 ]
  refute_file "$BANK/pipeline.yaml"
}

@test "config init without host flags stays a byte copy of the default" {
  run bash "$PIPE" init "$BANK"
  [ "$status" -eq 0 ]
  cmp -s "$REPO_ROOT/references/pipeline.default.yaml" "$BANK/pipeline.yaml"
}

# ═══ show (matrix) ═══

@test "config show: claude-code optimal matrix with agents, models and sources" {
  bash "$PIPE" init --host claude-code "$BANK"
  run bash "$PIPE" matrix --host claude-code "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "implement → verify → done"
  assert_substring "$output" "verify: plan"
  assert_substring "$output" "cost: optimal"
  [[ "$output" =~ developer\ +mb-developer\ +sonnet\ +profile\ +calm ]]
  [[ "$output" =~ reviewer\ +mb-reviewer\ +opus\ +profile ]]
  [[ "$output" =~ verifier\ +plan-verifier\ +sonnet\ +profile ]]
}

@test "config show: --cost premium and --preset governed are applied" {
  run bash "$PIPE" matrix --host claude-code --cost premium --preset governed --verify stage "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" =~ developer\ +mb-developer\ +opus\ +profile ]]
  assert_substring "$output" "judge"
  assert_substring "$output" "verify: stage"
  assert_substring "$output" "cost: premium"
}

@test "config show: pi without a profile → inherit plus the Pi alias note" {
  run bash "$PIPE" matrix --host pi "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" =~ developer\ +mb-developer\ +inherit\ +inherit ]]
  assert_substring "$output" "AGR-056"
}

@test "config show: bad --cost → exit 2" {
  run bash "$PIPE" matrix --host claude-code --cost cheap "$BANK"
  [ "$status" -eq 2 ]
}

@test "config show on this repo: explicit models win (opus roles, codex-cli reviewer gpt-5.6-sol)" {
  cd "$REPO_ROOT" || return 1
  run bash "$PIPE" matrix --host claude-code "$REPO_ROOT/.memory-bank"
  [ "$status" -eq 0 ]
  [[ "$output" =~ developer\ +mb-developer\ +opus\ +role ]]
  [[ "$output" =~ reviewer\ +codex-cli\ +gpt-5.6-sol\ +role ]]
  [[ "$output" =~ judge\ +mb-judge\ +opus\ +role ]]
}

# ═══ Stage 4b: init re-renders the installed agents of static-model hosts ═══
# Installs go to the temp HOME / temp project only.

cursor_global_install() {
  MB_LANGUAGE=en bash "$REPO_ROOT/adapters/cursor.sh" install-global </dev/null >/dev/null
}

@test "config init --host cursor --cost premium: installed mb-developer gets the premium model" {
  cursor_global_install
  run bash "$PIPE" init --host cursor --cost premium "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "applied"
  assert_substring "$(cat "$HOME/.cursor/agents/mb-developer.md")" $'\nmodel: claude-opus-5-5\n'
}

@test "config init --host cursor (optimal): developer mid, reviewer premium, role-less agent none" {
  cursor_global_install
  run bash "$PIPE" init --host cursor --cost premium "$BANK"
  run bash "$PIPE" init --host cursor --force "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$(cat "$HOME/.cursor/agents/mb-developer.md")" $'\nmodel: claude-sonnet-5-5\n'
  assert_substring "$(cat "$HOME/.cursor/agents/mb-reviewer.md")" $'\nmodel: claude-opus-5-5\n'
  refute_substring "$(cat "$HOME/.cursor/agents/mb-doctor.md")" $'\nmodel:'
}

@test "config init --host cursor repeated: installed agents byte-identical, no backups" {
  cursor_global_install
  bash "$PIPE" init --host cursor --cost premium "$BANK"
  cp -R "$HOME/.cursor/agents" "$TMPROOT/snap"
  run bash "$PIPE" init --host cursor --cost premium --force "$BANK"
  [ "$status" -eq 0 ]
  run diff -r "$TMPROOT/snap" "$HOME/.cursor/agents"
  [ "$status" -eq 0 ]
}

@test "config init --host cursor without installed agents: pipeline written, nothing installed" {
  run bash "$PIPE" init --host cursor "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "not installed"
  [ ! -e "$HOME/.cursor" ]
}

@test "config init --host opencode: project agents get model provider/id from the profile" {
  bash "$REPO_ROOT/adapters/opencode.sh" install "$PROJ" >/dev/null
  refute_substring "$(cat "$PROJ/.opencode/agent/mb-developer.md")" $'\nmodel:'
  run bash "$PIPE" init --host opencode --model-premium openai/gpt-6-astra --model-mid openai/gpt-6.1-sol "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$(cat "$PROJ/.opencode/agent/mb-developer.md")" $'\nmodel: openai/gpt-6.1-sol\n'
  assert_substring "$(cat "$PROJ/.opencode/agent/mb-reviewer.md")" $'\nmodel: openai/gpt-6-astra\n'
}

@test "config init --host codex: installed role toml gets model" {
  mkdir -p "$HOME/.codex/agents"
  python3 "$REPO_ROOT/scripts/mb-agent-render.py" "$REPO_ROOT/agents/mb-developer.md" \
    --skill-dir "$REPO_ROOT" --host codex > "$HOME/.codex/agents/mb-developer.toml"
  run bash "$PIPE" init --host codex --cost premium "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$(cat "$HOME/.codex/agents/mb-developer.toml")" 'model = "gpt-6-astra"'
}

@test "config show: static hosts say installed agents, dynamic hosts per-dispatch" {
  run bash "$PIPE" matrix --host cursor "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "applied: static (installed agents)"
  run bash "$PIPE" matrix --host claude-code "$BANK"
  assert_substring "$output" "applied: per-dispatch"
}

# ═══ show: Quality section (project-quality-settings Stage 3, AGR-076) ═══

@test "config show: Quality section shows resolved values with their source" {
  printf '{"schema_version":1,"scope":"project","quality":{"tdd":"off","coverage":{"enabled":true,"overall":80}}}\n' \
    >"$BANK/rules-profile.json"
  run bash "$PIPE" matrix --host claude-code "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "quality:"
  assert_substring "$output" "quality.tdd = off (project)"
  assert_substring "$output" "quality.coverage.enabled = true (project)"
  assert_substring "$output" "quality.coverage.overall = 80 (project)"
  assert_substring "$output" "quality.testing_trophy = on (default)"
}

@test "config show: an invalid quality profile does not hide the role matrix" {
  printf '{"schema_version":1,"scope":"project","quality":{"tdd":"sometimes"}}\n' >"$BANK/rules-profile.json"
  run bash "$PIPE" matrix --host claude-code "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "mb-developer"
  assert_substring "$output" "quality: invalid"
}
