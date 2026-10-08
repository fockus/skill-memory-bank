# shellcheck shell=bash
# Suite-wide repo hygiene — see lib/repo_guard.bash.
# shellcheck source=lib/repo_guard.bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/repo_guard.bash"

setup_suite() { mb_repo_guard_setup; }
teardown_suite() { mb_repo_guard_check; }
