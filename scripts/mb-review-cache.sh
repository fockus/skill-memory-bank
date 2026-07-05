#!/usr/bin/env bash
# mb-review-cache.sh — deterministic touched-file sha + test-evidence TTL
# cache helpers for the reviewer-2.0 orchestrator (scripts/mb-review.sh).
# Design: .memory-bank/specs/reviewer-2.0/design.md §5 "Test-cache contract",
# §8 test_mb_review_sha / test_mb_review_cache.
#
# Subcommands:
#   sha                                     stdin: newline-separated paths.
#                                            Prints "sha256:<hex>" — sha256
#                                            over the sorted, canonicalised
#                                            representation (see `canonical`).
#                                            Deterministic regardless of input
#                                            order; empty stdin -> sha of the
#                                            empty set.
#
#   canonical                               Same input as `sha`. Prints the
#                                            pre-hash canonical text (one
#                                            "<path>\t<marker>" line per
#                                            sorted path) — debug/testing aid
#                                            for asserting the DELETED: marker.
#
#   check --mb <path> --sha <sha>
#         [--ttl <seconds>]                 Cache file: <mb>/tmp/last-tests.json.
#                                            Prints HIT or MISS to stdout.
#                                            Exit 0 = HIT, 1 = MISS (missing
#                                            file, schema_version != 1, sha
#                                            mismatch, or TTL expired — default
#                                            ttl 600s). Reasons on stderr.
#
#   write --mb <path> --sha <sha>
#         [--run-id <id>]                   stdin: evidence JSON (must be an
#                                            object with boolean "tests_pass";
#                                            "counts"/"coverage"/"failures"/
#                                            "elapsed_sec"/"stack_detected" are
#                                            optional, defaulted). Stamps
#                                            schema_version=1, the given sha as
#                                            touched_files_sha, and a fresh
#                                            run_id (ISO8601Z + "-" + random
#                                            hex suffix) unless --run-id
#                                            overrides it. Atomic write.
#                                            Prints the written cache path.
#
#   clear --mb <path>                       Removes the cache file. Idempotent
#                                            — a missing file is not an error.
#                                            This is what /mb work --refresh-tests
#                                            calls before the next check.
#
# Exit codes:
#   0  success (sha/canonical/write/clear), or `check` HIT
#   1  `check` MISS
#   2  usage / validation error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  echo "Usage: mb-review-cache.sh {sha|canonical|check|write|clear} [options]" >&2
  echo "Run 'mb-review-cache.sh --help' for the full contract." >&2
}

# Guards against the bash "shift count out of range" crash when a
# value-taking flag is the LAST arg with no following value: without this,
# `shift 2` with $#==1 aborts the whole script under `set -euo pipefail`
# with a silent exit 1 -- never the script's own documented "exit 2 =
# usage / validation error" contract.
# $1 = subcommand name (for the message); remaining args ("$@" from the
# call site) start with the flag itself, e.g. `require_value check "$@"`
# where the outer "$@" is `--sha` (no value) or `--sha foo`.
require_value() {
  local subcmd="$1"
  shift
  [ "$#" -ge 2 ] || { echo "[review-cache] $subcmd: $1 requires a value" >&2; exit 2; }
}

# ---- sha / canonical ---------------------------------------------------

# Reads newline-separated paths from stdin and prints either the sha256 over
# the canonical representation ("sha") or the canonical text itself
# ("canonical"). Blank lines are ignored so an empty touched-file set is
# handled without special-casing callers.
#
# The path list is captured into a variable FIRST (not read live inside the
# python heredoc) because `python3 - <<'PY'` already consumes stdin to supply
# the script source itself — a live `sys.stdin` read inside that heredoc
# would see EOF, not the caller's piped paths.
run_sha_or_canonical() {
  local mode="$1" input
  input=$(cat -)
  MODE="$mode" PATHS_INPUT="$input" python3 - <<'PY'
import hashlib
import os

mode = os.environ["MODE"]

paths = []
for raw in os.environ.get("PATHS_INPUT", "").splitlines():
    if raw.strip():
        paths.append(raw)

lines = []
for path in sorted(paths):
    if os.path.isfile(path):
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        marker = f"sha256:{h.hexdigest()}"
    else:
        marker = f"DELETED:{path}"
    lines.append(f"{path}\t{marker}")

canonical = "\n".join(lines)

if mode == "canonical":
    print(canonical)
else:
    print("sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest())
PY
}

cmd_sha() {
  run_sha_or_canonical sha
}

cmd_canonical() {
  run_sha_or_canonical canonical
}

# ---- check --------------------------------------------------------------

cmd_check() {
  local mb_arg="" sha="" ttl="600"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) require_value check "$@"; mb_arg="$2"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      --sha) require_value check "$@"; sha="$2"; shift 2 ;;
      --sha=*) sha="${1#--sha=}"; shift ;;
      --ttl) require_value check "$@"; ttl="$2"; shift 2 ;;
      --ttl=*) ttl="${1#--ttl=}"; shift ;;
      *) echo "[review-cache] check: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  [ -z "$sha" ] && { echo "[review-cache] check: --sha required" >&2; exit 2; }

  local bank cache
  bank=$(mb_resolve_path "$mb_arg")
  cache="$bank/tmp/last-tests.json"

  if [ ! -f "$cache" ]; then
    echo "[review-cache] MISS: no cache file at $cache" >&2
    echo "MISS"
    exit 1
  fi

  CACHE="$cache" EXPECT_SHA="$sha" TTL="$ttl" python3 - <<'PY'
