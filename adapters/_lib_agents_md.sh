#!/usr/bin/env bash
# adapters/_lib_agents_md.sh — shared AGENTS.md management library.
#
# AGENTS.md is the shared-format instructions file used by OpenCode, Codex,
# and Pi Code (fallback). Cline also auto-reads it. Multiple MB adapters may
# install simultaneously — this library coordinates ownership via a refcount
# file .mb-agents-owners.json in the project root.
#
# Design:
#   - Single shared MB section between <!-- memory-bank:start/end --> markers
#   - .mb-agents-owners.json tracks which clients currently reference the section
#   - First installer (empty owners list) becomes responsible for file creation;
#     we record initial_had_user_content to decide uninstall behavior
#   - Uninstall decrements owners; when list empty → remove section (and file,
#     if initial_had_user_content == false)
#
# Usage (source into adapter):
#   . "$(dirname "$0")/_lib_agents_md.sh"
#   agents_md_install  <project_root> <client_name> <skill_dir>
#   agents_md_uninstall <project_root> <client_name>

MB_START_MARKER="<!-- memory-bank:start -->"
MB_END_MARKER="<!-- memory-bank:end -->"

_owners_require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "[agents-md] jq required" >&2
    return 1
  }
}

mb_preferred_language() {
  printf '%s' "${MB_LANGUAGE:-${LANGUAGE:-en}}"
}

# Emit a rules file with its language lines localized through the same
# memory_bank_skill._texttools strings install.sh uses (responses + code comments,
# MB_LANGUAGE / MB_COMMENTS_LANGUAGE; unknown codes fall back to English).
mb_emit_rules_file() {
  local rules_file="$1"
  if [ ! -f "$rules_file" ]; then
    return 1
  fi

  # Prefer the interpreter the CLI handed us (MB_PYTHON); fall back to python3.
  local py="${MB_PYTHON:-python3}"
  if ! command -v "$py" >/dev/null 2>&1; then
    cat "$rules_file"
    return 0
  fi

  local skill_root
  skill_root="$(cd "$(dirname "$rules_file")/.." && pwd)"
  TARGET_RULES_FILE="$rules_file" \
  MB_RULE_LANGUAGE="$(mb_preferred_language)" \
  MB_RULE_COMMENTS_LANGUAGE="${MB_COMMENTS_LANGUAGE:-}" \
  PYTHONPATH="$skill_root${PYTHONPATH:+:$PYTHONPATH}" \
  "$py" <<'PYEOF'
import os
import sys
from pathlib import Path

from memory_bank_skill._texttools import localize_language_text, resolve_language_strings

strings = resolve_language_strings(
    os.environ["MB_RULE_LANGUAGE"], os.environ.get("MB_RULE_COMMENTS_LANGUAGE") or None
)
text = Path(os.environ["TARGET_RULES_FILE"]).read_text(encoding="utf-8")
sys.stdout.write(localize_language_text(
    text,
    rule_full=strings.rule_full,
    rule_short=strings.rule_short,
    comments_language=strings.comments_language,
))
PYEOF
}

# L-4: version tag for the shared block, so a stale block can be reliably
# identified/found across skill upgrades. Rides in a dedicated line INSIDE
# the block rather than being spliced into $MB_START_MARKER itself — other
# adapters' test suites assert on the exact marker string
# (`<!-- memory-bank:start -->`) literally, so that text must stay stable.
# Best-effort: some callers (isolated test fixtures) have no VERSION file.
_mb_skill_version() {
  local skill_dir="$1"
  if [ -f "$skill_dir/VERSION" ]; then
    tr -d '[:space:]' < "$skill_dir/VERSION"
  else
    echo "unknown"
  fi
}

