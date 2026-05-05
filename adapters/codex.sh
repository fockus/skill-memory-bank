#!/usr/bin/env bash
# adapters/codex.sh — OpenAI Codex CLI cross-agent adapter.
#
# Codex reads AGENTS.md for project instructions (shared format with OpenCode
# and Pi fallback). Project-level settings live in .codex/config.toml.
# Codex hooks live in .codex/hooks.json (UserPromptSubmit stable,
# broader lifecycle hooks still evolving).
#
# Usage:
#   adapters/codex.sh install [PROJECT_ROOT]
#   adapters/codex.sh uninstall [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[codex-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CODEX_DIR="$PROJECT_ROOT/.codex"
CONFIG_TOML="$CODEX_DIR/config.toml"
HOOKS_JSON="$CODEX_DIR/hooks.json"
MANIFEST="$CODEX_DIR/.mb-manifest.json"

# shellcheck source=./_lib_agents_md.sh
. "$(dirname "$0")/_lib_agents_md.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

# ═══ config.toml template ═══
config_toml_body() {
  cat <<'TOML_EOF'
# Memory Bank — Codex project settings
# memory-bank: managed config (do not remove marker line)

# Read up to this many bytes from AGENTS.md (project doc discovery)
project_doc_max_bytes = 65536

# Fallback filenames when AGENTS.md is missing at a directory level
project_doc_fallback_filenames = ["CLAUDE.md", "CURSOR.md"]

# Approval policy — MB recommends on-request for defense-in-depth
approval_policy = "on-request"
TOML_EOF
}

# ═══ hooks.json body (UserPromptSubmit command schema) ═══
hooks_json_body() {
  cat <<'JSON_EOF'
{
  "version": 1,
  "_mb_warning": "Codex lifecycle hooks are still evolving. Re-run `adapters/codex.sh install` after Codex CLI upgrades.",
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .codex/hooks/before-prompt.sh",
            "timeout": 10,
            "statusMessage": "Memory Bank prompt guard",
            "_mb_owned": true
          }
        ]
      }
    ]
  }
}
JSON_EOF
}

# Pre-prompt guard script
before_prompt_body() {
  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# Codex UserPromptSubmit — block dangerous payloads
# memory-bank: managed hook
set -u
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
case "$PROMPT" in
  *"rm -rf /"*|*"rm -rf ~"*|*":(){ :|:& };:"*)
    jq -n \
      --arg reason "[MB-codex] BLOCKED dangerous prompt payload" \
      '{decision:"block", reason:$reason}'
    exit 0
    ;;
esac
exit 0
HOOK_EOF
}

# ═══ Install ═══
install_codex() {
  adapter_require_jq "codex-adapter" || exit 1
  mkdir -p "$CODEX_DIR/hooks"

  # 1. AGENTS.md via shared lib (refcount aware)
  local owned
  owned=$(agents_md_install "$PROJECT_ROOT" "codex" "$SKILL_DIR")

  # 2. config.toml
  config_toml_body > "$CONFIG_TOML"

  # 3. hooks.json (experimental)
  hooks_json_body > "$HOOKS_JSON"

  # 4. Pre-prompt script
  before_prompt_body > "$CODEX_DIR/hooks/before-prompt.sh"
  chmod +x "$CODEX_DIR/hooks/before-prompt.sh"

  # 5. Manifest
  local files_json
  files_json=$(printf '%s\n' "$CONFIG_TOML" "$HOOKS_JSON" "$CODEX_DIR/hooks/before-prompt.sh" | adapter_json_array_from_lines)

  adapter_write_manifest \
    "$MANIFEST" \
    "codex" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"agents_md_owned\": $owned, \"experimental_hooks\": true}"

  echo "[codex-adapter] installed to $PROJECT_ROOT (UserPromptSubmit guard enabled; lifecycle hooks evolving)"
}

# ═══ Uninstall ═══
uninstall_codex() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[codex-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "codex-adapter" || exit 1

  # 1. Remove tracked files
  adapter_remove_manifest_files "$MANIFEST"

  # 2. Decrement AGENTS.md ownership
  agents_md_uninstall "$PROJECT_ROOT" "codex"

  # 3. Remove manifest
  rm -f "$MANIFEST"

  # 4. Clean empty dirs
  rmdir "$CODEX_DIR/hooks" 2>/dev/null || true
  rmdir "$CODEX_DIR" 2>/dev/null || true

  echo "[codex-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_codex ;;
  uninstall) uninstall_codex ;;
  *)
    echo "Usage: $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac

adapter_contract_require_functions install_codex uninstall_codex >/dev/null
