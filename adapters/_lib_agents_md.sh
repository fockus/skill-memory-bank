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
  local lang="${MB_LANGUAGE:-${LANGUAGE:-en}}"
  case "$lang" in
    en|ru) printf '%s' "$lang" ;;
    *) printf '%s' "en" ;;
  esac
}

mb_emit_rules_file() {
  local rules_file="$1"
  local lang
  lang="$(mb_preferred_language)"

  if [ ! -f "$rules_file" ]; then
    return 1
  fi

  # Prefer the interpreter the CLI handed us (MB_PYTHON); fall back to python3.
  local py="${MB_PYTHON:-python3}"
  if ! command -v "$py" >/dev/null 2>&1; then
    cat "$rules_file"
    return 0
  fi

  TARGET_RULES_FILE="$rules_file" \
  MB_RULE_LANGUAGE="$lang" \
  "$py" <<'PYEOF'
from pathlib import Path
import os
import re
import sys

path = Path(os.environ["TARGET_RULES_FILE"])
text = path.read_text()
lang = os.environ["MB_RULE_LANGUAGE"]

if lang == "ru":
    replacement = "1. **Language**: Russian — responses and code comments. Technical terms may remain in English."
else:
    replacement = "1. **Language**: English — responses and code comments. Technical terms may remain in English."

text = re.sub(
    r"1\. \*\*[^*]+\*\*: .+",
    replacement,
    text,
)
sys.stdout.write(text)
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

# ───────── Build section content ─────────
# $1 = skill_dir
# $2 = include_ext_nudge (0|1, default 0) — emit the "Host parity extensions
#      (Pi/OpenCode)" nudge only for hosts that actually have parity
#      extensions to offer (pi, opencode). Codex/cline/kilo/windsurf share the
#      same AGENTS.md format but have no `--with-extensions` target, so a
#      codex-only install must not advertise a flag that does nothing for it
#      (REQ-020 is literally scoped to "a pi or opencode host").
_agents_md_section() {
  local skill_dir="$1"
  local include_ext_nudge="${2:-0}"
  echo "$MB_START_MARKER"
  echo "<!-- memory-bank-skill-version: $(_mb_skill_version "$skill_dir") -->"
  echo ''
  echo '# Memory Bank — Project Rules'
  echo ''
  echo 'This project uses Memory Bank for long-term memory + dev workflow.'
  echo ''
  echo '**Workflow:**'
  # shellcheck disable=SC2016
  echo '- Start of session: read `.memory-bank/status.md`, `checklist.md`, `roadmap.md`, `research.md`'
  # shellcheck disable=SC2016
  echo '- Update `checklist.md` immediately (⬜ → ✅) when tasks done'
  echo '- Before context window fill: manual actualize'
  echo ''
  echo '## GraphRAG-lite routing'
  echo ''
  echo 'For code-understanding questions, prefer Memory Bank graph tools over `grep`:'
  # shellcheck disable=SC2016
  echo '- `code_context` — ambiguous "where is the logic for X?" / "find similar implementation". Default for fuzzy code-context lookups; runs semantic candidates + graph expansion + read fallback via `scripts/mb-code-context.py`.'
  # shellcheck disable=SC2016
  echo '- `graph_neighbors` — "who calls X?" / "what imports Y?" / "where is X defined?". Direct structural query via `scripts/mb-graph-query.py neighbors`.'
  # shellcheck disable=SC2016
  echo '- `graph_impact` — "change impact" / "reverse deps". `scripts/mb-graph-query.py impact`.'
  # shellcheck disable=SC2016
  echo '- `graph_tests` — "what tests cover this file/symbol?". `scripts/mb-graph-query.py tests`.'
  echo ''
  echo 'Fail open: missing graph, stale graph, missing semantic provider, or unavailable native extension must not block work — CLI scripts are the universal fallback.'
  echo ''
  if [ "$include_ext_nudge" = "1" ]; then
    echo '## Host parity extensions (Pi/OpenCode)'
    echo ''
    # shellcheck disable=SC2016
    echo 'On a bare Pi or OpenCode host (no parity extensions installed yet), suggest running `install.sh --with-extensions=pi,opencode` once per session, then stay silent once installed.'
    echo ''
  fi
  echo '## Dynamic-flow firewall (completion gate)'
  echo ''
  # shellcheck disable=SC2016
  echo 'When a dynamic-flow is active — i.e. `.memory-bank/goal.md` exists — completion is gated by a deterministic firewall, NOT by your own judgement. The firewall exit code, not your self-assessment, decides "done".'
  echo ''
  # shellcheck disable=SC2016
  echo '- Run `scripts/mb-flow-verify.sh <bank>` and treat ONLY exit 0 as finished.'
  # shellcheck disable=SC2016
  echo '- On a red (non-zero) exit, repair the failing check and re-run the firewall; loop until it exits 0. Never self-certify completion over a red firewall.'
  # shellcheck disable=SC2016
  echo '- Hookless agent (e.g. Pi) with no live Stop-hook: a no-commit false-done cannot be blocked live — it is only detectable after the fact via the commit-time git-hooks fallback (`mb-flow-verify.sh` runs in `pre-commit` and blocks a red flow).'
  echo ''
  if [ -f "$skill_dir/rules/RULES.md" ]; then
    echo '---'
    echo ''
    echo '## Global Rules'
    echo ''
    mb_emit_rules_file "$skill_dir/rules/RULES.md"
    echo ''
  fi
  echo "$MB_END_MARKER"
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
    # First install ever — we create the file
    created_by_us=true
    _agents_md_section "$skill_dir" "$effective_nudge" > "$agents_md"
    owners=$(echo "$owners" | jq '.initial_had_user_content = false')
  elif ! grep -q "$MB_START_MARKER" "$agents_md"; then
    # File exists (user content) but no MB section yet — append
    {
      echo ''
      _agents_md_section "$skill_dir" "$effective_nudge"
    } >> "$agents_md"
    owners=$(echo "$owners" | jq '.initial_had_user_content = true')
  else
    # Section already present from another MB adapter — replace with fresh content
    local tmp="$agents_md.tmp"
    awk -v s="$MB_START_MARKER" -v e="$MB_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_md" > "$tmp"
    {
      cat "$tmp"
      echo ''
      _agents_md_section "$skill_dir" "$effective_nudge"
    } > "$agents_md"
    rm -f "$tmp"
  fi

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
      awk -v s="$MB_START_MARKER" -v e="$MB_END_MARKER" '
        BEGIN { inside=0 }
        index($0, s) { inside=1; next }
        index($0, e) { inside=0; next }
        !inside { print }
      ' "$agents_md" > "$tmp"
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
