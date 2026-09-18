#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

main() {
  helper_one
  out="$(helper_two)"
  only_in_unsourced
  bash "$SCRIPT_DIR/other.sh"
  cat <<'EOF'
not_a_function() {
  echo heredoc body
}
EOF
  printf '%s\n' "$out"
}

main "$@"
