#!/usr/bin/env bash
# mb-version-check.sh — the single authority for "is there a newer release?"
# No UI, no side effects beyond its own cache file. Stage 3's SessionStart
# hook is the only consumer that talks to a user; this only answers a question.
#
# Usage: mb-version-check.sh [--force] [--json]
#   --force   bypass the cache and always fetch, even when it's fresh.
#   --json    accepted for forward-compat — output is always strict JSON.
#
# Output (stdout, always): {current, latest, update_available, flavor,
#   upgrade_command, checked_at, source}
#
# Env:
#   MB_SKILL_DIR              install dir to inspect. Default: this script's
#                              own bundle root (`SCRIPT_DIR/..`) — never a
#                              hardcoded host path (ships via Codex/Cursor/
#                              pipx/pip/brew too, not just Claude Code).
#   MB_UPDATE_CHECK=off        short-circuit before any network call, cache
#                              I/O, or flavor detection (which can fork
#                              `brew --prefix`).
#   MB_UPDATE_CHECK_TTL        cache TTL, seconds. Default 86400 (24h).
#   MB_UPDATE_CHECK_FAIL_TTL   TTL for a *negative* cache entry (both GitHub
#                              and PyPI unreachable). Default 3600 (1h) — an
#                              outage is retried hourly, not every session.
#   MB_VERSION_CHECK_CACHE     cache file path override (tests / advanced).
#   MB_VERSION_CHECK_FETCH_BIN network seam replacing `curl` wholesale, same
#                              pattern as mb-drive.sh's MB_*_BIN seams.
#   MB_VERSION_CHECK_MAX_BODY  max fetch response bytes read. Default 65536
#                              — `--max-time` bounds wait time, not size.
#   MB_PYTHON                  python3 override. Absent/broken -> every path
#                              below degrades to a pure-shell fallback.
#
# Safety invariant (non-negotiable): fail-open on every path that isn't a
# usage error — broken network/cache/upstream API, even a missing python3,
# must never be worse than not checking at all. Every path still prints
# valid JSON and exits 0, with no stderr noise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

MB_PY="${MB_PYTHON:-python3}"
SKILL_DIR="${MB_SKILL_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TTL="${MB_UPDATE_CHECK_TTL:-86400}"
FAIL_TTL="${MB_UPDATE_CHECK_FAIL_TTL:-3600}"
# `${HOME:+...}`, not a bare `$HOME` — unset HOME degrades to "no cache", not a `set -u` abort.
DATA_HOME="${XDG_DATA_HOME:-${HOME:+$HOME/.local/share}}"
CACHE_FILE="${MB_VERSION_CHECK_CACHE:-${DATA_HOME:+$DATA_HOME/memory-bank/.mb-version-check.json}}"
FETCH_BIN="${MB_VERSION_CHECK_FETCH_BIN:-curl}"
MAX_TIME=3
MAX_BODY_BYTES="${MB_VERSION_CHECK_MAX_BODY:-65536}"

GITHUB_URL="https://api.github.com/repos/fockus/skill-memory-bank/releases/latest"
PYPI_URL="https://pypi.org/pypi/memory-bank-skill/json"

# Preflighted once as an EXECUTION probe, not just `command -v` — a pyenv
# shim for an uninstalled version passes `command -v` yet fails at exec time.
PY_AVAILABLE=0
if command -v "$MB_PY" >/dev/null 2>&1 && "$MB_PY" -c 'pass' >/dev/null 2>&1; then
  PY_AVAILABLE=1
fi
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --json) shift ;; # output is always strict JSON; kept for explicit callers
    -h|--help)
      sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "[error] mb-version-check.sh: unknown argument: $1" >&2
      echo "Usage: mb-version-check.sh [--force] [--json]" >&2
      exit 2
      ;;
  esac
done

# Python helpers. Every call reads its input from stdin/env (never a bare
# CLI arg) so a JSON payload full of quotes/newlines is never re-interpreted
# by the shell. Every call is guarded with `set +e ... set -e` at the call
# site so a broken interpreter degrades to fail-open, never a crash under
# `set -euo pipefail`. `_mvc_now_iso`/`_mvc_emit` also carry their own
# pure-shell fallback — they must succeed even when python never runs at all.

