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

# ─────────────────────────────────────────────────────────────────────────────
# Agent-agnostic storage resolver (Sprint 1 / global-storage-core)
# ─────────────────────────────────────────────────────────────────────────────
# Canonical config directory per supported code agent. Returns non-zero for
# unknown agents so callers can fail closed.
mb_agent_config_dir() {
  local agent="${1:-}"
  case "$agent" in
    claude-code) printf '%s\n' "$HOME/.claude" ;;
    cursor)      printf '%s\n' "$HOME/.cursor" ;;
    codex)       printf '%s\n' "$HOME/.codex" ;;
    opencode)    printf '%s\n' "$HOME/.config/opencode" ;;
    pi)          printf '%s\n' "$HOME/.pi/agent" ;;
    windsurf)    printf '%s\n' "$HOME/.windsurf" ;;
    cline)       printf '%s\n' "$HOME/.cline" ;;
    kilo)        printf '%s\n' "$HOME/.kilocode" ;;
    *)           return 1 ;;
  esac
}

# Path to the global Memory Bank registry JSON for an agent.
mb_registry_path() {
  local agent="${1:-}" base
  base=$(mb_agent_config_dir "$agent") || return 1
  printf '%s\n' "$base/memory-bank/registry.json"
}

# Deterministic key for a project — realpath plus optional git remote URL.
# Used as the SHA256 input for `mb_project_id` and as the registry lookup key
# basis. Stable across reruns; ignores the working tree state.
mb_project_key() {
  local project_root="${1:-$PWD}" real remote
  real=$(mb_resolve_real_path "$project_root")
  remote=""
  if command -v git >/dev/null 2>&1 && [ -d "$project_root/.git" ]; then
    remote=$(git -C "$project_root" config --get remote.origin.url 2>/dev/null || true)
  fi
  if [ -n "$remote" ]; then
    printf '%s|%s\n' "$real" "$remote"
  else
    printf '%s\n' "$real"
  fi
}

# Stable slug-hash id matching ^[A-Za-z0-9_-]+$. Slug = sanitized basename;
# suffix = first 12 hex chars of sha256(mb_project_key).
mb_project_id() {
  local project_root="${1:-$PWD}" key slug hash
  key=$(mb_project_key "$project_root")
  slug=$(basename "$(mb_resolve_real_path "$project_root")")
  slug=$(mb_sanitize_topic "$slug")
  [ -z "$slug" ] && slug="project"
  hash=$(printf '%s' "$key" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.read().encode()).hexdigest()[:12])')
  printf '%s-%s\n' "$slug" "$hash"
}

# Look up the registered bank path for project_root in agent's registry.
# Fails closed: missing file, malformed JSON or absent entry all return 1
# with no stdout.
mb_registry_lookup() {
  local agent="${1:-}" project_root="${2:-$PWD}" registry real
  registry=$(mb_registry_path "$agent") || return 1
  [ -f "$registry" ] || return 1
  real=$(mb_resolve_real_path "$project_root")
  python3 - "$registry" "$real" <<'PY' || return 1
import json
import sys

path, project = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)
projects = data.get("projects") or {}
entry = projects.get(project)
if entry is None:
    sys.exit(1)
bank = entry.get("bank_path") if isinstance(entry, dict) else entry
if not bank:
    sys.exit(1)
print(bank)
PY
}

# Resolve effective Memory Bank path.
#
# Precedence (first match wins):
#   1. explicit positional argument
#   2. MB_PATH env override
#   3. local <cwd>/.memory-bank/ directory
#   4. global registry hit for MB_AGENT (only if MB_AGENT is set)
#   5. legacy .claude-workspace `storage: external` pointer (backward compat)
#   6. relative ".memory-bank" fallback
mb_resolve_path() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return 0
  fi

  if [ -n "${MB_PATH:-}" ]; then
    printf '%s\n' "$MB_PATH"
    return 0
  fi

  if [ -d ".memory-bank" ]; then
    printf '%s\n' ".memory-bank"
    return 0
  fi

  if [ -n "${MB_AGENT:-}" ]; then
    local hit
    if hit=$(mb_registry_lookup "$MB_AGENT" "$PWD" 2>/dev/null) && [ -n "$hit" ]; then
      printf '%s\n' "$hit"
      return 0
    fi
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

# ─────────────────────────────────────────────────────────────────────────────
# Named pipelines — selection + host binding (project pipeline isolation)
# ─────────────────────────────────────────────────────────────────────────────
# Detect the current code-agent host id, used to auto-select the pipeline whose
# `agents:` list binds it. Always exits 0; prints the id or an empty line.
# Precedence (first match wins):
#   1. MB_PIPELINE_HOST env  (explicit per-run override)
#   2. MB_AGENT env          (canonical agent var, also used for global storage)
#   3. host environment signatures (claude-code / opencode / codex / cursor / windsurf / pi)
#   4. empty string          (unknown host — callers fall back to the declared default)
mb_detect_host() {
  if [ -n "${MB_PIPELINE_HOST:-}" ]; then
    printf '%s\n' "$MB_PIPELINE_HOST"
    return 0
  fi
  if [ -n "${MB_AGENT:-}" ]; then
    printf '%s\n' "$MB_AGENT"
    return 0
  fi
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
    printf '%s\n' "claude-code"
    return 0
  fi
  if [ -n "${OPENCODE:-}" ] || [ -n "${OPENCODE_BIN:-}" ]; then
    printf '%s\n' "opencode"
    return 0
  fi
  if [ -n "${CODEX_SANDBOX:-}" ] || [ -n "${CODEX_HOME:-}" ]; then
    printf '%s\n' "codex"
    return 0
  fi
  if [ -n "${CURSOR_TRACE_ID:-}" ] || [ -n "${CURSOR_AGENT:-}" ]; then
    printf '%s\n' "cursor"
    return 0
  fi
  if [ -n "${WINDSURF_AGENT:-}" ]; then
    printf '%s\n' "windsurf"
    return 0
  fi
  if [ -n "${PI_AGENT:-}" ]; then
    printf '%s\n' "pi"
    return 0
  fi
  printf '%s\n' ""
}

