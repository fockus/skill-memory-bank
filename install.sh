#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# skill-memory-bank — Installer
# Long-term project memory + global rules + 18 dev commands
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SOURCE_SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
CURSOR_DIR="$HOME/.cursor"
OPENCODE_DIR="$HOME/.config/opencode"
CANONICAL_SKILL_DIR="$CLAUDE_DIR/skills/skill-memory-bank"
CLAUDE_SKILL_ALIAS="$CLAUDE_DIR/skills/memory-bank"
CODEX_SKILL_ALIAS="$CODEX_DIR/skills/memory-bank"
CURSOR_SKILL_ALIAS="$CURSOR_DIR/skills/memory-bank"
CURSOR_USER_RULES_FILE="$CURSOR_DIR/memory-bank-user-rules.md"
MANIFEST="$SOURCE_SKILL_DIR/.installed-manifest.json"
CODEX_START_MARKER="<!-- memory-bank-codex:start -->"
CODEX_END_MARKER="<!-- memory-bank-codex:end -->"
CURSOR_START_MARKER="<!-- memory-bank-cursor:start -->"
CURSOR_END_MARKER="<!-- memory-bank-cursor:end -->"

# Cursor global hook scripts & event bindings (mirror adapters/cursor.sh, rooted in ~/.cursor)
CURSOR_GLOBAL_HOOKS=(
  "session-end-autosave.sh"
  "mb-compact-reminder.sh"
  "block-dangerous.sh"
)
CURSOR_GLOBAL_HOOK_BINDINGS=(
  "sessionEnd:session-end-autosave.sh"
  "preCompact:mb-compact-reminder.sh"
  "beforeShellExecution:block-dangerous.sh"
)

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

INSTALLED_FILES=()
BACKED_UP_FILES=()

# shellcheck disable=SC1091
. "$SOURCE_SKILL_DIR/adapters/_lib_agents_md.sh"

count_matching_files() {
  find "$1" -maxdepth 1 -type f -name "$2" | wc -l | tr -d ' '
}

# ═══ Arg parsing ═══
VALID_CLIENTS=(claude-code cursor windsurf cline kilo opencode pi codex)
VALID_LANGUAGES=(en ru es zh)
CLIENTS=""                  # unset sentinel — triggers interactive or default
LANGUAGE=""                 # unset sentinel — triggers interactive or default
PROJECT_ROOT="$PWD"
NON_INTERACTIVE=0

show_help() {
  cat <<HELP_EOF
Usage: install.sh [OPTIONS]

Installs Memory Bank (global ~/.claude/) and optionally writes cross-agent
adapters (.cursor/, .windsurf/, .clinerules/, etc.) into a project directory.

Options:
  --clients <list>        Comma-separated client list.
                          Valid: claude-code, cursor, windsurf, cline, kilo,
                                 opencode, pi, codex
                          If omitted and running in a TTY → interactive menu.
                          Non-TTY default: claude-code only.
  --language <code>       Preferred locale for rules + .memory-bank/ templates.
                          Valid: en, ru, es, zh
                          (es/zh ship as scaffolds awaiting community translations)
                          If omitted and running in a TTY → interactive prompt.
                          Non-TTY default: en.
  --project-root <path>   Target directory for cross-agent adapters (default: PWD).
  --non-interactive       Never prompt; use defaults when --clients not passed.
  --help                  Show this message.

Examples:
  install.sh                                         # Interactive menu (TTY)
  install.sh --non-interactive                       # claude-code only, no prompt
  install.sh --language ru                           # install Russian language rules
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
    --language)
      LANGUAGE="${2:-}"
      [ -z "$LANGUAGE" ] && { echo "[install.sh] --language requires an argument" >&2; exit 1; }
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=1; shift ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      echo "[install.sh] unknown argument: $1 (use --help)" >&2
      exit 1
      ;;
  esac
done

# ═══ Interactive client picker ═══
# Triggers only when: --clients empty AND stdin is TTY AND --non-interactive not set.
# Env override: MB_CLIENTS="claude-code,cursor" bash install.sh — skip prompt too.
if [ -z "$CLIENTS" ] && [ -n "${MB_CLIENTS:-}" ]; then
  CLIENTS="$MB_CLIENTS"
fi
if [ -z "$LANGUAGE" ] && [ -n "${MB_LANGUAGE:-}" ]; then
  LANGUAGE="$MB_LANGUAGE"
fi

