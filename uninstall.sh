#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SKILL_DIR/scripts/_lib.sh"
# Interpreter that owns the memory_bank_skill package (set by the `memory-bank`
# CLI to sys.executable); falls back to python3 for a direct `bash uninstall.sh`.
MB_PY="${MB_PYTHON:-python3}"
# A12: same resolution install.sh used — MB_MANIFEST_PATH override, else the
# co-located manifest when SKILL_DIR is user-writable, else the XDG-fallback
# path a pip/sudo install (root-owned SKILL_DIR) would have used instead.
MANIFEST="$(mb_resolve_manifest_path "$SKILL_DIR")"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
CURSOR_DIR="$HOME/.cursor"
OPENCODE_DIR="$HOME/.config/opencode"
PI_AGENT_DIR="$HOME/.pi/agent"
CODEX_START_MARKER="<!-- memory-bank-codex:start -->"
CODEX_END_MARKER="<!-- memory-bank-codex:end -->"
PI_START_MARKER="<!-- memory-bank-pi:start -->"
PI_END_MARKER="<!-- memory-bank-pi:end -->"
GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
# A22: was referenced (lines below) without being declared — under `set -u`
# that's a latent unbound-variable crash the moment either code path runs.
YELLOW='\033[1;33m'

managed_roots=("$CLAUDE_DIR" "$CODEX_DIR" "$CURSOR_DIR" "$OPENCODE_DIR" "$PI_AGENT_DIR")
NON_INTERACTIVE=0
# A22 (CDX-I11): explicit opt-in to proceed past a corrupt manifest (below).
FORCE=0

run_texttool() {
  PYTHONPATH="$SKILL_DIR${PYTHONPATH:+:$PYTHONPATH}" \
    "$MB_PY" -m memory_bank_skill._texttools "$@"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: uninstall.sh [-y|--non-interactive] [--force]

  -y, --non-interactive   Skip confirmation prompt and uninstall immediately.
  --force                 Proceed even if the manifest is corrupt/unreadable
                           (treated as empty — only generic cleanup runs).
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

# A22 (CDX-I11): a truncated/corrupt manifest used to be silently treated as
# EMPTY (every downstream reader `2>/dev/null`s the JSON parse and gets no
# lines back), so uninstall.sh quietly removed nothing while reporting
# success. Fail loudly instead, unless the caller explicitly opts in via
# --force (manifest is then treated as empty — only the generic/manual
# cleanup steps below still run).
if ! MANIFEST_PATH="$MANIFEST" "$MB_PY" -c "import json, os; json.load(open(os.environ['MANIFEST_PATH']))" >/dev/null 2>&1; then
  if [ "$FORCE" -eq 1 ]; then
    echo -e "${YELLOW}~${NC} manifest at $MANIFEST is corrupt/unreadable — proceeding anyway (--force)" >&2
  else
    echo -e "${RED}Manifest is corrupt or unreadable:${NC} $MANIFEST" >&2
    echo "  Re-run with --force to proceed anyway (treated as empty — only generic cleanup runs)." >&2
    exit 1
  fi
fi

if [ "$NON_INTERACTIVE" -eq 0 ]; then
  echo -n "Remove all memory-bank files? (y/n): "
  # A24 (CDX-I12): in a no-tty environment (CI/pipe) with nothing piped in, `read`
  # hits EOF immediately and fails — under `set -e` that used to die mid-prompt
  # with no explanation. Detect the read failure explicitly and exit with a clear
  # hint instead of an opaque/hanging failure. A real piped answer (even from a
  # non-tty pipe, e.g. `echo y | uninstall.sh`) still reads normally below.
  if ! read -r c; then
    echo -e "\n${RED}No input received on stdin.${NC} Re-run with -y/--non-interactive to skip the confirmation prompt." >&2
    exit 1
  fi
  [ "$c" != "y" ] && exit 0
fi

echo -e "\n${BLUE}Removing files...${NC}"
# A22: `|| true` so a corrupt manifest (only reachable here via --force,
# gated above) degrades to "nothing to remove" instead of a hard `set -e
# -o pipefail` crash on the JSON-parse failure — consistent with every other
# manifest reader in this script (Restoring backups, per-project adapters).
MANIFEST_PATH="$MANIFEST" "$MB_PY" -c "import json, os; [print(f) for f in json.load(open(os.environ['MANIFEST_PATH'])).get('files',[])]" 2>/dev/null | while read -r filepath; do
  [ -z "$filepath" ] && continue
  case "$filepath" in
    "$CLAUDE_DIR/CLAUDE.md"|"$CLAUDE_DIR/settings.json"|"$OPENCODE_DIR/AGENTS.md"|"$CODEX_DIR/AGENTS.md"|"$CURSOR_DIR/AGENTS.md"|"$CURSOR_DIR/hooks.json"|"$PI_AGENT_DIR/AGENTS.md")
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
done || true

