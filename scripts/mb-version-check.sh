#!/usr/bin/env bash
# mb-version-check.sh — the single authority for "is there a newer release?"
# No UI, no side effects beyond its own cache file. Stage 3's SessionStart
# hook is the only consumer that talks to a user; this only answers a question.
#
# Usage: mb-version-check.sh [--force] [--json] [--cache-only]
#   --force       bypass the cache and always fetch, even when it's fresh.
#   --json        accepted for forward-compat — output is always strict JSON.
#   --cache-only  answer purely from the on-disk cache. NEVER fetches, NEVER
#                 forks a network call, regardless of --force or TTL. A
#                 fresh cache hit answers normally (source: cache). A
#                 missing/stale/corrupt cache answers `update_available:
#                 false` with `source: cache-miss` — a valid, honest "I
#                 don't know yet" rather than paying for a fetch. This is
#                 the mode a SessionStart hook must use: local-only and
#                 near-instant (a handful of local forks, no network round
#                 trip), so a 1-2s watchdog is a backstop against pathology,
#                 not a race against the network. Callers that DO want a
#                 fresh answer (e.g. a detached background refresh) call
#                 this script in its normal mode instead.
#
# Output (stdout, always): {current, latest, update_available, flavor,
#   upgrade_command, checked_at, source}. `source` is one of: github, pypi,
#   cache, cache-miss, none, disabled, python-unavailable.
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
# Digit-only validation HERE (not just at each use site) — same
# ''|*[!0-9]* shape check `_mvc_cache_read_shell` already uses for `mtime`
# — so an invalid env value (`MB_UPDATE_CHECK_TTL=abc`) falls back to the
# default BEFORE it ever reaches `[ "$age" -gt "$effective_ttl" ]` in the
# --cache-only shell reader (a bad operand there is a `[: integer
# expected` stderr leak under `set -euo pipefail`, not a crash, but the
# --cache-only contract is zero stderr bytes on every input). Validating
# once at assignment also protects the python cache reader's own operand
# for free, since both call sites receive this same string.
TTL="${MB_UPDATE_CHECK_TTL:-86400}"
case "$TTL" in ''|*[!0-9]*) TTL=86400 ;; esac
FAIL_TTL="${MB_UPDATE_CHECK_FAIL_TTL:-3600}"
case "$FAIL_TTL" in ''|*[!0-9]*) FAIL_TTL=3600 ;; esac
# `${HOME:+...}`, not a bare `$HOME` — unset HOME degrades to "no cache", not a `set -u` abort.
DATA_HOME="${XDG_DATA_HOME:-${HOME:+$HOME/.local/share}}"
CACHE_FILE="${MB_VERSION_CHECK_CACHE:-${DATA_HOME:+$DATA_HOME/memory-bank/.mb-version-check.json}}"
FETCH_BIN="${MB_VERSION_CHECK_FETCH_BIN:-curl}"
MAX_TIME=3
MAX_BODY_BYTES="${MB_VERSION_CHECK_MAX_BODY:-65536}"

GITHUB_URL="https://api.github.com/repos/fockus/skill-memory-bank/releases/latest"
PYPI_URL="https://pypi.org/pypi/memory-bank-skill/json"

# Args parsed BEFORE the python preflight below (not after, as a bare
# reading of the script might expect) — CACHE_ONLY needs to be known
# first, because --cache-only's entire purpose is answering WITHOUT ever
# forking python, and that preflight probe is itself a python fork. See
# the preflight's own comment for why it is conditional on this.
FORCE=0
CACHE_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --json) shift ;; # output is always strict JSON; kept for explicit callers
    --cache-only) CACHE_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,49p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "[error] mb-version-check.sh: unknown argument: $1" >&2
      echo "Usage: mb-version-check.sh [--force] [--json] [--cache-only]" >&2
      exit 2
      ;;
  esac
done

# Preflighted once as an EXECUTION probe, not just `command -v` — a pyenv
# shim for an uninstalled version passes `command -v` yet fails at exec
# time. Skipped entirely for --cache-only: that path is 100% shell/sed/
# `date`/`mb_mtime` from here on (see the CACHE_ONLY branch below), so
# forking python just to answer "is python there?" would be the ONE
# python fork left on an otherwise python-free path — worth avoiding on
# its own merits, not just in the abstract.
PY_AVAILABLE=0
if [ "$CACHE_ONLY" -ne 1 ]; then
  if command -v "$MB_PY" >/dev/null 2>&1 && "$MB_PY" -c 'pass' >/dev/null 2>&1; then
    PY_AVAILABLE=1
  fi
