#!/usr/bin/env bash
# mb-init-bank.sh — deterministic locale-aware .memory-bank/ scaffolder
#
# Usage:
#   mb-init-bank.sh [--lang=XX] [--storage=local|global] [--agent=NAME]
#                   [--project-root=PATH] [--mb-root=PATH] [--force]
#
# Storage modes:
#   local  (default) — bank lives at <project_root>/.memory-bank/. Backward
#                      compatible: --mb-root acts as project_root in this mode.
#   global           — bank lives under <agent_config>/memory-bank/projects/
#                      <project_id>/.memory-bank/ and is registered in
#                      <agent_config>/memory-bank/registry.json. The project
#                      directory itself is left clean.
#
# Locale resolution (highest → lowest):
#   1. --lang=XX flag
#   2. MB_LANG env var
#   3. existing .mb-config value
#   4. default → en
#
# Safety:
#   - never overwrites existing core files;
#   - refuses to switch from local to global when a local bank already exists
#     (use --force only when you have a separate migration in mind);
#   - registry writes are atomic (tempfile + os.replace).
#
# Exit codes:
#   0 — success
#   2 — invalid locale or invalid agent
#   3 — missing template bundle
#   4 — refuses implicit local→global migration

set -eu

SUPPORTED_LOCALES=(en ru es zh)
SUPPORTED_AGENTS=(claude-code cursor codex opencode pi windsurf cline kilo)
CORE_FILES=(status.md roadmap.md checklist.md backlog.md research.md progress.md lessons.md)
CORE_DIRS=(plans plans/done notes reports experiments codebase)

# Resolve this script's own PHYSICAL directory through its FULL symlink chain
# (portable — no realpath on bare macOS). Deriving it from `dirname "$0"` meant a
# link in an attacker directory made init source THAT directory's `_lib.sh`, and
# broke template resolution for anyone installing through a symlink.
_mb_resolve_self_dir() {
  local src="$1" dir
  while [ -h "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" 2>/dev/null && pwd)"
    src="$(readlink "$src")"
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  cd -P "$(dirname "$src")" 2>/dev/null && pwd
}
SCRIPT_DIR="$(_mb_resolve_self_dir "${BASH_SOURCE[0]:-$0}")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

is_supported_locale() {
  local code="$1"
  for l in "${SUPPORTED_LOCALES[@]}"; do
    [ "$l" = "$code" ] && return 0
  done
  return 1
}

is_supported_agent() {
  local code="$1"
  for a in "${SUPPORTED_AGENTS[@]}"; do
    [ "$a" = "$code" ] && return 0
  done
  return 1
}

LANG_FLAG=""
MB_ROOT_OVERRIDE=""
STORAGE_MODE=""
AGENT_FLAG=""
PROJECT_ROOT_FLAG=""
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --lang=*)         LANG_FLAG="${arg#--lang=}" ;;
    --mb-root=*)      MB_ROOT_OVERRIDE="${arg#--mb-root=}" ;;
    --storage=*)      STORAGE_MODE="${arg#--storage=}" ;;
    --agent=*)        AGENT_FLAG="${arg#--agent=}" ;;
    --project-root=*) PROJECT_ROOT_FLAG="${arg#--project-root=}" ;;
    --force)          FORCE=1 ;;
    -h|--help)
      cat <<'USAGE'
mb-init-bank — scaffold .memory-bank/ from a locale template bundle.

Usage:
  mb-init-bank.sh [--lang=XX] [--storage=local|global] [--agent=NAME]
                  [--project-root=PATH] [--mb-root=PATH] [--force]

Options:
  --lang=XX           Locale (en|ru|es|zh). Default: MB_LANG, .mb-config, or en.
  --storage=MODE      `local` (default) — bank at <project>/.memory-bank/.
                      `global`         — bank under agent global storage,
                                         project directory stays clean.
  --agent=NAME        Required for global mode. One of:
                        claude-code, cursor, codex, opencode,
                        pi, windsurf, cline, kilo.
                      Defaults to $MB_AGENT or claude-code.
  --project-root=PATH Project root (default: $PWD). Used to derive project id
                      and the registry key for global mode.
  --mb-root=PATH      Backward-compat alias for --project-root in local mode.
  --force             Allow global init when a local .memory-bank/ already
                      exists (no data is copied — use a separate migration).

Examples:
  Local (team-shared):
    bash scripts/mb-init-bank.sh --storage=local --lang=ru
  Global (personal, repo stays clean):
    bash scripts/mb-init-bank.sh --storage=global --agent=pi \
                                 --project-root "$PWD" --lang=ru
USAGE
      exit 0
      ;;
  esac