# <skill_dir> -> local VERSION file content, or "unknown" (never fails; the
# `{ ...; }` group is required for `2>/dev/null` to catch a failed `<` redirect).
_mvc_current_version() {
  local dir="${1:-}" out rc
  [ -f "$dir/VERSION" ] || { printf '%s' "unknown"; return 0; }
  set +e
  out="$( { tr -d '[:space:]' < "$dir/VERSION"; } 2>/dev/null )"; rc=$?
  set -e
  [ "$rc" -eq 0 ] && printf '%s' "$out" || printf '%s' "unknown"
}

# now (ISO-8601 UTC), the single clock used everywhere. Tries python first,
# falls back to `date -u` (portable BSD/GNU alike) — never fails.
_mvc_now_iso() {
  if [ "$PY_AVAILABLE" -eq 1 ]; then
    local out rc
    set +e
    out="$("$MB_PY" -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' 2>/dev/null)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# <raw string> -> JSON-escaped string (no surrounding quotes), pure shell.
# Escapes backslash/double-quote, strips control chars — also a backstop
# against a tag_name/cache value smuggling ANSI escapes into a rendered field.
_mvc_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s" | tr -d '[:cntrl:]'
}

# Pure-shell JSON emit — the "works with no python at all" contract is
# enforced HERE, not by hoping every call site remembers to guard itself.
_mvc_emit_shell() {
  local current latest update_available flavor upgrade_command checked_at source
  current="$(_mvc_json_escape "$1")"
  latest="$(_mvc_json_escape "$2")"
  case "$3" in
    true) update_available="true" ;;
    *) update_available="false" ;;
  esac
  flavor="$(_mvc_json_escape "$4")"
  upgrade_command="$(_mvc_json_escape "$5")"
  checked_at="$(_mvc_json_escape "$6")"
  source="$(_mvc_json_escape "$7")"
  printf '{"current": "%s", "latest": "%s", "update_available": %s, "flavor": "%s", "upgrade_command": "%s", "checked_at": "%s", "source": "%s"}\n' \
    "$current" "$latest" "$update_available" "$flavor" "$upgrade_command" "$checked_at" "$source"
}

# <cache_file> <ttl> <fail_ttl> -> 4 lines: freshness("fresh"|"stale") /
# latest / source / checked_at. Missing/malformed/semantically-invalid ->
# "stale", never a crash. Cache is untrusted like the network: `latest`
# must pass the same semver shape, `source` a known value — a poisoned
# cache must not bypass validation. A negative entry uses `fail_ttl`.
_mvc_cache_read() {
  MVC_CACHE_FILE="$1" MVC_TTL="$2" MVC_FAIL_TTL="$3" "$MB_PY" - 2>/dev/null <<'PY'
import datetime, json, os, re

def stale():
    print("stale\n\n\n")

SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
ALLOWED_SOURCES = {"github", "pypi", "none"}
path = os.environ.get("MVC_CACHE_FILE", "")
try:
    ttl = int(os.environ.get("MVC_TTL", "86400"))
except Exception:
    ttl = 86400
try:
    fail_ttl = int(os.environ.get("MVC_FAIL_TTL", "3600"))
except Exception:
    fail_ttl = 3600

try:
    with open(path) as fh:
        data = json.load(fh)
    checked_at = str(data["checked_at"])
    latest = str(data.get("latest") or "")
    source = str(data.get("source") or "")
    if source not in ALLOWED_SOURCES or (latest and not SEMVER_RE.match(latest)):
        stale()
    else:
        checked_dt = datetime.datetime.strptime(
            checked_at, "%Y-%m-%dT%H:%M:%SZ"
        ).replace(tzinfo=datetime.timezone.utc)
        age = (datetime.datetime.now(datetime.timezone.utc) - checked_dt).total_seconds()
        effective_ttl = fail_ttl if source == "none" else ttl
        if age < 0 or age > effective_ttl:
            stale()
        else:
            print("fresh\n%s\n%s\n%s" % (latest, source, checked_at))
except Exception:
    stale()
PY
}

