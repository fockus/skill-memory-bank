#!/usr/bin/env bash
# adapters/_framework.sh — shared adapter helpers.
_MB_STRICT_FILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/opencode_files.py"

# Portable file mode as octal digits (e.g. 644). Empty string when unknown
# (caller then skips chmod). Preserves permissions across atomic tmp+mv rewrites,
# which would otherwise inherit mktemp's 0600.
#
# GNU-FIRST + VALIDATE, and both halves matter. A BSD-first chain
#   stat -f '%Lp' "$1" || stat -c '%a' "$1"
# is broken on Linux: GNU's `-f` means --file-system, so it does NOT fail cleanly —
# it prints a whole filesystem dump ("File: ... Type: overlayfs ...") to STDOUT and
# then exits non-zero, so `||` runs the GNU branch too and $( ) captures BOTH.
# The caller then ran `chmod "<fs dump>\n644"`, which fails under set -e and killed
# the adapter with a silent exit 1. Same class as _lib.sh::mb_mtime.
mb_file_mode() {
  local m
  m="$(stat -c '%a' "$1" 2>/dev/null || true)"     # GNU
  case "$m" in
    ''|*[!0-7]*) : ;;
    *) printf '%s\n' "$m"; return 0 ;;
  esac
  m="$(stat -f '%Lp' "$1" 2>/dev/null || true)"    # BSD
  case "$m" in
    ''|*[!0-7]*) return 0 ;;                       # unknown -> empty, caller skips chmod
    *) printf '%s\n' "$m"; return 0 ;;
  esac
}

adapter_require_jq() {
  local name="${1:-adapter}"
  command -v jq >/dev/null 2>&1 || {
    echo "[$name] jq required" >&2
    return 1
  }
}

adapter_json_array_from_lines() {
  # L-3: `printf '%s\n' "${arr[@]}"` on an EMPTY bash array still emits one
  # bare newline (printf always applies its format at least once even with
  # zero arguments) — the plain `jq -R . | jq -s .` pipeline slurped that
  # single empty line into `[""]` instead of `[]`. Filter blank lines before
  # slurping so a genuinely empty/degenerate input yields `[]`.
  jq -R 'select(length > 0)' | jq -s .
}

# A22 (CDX-I11): atomic write (mktemp in the same dir + mv). A plain
# `jq ... > "$manifest_path"` redirect truncates the target BEFORE jq even
# runs — a failed jq invocation (bad --argjson, disk full, process killed
# mid-write) left a corrupt/empty manifest behind instead of the previous,
# still-valid one. mktemp's random suffix (rather than just `.tmp`/`$$`) also
# keeps two adapters writing concurrently from colliding on the same tmp path.
adapter_write_manifest() {
  local manifest_path="$1"
  local adapter_name="$2"
  local skill_version="$3"
  local files_json="$4"
  local extra_json="${5:-}"
  [ -n "$extra_json" ] || extra_json='{}'

  local tmp mode
  tmp="$(mktemp "${manifest_path}.XXXXXX")" || return 1
  mode="$(mb_file_mode "$manifest_path" 2>/dev/null)"

  if ! jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg adapter "$adapter_name" \
    --arg skill_version "$skill_version" \
    --argjson files "$files_json" \
    --argjson extra "$extra_json" \
    '{schema_version: 1, installed_at: $installed_at, adapter: $adapter, skill_version: $skill_version, files: $files} + $extra' \
    > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod "${mode:-644}" "$tmp" 2>/dev/null || true
  if [ -n "${_MB_OC_IO_CONTEXT:-}" ] && [ "$manifest_path" = "${_MB_OC_IO_RECORD:-}" ]; then
    _mb_oc_io checkpoint "$manifest_path" "$tmp"
  else
    mv "$tmp" "$manifest_path"
  fi
}

adapter_remove_manifest_files() {
  local manifest_path="$1"
  local file_path
  if [ -n "${2:-}" ]; then
    _mb_strict_file remove "$manifest_path" "$manifest_path" "$2"
    return $?
  fi
  jq -r '.files[]?' "$manifest_path" | while IFS= read -r file_path; do
    [ -n "$file_path" ] && [ -f "$file_path" ] && rm -f "$file_path" || true
  done
}

# I-250: true when $1 is listed in adapter manifest $2 and was not edited after
# that manifest was written — our own file, replaced without a backup.
_mb_owned_unedited() {
  if [ -n "${3:-}" ]; then
    _mb_strict_file owned "$1" "$2" "$3"
    return $?
  fi
  [ ! "$1" -nt "$2" ] && jq -e --arg f "$1" '(.files // []) | any(. == $f)' "$2" >/dev/null 2>&1
}

_mb_strict_file() {
  python3 "$_MB_STRICT_FILES" "$@"
}

# Private, execution-scoped recovery context; never an ownership or replay source.
_mb_oc_context() {
  if [ -z "${_MB_OC_IO_CONTEXT:-}" ]; then
    _MB_OC_IO_CONTEXT="$(mktemp -d)" || return 1
    _MB_OC_IO_OWNED=1
    export _MB_OC_IO_CONTEXT
  fi
}

_mb_oc_start() {
  _mb_oc_context || return 1
  _mb_oc_io probe "$1" "$2"
}

