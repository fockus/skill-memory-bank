#!/usr/bin/env bash
# adapters/_framework.sh — shared adapter helpers.

# Portable file mode as octal digits (e.g. 644). BSD `stat -f%Lp`, GNU `stat -c%a`.
# Empty string on failure (caller then skips chmod). Used to preserve permissions
# across atomic tmp+mv rewrites (mktemp defaults to 0600).
mb_file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || true
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
