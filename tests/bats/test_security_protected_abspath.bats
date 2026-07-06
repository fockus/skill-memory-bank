#!/usr/bin/env bats
# Security: protected-path check must match absolute repo-relative paths.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME:-$(dirname "$BATS_TEST_FILENAME")}/../.." && pwd)"
  CHECKER="$REPO_ROOT/scripts/mb-work-protected-check.sh"
  SANDBOX="$(mktemp -d)"
  REPO="$SANDBOX/repo"
  mkdir -p "$REPO/ci" "$REPO/.github/workflows" "$REPO/.memory-bank"
  touch "$REPO/ci/deploy.sh" "$REPO/.github/workflows/release.yml"
  cat > "$REPO/.memory-bank/pipeline.yaml" <<'YAML'
protected_paths:
  - "ci/**"
  - ".github/workflows/**"
  - ".env"
YAML
  git -C "$REPO" init -q
  git -C "$REPO" config user.email "t@test"
  git -C "$REPO" config user.name "t"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m init
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

@test "protected_check: matches absolute ci path" {
  run bash "$CHECKER" "$REPO/ci/deploy.sh" --mb "$REPO/.memory-bank"
  [ "$status" -eq 1 ]
}

@test "protected_check: matches absolute github workflow" {
  run bash "$CHECKER" "$REPO/.github/workflows/release.yml" --mb "$REPO/.memory-bank"
  [ "$status" -eq 1 ]
}

@test "protected_check: still matches basename env" {
  run bash "$CHECKER" "/anywhere/.env" --mb "$REPO/.memory-bank"
  [ "$status" -eq 1 ]
}

@test "protected_check: allows unprotected path" {
  mkdir -p "$REPO/src"
  touch "$REPO/src/app.py"
  run bash "$CHECKER" "$REPO/src/app.py" --mb "$REPO/.memory-bank"
  [ "$status" -eq 0 ]
}