done

# ── Resolve project root ────────────────────────────────────────────────────
PROJECT_ROOT="${PROJECT_ROOT_FLAG:-${MB_ROOT_OVERRIDE:-${MB_ROOT:-$PWD}}}"

# ── Resolve storage mode ─────────────────────────────────────────────────────
STORAGE_MODE="${STORAGE_MODE:-local}"
case "$STORAGE_MODE" in
  local|global) ;;
  *)
    echo "mb-init-bank: invalid storage mode '$STORAGE_MODE' (supported: local, global)" >&2
    exit 2
    ;;
esac

# ── Resolve agent (only meaningful for global mode) ──────────────────────────
AGENT="${AGENT_FLAG:-${MB_AGENT:-claude-code}}"
if [ "$STORAGE_MODE" = "global" ]; then
  if ! is_supported_agent "$AGENT"; then
    echo "mb-init-bank: invalid agent '$AGENT'." >&2
    echo "Supported agents: ${SUPPORTED_AGENTS[*]}" >&2
    exit 2
  fi
fi

# ── Resolve bank path per storage mode ───────────────────────────────────────
if [ "$STORAGE_MODE" = "local" ]; then
  BANK="$PROJECT_ROOT/.memory-bank"
  PROJECT_ID=""
else
  # Refuse implicit migration: existing local bank + global request.
  if [ -d "$PROJECT_ROOT/.memory-bank" ] && [ "$FORCE" -ne 1 ]; then
    cat >&2 <<EOF
mb-init-bank: refusing to switch to global mode while a local bank exists at
  $PROJECT_ROOT/.memory-bank

This script does NOT copy or move existing data implicitly. Options:
  1. Keep the local bank — run \`/mb start\` as usual; no action needed.
  2. Run an explicit migration before switching (separate plan).
  3. Override with \`--force\` to create a NEW global bank for this project
     while leaving the local one untouched (you will have two parallel banks).
EOF
    exit 4
  fi

  AGENT_CFG=$(mb_agent_config_dir "$AGENT")
  PROJECT_ID=$(mb_project_id "$PROJECT_ROOT")
  BANK="$AGENT_CFG/memory-bank/projects/$PROJECT_ID/.memory-bank"
fi

CONFIG="$BANK/.mb-config"

# ── Resolve locale ───────────────────────────────────────────────────────────
LANG_RESOLVED=""
if [ -n "$LANG_FLAG" ]; then
  LANG_RESOLVED="$LANG_FLAG"
elif [ -n "${MB_LANG:-}" ]; then
  LANG_RESOLVED="$MB_LANG"
elif [ -f "$CONFIG" ]; then
  LANG_RESOLVED="$(grep -E '^lang=' "$CONFIG" 2>/dev/null | tail -1 | cut -d= -f2-)"
fi
[ -n "$LANG_RESOLVED" ] || LANG_RESOLVED="en"

if ! is_supported_locale "$LANG_RESOLVED"; then
  echo "mb-init-bank: invalid locale '$LANG_RESOLVED' (supported: ${SUPPORTED_LOCALES[*]})" >&2
  exit 2
fi

SRC="$REPO_ROOT/templates/locales/$LANG_RESOLVED/.memory-bank"
if [ ! -d "$SRC" ]; then
  echo "mb-init-bank: missing template bundle: $SRC" >&2
  exit 3
fi

# ── Scaffold filesystem ──────────────────────────────────────────────────────
mkdir -p "$BANK"
for d in "${CORE_DIRS[@]}"; do
  mkdir -p "$BANK/$d"
done

for f in "${CORE_FILES[@]}"; do
  if [ -f "$BANK/$f" ]; then
    # never clobber user content
    continue
  fi
  cp "$SRC/$f" "$BANK/$f"
done

# ── Bank-local ignore rules ──────────────────────────────────────────────────
# <bank>/tmp/ holds throwaway scratch artifacts — above all the RAW /mb discuss
# interview candidate, credentials included, before it has been scanned
# (REQ-007). /mb discuss tells the user that directory is gitignored, and that
# promise has to be true in EVERY bank, not just in repos whose root .gitignore
# happens to list it: a fresh `git init` + `/mb init` had no rule at all, so
# `git add .` staged the raw candidate.
#
# The rule lives in a bank-local .gitignore so it travels with the bank and
# needs no edit to the project's own .gitignore. Existing files are extended,
# never clobbered, and the append is idempotent.
#
# Writing it safely matters as much as writing it: a symlink planted at
# <bank>/.gitignore used to be followed (appending into an arbitrary outside
# file), and appending to a file with no terminal LF glued the comment onto the
# last rule — `/secret` became `/secret# Memory Bank scratch…`, silently
# disabling the rule the user wrote.
BANK_IGNORE="$BANK/.gitignore"
"${MB_PYTHON:-python3}" - "$BANK_IGNORE" <<'PY' || { echo "mb-init-bank: refusing to write $BANK/.gitignore" >&2; exit 5; }
import os
import stat
import sys
import tempfile