# Write SECTION_FILE (a block that carries its own START/END marker lines) into
# FILE: replace the existing block, or append it after the user's content, or
# create the file. Blank lines left before the block are trimmed each time, so a
# reinstall never grows the file. Prints `created`, `refreshed`, or `merged`.
#
# POSITION=top (5th arg) puts the block at the top of the file instead — right
# after the line holding ANCHOR (6th arg, e.g. the mb-language end marker) when
# present — one blank line around it, the rest of the file byte-for-byte. Top
# mode writes atomically (temp file + mv), so FILE must be a real path, not a
# symlink (the caller resolves it).
mb_upsert_marked_block() {
  local file="$1" start="$2" end="$3" section="$4" position="${5:-end}" anchor="${6:-}"
  local state=merged kept tmp
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then
    cat "$section" > "$file"
    echo created
    return 0
  fi
  grep -qF -- "$start" "$file" && state=refreshed
  if [ "$position" = top ]; then
    tmp="$(mktemp "$file.XXXXXX")"
    cp -p "$file" "$tmp"  # keep FILE's mode; mktemp creates 0600
    awk -v s="$start" -v e="$end" -v a="$anchor" -v sec="$section" '
      index($0, s) { inside = 1; next }
      index($0, e) { inside = 0; next }
      !inside { lines[++n] = $0; if (a != "" && !at && index($0, a)) at = n }
      END {
        for (i = 1; i <= at; i++) print lines[i]
        if (at) print ""
        while ((getline l < sec) > 0) print l
        for (i = at + 1; i <= n && lines[i] == ""; i++) ;
        if (i <= n) print ""
        for (; i <= n; i++) print lines[i]
      }
    ' "$file" > "$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
    echo "$state"
    return 0
  fi
  kept="$(mktemp)"
  awk -v s="$start" -v e="$end" '
    index($0, s) { inside = 1; next }
    index($0, e) { inside = 0; next }
    !inside { lines[++n] = $0; if (NF) last = n }
    END { for (i = 1; i <= last; i++) print lines[i] }
  ' "$file" > "$kept"
  {
    if [ -s "$kept" ]; then
      cat "$kept"
      printf '\n'
    fi
    cat "$section"
  } > "$file"
  rm -f "$kept"
  echo "$state"
}

