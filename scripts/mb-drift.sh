#!/usr/bin/env bash
# mb-drift.sh — 8 deterministic drift checkers for Memory Bank (no AI required).
#
# Usage:
#   mb-drift.sh [project-dir]
#
# Output (stdout): key=value
#   drift_check_<name>=ok|warn|skip
#   drift_warnings=N
# Diagnostics (stderr): lines prefixed with `[drift:<name>]`
#
# Exit: 0 if `drift_warnings=0`, otherwise 1.

set -u

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

DIR="${1:-.}"
MB="$DIR/.memory-bank"
STALE_DAYS=30
WARNINGS=0

if [ ! -d "$MB" ]; then
  echo "drift_warnings=1"
  echo "drift_check_bank=warn"
  echo "[drift:bank] .memory-bank/ not found in $DIR" >&2
  exit 1
fi

_mtime() { stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0; }

warn() {
  echo "drift_check_${1}=warn"
  echo "[drift:${1}] ${2}" >&2
  WARNINGS=$(( WARNINGS + 1 ))
}

ok()   { echo "drift_check_${1}=ok"; }
skip() { echo "drift_check_${1}=skip"; echo "[drift:${1} skipped] ${2}" >&2; }

# ═══ 1. path — linked MB files exist ═══
check_path() {
  local count=0 file
  for file in "$MB"/status.md "$MB"/roadmap.md "$MB"/checklist.md "$MB"/backlog.md; do
    [ -f "$file" ] || continue
    while read -r ref; do
      [ -z "$ref" ] && continue
      if [ ! -e "$MB/$ref" ]; then
        count=$(( count + 1 ))
        echo "  - $(basename "$file") -> $ref not found" >&2
      fi
    done < <(grep -oE '(notes|plans|reports|experiments)/[A-Za-z0-9_\-]+\.md' "$file" 2>/dev/null | sort -u)
  done
  if [ "$count" -gt 0 ]; then warn path "$count broken references"; else ok path; fi
}

# ═══ 2. staleness — core files are newer than 30 days ═══
check_staleness() {
  local count=0 now file name age
  now=$(date +%s)
  for file in "$MB"/status.md "$MB"/roadmap.md "$MB"/checklist.md "$MB"/progress.md; do
    [ -f "$file" ] || continue
    age=$(( (now - $(_mtime "$file")) / 86400 ))
    if [ "$age" -gt "$STALE_DAYS" ]; then
      name=$(basename "$file")
      count=$(( count + 1 ))
      echo "  - $name has not been updated for $age days (threshold $STALE_DAYS)" >&2
    fi
  done
  if [ "$count" -gt 0 ]; then warn staleness "$count stale core files"; else ok staleness; fi
}

# ═══ 3. script-coverage — `bash scripts/X.sh` references exist ═══
check_script_coverage() {
  local count=0 file ref
  for file in "$MB"/status.md "$MB"/roadmap.md "$MB"/checklist.md "$MB"/backlog.md; do
    [ -f "$file" ] || continue
    while read -r ref; do
      [ -z "$ref" ] && continue
      if [ ! -e "$DIR/$ref" ] && [ ! -e "$HOME/.claude/skills/memory-bank/$ref" ]; then
        count=$(( count + 1 ))
        echo "  - $(basename "$file") -> $ref not found" >&2
      fi
    done < <(grep -oE 'bash scripts/[A-Za-z0-9_\-]+\.sh' "$file" 2>/dev/null | awk '{print $2}' | sort -u)
  done
  if [ "$count" -gt 0 ]; then warn script_coverage "$count missing scripts"; else ok script_coverage; fi
}

# ═══ 4. dependency — Python version in STATUS vs `pyproject.toml` ═══
check_dependency() {
  local py_status py_proj
  if [ ! -f "$DIR/pyproject.toml" ] && [ ! -f "$DIR/package.json" ] && [ ! -f "$DIR/go.mod" ]; then
    skip dependency "no project deps file"
    return
  fi
  # Compare Python: "Python 3.X" in STATUS vs `requires-python` in pyproject
  if [ -f "$DIR/pyproject.toml" ] && [ -f "$MB/status.md" ]; then
    py_status=$(grep -oE 'Python[[:space:]]+3\.[0-9]+' "$MB/status.md" 2>/dev/null | head -1 | grep -oE '3\.[0-9]+' || true)
    py_proj=$(grep -oE 'requires-python[^"]*"[^"]+' "$DIR/pyproject.toml" 2>/dev/null | grep -oE '3\.[0-9]+' | head -1 || true)
    if [ -n "$py_status" ] && [ -n "$py_proj" ] && [ "$py_status" != "$py_proj" ]; then
      warn dependency "STATUS Python=$py_status vs pyproject=$py_proj"
      return
    fi
  fi
  ok dependency
}

