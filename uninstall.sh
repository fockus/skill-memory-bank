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
CURSOR_START_MARKER="<!-- memory-bank-cursor:start -->"
CURSOR_END_MARKER="<!-- memory-bank-cursor:end -->"
GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

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

echo -n "Remove all memory-bank files? (y/n): "; read -r c; [ "$c" != "y" ] && exit 0

echo -e "\n${BLUE}Removing files...${NC}"
# Manifest stores absolute paths already — no realpath needed (BSD realpath has no -m flag).
MANIFEST_PATH="$MANIFEST" python3 -c "import json, os; [print(f) for f in json.load(open(os.environ['MANIFEST_PATH'])).get('files',[])]" 2>/dev/null | while read -r filepath; do
  [ -z "$filepath" ] && continue
  case "$filepath" in
    "$CLAUDE_DIR/CLAUDE.md"|"$CLAUDE_DIR/settings.json"|"$OPENCODE_DIR/AGENTS.md"|"$CODEX_DIR/AGENTS.md"|"$CURSOR_DIR/AGENTS.md"|"$CURSOR_DIR/hooks.json")
      echo "  keep $filepath (managed merged file)"
      continue
      ;;
  esac
  if [ -e "$filepath" ] || [ -L "$filepath" ]; then
    case "$filepath" in
      "$HOME/.claude/"*) rm -rf "$filepath" && echo "  rm $filepath" ;;
      "$HOME/.codex/"*) rm -rf "$filepath" && echo "  rm $filepath" ;;
      "$HOME/.cursor/"*) rm -rf "$filepath" && echo "  rm $filepath" ;;
      "$HOME/.config/opencode/"*) rm -rf "$filepath" && echo "  rm $filepath" ;;
      *) echo "  [SKIP] $filepath (outside managed dirs)" ;;
    esac
  fi
done

echo -e "\n${BLUE}Restoring backups...${NC}"
MANIFEST_PATH="$MANIFEST" python3 -c "import json, os; [print(b) for b in json.load(open(os.environ['MANIFEST_PATH'])).get('backups',[])]" 2>/dev/null | while read -r bp; do
  [ -n "$bp" ] && echo "$bp" | grep -q '|' && {
    orig="${bp%%|*}"; bak="${bp##*|}"
    case "$orig" in
      "$HOME/.claude/"*) { [ -e "$bak" ] || [ -L "$bak" ]; } && mv "$bak" "$orig" && echo "  restored $orig" ;;
      "$HOME/.codex/"*) { [ -e "$bak" ] || [ -L "$bak" ]; } && mv "$bak" "$orig" && echo "  restored $orig" ;;
      "$HOME/.cursor/"*) { [ -e "$bak" ] || [ -L "$bak" ]; } && mv "$bak" "$orig" && echo "  restored $orig" ;;
      "$HOME/.config/opencode/"*) { [ -e "$bak" ] || [ -L "$bak" ]; } && mv "$bak" "$orig" && echo "  restored $orig" ;;
      *) echo "  [SKIP] $orig (outside managed dirs)" ;;
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

# Clean OpenCode AGENTS.md MB section
[ -f "$OPENCODE_DIR/AGENTS.md" ] && grep -q "memory-bank:start" "$OPENCODE_DIR/AGENTS.md" && OPENCODE_AGENTS_PATH="$OPENCODE_DIR/AGENTS.md" python3 << 'PYEOF' 2>/dev/null || true
import os
import tempfile

agents_path = os.environ["OPENCODE_AGENTS_PATH"]
content = open(agents_path, encoding="utf-8").read().splitlines()
inside = False
kept = []
for line in content:
    if "<!-- memory-bank:start -->" in line:
        inside = True
        continue
    if inside and "<!-- memory-bank:end -->" in line:
        inside = False
        continue
    if not inside:
        kept.append(line)

new_content = "\n".join(kept).strip()
if new_content:
    new_content += "\n"
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(agents_path) or '.', suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write(new_content)
        os.replace(tmp_path, agents_path)
    except BaseException:
        os.unlink(tmp_path)
        raise
else:
    os.remove(agents_path)
print('  OpenCode AGENTS.md cleaned')
PYEOF

