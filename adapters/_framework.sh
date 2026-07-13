#!/usr/bin/env bash
# adapters/_framework.sh — shared adapter helpers.

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
  mv "$tmp" "$manifest_path"
}

adapter_remove_manifest_files() {
  local manifest_path="$1"
  local file_path
  jq -r '.files[]?' "$manifest_path" | while IFS= read -r file_path; do
    [ -n "$file_path" ] && [ -f "$file_path" ] && rm -f "$file_path" || true
  done
}
