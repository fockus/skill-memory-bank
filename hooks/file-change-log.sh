#!/bin/bash
# PostToolUse hook: file-change log + placeholder/secret checks.
#   - logs Write/Edit events to ~/.claude/file-changes.log
#   - rotates the log after 10 MB (→ .log.1, .log.2)
#   - searches TODO/FIXME/HACK/XXX/PLACEHOLDER/NotImplementedError in CODE (not
#     in docstrings and not in plain-text files)
#   - does NOT treat bare `pass` as a placeholder — it is valid Python
#   - warns about hardcoded secrets in source code

set -u

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for hook" >&2; exit 1; }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
LOG_FILE="$HOME/.claude/file-changes.log"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10 MB

# ═══ Log rotation ═══
# Portable size check: BSD `stat -f%z` (macOS) or GNU `stat -c%s` (Linux).
if [ -f "$LOG_FILE" ]; then
  LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]; then
    # Shift .log.2 → .log.3, .log.1 → .log.2, .log → .log.1
    [ -f "$LOG_FILE.2" ] && mv "$LOG_FILE.2" "$LOG_FILE.3"
    [ -f "$LOG_FILE.1" ] && mv "$LOG_FILE.1" "$LOG_FILE.2"
    mv "$LOG_FILE" "$LOG_FILE.1"
    # Re-tighten perms on every rotated copy — the original file may have
    # been created with a looser umask before the chmod-600 fix landed.
    [ -f "$LOG_FILE.1" ] && chmod 600 "$LOG_FILE.1" 2>/dev/null || true
    [ -f "$LOG_FILE.2" ] && chmod 600 "$LOG_FILE.2" 2>/dev/null || true
    [ -f "$LOG_FILE.3" ] && chmod 600 "$LOG_FILE.3" 2>/dev/null || true
  fi
fi

# ═══ Append log entry ═══
# Create with 600 mode atomically: touch+chmod *before* the first write so we
# never have a window where the file is world-readable.
if [ ! -f "$LOG_FILE" ]; then
  : > "$LOG_FILE" 2>/dev/null && chmod 600 "$LOG_FILE" 2>/dev/null || true
fi
case "$TOOL" in
  Write) echo "[$TIMESTAMP] WRITE: $FILE_PATH" >> "$LOG_FILE" ;;
  Edit)  echo "[$TIMESTAMP] EDIT: $FILE_PATH"  >> "$LOG_FILE" ;;
esac
# Idempotent perm reassertion — cheap, ensures legacy 644 files get tightened.
[ -f "$LOG_FILE" ] && chmod 600 "$LOG_FILE" 2>/dev/null || true

[ -f "$FILE_PATH" ] || exit 0

# Plain-text files — no checks (`TODO` in markdown/config is not a bug).
if [[ "$FILE_PATH" =~ \.(md|txt|json|yaml|yml|toml|cfg|ini|env)$ ]]; then
  exit 0
fi

# ═══ Placeholder detection (outside docstrings) ═══
#
# Algorithm: first strip triple-quoted blocks (""" ... """ and ''' ... '''),
# then grep what remains.
#   - `pass` is removed from the list — it is a legitimate Python statement.
#   - Search uses another word boundary (\b): "TODOLIST" should not trigger.
#
# awk receives quote markers through variables so shellcheck-SC1003 does not get
# confused by triple single quotes inside the awk script.
stripped=$(awk -v dq='"""' -v sq="'''" '
  BEGIN { in_q = 0 }
  function count(str, pat,   n) {
    n = 0
    while (index(str, pat) > 0) {
      str = substr(str, index(str, pat) + length(pat))
      n++
    }
    return n
  }
  {
    line = $0
    occ = count(line, dq) + count(line, sq)
    if (in_q) {
      if (occ > 0) { in_q = 0 }
      next
    }
    if (occ >= 2) { next }          # open-and-close on one line → skip
    if (occ == 1) { in_q = 1; next } # only opener → enter docstring
    printf "%d:%s\n", NR, line
  }
' "$FILE_PATH")

PLACEHOLDERS=$(printf '%s\n' "$stripped" \
  | grep -E '\b(TODO|FIXME|HACK|XXX|PLACEHOLDER|NotImplementedError|raise NotImplemented)\b' \
  | head -5 || true)

if [ -n "$PLACEHOLDERS" ]; then
  echo "WARNING: Placeholders found in $FILE_PATH:" >&2
  echo "$PLACEHOLDERS" >&2
fi

# ═══ <private> markers in .md files ═══
# If the user commits a file with <private>...</private>, warn them.
# The block will not leak through index.json/search, but it may leak into git history.
if [[ "$FILE_PATH" =~ \.md$ ]] && grep -q '<private>' "$FILE_PATH" 2>/dev/null; then
  echo "WARNING: <private> block in $FILE_PATH — make sure it should go into git (or use git-filter/.gitattributes)" >&2
fi

# ═══ Secrets in source files ═══
if [[ "$FILE_PATH" =~ \.(py|go|js|ts|rb|java|rs|swift|kt)$ ]]; then
  SECRETS=$(grep -nEi '(password|secret|api_key|token|private_key)\s*=\s*["\x27][^"\x27]{8,}' "$FILE_PATH" 2>/dev/null \
    | grep -vEi '(test|mock|fake|example|placeholder|xxx|your_)' \
    | head -3)
  if [ -n "$SECRETS" ]; then
    echo "WARNING: Possible hardcoded secrets in $FILE_PATH:" >&2
    echo "$SECRETS" >&2
  fi
fi

exit 0
