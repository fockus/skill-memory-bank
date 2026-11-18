#!/usr/bin/env bash
# mb-openspec.sh — thin dispatcher: import|sync|list|status|export → mb-openspec.py
#
# OpenSpec <-> Memory Bank round-trip adapter (spec: openspec-adapter, T4, AGR-105).
# All the domain logic lives in mb-openspec.py (stdlib Python, no `openspec`
# CLI dependency, D-08) — this wrapper only validates the subcommand and
# forwards argv, matching the other thin `mb-*.sh` dispatchers in this repo.
#
# Usage:
#   mb-openspec.sh import <change_dir> [--as <topic>] [--mb <bank>] [--normalize]
#   mb-openspec.sh list   [--all] [--openspec <root>] [--mb <bank>]
#   mb-openspec.sh status <topic> [--mb <bank>]
#   mb-openspec.sh sync   [<topic>] [--take openspec|bank] [--mb <bank>] [--normalize]
#   mb-openspec.sh export <topic> [--write] [--allow-delete] [--mb <bank>]
#   mb-openspec.sh export <topic> --new [--id <id>] [--cap <cap>] [--openspec <root>] [--write]
#
# Exit codes:
#   0 — success
#   1 — domain error (see mb-openspec.py: missing change dir/bank/topic,
#       write-guard violation, sync conflict, export refused because
#       OpenSpec changed since the last sync)
#   2 — usage error (missing/unknown subcommand)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
mb-openspec — OpenSpec <-> Memory Bank round-trip adapter

Usage:
  mb-openspec.sh import <change_dir> [--as <topic>] [--mb <bank>] [--normalize]
  mb-openspec.sh list   [--all] [--openspec <root>] [--mb <bank>]
  mb-openspec.sh status <topic> [--mb <bank>]
  mb-openspec.sh sync   [<topic>] [--take openspec|bank] [--mb <bank>] [--normalize]
  mb-openspec.sh export <topic> [--write] [--allow-delete] [--mb <bank>]
  mb-openspec.sh export <topic> --new [--id <id>] [--cap <cap>] [--openspec <root>] [--write]
  mb-openspec.sh --help

--normalize fills LLM text slots (EARS rewrite, missing scenario, Covers),
cached by source-requirement hash; omit it for the deterministic-only path.
sync merges per unit and writes only the bank; on a conflict nothing is
written until `--take openspec|bank` or matching edits resolve it.
export prints a diff of the bank's changes; only --write touches OpenSpec.
USAGE
}

main() {
  local sub="${1:-}"
  case "$sub" in
    import|list|status|sync|export)
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
