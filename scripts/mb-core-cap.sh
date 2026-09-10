#!/usr/bin/env bash
# mb-core-cap.sh — hard line caps for the two core registries (AGR-043).
#
# Usage:
#   mb-core-cap.sh check [--mb <path>] [--json]
#   mb-core-cap.sh fix   [--mb <path>] [--json]
#
# `status.md` holds only the CURRENT state and `checklist.md` only the plans in
# flight; everything else lives in `progress.md`. That is a contract, so it is
# an exit code — not a sentence in a file header.
#
#   check  Report `status_lines=N status_cap=M checklist_lines=N checklist_cap=M
#          over=<csv|none>`. Exit 0 within caps, 1 over.
#   fix    Deterministic repair: mb-status-rotate.sh --apply (dated sections →
#          progress.md) + mb-checklist-prune.sh --apply (closed plans →
#          progress.md, v2 compaction), then re-check.
#
# Caps: MB_STATUS_MAX_LINES / MB_CHECKLIST_MAX_LINES (env)
#       → `<mb>/.mb-config` `status_max_lines=` / `checklist_max_lines=`
#       → 60 / 100.
#
# Kill-switch: MB_CORE_CAP=off (env) or `core_cap=off` in `<mb>/.mb-config`
# disables both subcommands entirely (exit 0, nothing written).
#
# Exit codes:
#   0  within caps (or kill-switched)
#   1  still over cap — dispatch MB Manager `action: actualize --strict`
#   2  usage / environment error (missing bank, missing python3, missing helper)
#   3  `fix` only: the prune refused because live plans do not fit. Passed
#      through from mb-checklist-prune.sh unflattened — AGR-043 makes this an
#      owner decision (pause or close plans), never a trim of live work.
#
# Nothing is ever deleted: every block that leaves a core file is verified in
# progress.md first by the rotate/prune helpers this script composes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

ACTION=""
MB_ARG=""
JSON="0"

while [ $# -gt 0 ]; do
  case "$1" in
    check|fix) ACTION="$1"; shift ;;
    --mb)      MB_ARG="${2:-}"; shift 2 ;;
    --mb=*)    MB_ARG="${1#--mb=}"; shift ;;
    --json)    JSON="1"; shift ;;
    --help|-h)
      sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "[error] unknown argument: $1" >&2
      echo "Usage: mb-core-cap.sh check|fix [--mb <path>] [--json]" >&2
      exit 2 ;;
  esac
done

if [ -z "$ACTION" ]; then
  echo "[error] expected a subcommand: check | fix" >&2
  exit 2
fi

MB_PATH_RAW=$(mb_resolve_path "$MB_ARG")
if [ ! -d "$MB_PATH_RAW" ]; then
  echo "[error] .memory-bank not found at: $MB_PATH_RAW" >&2
  exit 2
fi
MB_PATH=$(cd "$MB_PATH_RAW" && pwd)

# Kill-switch: env wins, then the per-bank `.mb-config` toggle.
_cap_disabled() {
  case "${MB_CORE_CAP:-on}" in
    off|OFF|0|false|FALSE|no|NO) return 0 ;;
  esac
  if [ -f "$MB_PATH/.mb-config" ] && [ ! -L "$MB_PATH/.mb-config" ]; then
    local raw
    raw=$(grep -E '^core_cap=' "$MB_PATH/.mb-config" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    case "$raw" in off|OFF|0|false|FALSE|no|NO) return 0 ;; esac
  fi
  return 1
}
_cap_disabled && exit 0

if ! command -v python3 >/dev/null 2>&1; then
  echo "[error] python3 not found — cannot count core-file lines" >&2
  exit 2
fi

# Counting + cap resolution live in python (line arithmetic and precedence in
# bash is where these scripts historically go wrong); bash stays the CLI.
_report() {
  MB_CC_PATH="$MB_PATH" MB_CC_JSON="$JSON" python3 - <<'PY'
import json
import os

mb = os.environ["MB_CC_PATH"]
as_json = os.environ.get("MB_CC_JSON") == "1"

config = {}
cfg_path = os.path.join(mb, ".mb-config")
if os.path.isfile(cfg_path) and not os.path.islink(cfg_path):
    try:
        for raw in open(cfg_path, encoding="utf-8", errors="replace"):
            if "=" in raw and not raw.lstrip().startswith("#"):
                key, _, value = raw.partition("=")
                config[key.strip()] = value.strip()
    except OSError:
        config = {}


def cap(env_name: str, config_key: str, default: int) -> int:
    for raw in (os.environ.get(env_name), config.get(config_key)):
        if raw and raw.isdigit():
            return int(raw)
    return default


def lines(name: str) -> int:
    path = os.path.join(mb, name)
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return len(fh.read().splitlines())
    except OSError:
        return 0


data = {
    "status_lines": lines("status.md"),
    "status_cap": cap("MB_STATUS_MAX_LINES", "status_max_lines", 60),
    "checklist_lines": lines("checklist.md"),
    "checklist_cap": cap("MB_CHECKLIST_MAX_LINES", "checklist_max_lines", 100),
}
over = [n for n in ("status", "checklist") if data[f"{n}_lines"] > data[f"{n}_cap"]]
data["over"] = over

if as_json:
    print(json.dumps(data))
else:
    print(
        "status_lines=%(status_lines)d status_cap=%(status_cap)d "
        "checklist_lines=%(checklist_lines)d checklist_cap=%(checklist_cap)d "
        "over=%(over)s" % dict(data, over=",".join(over) or "none")
    )

raise SystemExit(1 if over else 0)
PY
}

# `_lib.sh` turns on strict mode, so a non-zero `_report` would abort the script
# before its exit code could be read — capture it explicitly instead.
if [ "$ACTION" = "check" ]; then
  rc=0
  _report || rc=$?
  exit "$rc"
fi

# ── fix ────────────────────────────────────────────────────────────────────
ROTATE="$SCRIPT_DIR/mb-status-rotate.sh"
PRUNE="$SCRIPT_DIR/mb-checklist-prune.sh"
for helper in "$ROTATE" "$PRUNE"; do
  if [ ! -f "$helper" ]; then
    echo "[error] missing helper: $helper" >&2
    exit 2
  fi
done

bash "$ROTATE" --apply --mb "$MB_PATH" || echo "[warn] status rotation reported a problem — status.md left as is" >&2

prune_rc=0
bash "$PRUNE" --apply --mb "$MB_PATH" || prune_rc=$?

rc=0
_report || rc=$?

if [ "$prune_rc" -eq 3 ]; then
  # Not a generic failure: live plans do not fit, and live work is never cut.
  echo "[core-cap] checklist.md is over cap with live plans — pause or close plans (owner decision, AGR-043)" >&2
  exit 3
fi

if [ "$rc" -ne 0 ]; then
  echo "[core-cap] still over cap — dispatch MB Manager \`action: actualize --strict\`, then rerun \`mb-core-cap.sh check\`" >&2
  exit 1
fi
exit 0
