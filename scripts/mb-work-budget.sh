#!/usr/bin/env bash
# mb-work-budget.sh — token budget tracker for /mb work --budget.
#
# Subcommands (each takes [--mb <path>] for bank override):
#   init <total_tokens> [--warn-at PCT] [--stop-at PCT]   start tracking
#   add <tokens>                                          increment spent
#   status                                                show current state
#   check                                                 0=ok, 1=warn, 2=stop
#   clear                                                 remove state
#
# State file: <bank>/.work-budget.json
#   { total, spent, warn_at_percent, stop_at_percent, started }
#
# Defaults are read from pipeline.yaml:budget.{warn_at_percent, stop_at_percent}.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,16p' "$0" >&2
}

resolve_pipeline_defaults() {
  # $1 = mb_arg → echoes "warn stop"
  local mb_arg="$1"
  local pipeline_path
  pipeline_path=$(bash "$PIPELINE" path "$mb_arg" 2>/dev/null || true)
  if [ -z "$pipeline_path" ]; then
    pipeline_path="$SCRIPT_DIR/../references/pipeline.default.yaml"
  fi
  PIPELINE_YAML="$pipeline_path" python3 - <<'PY'
import os, sys
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    b = cfg.get("budget") or {}
    print(f"{b.get('warn_at_percent', 80)} {b.get('stop_at_percent', 100)}")
except Exception:
    print("80 100")
PY
}

cmd_init() {
  local total=""
  local warn=""
  local stop=""
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --warn-at) warn="${2:-}"; shift 2 ;;
      --warn-at=*) warn="${1#--warn-at=}"; shift ;;
      --stop-at) stop="${2:-}"; shift 2 ;;
      --stop-at=*) stop="${1#--stop-at=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) if [ -z "$total" ]; then total="$1"; fi; shift ;;
    esac
  done
  if [ -z "$total" ]; then
    echo "[budget] init <total_tokens> required" >&2
    exit 2
  fi

  local defaults
  defaults=$(resolve_pipeline_defaults "$mb_arg")
  local def_warn def_stop
  def_warn=$(echo "$defaults" | awk '{print $1}')
  def_stop=$(echo "$defaults" | awk '{print $2}')
  [ -z "$warn" ] && warn="$def_warn"
  [ -z "$stop" ] && stop="$def_stop"

  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state="$bank/.work-budget.json"

  TOTAL="$total" WARN="$warn" STOP="$stop" STATE="$state" python3 - <<'PY'
import json, os, datetime
state = {
    "total": int(os.environ["TOTAL"]),
    "spent": 0,
    "warn_at_percent": int(os.environ["WARN"]),
    "stop_at_percent": int(os.environ["STOP"]),
    "started": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
open(os.environ["STATE"], "w", encoding="utf-8").write(json.dumps(state) + "\n")
PY
  echo "[budget] initialized: total=$total warn=$warn% stop=$stop%"
}

cmd_add() {
  local delta=""
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) if [ -z "$delta" ]; then delta="$1"; fi; shift ;;
    esac
  done
  if [ -z "$delta" ]; then
    echo "[budget] add <tokens> required" >&2
    exit 2
  fi
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state="$bank/.work-budget.json"
  if [ ! -f "$state" ]; then
    echo "[budget] no active budget (run 'init' first)" >&2
    exit 1
  fi
  STATE="$state" DELTA="$delta" python3 - <<'PY'
import json, os
p = os.environ["STATE"]
data = json.loads(open(p, encoding="utf-8").read())
data["spent"] = int(data.get("spent", 0)) + int(os.environ["DELTA"])
open(p, "w", encoding="utf-8").write(json.dumps(data) + "\n")
print(f"[budget] spent={data['spent']}")
PY
}

cmd_status() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) shift ;;
    esac
  done
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state="$bank/.work-budget.json"
  if [ ! -f "$state" ]; then
    echo "[budget] no active budget" >&2
    exit 1
  fi
  STATE="$state" python3 - <<'PY'
import json, os
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
total = int(data["total"])
spent = int(data.get("spent", 0))
pct = (spent / total * 100) if total else 0
print(f"total={total} spent={spent} pct={pct:.1f}% warn={data['warn_at_percent']}% stop={data['stop_at_percent']}%")
PY
}

cmd_check() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) shift ;;
    esac
  done
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state="$bank/.work-budget.json"
  if [ ! -f "$state" ]; then
    echo "[budget] no active budget" >&2
    exit 1
  fi
  STATE="$state" python3 - <<'PY'
import json, os, sys
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
total = int(data["total"])
spent = int(data.get("spent", 0))
warn = int(data["warn_at_percent"])
stop = int(data["stop_at_percent"])
if total <= 0:
    sys.exit(0)
pct = spent * 100 / total
if pct >= stop:
    sys.stderr.write(f"[budget] STOP: spent {spent}/{total} ({pct:.1f}% >= {stop}%)\n")
    sys.exit(2)
if pct >= warn:
    sys.stderr.write(f"[budget] WARN: spent {spent}/{total} ({pct:.1f}% >= {warn}%)\n")
    sys.exit(1)
sys.exit(0)
PY
}

cmd_clear() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) shift ;;
    esac
  done
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state="$bank/.work-budget.json"
  rm -f "$state"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage; exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    add) shift; cmd_add "$@" ;;
    status) shift; cmd_status "$@" ;;
    check) shift; cmd_check "$@" ;;
    clear) shift; cmd_clear "$@" ;;
    *) echo "[budget] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