# Path to the named-pipelines directory of a bank: <bank>/pipelines.
# Resolves the bank via mb_resolve_path when no explicit arg is given.
mb_pipeline_dir() {
  local mb
  mb=$(mb_resolve_path "${1:-}")
  printf '%s/pipelines\n' "$mb"
}

# Read a top-level metadata field from a pipeline file.
#   pipeline_name → string (empty if absent)
#   default       → "true" / "false" (false if absent)
#   agents        → space-separated client ids (empty if absent)
# Uses PyYAML when present; degrades to a minimal parser for just these three
# keys when PyYAML is unavailable.
mb_pipeline_meta() {
  local file="${1:-}" field="${2:-}"
  if [ ! -f "$file" ]; then
    [ "$field" = "default" ] && printf 'false\n'
    return 0
  fi
  MB_PIPE_FILE="$file" MB_PIPE_FIELD="$field" python3 - <<'PY'
import os

path = os.environ["MB_PIPE_FILE"]
field = os.environ["MB_PIPE_FIELD"]

data = None
try:
    import yaml
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except ModuleNotFoundError:
    data = None
except Exception:
    data = {}

if data is None:
    # Minimal fallback: parse only pipeline_name / default / agents.
    data = {}
    agents = []
    in_agents = False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if in_agents:
                if stripped.startswith("- "):
                    agents.append(stripped[2:].strip().strip('"').strip("'"))
                    continue
                if line[:1] not in (" ", "\t") and stripped:
                    in_agents = False
                else:
                    continue
            if stripped.startswith("pipeline_name:"):
                data["pipeline_name"] = stripped.split(":", 1)[1].strip().strip('"').strip("'")
            elif stripped.startswith("default:"):
                data["default"] = stripped.split(":", 1)[1].strip().strip('"').strip("'")
            elif stripped.startswith("agents:"):
                rest = stripped.split(":", 1)[1].strip()
                if rest.startswith("[") and rest.endswith("]"):
                    inner = rest[1:-1].strip()
                    agents = [a.strip().strip('"').strip("'") for a in inner.split(",") if a.strip()]
                elif rest:
                    agents = [a.strip().strip('"').strip("'") for a in rest.split(",") if a.strip()]
                else:
                    in_agents = True
    if agents:
        data["agents"] = agents

if field == "default":
    val = data.get("default", False)
    if isinstance(val, bool):
        print("true" if val else "false")
    else:
        print("true" if str(val).strip().lower() in ("true", "yes", "1", "on") else "false")
elif field == "agents":
    val = data.get("agents") or []
    if isinstance(val, str):
        val = [val]
    print(" ".join(str(x) for x in val))
else:
    val = data.get(field)
    print("" if val is None else str(val))
PY
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
# Lowercase, spaces → dashes, keep only [a-z0-9.-], squeeze repeated dashes.
# Internal dots are preserved (dotted spec names like `reviewer-2.0`, version
# strings like `v1.2.3`). Leading/trailing dots are stripped so a pure-dot
# input (`.`, `..`) collapses to empty and `../x` → `x` — no path traversal:
# slashes are already removed by the charset filter, and `.`/`..` as a whole
# component is the only filesystem-special case, which the strip neutralizes.
mb_sanitize_topic() {
  local input="${1:-}"
  printf '%s' "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' ' '-' \
    | tr -cd 'a-z0-9.-' \
    | tr -s '-' \
    | sed 's/^\.*//; s/\.*$//'
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

# mb_resolve_manifest_path <skill_dir> — shared by install.sh/uninstall.sh (A12).
#
# Precedence:
#   1. $MB_MANIFEST_PATH — explicit override (tests / advanced users).
#   2. <skill_dir>/.installed-manifest.json, when skill_dir is user-writable
#      (the common case: git checkout, editable installs, a Homebrew cellar
#      you own).
#   3. ${XDG_DATA_HOME:-$HOME/.local/share}/memory-bank/.installed-manifest.json
#      — pip/sudo installs frequently place the skill under a root-owned
#      prefix (site-packages/share/...) a normal user cannot write to; silently
#      losing the manifest there means uninstall has nothing to roll back.
#
# Self-heals: if the writable co-located path has no manifest yet but the user
# fallback dir already does (e.g. an earlier unwritable install ran first),
# reuse the fallback so uninstall.sh finds what install.sh actually wrote.
mb_resolve_manifest_path() {
  local skill_dir="${1:?skill_dir required}"

  if [ -n "${MB_MANIFEST_PATH:-}" ]; then
    printf '%s\n' "$MB_MANIFEST_PATH"
    return 0
  fi

  local user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/memory-bank"
  local user_manifest="$user_dir/.installed-manifest.json"
  local local_manifest="$skill_dir/.installed-manifest.json"

  if [ -w "$skill_dir" ]; then
    if [ ! -f "$local_manifest" ] && [ -f "$user_manifest" ]; then
      printf '%s\n' "$user_manifest"
      return 0
    fi
    printf '%s\n' "$local_manifest"
    return 0
  fi

  printf '%s\n' "$user_manifest"
}