# ───────── Build section content ─────────
# The project's AGENTS.md carries, top-down: the mb-language block (written by
# mb-language.py), the Key rules block (scripts/mb-rules.sh), the short MB block
# below, then the agreements block (mb-agree.sh). Detailed rules stay in the
# installed skill's rules/RULES.md and are read on demand (AGR-063, AGR-066).
MB_KR_START="<!-- mb-key-rules:start -->"
MB_KR_END="<!-- mb-key-rules:end -->"
MB_LANGUAGE_END="<!-- mb-language:end -->"
_MB_AGENTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# $1 = project_root, $2 = mode: delta (default — only the project's differences from
# the user-level rules, the host loads the full block from its global file, AGR-083)
# or full (hosts without a global instructions file). The Key rules block (with its
# markers), rendered by scripts/mb-rules.sh. Fail-open: prints nothing when it cannot render.
_agents_md_key_rules() {
  local project_root="$1" mode="${2:-delta}" rules_sh="$_MB_AGENTS_LIB_DIR/../scripts/mb-rules.sh" out
  [ -f "$rules_sh" ] && [ -d "$project_root" ] || return 0
  out="$(bash "$rules_sh" render --target=project --mode="$mode" --project="$project_root" 2>/dev/null)" || return 0
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

# $1 = skill_dir
# $2 = include_ext_nudge (0|1, default 0) — emit the extensions nudge only for
#      hosts that have parity extensions to offer (pi, opencode). Codex/cline/
#      kilo/windsurf share the AGENTS.md format but have no `--with-extensions`
#      target (REQ-020 is scoped to "a pi or opencode host").
# $3 = has_key_rules (0|1, default 0) — 1 when the Key rules block (which ends
#      with the project RULES.md pointer) sits right above; 0 adds the pointer here.
_agents_md_mb_block() {
  echo "$MB_START_MARKER"
  echo "<!-- memory-bank-skill-version: $(_mb_skill_version "$1") -->"
  _agents_md_mb_body "$@"
  echo "$MB_END_MARKER"
}

# The MB block without its markers — same arguments as _agents_md_mb_block.
# Also the body of the per-host rule files (mb_rule_file_body).
_agents_md_mb_body() {
  local skill_dir="$1"
  local include_ext_nudge="${2:-0}"
  local has_key_rules="${3:-0}"
  echo '## Memory Bank'
  echo "- Language: $(_mb_language_rule)"
  # shellcheck disable=SC2016
  echo '- First reply: `[MEMORY BANK: ACTIVE]` if a bank resolves (local or global), else `[MEMORY BANK: ABSENT]`; never init one unasked. Run `/mb context` first.'
  if [ "$has_key_rules" != "1" ]; then
    # The Key rules block normally carries this pointer (AGR-066).
    # shellcheck disable=SC2016
    echo '- Own rules: `RULES.md` / `.memory-bank/RULES.md`.'
  fi
  # shellcheck disable=SC2016
  echo '- Firewall: with `.memory-bank/goal.md`, done = `mb-flow-verify.sh` exit 0; on red, repair and re-run — never self-certify. Hookless Pi: a no-commit false-done shows only at commit-time.'
  # shellcheck disable=SC2016
  echo '- `/mb drive`: you are the runtime — loop `mb-drive.sh next --bank <bank>`, run the action, repeat until `stop_success|stop_human|stop_budget`; exact agent/model/thinking from `pipeline.yaml` roles (implement, codex review, judge); `stop_success` also needs `mb-goal-acceptance.sh` 100%; no goal: refuses (fix via `mb-goal-validate.sh`).'
  # shellcheck disable=SC2016
  echo '- GraphRAG-lite routing: `code_context` (`scripts/mb-code-context.py`) for fuzzy questions, `graph_neighbors|graph_impact|graph_tests` (`scripts/mb-graph-query.py`); fail open to grep.'
  if [ "$include_ext_nudge" = "1" ]; then
    # shellcheck disable=SC2016
    echo '- Bare Pi/OpenCode: offer `install.sh --with-extensions=pi,opencode` once per session.'
  fi
  if [ -f "$skill_dir/rules/RULES.md" ]; then
    echo "- Read \`$skill_dir/rules/RULES.md\` § TDD, § Architecture, § Tests, § Session Pipeline, § \`/mb work\` when the task touches them. Scripts named here live in \`$skill_dir/scripts/\`."
  fi
}

# The localized language rule (MB_LANGUAGE / MB_COMMENTS_LANGUAGE, same strings
# install.sh uses); English when python or the skill package is unavailable.
_mb_language_rule() {
  local py="${MB_PYTHON:-python3}" out=""
  if command -v "$py" >/dev/null 2>&1; then
    out="$(MB_RULE_LANGUAGE="$(mb_preferred_language)" \
      MB_RULE_COMMENTS_LANGUAGE="${MB_COMMENTS_LANGUAGE:-}" \
      PYTHONPATH="$_MB_AGENTS_LIB_DIR/..${PYTHONPATH:+:$PYTHONPATH}" \
      "$py" -c 'import os
from memory_bank_skill._texttools import resolve_language_strings as r
print(r(os.environ["MB_RULE_LANGUAGE"], os.environ.get("MB_RULE_COMMENTS_LANGUAGE") or None).rule_full)' 2>/dev/null)" || out=""
  fi
  printf '%s\n' "${out:-English — responses and code comments. Technical terms may remain in English.}"
}

# Per-host project rules file body (Cursor .mdc, Windsurf, Cline, Kilo — hosts
# that read one always-on file, no skill loading): title, Key rules, MB body.
# $1 = skill_dir, $2 = project_root, $3 = with_key_rules (1|0, default 1) —
# 0 when the project's AGENTS.md already carries the Key rules (Cursor reads both);
# $4 = Key rules mode: full (default — Windsurf/Cline/Kilo have no global
# instructions file) or delta (Cursor, which also loads ~/.cursor/AGENTS.md).
mb_rule_file_body() {
  local key_rules=""
  echo '# Memory Bank — Project Rules'
  echo ''
  echo 'This project uses Memory Bank for long-term memory + dev workflow.'
  echo ''
  [ "${3:-1}" = "1" ] && key_rules="$(_agents_md_key_rules "$2" "${4:-full}")"
  if [ -n "$key_rules" ]; then
    printf '%s\n\n' "$key_rules"
    _agents_md_mb_body "$1" 0 1
  else
    _agents_md_mb_body "$1" 0 0
  fi
}

# $1 = skill_dir, $2 = include_ext_nudge, $3 = project_root (default: $PWD).
# The full project section as it lands in AGENTS.md: Key rules, then the MB block.
_agents_md_section() {
  local key_rules
  key_rules="$(_agents_md_key_rules "${3:-$PWD}")"
  if [ -n "$key_rules" ]; then
    printf '%s\n\n' "$key_rules"
    _agents_md_mb_block "$1" "${2:-0}" 1
  else
    _agents_md_mb_block "$1" "${2:-0}" 0
  fi
}

# Drop the Key rules and MB blocks from FILE (stdout); everything else verbatim.
_agents_md_strip() {
  awk -v s="$MB_START_MARKER" -v e="$MB_END_MARKER" -v ks="$MB_KR_START" -v ke="$MB_KR_END" '
    index($0, s) || index($0, ks) { inside = 1; next }
    index($0, e) || index($0, ke) { inside = 0; next }
    !inside { print }
  ' "$1"
}

# ───────── Owners refcount helpers ─────────
_owners_file() { echo "$1/.mb-agents-owners.json"; }

_owners_read() {
  local f
  _owners_require_jq || return 1
  f=$(_owners_file "$1")
  if [ -f "$f" ]; then
    cat "$f"
  else
    jq -n '{owners: [], initial_had_user_content: false}'
  fi
}

_owners_write() {
  local pr="$1" data="$2"
  local target tmp
  _owners_require_jq || return 1
  target=$(_owners_file "$pr")
  # A14 (M-6): BSD mktemp only randomizes a *trailing* run of X's — the old
  # "$target.XXXXXX.tmp" template has a literal suffix after the X's, so BSD
  # never randomizes it. A leftover from an interrupted prior run (crash
  # between mktemp and mv) then collides with EEXIST on the next install.
  # Keep the tmp file in the same directory (atomic same-filesystem mv) with
  # the random run as the very last path component.
  tmp=$(mktemp "$(dirname "$target")/.mb-agents-owners.XXXXXXXX")
  printf '%s\n' "$data" > "$tmp"
  mv "$tmp" "$target"
}

# Write the Key rules + MB blocks at the top of AGENTS.md (after the mb-language
# block when present); user content and other managed blocks (agreements) follow
# verbatim. Old blocks are dropped first, together with the trailing blank run, so
# a file from the old layout (MB block appended at the end) migrates cleanly and
# every re-install is byte-identical.
_agents_md_write() {
  local file="$1" skill_dir="$2" nudge="$3" project_root="$4" real kr mb tmp rc=0
  real="$file"
  if [ -L "$file" ]; then
    real="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$file")" || return 1
  fi
  kr="$(mktemp)"
  mb="$(mktemp)"
  _agents_md_key_rules "$project_root" > "$kr"
  if [ -s "$kr" ]; then
    _agents_md_mb_block "$skill_dir" "$nudge" 1 > "$mb"
  else
    _agents_md_mb_block "$skill_dir" "$nudge" 0 > "$mb"
  fi
  if [ -f "$real" ]; then
    tmp="$(mktemp "$real.XXXXXX")"
    cp -p "$real" "$tmp"
    _agents_md_strip "$real" \
      | awk '{ l[++n] = $0; if (NF) last = n } END { for (i = 1; i <= last; i++) print l[i] }' > "$tmp" \
      && mv -f "$tmp" "$real" || { rm -f "$tmp"; rc=1; }
  fi
  if [ "$rc" -eq 0 ]; then
    mb_upsert_marked_block "$real" "$MB_START_MARKER" "$MB_END_MARKER" "$mb" top "$MB_LANGUAGE_END" >/dev/null || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ -s "$kr" ]; then
    mb_upsert_marked_block "$real" "$MB_KR_START" "$MB_KR_END" "$kr" top "$MB_LANGUAGE_END" >/dev/null || rc=1
  fi
  rm -f "$kr" "$mb"
  return "$rc"
}

