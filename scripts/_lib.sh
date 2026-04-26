#!/usr/bin/env bash
# _lib.sh — shared utilities for Memory Bank scripts.
# Source from other scripts: source "$(dirname "$0")/_lib.sh"
#
# All functions print their output to stdout and return 0 on success.
# They avoid `exit` so sourcing scripts stay in control.
#
# Strict mode is propagated to the sourcing shell so consumers that forgot
# `set -euo pipefail` still inherit fail-fast behaviour. Library functions
# remain non-fatal — they return non-zero, never `exit`.

# shellcheck shell=bash

set -euo pipefail

# Resolve MB path from explicit arg or .claude-workspace file in cwd.
# Falls back to ".memory-bank" (relative path) when nothing else is known.
mb_normalize_path() {
  local path="${1:-}"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" <<'PY'
import os
import sys

print(os.path.abspath(os.path.normpath(sys.argv[1])))
PY
    return 0
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$path" 2>/dev/null && return 0
  fi
  printf '%s\n' "$path"
}

mb_resolve_real_path() {
  local path="${1:-}"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
    return 0
  fi
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$path" 2>/dev/null && return 0
  fi
  mb_normalize_path "$path"
}

mb_path_is_within() {
  local candidate root normalized_candidate normalized_root
  candidate="${1:-}"
  shift || true
  normalized_candidate=$(mb_normalize_path "$candidate")
  for root in "$@"; do
    normalized_root=$(mb_normalize_path "$root")
    case "$normalized_candidate" in
      "$normalized_root"|"$normalized_root"/*) return 0 ;;
    esac
  done
  return 1
}

mb_mtime() {
  local path="${1:-}"
  [ -e "$path" ] || {
    printf '%s\n' 0
    return 0
  }
  stat -f%m "$path" 2>/dev/null || stat -c%Y "$path" 2>/dev/null || printf '%s\n' 0
}

mb_valid_workspace_project_id() {
  local project_id="${1:-}"
  [[ "$project_id" =~ ^[A-Za-z0-9_-]+$ ]]
}

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
      if [ -n "$project_id" ] && mb_valid_workspace_project_id "$project_id"; then
        printf '%s\n' "$HOME/.claude/workspaces/$project_id/.memory-bank"
        return 0
      fi
    fi
  fi

  printf '%s\n' ".memory-bank"
}

# Detect project stack by scanning manifest files in a directory.
# Outputs one of: python, go, rust, node, java, kotlin, swift, cpp, multi, unknown.
#
# Java vs Kotlin resolution:
#   - build.gradle.kts OR apply plugin: 'kotlin' in build.gradle → kotlin
#   - pom.xml OR build.gradle (without the Kotlin marker) → java
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

  # Kotlin takes priority over Java (overlapping Gradle manifests)
  if [ -f "$dir/build.gradle.kts" ] || \
     { [ -f "$dir/build.gradle" ] && grep -qE "plugin.*kotlin|kotlin\(" "$dir/build.gradle" 2>/dev/null; }; then
    count=$((count + 1))
    stack="kotlin"
  elif [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ]; then
    count=$((count + 1))
    stack="java"
  fi

  if [ -f "$dir/Package.swift" ]; then
    count=$((count + 1))
    stack="swift"
  fi

  if [ -f "$dir/CMakeLists.txt" ] || [ -f "$dir/meson.build" ]; then
    count=$((count + 1))
    stack="cpp"
  fi

  if [ -f "$dir/Gemfile" ] || [ -f "$dir/Rakefile" ] || [ -f "$dir/Gemfile.lock" ]; then
    count=$((count + 1))
    stack="ruby"
  fi

  if [ -f "$dir/composer.json" ]; then
    count=$((count + 1))
    stack="php"
  fi

  # C# / .NET: .csproj/.fsproj/.sln — glob-matched, `compgen` for portability
  if compgen -G "$dir/*.csproj" >/dev/null 2>&1 \
     || compgen -G "$dir/*.sln" >/dev/null 2>&1 \
     || compgen -G "$dir/*.fsproj" >/dev/null 2>&1 \
     || [ -f "$dir/global.json" ]; then
    count=$((count + 1))
    stack="csharp"
  fi

  if [ -f "$dir/mix.exs" ]; then
    count=$((count + 1))
    stack="elixir"
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
# Defaults are conventional; projects with unusual setup should override via
# .memory-bank/metrics.sh.
mb_detect_test_cmd() {
  case "${1:-}" in
    python) printf '%s\n' "pytest -q" ;;
    go)     printf '%s\n' "go test ./..." ;;
    rust)   printf '%s\n' "cargo test" ;;
    node)   printf '%s\n' "npm test" ;;
    java)   printf '%s\n' "mvn test" ;;
    kotlin) printf '%s\n' "gradle test" ;;
    swift)  printf '%s\n' "swift test" ;;
    cpp)    printf '%s\n' "ctest --output-on-failure" ;;
    ruby)   printf '%s\n' "bundle exec rspec" ;;
    php)    printf '%s\n' "vendor/bin/phpunit" ;;
    csharp) printf '%s\n' "dotnet test" ;;
    elixir) printf '%s\n' "mix test" ;;
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
    java)   printf '%s\n' "mvn checkstyle:check" ;;
    kotlin) printf '%s\n' "detekt" ;;
    swift)  printf '%s\n' "swiftlint" ;;
    cpp)    printf '%s\n' "cppcheck --enable=all --quiet ." ;;
    ruby)   printf '%s\n' "rubocop" ;;
    php)    printf '%s\n' "vendor/bin/phpstan analyse" ;;
    csharp) printf '%s\n' "dotnet format --verify-no-changes" ;;
    elixir) printf '%s\n' "mix credo --strict" ;;
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
    java)   printf '%s\n' "**/*.java" ;;
    kotlin) printf '%s\n' "**/*.kt **/*.kts" ;;
    swift)  printf '%s\n' "**/*.swift" ;;
    cpp)    printf '%s\n' "**/*.cpp **/*.cc **/*.cxx **/*.hpp **/*.h" ;;
    ruby)   printf '%s\n' "**/*.rb" ;;
    php)    printf '%s\n' "**/*.php" ;;
    csharp) printf '%s\n' "**/*.cs" ;;
    elixir) printf '%s\n' "**/*.ex **/*.exs" ;;
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
