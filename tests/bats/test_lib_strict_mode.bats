#!/usr/bin/env bats
# Stage 5 — `scripts/_lib.sh` must enable strict mode at the top of the file.
# Sourcing _lib.sh into a fresh bash shell should activate `set -euo pipefail`,
# so any consumer that forgot it still inherits the safety guarantees.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/scripts/_lib.sh"
  [ -f "$LIB" ] || skip "scripts/_lib.sh missing"
}

@test "_lib.sh declares 'set -euo pipefail' near the top" {
  # Allow it anywhere in the first 12 lines so a future header-comment add
  # doesn't break the test.
  run head -n 12 "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"set -euo pipefail"* ]]
}

@test "_lib.sh propagates 'set -u' to the sourcing shell" {
  # Subshell so a failure does not kill bats. Sourcing _lib.sh should enable
  # `-u`; reading $UNDEFINED_VAR_xyz must then exit non-zero.
  run bash -c "source '$LIB' && echo \"\${UNDEFINED_VAR_xyz}\""
  [ "$status" -ne 0 ]
}

@test "_lib.sh propagates 'pipefail' to the sourcing shell" {
  # `false | true` returns 0 without pipefail, non-zero with pipefail.
  run bash -c "source '$LIB' && false | true"
  [ "$status" -ne 0 ]
}

@test "_lib.sh propagates 'set -e' to the sourcing shell" {
  # In `set -e` mode, an unhandled non-zero exit aborts the script before the
  # final `echo`. Output must not contain the sentinel.
  run bash -c "source '$LIB' && false; echo SHOULD_NOT_PRINT"
  [[ "$output" != *"SHOULD_NOT_PRINT"* ]]
}
