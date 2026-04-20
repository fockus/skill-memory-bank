#!/usr/bin/env bash
# adapters/windsurf.sh — Windsurf Cascade cross-agent adapter.
#
# Windsurf Cascade Hooks: JSON config (3 levels: user/workspace/project) +
# shell commands via stdin JSON. Pre-hooks exit 2 = block action.
# Events (from docs): user-prompt-submit, model-response, tool-use (varies by version).
#
# Usage:
#   adapters/windsurf.sh install [PROJECT_ROOT]
#   adapters/windsurf.sh uninstall [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[windsurf-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WINDSURF_DIR="$PROJECT_ROOT/.windsurf"
RULES_FILE="$WINDSURF_DIR/rules/memory-bank.md"
HOOKS_JSON="$WINDSURF_DIR/hooks.json"
HOOKS_DIR="$WINDSURF_DIR/hooks"
MANIFEST="$WINDSURF_DIR/.mb-manifest.json"

EVENT_BINDINGS=(
  "user-prompt-submit:before-prompt.sh"
  "model-response:after-response.sh"
)

require_jq() { command -v jq >/dev/null 2>&1 || { echo "[windsurf-adapter] jq required" >&2; exit 1; }; }

before_prompt_body() {
  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# Windsurf user-prompt-submit — block dangerous requests
# memory-bank: managed hook
set -u
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .userPrompt // empty' 2>/dev/null || true)
CMD=$(printf '%s' "$INPUT" | jq -r '.command // empty' 2>/dev/null || true)

# Check both prompt text and any command payload
for text in "$PROMPT" "$CMD"; do
  case "$text" in
    *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf /*"*|*":(){ :|:& };:"*)
      printf '[MB-windsurf] BLOCKED dangerous payload\n' >&2
      exit 2  # Cascade pre-hook block
      ;;
  esac
done
exit 0
HOOK_EOF
}

after_response_body() {
  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# Windsurf model-response — Memory Bank auto-capture (once per session)
# memory-bank: managed hook
set -u
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.workspaceRoot // .cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

MB="$CWD/.memory-bank"
[ -d "$MB" ] || exit 0

case "${MB_AUTO_CAPTURE:-auto}" in
  off|strict) exit 0 ;;
esac

PROGRESS="$MB/progress.md"
[ -f "$PROGRESS" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // .conversationId // "ws-unknown"' 2>/dev/null || echo "ws-unknown")
SID_NORM="${SID#ws-}"
SID_PREFIX=$(printf '%s' "$SID_NORM" | cut -c1-8)
TODAY=$(date +%Y-%m-%d)

if grep -q "Auto-capture.*ws-${SID_PREFIX}" "$PROGRESS" 2>/dev/null; then
  exit 0
fi

{
  printf '\n## %s\n\n' "$TODAY"
  printf '### Auto-capture %s (ws-%s)\n' "$TODAY" "$SID_PREFIX"
  printf -- '- Windsurf Cascade session detected via model-response hook\n'
  printf -- '- Details will be restored on next /mb start\n'
} >> "$PROGRESS"
exit 0
HOOK_EOF
}

# ═══ Install ═══
install_windsurf() {
  require_jq
  mkdir -p "$WINDSURF_DIR/rules" "$HOOKS_DIR"

  # 1. Rules file (Windsurf frontmatter: trigger)
  {
    echo '---'
    echo 'trigger: always_on'
    echo '---'
    echo ''
    echo '# Memory Bank — Project Rules'
    echo ''
    echo 'This project uses Memory Bank for long-term memory + dev workflow.'
    echo ''
    echo '**Workflow:**'
    echo '- Start of session: read `.memory-bank/STATUS.md`, `checklist.md`, `plan.md`, `RESEARCH.md`'
    echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
    echo ''
    if [ -f "$SKILL_DIR/rules/RULES.md" ]; then
      echo '---'
      echo ''
      echo '# Global Rules'
      echo ''
      cat "$SKILL_DIR/rules/RULES.md"
    fi
  } > "$RULES_FILE"

  # 2. Hook scripts
  before_prompt_body > "$HOOKS_DIR/before-prompt.sh"
  after_response_body > "$HOOKS_DIR/after-response.sh"
  chmod +x "$HOOKS_DIR"/*.sh

  # 3. Build our hook config
  local our_hooks_json
  our_hooks_json=$(jq -n '{hooks: {}}')
  local binding event script cmd
  for binding in "${EVENT_BINDINGS[@]}"; do
    event="${binding%%:*}"
    script="${binding#*:}"
    cmd="bash .windsurf/hooks/$script"
    our_hooks_json=$(echo "$our_hooks_json" | jq \
      --arg event "$event" --arg cmd "$cmd" \
      '.hooks[$event] = [{command: $cmd, _mb_owned: true}]')
  done

  # 4. Merge with existing hooks.json
  local merged
  if [ -f "$HOOKS_JSON" ]; then
    merged=$(jq --slurpfile new <(echo "$our_hooks_json") '
      . as $existing |
      reduce ($new[0].hooks | keys[]) as $evt (
        $existing;
        .hooks //= {}
        | .hooks[$evt] = (
            ((.hooks[$evt] // []) | map(select((._mb_owned // false) | not)))
            + ($new[0].hooks[$evt])
          )
      )
    ' "$HOOKS_JSON")
  else
    merged="$our_hooks_json"
  fi
  echo "$merged" > "$HOOKS_JSON"

  # 5. Manifest
  local files_json events_json
  files_json=$(printf '%s\n' "$RULES_FILE" "$HOOKS_DIR"/*.sh | jq -R . | jq -s .)
  events_json=$(printf '%s\n' "${EVENT_BINDINGS[@]}" | awk -F: '{print $1}' | jq -R . | jq -s .)

  jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg skill_version "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    --argjson files "$files_json" \
    --argjson hooks_events "$events_json" \
    '{installed_at: $installed_at, adapter: "windsurf", skill_version: $skill_version, files: $files, hooks_events: $hooks_events}' \
    > "$MANIFEST"

  echo "[windsurf-adapter] installed to $PROJECT_ROOT"
}

# ═══ Uninstall ═══
uninstall_windsurf() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[windsurf-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  require_jq

  local files events
  files=$(jq -r '.files[]' "$MANIFEST")
  events=$(jq -r '.hooks_events[]' "$MANIFEST")

  local f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
  done <<< "$files"

  # Strip our-owned entries from hooks.json
  if [ -f "$HOOKS_JSON" ]; then
    local tmp="$HOOKS_JSON.tmp"
    cp "$HOOKS_JSON" "$tmp"
    local evt
    while IFS= read -r evt; do
      [ -z "$evt" ] && continue
      jq --arg e "$evt" '
        .hooks[$e] = ((.hooks[$e] // []) | map(select((._mb_owned // false) | not)))
        | if (.hooks[$e] | length) == 0 then del(.hooks[$e]) else . end
      ' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
    done <<< "$events"

    local remaining
    remaining=$(jq '.hooks | length' "$tmp")
    if [ "$remaining" -eq 0 ]; then
      rm -f "$HOOKS_JSON" "$tmp"
    else
      mv "$tmp" "$HOOKS_JSON"
    fi
  fi

  rm -f "$MANIFEST"

  rmdir "$HOOKS_DIR" 2>/dev/null || true
  rmdir "$WINDSURF_DIR/rules" 2>/dev/null || true
  rmdir "$WINDSURF_DIR" 2>/dev/null || true

  echo "[windsurf-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_windsurf ;;
  uninstall) uninstall_windsurf ;;
  *)
    echo "Usage: $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac
