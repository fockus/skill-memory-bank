#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# claude-skill-memory-bank — Installer
# Long-term project memory + global rules + 19 dev commands
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MANIFEST="$SKILL_DIR/.installed-manifest.json"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

INSTALLED_FILES=()
BACKED_UP_FILES=()

echo ""
echo -e "${BOLD}═══ Installing claude-skill-memory-bank ═══${NC}"
echo ""
echo "  • Global RULES.md (TDD, SOLID, Clean Architecture)"
echo "  • 19 dev commands (/mb, /commit, /review, /test, etc.)"
echo "  • 4 agents (mb-doctor, mb-manager, plan-verifier, mb-codebase-mapper)"
echo "  • 2 hooks (block-dangerous, file-change-log)"
echo "  • Settings hooks (Setup, PreCompact, Stop)"
echo ""

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
  [[ "$2" == *.sh ]] && chmod +x "$2"
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
  install_file "$SKILL_DIR/rules/CLAUDE-GLOBAL.md" "$CLAUDE_DIR/CLAUDE.md"
  echo -e "  ${GREEN}✓${NC} CLAUDE.md (created)"
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
for f in "$SKILL_DIR"/scripts/*.sh; do [ -f "$f" ] && install_file "$f" "$MB_DEST/scripts/$(basename "$f")"; done
for f in "$SKILL_DIR"/references/*.md; do [ -f "$f" ] && install_file "$f" "$MB_DEST/references/$(basename "$f")"; done
echo -e "  ${GREEN}✓${NC} SKILL.md + scripts + references"

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

echo ""
echo -e "${GREEN}═══ Memory Bank installed ═══${NC}"
echo ""
echo "  Next: /mb:setup-project — init .memory-bank/ + generate CLAUDE.md"
echo "  Uninstall: $SKILL_DIR/uninstall.sh"
echo ""