# <cache_file> <latest> <source> <checked_at> -> atomic best-effort write.
# Unwritable cache dir just means "no cache next time". Atomic (tmp file +
# os.replace) so two racing SessionStart hooks can't interleave into garbage.
_mvc_cache_write() {
  MVC_CACHE_FILE="$1" MVC_LATEST="$2" MVC_SOURCE="$3" MVC_CHECKED_AT="$4" \
    "$MB_PY" - 2>/dev/null <<'PY'
import json, os, tempfile
path = os.environ.get("MVC_CACHE_FILE", "")
try:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    payload = {
        "latest": os.environ.get("MVC_LATEST", ""),
        "source": os.environ.get("MVC_SOURCE", ""),
        "checked_at": os.environ.get("MVC_CHECKED_AT", ""),
    }
    fd, tmp_path = tempfile.mkstemp(prefix=".mb-version-check.", dir=os.path.dirname(path) or ".")
    with os.fdopen(fd, "w") as fh:
        json.dump(payload, fh)
    os.replace(tmp_path, path)
except Exception:
    pass
PY
}

# <mode:github|pypi> <raw_body via stdin> -> a normalized "X.Y.Z" string, or
# nothing (invalid JSON / missing field / pre-release / malformed tag) —
# empty output means "ignore this answer" to every caller. Passed via `-c`
# (not a `<<PY` heredoc): this reads the body from stdin, and a heredoc
# would redirect stdin to itself and starve that pipe.
_MVC_EXTRACT_TAG_PY='
import json, os, re, sys
mode = os.environ.get("MVC_MODE", "")
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tag = ""
if mode == "github":
    tag = data.get("tag_name") or ""
elif mode == "pypi":
    info = data.get("info") or {}
    tag = info.get("version") or ""
tag = str(tag).strip()
if tag[:1] in ("v", "V"):
    tag = tag[1:]
if re.match(r"^[0-9]+\.[0-9]+\.[0-9]+$", tag):
    print(tag)
'
_mvc_extract_tag() {
  MVC_MODE="$1" "$MB_PY" -c "$_MVC_EXTRACT_TAG_PY" 2>/dev/null
}

# <current> <latest> -> "true"/"false". Numeric (X, Y, Z as integers) semver
# compare — a lexical string compare gets "5.10.0 > 5.9.0" backwards. Any
# unparsable input -> "false" (fail-open). Both sides strip an optional
# `v`/`V` prefix before the regex — symmetric normalization, so a
# `v`-prefixed VERSION file still compares correctly against `latest`.
_mvc_compare() {
  "$MB_PY" - "$1" "$2" 2>/dev/null <<'PY'
import re, sys

def parse(value):
    value = (value or "").strip()
    if value[:1] in ("v", "V"):
        value = value[1:]
    m = re.match(r"^([0-9]+)\.([0-9]+)\.([0-9]+)$", value)
    return tuple(int(part) for part in m.groups()) if m else None

current, latest = parse(sys.argv[1]), parse(sys.argv[2])
if current is None or latest is None:
    print("false")
else:
    print("true" if latest > current else "false")
PY
}

# Builds the final strict JSON envelope. Tries python's json.dumps first
# (no hand-rolled string concatenation, so quoting/escaping can never
# produce invalid JSON); falls back to the pure shell emitter when python
# is unavailable or misbehaves — the JSON contract never depends on it.
_mvc_emit() {
  if [ "$PY_AVAILABLE" -eq 1 ]; then
    local out rc
    set +e
    out="$("$MB_PY" - "$1" "$2" "$3" "$4" "$5" "$6" "$7" 2>/dev/null <<'PY'
import json, sys
current, latest, update_available, flavor, upgrade_command, checked_at, source = sys.argv[1:8]
print(json.dumps({
    "current": current,
    "latest": latest,
    "update_available": update_available == "true",
    "flavor": flavor,
    "upgrade_command": upgrade_command,
    "checked_at": checked_at,
    "source": source,
}))
PY
)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  _mvc_emit_shell "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