import datetime
import json
import os
import re
import sys

cache_path = os.environ["CACHE"]
expect_sha = os.environ["EXPECT_SHA"]
try:
    ttl = int(os.environ["TTL"])
except (TypeError, ValueError):
    ttl = 600


def miss(reason: str) -> None:
    sys.stderr.write(f"[review-cache] MISS: {reason}\n")
    print("MISS")
    sys.exit(1)


try:
    with open(cache_path, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:
    miss(f"cache file unreadable/corrupt ({exc})")

if not isinstance(data, dict) or data.get("schema_version") != 1:
    miss("schema_version mismatch")

if data.get("touched_files_sha") != expect_sha:
    miss("touched_files_sha mismatch")

run_id = data.get("run_id", "")
m = re.match(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)", run_id)
if not m:
    miss("run_id missing/unparseable timestamp")

try:
    ts = datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=datetime.timezone.utc
    )
except Exception as exc:
    miss(f"run_id timestamp parse error ({exc})")

age = (datetime.datetime.now(datetime.timezone.utc) - ts).total_seconds()
if age < 0:
    age = 0.0  # clock skew safety net — never treat the future as stale
if age >= ttl:
    miss(f"TTL expired ({age:.0f}s >= {ttl}s)")

print("HIT")
PY
}

# ---- write ----------------------------------------------------------------

cmd_write() {
  local mb_arg="" sha="" run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) require_value write "$@"; mb_arg="$2"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      --sha) require_value write "$@"; sha="$2"; shift 2 ;;
      --sha=*) sha="${1#--sha=}"; shift ;;
      --run-id) require_value write "$@"; run_id="$2"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      *) echo "[review-cache] write: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  [ -z "$sha" ] && { echo "[review-cache] write: --sha required" >&2; exit 2; }

  local bank tmp_dir cache tmp_file input_json
  bank=$(mb_resolve_path "$mb_arg")
  tmp_dir="$bank/tmp"
  mkdir -p "$tmp_dir"
  cache="$tmp_dir/last-tests.json"

  input_json=$(cat -)
  [ -z "$input_json" ] && { echo "[review-cache] write: evidence JSON required on stdin" >&2; exit 2; }

  tmp_file=$(mktemp "$tmp_dir/.last-tests.XXXXXX")

  if ! CACHE_TMP="$tmp_file" SHA="$sha" RUN_ID="$run_id" INPUT_JSON="$input_json" python3 - <<'PY'
import datetime
import json
import os
import secrets
import sys

sha = os.environ["SHA"]
run_id = os.environ.get("RUN_ID") or ""
cache_tmp = os.environ["CACHE_TMP"]

try:
    data = json.loads(os.environ["INPUT_JSON"])
except Exception as exc:
    sys.stderr.write(f"[review-cache] write: invalid evidence JSON ({exc})\n")
    sys.exit(2)

if not isinstance(data, dict):
    sys.stderr.write("[review-cache] write: evidence JSON must be an object\n")
    sys.exit(2)

tests_pass = data.get("tests_pass")
if not isinstance(tests_pass, bool):
    sys.stderr.write("[review-cache] write: evidence JSON requires boolean 'tests_pass'\n")
    sys.exit(2)

if not run_id:
    run_id = (
        datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        + "-"
        + secrets.token_hex(3)
    )

evidence = {
    "schema_version": 1,
    "run_id": run_id,
    "stack_detected": data.get("stack_detected", "unknown"),
    "touched_files_sha": sha,
    "tests_pass": tests_pass,
    "counts": data.get("counts") or {"passed": 0, "failed": 0, "skipped": 0},
    "coverage": data.get("coverage") or {},
    "failures": data.get("failures") or [],
    "elapsed_sec": data.get("elapsed_sec", 0),
}

with open(cache_tmp, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(evidence, ensure_ascii=False) + "\n")
PY
  then
    rm -f "$tmp_file"
    exit 2
  fi

  mv "$tmp_file" "$cache"
  printf '%s\n' "$cache"
}

# ---- clear ------------------------------------------------------------------

cmd_clear() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) require_value clear "$@"; mb_arg="$2"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) echo "[review-cache] clear: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  rm -f "$bank/tmp/last-tests.json"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
    exit 2
  fi
  case "$1" in
    -h|--help) sed -n '2,51p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    sha) shift; cmd_sha "$@" ;;
    canonical) shift; cmd_canonical "$@" ;;
    check) shift; cmd_check "$@" ;;
    write) shift; cmd_write "$@" ;;
    clear) shift; cmd_clear "$@" ;;
    *) echo "[review-cache] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
