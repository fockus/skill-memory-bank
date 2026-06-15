#!/usr/bin/env bash
# mb-progress-chain.sh — append-only physical integrity for progress.md.
#
# Maintains a hash chain of the last N=20 `## YYYY-MM-DD` entries in
# `index.json:progress_chain` (design specs/handoff-v2/design.md §6).
#
# Usage:
#   mb-progress-chain.sh --rebuild-tail [mb_path]   # recompute + write chain (idempotent)
#   mb-progress-chain.sh --verify       [mb_path]   # recompute + compare; exit 2 on tamper
#
# `mb_path` defaults to the resolved Memory Bank (mb_resolve_path).
#
# Exit codes:
#   0  success (rebuild done, or verify passed)
#   2  verify failed (tamper/deletion/malformed index) OR bad usage
#
# Output (stdout): a single structured JSON object.
# - rebuild: {"ok": true, "progress_chain": {...}}
# - verify : {"ok": true|false, "error": ..., "mismatches": [...], "missing": [...]}

set -euo pipefail

# ── Symlink-safe self-location (Finding #4) ─────────────────────────────────
# We MUST resolve the physical script location BEFORE sourcing _lib.sh, because
# _lib.sh may not exist in the logical dirname($0) when this script is reached
# through a symlink (e.g. a project that symlinks the skill's scripts/ dir).
# We cannot use mb_resolve_real_path here — it lives in the _lib.sh we have yet
# to source. Use a portable two-step: readlink -f (GNU/Linux) with a python3
# fallback (macOS, where readlink has no -f).
_self_realpath() {
  local target="$1"
  if command -v readlink >/dev/null 2>&1 && readlink -f "$target" >/dev/null 2>&1; then
    readlink -f "$target"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$target"
  else
    # Fallback: logical path (works when not a symlink, degrades gracefully).
    cd "$(dirname "$target")" && pwd -P
  fi
}

SCRIPT_SELF="$(_self_realpath "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SELF")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Now source _lib.sh from the RESOLVED physical directory.
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: mb-progress-chain.sh (--rebuild-tail | --verify) [mb_path]

  --rebuild-tail   Recompute the last N=20 progress.md entries and write
                   index.json:progress_chain (idempotent, read-modify-write).
                   If index.json is malformed a .bak is written before overwrite.
  --verify         Recompute and compare against the recorded chain.
                   Exit 2 on any mismatch, deletion, ambiguity, or malformed index.
EOF
}

MODE="${1:-}"
case "$MODE" in
  --rebuild-tail | --verify) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

MB_PATH="$(mb_resolve_path "${2:-}")"

# Delegate hashing/JSON to the Python module (3.11/3.12-safe, stdlib only).
PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}" \
  python3 -m memory_bank_skill.progress_chain "$MODE" "$MB_PATH"