interactive_pick_clients() {
  echo ""
  echo -e "${BOLD}Which AI coding agents do you want to enable?${NC}"
  echo "  Claude Code is recommended as the primary target."
  echo "  Cross-agent adapters write per-client config (.cursor/, .windsurf/, etc.)"
  echo "  into the current project ($PROJECT_ROOT)."
  echo ""
  local idx=1
  for c in "${VALID_CLIENTS[@]}"; do
    local marker=" "
    [ "$c" = "claude-code" ] && marker="*"
    printf "  [%d]%s %s\n" "$idx" "$marker" "$c"
    idx=$((idx + 1))
  done
  echo ""
  echo "  Enter numbers separated by spaces or commas (e.g. '1 2 5'),"
  echo "  'all' for every client, or press Enter for just claude-code."
  echo ""
  printf "> "
  local reply
  IFS= read -r reply </dev/tty || reply=""
  reply="${reply// /,}"         # spaces → commas
  reply="${reply//,,/,}"         # collapse double commas
  reply="${reply#,}"; reply="${reply%,}"

  if [ -z "$reply" ]; then
    CLIENTS="claude-code"
    echo "  → selected: claude-code (default)"
    return
  fi

  if [ "$reply" = "all" ]; then
    CLIENTS="$(IFS=,; echo "${VALID_CLIENTS[*]}")"
    echo "  → selected: $CLIENTS"
    return
  fi

  local picked=()
  IFS=',' read -ra parts <<< "$reply"
  for p in "${parts[@]}"; do
    p="${p// /}"
    [ -z "$p" ] && continue
    if ! [[ "$p" =~ ^[0-9]+$ ]]; then
      echo "[install.sh] invalid selection: '$p' (expected number 1-${#VALID_CLIENTS[@]})" >&2
      exit 1
    fi
    local i=$((p - 1))
    if [ "$i" -lt 0 ] || [ "$i" -ge "${#VALID_CLIENTS[@]}" ]; then
      echo "[install.sh] out of range: '$p' (valid: 1-${#VALID_CLIENTS[@]})" >&2
      exit 1
    fi
    picked+=("${VALID_CLIENTS[$i]}")
  done

  if [ "${#picked[@]}" -eq 0 ]; then
    CLIENTS="claude-code"
    echo "  → selected: claude-code (default)"
  else
    CLIENTS="$(IFS=,; echo "${picked[*]}")"
    echo "  → selected: $CLIENTS"
  fi
}

interactive_pick_language() {
  echo ""
  echo -e "${BOLD}Which language should Memory Bank rules use?${NC}"
  echo "  This controls the installed global language rule and comment-language guidance."
  echo ""
  echo "  [1]* en  English"
  echo "  [2]  ru  Russian"
  echo ""
  echo "  Press Enter for English."
  echo ""
  printf "> "
  local reply
  IFS= read -r reply </dev/tty || reply=""
  reply="${reply// /}"

  case "$reply" in
    ""|"1"|"en")
      LANGUAGE="en"
      echo "  -> selected language: en"
      ;;
    "2"|"ru")
      LANGUAGE="ru"
      echo "  -> selected language: ru"
      ;;
    *)
      echo "[install.sh] invalid language '$reply' (valid: en, ru)" >&2
      exit 1
      ;;
  esac
}

if [ -z "$CLIENTS" ]; then
  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ]; then
    CLIENTS="claude-code"
  else
    interactive_pick_clients
  fi
fi

if [ -z "$LANGUAGE" ]; then
  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ]; then
    LANGUAGE="en"
  else
    interactive_pick_language
  fi
fi

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

valid_language=0
for lang in "${VALID_LANGUAGES[@]}"; do
  [ "$LANGUAGE" = "$lang" ] && valid_language=1 && break
done
if [ "$valid_language" -eq 0 ]; then
  echo "[install.sh] invalid language '$LANGUAGE'. Valid: ${VALID_LANGUAGES[*]}" >&2
  exit 1
fi