fi

# Python helpers. Every call reads its input from stdin/env (never a bare
# CLI arg) so a JSON payload full of quotes/newlines is never re-interpreted
# by the shell. Every call is guarded with `set +e ... set -e` at the call
# site so a broken interpreter degrades to fail-open, never a crash under
# `set -euo pipefail`. `_mvc_now_iso`/`_mvc_emit` also carry their own
# pure-shell fallback — they must succeed even when python never runs at all.

# <skill_dir> -> local VERSION file content, or "unknown" (never fails).
# ZERO forks: `[ -r ... ]` (builtin) decides readability up front instead
# of discovering it via a failed redirect, and `$(<file)` is bash's own
# builtin whole-file read (no `cat`/`tr` process) — this runs on EVERY
# invocation of this script, cache-only included, so a fork saved here is
# a fork saved on every session start.
_mvc_current_version() {
  local dir="${1:-}" out
  [ -f "$dir/VERSION" ] && [ -r "$dir/VERSION" ] || { printf '%s' "unknown"; return 0; }
  out="$(<"$dir/VERSION")" 2>/dev/null
  out="${out//[[:space:]]/}"
  [ -n "$out" ] && printf '%s' "$out" || printf '%s' "unknown"
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

# <raw string> -> JSON-escaped string (no surrounding quotes), pure shell,
# ZERO forks (`${s//[[:cntrl:]]/}` replaces a `printf | tr` pipe — a
# two-process fork for every one of the 6 string fields `_mvc_emit_shell`
# escapes, on every cache-only session start). Escapes backslash/double-
# quote, strips control chars — also a backstop against a tag_name/cache
# value smuggling ANSI escapes into a rendered field.
_mvc_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//[[:cntrl:]]/}"
  printf '%s' "$s"
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

# <value> -> stdout "MAJOR MINOR PATCH" (space-separated) + success, or
# failure for anything that is not EXACTLY X.Y.Z — digits and dots only,
# EXACTLY two dots (three fields), no empty field ("5.9", "5.9.0.1",
# "5.9.0-rc1", "5..0", "" all rejected). ZERO forks. This is the shell
# equivalent of the python paths' `SEMVER_RE = r"^[0-9]+\.[0-9]+\.[0-9]+$"`
# — the ONE place that shape rule is defined for every python-free
# consumer (_mvc_compare_shell and _mvc_cache_read_shell both call this
# rather than each re-deriving the same regex by hand, which is exactly
# how two validators drift apart over time).
_mvc_semver_parts_shell() {
  local v="$1" dots f1 f2 f3
  case "$v" in *[!0-9.]*|'') return 1 ;; esac
  dots="${v//[^.]/}"
  [ "${#dots}" -eq 2 ] || return 1
  f1="${v%%.*}"; f2="${v#*.}"; f3="${f2#*.}"; f2="${f2%%.*}"
  [ -n "$f1" ] && [ -n "$f2" ] && [ -n "$f3" ] || return 1
  # Magnitude cap, not just shape — a digits-and-dots component can still
  # be long enough to overflow bash's integer `[ -gt ]`/`[ -lt ]` in
  # _mvc_compare_shell (a poisoned/corrupt cache entry, e.g.
  # "999999999999999999999999999999.0.0", is arithmetically "digits only"
  # yet not a real version). 9 digits is a generous ceiling — no real
  # semver component gets anywhere close — and stays well inside a 64-bit
  # integer compare on every bash this script supports.
  [ "${#f1}" -le 9 ] && [ "${#f2}" -le 9 ] && [ "${#f3}" -le 9 ] || return 1
  printf '%s %s %s' "$f1" "$f2" "$f3"
}

