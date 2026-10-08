# shellcheck shell=bash
# scripts/mb_rules_sync_lib.sh — file writers behind `mb-rules.sh sync` (sourced by
# mb-rules.sh; uses its SCRIPT_DIR, SKILL_ROOT, markers, _die and render_block).
# Each real file is written once per run (symlinks resolved); a per-host rule file
# that was ours before the rewrite stays ours for the next adapter install.

# _sync_rules_md PROJECT BANK — the settings block on top of the project RULES.md
# (<project>/RULES.md, else <bank>/RULES.md); with CREATE_RULES_MD=1 a missing
# <project>/RULES.md is created first.
CREATE_RULES_MD=0
_sync_rules_md() {
  local project="$1" bank="$2" file="" section state
  if [ -f "$project/RULES.md" ]; then
    file="$project/RULES.md"
  elif [ -f "$bank/RULES.md" ]; then
    file="$bank/RULES.md"
  elif [ "$CREATE_RULES_MD" = 1 ]; then
    file="$project/RULES.md"
    # shellcheck disable=SC2016  # backticks are literal markdown
    printf '## Own rules\n\nYour project rules go here; `/mb rules` never edits text outside the managed block.\n' > "$file"
  else
    return 0
  fi
  section="$(mktemp)"
  if ! bash "$SCRIPT_DIR/mb-profile.sh" quality --json "--project=$bank/rules-profile.json" \
      | PYTHONPATH="$SCRIPT_DIR/..${PYTHONPATH:+:$PYTHONPATH}" \
        "$(mb_resolve_python "$SCRIPT_DIR/..")" -m memory_bank_skill.quality rules-md > "$section"; then
    rm -f "$section"
    _die "render failed for $file"
  fi
  state="$(mb_upsert_marked_block "$(_realpath "$file")" "$PR_START" "$PR_END" "$section" top)"
  rm -f "$section"
  printf '%s %s\n' "$state" "$file"
}

_realpath() {
  "${MB_PYTHON:-python3}" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

# _seen FILE — true when FILE's real path was already written this run (symlinks).
SEEN=""
_seen() {
  case "$SEEN" in *"|$1|"*) return 0 ;; esac
  SEEN="$SEEN|$1|"
  return 1
}

# _sync_file FILE TARGET HOST PROJECT BANK MODE — upsert the block at the top of FILE
# (symlinks resolved; each real file once).
_sync_file() {
  local file="$1" real section state
  [ -f "$file" ] || return 0
  real="$(_realpath "$file")"
  _seen "$real" && return 0
  section="$(mktemp)"
  if ! render_block "$2" "$3" "$4" "$5" "$6" > "$section"; then
    rm -f "$section"
    _die "render failed for $file"
  fi
  state="$(mb_upsert_marked_block "$real" "$KR_START" "$KR_END" "$section" top "$LANGUAGE_END")"
  rm -f "$section"
  printf '%s %s\n' "$state" "$file"
}

# _sync_agents_md PROJECT — an AGENTS.md with the Memory Bank block: rewrite the Key
# rules + MB blocks as agents_md_install does (the extensions nudge from the owners file).
_sync_agents_md() {
  local file="$1/AGENTS.md" nudge=0
  _seen "$(_realpath "$file")" && return 0
  grep -qE '"(pi|opencode)"' "$1/.mb-agents-owners.json" 2>/dev/null && nudge=1
  _agents_md_write "$file" "$SKILL_ROOT" "$nudge" "$1" || _die "write failed: $file"
  printf 'refreshed %s\n' "$file"
}

# _sync_rule_file FILE PROJECT [KR args...] — a per-host rule file the adapters wrote:
# replace its body (from the title line to EOF, or to the Cline file-form end marker)
# with a fresh mb_rule_file_body; frontmatter and text outside stay. Files without the
# title are not ours and stay untouched. A file its adapter manifest
# (<project>/<host dir>/.mb-manifest.json) lists and that was not edited after that
# manifest gets the manifest's mtime back after the rewrite, so the next install
# (_mb_owned_unedited) still sees it as ours; an edited one stays newer → backed up.
_sync_rule_file() {
  local file="$1" project="$2" real body tmp manifest rel owned=0
  shift 2
  [ -f "$file" ] && grep -qxF -- "$MB_RULE_FILE_TITLE" "$file" || return 0
  real="$(_realpath "$file")"
  _seen "$real" && return 0
  rel="${file#"$project"/}"
  manifest="$project/${rel%%/*}/.mb-manifest.json"
  # The manifest keeps the install-time path (maybe not the physical one): match the tail.
  [ -f "$manifest" ] && [ ! "$real" -nt "$manifest" ] \
    && jq -e --arg r "/$rel" 'any(.files[]?; endswith($r))' "$manifest" >/dev/null 2>&1 \
    && owned=1
  body="$(mktemp)"
  mb_rule_file_body "$SKILL_ROOT" "$project" "$@" > "$body"
  tmp="$(mktemp "$real.XXXXXX")"
  cp -p "$real" "$tmp"  # keep the file's mode; mktemp creates 0600
  awk -v t="$MB_RULE_FILE_TITLE" -v e="<!-- memory-bank-cline:end -->" -v b="$body" '
    $0 == t && !done { while ((getline l < b) > 0) print l; skip = 1; done = 1; next }
    skip && $0 == e { skip = 0 }
    !skip { print }
  ' "$real" > "$tmp" && mv -f "$tmp" "$real" || { rm -f "$tmp" "$body"; _die "write failed: $file"; }
  rm -f "$body"
  [ "$owned" = 0 ] || touch -r "$manifest" "$real"
  printf 'refreshed %s\n' "$file"
}