# ═══ 5. cross-file — numeric consistency across MB files ═══
# Check pattern `NNN <unit>` where unit = tests|bats|pytest — values must match
# between `status.md` and `checklist.md`/`progress.md` when mentioned in both.
check_cross_file() {
  local st ch count=0 other
  [ -f "$MB/status.md" ] || { ok cross_file; return; }
  # Extract the first "N bats green" from STATUS.
  st=$(grep -oE '[0-9]+ bats green' "$MB/status.md" 2>/dev/null | head -1 | awk '{print $1}' || true)
  if [ -n "${st:-}" ]; then
    for other in "$MB/checklist.md" "$MB/progress.md"; do
      [ -f "$other" ] || continue
      ch=$(grep -oE '[0-9]+ bats green' "$other" 2>/dev/null | head -1 | awk '{print $1}' || true)
      if [ -n "${ch:-}" ] && [ "$ch" != "$st" ]; then
        count=$(( count + 1 ))
        echo "  - STATUS=$st tests vs $(basename "$other")=$ch" >&2
      fi
    done
  fi
  if [ "$count" -gt 0 ]; then warn cross_file "$count mismatches"; else ok cross_file; fi
}

# ═══ 6. index-sync — `index.json` is newer than all notes ═══
check_index_sync() {
  local idx_mt note_mt file
  if [ ! -f "$MB/index.json" ]; then
    skip index_sync "no index.json"
    return
  fi
  idx_mt=$(_mtime "$MB/index.json")
  for file in "$MB"/notes/*.md; do
    [ -f "$file" ] || continue
    note_mt=$(_mtime "$file")
    if [ "$note_mt" -gt "$idx_mt" ]; then
      warn index_sync "$(basename "$file") is newer than index.json"
      return
    fi
  done
  ok index_sync
}

# ═══ 7. command — `npm run X` / `make X` references exist ═══
check_command() {
  local count=0 file target
  # npm run X
  if [ -f "$DIR/package.json" ]; then
    for file in "$MB"/status.md "$MB"/roadmap.md "$MB"/checklist.md; do
      [ -f "$file" ] || continue
      while read -r target; do
        [ -z "$target" ] && continue
        if ! grep -qE "\"$target\"[[:space:]]*:" "$DIR/package.json" 2>/dev/null; then
          count=$(( count + 1 ))
          echo "  - $(basename "$file") -> npm run $target (no script)" >&2
        fi
      done < <(grep -oE 'npm run [A-Za-z0-9_\-]+' "$file" 2>/dev/null | awk '{print $3}' | sort -u)
    done
  fi
  # make X
  if [ -f "$DIR/Makefile" ]; then
    for file in "$MB"/status.md "$MB"/roadmap.md; do
      [ -f "$file" ] || continue
      while read -r target; do
        [ -z "$target" ] && continue
        if ! grep -qE "^$target:" "$DIR/Makefile" 2>/dev/null; then
          count=$(( count + 1 ))
          echo "  - $(basename "$file") -> make $target (no target)" >&2
        fi
      done < <(grep -oE 'make [A-Za-z][A-Za-z0-9_\-]+' "$file" 2>/dev/null | awk '{print $2}' | sort -u)
    done
  fi
  if [ "$count" -gt 0 ]; then warn command "$count missing commands"; else ok command; fi
}

# ═══ 8. frontmatter — note YAML is valid (closing fence present) ═══
check_frontmatter() {
  local count=0 file
  for file in "$MB"/notes/*.md; do
    [ -f "$file" ] || continue
    # First non-empty line must be `---`; then look for a closing fence before EOF.
    local has_fence_open has_fence_close
    has_fence_open=$(head -1 "$file" | grep -c '^---$' || true)
    if [ "$has_fence_open" -eq 0 ]; then
      continue  # no frontmatter — not drift, just a note without a header
    fi
    has_fence_close=$(awk 'NR>1 && /^---$/ {print; exit}' "$file" | wc -l | tr -d ' ')
    if [ "$has_fence_close" -eq 0 ]; then
      count=$(( count + 1 ))
      echo "  - $(basename "$file") frontmatter is not closed" >&2
    fi
  done
  if [ "$count" -gt 0 ]; then warn frontmatter "$count malformed notes"; else ok frontmatter; fi
}

# ═══ 9. research_experiments — H-NNN Confirmed/Refuted ↔ experiments/EXP-NNN.md ═══
# For every hypothesis that reports a definitive outcome (Confirmed/Refuted) in
# research.md, the matching experiments/EXP-NNN.md must exist on disk. Otherwise
# the knowledge trail is broken and future sessions cannot inspect the evidence.
check_research_experiments() {
  local research="$MB/research.md"
  if [ ! -f "$research" ]; then
    skip research_experiments "research.md not found"
    return
  fi
  local count=0 id num file_expected
  # Extract rows of the form "| H-NNN | ... | ✅ Confirmed | ... |" or "❌ Refuted".
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    num="${id#H-}"
    file_expected="$MB/experiments/EXP-${num}.md"
    if [ ! -f "$file_expected" ]; then
      count=$(( count + 1 ))
      echo "  - ${id} has definitive status but experiments/EXP-${num}.md is missing" >&2
    fi
  done < <(grep -E '^\| *H-[0-9]+ *\|' "$research" 2>/dev/null \
           | grep -E 'Confirmed|Refuted' \
           | sed -nE 's/^\| *(H-[0-9]+) *\|.*/\1/p')
  if [ "$count" -gt 0 ]; then
    warn research_experiments "$count hypothesis/experiment gap(s)"
  else
    ok research_experiments
  fi
}