# Clean Codex AGENTS.md MB section
[ -f "$CODEX_DIR/AGENTS.md" ] && grep -q "memory-bank-codex:start" "$CODEX_DIR/AGENTS.md" && CODEX_AGENTS_PATH="$CODEX_DIR/AGENTS.md" CODEX_START="$CODEX_START_MARKER" CODEX_END="$CODEX_END_MARKER" python3 << 'PYEOF' 2>/dev/null || true
import os
import tempfile

agents_path = os.environ["CODEX_AGENTS_PATH"]
start = os.environ["CODEX_START"]
end = os.environ["CODEX_END"]
content = open(agents_path, encoding="utf-8").read().splitlines()
inside = False
kept = []
for line in content:
    if start in line:
        inside = True
        continue
    if inside and end in line:
        inside = False
        continue
    if not inside:
        kept.append(line)

new_content = "\n".join(kept).strip()
if new_content:
    new_content += "\n"
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(agents_path) or ".", suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            f.write(new_content)
        os.replace(tmp_path, agents_path)
    except BaseException:
        os.unlink(tmp_path)
        raise
else:
    os.remove(agents_path)
print("  Codex AGENTS.md cleaned")
PYEOF

# Clean Cursor AGENTS.md MB section
[ -f "$CURSOR_DIR/AGENTS.md" ] && grep -q "memory-bank-cursor:start" "$CURSOR_DIR/AGENTS.md" && CURSOR_AGENTS_PATH="$CURSOR_DIR/AGENTS.md" CURSOR_START="$CURSOR_START_MARKER" CURSOR_END="$CURSOR_END_MARKER" python3 << 'PYEOF' 2>/dev/null || true
import os
import tempfile

agents_path = os.environ["CURSOR_AGENTS_PATH"]
start = os.environ["CURSOR_START"]
end = os.environ["CURSOR_END"]
content = open(agents_path, encoding="utf-8").read().splitlines()
inside = False
kept = []
for line in content:
    if start in line:
        inside = True
        continue
    if inside and end in line:
        inside = False
        continue
    if not inside:
        kept.append(line)

new_content = "\n".join(kept).strip()
if new_content:
    new_content += "\n"
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(agents_path) or ".", suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            f.write(new_content)
        os.replace(tmp_path, agents_path)
    except BaseException:
        os.unlink(tmp_path)
        raise
else:
    os.remove(agents_path)
print("  Cursor AGENTS.md cleaned")
PYEOF

# Clean Cursor hooks.json from _mb_owned entries
if [ -f "$CURSOR_DIR/hooks.json" ] && command -v jq >/dev/null 2>&1; then
  CURSOR_HOOKS_PATH="$CURSOR_DIR/hooks.json" python3 << 'PYEOF' 2>/dev/null || true
import json
import os
import tempfile

hooks_path = os.environ["CURSOR_HOOKS_PATH"]
with open(hooks_path, encoding="utf-8") as f:
    data = json.load(f)

hooks = data.get("hooks", {})
cleaned = {}
for event, entries in hooks.items():
    if not isinstance(entries, list):
        cleaned[event] = entries
        continue
    kept = [e for e in entries if not (isinstance(e, dict) and e.get("_mb_owned") is True)]
    if kept:
        cleaned[event] = kept

if cleaned:
    data["hooks"] = cleaned
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(hooks_path) or ".", suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, hooks_path)
    except BaseException:
        os.unlink(tmp_path)
        raise
    print("  Cursor hooks.json cleaned (MB entries removed)")
else:
    os.remove(hooks_path)
    print("  Cursor hooks.json removed (no user hooks left)")
PYEOF
fi

# Remove Cursor User Rules paste-file (auto-generated, no user edits expected)
[ -f "$CURSOR_DIR/memory-bank-user-rules.md" ] && rm -f "$CURSOR_DIR/memory-bank-user-rules.md" && echo "  rm $CURSOR_DIR/memory-bank-user-rules.md"

rm -f "$MANIFEST"
rmdir "$CLAUDE_DIR/skills" 2>/dev/null || true
rmdir "$CODEX_DIR/skills" 2>/dev/null || true
rmdir "$CURSOR_DIR/skills" 2>/dev/null || true
rmdir "$CURSOR_DIR/hooks" 2>/dev/null || true
rmdir "$CURSOR_DIR/commands" 2>/dev/null || true
rmdir "$OPENCODE_DIR/commands" 2>/dev/null || true
rmdir "$OPENCODE_DIR" 2>/dev/null || true

echo -e "\n${GREEN}═══ Uninstalled ═══${NC}\n  Project .memory-bank/ dirs untouched.\n"
