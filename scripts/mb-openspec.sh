#!/usr/bin/env bash
# mb-openspec.sh — thin dispatcher: import|sync|list|status → mb-openspec.py
#
# OpenSpec → Memory Bank one-way import adapter (spec: openspec-adapter, T4).
# All the domain logic lives in mb-openspec.py (stdlib Python, no `openspec`
# CLI dependency, D-08) — this wrapper only validates the subcommand and
# forwards argv, matching the other thin `mb-*.sh` dispatchers in this repo.
#
# Usage:
#   mb-openspec.sh import <change_dir> [--as <topic>] [--mb <bank>]
#   mb-openspec.sh list   [--all] [--openspec <root>] [--mb <bank>]
#   mb-openspec.sh status <topic> [--mb <bank>]
#   mb-openspec.sh sync   [<topic>] [--mb <bank>]
#
# Exit codes:
#   0 — success
#   1 — domain error (see mb-openspec.py: missing change dir/bank/topic,
#       write-guard violation)
#   2 — usage error (missing/unknown subcommand)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
mb-openspec — OpenSpec -> Memory Bank one-way import adapter

Usage:
  mb-openspec.sh import <change_dir> [--as <topic>] [--mb <bank>]
  mb-openspec.sh list   [--all] [--openspec <root>] [--mb <bank>]
  mb-openspec.sh status <topic> [--mb <bank>]
  mb-openspec.sh sync   [<topic>] [--mb <bank>]
  mb-openspec.sh --help
USAGE
}

main() {
  local sub="${1:-}"
  case "$sub" in
    import|list|status|sync)
      shift
      exec python3 "$SCRIPT_DIR/mb-openspec.py" "$sub" "$@"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    "")
      usage >&2
      exit 2
      ;;
    *)
      echo "mb-openspec: unknown subcommand '$sub'" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