# ═══ 10. terminology — legacy Cyrillic planning terms outside whitelist ═══
# Canonical hierarchy is Phase → Sprint → Stage (references/templates.md §
# Plan decomposition). Cyrillic «Этап / Эпик / Спринт / Фаза» are legacy
# aliases that are allowed in archived `plans/done/`, in `lessons.md`,
# `progress.md`, `CHANGELOG.md`, and in the SSoT `references/templates.md`
# itself. Active surface (`commands/`, `rules/`, `references/` minus the
# SSoT, `SKILL.md`, `README.md`, and live MB core files) must not contain
# them — otherwise the convention drifts file by file.
check_terminology() {
  local count=0
  # Build a list of candidate files. Use `find` rather than `git grep` so the
  # checker also works on a fresh `mb-init`'d project that is not yet tracked.
  local files=()
  for f in \
    "$DIR/SKILL.md" \
    "$DIR/README.md" \
    "$MB/status.md" \
    "$MB/checklist.md" \
    "$MB/roadmap.md" \
    "$MB/research.md" \
    "$MB/backlog.md"
  do
    [ -f "$f" ] && files+=("$f")
  done
  # commands/ + rules/ + references/ (active surface).
  while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
  done < <(find "$DIR/commands" "$DIR/rules" "$DIR/references" -maxdepth 3 -type f -name '*.md' 2>/dev/null \
            | grep -v 'references/templates\.md$' || true)
  # active plans/ — but NOT plans/done/ (frozen archive).
  while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
  done < <(find "$MB/plans" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)

  # Lines that explicitly mark the term as legacy / alias / Cyrillic, or that
  # quote it via French quotes «...», are meta-references documenting the
  # convention itself — not drift. We skip them before counting.
  for f in "${files[@]:-}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    local hits
    # Skip meta-references: lines that mark the term as legacy/alias, lines
    # quoting the term in `«...»` or backticks (regex literals or code spans
    # such as `\b(Этап|Спринт)\b`), and TDD jargon (`RED-фаза`, `GREEN-фаза`).
    hits=$(grep -iE '\b(Этап|Эпик|Спринт|Фаза)\b' "$f" 2>/dev/null \
            | grep -ivE 'legacy|alias|Cyrillic|«|»|deprecat' \
            | grep -vE '\\b\(' \
            | grep -ivE 'red-фаза|green-фаза|refactor-фаза|test-фаза' \
            | grep -vE "\`[^\`]*(Этап|Эпик|Спринт|[Фф]аза)[^\`]*\`" \
            || true)
    if [ -n "$hits" ]; then
      count=$(( count + 1 ))
      echo "  - $(basename "$f") contains legacy Cyrillic planning term" >&2
    fi
  done

  if [ "$count" -gt 0 ]; then
    warn terminology "$count file(s) with legacy Cyrillic planning terms"
  else
    ok terminology
  fi
}

# ═══ Run all checks ═══
check_path
check_staleness
check_script_coverage
check_dependency
check_cross_file
check_index_sync
check_command
check_frontmatter
check_research_experiments
check_terminology

echo "drift_warnings=$WARNINGS"

[ "$WARNINGS" -eq 0 ] && exit 0 || exit 1
