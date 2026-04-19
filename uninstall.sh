#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SKILL_DIR/.installed-manifest.json"
CLAUDE_DIR="$HOME/.claude"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "\n${BOLD}═══ Uninstalling claude-skill-memory-bank ═══${NC}\n"

if [ ! -f "$MANIFEST" ]; then
  echo -e "${RED}No manifest found.${NC} Manual cleanup:"
  echo "  rm ~/.claude/commands/{mb,adr,plan,start,done,commit,review,test,doc,pr,changelog,catchup,refactor,security-review,contract,api-contract,db-migration,observability}.md"
  echo "  rm ~/.claude/agents/{mb-doctor,mb-manager,plan-verifier,mb-codebase-mapper}.md"
  echo "  rm ~/.claude/hooks/{block-dangerous,file-change-log}.sh"
  echo "  rm -rf ~/.claude/skills/memory-bank"
  exit 1
fi

echo -n "Remove all memory-bank files? (y/n): "; read -r c; [ "$c" != "y" ] && exit 0

echo -e "\n${BLUE}Removing files...${NC}"
MANIFEST_PATH="$MANIFEST" python3 -c "import json, os; [print(f) for f in json.load(open(os.environ['MANIFEST_PATH'])).get('files',[])]" 2>/dev/null | while read -r filepath; do
  if [ -f "$filepath" ]; then
    resolved=$(realpath -m "$filepath" 2>/dev/null) || continue
    case "$resolved" in
      "$HOME/.claude/"*) rm "$resolved" && echo "  rm $resolved" ;;
      *) echo "  [SKIP] $filepath (outside ~/.claude/)" ;;
    esac
  fi
done

echo -e "\n${BLUE}Restoring backups...${NC}"
MANIFEST_PATH="$MANIFEST" python3 -c "import json, os; [print(b) for b in json.load(open(os.environ['MANIFEST_PATH'])).get('backups',[])]" 2>/dev/null | while read -r bp; do
  [ -n "$bp" ] && echo "$bp" | grep -q '|' && {
    orig="${bp%%|*}"; bak="${bp##*|}"
    resolved_orig=$(realpath -m "$orig" 2>/dev/null) || continue
    resolved_bak=$(realpath -m "$bak" 2>/dev/null) || continue
    case "$resolved_orig" in
      "$HOME/.claude/"*) [ -f "$resolved_bak" ] && mv "$resolved_bak" "$resolved_orig" && echo "  restored $resolved_orig" ;;
      *) echo "  [SKIP] $orig (outside ~/.claude/)" ;;
    esac
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
[ -f "$CLAUDE_DIR/CLAUDE.md" ] && grep -q "\[MEMORY-BANK-SKILL\]" "$CLAUDE_DIR/CLAUDE.md" && CLAUDE_MD_PATH="$CLAUDE_DIR/CLAUDE.md" python3 << 'PYEOF' 2>/dev/null || true
import os
claude_md = os.environ["CLAUDE_MD_PATH"]
c=open(claude_md).read()
m='# [MEMORY-BANK-SKILL]'
if m in c:
    import tempfile
    new_content = c[:c.index(m)].rstrip()+'\n'
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(claude_md) or '.', suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f: f.write(new_content)
        os.replace(tmp_path, claude_md)
    except BaseException:
        os.unlink(tmp_path)
        raise
print('  CLAUDE.md cleaned')
PYEOF

rm -f "$MANIFEST"
rmdir "$CLAUDE_DIR/skills/memory-bank/"{scripts,references,agents} 2>/dev/null || true
rmdir "$CLAUDE_DIR/skills/memory-bank" 2>/dev/null || true

echo -e "\n${GREEN}═══ Uninstalled ═══${NC}\n  Project .memory-bank/ dirs untouched.\n"
