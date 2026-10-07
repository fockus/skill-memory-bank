#!/usr/bin/env bats
# agents-md-diet gate (plan 2026-10-06_fix_agents-md-diet, AGR-063 / AGR-066):
# every always-loaded instruction file stays small, carries no copy of
# rules/RULES.md, opens with the Key rules block and points at the detailed
# rules instead. Budgets are measured on the default Key rules selection
# (empty temp HOME, no rules profile) with the skill path normalized to `/SKILL`,
# so a long install path cannot flip the gate. Split budget (plan owner,
# 2026-10-07): Key rules <= 3072 B, MB block <= 1536 B, project block and the
# per-host rule files <= 4608 B, global host files <= 8192 B. The project
# AGENTS.md / CLAUDE.md carry only the project's Key rules differences (AGR-083):
# with none, that block stays <= 300 B; the full block is still gated at 3072 B
# (global files, Windsurf/Cline/Kilo rule files).
#
# The global host files (Stage 3) are gated here too.

load lib/assert

KR_BUDGET=3072
KR_DELTA_BUDGET=300
MB_BUDGET=1536
PROJECT_BUDGET=4608
GLOBAL_BUDGET=8192

# Headings that only a pasted copy of rules/RULES.md would bring along.
RULES_HEADINGS=(
  '# Global Rules'
  '## Source of Truth'
  '### Contract-First Development'
  '## Coding Standards'
  '## Tests — Testing Trophy'
  '## Cross-session coordination'
)

KR_START='<!-- mb-key-rules:start -->'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$HOME" "$PROJECT"
  command -v jq >/dev/null || skip "jq required"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/adapters/_lib_agents_md.sh"
  # Worst case: the pi/opencode extensions nudge is on.
  SECTION_FILE="$BATS_TEST_TMPDIR/section.md"
  _agents_md_section "$REPO_ROOT" 1 "$PROJECT" > "$SECTION_FILE"
}

_size() { wc -c < "$1" | tr -d ' '; }

# Byte size of FILE (or of stdin with FILE = -) with ROOT replaced by /SKILL.
_norm_size() {
  local body root="$2"
  body="$(cat "$1")"
  printf '%s\n' "${body//"$root"//SKILL}" | wc -c | tr -d ' '
}

_refute_rules_copy() {
  local body="$1" heading
  for heading in "${RULES_HEADINGS[@]}"; do
    refute_substring "$body" "$heading"
  done
}

# Installs every client into a temp HOME + temp git project from a copy of the
# repo (the real ~/.codex, ~/.pi, ... are never touched).
_install_all_clients() {
  local src="$BATS_TEST_TMPDIR/skill"
  mkdir -p "$src"
  rsync -a --exclude='.git' --exclude='.index' --exclude='.memsearch' \
    --exclude='/tests' --exclude='node_modules' --exclude='.venv' \
    --exclude='/.memory-bank' "$REPO_ROOT/" "$src/"
  git -C "$PROJECT" init -q
  MB_SKIP_DEPS_CHECK=1 bash "$src/install.sh" \
    --clients claude-code,cursor,windsurf,cline,kilo,opencode,pi,codex \
    --project-root "$PROJECT" --non-interactive </dev/null >/dev/null 2>&1
}

@test "budget: project block fits ${PROJECT_BUDGET} B, Key rules ${KR_DELTA_BUDGET} B (full ${KR_BUDGET} B), MB block ${MB_BUDGET} B (skill path normalized)" {
  local whole kr full mb
  whole="$(_norm_size "$SECTION_FILE" "$REPO_ROOT")"
  kr="$(sed -n '/mb-key-rules:start/,/mb-key-rules:end/p' "$SECTION_FILE" | _norm_size - "$REPO_ROOT")"
  full="$(_agents_md_key_rules "$PROJECT" full | _norm_size - "$REPO_ROOT")"
  mb="$(sed -n '/memory-bank:start/,/memory-bank:end/p' "$SECTION_FILE" | _norm_size - "$REPO_ROOT")"
  echo "project block: $whole B (Key rules $kr B, full $full B, MB block $mb B)" >&2
  [ "$whole" -le "$PROJECT_BUDGET" ]
  [ "$kr" -le "$KR_DELTA_BUDGET" ]
  [ "$full" -gt "$KR_DELTA_BUDGET" ]
  [ "$full" -le "$KR_BUDGET" ]
  [ "$mb" -le "$MB_BUDGET" ]
}

@test "budget: project block carries no copy of rules/RULES.md" {
  _refute_rules_copy "$(cat "$SECTION_FILE")"
}

@test "budget: Key rules is the first section of the project block" {
  [ "$(head -n 1 "$SECTION_FILE")" = "$KR_START" ]
  assert_substring "$(cat "$SECTION_FILE")" '## Key rules'
}

