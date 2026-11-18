# shellcheck shell=bash
# Suite-wide repo hygiene — see lib/repo_guard.bash.
# shellcheck source=lib/repo_guard.bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/repo_guard.bash"

# stdin as in CI: an agent's background shell keeps it open, so a stray `cat`
# in a test would block the whole run forever instead of reading EOF.
setup_suite() { exec </dev/null; mb_python_direct; mb_repo_guard_setup; }
teardown_suite() { mb_repo_guard_check; }