# <current> <latest> -> "true"/"false", ZERO forks — the pure-shell twin of
# _mvc_compare, used ONLY by the --cache-only path where avoiding a python
# fork is the entire point (a cold/absent cache must answer in a handful of
# milliseconds, not stack multiple python startups on top of each other).
# Same contract: numeric X.Y.Z compare, symmetric v-prefix stripped from
# both sides, any unparsable input -> false (fail-open) rather than a
# crash. Deliberately a separate implementation from what _mvc_compare
# calls into python for — this one must keep working even when python is
# broken, which _mvc_compare cannot promise.
_mvc_compare_shell() {
  local cur="$1" lat="$2" cur_parts lat_parts c1 c2 c3 l1 l2 l3
  cur="${cur#v}"; cur="${cur#V}"
  lat="${lat#v}"; lat="${lat#V}"
  cur_parts="$(_mvc_semver_parts_shell "$cur")" || { printf 'false'; return 0; }
  lat_parts="$(_mvc_semver_parts_shell "$lat")" || { printf 'false'; return 0; }
  # shellcheck disable=SC2086 # intentional word-split: _mvc_semver_parts_shell's
  # own output is exactly "N N N" (digits and single spaces, its only
  # possible shape), so this is how the 3 fields become $1/$2/$3.
  set -- $cur_parts; c1="$1"; c2="$2"; c3="$3"
  # shellcheck disable=SC2086
  set -- $lat_parts; l1="$1"; l2="$2"; l3="$3"
  if [ "$l1" -gt "$c1" ]; then printf 'true'; return 0; fi
  if [ "$l1" -lt "$c1" ]; then printf 'false'; return 0; fi
  if [ "$l2" -gt "$c2" ]; then printf 'true'; return 0; fi
  if [ "$l2" -lt "$c2" ]; then printf 'false'; return 0; fi
  if [ "$l3" -gt "$c3" ]; then printf 'true'; return 0; fi
  printf 'false'
}

# <cache_file> <ttl> <fail_ttl> -> same 4-line contract as _mvc_cache_read
# (freshness "fresh"|"stale" / latest / source / checked_at), ZERO forks —
# the --cache-only path's cache reader. The cache is untrusted input, same
# as a network answer, so this enforces the SAME two trust rules the
# python reader enforces, just without python:
#   * `latest` (when present) must satisfy _mvc_semver_parts_shell — a
#     poisoned `"latest": "9.9.9; rm -rf /"` or an ANSI/control-byte
#     payload fails the digits-and-dots check and is treated as stale.
#   * `source` must be one of the values this script itself ever WRITES
#     to the cache file (github, pypi, none — matches the python reader's
#     ALLOWED_SOURCES exactly; "cache"/"cache-miss"/"disabled" are
#     OUTPUT-only values, never written, so they are correctly rejected
#     here too if a hand-edited/malicious file claims one of them).
# Freshness uses the cache FILE's own mtime (`_lib.sh::mb_mtime`, GNU-
# `stat -c` first with a BSD `stat -f` fallback — never a raw `stat`, this
# repo has been bitten by the GNU/BSD flag mismatch before) rather than
# parsing the `checked_at` field: the atomic tmp+rename write
# (_mvc_cache_write) sets the file's mtime at exactly the moment the cache
# was written, so it is an accurate freshness clock without needing any
# date-arithmetic library. `checked_at` itself is still read and returned
# for display — just not used as the clock.
# <json> <key> -> sets `REPLY` to the string value of `"key": "value"`, or
# "" when absent/malformed; returns 1 on no-match. ZERO forks — bash's own
# `[[ =~ ]]`/BASH_REMATCH (POSIX ERE, supported since bash 3.0) replaces a
# `printf | sed` pipe (a two-process fork PER FIELD) that the network-path
# reader can afford (it already forked python) but the whole point of the
# cache-only path is not paying for.
_mvc_field_shell() {
  local json="$1" key="$2"
  if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    REPLY="${BASH_REMATCH[1]}"
    return 0
  fi
  REPLY=""
  return 1
}

