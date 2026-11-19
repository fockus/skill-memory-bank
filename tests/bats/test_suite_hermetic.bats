#!/usr/bin/env bats
# The suite must never reach the repo it runs from. A linked worktree's pre-commit
# hook exports an absolute GIT_DIR; a suite run inside it (the closure gate) once
# rewrote the shared .git/hooks and set core.bare=true for every checkout.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=lib/repo_guard.bash
  source "$REPO_ROOT/tests/bats/lib/repo_guard.bash"
  S="$BATS_TEST_TMPDIR/scratch"
  git init -q "$S/repo"
  git -C "$S/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$S/repo" worktree add -q "$S/wt" 2>/dev/null
}

@test "hermetic: the guard fingerprint covers a worktree's shared hooks and core config" {
  local before after
  before="$(mb_repo_fingerprint "$S/wt")"
  git -C "$S/repo" config core.bare true
  after="$(mb_repo_fingerprint "$S/wt")"
  [ "$before" != "$after" ] || { echo "core.bare flip not seen"; false; }
  git -C "$S/repo" config core.bare false
  printf '#!/bin/sh\n' > "$S/repo/.git/hooks/pre-commit"
  after="$(mb_repo_fingerprint "$S/wt")"
  [ "$before" != "$after" ] || { echo "hook write not seen"; false; }
}

@test "hermetic: a suite run under a hook's GIT_DIR cannot touch the committing repo" {
  local inner="$BATS_TEST_TMPDIR/inner" gitdir
  gitdir="$(git -C "$S/wt" rev-parse --absolute-git-dir)"
  mkdir -p "$inner"
  cat > "$inner/test_inner.bats" <<'EOF'
@test "inner: initialise a private repo" { git init -q "$BATS_TEST_TMPDIR/private"; }
EOF
  run env GIT_DIR="$gitdir" GIT_INDEX_FILE="$gitdir/index" \
    bats --setup-suite-file "$REPO_ROOT/tests/bats/setup_suite.bash" "$inner/test_inner.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git -C "$S/repo" config core.bare)" = false ]
}

@test "hermetic: a test never inherits the runner's XDG base dirs" {
  # GitHub runners export XDG_CONFIG_HOME=/home/runner/.config: tests that set HOME
  # still installed into that one real directory and collided under --jobs.
  local inner="$BATS_TEST_TMPDIR/inner"
  mkdir -p "$inner"
  cat > "$inner/test_inner.bats" <<'INNER'
@test "inner: XDG base dirs follow HOME" {
  [ -z "${XDG_CONFIG_HOME:-}" ] && [ -z "${XDG_DATA_HOME:-}" ] && [ -z "${XDG_STATE_HOME:-}" ] && [ -z "${XDG_CACHE_HOME:-}" ]
}
INNER
  run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/real/config" XDG_DATA_HOME="$BATS_TEST_TMPDIR/real/data" \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/real/state" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/real/cache" \
    bats --setup-suite-file "$REPO_ROOT/tests/bats/setup_suite.bash" "$inner/test_inner.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