# Runs the fetch seam with a hard time budget AND a hard size cap ($1=url ->
# stdout=body, exit status mirrors the fetch binary's own). `head -c` caps
# the body at the pipe so a hostile/huge response is never fully buffered.
# `PIPESTATUS[0]` (not `$?`, which under `pipefail` would reflect `head`)
# carries the real fetch exit status back as this function's return code.
_mvc_fetch() {
  local url="$1" out rc
  set +e
  out="$("$FETCH_BIN" -fsS --max-time "$MAX_TIME" "$url" 2>/dev/null | head -c "$MAX_BODY_BYTES")"
  rc="${PIPESTATUS[0]}"
  set -e
  printf '%s' "$out"
  return "$rc"
}

# MB_UPDATE_CHECK=off — the absolute first short-circuit: before flavor
# detection (can fork `brew --prefix`), before cache I/O, before anything.
# Still answers the same strict-JSON contract.
if [ "${MB_UPDATE_CHECK:-on}" = "off" ]; then
  current_version="$(_mvc_current_version "$SKILL_DIR")"
  checked_at="$(_mvc_now_iso)"
  _mvc_emit "$current_version" "" "false" "unknown" "$(mb_upgrade_command "unknown")" "$checked_at" "disabled"
  exit 0
fi

current_version="$(_mvc_current_version "$SKILL_DIR")"
flavor="$(mb_install_flavor "$SKILL_DIR")"
upgrade_command="$(mb_upgrade_command "$flavor" "$SKILL_DIR")"

# python3/MB_PYTHON missing — everything below needs it, so answer from
# what pure shell already knows and stop before an unguarded exec attempt.
if [ "$PY_AVAILABLE" -ne 1 ]; then
  checked_at="$(_mvc_now_iso)"
  _mvc_emit "$current_version" "" "false" "$flavor" "$upgrade_command" "$checked_at" "python-unavailable"
  exit 0
fi

latest=""
source_used="none"
checked_at=""
used_cache=0

if [ "$FORCE" -ne 1 ]; then
  set +e
  cache_out="$(_mvc_cache_read "$CACHE_FILE" "$TTL" "$FAIL_TTL")"
  set -e
  cache_fresh="$(printf '%s\n' "$cache_out" | sed -n '1p')"
  if [ "$cache_fresh" = "fresh" ]; then
    latest="$(printf '%s\n' "$cache_out" | sed -n '2p')"
    source_used="cache"
    checked_at="$(printf '%s\n' "$cache_out" | sed -n '4p')"
    used_cache=1
  fi
fi

if [ "$used_cache" -ne 1 ]; then
  fetched=0

  # GitHub first, PyPI fallback — same shape for both, so one loop drives it.
  for src_pair in "github $GITHUB_URL" "pypi $PYPI_URL"; do
    [ "$fetched" -eq 1 ] && break
    src_mode="${src_pair%% *}"
    src_url="${src_pair#* }"
    set +e
    body="$(_mvc_fetch "$src_url")"
    fetch_rc=$?
    set -e
    if [ "$fetch_rc" -eq 0 ] && [ -n "$body" ]; then
      set +e
      tag="$(printf '%s' "$body" | _mvc_extract_tag "$src_mode")"
      set -e
      if [ -n "$tag" ]; then
        latest="$tag"
        source_used="$src_mode"
        fetched=1
      fi
    fi
  done

  checked_at="$(_mvc_now_iso)"

  if [ "$fetched" -eq 1 ]; then
    _mvc_cache_write "$CACHE_FILE" "$latest" "$source_used" "$checked_at" || true
  else
    # Negative-cache the outage: an offline user must not re-pay the full
    # dual-timeout budget on every SessionStart.
    source_used="none"
    _mvc_cache_write "$CACHE_FILE" "" "none" "$checked_at" || true
  fi
fi

update_available="false"
if [ -n "$latest" ]; then
  set +e
  update_available="$(_mvc_compare "$current_version" "$latest")"
  set -e
  case "$update_available" in
    true|false) : ;;
    *) update_available="false" ;;
  esac
fi

_mvc_emit "$current_version" "$latest" "$update_available" "$flavor" "$upgrade_command" "$checked_at" "$source_used"
exit 0
