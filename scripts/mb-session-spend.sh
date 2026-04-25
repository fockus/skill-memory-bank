#!/usr/bin/env bash
# mb-session-spend.sh — session token-spend tracker (sprint_context_guard).
#
# Subcommands (all accept [--mb <path>]):
#   init [--soft N] [--hard N]    start tracking (defaults from pipeline.yaml)
#   add <chars>                   increment spent (chars/4 ≈ tokens estimate)
#   status                        show current state
#   check                         exit 0 below soft, 1 at/above soft, 2 at/above hard
#   clear                         remove state file
#
# Mirror of mb-work-budget.sh, but session-scoped (per Claude Code session) and
# using `pipeline.yaml:sprint_context_guard` for thresholds instead of `budget`.
#
# State file: <bank>/.session-spend.json
#   {total_estimate_tokens, soft_warn_tokens, hard_stop_tokens, started}

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,16p' "$0" >&2
}

resolve_pipeline_defaults() {
  local mb_arg="$1"
  local pipeline_path
  pipeline_path=$(bash "$PIPELINE" path "$mb_arg" 2>/dev/null || true)
  if [ -z "$pipeline_path" ]; then
    pipeline_path="$SCRIPT_DIR/../references/pipeline.default.yaml"
  fi
  PIPELINE_YAML="$pipeline_path" python3 - <<'PY'
import os
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    g = cfg.get("sprint_context_guard") or {}
    print(f"{g.get('soft_warn_tokens', 150000)} {g.get('hard_stop_tokens', 190000)}")
except Exception:
    print("150000 190000")
PY
}

cmd_init() {
  local soft=""
  local hard=""
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --soft) soft="${2:-}"; shift 2 ;;
      --soft=*) soft="${1#--soft=}"; shift ;;
      --hard) hard="${2:-}"; shift 2 ;;
      --hard=*) hard="${1#--hard=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) shift ;;
    esac
  done

  local defaults
  defaults=$(resolve_pipeline_defaults "$mb_arg")
  local def_soft def_hard
  def_soft=$(echo "$defaults" | awk '{print $1}')
  def_hard=$(echo "$defaults" | awk '{print $2}')
  [ -z "$soft" ] && soft="$def_soft"
  [ -z "$hard" ] && hard="$def_hard"

  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state="$bank/.session-spend.json"

  SOFT="$soft" HARD="$hard" STATE="$state" python3 - <<'PY'
import datetime, json, os
data = {
    "total_estimate_tokens": 0,
    "soft_warn_tokens": int(os.environ["SOFT"]),
    "hard_stop_tokens": int(os.environ["HARD"]),
    "started": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
open(os.environ["STATE"], "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
  echo "[session-spend] initialized: soft=$soft hard=$hard tokens"
}

cmd_add() {
  local chars=""
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) if [ -z "$chars" ]; then chars="$1"; fi; shift ;;
    esac
  done
  if [ -z "$chars" ]; then
    echo "[session-spend] add <chars> required" >&2
    exit 2
  fi
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state="$bank/.session-spend.json"
  if [ ! -f "$state" ]; then
    echo "[session-spend] no active session (run 'init' first)" >&2
    exit 1
  fi
  STATE="$state" CHARS="$chars" python3 - <<'PY'
import json, os
p = os.environ["STATE"]
data = json.loads(open(p, encoding="utf-8").read())
delta_tokens = int(int(os.environ["CHARS"]) // 4)
data["total_estimate_tokens"] = int(data.get("total_estimate_tokens", 0)) + delta_tokens
open(p, "w", encoding="utf-8").write(json.dumps(data) + "\n")
print(f"[session-spend] +{delta_tokens} → total={data['total_estimate_tokens']}")
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
  local state="$bank/.session-spend.json"
  if [ ! -f "$state" ]; then
    echo "[session-spend] no active session" >&2
    exit 1
  fi
  STATE="$state" python3 - <<'PY'
import json, os
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
total = int(data["total_estimate_tokens"])
soft = int(data["soft_warn_tokens"])
hard = int(data["hard_stop_tokens"])
print(f"total={total} soft={soft} hard={hard}")
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
  local state="$bank/.session-spend.json"
  if [ ! -f "$state" ]; then
    exit 0
  fi
  STATE="$state" python3 - <<'PY'
import json, os, sys
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
total = int(data["total_estimate_tokens"])
soft = int(data["soft_warn_tokens"])
hard = int(data["hard_stop_tokens"])
if total >= hard:
    sys.stderr.write(f"[session-spend] STOP: estimated {total} tokens >= hard {hard}\n")
    sys.exit(2)
if total >= soft:
    sys.stderr.write(f"[session-spend] WARN: estimated {total} tokens >= soft {soft}\n")
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
  local state="$bank/.session-spend.json"
  rm -f "$state"
}

main() {
  if [ "$#" -lt 1 ]; then usage; exit 2; fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    add) shift; cmd_add "$@" ;;
    status) shift; cmd_status "$@" ;;
    check) shift; cmd_check "$@" ;;
    clear) shift; cmd_clear "$@" ;;
    *) echo "[session-spend] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
