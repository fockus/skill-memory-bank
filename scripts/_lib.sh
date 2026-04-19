#!/usr/bin/env bash
# _lib.sh — shared utilities for Memory Bank scripts.
# Source from other scripts: source "$(dirname "$0")/_lib.sh"
#
# All functions print their output to stdout and return 0 on success.
# They avoid `exit` so sourcing scripts stay in control.

# shellcheck shell=bash

# Resolve MB path from explicit arg or .claude-workspace file in cwd.
# Falls back to ".memory-bank" (relative path) when nothing else is known.
mb_resolve_path() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return 0
  fi

  if [ -f ".claude-workspace" ]; then
    local storage project_id
    storage=$(grep '^storage:' .claude-workspace 2>/dev/null | awk '{print $2}' | tr -d '"' || true)
    if [ "$storage" = "external" ]; then
      project_id=$(grep '^project_id:' .claude-workspace 2>/dev/null | awk '{print $2}' | tr -d '"' || true)
      if [ -n "$project_id" ]; then
        printf '%s\n' "$HOME/.claude/workspaces/$project_id/.memory-bank"
        return 0
      fi
    fi
  fi

  printf '%s\n' ".memory-bank"
}

# Detect project stack by scanning manifest files in a directory.
# Outputs one of: python, go, rust, node, multi, unknown.
mb_detect_stack() {
  local dir="${1:-$PWD}"

  if [ ! -d "$dir" ]; then
    printf '%s\n' "unknown"
    return 0
  fi

  local count=0 stack=""

  if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/requirements.txt" ] || [ -f "$dir/setup.py" ]; then
    count=$((count + 1))
    stack="python"
  fi
  if [ -f "$dir/go.mod" ]; then
    count=$((count + 1))
    stack="go"
  fi
  if [ -f "$dir/Cargo.toml" ]; then
    count=$((count + 1))
    stack="rust"
  fi
  if [ -f "$dir/package.json" ]; then
    count=$((count + 1))
    stack="node"
  fi

  if [ "$count" -eq 0 ]; then
    printf '%s\n' "unknown"
  elif [ "$count" -ge 2 ]; then
    printf '%s\n' "multi"
  else
    printf '%s\n' "$stack"
  fi
}

# Return a recommended test command for a detected stack.
# Empty output for unknown stacks — caller decides how to handle.
mb_detect_test_cmd() {
  case "${1:-}" in
    python) printf '%s\n' "pytest -q" ;;
    go)     printf '%s\n' "go test ./..." ;;
    rust)   printf '%s\n' "cargo test" ;;
    node)   printf '%s\n' "npm test" ;;
    multi)  printf '%s\n' "pytest -q" ;;
    *)      : ;;
  esac
}

# Return a recommended lint command for a detected stack.
mb_detect_lint_cmd() {
  case "${1:-}" in
    python) printf '%s\n' "ruff check ." ;;
    go)     printf '%s\n' "go vet ./..." ;;
    rust)   printf '%s\n' "cargo clippy -- -D warnings" ;;
    node)   printf '%s\n' "eslint ." ;;
    multi)  printf '%s\n' "ruff check ." ;;
    *)      : ;;
  esac
}

# Return a source-file glob pattern for the detected stack.
mb_detect_src_glob() {
  case "${1:-}" in
    python) printf '%s\n' "**/*.py" ;;
    go)     printf '%s\n' "**/*.go" ;;
    rust)   printf '%s\n' "**/*.rs" ;;
    node)   printf '%s\n' "**/*.ts **/*.tsx **/*.js **/*.jsx" ;;
    multi)  printf '%s\n' "**/*.py" ;;
    *)      : ;;
  esac
}

# Sanitize a free-form topic into a filename-safe slug.
# Lowercase, spaces → dashes, keep only [a-z0-9-], squeeze repeated dashes.
mb_sanitize_topic() {
  local input="${1:-}"
  printf '%s' "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' ' '-' \
    | tr -cd 'a-z0-9-' \
    | tr -s '-'
}

# Return a collision-free filename by appending _2, _3, ... before the extension.
# Preserves the original extension when one is present.
mb_collision_safe_filename() {
  local path="${1:?path required}"

  if [ ! -e "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi

  local dir base stem ext
  dir=$(dirname "$path")
  base=$(basename "$path")

  if [[ "$base" == *.* ]]; then
    ext=".${base##*.}"
    stem="${base%.*}"
  else
    ext=""
    stem="$base"
  fi

  local i=2 candidate
  while :; do
    candidate="$dir/${stem}_${i}${ext}"
    if [ ! -e "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    i=$((i + 1))
  done
}
