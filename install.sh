#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# claude-skill-memory-bank — Installer
# Long-term project memory + global rules + 18 dev commands
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MANIFEST="$SKILL_DIR/.installed-manifest.json"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

INSTALLED_FILES=()
BACKED_UP_FILES=()

# ═══ Arg parsing ═══
VALID_CLIENTS=(claude-code cursor windsurf cline kilo opencode pi codex)
CLIENTS="claude-code"
PROJECT_ROOT="$PWD"

show_help() {
  cat <<HELP_EOF
Usage: install.sh [OPTIONS]

Installs Memory Bank (global ~/.claude/) and optionally writes cross-agent
adapters (.cursor/, .windsurf/, .clinerules/, etc.) into a project directory.

Options:
  --clients <list>        Comma-separated client list. Default: claude-code only.
                          Valid: claude-code, cursor, windsurf, cline, kilo,
                                 opencode, pi, codex
  --project-root <path>   Target directory for cross-agent adapters (default: PWD).
  --help                  Show this message.

Examples:
  install.sh                                         # Global install only
  install.sh --clients claude-code,cursor            # + .cursor/ adapter in PWD
  install.sh --clients cursor,windsurf,opencode     # Multi-client, no claude-code
HELP_EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --clients)
      CLIENTS="${2:-}"
      [ -z "$CLIENTS" ] && { echo "[install.sh] --clients requires an argument" >&2; exit 1; }
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
      [ -z "$PROJECT_ROOT" ] && { echo "[install.sh] --project-root requires an argument" >&2; exit 1; }
      shift 2
      ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      echo "[install.sh] unknown argument: $1 (use --help)" >&2
      exit 1
      ;;
  esac
done

# Validate client list
IFS=',' read -ra CLIENTS_ARR <<< "$CLIENTS"
for c in "${CLIENTS_ARR[@]}"; do
  c_trimmed="${c// /}"
  valid=0
  for v in "${VALID_CLIENTS[@]}"; do
    [ "$c_trimmed" = "$v" ] && valid=1 && break
  done
  if [ "$valid" -eq 0 ]; then
    echo "[install.sh] invalid client '$c_trimmed'. Valid: ${VALID_CLIENTS[*]}" >&2
    exit 1
  fi
done

echo ""
echo -e "${BOLD}═══ Installing claude-skill-memory-bank ═══${NC}"
echo ""
echo "  • Global RULES.md (TDD, SOLID, Clean Architecture, FSD for frontend)"
echo "  • 18 dev commands (/mb, /commit, /review, /test, etc.)"
echo "  • 4 agents (mb-doctor, mb-manager, plan-verifier, mb-codebase-mapper)"
echo "  • 2 hooks (block-dangerous, file-change-log)"
echo "  • Settings hooks (Setup, PreCompact, Stop)"
echo ""

# ═══ Step 0: Preflight dependency check ═══
# Можно skip'ать через MB_SKIP_DEPS_CHECK=1 (CI / isolated envs).
if [ "${MB_SKIP_DEPS_CHECK:-0}" != "1" ]; then
  echo -e "${BLUE}[0/7] Dependency check${NC}"
  if ! bash "$SKILL_DIR/scripts/mb-deps-check.sh" --install-hints; then
    echo ""
    echo -e "${RED}✗${NC} Required dependencies missing. Install them first and re-run install.sh."
    echo "   (Override: MB_SKIP_DEPS_CHECK=1 bash install.sh)"
    exit 1
  fi
fi

backup_if_exists() {
  if [ -f "$1" ] && [ ! -L "$1" ]; then
    local backup="$1.pre-mb-backup.$(date +%s)"
    cp "$1" "$backup"
    BACKED_UP_FILES+=("$1|$backup")
  fi
}

install_file() {
  mkdir -p "$(dirname "$2")"
  backup_if_exists "$2"
  cp "$1" "$2"
  [[ "$2" == *.sh || "$2" == *.py ]] && chmod +x "$2"
  INSTALLED_FILES+=("$2")
}

# ═══ Step 1: Rules ═══
echo -e "${BLUE}[1/7] Rules${NC}"
install_file "$SKILL_DIR/rules/RULES.md" "$CLAUDE_DIR/RULES.md"
echo -e "  ${GREEN}✓${NC} RULES.md"

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  if ! grep -q "\[MEMORY-BANK-SKILL\]" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
    printf '\n# [MEMORY-BANK-SKILL]\n' >> "$CLAUDE_DIR/CLAUDE.md"
    cat "$SKILL_DIR/rules/CLAUDE-GLOBAL.md" >> "$CLAUDE_DIR/CLAUDE.md"
    INSTALLED_FILES+=("$CLAUDE_DIR/CLAUDE.md")
    echo -e "  ${GREEN}✓${NC} CLAUDE.md (merged)"
  else
    # Already installed — do NOT add to INSTALLED_FILES (no backup = uninstall would delete it)
    echo -e "  ${YELLOW}~${NC} CLAUDE.md (already has MB section)"
  fi
