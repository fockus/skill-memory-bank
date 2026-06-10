#!/usr/bin/env bash
# mb-drift.sh — 14 deterministic drift checkers for Memory Bank (no AI required).
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

  # Only flag the terms when used as a decomposition MARKER — a markdown heading
  # (`## Этап 1`) or a table row (`| Фаза | … |`). Incidental Russian prose nouns
  # and their declensions ("каждый этап", "эта фаза", "этапы") are NOT drift and
  # must not be flagged — BSD grep `\b` cannot word-boundary Cyrillic, so a plain
  # whole-word match false-positives on every Russian sentence. Heading/table
  # anchoring is the deterministic signal of an actual hierarchy marker.
  for f in "${files[@]:-}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    local hits
    # Skip meta-references: lines marking the term as legacy/alias/Cyrillic, or
    # quoting it in `«...»` / backticks (regex literals or code spans).
    # shellcheck disable=SC2016 # Single quotes keep the regex literal for grep.
    # Marker = the term as the FIRST word of a heading (`## Этап 1`), or a table
    # cell that STARTS with the term (`| Фаза |`, `| Этапы |`). Prose inside a
    # heading tail or a data cell (e.g. `… **КРОСС-ФАЗА:** …`) is NOT a marker.
    hits=$(grep -inE '^#{1,6}[[:space:]]+(Этап|Эпик|Спринт|Фаза)|\|[[:space:]]*(Этап|Эпик|Спринт|Фаза)[^|]*\|' "$f" 2>/dev/null \
            | grep -ivE 'legacy|alias|Cyrillic|«|»|deprecat' \
            | grep -vE '`[^`]*(Этап|Эпик|Спринт|[Фф]аза)[^`]*`' \
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

# ═══ 11. uncommitted — stale "uncommitted/не закоммичено" tags (verify vs git) ═══
check_uncommitted() {
  local hits
  # `|| true` keeps a no-match grep (exit 1) from tripping `set -euo pipefail`.
  hits=$( { grep -ihE 'uncommitted|не закоммич|не коммичено' \
           "$MB/status.md" "$MB/checklist.md" 2>/dev/null || true; } | wc -l | tr -d ' ')
  if [ "${hits:-0}" -gt 0 ]; then
    warn uncommitted "$hits 'uncommitted' tag(s) in status/checklist — verify vs git (git log -S<token> --all -- <path>); strip if committed"
  else
    ok uncommitted
  fi
}

# ═══ 12. active_plans — status.md vs roadmap.md divergence + done-plan still listed ═══
check_active_plans() {
  local issues=0 s_block r_block listed p base
  # `|| true` keeps no-match grep (exit 1) from tripping `set -euo pipefail`.
  s_block=$(sed -n '/<!-- mb-active-plans -->/,/<!-- \/mb-active-plans -->/p' "$MB/status.md" 2>/dev/null \
              | { grep -oE 'plans/[A-Za-z0-9_./-]+\.md' || true; } | sort -u)
  r_block=$(sed -n '/<!-- mb-active-plans -->/,/<!-- \/mb-active-plans -->/p' "$MB/roadmap.md" 2>/dev/null \
              | { grep -oE 'plans/[A-Za-z0-9_./-]+\.md' || true; } | sort -u)
  if [ -n "$s_block" ] && [ -n "$r_block" ] && [ "$s_block" != "$r_block" ]; then
    issues=$(( issues + 1 ))
    echo "  - status.md and roadmap.md mb-active-plans blocks diverge" >&2
  fi
  listed=$(printf '%s\n%s\n' "$s_block" "$r_block" | sort -u)
  while read -r p; do
    [ -z "$p" ] && continue
    base=$(basename "$p")
    if [ -f "$MB/plans/done/$base" ]; then
      issues=$(( issues + 1 ))
      echo "  - $base is in plans/done/ but still listed as active" >&2
    fi
  done <<< "$listed"
  if [ "$issues" -gt 0 ]; then
    warn active_plans "$issues active-plans inconsistency(ies) — regenerate via mb-roadmap-sync.sh / drop done plans"
  else
    ok active_plans
  fi
}

# ═══ 13. plan_status — frontmatter status: outside canonical vocabulary ═══
# Canonical plan statuses: queued | in_progress | done | blocked. roadmap-sync
# only renders Now/Next from in_progress/queued, so non-canonical values
# (active/planned/…) silently drop a plan off the roadmap. Deterministic; the
# "prose says X but reality is Y" semantic lie stays a /mb verify / mb-doctor job.
check_plan_status() {
  local count=0 f st base
  local canon="queued in_progress done blocked paused"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    st=$(awk 'NR==1&&/^---$/{i=1;next} i&&/^---$/{exit} i&&/^status:/{sub(/^status:[[:space:]]*/,"");gsub(/["'\'' ]/,"");print;exit}' "$f")
    [ -n "$st" ] || continue
    case " $canon " in
      *" $st "*) : ;;
      *) count=$(( count + 1 )); base=$(basename "$f")
         echo "  - $base: non-canonical status '$st' (use one of: $canon)" >&2 ;;
    esac
  done < <(find "$MB/plans" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)
  if [ "$count" -gt 0 ]; then
    warn plan_status "$count plan(s) with non-canonical status: (canonical: $canon)"
  else
    ok plan_status
  fi
}

