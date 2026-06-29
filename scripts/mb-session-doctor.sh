#!/usr/bin/env bash
# mb-session-doctor.sh — diagnose session-memory subsystem health.
# Reports: unsummarized sessions, missing _recent.md, empty semantic index,
# missing adapter files (Claude hooks, Pi extension), legacy auto-capture stubs.
# Usage: mb-session-doctor.sh [project_root]
# Exit 0 always (informational); severity per check is reported in output.
set -u

PROJECT_ROOT="${1:-$PWD}"
HOOK_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude"
SKILL_HOOKS="$HOME/.claude/skills/memory-bank/hooks"

# shellcheck source=../hooks/lib/session-common.sh
SESSION_COMMON="$SKILL_HOOKS/lib/session-common.sh"
if [ -f "$SESSION_COMMON" ]; then
  # shellcheck source=hooks/lib/session-common.sh
  . "$SESSION_COMMON"
  MB="$(sc_resolve_mb "$PROJECT_ROOT")"
else
  # Fallback resolve without session-common.sh
  MB=""
  dir="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || dir="$PWD"
  while [ -n "$dir" ]; do
    [ -d "$dir/.memory-bank" ] && { MB="$dir/.memory-bank"; break; }
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
fi

issues=0
warns=0
infos=0

echo "=== MB session-memory doctor ==="
echo "  project: $PROJECT_ROOT"
echo "  bank:    ${MB:-NOT FOUND}"
echo ""

[ -z "$MB" ] && { echo "[WARN] No Memory Bank found."; exit 0; }

SDIR="$MB/session"
INDEXDIR="$MB/.index"
PROGRESS="$MB/progress.md"

# ─── Check 1: unsummarized sessions ─────────────────────────────────────────
echo "--- Sessions ---"
session_count=0; unsummarized=0; summarized=0; no_summary=0
for f in "$SDIR/"*.md; do
  [ -f "$f" ] || continue
  [ "$(basename "$f")" = "_recent.md" ] && continue
  session_count=$((session_count + 1))
  if grep -q '^summarized: true$' "$f" 2>/dev/null; then
    summarized=$((summarized + 1))
    if ! grep -q '^## Summary$' "$f" 2>/dev/null; then
      echo "  [WARN] $f: summarized:true but missing ## Summary section"
      warns=$((warns + 1))
    fi
  elif grep -q '^summarized: false$' "$f" 2>/dev/null; then
    unsummarized=$((unsummarized + 1))
  fi
  has_summary=0
  grep -q '^## Summary$' "$f" 2>/dev/null && has_summary=1
  [ "$has_summary" -eq 0 ] && no_summary=$((no_summary + 1))
done

echo "  sessions: $session_count | summarized: $summarized | unsummarized: $unsummarized | no summary: $no_summary"
if [ "$unsummarized" -gt 0 ]; then
  echo "  [WARN] $unsummarized session(s) have summarized:false — run mb-session-catchup.sh or set MB_SUMMARY_BACKEND"
  warns=$((warns + 1))
fi

# ─── Check 2: _recent.md ─────────────────────────────────────────────────────
echo "--- _recent.md ---"
RECENT="$SDIR/_recent.md"
if [ -f "$RECENT" ]; then
  recent_entries=$(grep -c '^## ' "$RECENT" 2>/dev/null || echo 0)
  echo "  file: present | entries: $recent_entries"
  # Check if _recent.md is older than newest session
  if [ "$session_count" -gt 0 ]; then
    recent_mtime=$(stat -f%m "$RECENT" 2>/dev/null || stat -c%Y "$RECENT" 2>/dev/null || echo 0)
    newest_session_mtime=0
    for f in "$SDIR/"*.md; do
      [ -f "$f" ] || continue
      [ "$(basename "$f")" = "_recent.md" ] && continue
      mtime=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0)
      [ "$mtime" -gt "$newest_session_mtime" ] && newest_session_mtime=$mtime
    done
    if [ "$recent_mtime" -lt "$newest_session_mtime" ] 2>/dev/null; then
      echo "  [WARN] _recent.md appears stale (older than newest session). Run: mb-session-recent-rebuild.sh"
      warns=$((warns + 1))
    fi
  fi
