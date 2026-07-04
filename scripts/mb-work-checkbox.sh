#!/usr/bin/env bash
# mb-work-checkbox.sh — deterministic DoD-checkbox flip, gated on work-state.
#
# Usage:
#   mb-work-checkbox.sh flip <plan-or-spec> <item_no> [--mb <path>] [--run-id ID]
#
# Flips `- ⬜` → `- ✅` and `- [ ]` → `- [x]` (both checkbox dialects
# `mb-work-plan.sh` recognises) but ONLY inside the requested item's marker
# block (`<!-- mb-stage:N -->` / `<!-- mb-task:N -->` up to the next marker
# or EOF), and ONLY when the resolved work-state file says the gate already
# passed for that exact item (`phase == "done"` AND `item_no` matches).
# Everywhere else this is a fail-safe refusal — never a blind flip.
#
# `--run-id` (fallback `$MB_WORK_RUN_ID`) selects WHICH state file is
# consulted, via scripts/mb-work-slots.sh's `mbw_state_slot`: under
# `MB_WORK_PARALLEL` with a non-empty run_id it reads
# `<bank>/.work-state/<run_id>.json` (a run only ever flips its own item);
# otherwise (parallel off, or no run_id) it reads the legacy singleton
# `<bank>/.work-state.json`, byte-identical to pre-I-094 behaviour.
#
# Exit codes:
#   0  flipped (or already flipped — idempotent no-op)
#   1  refused: no active work-state, or phase != done, or item_no mismatch
#   2  usage error: bad args, file not found, item_no absent from the file
#
# Design contract: atomic write (mktemp → mv), bash 3.2 + 5.x, set -eu.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

usage() {
	sed -n '2,24p' "$0" >&2
}

cmd_flip() {
	local mb_arg="" run_id=""
	local pos=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--mb)
			mb_arg="${2:-}"
			shift 2
			;;
		--mb=*)
			mb_arg="${1#--mb=}"
			shift
			;;
		--run-id)
			run_id="${2:-}"
			shift 2
			;;
		--run-id=*)
			run_id="${1#--run-id=}"
			shift
			;;
		*)
			pos+=("$1")
			shift
			;;
		esac
	done
	[ -z "$run_id" ] && run_id="${MB_WORK_RUN_ID:-}"

	local file="${pos[0]:-}"
	local item_no="${pos[1]:-}"
	if [ -z "$file" ] || [ -z "$item_no" ]; then
		echo "[checkbox] flip <plan-or-spec> <item_no> required" >&2
		exit 2
	fi
	case "$item_no" in
	'' | *[!0-9]*)
		echo "[checkbox] item_no must be a positive integer, got '$item_no'" >&2
		exit 2
		;;
	esac
	if [ ! -f "$file" ]; then
		echo "[checkbox] file not found: $file" >&2
		exit 2
	fi

	local bank
	bank=$(mb_resolve_path "$mb_arg")
	local state
	state=$(mbw_state_slot "$bank" "$run_id")
	if [ ! -f "$state" ]; then
		echo "[checkbox] refused: no active work-state (never a blind flip)" >&2
		exit 1
	fi

	local gate
	gate=$(STATE="$state" ITEM_NO="$item_no" python3 - <<'PY'
import json
import os

try:
    with open(os.environ["STATE"], encoding="utf-8") as fh:
        data = json.loads(fh.read())
except Exception:
    print("refuse")
    raise SystemExit(0)

target = int(os.environ["ITEM_NO"])
try:
    state_item = int(data.get("item_no"))
except (TypeError, ValueError):
    state_item = None

if data.get("phase") == "done" and state_item == target:
    print("ok")
else:
    print("refuse")
PY
	)
	if [ "$gate" != "ok" ]; then
		echo "[checkbox] refused: work-state phase != done or item_no mismatch for item $item_no" >&2
		exit 1
	fi

	FILE="$file" ITEM_NO="$item_no" python3 - <<'PY'
import os
import re
import sys
import tempfile

path = os.environ["FILE"]
item_no = int(os.environ["ITEM_NO"])

with open(path, encoding="utf-8") as fh:
    text = fh.read()

marker_re = re.compile(r"<!--\s*mb-(?:stage|task):(\d+)\s*-->")
matches = list(marker_re.finditer(text))
if not matches:
    sys.stderr.write(f"[checkbox] no mb-stage/mb-task markers in {path}\n")
    sys.exit(2)

target_idx = None
for i, m in enumerate(matches):
    if int(m.group(1)) == item_no:
        target_idx = i
        break

if target_idx is None:
    sys.stderr.write(f"[checkbox] item {item_no} not found in {path}\n")
    sys.exit(2)

block_start = matches[target_idx].end()
block_end = matches[target_idx + 1].start() if target_idx + 1 < len(matches) else len(text)

block = text[block_start:block_end]
new_block = re.sub(r"^(\s*-\s+)⬜", r"\1✅", block, flags=re.M)
new_block = re.sub(r"^(\s*-\s+)\[ \]", r"\1[x]", new_block, flags=re.M)

if new_block == block:
    # Already flipped (or nothing to flip) — idempotent no-op.
    sys.exit(0)

new_text = text[:block_start] + new_block + text[block_end:]

dir_name = os.path.dirname(os.path.abspath(path)) or "."
fd, tmp_path = tempfile.mkstemp(dir=dir_name, prefix=".mb-work-checkbox-")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(new_text)
    os.replace(tmp_path, path)
except BaseException:
    os.unlink(tmp_path)
    raise
PY
	echo "[checkbox] flipped item $item_no in $file"
}

main() {
	if [ "$#" -lt 1 ]; then
		usage
		exit 2
	fi
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	flip)
		shift
		cmd_flip "$@"
		;;
	*)
		echo "[checkbox] unknown subcommand '$1'" >&2
		usage
		exit 2
		;;
	esac
}

main "$@"
