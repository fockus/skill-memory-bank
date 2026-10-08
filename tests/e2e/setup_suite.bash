# shellcheck shell=bash
# Suite-wide repo hygiene — see ../bats/lib/repo_guard.bash.
# shellcheck source=../bats/lib/repo_guard.bash
source "$(dirname "${BASH_SOURCE[0]}")/../bats/lib/repo_guard.bash"

setup_suite() { mb_repo_guard_setup; }
teardown_suite() { mb_repo_guard_check; }
