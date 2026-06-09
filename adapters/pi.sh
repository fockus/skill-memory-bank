#!/usr/bin/env bash
# adapters/pi.sh — Pi Code (pi-mono) cross-agent adapter.
#
# Pi global install is handled by install.sh. This adapter adds project-local wiring.
#
#   MB_PI_MODE=agents-md  (default)  — project AGENTS.md (shared, refcount) +
#                                       git-hooks-fallback when PROJECT_ROOT is a git repo.
#                                       Safe, stable today.
#
# Compatibility path:
#   MB_PI_MODE=skill adapters/pi.sh install [PROJECT_ROOT]
#                                       Native ~/.pi/agent/skills/memory-bank/ package.
#
# Usage:
#   adapters/pi.sh install [PROJECT_ROOT]
#   adapters/pi.sh uninstall [PROJECT_ROOT]
#
# Switch: MB_PI_MODE=skill adapters/pi.sh install [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[pi-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ADAPTERS_DIR="$SKILL_DIR/adapters"
GIT_FALLBACK="$ADAPTERS_DIR/git-hooks-fallback.sh"
MANIFEST="$PROJECT_ROOT/.mb-pi-manifest.json"

MODE="${MB_PI_MODE:-agents-md}"

# shellcheck source=./_lib_agents_md.sh
. "$(dirname "$0")/_lib_agents_md.sh"
# shellcheck source=../scripts/_lib.sh
. "$SKILL_DIR/scripts/_lib.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

# ═══ Skill mode (native ~/.pi/agent/skills/memory-bank/) ═══
PI_AGENT_DIR="$HOME/.pi/agent"
PI_SKILL_DIR="$PI_AGENT_DIR/skills/memory-bank"
PI_START_MARKER="<!-- memory-bank-pi:start -->"
PI_END_MARKER="<!-- memory-bank-pi:end -->"