else
  echo "  missing — run: mb-session-recent-rebuild.sh"
  warns=$((warns + 1))
fi

# ─── Check 3: semantic index ─────────────────────────────────────────────────
echo "--- Semantic index ---"
if [ -f "$INDEXDIR/store.json" ]; then
  chunks=$(python3 -c "
import json
try:
  d=json.load(open('$INDEXDIR/store.json'))
  if 'chunks' in d: print(d['chunks'])
  else: print(len(d.get('blocks',[])))
except: print(0)
" 2>/dev/null || echo 0)
  echo "  chunks: $chunks"
  if [ "$chunks" = "0" ] 2>/dev/null; then
    echo "  [INFO] Semantic index is empty. Run: mb-reindex.sh --full (requires fastembed venv)"
    infos=$((infos + 1))
  fi
else
  echo "  not built. Run: mb-reindex.sh --full (requires fastembed venv)"
  infos=$((infos + 1))
fi

# ─── Check 4: Claude adapter hooks ───────────────────────────────────────────
echo "--- Claude adapter ---"
if [ -d "$HOOK_DIR" ]; then
  missing_hooks=""
  for hook in mb-session-catchup.sh mb-session-summarize.sh mb-pre-compact.sh; do
    if [ ! -f "$HOOK_DIR/hooks/$hook" ] && [ ! -f "$SKILL_HOOKS/$hook" ]; then
      missing_hooks="$missing_hooks $hook"
    fi
  done
  if [ -n "$missing_hooks" ]; then
    echo "  [WARN] Missing hooks:$missing_hooks — run adapter install"
    warns=$((warns + 1))
  else
    echo "  hooks: ok"
  fi
else
  echo "  [INFO] Claude dir not found ($HOOK_DIR) — skipping hook check"
  infos=$((infos + 1))
fi

# ─── Check 5: Pi adapter extension ───────────────────────────────────────────
echo "--- Pi adapter ---"
PI_EXT="$HOME/.pi/agent/extensions/memory-bank-session.ts"
PI_EXT_SKILL="$SKILL_HOOKS/../adapters/pi_session_memory_extension.ts"

if [ -f "$PI_EXT" ]; then
  echo "  extension: installed ($PI_EXT)"
elif [ -f "$PI_EXT_SKILL" ]; then
  echo "  [INFO] Extension exists in skill repo but not installed. Run: adapters/pi.sh install"
  infos=$((infos + 1))
else
  echo "  [INFO] Pi session adapter extension not found (Stage 4 will create it)"
  infos=$((infos + 1))
fi

# ─── Check 6: auto-capture stubs in progress.md ──────────────────────────────
echo "--- Legacy auto-capture ---"
if [ -f "$PROGRESS" ]; then
  stub_count=$(grep -c '^### Auto-capture' "$PROGRESS" 2>/dev/null || echo 0)
  echo "  auto-capture stubs: $stub_count"
  if [ "$stub_count" -gt 0 ]; then
    echo "  [WARN] $stub_count auto-capture stubs in progress.md. Set MB_AUTO_CAPTURE=off or run mb-consolidate.sh --dry-run"
    warns=$((warns + 1))
  fi
fi

# ─── Check 7: summary backend configured ─────────────────────────────────────
echo "--- Summary backend ---"
backend="${MB_SUMMARY_BACKEND:-}"
if [ -z "$backend" ]; then
  if command -v claude >/dev/null 2>&1; then
    backend="claude-code (auto-detected)"
  else
    backend="none (no claude CLI found)"
  fi
fi
echo "  backend: $backend"
if [ "$backend" = "none (no claude CLI found)" ]; then
  echo "  [INFO] No summarizer available. Session capture still works; summaries will be deferred to catchup with a configured backend."
  infos=$((infos + 1))
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Result ==="
echo "  WARNs: $warns | INFOs: $infos"
if [ "$warns" -gt 0 ] || [ "$infos" -gt 0 ]; then
  exit 0
fi
echo "  session-memory: healthy"
exit 0
