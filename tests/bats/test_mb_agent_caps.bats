#!/usr/bin/env bats
# Tests for scripts/mb-agent-caps.sh — capability-aware transport+model resolver.
# Hermetic: MB_CAPS_FIXTURE bypasses real pi/opencode probing, so CI needs neither.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CAPS="$REPO_ROOT/scripts/mb-agent-caps.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"
  cat > "$BANK/pipeline.yaml" <<'YAML'
version: "1"
roles:
  reviewer: { agent: mb-reviewer, model: openai-codex/gpt-5.5, thinking: xhigh }
  backend:  { agent: mb-backend,  model: opencode-go/deepseek-v4-pro, thinking: high }
dispatch:
  priority: [pi, opencode, claude-agent]
  on_none_available: fallback
  prefer:
    "openai-codex/*": codex
  enumerable: [pi, opencode]
  model_map:
    openai-codex/gpt-5.5: { codex: gpt-5.5, opencode: opencode/gpt-5.2 }
    opencode-go/deepseek-v4-pro: { opencode: opencode/deepseek-v4-flash }
  fallback:
    claude-agent: { reviewer: opus, backend: sonnet }
YAML
}

fixture() { # write fixture lines to a temp file, echo its path
  local f="$BATS_TEST_TMPDIR/fix.$RANDOM"
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

@test "resolve: pi offers the contract model → transport=pi, unmapped contract id" {
  local fix; fix=$(fixture "transport pi" "transport opencode" \
    "model pi openai-codex/gpt-5.5" "model opencode opencode/gpt-5.2")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role reviewer --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=pi"* ]]
  [[ "$output" == *"model=openai-codex/gpt-5.5"* ]]
  [[ "$output" == *"substituted=false"* ]]
}

@test "resolve: pi absent, opencode offers mapped model → transport=opencode mapped id" {
  local fix; fix=$(fixture "transport opencode" "model opencode opencode/gpt-5.2")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role reviewer --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=opencode"* ]]
  [[ "$output" == *"model=opencode/gpt-5.2"* ]]
}

@test "resolve: priority is pi before opencode when both offer a model" {
  local fix; fix=$(fixture "transport pi" "transport opencode" \
    "model pi openai-codex/gpt-5.5" "model opencode opencode/gpt-5.2")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role reviewer --mb "$BANK"
  [[ "$output" == *"transport=pi"* ]]
}

@test "resolve: opencode installed but model missing → falls through" {
  # opencode present but does NOT list the mapped model → must fall back to claude
  local fix; fix=$(fixture "transport opencode" "model opencode some/other-model")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role reviewer --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=claude-agent"* ]]
  [[ "$output" == *"substituted=true"* ]]
}

@test "resolve: nothing available → claude-agent fallback with role tier model" {
  local fix; fix=$(fixture)
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role reviewer --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=claude-agent"* ]]
  [[ "$output" == *"model=opus"* ]]
  [[ "$output" == *"substituted=true"* ]]
}

@test "resolve: backend tier falls back to sonnet" {
  local fix; fix=$(fixture)
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role backend --mb "$BANK"
  [[ "$output" == *"model=sonnet"* ]]
}

@test "resolve: on_none_available=error → exit 3 when nothing available" {
  sed -i.bak 's/on_none_available: fallback/on_none_available: error/' "$BANK/pipeline.yaml"
  local fix; fix=$(fixture)
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role reviewer --mb "$BANK"
  [ "$status" -eq 3 ]
}

@test "resolve: unknown role (no model) → exit 1" {
  local fix; fix=$(fixture "transport pi" "model pi x/y")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role nonesuch --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "resolve: --role is required" {
  run bash "$CAPS" resolve --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "detect: reports availability and model counts from fixture" {
  local fix; fix=$(fixture "transport pi" "model pi a/b" "model pi c/d")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" detect --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=pi available=true models=2"* ]]
  [[ "$output" == *"transport=opencode available=false"* ]]
  [[ "$output" == *"transport=claude-agent available=true"* ]]
}

@test "resolve: chatgpt model + codex present → prefers codex (trusted), mapped id" {
  # codex is non-enumerable: no "model codex ..." line needed, just the transport.
  local fix; fix=$(fixture "transport codex" "transport pi" "model pi openai-codex/gpt-5.5")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role reviewer --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=codex"* ]]
  [[ "$output" == *"model=gpt-5.5"* ]]
  [[ "$output" == *"substituted=false"* ]]
}

@test "resolve: chatgpt model, codex absent → falls through to pi" {
  local fix; fix=$(fixture "transport pi" "model pi openai-codex/gpt-5.5")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role reviewer --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=pi"* ]]
}

@test "resolve: non-chatgpt role does not prefer codex even when codex present" {
  local fix; fix=$(fixture "transport codex" "transport opencode" \
    "model opencode opencode/deepseek-v4-flash")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" resolve --role backend --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=opencode"* ]]
  [[ "$output" != *"transport=codex"* ]]
}

@test "detect: includes codex transport" {
  local fix; fix=$(fixture "transport codex")
  run env MB_CAPS_FIXTURE="$fix" bash "$CAPS" detect --mb "$BANK"
  [[ "$output" == *"transport=codex available=true"* ]]
}

@test "unknown subcommand → exit 1" {
  run bash "$CAPS" frobnicate
  [ "$status" -eq 1 ]
}