echo ""
echo -e "${BOLD}═══ Installing skill-memory-bank ═══${NC}"
echo ""
COMMAND_COUNT="$(count_matching_files "$SOURCE_SKILL_DIR/commands" '*.md')"
AGENT_COUNT="$(count_matching_files "$SOURCE_SKILL_DIR/agents" '*.md')"
HOOK_COUNT="$(count_matching_files "$SOURCE_SKILL_DIR/hooks" '*.sh')"
SCRIPT_COUNT="$(count_matching_files "$SOURCE_SKILL_DIR/scripts" 'mb-*.sh')"
echo "  • Global RULES.md (TDD, SOLID, Clean Architecture, FSD for frontend)"
echo "  • $COMMAND_COUNT dev commands (/mb, /commit, /review, /test, etc.)"
echo "  • $AGENT_COUNT agents (mb-doctor, mb-manager, plan-verifier, mb-codebase-mapper)"
echo "  • $HOOK_COUNT hooks (block-dangerous, file-change-log, session-end-autosave, mb-compact-reminder)"
echo "  • $SCRIPT_COUNT mb-* scripts (plan-sync, plan-done, idea, idea-promote, adr, migrate-structure, compact, …)"
echo "  • Settings hooks (Setup, PreCompact, Stop)"
echo "  • Preferred language: $LANGUAGE"
echo ""

# ═══ Step 0: Preflight dependency check ═══
# Can be skipped via MB_SKIP_DEPS_CHECK=1 (CI / isolated envs).
if [ "${MB_SKIP_DEPS_CHECK:-0}" != "1" ]; then
  echo -e "${BLUE}[0/7] Dependency check${NC}"
  if ! bash "$SOURCE_SKILL_DIR/scripts/mb-deps-check.sh" --install-hints; then
    echo ""
    echo -e "${RED}✗${NC} Required dependencies missing. Install them first and re-run install.sh."
    echo "   (Override: MB_SKIP_DEPS_CHECK=1 bash install.sh)"
    exit 1
  fi
fi

backup_if_exists() {
  # Skip-when-identical backup with rotation (keeps only the latest backup).
  # Args: $1 = target path, $2 (optional) = expected content path.
  # If $2 is given and target content already matches expected, return 2 (skip marker).
  # Legacy 1-arg callers keep previous behavior: unconditional backup.
  local target="$1"
  local expected="${2:-}"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -n "$expected" ] && [ -f "$expected" ] && cmp -s "$target" "$expected"; then
      return 2
    fi
    # Rotation: remove any previous .pre-mb-backup.* for this target.
    # Prevents the "backup creep" problem (hundreds of stale backups accumulating
    # across repeat installs). We keep only the freshest snapshot.
    # Use shopt/compgen-free pattern that tolerates "no match" without nullglob.
    local old
    for old in "$target".pre-mb-backup.*; do
      [ -e "$old" ] || [ -L "$old" ] || continue
      rm -rf -- "$old"
    done
    local backup
    backup="$target.pre-mb-backup.$(date +%s)"
    mv "$target" "$backup"
    BACKED_UP_FILES+=("$target|$backup")
  fi
}

install_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  # Content-identity shortcut — avoid spurious .pre-mb-backup.* on repeat installs.
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    [[ "$dst" == *.sh || "$dst" == *.py ]] && chmod +x "$dst"
    INSTALLED_FILES+=("$dst")
    return 0
  fi

  backup_if_exists "$dst"
  cp "$src" "$dst"
  [[ "$dst" == *.sh || "$dst" == *.py ]] && chmod +x "$dst"
  INSTALLED_FILES+=("$dst")
}

language_rule_full() {
  case "$LANGUAGE" in
    en) printf '%s' "English — responses and code comments. Technical terms may remain in English." ;;
    ru) printf '%s' "Russian — responses and code comments. Technical terms may remain in English." ;;
  esac
}

language_rule_short() {
  case "$LANGUAGE" in
    en) printf '%s' "respond in English; technical terms may remain in English." ;;
    ru) printf '%s' "respond in Russian; technical terms may remain in English." ;;
  esac
}

comments_language_name() {
  case "$LANGUAGE" in
    en) printf '%s' "English" ;;
    ru) printf '%s' "Russian" ;;
  esac
}