# ═══ 14. plan_vs_git — MB plan claims vs git reality (shipped-but-not-closed) ═══
# A plan whose frontmatter says status: queued|in_progress while its declared target files
# already have commits dated AFTER the plan is almost certainly implemented-but-not-closed —
# the exact drift that left deep-search-v2 reading as "code NOT touched / queued" after the
# epic had shipped. This is the fail-loud guardrail for Memory Bank itself: such drift becomes
# a deterministic warn (exit≠0) instead of a silent state a fresh agent reads as "not started".
#
# Signal (low false-positive): declared file = backtick-wrapped path token containing a '/' and an
# extension (the `Create:`/`Modify:` convention). "After the plan" is keyed off the plan's
# YYYY-MM-DD filename prefix, so pre-existing modify-targets (committed before the plan) do NOT
# trip it. Advisory only. Requires a git repo and a dated plan filename; otherwise skip the plan.
# NOTE: only canonical YAML-frontmatter `status:` plans are assessed; legacy bold-field
# («**Статус:**») plans are invisible here by design (migrate them to frontmatter).
check_plan_vs_git() {
  if ! git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
    skip plan_vs_git "not a git repo"
    return
  fi
  local dir_abs count=0 f st base plan_date tok rel impl
  dir_abs=$(cd "$DIR" && pwd)
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    st=$(awk 'NR==1&&/^---$/{i=1;next} i&&/^---$/{exit} i&&/^status:/{sub(/^status:[[:space:]]*/,"");gsub(/["'\'' ]/,"");print;exit}' "$f")
    case "$st" in
      queued | in_progress) : ;;
      *) continue ;;
    esac
    base=$(basename "$f")
    plan_date=$(printf '%s' "$base" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    [ -n "$plan_date" ] || continue
    impl=0
    # shellcheck disable=SC2016 # Single quotes keep the backtick literal for the grep regex.
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      if [ -f "$DIR/$tok" ]; then
        rel="$tok"
      elif [ "${tok#/}" != "$tok" ] && [ -f "$tok" ]; then
        case "$tok" in
          "$dir_abs"/*) rel="${tok#"$dir_abs"/}" ;;
          *) continue ;;
        esac
      else
        continue
      fi
      if [ -n "$(git -C "$DIR" log --since="$plan_date 00:00:00" --pretty=%h -- "$rel" 2>/dev/null)" ]; then
        impl=$(( impl + 1 ))
      fi
    done < <(grep -oE '`[A-Za-z0-9_./-]+/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+`' "$f" 2>/dev/null | tr -d '`' | sort -u)
    if [ "$impl" -gt 0 ]; then
      count=$(( count + 1 ))
      echo "  - $base: status=$st but $impl declared file(s) committed after plan date ($plan_date) — likely done; run /mb done or correct status" >&2
    fi
  done < <(find "$MB/plans" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)
  if [ "$count" -gt 0 ]; then
    warn plan_vs_git "$count plan(s) shipped-but-not-closed (MB status vs git) — fail-loud guard"
  else
    ok plan_vs_git
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
check_uncommitted
check_active_plans
check_plan_status
check_plan_vs_git

echo "drift_warnings=$WARNINGS"

[ "$WARNINGS" -eq 0 ] && exit 0 || exit 1
