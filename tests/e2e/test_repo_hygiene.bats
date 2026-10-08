#!/usr/bin/env bats
# The suite environment (setup_suite.bash → lib/repo_guard.bash) must keep a
# plain `install.sh` / `uninstall.sh` run — no --project-root, no explicit
# MB_MANIFEST_PATH — out of the repo checkout, which is the owner's live skill.

load ../bats/lib/assert
load ../bats/lib/repo_guard

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PYTHONUSERBASE="$(/usr/bin/python3 -m site --user-base)"
  export PYTHONUSERBASE
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  # A git repo, as the repo root was: kilo requires one (git-hooks fallback).
  mkdir -p "$SANDBOX_HOME/project"
  cd "$SANDBOX_HOME/project" && git init -q
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && rm -rf "$SANDBOX_HOME"
}

@test "repo hygiene: default install + uninstall for every client leaves the checkout untouched" {
  local before
  before="$(mb_repo_fingerprint)"

  bash "$REPO_ROOT/install.sh" --non-interactive --language en \
    --clients claude-code,cursor,windsurf,cline,kilo,opencode,pi,codex >/dev/null 2>&1
  [ -f "$MB_MANIFEST_PATH" ]
  [ -f "$PWD/.cursor/rules/memory-bank.mdc" ]   # adapters went to the temp project
  bash "$REPO_ROOT/uninstall.sh" -y >/dev/null 2>&1

  [ "$(mb_repo_fingerprint)" = "$before" ]
}

@test "repo hygiene: the fingerprint catches a rewritten manifest and a new adapter dir" {
  local fake="$SANDBOX_HOME/checkout" before
  mkdir -p "$fake"
  printf '{}' > "$fake/.installed-manifest.json"
  before="$(mb_repo_fingerprint "$fake")"
  assert_substring "$before" ".installed-manifest.json"

  printf '{"files": []}' > "$fake/.installed-manifest.json"
  [ "$(mb_repo_fingerprint "$fake")" != "$before" ]

  refute_substring "$before" ".cursor"
  mkdir -p "$fake/.cursor/rules" && : > "$fake/.cursor/rules/memory-bank.mdc"
  assert_substring "$(mb_repo_fingerprint "$fake")" ".cursor/rules/memory-bank.mdc"
}