_mvc_cache_read_shell() {
  local file="$1" ttl="$2" fail_ttl="$3"
  local raw latest source checked_at mtime now age effective_ttl REPLY
  [ -f "$file" ] && [ -r "$file" ] || { printf 'stale\n\n\n\n'; return 0; }
  raw="$(<"$file")" 2>/dev/null
  [ -n "$raw" ] || { printf 'stale\n\n\n\n'; return 0; }
  # A multi-line "JSON" file is corrupt (or a malicious multi-record
  # smuggle attempt) — reject outright rather than field-extract from it,
  # same posture the hook itself takes on the resolver's own answer.
  case "$raw" in *$'\n'*) printf 'stale\n\n\n\n'; return 0 ;; esac
  _mvc_field_shell "$raw" latest; latest="$REPLY"
  _mvc_field_shell "$raw" source; source="$REPLY"
  _mvc_field_shell "$raw" checked_at; checked_at="$REPLY"
  if [ -n "$latest" ]; then
    _mvc_semver_parts_shell "$latest" >/dev/null || { printf 'stale\n\n\n\n'; return 0; }
  fi
  case "$source" in
    github|pypi|none) : ;;
    *) printf 'stale\n\n\n\n'; return 0 ;;
  esac
  mtime="$(mb_mtime "$file")"
  case "$mtime" in ''|*[!0-9]*) printf 'stale\n\n\n\n'; return 0 ;; esac
  now="$(date -u +%s)"
  age=$(( now - mtime ))
  effective_ttl="$ttl"
  [ "$source" = "none" ] && effective_ttl="$fail_ttl"
  if [ "$age" -lt 0 ] || [ "$age" -gt "$effective_ttl" ]; then
    printf 'stale\n\n\n\n'
    return 0
  fi
  printf 'fresh\n%s\n%s\n%s\n' "$latest" "$source" "$checked_at"
}

# Builds the final strict JSON envelope. Tries python's json.dumps first
# (no hand-rolled string concatenation, so quoting/escaping can never
# produce invalid JSON); falls back to the pure shell emitter when python
# is unavailable or misbehaves — the JSON contract never depends on it.
#
# ensure_ascii=False below: a \uXXXX escape (e.g. the unknown-flavor
# upgrade_command em dash) is technically valid JSON, but a consumer that
# greps the raw bytes without re-decoding JSON (hooks/mb-update-notify.sh
# does exactly that) would print the literal backslash-u sequence rather
# than the character. Real UTF-8 fixes that; the shell fallback emitter
# (_mvc_emit_shell) already emits raw UTF-8 by construction, so this keeps
# both emitters in agreement. NOTE for maintainers: keep every heredoc body
# below free of a bare apostrophe/backtick — bash 3.2's `$(...)` scanner
# tracks quote balance THROUGH a single-quoted heredoc body too (a known
# pre-4.0 limitation), so a stray apostrophe in a heredoc comment breaks
# parsing under macOS system bash even though it never affects bash 4+.
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
}, ensure_ascii=False))
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

# --cache-only: answer from the on-disk cache alone, NEVER a fetch, and —
# unlike every other path below — NEVER a python fork either. `--force` is
# deliberately ignored here (cache-only wins; a caller asking for both is
# asking for a contradiction, and "never touch the network" is the
# stronger promise). This is the path a SessionStart hook must use, and
# "near-instant" is a real requirement, not a nice-to-have: a session
# start that measurably waits is the whole failure mode this design
# exists to close. Every step here is ZERO-fork or a lightweight native
# binary (`cat`, `sed`, `date`, the `stat`-based `_lib.sh::mb_mtime`) —
# `_mvc_cache_read_shell` (freshness + the SAME trust rules the network
# path enforces on untrusted cache content — see its own header),
# `_mvc_compare_shell` (numeric semver compare), `_mvc_emit_shell` (the
# JSON envelope). This intentionally runs BEFORE the PY_AVAILABLE
# preflight below (which itself is skipped for --cache-only, see its own
# comment) — a cache-only answer must not depend on python being
# installed, let alone pay for probing it.
if [ "$CACHE_ONLY" -eq 1 ]; then
  cache_out="$(_mvc_cache_read_shell "$CACHE_FILE" "$TTL" "$FAIL_TTL")"
  cache_fresh="$(printf '%s\n' "$cache_out" | sed -n '1p')"
  co_latest=""
  co_source="cache-miss"
  co_checked_at=""
  if [ "$cache_fresh" = "fresh" ]; then
    co_latest="$(printf '%s\n' "$cache_out" | sed -n '2p')"
    co_source="cache"
    co_checked_at="$(printf '%s\n' "$cache_out" | sed -n '4p')"
  fi
  [ -n "$co_checked_at" ] || co_checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  co_update_available="false"
  if [ -n "$co_latest" ]; then
    co_update_available="$(_mvc_compare_shell "$current_version" "$co_latest")"
  fi
  _mvc_emit_shell "$current_version" "$co_latest" "$co_update_available" "$flavor" "$upgrade_command" "$co_checked_at" "$co_source"
  exit 0
fi

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