_mb_oc_io() {
  python3 - "$(dirname "$_MB_STRICT_FILES")" "$1" "$_MB_OC_IO_CONTEXT" "${@:2}" <<'PY'
import json
import sys

sys.path.insert(0, sys.argv[1])
from opencode_files import private_directory
from opencode_install_io import abort, checkpoint, mark, prepare, probe

directory = sys.argv[3]
try:
    context = private_directory(directory)
    action = sys.argv[2]
    values = sys.argv[4:]
    if action == "probe":
        probe(context, *values)
    elif action == "prepare":
        prepare(context, *values)
    elif action == "mark":
        print(json.dumps(mark(context, *values)))
    elif action == "checkpoint":
        checkpoint(context, *values)
    elif action == "abort":
        abort(context)
    else:
        raise ValueError("unknown operation")
except (OSError, ValueError, KeyError, TypeError) as exc:
    print(f"[opencode-io] {exc}; recovery: {directory}", file=sys.stderr)
    raise SystemExit(1) from None
PY
}

_mb_oc_paths() {
  printf '%s\n' "$@" | jq -R '{path: .}' | jq -sc .
}

_mb_oc_require_owned() {
  local file="$1" record="$2" root="$3" kind="${4:-owned}" rc=0
  _mb_strict_file path "$file" "$record" "$root" || return $?
  [ -e "$file" ] || [ -L "$file" ] || return 0
  _mb_strict_file "$kind" "$file" "$record" "$root" || rc=$?
  [ "$rc" -eq 1 ] || return "$rc"
  echo "[opencode] preserved $file: automatic replacement requires verifiable ownership; restore an authoritative manifest or request separately approved exact manual replacements." >&2
  return 1
}

_mb_oc_source_paths() {
  python3 - "$1" "$2" <<'PY'
import hashlib, json, sys
with open(sys.argv[2], 'rb') as source:
    digest = hashlib.file_digest(source, 'sha256').hexdigest()
print(json.dumps([{'path': sys.argv[1], 'expected': digest}]))
PY
}

# Conditional shell callers must not disable the legacy writer's error handling.
_mb_oc_upsert() {
  bash -euo pipefail -c '. "$1"; shift; mb_upsert_marked_block "$@"' _ \
    "$(dirname "$_MB_STRICT_FILES")/_lib_agents_md.sh" "$@"
}

_mb_oc_apply() {
  local _MB_OC_IO_RECORD="$1" root="$2" paths="$3" checkpoint="$4" rc=0
  local _MB_OC_POST_HASHES
  local _MB_OC_EXPECTED_POSTS='{}'
  shift 4
  if [ -f "$_MB_OC_IO_CONTEXT/pending.json" ] || [ -f "$_MB_OC_IO_CONTEXT/failed" ]; then
    echo "[opencode-io] earlier operation failed; recovery: $_MB_OC_IO_CONTEXT" >&2
    return 1
  fi
  if ! _mb_oc_io prepare "$_MB_OC_IO_RECORD" "$root" "$paths"; then
    _mb_oc_io mark >/dev/null && _mb_oc_io abort || true
    return 1
  fi
  "$@" || rc=$?
  if ! _MB_OC_POST_HASHES="$(_mb_oc_io mark "$_MB_OC_EXPECTED_POSTS")"; then
    _mb_oc_io abort || true
    return 1
  fi
  if [ "$rc" -eq 0 ] && "$checkpoint"; then
    return 0
  fi
  if [ -f "$_MB_OC_IO_CONTEXT/pending.json" ]; then _mb_oc_io abort || true; fi
  return 1
}

_mb_oc_save_manifest() {
  local record="$1" root="$2" written="$3" extra="$4" previous ownership delta="${_MB_OC_POST_HASHES:-}"
  [ -n "$delta" ] || delta='{}'
  [ ! -f "$_MB_OC_IO_CONTEXT/failed" ] || return 1
  previous='{}'
  if [ -f "$record" ]; then previous="$(jq -c . "$record")" || return 1; fi
  ownership=$(printf '%s' "$written" | _mb_strict_file records "$record" "$record" "$root") || return 1
  extra=$(jq -n --argjson prior "$previous" --argjson extra "$extra" --argjson owned "$ownership" \
    --argjson delta "$delta" '
    $prior + $extra + {files:$owned.files,file_sha256: ($owned.file_sha256 + ($delta | with_entries(select(.value != null and (.key as $path | $owned.files | index($path) != null)))))}
    | del(.schema_version,.installed_at,.adapter,.skill_version)') || return 1
  if ! adapter_write_manifest "$record" opencode "$(cat "$(dirname "$_MB_STRICT_FILES")/../VERSION")" "$(printf '%s' "$ownership" | jq '.files')" "$extra"; then
    if [ ! -f "$_MB_OC_IO_CONTEXT/pending.json" ]; then _mb_oc_io abort || true; fi
    return 1
  fi
}

_mb_oc_exit() {
  local rc=$?
  [ "${_MB_OC_IO_OWNED:-0}" = 1 ] || return "$rc"
  if [ -f "$_MB_OC_IO_CONTEXT/pending.json" ]; then
    if [ ! -f "$_MB_OC_IO_CONTEXT/rollback-started" ]; then
      _mb_oc_io mark "${_MB_OC_EXPECTED_POSTS:-}" >/dev/null && _mb_oc_io abort || rc=1
    else rc=1; fi
  fi
  _mb_oc_close || rc=1
  return "$rc"
}

_mb_oc_close() {
  [ "${_MB_OC_IO_OWNED:-0}" = 1 ] || return 0
  local rc=0
  if [ -f "$_MB_OC_IO_CONTEXT/failed" ] && [ ! -f "$_MB_OC_IO_CONTEXT/pending.json" ]; then
    rm -f "$_MB_OC_IO_CONTEXT/failed" || return 1
    rc=1
  fi
  if ! rmdir "$_MB_OC_IO_CONTEXT" 2>/dev/null; then
    echo "[opencode-io] incomplete recovery retained; recovery: $_MB_OC_IO_CONTEXT" >&2
    return 1
  fi
  return "$rc"
}