# ───────── Install ─────────
# Ensures our MB section exists in AGENTS.md, registers client in owners list.
# Signature is unchanged (project_root, client, skill_dir) — no adapter call
# site needs editing: whether the "Host parity extensions" nudge (REQ-020)
# belongs in this project's AGENTS.md is derived below purely from $client
# (pi/opencode have parity extensions to offer; codex/cline/kilo/windsurf do
# not) and, for a shared file with multiple owning adapters, from the full
# current owners set — see effective_nudge below.
# Writes to stdout: "true" if this install created the file, "false" if user file existed.
agents_md_install() {
  local project_root="$1"
  local client="$2"
  local skill_dir="$3"
  local agents_md="$project_root/AGENTS.md"

  local owners
  owners=$(_owners_read "$project_root")

  # Add client to owners (dedupe) BEFORE deciding the nudge so the shared
  # AGENTS.md section (one file, multiple possible owning adapters) reflects
  # every current owner, not just the client installing right now — e.g. a
  # codex adapter re-running in a project that already has pi installed must
  # not silently strip pi's nudge, and installing pi after codex must add it.
  owners=$(echo "$owners" | jq --arg c "$client" '.owners = ((.owners // []) - [$c] + [$c])')

  # REQ-020 is scoped to "a pi or opencode host" — a codex-only install must
  # not advertise a flag ("--with-extensions") that does nothing for it.
  # $client was already folded into owners above, so checking the owners set
  # for pi/opencode membership covers both "this call's client is pi/opencode"
  # and "some OTHER current owner of this shared file is" in one check.
  local effective_nudge=0
  if echo "$owners" | jq -e '(.owners // []) | any(. == "pi" or . == "opencode")' >/dev/null 2>&1; then
    effective_nudge=1
  fi

  local created_by_us=false
  if [ ! -f "$agents_md" ]; then
    created_by_us=true
    owners=$(echo "$owners" | jq '.initial_had_user_content = false')
  elif ! grep -qF -- "$MB_START_MARKER" "$agents_md"; then
    owners=$(echo "$owners" | jq '.initial_had_user_content = true')
  fi
  _agents_md_write "$agents_md" "$skill_dir" "$effective_nudge" "$project_root" || return 1

  _owners_write "$project_root" "$owners"

  echo "$created_by_us"
}