localize_installed_file() {
  local file="$1"
  local after_marker="${2:-}"
  TARGET_FILE="$file" \
  TARGET_AFTER_MARKER="$after_marker" \
  MB_RULE_FULL="$(language_rule_full)" \
  MB_RULE_SHORT="$(language_rule_short)" \
  MB_COMMENTS_LANGUAGE="$(comments_language_name)" \
  python3 <<'PYEOF'
from pathlib import Path
import os
import re

path = Path(os.environ["TARGET_FILE"])
if not path.exists():
    raise SystemExit(0)

text = path.read_text()
after_marker = os.environ.get("TARGET_AFTER_MARKER", "")
rule_full = os.environ["MB_RULE_FULL"]
rule_short = os.environ["MB_RULE_SHORT"]
comments_language = os.environ["MB_COMMENTS_LANGUAGE"]

prefix = ""
target = text
if after_marker and after_marker in text:
    prefix, rest = text.split(after_marker, 1)
    prefix = prefix + after_marker
    target = rest

target = re.sub(
    r"1\. \*\*[^*]+\*\*: .+",
    f"1. **Language**: {rule_full}",
    target,
)
target = re.sub(
    r"> \*\*[^*]+\*\* — .+",
    f"> **Language** — {rule_short}",
    target,
)
target = target.replace("comments in English", f"comments in {comments_language}")
target = target.replace("comments in Russian", f"comments in {comments_language}")

path.write_text(prefix + target)
PYEOF
}

# Apply localization in-place to an arbitrary file (not bound to "standard" target).
# Uses the same language-substitution logic as localize_installed_file() but skips the
# file-existence-is-acceptable short-circuit; caller guarantees the file exists.
localize_path_inplace() {
  local file="$1"
  local after_marker="${2:-}"
  [ -f "$file" ] || return 0
  TARGET_FILE="$file" \
  TARGET_AFTER_MARKER="$after_marker" \
  MB_RULE_FULL="$(language_rule_full)" \
  MB_RULE_SHORT="$(language_rule_short)" \
  MB_COMMENTS_LANGUAGE="$(comments_language_name)" \
  python3 <<'PYEOF'
from pathlib import Path
import os
import re

path = Path(os.environ["TARGET_FILE"])
text = path.read_text()
after_marker = os.environ.get("TARGET_AFTER_MARKER", "")
rule_full = os.environ["MB_RULE_FULL"]
rule_short = os.environ["MB_RULE_SHORT"]
comments_language = os.environ["MB_COMMENTS_LANGUAGE"]

prefix = ""
target = text
if after_marker and after_marker in text:
    prefix, rest = text.split(after_marker, 1)
    prefix = prefix + after_marker
    target = rest

target = re.sub(
    r"1\. \*\*[^*]+\*\*: .+",
    f"1. **Language**: {rule_full}",
    target,
)
target = re.sub(
    r"> \*\*[^*]+\*\* — .+",
    f"> **Language** — {rule_short}",
    target,
)
target = target.replace("comments in English", f"comments in {comments_language}")
target = target.replace("comments in Russian", f"comments in {comments_language}")

path.write_text(prefix + target)
PYEOF
}

# Idempotent copy+localize: compose expected post-install content in a temp file,
# compare with the current dst, and skip the backup+write entirely when they match.
install_file_localized() {
  local src="$1" dst="$2" marker="${3:-}"
  mkdir -p "$(dirname "$dst")"

  local tmp
  tmp="$(mktemp)"
  cp "$src" "$tmp"
  localize_path_inplace "$tmp" "$marker"

  if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then
    rm -f "$tmp"
    INSTALLED_FILES+=("$dst")
    return 0
  fi

  backup_if_exists "$dst"
  mv "$tmp" "$dst"
  INSTALLED_FILES+=("$dst")
}

write_language_config() {
  local config_path="$CLAUDE_DIR/memory-bank-config.json"
  mkdir -p "$CLAUDE_DIR"
  cat > "$config_path" <<EOF
{
  "preferred_language": "$LANGUAGE",
  "language_rule": "$(language_rule_full)"
}
EOF
  INSTALLED_FILES+=("$config_path")
}

install_symlink() {
  local source="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$source" ]; then
    INSTALLED_FILES+=("$dest")
    return
  fi

  backup_if_exists "$dest"
  ln -s "$source" "$dest"
  INSTALLED_FILES+=("$dest")
}

resolve_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