path = sys.argv[1]
RULE = "/tmp/"
COMMENT = "# Memory Bank scratch: raw interview candidates never reach git (REQ-007)."

try:
    st = os.lstat(path)
except FileNotFoundError:
    st = None
except OSError:
    sys.exit(1)

# Only a regular file is ever written. A symlink (or anything else) is refused
# outright rather than followed.
if st is not None and (stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode)):
    sys.exit(1)

if st is None:
    existing, mode = "", None
else:
    try:
        with open(path, encoding="utf-8") as fh:
            existing = fh.read()
    except (OSError, UnicodeError):
        sys.exit(1)
    mode = stat.S_IMODE(st.st_mode)
    # Idempotent: never append the rule twice.
    if any(l.strip() == RULE for l in existing.split("\n")):
        sys.exit(0)

# Guarantee the separating newline before appending.
if existing and not existing.endswith("\n"):
    existing += "\n"
content = existing + COMMENT + "\n" + RULE + "\n"

directory = os.path.dirname(path) or "."
try:
    fd, tmp = tempfile.mkstemp(prefix=".gitignore-", suffix=".tmp", dir=directory)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(content)
    # mkstemp publishes 0600; an existing file keeps its own mode verbatim.
    if mode is not None:
        os.chmod(tmp, mode)
    else:
        cur = os.umask(0); os.umask(cur)
        os.chmod(tmp, 0o666 & ~cur)
    os.replace(tmp, path)
except OSError:
    try:
        os.unlink(tmp)
    except (OSError, NameError):
        pass
    sys.exit(1)
PY

# ── Write .mb-config (idempotent upsert of every key) ────────────────────────
# Stable line order: lang, storage_mode, agent, project_root, project_id.
mb_config_set() {
  local key="$1" value="$2"
  if [ -f "$CONFIG" ] && grep -qE "^${key}=" "$CONFIG"; then
    tmp="$(mktemp)"
    grep -vE "^${key}=" "$CONFIG" > "$tmp" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$CONFIG"
  else
    printf '%s=%s\n' "$key" "$value" >> "$CONFIG"
  fi
}

touch "$CONFIG"
mb_config_set lang "$LANG_RESOLVED"
mb_config_set storage_mode "$STORAGE_MODE"

if [ "$STORAGE_MODE" = "global" ]; then
  PROJECT_REAL=$(mb_resolve_real_path "$PROJECT_ROOT")
  mb_config_set agent "$AGENT"
  mb_config_set project_root "$PROJECT_REAL"
  mb_config_set project_id "$PROJECT_ID"

  # ── Write registry entry atomically (Python stdlib) ────────────────────────
  # A19 (CDX-I6): honor MB_PYTHON so pipx/venv installs without a bare `python3`
  # on PATH don't fail registry writes — falls back to python3 unchanged.
  REGISTRY=$(mb_registry_path "$AGENT")
  mkdir -p "$(dirname "$REGISTRY")"
  "${MB_PYTHON:-python3}" - "$REGISTRY" "$PROJECT_REAL" "$BANK" "$AGENT" "$PROJECT_ID" <<'PY'
import json
import os
import sys
import tempfile

registry, project, bank, agent, project_id = sys.argv[1:6]
data = {}
if os.path.exists(registry):
    try:
        with open(registry) as fh:
            data = json.load(fh)
    except Exception:
        # Corrupt registry: bail out instead of silently losing existing data.
        sys.stderr.write(f"mb-init-bank: refusing to overwrite corrupt registry {registry!r}\n")
        sys.exit(5)
if not isinstance(data, dict):
    data = {}
projects = data.setdefault("projects", {})
projects[project] = {
    "bank_path": bank,
    "agent": agent,
    "project_id": project_id,
}
# Atomic write: tempfile in same dir + os.replace.
fd, tmp = tempfile.mkstemp(prefix=".registry-", dir=os.path.dirname(registry))
try:
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, registry)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
PY
fi

if [ "$STORAGE_MODE" = "global" ]; then
  echo "mb-init-bank: initialized $BANK (lang=$LANG_RESOLVED, agent=$AGENT, project_id=$PROJECT_ID)"
else
  echo "mb-init-bank: initialized $BANK (lang=$LANG_RESOLVED)"
fi