# ───────── Uninstall ─────────
# Removes client from owners. If owners becomes empty: remove section (and file
# if initial_had_user_content == false).
agents_md_uninstall() {
  local project_root="$1"
  local client="$2"
  local agents_md="$project_root/AGENTS.md"
  local owners_file
  owners_file=$(_owners_file "$project_root")

  # Nothing to do if no owners file
  [ -f "$owners_file" ] || return 0

  local owners
  owners=$(cat "$owners_file")
  owners=$(echo "$owners" | jq --arg c "$client" '.owners = ((.owners // []) - [$c])')
  local remaining
  remaining=$(echo "$owners" | jq '.owners | length')

  if [ "$remaining" -gt 0 ]; then
    # Other MB adapters still installed — keep section, just update refcount
    _owners_write "$project_root" "$owners"
    return 0
  fi

  # No more MB adapters — remove section
  local had_user
  had_user=$(echo "$owners" | jq -r '.initial_had_user_content')

  if [ -f "$agents_md" ]; then
    if [ "$had_user" = "true" ]; then
      # Strip our section, preserve user content
      local tmp="$agents_md.tmp"
      _agents_md_strip "$agents_md" > "$tmp"
      # Remove file if fully empty
      if ! grep -q '[^[:space:]]' "$tmp" 2>/dev/null; then
        rm -f "$agents_md"
      else
        mv "$tmp" "$agents_md"
      fi
      rm -f "$tmp"
    else
      # We created the file — remove entirely
      rm -f "$agents_md"
    fi
  fi

  rm -f "$owners_file"
}