ensure_skill_aliases() {
  mkdir -p "$CLAUDE_DIR/skills" "$CODEX_DIR/skills" "$CURSOR_DIR/skills"

  local source_real canonical_real
  source_real="$(resolve_dir "$SOURCE_SKILL_DIR")"
  canonical_real=""
  if [ -e "$CANONICAL_SKILL_DIR" ] || [ -L "$CANONICAL_SKILL_DIR" ]; then
    canonical_real="$(resolve_dir "$CANONICAL_SKILL_DIR")"
  fi

  if [ "$canonical_real" != "$source_real" ]; then
    install_symlink "$SOURCE_SKILL_DIR" "$CANONICAL_SKILL_DIR"
    echo -e "  ${GREEN}✓${NC} canonical skill: $CANONICAL_SKILL_DIR"
  else
    echo -e "  ${YELLOW}~${NC} canonical skill already points to source"
  fi

  install_symlink "$CANONICAL_SKILL_DIR" "$CLAUDE_SKILL_ALIAS"
  install_symlink "$CANONICAL_SKILL_DIR" "$CODEX_SKILL_ALIAS"
  install_symlink "$CANONICAL_SKILL_DIR" "$CURSOR_SKILL_ALIAS"
  echo -e "  ${GREEN}✓${NC} Claude/Codex/Cursor skill aliases"
}

install_opencode_global_agents() {
  local agents_file="$OPENCODE_DIR/AGENTS.md"
  local tmp
  mkdir -p "$OPENCODE_DIR"

  if [ -f "$agents_file" ] && grep -q "$MB_START_MARKER" "$agents_file" 2>/dev/null; then
    tmp="$agents_file.tmp"
    awk -v s="$MB_START_MARKER" -v e="$MB_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_file" > "$tmp"
    {
      cat "$tmp"
      printf '\n'
      _agents_md_section "$SOURCE_SKILL_DIR"
    } > "$agents_file"
    rm -f "$tmp"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} OpenCode AGENTS.md (refreshed)"
    return
  fi

  if [ -f "$agents_file" ]; then
    {
      printf '\n'
      _agents_md_section "$SOURCE_SKILL_DIR"
    } >> "$agents_file"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} OpenCode AGENTS.md (merged)"
    return
  fi

  _agents_md_section "$SOURCE_SKILL_DIR" > "$agents_file"
  INSTALLED_FILES+=("$agents_file")
  echo -e "  ${GREEN}✓${NC} OpenCode AGENTS.md (created)"
}

