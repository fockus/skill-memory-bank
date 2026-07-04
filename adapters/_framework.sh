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
  jq -R . | jq -s .
}

adapter_write_manifest() {
  local manifest_path="$1"
  local adapter_name="$2"
  local skill_version="$3"
  local files_json="$4"
  local extra_json="${5:-}"
  [ -n "$extra_json" ] || extra_json='{}'

  jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg adapter "$adapter_name" \
    --arg skill_version "$skill_version" \
    --argjson files "$files_json" \
    --argjson extra "$extra_json" \
    '{schema_version: 1, installed_at: $installed_at, adapter: $adapter, skill_version: $skill_version, files: $files} + $extra' \
    > "$manifest_path"
}

adapter_remove_manifest_files() {
  local manifest_path="$1"
  local file_path
  jq -r '.files[]?' "$manifest_path" | while IFS= read -r file_path; do
    [ -n "$file_path" ] && [ -f "$file_path" ] && rm -f "$file_path" || true
  done
}