else
  mkdir -p "$CLAUDE_DIR"
  {
    printf '# [MEMORY-BANK-SKILL]\n'
    cat "$SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  } > "$CLAUDE_DIR/CLAUDE.md"
  INSTALLED_FILES+=("$CLAUDE_DIR/CLAUDE.md")
  echo -e "  ${GREEN}✓${NC} CLAUDE.md (created with marker)"
fi

# ═══ Step 2: Agents ═══
echo -e "${BLUE}[2/7] Agents${NC}"
for f in "$SKILL_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  install_file "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done
echo -e "  ${GREEN}✓${NC} $(ls "$SKILL_DIR"/agents/*.md 2>/dev/null | wc -l | tr -d ' ') agents"

# ═══ Step 3: Hooks ═══
echo -e "${BLUE}[3/7] Hooks${NC}"
for f in "$SKILL_DIR"/hooks/*.sh; do
  [ -f "$f" ] || continue
  install_file "$f" "$CLAUDE_DIR/hooks/$(basename "$f")"
done
echo -e "  ${GREEN}✓${NC} $(ls "$SKILL_DIR"/hooks/*.sh 2>/dev/null | wc -l | tr -d ' ') hooks"

# ═══ Step 4: Commands ═══
echo -e "${BLUE}[4/7] Commands${NC}"
for f in "$SKILL_DIR"/commands/*.md; do
  [ -f "$f" ] || continue
  install_file "$f" "$CLAUDE_DIR/commands/$(basename "$f")"
done
echo -e "  ${GREEN}✓${NC} $(ls "$SKILL_DIR"/commands/*.md 2>/dev/null | wc -l | tr -d ' ') commands"

# ═══ Step 5: Skill files ═══
echo -e "${BLUE}[5/7] Skill data${NC}"
MB_DEST="$CLAUDE_DIR/skills/memory-bank"
mkdir -p "$MB_DEST"/{agents,scripts,references}
install_file "$SKILL_DIR/SKILL.md" "$MB_DEST/SKILL.md"
[ -f "$SKILL_DIR/VERSION" ] && install_file "$SKILL_DIR/VERSION" "$MB_DEST/VERSION"
for f in "$SKILL_DIR"/scripts/*.sh; do [ -f "$f" ] && install_file "$f" "$MB_DEST/scripts/$(basename "$f")"; done
for f in "$SKILL_DIR"/scripts/*.py; do [ -f "$f" ] && install_file "$f" "$MB_DEST/scripts/$(basename "$f")"; done
for f in "$SKILL_DIR"/references/*.md; do [ -f "$f" ] && install_file "$f" "$MB_DEST/references/$(basename "$f")"; done
echo -e "  ${GREEN}✓${NC} SKILL.md + VERSION + scripts + references"

# ═══ Step 6: Settings hooks ═══
echo -e "${BLUE}[6/7] Settings${NC}"
if [ -f "$SKILL_DIR/settings/hooks.json" ] && command -v python3 &>/dev/null; then
  python3 "$SKILL_DIR/settings/merge-hooks.py" \
    "$CLAUDE_DIR/settings.json" \
    "$SKILL_DIR/settings/hooks.json" \
    2>/dev/null && echo -e "  ${GREEN}✓${NC} Hooks merged" \
    || echo -e "  ${YELLOW}~${NC} Manual hook setup may be needed"
else
  echo -e "  ${YELLOW}~${NC} Skipped (python3 required for merge)"
fi

# ═══ Step 7: Manifest ═══
echo -e "${BLUE}[7/7] Manifest${NC}"
INSTALLED_FILES_STR="$(printf '%s\n' ${INSTALLED_FILES[@]+"${INSTALLED_FILES[@]}"})" \
BACKED_UP_STR="$(printf '%s\n' ${BACKED_UP_FILES[@]+"${BACKED_UP_FILES[@]}"})" \
MANIFEST_PATH="$MANIFEST" \
INSTALL_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
python3 << 'PYEOF' 2>/dev/null || echo '  Manifest write failed'
import json, os
files = [f for f in os.environ.get("INSTALLED_FILES_STR", "").split("\n") if f]
backups = [b for b in os.environ.get("BACKED_UP_STR", "").split("\n") if b]
manifest = {
    "installed_at": os.environ["INSTALL_DATE"],
    "skill": "claude-skill-memory-bank",
    "files": list(set(files)),
    "backups": list(set(backups))
}
with open(os.environ["MANIFEST_PATH"], "w") as f:
    json.dump(manifest, f, indent=2)
print("  Manifest saved")
PYEOF

# ═══ Step 8: Cross-agent adapters (optional) ═══
ADAPTERS_INVOKED=()
for c in "${CLIENTS_ARR[@]}"; do
  c_trimmed="${c// /}"
  [ "$c_trimmed" = "claude-code" ] && continue  # already done above
  adapter="$SKILL_DIR/adapters/$c_trimmed.sh"
  if [ ! -x "$adapter" ]; then
    echo -e "  ${YELLOW}~${NC} adapter missing or not executable: $adapter" >&2
    continue
  fi
  echo -e "${BLUE}[8/8] Cross-agent: $c_trimmed${NC}"
  if bash "$adapter" install "$PROJECT_ROOT"; then
    ADAPTERS_INVOKED+=("$c_trimmed")
  else
    echo -e "  ${RED}✗${NC} adapter $c_trimmed failed" >&2
  fi
done

echo ""
echo -e "${GREEN}═══ Memory Bank installed ═══${NC}"
if [ "${#ADAPTERS_INVOKED[@]}" -gt 0 ]; then
  echo -e "  Cross-agent adapters: ${ADAPTERS_INVOKED[*]} (project: $PROJECT_ROOT)"
fi
echo ""
echo "  Next: /mb init — init .memory-bank/ + auto-generate CLAUDE.md (--full, default)"
echo "  Uninstall: $SKILL_DIR/uninstall.sh"
echo ""
echo "  Optional — multi-language code graph (Go/JS/TS/Rust/Java via tree-sitter):"
echo "    pip install tree-sitter tree-sitter-python tree-sitter-go \\"
echo "                tree-sitter-javascript tree-sitter-typescript tree-sitter-rust tree-sitter-java"
echo "  Without these, /mb graph works for Python-only (via stdlib ast)."
echo ""