codex_agents_section() {
  cat <<EOF
$CODEX_START_MARKER

# Memory Bank — Codex Global Entry Point

Global Memory Bank skill is registered at:
- \`~/.codex/skills/memory-bank/SKILL.md\`

Bundled resources available to Codex:
- Commands: \`~/.codex/skills/memory-bank/commands/\`
- Agents: \`~/.codex/skills/memory-bank/agents/\`
- Hooks: \`~/.codex/skills/memory-bank/hooks/\`

Recommended workflow:
- Start by reading \`.memory-bank/STATUS.md\`, \`checklist.md\`, \`plan.md\`, \`RESEARCH.md\`
- Use \`~/.codex/skills/memory-bank/commands/mb.md\` as the entrypoint for Memory Bank flows
- Resolve agent prompts from \`~/.codex/skills/memory-bank/agents/\`

Codex hooks support is conservative:
- Global Claude-style lifecycle parity is NOT guaranteed
- Prefer project-level \`.codex/\` adapter files for Codex hook/config integration
- Treat \`.codex/hooks.json\` as experimental unless documented otherwise

$CODEX_END_MARKER
EOF
}

install_codex_global_agents() {
  local agents_file="$CODEX_DIR/AGENTS.md"
  local tmp
  mkdir -p "$CODEX_DIR"

  if [ -f "$agents_file" ] && grep -q "$CODEX_START_MARKER" "$agents_file" 2>/dev/null; then
    tmp="$agents_file.tmp"
    awk -v s="$CODEX_START_MARKER" -v e="$CODEX_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_file" > "$tmp"
    {
      cat "$tmp"
      printf '\n'
      codex_agents_section
    } > "$agents_file"
    rm -f "$tmp"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} Codex AGENTS.md (refreshed)"
    return
  fi

  if [ -f "$agents_file" ]; then
    {
      printf '\n'
      codex_agents_section
    } >> "$agents_file"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} Codex AGENTS.md (merged)"
    return
  fi

  codex_agents_section > "$agents_file"
  INSTALLED_FILES+=("$agents_file")
  echo -e "  ${GREEN}✓${NC} Codex AGENTS.md (created)"
}

# ═══ Cursor global install helpers ═══
# Cursor docs (confirmed 2026-04):
#   - ~/.cursor/hooks.json + ~/.cursor/hooks/*   — user hooks (merged with project)
#   - ~/.cursor/commands/*.md                     — user slash commands
#   - ~/.cursor/skills/<name>/SKILL.md            — personal skills (auto-discovered)
#   - User Rules (analog of ~/.claude/CLAUDE.md)  — UI-only, no file API
# To cover the "global rules" channel we write three complementary artifacts:
#   1. ~/.cursor/skills/memory-bank      (canonical alias — handled in ensure_skill_aliases)
#   2. ~/.cursor/AGENTS.md               (marker section — for future compatibility/forks)
#   3. ~/.cursor/memory-bank-user-rules.md  (paste-ready file for Settings → Rules → User Rules)

cursor_agents_section() {
  cat <<EOF
$CURSOR_START_MARKER

# Memory Bank — Cursor Global Entry Point

Global Memory Bank skill is registered at:
- \`~/.cursor/skills/memory-bank/SKILL.md\`

Bundled resources available to Cursor agents:
- Commands: \`~/.cursor/commands/\` (mirror of skill \`commands/\`)
- Agent prompts: \`~/.cursor/skills/memory-bank/agents/\`
- Hooks: \`~/.cursor/hooks/\` wired via \`~/.cursor/hooks.json\`

Recommended workflow:
- Start by reading \`.memory-bank/STATUS.md\`, \`checklist.md\`, \`plan.md\`, \`RESEARCH.md\`
- Use \`/mb\` as the entrypoint for Memory Bank flows
- Update \`checklist.md\` immediately (⬜ → ✅) when tasks complete

Cursor surfaces user-level rules only through **Settings → Rules → User Rules**.
The same content is mirrored to \`~/.cursor/memory-bank-user-rules.md\` for copy-paste:
- macOS:  \`pbcopy < ~/.cursor/memory-bank-user-rules.md\`
- Linux:  \`xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md\`

---

EOF
  cat "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  printf '\n%s\n' "$CURSOR_END_MARKER"
}

install_cursor_global_agents() {
  local agents_file="$CURSOR_DIR/AGENTS.md"
  local tmp
  mkdir -p "$CURSOR_DIR"

  if [ -f "$agents_file" ] && grep -q "$CURSOR_START_MARKER" "$agents_file" 2>/dev/null; then
    tmp="$agents_file.tmp"
    awk -v s="$CURSOR_START_MARKER" -v e="$CURSOR_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_file" > "$tmp"
    {
      cat "$tmp"
      printf '\n'
      cursor_agents_section
    } > "$agents_file"
    rm -f "$tmp"
    INSTALLED_FILES+=("$agents_file")
    localize_installed_file "$agents_file" "$CURSOR_START_MARKER"
    echo -e "  ${GREEN}✓${NC} Cursor AGENTS.md (refreshed)"
    return
  fi

  if [ -f "$agents_file" ]; then
    {
      printf '\n'
      cursor_agents_section
    } >> "$agents_file"
    INSTALLED_FILES+=("$agents_file")
    localize_installed_file "$agents_file" "$CURSOR_START_MARKER"
    echo -e "  ${GREEN}✓${NC} Cursor AGENTS.md (merged)"
    return
  fi

  cursor_agents_section > "$agents_file"
  INSTALLED_FILES+=("$agents_file")
  localize_installed_file "$agents_file" "$CURSOR_START_MARKER"
  echo -e "  ${GREEN}✓${NC} Cursor AGENTS.md (created)"
}

install_cursor_user_rules_paste() {
  mkdir -p "$CURSOR_DIR"

  local tmp
  tmp="$(mktemp)"
  {
    cat <<'EOF'
# Memory Bank — User Rules (paste into Cursor → Settings → Rules → User Rules)

> This content mirrors the global Memory Bank skill at `~/.cursor/skills/memory-bank/`.
> Cursor does not expose a file API for global User Rules, so paste this block manually
> into Settings → Rules → User Rules once per machine.

EOF
    cat "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  } > "$tmp"
  localize_path_inplace "$tmp"

  if [ -f "$CURSOR_USER_RULES_FILE" ] && cmp -s "$tmp" "$CURSOR_USER_RULES_FILE"; then
    rm -f "$tmp"
    INSTALLED_FILES+=("$CURSOR_USER_RULES_FILE")
    echo -e "  ${YELLOW}~${NC} Cursor User Rules paste-file unchanged"
    return
  fi

  backup_if_exists "$CURSOR_USER_RULES_FILE"
  mv "$tmp" "$CURSOR_USER_RULES_FILE"
  INSTALLED_FILES+=("$CURSOR_USER_RULES_FILE")
  echo -e "  ${GREEN}✓${NC} Cursor User Rules paste-file: $CURSOR_USER_RULES_FILE"
}

install_cursor_global_hooks() {
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "  ${YELLOW}~${NC} Cursor global hooks skipped (jq required)"
    return 0
  fi

  mkdir -p "$CURSOR_DIR/hooks"

  local h
  for h in "${CURSOR_GLOBAL_HOOKS[@]}"; do
    if [ ! -f "$SOURCE_SKILL_DIR/hooks/$h" ]; then
      echo -e "  ${YELLOW}~${NC} missing source hook: $SOURCE_SKILL_DIR/hooks/$h"
      continue
    fi
    install_file "$SOURCE_SKILL_DIR/hooks/$h" "$CURSOR_DIR/hooks/$h"
  done

  # Build our hook bindings: each event gets one { command, _mb_owned } entry.
  local our_hooks_json
  our_hooks_json=$(jq -n '{hooks: {}}')
  local binding event script cmd
  for binding in "${CURSOR_GLOBAL_HOOK_BINDINGS[@]}"; do
    event="${binding%%:*}"
    script="${binding#*:}"
    cmd="bash $CURSOR_DIR/hooks/$script"
    our_hooks_json=$(echo "$our_hooks_json" | jq \
      --arg event "$event" \
      --arg cmd "$cmd" \
      '.hooks[$event] = [{command: $cmd, _mb_owned: true}]')
  done

  local hooks_json="$CURSOR_DIR/hooks.json"
  local merged
  if [ -f "$hooks_json" ]; then
    merged=$(jq --slurpfile new <(echo "$our_hooks_json") '
      . as $existing |
      (.version // 1) as $ver |
      reduce ($new[0].hooks | keys[]) as $evt (
        $existing;
        .version = $ver
        | .hooks //= {}
        | .hooks[$evt] = (
            ((.hooks[$evt] // []) | map(select((._mb_owned // false) | not)))
            + ($new[0].hooks[$evt])
          )
      )
    ' "$hooks_json")
  else
    merged=$(echo "$our_hooks_json" | jq '.version = 1')
  fi
  echo "$merged" > "$hooks_json"
  INSTALLED_FILES+=("$hooks_json")
  echo -e "  ${GREEN}✓${NC} Cursor global hooks.json (${#CURSOR_GLOBAL_HOOK_BINDINGS[@]} events)"
}

# ═══ Step 1: Rules ═══
echo -e "${BLUE}[1/7] Rules${NC}"
install_file_localized "$SOURCE_SKILL_DIR/rules/RULES.md" "$CLAUDE_DIR/RULES.md"
echo -e "  ${GREEN}✓${NC} RULES.md"

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  if ! grep -q "\[MEMORY-BANK-SKILL\]" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
    printf '\n# [MEMORY-BANK-SKILL]\n' >> "$CLAUDE_DIR/CLAUDE.md"
    cat "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md" >> "$CLAUDE_DIR/CLAUDE.md"
    localize_installed_file "$CLAUDE_DIR/CLAUDE.md" "# [MEMORY-BANK-SKILL]"
    INSTALLED_FILES+=("$CLAUDE_DIR/CLAUDE.md")
    echo -e "  ${GREEN}✓${NC} CLAUDE.md (merged)"
  else
    localize_installed_file "$CLAUDE_DIR/CLAUDE.md" "# [MEMORY-BANK-SKILL]"
    # Already installed — do NOT add to INSTALLED_FILES (no backup = uninstall would delete it)
    echo -e "  ${YELLOW}~${NC} CLAUDE.md (already has MB section; language refreshed)"
  fi
else
  mkdir -p "$CLAUDE_DIR"
  {
    printf '# [MEMORY-BANK-SKILL]\n'
    cat "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  } > "$CLAUDE_DIR/CLAUDE.md"
  localize_installed_file "$CLAUDE_DIR/CLAUDE.md" "# [MEMORY-BANK-SKILL]"
  INSTALLED_FILES+=("$CLAUDE_DIR/CLAUDE.md")
  echo -e "  ${GREEN}✓${NC} CLAUDE.md (created with marker)"
fi

write_language_config
echo -e "  ${GREEN}✓${NC} language preference ($LANGUAGE)"

install_opencode_global_agents
install_codex_global_agents

# ═══ Step 2: Agents ═══
echo -e "${BLUE}[2/7] Agents${NC}"
for f in "$SOURCE_SKILL_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  install_file "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done
echo -e "  ${GREEN}✓${NC} $(count_matching_files "$SOURCE_SKILL_DIR/agents" '*.md') agents"

# ═══ Step 3: Hooks ═══
echo -e "${BLUE}[3/7] Hooks${NC}"
for f in "$SOURCE_SKILL_DIR"/hooks/*.sh; do
  [ -f "$f" ] || continue
  install_file "$f" "$CLAUDE_DIR/hooks/$(basename "$f")"
done
echo -e "  ${GREEN}✓${NC} $(count_matching_files "$SOURCE_SKILL_DIR/hooks" '*.sh') hooks"

# ═══ Step 4: Commands ═══
echo -e "${BLUE}[4/7] Commands${NC}"
for f in "$SOURCE_SKILL_DIR"/commands/*.md; do
  [ -f "$f" ] || continue
  install_file "$f" "$CLAUDE_DIR/commands/$(basename "$f")"
  install_file "$f" "$OPENCODE_DIR/commands/$(basename "$f")"
  install_file "$f" "$CURSOR_DIR/commands/$(basename "$f")"
done
echo -e "  ${GREEN}✓${NC} $(count_matching_files "$SOURCE_SKILL_DIR/commands" '*.md') commands"

# ═══ Step 5: Skill files ═══
echo -e "${BLUE}[5/7] Skill registration${NC}"
ensure_skill_aliases
install_cursor_global_agents
install_cursor_user_rules_paste
install_cursor_global_hooks

# ═══ Step 6: Settings hooks ═══
echo -e "${BLUE}[6/7] Settings${NC}"
if [ -f "$SOURCE_SKILL_DIR/settings/hooks.json" ] && command -v python3 &>/dev/null; then
  python3 "$SOURCE_SKILL_DIR/settings/merge-hooks.py" \
    "$CLAUDE_DIR/settings.json" \
    "$SOURCE_SKILL_DIR/settings/hooks.json" \
    2>/dev/null && echo -e "  ${GREEN}✓${NC} Hooks merged" \
    || echo -e "  ${YELLOW}~${NC} Manual hook setup may be needed"
  localize_installed_file "$CLAUDE_DIR/settings.json"
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
raw_backups = [b for b in os.environ.get("BACKED_UP_STR", "").split("\n") if b]

# filter: keep only backups whose backup_path ("target|backup") still exists on disk
def _backup_path(entry: str) -> str:
    parts = entry.split("|", 1)
    return parts[1] if len(parts) == 2 else ""

backups = [b for b in raw_backups if os.path.exists(_backup_path(b))]

manifest = {
    "installed_at": os.environ["INSTALL_DATE"],
    "skill": "skill-memory-bank",
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
  adapter="$SOURCE_SKILL_DIR/adapters/$c_trimmed.sh"
  if [ ! -x "$adapter" ]; then
    echo -e "  ${YELLOW}~${NC} adapter missing or not executable: $adapter" >&2
    continue
  fi
  echo -e "${BLUE}[8/8] Cross-agent: $c_trimmed${NC}"
  if MB_LANGUAGE="$LANGUAGE" bash "$adapter" install "$PROJECT_ROOT"; then
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
echo "  Canonical skill: $CANONICAL_SKILL_DIR"
echo "  Claude alias:    $CLAUDE_SKILL_ALIAS"
echo "  Codex alias:     $CODEX_SKILL_ALIAS"
echo "  Cursor alias:    $CURSOR_SKILL_ALIAS"
echo "  Uninstall: $SOURCE_SKILL_DIR/uninstall.sh"
echo ""
echo -e "${BOLD}Cursor User Rules (one-time manual step):${NC}"
echo "  Cursor's global User Rules live in Settings → Rules → User Rules (UI only)."
echo "  Copy the bundled paste-file to clipboard and paste it in once per machine:"
echo "    macOS:  pbcopy < $CURSOR_USER_RULES_FILE"
echo "    Linux:  xclip -selection clipboard < $CURSOR_USER_RULES_FILE"
echo ""
echo "  Optional — multi-language code graph (Go/JS/TS/Rust/Java via tree-sitter):"
echo "    pip install tree-sitter tree-sitter-python tree-sitter-go \\"
echo "                tree-sitter-javascript tree-sitter-typescript tree-sitter-rust tree-sitter-java"
echo "  Without these, /mb graph works for Python-only (via stdlib ast)."
echo ""
