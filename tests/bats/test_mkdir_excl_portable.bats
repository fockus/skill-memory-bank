#!/usr/bin/env bats
# Locks must not trust the `mkdir` binary to be exclusive: uutils coreutils 0.10
# (Ubuntu 26.04's default) told several concurrent callers that THEY created the
# same directory, so two writers entered one critical section (duplicate BUG ids).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # A `mkdir` that, like uutils on a lost race, reports success for an existing dir.
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  real="$(command -v mkdir)"
  printf '#!/bin/sh\nfor a; do last="$a"; done\n[ -d "$last" ] && exit 0\nexec %s "$@"\n' "$real" > "$STUB/mkdir"
  chmod +x "$STUB/mkdir"
}

@test "mkdir-excl: refuses an existing directory even when the mkdir binary claims success" {
  local dir="$BATS_TEST_TMPDIR/gate"
  run env PATH="$STUB:$PATH" bash -c ". '$REPO_ROOT/scripts/_lib.sh'; mb_mkdir_excl '$dir' && mb_mkdir_excl '$dir'"
  [ "$status" -ne 0 ]
  [ -d "$dir" ]
}

@test "mkdir-excl: a held mb_lock is not granted to a second caller under a lying mkdir" {
  local lock="$BATS_TEST_TMPDIR/l.lock"
  run env PATH="$STUB:$PATH" bash -c ". '$REPO_ROOT/scripts/_lib.sh'
    mb_lock_acquire '$lock' 1 3600 >/dev/null || exit 9
    mb_lock_acquire '$lock' 1 3600"
  [ "$status" -eq 1 ]   # lock_timeout, never a second grant
}

@test "mkdir-excl: no lock in scripts/ or hooks/ gates on the mkdir binary" {
  run grep -rnE '(if|until|while)( !)? mkdir "' "$REPO_ROOT/scripts" "$REPO_ROOT/hooks" --include='*.sh'
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "mkdir-excl: a lock released between a lost mkdir and the check is retried, not called corrupt" {
  # The winner can release in that window; the vanished path is not a corrupt lock.
  local lock="$BATS_TEST_TMPDIR/race.lock"
  run bash -c ". '$REPO_ROOT/scripts/_lib.sh'
    eval \"real_\$(declare -f mb_mkdir_excl)\"
    lost=0
    mb_mkdir_excl() { if [ \$lost = 0 ] && [ \"\$1\" = '$lock' ]; then lost=1; return 1; fi; real_mb_mkdir_excl \"\$1\"; }
    mb_lock_acquire '$lock' 5 3600"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
