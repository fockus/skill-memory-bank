#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SKILL_DIR/.installed-manifest.json"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
CURSOR_DIR="$HOME/.cursor"
OPENCODE_DIR="$HOME/.config/opencode"
CODEX_START_MARKER="<!-- memory-bank-codex:start -->"
CODEX_END_MARKER="<!-- memory-bank-codex:end -->"
GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/_lib.sh"

managed_roots=("$CLAUDE_DIR" "$CODEX_DIR" "$CURSOR_DIR" "$OPENCODE_DIR")
NON_INTERACTIVE=0

run_texttool() {
  PYTHONPATH="$SKILL_DIR${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m memory_bank_skill._texttools "$@"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: uninstall.sh [-y|--non-interactive]

  -y, --non-interactive   Skip confirmation prompt and uninstall immediately.
EOF
      exit 0
      ;;
    *)
      echo "[uninstall.sh] unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

echo -e "\n${BOLD}═══ Uninstalling skill-memory-bank ═══${NC}\n"

if [ ! -f "$MANIFEST" ]; then
  echo -e "${RED}No manifest found.${NC} Manual cleanup:"
  echo "  rm ~/.claude/commands/{mb,adr,plan,start,done,commit,review,test,doc,pr,changelog,catchup,refactor,security-review,contract,api-contract,db-migration,observability}.md"
  echo "  rm ~/.claude/agents/{mb-doctor,mb-manager,plan-verifier,mb-codebase-mapper}.md"
  echo "  rm ~/.claude/hooks/{block-dangerous,file-change-log}.sh"
  echo "  rm -rf ~/.claude/skills/{skill-memory-bank,memory-bank}"
  echo "  rm -rf ~/.codex/skills/memory-bank"
  echo "  edit ~/.codex/AGENTS.md and remove the memory-bank-codex block"
  exit 1
fi

if [ "$NON_INTERACTIVE" -eq 0 ]; then
  echo -n "Remove all memory-bank files? (y/n): "
  read -r c
  [ "$c" != "y" ] && exit 0
fi

echo -e "\n${BLUE}Removing files...${NC}"
MANIFEST_PATH="$MANIFEST" python3 -c "import json, os; [print(f) for f in json.load(open(os.environ['MANIFEST_PATH'])).get('files',[])]" 2>/dev/null | while read -r filepath; do
  [ -z "$filepath" ] && continue
  case "$filepath" in
    "$CLAUDE_DIR/CLAUDE.md"|"$CLAUDE_DIR/settings.json"|"$OPENCODE_DIR/AGENTS.md"|"$CODEX_DIR/AGENTS.md"|"$CURSOR_DIR/AGENTS.md"|"$CURSOR_DIR/hooks.json")
      echo "  keep $filepath (managed merged file)"
      continue
      ;;
  esac
  if [ -e "$filepath" ] || [ -L "$filepath" ]; then
    if mb_path_is_within "$filepath" "${managed_roots[@]}"; then
      rm -rf "$filepath" && echo "  rm $filepath"
    else
      echo "  [SKIP] $filepath (outside managed dirs)"
    fi
  fi
done

echo -e "\n${BLUE}Restoring backups...${NC}"
MANIFEST_PATH="$MANIFEST" python3 -c "import json, os; [print(b) for b in json.load(open(os.environ['MANIFEST_PATH'])).get('backups',[])]" 2>/dev/null | while read -r bp; do
  [ -n "$bp" ] && echo "$bp" | grep -q '|' && {
    orig="${bp%%|*}"; bak="${bp##*|}"
    if mb_path_is_within "$orig" "${managed_roots[@]}"; then
      { [ -e "$bak" ] || [ -L "$bak" ]; } && mv "$bak" "$orig" && echo "  restored $orig"
    else
      echo "  [SKIP] $orig (outside managed dirs)"
    fi
  }
done

echo -e "\n${BLUE}Cleaning settings.json...${NC}"
[ -f "$CLAUDE_DIR/settings.json" ] && SETTINGS_PATH="$CLAUDE_DIR/settings.json" python3 << 'PYEOF' 2>/dev/null || true
import json, os
settings_path = os.environ["SETTINGS_PATH"]
with open(settings_path) as f: s=json.load(f)
h=s.get('hooks',{})
for e in list(h.keys()):
  if isinstance(h[e],list):
    h[e]=[x for x in h[e] if not isinstance(x, dict) or not any(
      '[memory-bank-skill]' in hk.get('command', '')
      for hk in x.get('hooks', []) if isinstance(hk, dict)
    )]
s['hooks']=h
import tempfile
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(settings_path) or '.', suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w') as f: json.dump(s,f,indent=2,ensure_ascii=False)
    os.replace(tmp_path, settings_path)
except BaseException:
    os.unlink(tmp_path)
    raise
print('  Hooks cleaned')
PYEOF

# Clean CLAUDE.md MB section
[ -f "$CLAUDE_DIR/CLAUDE.md" ] && grep -q "\[MEMORY-BANK-SKILL\]" "$CLAUDE_DIR/CLAUDE.md" && run_texttool strip-after-marker --path "$CLAUDE_DIR/CLAUDE.md" --marker "# [MEMORY-BANK-SKILL]" 2>/dev/null && echo "  CLAUDE.md cleaned" || true

# Clean OpenCode AGENTS.md MB section
[ -f "$OPENCODE_DIR/AGENTS.md" ] && grep -q "memory-bank:start" "$OPENCODE_DIR/AGENTS.md" && run_texttool strip-between-markers --path "$OPENCODE_DIR/AGENTS.md" --start-marker "<!-- memory-bank:start -->" --end-marker "<!-- memory-bank:end -->" 2>/dev/null && echo "  OpenCode AGENTS.md cleaned" || true

# Clean Codex AGENTS.md MB section
[ -f "$CODEX_DIR/AGENTS.md" ] && grep -q "memory-bank-codex:start" "$CODEX_DIR/AGENTS.md" && run_texttool strip-between-markers --path "$CODEX_DIR/AGENTS.md" --start-marker "$CODEX_START_MARKER" --end-marker "$CODEX_END_MARKER" 2>/dev/null && echo "  Codex AGENTS.md cleaned" || true

# Cursor global cleanup lives in adapters/cursor.sh
if [ -f "$CURSOR_DIR/.mb-manifest.json" ]; then
  bash "$SKILL_DIR/adapters/cursor.sh" uninstall-global >/dev/null && echo "  Cursor global adapter cleaned"
fi

rm -f "$MANIFEST"
rmdir "$CLAUDE_DIR/skills" 2>/dev/null || true
rmdir "$CODEX_DIR/skills" 2>/dev/null || true
rmdir "$CURSOR_DIR/skills" 2>/dev/null || true
rmdir "$CURSOR_DIR/hooks" 2>/dev/null || true
rmdir "$CURSOR_DIR/commands" 2>/dev/null || true
rmdir "$OPENCODE_DIR/commands" 2>/dev/null || true
rmdir "$OPENCODE_DIR" 2>/dev/null || true

echo -e "\n${GREEN}═══ Uninstalled ═══${NC}\n  Project .memory-bank/ dirs untouched.\n"