@test "budget: installed AGENTS.md orders language, Key rules, MB block, agreements; reinstall is byte-identical" {
  cat > "$PROJECT/AGENTS.md" <<'EOF'
<!-- mb-language:start -->
Respond in Russian.
<!-- mb-language:end -->

<!-- mb-agreements:start -->
## Active Agreements
- AGR-001: example
<!-- mb-agreements:end -->

# User notes
EOF
  agents_md_install "$PROJECT" codex "$REPO_ROOT" >/dev/null
  local order
  order="$(grep -oE '<!-- (mb-language|mb-key-rules|memory-bank|mb-agreements):start -->' "$PROJECT/AGENTS.md" | tr '\n' ' ')"
  [ "$order" = "<!-- mb-language:start --> <!-- mb-key-rules:start --> <!-- memory-bank:start --> <!-- mb-agreements:start --> " ]
  assert_substring "$(cat "$PROJECT/AGENTS.md")" '# User notes'

  cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/first"
  agents_md_install "$PROJECT" opencode "$REPO_ROOT" >/dev/null
  agents_md_install "$PROJECT" opencode "$REPO_ROOT" >/dev/null
  # opencode adds the extensions nudge; a third run must change nothing.
  cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/second"
  agents_md_install "$PROJECT" opencode "$REPO_ROOT" >/dev/null
  cmp "$BATS_TEST_TMPDIR/second" "$PROJECT/AGENTS.md"
  [ "$(grep -c "$KR_START" "$PROJECT/AGENTS.md")" -eq 1 ]
}

@test "budget: project block points at the project's local RULES.md, not a global one (AGR-066)" {
  mkdir -p "$PROJECT/.memory-bank"
  echo '# My rules' > "$PROJECT/.memory-bank/RULES.md"
  local body
  body="$(_agents_md_section "$REPO_ROOT" 1 "$PROJECT")"
  # shellcheck disable=SC2016
  assert_substring "$body" '`.memory-bank/RULES.md`'
  # shellcheck disable=SC2088
  refute_substring "$body" '~/.claude/RULES.md'
  # Without the Key rules block (render failed) the MB block carries the pointer itself.
  # shellcheck disable=SC2016
  assert_substring "$(_agents_md_mb_block "$REPO_ROOT" 0 0)" '`.memory-bank/RULES.md`'
}

@test "budget: rules/RULES.md pointers in the project block resolve to the installed skill" {
  local paths p
  paths="$(grep -oE '/[^ `]*rules/RULES\.md' "$SECTION_FILE" | sort -u)"
  [ -n "$paths" ]
  while IFS= read -r p; do
    [ -f "$p" ]
  done <<< "$paths"
}

@test "budget: global Codex/Pi/OpenCode/Cursor AGENTS.md fit ${GLOBAL_BUDGET} bytes, open with Key rules, point at the global RULES.md" {
  _install_all_clients
  local f size
  for f in "$HOME/.codex/AGENTS.md" "$HOME/.pi/agent/AGENTS.md" \
           "$HOME/.config/opencode/AGENTS.md" "$HOME/.cursor/AGENTS.md"; do
    [ -f "$f" ]
    size="$(_size "$f")"
    echo "$f: $size bytes" >&2
    [ "$size" -le "$GLOBAL_BUDGET" ]
    _refute_rules_copy "$(cat "$f")"
    # No retelling of the rules the Key rules block already carries.
    refute_grep -qF 'Engineering baseline' "$f"
    [ "$(grep -m1 -E '^<!-- ' "$f")" = "$KR_START" ]
    assert_substring "$(cat "$f")" 'skills/memory-bank/rules/RULES.md'
  done
}

@test "budget: Cursor .mdc and Windsurf/Cline/Kilo rule files fit ${PROJECT_BUDGET} B, carry Key rules once, no RULES.md copy" {
  _install_all_clients
  local f size src="$BATS_TEST_TMPDIR/skill"
  for f in "$PROJECT/.cursor/rules/memory-bank.mdc" "$PROJECT/.windsurf/rules/memory-bank.md" \
           "$PROJECT/.clinerules/memory-bank.md" "$PROJECT/.kilocode/rules/memory-bank.md"; do
    [ -f "$f" ]
    size="$(_norm_size "$f" "$src")"
    echo "$f: $size B" >&2
    [ "$size" -le "$PROJECT_BUDGET" ]
    _refute_rules_copy "$(cat "$f")"
    if [ "$f" = "$PROJECT/.cursor/rules/memory-bank.mdc" ]; then
      # Cursor also loads the project AGENTS.md, which carries the Key rules
      # (install.sh runs the cursor client after codex/opencode/pi).
      assert_grep -qF "$KR_START" "$PROJECT/AGENTS.md"
      refute_substring "$(cat "$f")" "$KR_START"
    else
      # No global instructions file on these hosts: the full block (AGR-083).
      assert_substring "$(cat "$f")" "$KR_START"
      assert_substring "$(cat "$f")" 'TDD: new logic'
      refute_substring "$(cat "$f")" 'Global Key rules apply'
    fi
    # These hosts load no skill — the detailed rules are read by absolute path.
    assert_grep -qF "\`$src/rules/RULES.md\`" "$f"
    [ -f "$src/rules/RULES.md" ]
  done
}