echo -e "\n${BLUE}Restoring backups...${NC}"
# A22: same `|| true` rationale as "Removing files" above.
MANIFEST_PATH="$MANIFEST" "$MB_PY" -c "import json, os; [print(b) for b in json.load(open(os.environ['MANIFEST_PATH'])).get('backups',[])]" 2>/dev/null | while read -r bp; do
  [ -n "$bp" ] && echo "$bp" | grep -q '|' && {
    orig="${bp%%|*}"; bak="${bp##*|}"
    case "$orig" in
      "$CLAUDE_DIR/CLAUDE.md")
        # A20 (CDX-I9): CLAUDE.md is a merge-managed file with paired A13
        # start/end markers (see the "keep ... (managed merged file)" skip
        # above) and install.sh now keeps the live file self-contained
        # ([original content][MB block]) from the very first merge onward —
        # a wholesale `mv "$bak" "$orig"` here would clobber content the user
        # added AFTER install (inside OR outside the MB-managed block),
        # restoring only the pre-install snapshot. The MB section is instead
        # stripped surgically further below (strip-between-markers); never
        # blind-restore the pre-install backup over live user edits.
        echo "  [SKIP] $orig (merge-managed — MB section stripped below, not backup-restored)"
        continue
        ;;
    esac
    if mb_path_is_within "$orig" "${managed_roots[@]}"; then
      { [ -e "$bak" ] || [ -L "$bak" ]; } && mv "$bak" "$orig" && echo "  restored $orig"
    else
      echo "  [SKIP] $orig (outside managed dirs)"
    fi
  }
done || true

echo -e "\n${BLUE}Cleaning settings.json...${NC}"
[ -f "$CLAUDE_DIR/settings.json" ] && SETTINGS_PATH="$CLAUDE_DIR/settings.json" "$MB_PY" << 'PYEOF' 2>/dev/null || true
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

# Clean CLAUDE.md MB section — A13 (M-5): strip strictly between the paired
# start/end markers so content the user placed AFTER the section survives
# (the old strip-after-marker ate everything to EOF). Files written before
# A13 have no end marker; strip_between_markers degrades to the previous
# to-EOF behavior for those (nothing worse than before, no regression).
[ -f "$CLAUDE_DIR/CLAUDE.md" ] && grep -q "\[MEMORY-BANK-SKILL\]" "$CLAUDE_DIR/CLAUDE.md" && run_texttool strip-between-markers --path "$CLAUDE_DIR/CLAUDE.md" --start-marker "# [MEMORY-BANK-SKILL]" --end-marker "<!-- /memory-bank-skill -->" 2>/dev/null && echo "  CLAUDE.md cleaned" || true

# Clean OpenCode AGENTS.md MB section
[ -f "$OPENCODE_DIR/AGENTS.md" ] && grep -q "memory-bank:start" "$OPENCODE_DIR/AGENTS.md" && run_texttool strip-between-markers --path "$OPENCODE_DIR/AGENTS.md" --start-marker "<!-- memory-bank:start -->" --end-marker "<!-- memory-bank:end -->" 2>/dev/null && echo "  OpenCode AGENTS.md cleaned" || true

