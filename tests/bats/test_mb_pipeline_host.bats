#!/usr/bin/env bats
# Tests for scripts/_lib.sh named-pipeline helpers:
#   mb_detect_host    — resolve current code-agent host id
#   mb_pipeline_dir   — <bank>/pipelines directory
#   mb_pipeline_meta  — read pipeline_name / default / agents from a pipeline file

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/scripts/_lib.sh"
  TMPDIR="$(mktemp -d)"

  [ -f "$LIB" ] || skip "scripts/_lib.sh not implemented yet (TDD red phase)"

  # Hermetic baseline: clear every host signature this test process may have
  # inherited (the suite itself often runs inside Claude Code → CLAUDECODE set).
  unset MB_PIPELINE_HOST MB_AGENT \
        CLAUDECODE CLAUDE_CODE_ENTRYPOINT \
        CURSOR_TRACE_ID CURSOR_AGENT \
        OPENCODE OPENCODE_BIN \
        CODEX_SANDBOX CODEX_HOME \
        WINDSURF_AGENT PI_AGENT || true

  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ═══ mb_detect_host ═══

@test "mb_detect_host: no signals → empty" {
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mb_detect_host: MB_PIPELINE_HOST override wins" {
  export MB_PIPELINE_HOST="opencode"
  export CLAUDECODE="1"
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
}

@test "mb_detect_host: MB_AGENT used when no explicit override" {
  export MB_AGENT="pi"
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ "$output" = "pi" ]
}

@test "mb_detect_host: CLAUDECODE env → claude-code" {
  export CLAUDECODE="1"
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ "$output" = "claude-code" ]
}

@test "mb_detect_host: CLAUDE_CODE_ENTRYPOINT env → claude-code" {
  export CLAUDE_CODE_ENTRYPOINT="cli"
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ "$output" = "claude-code" ]
}

@test "mb_detect_host: OPENCODE env → opencode" {
  export OPENCODE="1"
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
}

@test "mb_detect_host: CODEX_SANDBOX env → codex" {
  export CODEX_SANDBOX="seatbelt"
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}

@test "mb_detect_host: CURSOR_TRACE_ID env → cursor" {
  export CURSOR_TRACE_ID="abc"
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ "$output" = "cursor" ]
}

@test "mb_detect_host: MB_AGENT beats env signature" {
  export MB_AGENT="codex"
  export CLAUDECODE="1"
  run mb_detect_host
  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}

# ═══ mb_pipeline_dir ═══

@test "mb_pipeline_dir: explicit bank → <bank>/pipelines" {
  run mb_pipeline_dir "/some/bank"
  [ "$status" -eq 0 ]
  [ "$output" = "/some/bank/pipelines" ]
}

@test "mb_pipeline_dir: no arg resolves bank then appends pipelines" {
  cd "$TMPDIR"
  mkdir -p .memory-bank
  run mb_pipeline_dir
  [ "$status" -eq 0 ]
  [ "$output" = ".memory-bank/pipelines" ]
}

# ═══ mb_pipeline_meta ═══

_write_pipeline() {
  # $1 = path, $2... = body lines
  local path="$1"; shift
  printf '%s\n' "$@" > "$path"
}

@test "mb_pipeline_meta: reads pipeline_name" {
  local f="$TMPDIR/p.yaml"
  _write_pipeline "$f" 'pipeline_name: claude-fast' 'default: false' 'version: "1"'
  run mb_pipeline_meta "$f" pipeline_name
  [ "$status" -eq 0 ]
  [ "$output" = "claude-fast" ]
}

@test "mb_pipeline_meta: missing pipeline_name → empty" {
  local f="$TMPDIR/p.yaml"
  _write_pipeline "$f" 'version: "1"' 'default: true'
  run mb_pipeline_meta "$f" pipeline_name
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mb_pipeline_meta: default true normalized" {
  local f="$TMPDIR/p.yaml"
  _write_pipeline "$f" 'pipeline_name: solo' 'default: true'
  run mb_pipeline_meta "$f" default
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "mb_pipeline_meta: default absent → false" {
  local f="$TMPDIR/p.yaml"
  _write_pipeline "$f" 'pipeline_name: solo'
  run mb_pipeline_meta "$f" default
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "mb_pipeline_meta: agents inline list → space separated" {
  local f="$TMPDIR/p.yaml"
  _write_pipeline "$f" 'pipeline_name: pi-gov' 'agents: [pi, opencode]'
  run mb_pipeline_meta "$f" agents
  [ "$status" -eq 0 ]
  [ "$output" = "pi opencode" ]
}

@test "mb_pipeline_meta: agents block list → space separated" {
  local f="$TMPDIR/p.yaml"
  _write_pipeline "$f" 'pipeline_name: pi-gov' 'agents:' '  - pi' '  - opencode'
  run mb_pipeline_meta "$f" agents
  [ "$status" -eq 0 ]
  [ "$output" = "pi opencode" ]
}

@test "mb_pipeline_meta: agents absent → empty" {
  local f="$TMPDIR/p.yaml"
  _write_pipeline "$f" 'pipeline_name: solo'
  run mb_pipeline_meta "$f" agents
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mb_pipeline_meta: parses without PyYAML (fallback)" {
  local f="$TMPDIR/p.yaml"
  _write_pipeline "$f" 'pipeline_name: claude-fast' 'default: true' 'agents: [claude-code]'
  local shim="$TMPDIR/shim"; mkdir -p "$shim"
  printf "raise ModuleNotFoundError('yaml')\n" > "$shim/yaml.py"
  PYTHONPATH="$shim" run mb_pipeline_meta "$f" pipeline_name
  [ "$status" -eq 0 ]
  [ "$output" = "claude-fast" ]
  PYTHONPATH="$shim" run mb_pipeline_meta "$f" default
  [ "$output" = "true" ]
  PYTHONPATH="$shim" run mb_pipeline_meta "$f" agents
  [ "$output" = "claude-code" ]
}
