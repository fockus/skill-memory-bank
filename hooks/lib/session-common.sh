# shellcheck shell=bash
# session-common.sh — shared helpers for the MB session-memory subsystem.
# Sourced by mb-session-turn.sh / mb-session-end.sh / mb-session-start.sh / mb-recall.sh.
# Defines functions only — no side effects on source. Do NOT `set -u` here (sourced into bats).

# Resolve the active Memory Bank directory by walking up from a start dir.
# Echoes the absolute path of the nearest <dir>/.memory-bank, or nothing.
sc_resolve_mb() {
  local dir="${1:-$PWD}"
  [ -d "$dir" ] || dir="$PWD"
  dir="$(cd "$dir" 2>/dev/null && pwd)" || return 0
  while [ -n "$dir" ]; do
    if [ -d "$dir/.memory-bank" ]; then
      printf '%s\n' "$dir/.memory-bank"
      return 0
    fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  return 0
}

# Build the per-session file path: <mb>/session/<date>_<hhmm>_<sid8>.md
sc_session_file() {
  local mb="$1" sid="$2" date="$3" hhmm="$4"
  local sid8="${sid:0:8}"
  printf '%s\n' "$mb/session/${date}_${hhmm}_${sid8}.md"
}

# Find an existing session file by full session_id. The filename carries only sid8
# (and a cosmetic wall-clock minute), so scan every sid8-matching file and confirm the
# full `session_id` frontmatter. Echoes the most recent match (lexicographic = latest
# date_hhmm), or nothing. This is the canonical lookup for both the Stop and SessionEnd
# hooks — it keeps all turns of one session in ONE file regardless of minute boundaries.
sc_find_session_file() {
  local mb="$1" sid="$2" sid8="${2:0:8}" f found=""
  for f in "$mb"/session/*_"$sid8".md; do
    [ -f "$f" ] || continue
    [ "$(sc_fm_get "$f" session_id)" = "$sid" ] && found="$f"
  done
  printf '%s\n' "$found"
}

# Read a frontmatter key (between the first two `---` fences). Echoes value or nothing.
sc_fm_get() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v k="$key" '
    NR==1 && /^---$/ { infm=1; next }
    infm && /^---$/  { exit }
    infm {
      pos=index($0, ":")
      if (pos>0) {
        kk=substr($0,1,pos-1)
        gsub(/^[ \t]+/,"",kk); gsub(/[ \t]+$/,"",kk)
        if (kk==k) {
          v=substr($0,pos+1)
          gsub(/^[ \t]+/,"",v); gsub(/[ \t]+$/,"",v)
          print v; exit
        }
      }
    }
  ' "$file"
}

# Set/replace a frontmatter key (atomic temp->mv). Assumes a frontmatter block exists.
sc_fm_set() {
  local file="$1" key="$2" value="$3"
  local tmp="${file}.tmp.$$"
  awk -v k="$key" -v v="$value" '
    BEGIN { infm=0; done=0 }
    NR==1 && /^---$/ { infm=1; print; next }
    infm && /^---$/ {
      if (!done) { print k": "v; done=1 }
      infm=0; print; next
    }
    infm {
      pos=index($0, ":")
      kk=(pos>0)?substr($0,1,pos-1):""
      gsub(/^[ \t]+/,"",kk); gsub(/[ \t]+$/,"",kk)
      if (kk==k) { print k": "v; done=1; next }
      print; next
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Portable mtime (seconds since epoch) of a path; empty if missing.
_sc_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# Acquire a portable atomic lock via mkdir (flock is absent on macOS).
#   sc_lock <lockdir> [timeout_s=10] [ttl_s=300]
# Returns 0 on acquire, non-zero on timeout. Breaks a stale lock older than ttl.
sc_lock() {
  local lock="$1" timeout="${2:-10}" ttl="${3:-300}" waited=0 age now
  while true; do
    if mkdir "$lock" 2>/dev/null; then
      return 0
    fi
    age="$(_sc_mtime "$lock")"
    if [ -n "$age" ]; then
      now="$(date +%s)"
      if [ "$((now - age))" -gt "$ttl" ]; then
        rm -rf "$lock" 2>/dev/null
        continue
      fi
    fi
    if [ "$waited" -ge "$timeout" ]; then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

# Release a lock acquired with sc_lock.
sc_unlock() {
  rm -rf "$1" 2>/dev/null || true
}

# True if capture must be skipped (anti-recursion sentinel or global off-switch).
sc_capture_disabled() {
  [ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && return 0
  [ "${MB_SESSION_CAPTURE:-auto}" = "off" ] && return 0
  return 1
}

# Redact API keys/tokens from stdin before persisting session text.
# Default ON; disable with MB_REDACT_SECRETS=off. Keep the pattern set in sync
# with hooks/lib/redact.py (the python side used by the semantic chunker).
# POSIX ERE only (BSD sed on macOS): no \b, no case-insensitive flag — the
# env-var pattern intentionally covers uppercase env-style names only.
sc_redact_secrets() {
  if [ "${MB_REDACT_SECRETS:-on}" = "off" ]; then
    cat
    return 0
  fi
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{20,}/[REDACTED]/g' \
    -e 's/gh[pousr]_[A-Za-z0-9]{20,}/[REDACTED]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{22,}/[REDACTED]/g' \
    -e 's/(AKIA|ASIA)[A-Z0-9]{16}/[REDACTED]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED]/g' \
    -e 's/AIza[A-Za-z0-9_-]{30,}/[REDACTED]/g' \
    -e 's/hf_[A-Za-z0-9]{30,}/[REDACTED]/g' \
    -e 's/npm_[A-Za-z0-9]{30,}/[REDACTED]/g' \
    -e 's/pypi-[A-Za-z0-9_-]{20,}/[REDACTED]/g' \
    -e 's|eyJ[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_.+/=-]{5,}|[REDACTED]|g' \
    -e 's/([Bb]earer[[:space:]]+)[A-Za-z0-9._~+/=-]{20,}/\1[REDACTED]/g' \
    -e "s/([A-Z0-9_]*(API_?KEY|TOKEN|SECRET|PASSWORD|PASSWD)[A-Z0-9_]*[[:space:]]*[=:][[:space:]]*)['\"]?[^[:space:]'\"]{8,}['\"]?/\1[REDACTED]/g"
}

# sc_semantic_py <hook_dir> <mb_root> — echo the python for the semantic CLI.
# Prefers a venv beside the installed hooks (global ~/.claude/hooks/.venv, or a
# project-local bin/.venv), then a legacy .memory-bank/.venv, then system python3.
sc_semantic_py() {
  if [ -x "$1/.venv/bin/python" ]; then
    printf '%s' "$1/.venv/bin/python"
  elif [ -n "${2:-}" ] && [ -x "$2/.venv/bin/python" ]; then
    printf '%s' "$2/.venv/bin/python"
  else
    printf 'python3'
  fi
}