# Clean Codex AGENTS.md MB section
[ -f "$CODEX_DIR/AGENTS.md" ] && grep -q "memory-bank-codex:start" "$CODEX_DIR/AGENTS.md" && run_texttool strip-between-markers --path "$CODEX_DIR/AGENTS.md" --start-marker "$CODEX_START_MARKER" --end-marker "$CODEX_END_MARKER" 2>/dev/null && echo "  Codex AGENTS.md cleaned" || true

# Clean Pi AGENTS.md MB section
[ -f "$PI_AGENT_DIR/AGENTS.md" ] && grep -q "memory-bank-pi:start" "$PI_AGENT_DIR/AGENTS.md" && run_texttool strip-between-markers --path "$PI_AGENT_DIR/AGENTS.md" --start-marker "$PI_START_MARKER" --end-marker "$PI_END_MARKER" 2>/dev/null && echo "  Pi AGENTS.md cleaned" || true

# Cursor global cleanup lives in adapters/cursor.sh
if [ -f "$CURSOR_DIR/.mb-manifest.json" ]; then
  bash "$SKILL_DIR/adapters/cursor.sh" uninstall-global >/dev/null && echo "  Cursor global adapter cleaned"
fi

# ── Per-project cross-agent adapters (A10) ──────────────────────────────────
# install.sh records the project-level clients it invoked (Step 8) + the
# project root they targeted in the manifest. Call each adapter's own
# `uninstall` so it removes its project artifacts AND decrements the shared
# AGENTS.md owners refcount (adapters/_lib_agents_md.sh) — otherwise stale
# project files + an inflated refcount are left behind.
if [ -f "$MANIFEST" ] && command -v jq >/dev/null 2>&1; then
  MB_UNINSTALL_PROJECT_ROOT="$(jq -r '.project_root // empty' "$MANIFEST" 2>/dev/null || true)"
  if [ -n "$MB_UNINSTALL_PROJECT_ROOT" ] && [ -d "$MB_UNINSTALL_PROJECT_ROOT" ]; then
    while IFS= read -r mb_client; do
      [ -n "$mb_client" ] || continue
      mb_adapter="$SKILL_DIR/adapters/$mb_client.sh"
      if [ ! -x "$mb_adapter" ]; then
        echo -e "${YELLOW}  ~ $mb_client adapter script missing, skipped (manual cleanup may be needed)${NC}" >&2
        continue
      fi
      if bash "$mb_adapter" uninstall "$MB_UNINSTALL_PROJECT_ROOT" >/dev/null 2>&1; then
        echo "  $mb_client project adapter cleaned ($MB_UNINSTALL_PROJECT_ROOT)"
      else
        echo -e "${YELLOW}  ~ $mb_client adapter uninstall reported an error (see manual cleanup)${NC}" >&2
      fi
    done < <(jq -r '.clients[]? // empty' "$MANIFEST" 2>/dev/null)
  fi
fi

rm -f "$MANIFEST"
rmdir "$CLAUDE_DIR/skills" 2>/dev/null || true
rmdir "$CODEX_DIR/skills" 2>/dev/null || true
rmdir "$CODEX_DIR/prompts" 2>/dev/null || true
rmdir "$CURSOR_DIR/skills" 2>/dev/null || true
rmdir "$CURSOR_DIR/hooks" 2>/dev/null || true
rmdir "$CURSOR_DIR/commands" 2>/dev/null || true
rmdir "$OPENCODE_DIR/commands" 2>/dev/null || true
rmdir "$OPENCODE_DIR/skills" 2>/dev/null || true
rmdir "$PI_AGENT_DIR/prompts" 2>/dev/null || true
rmdir "$PI_AGENT_DIR/skills" 2>/dev/null || true
rmdir "$PI_AGENT_DIR/.memory-bank-backups" 2>/dev/null || true
rmdir "$PI_AGENT_DIR" 2>/dev/null || true
rmdir "$HOME/.pi" 2>/dev/null || true
rmdir "$OPENCODE_DIR" 2>/dev/null || true

echo -e "\n${GREEN}═══ Uninstalled ═══${NC}\n  Project .memory-bank/ dirs untouched.\n"