pi_global_agents_section() {
  cat <<EOF
$PI_START_MARKER

# Memory Bank — Pi Global Entry Point

Global Memory Bank skill is registered at:
- \`~/.pi/agent/skills/memory-bank/SKILL.md\`

Pi loads this file at startup and injects it into the agent prompt. Treat the section below as always-on Memory Bank guidance.

Bundled resources available to Pi:
- Slash prompt templates: \`~/.pi/agent/prompts/\` (for \`/mb\`, \`/start\`, \`/done\`, \`/plan\`, etc.)
- Skill resources: \`~/.pi/agent/skills/memory-bank/{commands,agents,hooks,scripts,references,rules}/\`

Recommended workflow:
- If \`./.memory-bank/\` exists, Memory Bank is active: read \`status.md\`, \`checklist.md\`, \`roadmap.md\`, and \`research.md\` at session start.
- Use \`/mb start\` to restore project context and \`/mb done\` to save progress.
- Before implementation, prefer \`/mb plan <feature|fix|refactor|experiment> <topic>\` and follow TDD.
- Detailed rules live at \`~/.pi/agent/skills/memory-bank/rules/RULES.md\`.

### Mandatory \`/mb work\` execution gate

When Memory Bank is ACTIVE and the user asks to implement, fix, continue, resume, "do the next step", "go by the plan", or work from an existing plan/spec, **do not implement manually first**. Before editing production code or restoring paused WIP, resolve the Memory Bank work item and workflow:

1. Resolve the effective workflow from \`<bank>/pipeline.yaml\` via \`mb-workflow.sh\` (default may be project-specific, e.g. governed execution).
2. Resolve the target/range via \`mb-work-resolve.sh\` and \`mb-work-plan.sh\`; spec tasks with \`<!-- mb-task:N -->\` are executable source of truth.
3. If a wrapper plan points to a spec, ensure \`linked_spec\` is present; if no executable \`mb-stage\`/\`mb-task\` exists, stop and repair the plan/spec before implementation.
4. Follow the resolved workflow steps exactly (\`implement\`, \`verify\`, \`review\`, \`judge\`, \`fix\`, \`done\`). If \`review\`/\`judge\` are configured, do not claim completion before those gates or an explicit user-approved workflow override.
5. Dispatch agents with the exact \`model\` and \`thinking\` from the JSON line / \`pipeline.yaml\`; never rely on fuzzy model aliases or agent frontmatter defaults.
6. Manual inline work is allowed only for trivial non-plan tasks or when the user explicitly says to skip \`/mb work\`; still apply TDD and verification.

This gate exists to prevent the agent from rationalizing around Memory Bank after compaction, stash restores, or mid-session pivots.

## Core Memory Bank rules

EOF
  sed 's#~/.claude/RULES.md#~/.pi/agent/skills/memory-bank/rules/RULES.md#g; s#~/.claude/skills/memory-bank#~/.pi/agent/skills/memory-bank#g' "$SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  cat <<EOF

$PI_END_MARKER
EOF
}

install_pi_global_agents() {
  local agents_file="$PI_AGENT_DIR/AGENTS.md"
  local tmp section_tmp
  mkdir -p "$PI_AGENT_DIR"
  section_tmp="$(mktemp)"
  pi_global_agents_section > "$section_tmp"

  if [ -f "$agents_file" ] && grep -q "$PI_START_MARKER" "$agents_file" 2>/dev/null; then
    tmp="$agents_file.tmp"
    awk -v s="$PI_START_MARKER" -v e="$PI_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_file" > "$tmp"
    {
      if grep -q '[^[:space:]]' "$tmp"; then
        awk 'NF { last=NR } { lines[NR]=$0 } END { for (i=1; i<=last; i++) print lines[i] }' "$tmp"
        printf '\n\n'
      fi
      cat "$section_tmp"
    } > "$agents_file"
    rm -f "$tmp" "$section_tmp"
    return 0
  fi

  if [ -f "$agents_file" ]; then
    {
      printf '\n'
      cat "$section_tmp"
    } >> "$agents_file"
    rm -f "$section_tmp"
    return 0
  fi

  mv "$section_tmp" "$agents_file"
}

install_pi_settings_skill() {
  local settings_file="$PI_AGENT_DIR/settings.json"
  mkdir -p "$PI_AGENT_DIR"

  SETTINGS_FILE="$settings_file" python3 <<'PYEOF'
import json
import os
from pathlib import Path

path = Path(os.environ["SETTINGS_FILE"])
skill = "~/.pi/agent/skills/memory-bank"

if path.exists():
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid Pi settings.json, refusing to overwrite: {exc}")
    if not isinstance(data, dict):
        raise SystemExit("invalid Pi settings.json: root must be an object")
else:
    data = {}

raw_skills = data.get("skills", [])
if raw_skills is None:
    raw_skills = []
if not isinstance(raw_skills, list):
    raise SystemExit("invalid Pi settings.json: skills must be an array")

skills = []
for item in [skill, *raw_skills]:
    if item not in skills:
        skills.append(item)

data["skills"] = skills
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PYEOF
}

install_skill_mode() {
  install_pi_global_agents
  install_pi_settings_skill

  if [ -L "$PI_SKILL_DIR" ]; then
    adapter_write_manifest \
      "$MANIFEST" \
      "pi" \
      "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
      '[]' \
      '{"mode": "skill", "pi_skill_dir": "", "global_skill_alias_detected": true}'
    echo "[pi-adapter] global Pi skill alias already exists; leaving it unchanged"
    return 0
  fi

  mkdir -p "$PI_SKILL_DIR"

  # Minimal Agent Skills-compatible SKILL.md for Pi discovery.
  {
    echo '---'
    echo 'name: memory-bank'
    echo 'description: "Memory Bank — long-term project memory + dev toolkit"'
    echo 'version: '"$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)"
    echo '---'
    echo ''
    echo '# Memory Bank — Pi Skill'
    echo ''
    echo 'Long-term project memory via `.memory-bank/` + dev workflow rules.'
    echo ''
    echo '**Workflow:**'
    # shellcheck disable=SC2016
    echo '- Start of session: read `.memory-bank/status.md`, `checklist.md`, `roadmap.md`, `research.md`'
    # shellcheck disable=SC2016
    echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
    echo ''
    if [ -f "$SKILL_DIR/rules/RULES.md" ]; then
      echo '---'
      echo ''
      echo '# Global Rules'
      echo ''
      mb_emit_rules_file "$SKILL_DIR/rules/RULES.md"
    fi
  } > "$PI_SKILL_DIR/SKILL.md"

  local files_json
  files_json=$(printf '%s\n' "$PI_SKILL_DIR/SKILL.md" | adapter_json_array_from_lines)

  adapter_write_manifest \
    "$MANIFEST" \
    "pi" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"mode\": \"skill\", \"pi_skill_dir\": $(jq -Rn --arg p "$PI_SKILL_DIR" '$p')}"

  echo "[pi-adapter] installed (mode: skill, path: $PI_SKILL_DIR)"
}

uninstall_skill_mode() {
  local skill_path
  skill_path=$(jq -r '.pi_skill_dir // empty' "$MANIFEST")
  if [ -n "$skill_path" ] && [ -d "$skill_path" ]; then
    if mb_path_is_within "$skill_path" "$HOME/.pi/agent/skills"; then
      rm -rf "$skill_path"
    else
      echo "[pi-adapter] skip unsafe manifest path: $skill_path" >&2
    fi
  fi
  rm -f "$MANIFEST"
  # Clean empty parent dirs
  rmdir "$HOME/.pi/agent/skills" 2>/dev/null || true
  rmdir "$HOME/.pi/agent" 2>/dev/null || true
  rmdir "$HOME/.pi" 2>/dev/null || true
}

# ═══ AGENTS.md mode (default) ═══
install_agents_md_mode() {
  local owned git_hooks_installed graph_ext_installed
  owned=$(agents_md_install "$PROJECT_ROOT" "pi" "$SKILL_DIR")
  git_hooks_installed=false
  if [ -d "$PROJECT_ROOT/.git" ]; then
    bash "$GIT_FALLBACK" install "$PROJECT_ROOT" >/dev/null
    git_hooks_installed=true
  else
    echo "[pi-adapter] project is not a git repo; installed AGENTS.md only" >&2
  fi

  graph_ext_installed=$(_install_graph_rag_extension)

  adapter_write_manifest \
    "$MANIFEST" \
    "pi" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "[\"$PROJECT_ROOT/.pi/extensions/memory-bank-graph-rag.ts\"]" \
    "{\"mode\": \"agents-md\", \"agents_md_owned\": $owned, \"git_hooks_installed\": $git_hooks_installed, \"graph_ext_installed\": $graph_ext_installed}"

  echo "[pi-adapter] installed (mode: agents-md)"
}

# Copy adapters/pi_graph_rag_extension.ts → $PROJECT_ROOT/.pi/extensions/.
# Provides native Pi tool wrappers (code_context, graph_neighbors,
# graph_impact, graph_tests) that delegate to scripts/mb-*-query.py and
# scripts/mb-code-context.py. Fail-open contract: missing source file
# is not fatal — returns "false" so caller can record skipped state.
_install_graph_rag_extension() {
  local src="$SKILL_DIR/adapters/pi_graph_rag_extension.ts"
  local dest="$PROJECT_ROOT/.pi/extensions/memory-bank-graph-rag.ts"
  if [ ! -f "$src" ]; then
    echo "false"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "true"
}

uninstall_agents_md_mode() {
  local installed_git installed_graph_ext
  installed_git=$(jq -r '.git_hooks_installed // false' "$MANIFEST")
  installed_graph_ext=$(jq -r '.graph_ext_installed // false' "$MANIFEST")

  agents_md_uninstall "$PROJECT_ROOT" "pi"

  if [ "$installed_git" = "true" ]; then
    bash "$GIT_FALLBACK" uninstall "$PROJECT_ROOT" >/dev/null
  fi

  if [ "$installed_graph_ext" = "true" ]; then
    rm -f "$PROJECT_ROOT/.pi/extensions/memory-bank-graph-rag.ts"
    rmdir "$PROJECT_ROOT/.pi/extensions" 2>/dev/null || true
    rmdir "$PROJECT_ROOT/.pi" 2>/dev/null || true
  fi

  rm -f "$MANIFEST"
}

# ═══ Dispatch ═══
install_pi() {
  adapter_require_jq "pi-adapter" || exit 1
  case "$MODE" in
    skill)
      install_skill_mode
      ;;
    agents-md) install_agents_md_mode ;;
    *)
      echo "[pi-adapter] unknown MB_PI_MODE=$MODE (expected: agents-md|skill)" >&2
      exit 1
      ;;
  esac
}

uninstall_pi() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[pi-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "pi-adapter" || exit 1
  local installed_mode
  installed_mode=$(jq -r '.mode // "agents-md"' "$MANIFEST")
  case "$installed_mode" in
    skill)     uninstall_skill_mode ;;
    agents-md) uninstall_agents_md_mode ;;
    *)
      echo "[pi-adapter] unknown mode in manifest: $installed_mode" >&2
      exit 1
      ;;
  esac
  echo "[pi-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_pi ;;
  uninstall) uninstall_pi ;;
  *)
    echo "Usage: [MB_PI_MODE=agents-md|skill] $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac

adapter_contract_require_functions install_pi uninstall_pi >/dev/null
