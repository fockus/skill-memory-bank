#!/usr/bin/env bats
# Tests for scripts/mb-diff-scope.sh — the L5 diff-scope backstop (ADR-4).
#
# Contract (REQ-DF-042, ADR-3):
#   - emits {"name":"diff_scope","ok":true|false|null,"findings":[...]}
#   - ALWAYS exits 0 — pass/fail/skip carried ONLY by `ok`.
#   - Compares `git diff --name-only` against an ALLOWED glob set provided via
#     --allow "<glob[,glob...]>" (or --scope-file <path>, one glob per line).
#   - ok=true   when every changed file matches an allowed glob.
#   - ok=false  + findings listing each out-of-scope changed file.
#   - ok=null   when no allowed scope is provided (skip — nothing to enforce).
#
# Tests build an isolated throwaway git repo so `git diff` is deterministic and
# never touches the real repo's working tree.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-diff-scope.sh"
  command -v jq  >/dev/null || skip "jq required"
  command -v git >/dev/null || skip "git required"
  GIT_REPO="$(mktemp -d)"
  git -C "$GIT_REPO" init -q
  git -C "$GIT_REPO" config user.email t@t.t
  git -C "$GIT_REPO" config user.name t
  printf 'base\n' >"$GIT_REPO/base.txt"
  git -C "$GIT_REPO" add -A
  git -C "$GIT_REPO" commit -qm init
}

teardown() {
  [ -n "${GIT_REPO:-}" ] && rm -rf "$GIT_REPO"
}

json_of() {
  printf '%s\n' "$1" | grep '^{' | tail -n1
}

# Stage a tracked change to a path inside the throwaway repo.
change() {
  local rel="$1"
  mkdir -p "$GIT_REPO/$(dirname "$rel")"
  printf 'changed\n' >>"$GIT_REPO/$rel"
  git -C "$GIT_REPO" add -A
}

@test "diff_scope: script exists" {
  [ -f "$RUN" ]
}

@test "diff_scope: --help exits 0 and mentions --allow" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--allow"* ]]
}

# ---- PASS case --------------------------------------------------------------

@test "diff_scope: all changed files in scope → ok=true, exit 0" {
  change "src/app.py"
  run bash "$RUN" --repo "$GIT_REPO" --allow "src/*"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.name == "diff_scope"'
  echo "$j" | jq -e '.ok == true'
  echo "$j" | jq -e '.findings | length == 0'
}

@test "diff_scope: multiple allowed globs (csv) all match → ok=true" {
  change "src/app.py"
  change "docs/readme.md"
  run bash "$RUN" --repo "$GIT_REPO" --allow "src/*,docs/*"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}

# ---- FAIL case --------------------------------------------------------------

@test "diff_scope: out-of-scope file → ok=false, exit 0, finding names it" {
  change "src/app.py"
  change "infra/secrets.tf"
  run bash "$RUN" --repo "$GIT_REPO" --allow "src/*"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.ok == false'
  echo "$j" | jq -e '.findings | length == 1'
  echo "$j" | jq -e '[.findings[] | test("infra/secrets.tf")] | any'
}

@test "diff_scope: FAIL case STILL exits 0 (ADR-3 — no fail-loud in runner)" {
  change "out/of/scope.txt"
  run bash "$RUN" --repo "$GIT_REPO" --allow "src/*"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == false'
}

# ---- scope file variant -----------------------------------------------------

@test "diff_scope: --scope-file in-scope change → ok=true" {
  change "src/app.py"
  # Scope file lives OUTSIDE the repo so it is not itself a tracked change.
  local scope="$BATS_TEST_TMPDIR/scope.txt"
  printf '# allowed globs\nsrc/*\ndocs/*\n' >"$scope"
  run bash "$RUN" --repo "$GIT_REPO" --scope-file "$scope"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}

@test "diff_scope: --scope-file out-of-scope change → ok=false, names the file" {
  change "infra/secrets.tf"
  local scope="$BATS_TEST_TMPDIR/scope.txt"
  printf 'src/*\ndocs/*\n' >"$scope"
  run bash "$RUN" --repo "$GIT_REPO" --scope-file "$scope"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.ok == false'
  echo "$j" | jq -e '[.findings[] | test("infra/secrets.tf")] | any'
}

# ---- NULL / skip case -------------------------------------------------------

@test "diff_scope: no allowed scope provided → ok=null, exit 0" {
  change "src/app.py"
  run bash "$RUN" --repo "$GIT_REPO"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == null'
}

@test "diff_scope: no changed files but scope given → ok=true (vacuously in scope)" {
  run bash "$RUN" --repo "$GIT_REPO" --allow "src/*"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}
