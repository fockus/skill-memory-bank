#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# skill-memory-bank — Installer
# Long-term project memory + global rules + 34 dev commands
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SOURCE_SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SOURCE_SKILL_DIR/scripts/_lib.sh"
# shellcheck source=scripts/_install_options.sh
. "$SOURCE_SKILL_DIR/scripts/_install_options.sh"
# Interpreter that owns the memory_bank_skill package. The `memory-bank` CLI
# exports MB_PYTHON=sys.executable so pipx/pip/Homebrew installs invoke the
# venv's python (a bare system python3 cannot import the package). Falls back
# to python3 for a direct `bash install.sh` from a git checkout.
MB_PY="${MB_PYTHON:-python3}"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
CURSOR_DIR="$HOME/.cursor"
OPENCODE_DIR="$HOME/.config/opencode"
OPENCODE_LEGACY_DIR="$HOME/.opencode"
PI_AGENT_DIR="$HOME/.pi/agent"
CANONICAL_SKILL_DIR="$CLAUDE_DIR/skills/skill-memory-bank"
CLAUDE_SKILL_ALIAS="$CLAUDE_DIR/skills/memory-bank"
CODEX_SKILL_ALIAS="$CODEX_DIR/skills/memory-bank"
CURSOR_SKILL_ALIAS="$CURSOR_DIR/skills/memory-bank"
PI_SKILL_ALIAS="$PI_AGENT_DIR/skills/memory-bank"
# OpenCode's own skill-root alias (B6/A-1): guarantees `/mb` commands resolve
# a skill root even on a machine with no Claude Code tree at all — commands
# read `${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}` (commands/mb.md),
# and a host wrapper can point MB_SKILLS_ROOT at this alias instead.
OPENCODE_SKILL_ALIAS="$OPENCODE_DIR/skills/memory-bank"
CODEX_START_MARKER="<!-- memory-bank-codex:start -->"
CODEX_END_MARKER="<!-- memory-bank-codex:end -->"
# Own marker pair for the OpenCode global block. Before agents-md-diet Stage 3 it
# shared the project AGENTS.md pair; install_opencode_global_agents migrates it.
OPENCODE_START_MARKER="<!-- memory-bank-opencode:start -->"
OPENCODE_END_MARKER="<!-- memory-bank-opencode:end -->"
# shellcheck disable=SC2034  # read by adapters/_lib_pi_global.sh
PI_START_MARKER="<!-- memory-bank-pi:start -->"
# shellcheck disable=SC2034
PI_END_MARKER="<!-- memory-bank-pi:end -->"
# A13 (M-5): paired markers for the ~/.claude/CLAUDE.md MB section. Before this,
# refresh only had a start marker and blindly consumed start..EOF, destroying
# any user content placed after the section on every subsequent install.
CLAUDE_MB_START_MARKER="# [MEMORY-BANK-SKILL]"
CLAUDE_MB_END_MARKER="<!-- /memory-bank-skill -->"

# ─── Manifest path resolution (A12) ─────────────────────────────────────────
# pip/sudo installs frequently place SOURCE_SKILL_DIR under a root-owned
# prefix (e.g. <site-packages>/share/skill-memory-bank) a normal user cannot
# write to. Falling back silently there used to lose the uninstall rollback
# source entirely — mb_resolve_manifest_path (scripts/_lib.sh) picks a
# user-writable XDG location instead, and uninstall.sh applies the exact same
# resolution so it finds what install.sh actually wrote.
MANIFEST="$(mb_resolve_manifest_path "$SOURCE_SKILL_DIR")"
if ! mkdir -p "$(dirname "$MANIFEST")" 2>/dev/null; then
  echo "[install.sh] warning: could not create manifest directory $(dirname "$MANIFEST")" >&2
fi
if [ -z "${MB_MANIFEST_PATH:-}" ] && [ "$MANIFEST" != "$SOURCE_SKILL_DIR/.installed-manifest.json" ]; then
  echo "[install.sh] $SOURCE_SKILL_DIR is not writable — manifest will be stored at $MANIFEST instead" >&2
fi

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

INSTALLED_FILES=()
BACKED_UP_FILES=()
ADAPTERS_INVOKED=()
# A17: cross-agent adapters (Step 8) that failed or were missing/not-executable.
# A non-empty array fails the top-level install (exit nonzero) after all
# adapters have had a chance to run — successful siblings still get installed.
ADAPTERS_FAILED=()
# adapter-parity T2 (REQ-001/002/004/005): host families ("pi"|"opencode")
# whose extension offer was explicitly accepted THIS run. Empty on decline/
# skip — the manifest field of the same name mirrors this array honestly.
EXTENSIONS_INSTALLED=()

# ─── Manifest flush (A7 / H-5) ──────────────────────────────────────────────
# The manifest is the uninstall rollback source. Write it INCREMENTALLY via an
# EXIT trap so a partial failure still leaves a valid manifest of what was done
# (installed files + backups) instead of an unrecoverable orphan set. Atomic
# (tmp + os.replace). Idempotent via MB_MANIFEST_FLUSHED so the success path
# (Step 7) and the trap don't double-write.
MB_MANIFEST_FLUSHED=0
flush_manifest() {
  # A12: surface the real error instead of a bare "Manifest write failed"
  # (e.g. both the co-located and the XDG-fallback dirs are unwritable) —
  # capture stderr instead of blanket-discarding it via 2>/dev/null.
  local mf_output
  if ! mf_output=$(
    INSTALLED_FILES_STR="$(printf '%s\n' ${INSTALLED_FILES[@]+"${INSTALLED_FILES[@]}"})" \
    BACKED_UP_STR="$(printf '%s\n' ${BACKED_UP_FILES[@]+"${BACKED_UP_FILES[@]}"})" \
    CLIENTS_INSTALLED_STR="$(printf '%s\n' ${ADAPTERS_INVOKED[@]+"${ADAPTERS_INVOKED[@]}"})" \
    CLIENTS_FAILED_STR="$(printf '%s\n' ${ADAPTERS_FAILED[@]+"${ADAPTERS_FAILED[@]}"})" \
    EXTENSIONS_INSTALLED_STR="$(printf '%s\n' ${EXTENSIONS_INSTALLED[@]+"${EXTENSIONS_INSTALLED[@]}"})" \
    MANIFEST_PROJECT_ROOT="${PROJECT_ROOT:-}" \
    MANIFEST_LANGUAGE="${LANGUAGE:-}" \
    MANIFEST_COMMENTS_LANGUAGE="${COMMENTS_LANGUAGE:-}" \
    MANIFEST_CLIENTS_REQUESTED="${CLIENTS:-}" \
    MANIFEST_PATH="$MANIFEST" \
    INSTALL_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$MB_PY" << 'PYEOF' 2>&1
import hashlib, json, os, tempfile
files = [f for f in os.environ.get("INSTALLED_FILES_STR", "").split("\n") if f]
raw_backups = [b for b in os.environ.get("BACKED_UP_STR", "").split("\n") if b]
clients = [c for c in os.environ.get("CLIENTS_INSTALLED_STR", "").split("\n") if c]
clients_failed = [c for c in os.environ.get("CLIENTS_FAILED_STR", "").split("\n") if c]
extensions_installed = [e for e in os.environ.get("EXTENSIONS_INSTALLED_STR", "").split("\n") if e]


def _ordered_unique(items):
    return list(dict.fromkeys(items))


def _sha256(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def _backup_path(entry: str) -> str:
    parts = entry.split("|", 1)
    return parts[1] if len(parts) == 2 else ""


path = os.environ["MANIFEST_PATH"]
# Identity shortcuts do not create new backups. Carry the live original
# mappings across reinstall, including skill backups outside discovery dirs.
try:
    with open(path) as previous_file:
        previous = json.load(previous_file)
except (OSError, ValueError):
    previous = {}
previous_backups = previous.get("backups", []) if isinstance(previous, dict) else []
if not isinstance(previous_backups, list):
    previous_backups = []
backups = _ordered_unique([
    b for b in [*previous_backups, *raw_backups]
    if isinstance(b, str) and os.path.lexists(_backup_path(b))
])
manifest = {
    "schema_version": 1,
    "installed_at": os.environ["INSTALL_DATE"],
    "skill": "skill-memory-bank",
    "files": _ordered_unique(files),
    # Content of each regular file as written, so the next install can tell an
    # untouched leftover of this version from a file the user edited.
    "file_sha256": {f: _sha256(f) for f in _ordered_unique(files) if os.path.isfile(f) and not os.path.islink(f)},
    "backups": backups,
    # A10: per-project cross-agent adapters invoked at install time (excludes
    # claude-code, whose lifecycle is managed directly by install/uninstall.sh)
    # + the project root they were installed into, so uninstall.sh can call
    # each adapter's own `uninstall` and decrement the shared AGENTS.md refcount.
    "clients": _ordered_unique(clients),
    # A17: adapters that failed (nonzero exit) or were missing/not-executable —
    # a non-empty list here is why install.sh's own exit code is nonzero.
    "adapters_failed": _ordered_unique(clients_failed),
    # adapter-parity T2: host families ("pi"/"opencode") whose extension
    # offer was explicitly accepted this run. Empty array on decline/skip/no
    # offer shown — never inferred, always the literal accepted set (REQ-002).
    "extensions_installed": _ordered_unique(extensions_installed),
    "project_root": os.environ.get("MANIFEST_PROJECT_ROOT", ""),
    # Whose install this is: saved options and owned files apply only to this HOME.
    "home": os.environ.get("HOME", ""),
    # A21: the install options as requested (language, full --clients list
    # including claude-code) so `mb-upgrade.sh` can reapply them non-interactively
    # on the next re-install instead of silently resetting to en/claude-code-only.
    "language": os.environ.get("MANIFEST_LANGUAGE", ""),
    "comments_language": os.environ.get("MANIFEST_COMMENTS_LANGUAGE", ""),
    "clients_requested": os.environ.get("MANIFEST_CLIENTS_REQUESTED", ""),
    # adapter-parity T7 (REQ-015/017): this global manifest is claude-code's
    # own manifest (it has no separate adapters/claude-code.sh manifest file —
    # its lifecycle is managed directly here). claude-code is the reference
    # tier: statusline, subagents (Task tool), lifecycle-hooks, session-memory
    # and update-notify all ship natively — nothing to declare as limited.
    "platform_limited": [],
}
d = os.path.dirname(path) or "."
fd, tmp = tempfile.mkstemp(dir=d, prefix=".mb-manifest.")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(manifest, f, indent=2)
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PYEOF
  ); then
    echo "  Manifest write failed (target: $MANIFEST):" >&2
    while IFS= read -r line; do
      printf '    %s\n' "$line"
    done <<< "$mf_output" >&2
  fi
  MB_MANIFEST_FLUSHED=1
}

_mb_on_exit() {
  local rc=$?   # preserve the triggering exit code across the flush
  rm -rf "$MB_RUN_TMP"
  [ "$MB_MANIFEST_FLUSHED" = "1" ] && return "$rc"
  flush_manifest
  return "$rc"
}

# shellcheck disable=SC1091
. "$SOURCE_SKILL_DIR/adapters/_lib_agents_md.sh"
# shellcheck source=adapters/_lib_pi_global.sh
. "$SOURCE_SKILL_DIR/adapters/_lib_pi_global.sh"
# scripts/_lib.sh already sourced above (needed early for mb_resolve_manifest_path).

count_matching_files() {
  find "$1" -maxdepth 1 -type f -name "$2" | wc -l | tr -d ' '
}

# ═══ Arg parsing ═══
VALID_CLIENTS=("${MB_VALID_CLIENTS[@]}")
VALID_LANGUAGES=("${MB_VALID_LANGUAGES[@]}")
CLIENTS=""                  # unset sentinel — triggers interactive or default
LANGUAGE=""                 # unset sentinel — triggers interactive or default
COMMENTS_LANGUAGE=""        # empty = same as LANGUAGE
PROJECT_ROOT=""             # empty = saved project root, else PWD
NON_INTERACTIVE=0
# adapter-parity T2: opt-in host parity-extension offer (pi/opencode only).
# WITH_EXTENSIONS_FLAG=1 means "don't prompt — decide from WITH_EXTENSIONS_VALUE".
# Empty value = accept every offered host; non-empty = comma list of hosts.
WITH_EXTENSIONS_FLAG=0
WITH_EXTENSIONS_VALUE=""
KEY_RULES_MODE=""           # default|keep; empty = prompt on a TTY, else default/keep

show_help() {
  cat <<HELP_EOF
Usage: install.sh [OPTIONS]

Installs Memory Bank (global ~/.claude/) and optionally writes cross-agent
adapters (.cursor/, .windsurf/, .clinerules/, etc.) into a project directory.

Options:
  --clients <list>        Comma-separated client list.
                          Valid: claude-code, cursor, windsurf, cline, kilo,
                                 opencode, pi, codex
                          If omitted and running in a TTY → interactive menu.
                          Non-TTY default: claude-code only.
  --language <code>       Language of agent responses (and, by default, code comments).
                          Valid: en, ru, es, pt, zh
                          If omitted and running in a TTY → interactive prompt.
                          Non-TTY default: en.
  --comments-language <code>
                          Language of code comments when it differs from --language
                          (e.g. --language ru --comments-language en). Same codes.
                          A project can override both: /mb language <code> [--comments <code>].
  --project-root <path>   Target directory for cross-agent adapters (default: PWD).
  --non-interactive       Never prompt; use defaults when --clients not passed.
  --key-rules <mode>      Key rules selection (the block at the top of CLAUDE.md /
                          AGENTS.md): default = catalog defaults, keep = current
                          user selection. If omitted: checklist prompt on a TTY;
                          otherwise default on first install, keep on re-install.
  --with-extensions[=<list>]
                          Opt in to pi/opencode host parity extensions (session
                          memory, subagent dispatch, GraphRAG promotion)
                          without an interactive prompt. Bare flag accepts
                          every offered host; a comma list (e.g. pi,opencode)
                          scopes acceptance to those hosts only. Same effect
                          as the MB_WITH_EXTENSIONS env var. Ignored unless
                          --clients includes pi and/or opencode. Declining
                          (the default) leaves the install unchanged.
  --help                  Show this message.

A re-install reuses the options saved by the previous one (language, comments
language, clients, project root); pass a flag to change one. With no saved
manifest (pipx install --force, a cleaned Homebrew keg) they are inferred from
~/.claude/memory-bank-config.json and the clients' adapter manifests.

Examples:
  install.sh                                         # Interactive menu (TTY)
  install.sh --non-interactive                       # claude-code only, no prompt
  install.sh --language ru                           # install Russian language rules
  install.sh --clients claude-code,cursor            # + .cursor/ adapter in PWD
  install.sh --clients cursor,windsurf,opencode     # Multi-client, no claude-code
  install.sh --clients pi,opencode --with-extensions # accept both hosts' parity extensions
HELP_EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --clients)
      CLIENTS="${2:-}"
      [ -z "$CLIENTS" ] && { echo "[install.sh] --clients requires an argument" >&2; exit 1; }
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
      [ -z "$PROJECT_ROOT" ] && { echo "[install.sh] --project-root requires an argument" >&2; exit 1; }
      shift 2
      ;;
    --language)
      LANGUAGE="${2:-}"
      [ -z "$LANGUAGE" ] && { echo "[install.sh] --language requires an argument" >&2; exit 1; }
      shift 2
      ;;
    --comments-language)
      COMMENTS_LANGUAGE="${2:-}"
      [ -z "$COMMENTS_LANGUAGE" ] && { echo "[install.sh] --comments-language requires an argument" >&2; exit 1; }
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=1; shift ;;
    --key-rules|--key-rules=*)
      if [ "$1" = "--key-rules" ]; then KEY_RULES_MODE="${2:-}"; shift; else KEY_RULES_MODE="${1#--key-rules=}"; fi
      shift
      case "$KEY_RULES_MODE" in
        default|keep) ;;
        *) echo "[install.sh] --key-rules must be default or keep" >&2; exit 1 ;;
      esac
      ;;
    --with-extensions)
      WITH_EXTENSIONS_FLAG=1; WITH_EXTENSIONS_VALUE=""; shift ;;
    --with-extensions=*)
      WITH_EXTENSIONS_FLAG=1
      WITH_EXTENSIONS_VALUE="${1#--with-extensions=}"
      shift
      ;;
    --help|-h)
      show_help; exit 0 ;;
    *)
      echo "[install.sh] unknown argument: $1 (use --help)" >&2
      exit 1
      ;;
  esac
done

# ═══ Interactive client picker ═══
# Triggers only when: --clients empty AND stdin is TTY AND --non-interactive not set.
# Env override: MB_CLIENTS="claude-code,cursor" bash install.sh — skip prompt too.
if [ -z "$CLIENTS" ] && [ -n "${MB_CLIENTS:-}" ]; then
  CLIENTS="$MB_CLIENTS"
fi
if [ -z "$LANGUAGE" ] && [ -n "${MB_LANGUAGE:-}" ]; then
  LANGUAGE="$MB_LANGUAGE"
fi
if [ -z "$COMMENTS_LANGUAGE" ] && [ -n "${MB_COMMENTS_LANGUAGE:-}" ]; then
  COMMENTS_LANGUAGE="$MB_COMMENTS_LANGUAGE"
fi
# adapter-parity T2 (REQ-005): MB_WITH_EXTENSIONS env has the same contract as
# --with-extensions[=<list>] — an explicit CLI flag always wins. `+x` (not
# `-n`) so an env var set to the empty string still means "accept every
# offered host", matching the bare-flag behavior.
if [ "$WITH_EXTENSIONS_FLAG" != "1" ] && [ -n "${MB_WITH_EXTENSIONS+x}" ]; then
  WITH_EXTENSIONS_FLAG=1
  WITH_EXTENSIONS_VALUE="$MB_WITH_EXTENSIONS"
fi

# A plain re-run keeps the previous install's choices (saved in the manifest);
# whatever was passed explicitly (flag or MB_* env) wins. The project root: run
# inside a project (.git / .memory-bank, not the skill checkout itself) → that
# project, as before A21; elsewhere (pipx from ~, the skill dir) → the saved one.
CWD_IS_PROJECT=0
if { [ -e "$PWD/.git" ] || [ -d "$PWD/.memory-bank" ]; } && ! [ "$PWD" -ef "$SOURCE_SKILL_DIR" ]; then
  CWD_IS_PROJECT=1
fi
PREV_MANIFEST_SRC="$(mb_previous_manifest "$SOURCE_SKILL_DIR" "$MANIFEST")"
# No usable manifest (pipx --force / reinstall, a cleaned brew keg): infer the
# options from what the earlier install left in $HOME and this project.
MB_INFERRED_FROM=""
if { [ -z "$CLIENTS" ] || [ -z "$LANGUAGE" ] || [ -z "$PROJECT_ROOT" ]; } \
  && { mb_saved_install_options "$PREV_MANIFEST_SRC" \
    || mb_inferred_install_options "${PROJECT_ROOT:-$PWD}"; }; then
  if [ -z "$LANGUAGE" ]; then
    LANGUAGE="$MB_SAVED_LANGUAGE"
    [ -z "$COMMENTS_LANGUAGE" ] && COMMENTS_LANGUAGE="$MB_SAVED_COMMENTS_LANGUAGE"
  fi
  [ -z "$CLIENTS" ] && CLIENTS="$MB_SAVED_CLIENTS"
  if [ -z "$PROJECT_ROOT" ] && [ "$CWD_IS_PROJECT" = 1 ]; then
    PROJECT_ROOT="$PWD"
    [ -n "$MB_SAVED_PROJECT_ROOT" ] && ! [ "$PWD" -ef "$MB_SAVED_PROJECT_ROOT" ] \
      && echo "[install.sh] installing into the current project $PWD (previous install: $MB_SAVED_PROJECT_ROOT)" >&2
  elif [ -z "$PROJECT_ROOT" ] && [ -n "$MB_SAVED_PROJECT_ROOT" ]; then
    if [ -d "$MB_SAVED_PROJECT_ROOT" ]; then
      PROJECT_ROOT="$MB_SAVED_PROJECT_ROOT"
    else
      echo "[install.sh] saved project root $MB_SAVED_PROJECT_ROOT is gone — using $PWD" >&2
    fi
  fi
  if [ -n "$MB_INFERRED_FROM" ]; then
    echo "[install.sh] no previous install manifest — options inferred from $MB_INFERRED_FROM: language=${LANGUAGE:-en} clients=${CLIENTS:-claude-code} project=${PROJECT_ROOT:-$PWD} (pass --language/--clients/--project-root to change)" >&2
  else
    echo "[install.sh] saved options: language=$LANGUAGE clients=${CLIENTS:-claude-code} project=${PROJECT_ROOT:-$PWD} (pass --language/--clients/--project-root to change)" >&2
  fi
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$PWD"

interactive_pick_clients() {
  echo ""
  echo -e "${BOLD}Which AI coding agents do you want to enable?${NC}"
  echo "  Claude Code is recommended as the primary target."
  echo "  Cross-agent adapters write per-client config (.cursor/, .windsurf/, etc.)"
  echo "  into the current project ($PROJECT_ROOT)."
  echo ""
  local idx=1
  for c in "${VALID_CLIENTS[@]}"; do
    local marker=" "
    [ "$c" = "claude-code" ] && marker="*"
    printf "  [%d]%s %s\n" "$idx" "$marker" "$c"
    idx=$((idx + 1))
  done
  echo ""
  echo "  Enter numbers separated by spaces or commas (e.g. '1 2 5'),"
  echo "  'all' for every client, or press Enter for just claude-code."
  echo ""
  printf "> "
  local reply
  IFS= read -r reply </dev/tty || reply=""
  reply="${reply// /,}"         # spaces → commas
  reply="${reply//,,/,}"         # collapse double commas
  reply="${reply#,}"; reply="${reply%,}"

  if [ -z "$reply" ]; then
    CLIENTS="claude-code"
    echo "  → selected: claude-code (default)"
    return
  fi

  if [ "$reply" = "all" ]; then
    CLIENTS="$(IFS=,; echo "${VALID_CLIENTS[*]}")"
    echo "  → selected: $CLIENTS"
    return
  fi

  local picked=()
  IFS=',' read -ra parts <<< "$reply"
  for p in "${parts[@]}"; do
    p="${p// /}"
    [ -z "$p" ] && continue
    if ! [[ "$p" =~ ^[0-9]+$ ]]; then
      echo "[install.sh] invalid selection: '$p' (expected number 1-${#VALID_CLIENTS[@]})" >&2
      exit 1
    fi
    local i=$((p - 1))
    if [ "$i" -lt 0 ] || [ "$i" -ge "${#VALID_CLIENTS[@]}" ]; then
      echo "[install.sh] out of range: '$p' (valid: 1-${#VALID_CLIENTS[@]})" >&2
      exit 1
    fi
    picked+=("${VALID_CLIENTS[$i]}")
  done

  if [ "${#picked[@]}" -eq 0 ]; then
    CLIENTS="claude-code"
    echo "  → selected: claude-code (default)"
  else
    CLIENTS="$(IFS=,; echo "${picked[*]}")"
    echo "  → selected: $CLIENTS"
  fi
}

interactive_pick_language() {
  echo ""
  echo -e "${BOLD}Which language should Memory Bank rules use?${NC}"
  echo "  This controls the installed global language rule and comment-language guidance."
  echo ""
  echo "  [1]* en  English"
  echo "  [2]  ru  Russian"
  echo "  [3]  es  Spanish"
  echo "  [4]  pt  Portuguese"
  echo "  [5]  zh  Chinese (Simplified)"
  echo ""
  echo "  Press Enter for English."
  echo ""
  printf "> "
  local reply
  IFS= read -r reply </dev/tty || reply=""
  reply="${reply// /}"

  case "$reply" in
    ""|"1"|"en")
      LANGUAGE="en"
      echo "  -> selected language: en"
      ;;
    "2"|"ru")
      LANGUAGE="ru"
      echo "  -> selected language: ru"
      ;;
    "3"|"es") LANGUAGE="es"; echo "  -> selected language: es" ;;
    "4"|"pt") LANGUAGE="pt"; echo "  -> selected language: pt" ;;
    "5"|"zh") LANGUAGE="zh"; echo "  -> selected language: zh" ;;
    *)
      echo "[install.sh] invalid language '$reply' (valid: ${VALID_LANGUAGES[*]})" >&2
      exit 1
      ;;
  esac
}

if [ -z "$CLIENTS" ]; then
  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ]; then
    CLIENTS="claude-code"
  else
    interactive_pick_clients
  fi
fi

if [ -z "$LANGUAGE" ]; then
  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ]; then
    LANGUAGE="en"
  else
    interactive_pick_language
  fi
fi

# Validate client list
IFS=',' read -ra CLIENTS_ARR <<< "$CLIENTS"
for c in "${CLIENTS_ARR[@]}"; do
  c_trimmed="${c// /}"
  valid=0
  for v in "${VALID_CLIENTS[@]}"; do
    [ "$c_trimmed" = "$v" ] && valid=1 && break
  done
  if [ "$valid" -eq 0 ]; then
    echo "[install.sh] invalid client '$c_trimmed'. Valid: ${VALID_CLIENTS[*]}" >&2
    exit 1
  fi
done

# Validate --with-extensions / MB_WITH_EXTENSIONS values (adapter-parity T2).
# The list is a closed set {pi, opencode} — an unrecognized name (e.g. a typo
# like "pie") must not be silently swallowed into an honest-looking
# `extensions_installed: []`; automation could then mistake a typo'd flag for
# "ran, nothing to do". A *valid* name simply absent from --clients still
# stays a silent no-op — that's the documented REQ-002 default, enforced by
# _mb_offer_extensions only ever asking about hosts present in --clients.
if [ "$WITH_EXTENSIONS_FLAG" = "1" ] && [ -n "$WITH_EXTENSIONS_VALUE" ]; then
  IFS=',' read -ra with_ext_arr <<< "$WITH_EXTENSIONS_VALUE"
  for we in "${with_ext_arr[@]}"; do
    # Trim LEADING/TRAILING whitespace only (not internal): `${we// /}` used
    # to strip every space, so "open code" silently became the valid
    # "opencode" — a value with INTERNAL whitespace must fail the closed-set
    # check below, not be quietly repaired into something else.
    we_trimmed="$we"
    we_trimmed="${we_trimmed#"${we_trimmed%%[![:space:]]*}"}"
    we_trimmed="${we_trimmed%"${we_trimmed##*[![:space:]]}"}"
    [ -z "$we_trimmed" ] && continue
    case "$we_trimmed" in
      pi|opencode) ;;
      *)
        echo "[install.sh] unknown --with-extensions host '$we_trimmed'. Valid: pi, opencode" >&2
        exit 1
        ;;
    esac
  done
fi

# ═══ Extension offer (adapter-parity T2 — REQ-001/002/004/005) ═══
#
# mb_install_host_extensions <host>
# Contract (stable seam consumed by T3/pi and T5/opencode):
#   Input:  $1 = host family, always "pi" or "opencode".
#   Called: exactly once per host that the user explicitly accepted (prompt
#           reply y/yes, --with-extensions[=list], or MB_WITH_EXTENSIONS) —
#           never on decline/skip. Never called before consent exists.
#   Output: a single human-readable status line; must not prompt further.
#   Return: 0 → host is recorded in the manifest's extensions_installed[]
#           (today's stub always returns 0 and writes nothing — it exists
#           only to prove/host the call site). Non-zero → offer accepted but
#           installation failed; the host is NOT recorded, install continues
#           (never fatal, mirrors every other adapter-install failure mode).
# T3 (pi: session-memory + graph-rag) landed — see the "pi" branch below.
# T5 (opencode: parity plugin + global agents) landed too — see the
# "opencode" branch below.
mb_install_host_extensions() {
  local host="$1"
  case "$host" in
    pi)
      # adapter-parity T3 (REQ-006/007/010): install BOTH parity extensions
      # (session-memory + graph-rag) into the global Pi extensions dir
      # ($HOME/.pi/agent/extensions/) — no separate project-local run
      # required. adapters/pi.sh reports per-extension success/failure on
      # its own status line; this only announces the host-level action so
      # "pi parity extensions" is always a stable substring to assert on.
      echo -e "  ${GREEN}✓${NC} pi parity extensions: installing session-memory + graph-rag"
      if ! MB_LANGUAGE="$LANGUAGE" bash "$SOURCE_SKILL_DIR/adapters/pi.sh" install-global-extensions "$PROJECT_ROOT"; then
        echo -e "  ${RED}✗${NC} pi parity extensions: install failed" >&2
        return 1
      fi
      ;;
    opencode)
      # adapter-parity T5 (REQ-011/012): two artifacts, one accept.
      #   1. Global agent roster (~/.config/opencode/agent/*.md) — installed
      #      right here via the dedicated opencode.sh action (mirrors pi's
      #      install-global-extensions call above), independent of which
      #      project accepted the offer.
      #   2. THIS project's plugin.js gains session-start context injection
      #      + per-turn session capture — NOT written here (the per-client
      #      adapter loop, Step 8 below, has not run yet at this point in
      #      the script). MB_OC_PARITY_ACCEPTED=1 is exported so that
      #      LATER, unconditional `adapters/opencode.sh install` call (Step
      #      8, still gated on "opencode" being a --clients target) writes
      #      the extended plugin variant instead of the base one — single
      #      write, no double-write/revert race with the global agents step.
      #      A declined/no-flag install never sets this var, so
      #      adapters/opencode.sh's own default (extended=0) applies and the
      #      plugin stays the pre-T5-shaped base variant (NFR-001).
      #      Codex review fix (major): the export MUST happen only AFTER
      #      install-global-agents succeeds — exporting first and returning 1
      #      on failure left the var set for the rest of the process, so
      #      Step 8's unconditional plugin write still upgraded to the
      #      EXTENDED variant despite the host never being recorded in
      #      EXTENSIONS_INSTALLED (a dishonest, NFR-001-adjacent state: a
      #      failed accept leaving capture-enabled code behind). The
      #      global-agents install itself carries no MB_OC_PARITY_ACCEPTED
      #      dependency, so evaluating it first and exporting only on success
      #      is a pure reorder, not a behavior change on the success path.
      echo -e "  ${GREEN}✓${NC} opencode parity extensions: session-start plugin (this project) + global agents"
      if ! MB_LANGUAGE="$LANGUAGE" bash "$SOURCE_SKILL_DIR/adapters/opencode.sh" install-global-agents "$PROJECT_ROOT"; then
        echo -e "  ${RED}✗${NC} opencode parity extensions: global agents install failed" >&2
        return 1
      fi
      export MB_OC_PARITY_ACCEPTED=1
      ;;
    *)
      echo "[install.sh] mb_install_host_extensions: unknown host '$host'" >&2
      return 1
      ;;
  esac
  return 0
}

# Prints the space-separated subset of {pi, opencode} present in CLIENTS_ARR.
_mb_extension_hosts_present() {
  local host c
  for host in pi opencode; do
    for c in "${CLIENTS_ARR[@]}"; do
      if [ "${c// /}" = "$host" ]; then
        printf '%s ' "$host"
        break
      fi
    done
  done
}

# One prompt per host family present (TTY, no flag/env); flag/env accepts
# without prompting; no TTY + no flag/env → silent skip (REQ-002 default).
_mb_offer_extensions() {
  local hosts_present
  hosts_present="$(_mb_extension_hosts_present)"
  [ -z "$hosts_present" ] && return 0

  local host accept reply
  for host in $hosts_present; do
    accept=0
    if [ "$WITH_EXTENSIONS_FLAG" = "1" ]; then
      if [ -z "$WITH_EXTENSIONS_VALUE" ]; then
        accept=1
      else
        case ",${WITH_EXTENSIONS_VALUE// /}," in
          *",$host,"*) accept=1 ;;
        esac
      fi
    elif [ "$NON_INTERACTIVE" -eq 0 ] && [ -t 0 ]; then
      echo ""
      echo -e "${BOLD}Install $host parity extensions?${NC} (session memory, subagent dispatch)"
      echo "  Opt-in only — declining leaves this install unchanged."
      printf "  [y/N] > "
      IFS= read -r reply </dev/tty || reply=""
      case "$reply" in
        y|Y|yes|Yes|YES) accept=1 ;;
        *) accept=0 ;;
      esac
    fi

    if [ "$accept" -eq 1 ]; then
      if mb_install_host_extensions "$host"; then
        EXTENSIONS_INSTALLED+=("$host")
      fi
    fi
  done
}

valid_language=0
for lang in "${VALID_LANGUAGES[@]}"; do
  [ "$LANGUAGE" = "$lang" ] && valid_language=1 && break
done
if [ "$valid_language" -eq 0 ]; then
  echo "[install.sh] invalid language '$LANGUAGE'. Valid: ${VALID_LANGUAGES[*]}" >&2
  exit 1
fi
if [ -n "$COMMENTS_LANGUAGE" ]; then
  valid_language=0
  for lang in "${VALID_LANGUAGES[@]}"; do
    [ "$COMMENTS_LANGUAGE" = "$lang" ] && valid_language=1 && break
  done
  if [ "$valid_language" -eq 0 ]; then
    echo "[install.sh] invalid comments language '$COMMENTS_LANGUAGE'. Valid: ${VALID_LANGUAGES[*]}" >&2
    exit 1
  fi
fi
# Adapters (AGENTS.md rules for pi/cursor/windsurf/...) render the same language pair.
export MB_LANGUAGE="$LANGUAGE" MB_COMMENTS_LANGUAGE="$COMMENTS_LANGUAGE"

echo ""
echo -e "${BOLD}═══ Installing skill-memory-bank ═══${NC}"
echo ""
COMMAND_COUNT="$(count_matching_files "$SOURCE_SKILL_DIR/commands" '*.md')"
AGENT_COUNT="$(count_matching_files "$SOURCE_SKILL_DIR/agents" '*.md')"
HOOK_COUNT="$(count_matching_files "$SOURCE_SKILL_DIR/hooks" '*.sh')"
SCRIPT_COUNT="$(count_matching_files "$SOURCE_SKILL_DIR/scripts" 'mb-*.sh')"
echo "  • Global RULES.md (TDD, SOLID, Clean Architecture, FSD for frontend)"
echo "  • $COMMAND_COUNT dev commands (/mb, /commit, /review, /test, etc.)"
echo "  • $AGENT_COUNT agents (mb-doctor, mb-manager, plan-verifier, mb-codebase-mapper)"
echo "  • $HOOK_COUNT hooks (block-dangerous, file-change-log, session-end-autosave, mb-pre-compact)"
echo "  • $SCRIPT_COUNT mb-* scripts (plan-sync, plan-done, idea, idea-promote, adr, migrate-structure, compact, …)"
echo "  • Settings hooks (SessionStart, PreCompact, Stop, …)"
echo "  • Preferred language: $LANGUAGE"
echo ""

# ═══ Step 0: Preflight dependency check ═══
# Can be skipped via MB_SKIP_DEPS_CHECK=1 (CI / isolated envs).
if [ "${MB_SKIP_DEPS_CHECK:-0}" != "1" ]; then
  echo -e "${BLUE}[0/7] Dependency check${NC}"
  if ! bash "$SOURCE_SKILL_DIR/scripts/mb-deps-check.sh" --install-hints; then
    echo ""
    echo -e "${RED}✗${NC} Required dependencies missing. Install them first and re-run install.sh."
    echo "   (Override: MB_SKIP_DEPS_CHECK=1 bash install.sh)"
    exit 1
  fi
fi

# The previous install's manifest, read before this run rewrites it. PREV_OWNED:
# the files it wrote; PREV_UNCHANGED: those still exactly as it wrote them
# (sha256 from the manifest; a manifest without hashes: not modified after the
# manifest itself was written). An unchanged file of ours is replaced without a
# backup (I-250); an edited one keeps its backup; files only the old version
# wrote are cleaned up by remove_previous_orphans.
MB_RUN_TMP="$(mktemp -d)"
MB_RUN_START="$MB_RUN_TMP/run-start"
touch "$MB_RUN_START"
PREV_MANIFEST="$MB_RUN_TMP/prev-manifest.json"
PREV_OWNED="$MB_RUN_TMP/prev-owned.txt"
PREV_UNCHANGED="$MB_RUN_TMP/prev-unchanged.txt"
: > "$PREV_OWNED"
: > "$PREV_UNCHANGED"
if [ -n "$PREV_MANIFEST_SRC" ] && cp -p "$PREV_MANIFEST_SRC" "$PREV_MANIFEST" 2>/dev/null; then
  # Only a manifest of this HOME counts (a shared checkout can carry another HOME's list).
  MB_HOME_DIR="$HOME" "$MB_PY" - "$PREV_MANIFEST" "$PREV_OWNED" "$PREV_UNCHANGED" 2>/dev/null <<'PY' || : > "$PREV_OWNED"
import hashlib, json, os, sys
manifest, owned_out, unchanged_out = sys.argv[1:4]
prev = json.load(open(manifest))
home = os.environ["MB_HOME_DIR"].rstrip("/") + "/"
hashes = prev.get("file_sha256") or {}
written_at = os.path.getmtime(manifest)
owned = [f for f in dict.fromkeys(prev.get("files") or []) if isinstance(f, str) and f.startswith(home)]

def unchanged(path):
    if not os.path.isfile(path) or os.path.islink(path):
        return False
    if path in hashes:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest() == hashes[path]
    return int(os.path.getmtime(path)) <= int(written_at)

with open(owned_out, "w") as fh:
    fh.write("".join(f + "\n" for f in owned))
with open(unchanged_out, "w") as fh:
    fh.write("".join(f + "\n" for f in owned if unchanged(f)))
PY
fi
# No previous manifest at all: ownership is judged per file instead
# (scripts/_install_options.sh::mb_written_by_last_install).
MB_LAST_INSTALL_AT=""
if [ -z "$PREV_MANIFEST_SRC" ] && [ -f "$CLAUDE_DIR/memory-bank-config.json" ]; then
  MB_LAST_INSTALL_AT="$(mb_mtime "$CLAUDE_DIR/memory-bank-config.json")"
fi

# python3 is now confirmed usable → arm the manifest flush for ANY exit (A7/H-5).
trap _mb_on_exit EXIT

# Invariant: the extension offer/install runs AFTER every argument-validation
# step above (client list, --with-extensions closed-set, language) AND AFTER
# the EXIT trap is armed. mb_install_host_extensions's stub body is a no-op
# today, but T3/T5 replace it with a real per-host installer at this exact
# seam — arming the trap first means a real installer that writes files then
# fails partway still leaves a manifest record of what landed (rollback
# source), instead of writing files with no recorded evidence they exist.
_mb_offer_extensions

_mb_has_claude_marker() { grep -qxF -- "$CLAUDE_MB_START_MARKER" "$1"; }

backup_if_exists() {
  # Skip-when-identical backup with rotation (keeps only the latest backup).
  # Args: $1 = target path, $2 (optional) = expected content path.
  # If $2 is given and target content already matches expected, return 2 (skip marker).
  # Legacy 1-arg callers keep previous behavior: unconditional backup.
  local target="$1"
  local expected="${2:-}"
  # I-250: a file the previous install wrote and nobody edited since is ours —
  # replace it, no backup. Edited files, foreign files and directories (a real
  # checkout may sit at a skill path) keep the backup below.
  # MB_BLOCK_FILE=1: a file holding our marked block that the caller rewrites
  # keeping the user's text verbatim — ours if the previous install wrote it.
  # MB_ALWAYS_BACKUP=1 forces one for a caller that cannot keep the user's text.
  # Without a previous manifest: a file written by the last install and not
  # edited since, or a block file carrying our marker.
  local own_list="$PREV_UNCHANGED" own_now=mb_written_by_last_install
  [ "${MB_BLOCK_FILE:-0}" = 1 ] && own_list="$PREV_OWNED" && own_now=_mb_has_claude_marker
  if [ "${MB_ALWAYS_BACKUP:-0}" != 1 ] && [ -f "$target" ] && [ ! -L "$target" ] \
    && { grep -qxF -- "$target" "$own_list" || { [ -z "$PREV_MANIFEST_SRC" ] && "$own_now" "$target"; }; }; then
    rm -f -- "$target"
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ]; then
      local managed_root resolved_target
      case "$target" in
        "$CLAUDE_DIR"/*) managed_root="$CLAUDE_DIR" ;;
        "$CODEX_DIR"/*) managed_root="$CODEX_DIR" ;;
        "$CURSOR_DIR"/*) managed_root="$CURSOR_DIR" ;;
        "$OPENCODE_DIR"/*) managed_root="$OPENCODE_DIR" ;;
        "$PI_AGENT_DIR"/*) managed_root="$PI_AGENT_DIR" ;;
        *) managed_root="" ;;
      esac
      if [ -n "$managed_root" ]; then
        resolved_target=$(mb_resolve_real_path "$target")
        if ! mb_path_is_within "$resolved_target" "$managed_root"; then
          echo "[install.sh] refusing to back up symlink target outside managed dir: $target -> $resolved_target" >&2
          return 1
        fi
      fi
    fi
    if [ -n "$expected" ] && [ -f "$expected" ] && cmp -s "$target" "$expected"; then
      return 2
    fi
    # Rotation: remove any previous .pre-mb-backup.* for this target.
    # Prevents the "backup creep" problem (hundreds of stale backups accumulating
    # across repeat installs). We keep only the freshest snapshot.
    # Pi scans ~/.pi/agent/skills/* as skills, so keep Pi skill backups outside
    # that discovery directory to avoid duplicate "memory-bank" skill conflicts.
    local old backup
    if [ "$target" = "$PI_SKILL_ALIAS" ]; then
      mkdir -p "$PI_AGENT_DIR/.memory-bank-backups"
      for old in "$PI_AGENT_DIR/.memory-bank-backups/memory-bank.pre-mb-backup."*; do
        [ -e "$old" ] || [ -L "$old" ] || continue
        rm -rf -- "$old"
      done
      backup="$PI_AGENT_DIR/.memory-bank-backups/memory-bank.pre-mb-backup.$(date +%s)"
    elif [ "$target" = "$OPENCODE_SKILL_ALIAS" ]; then
      mkdir -p "$OPENCODE_DIR/.memory-bank-backups"
      for old in "$OPENCODE_DIR/.memory-bank-backups/memory-bank.pre-mb-backup."*; do
        [ -e "$old" ] || [ -L "$old" ] || continue
        rm -rf -- "$old"
      done
      backup="$OPENCODE_DIR/.memory-bank-backups/memory-bank.pre-mb-backup.$(date +%s)"
    else
      # H-4: NEVER rotate away the OLDEST backup — it holds the user's TRUE
      # original. If one already exists, the current file is an MB artifact from a
      # prior install: prune only newer (MB-generated) backups, keep the original,
      # re-record it in this run's manifest, and take no new backup.
      # (compgen-free glob; tolerates "no match" without nullglob.)
      local mb_oldest="" mb_old
      for mb_old in "$target".pre-mb-backup.*; do
        { [ -e "$mb_old" ] || [ -L "$mb_old" ]; } || continue
        mb_oldest="$mb_old"; break   # glob is lexically sorted → oldest epoch first
      done
      if [ -n "$mb_oldest" ]; then
        for mb_old in "$target".pre-mb-backup.*; do
          { [ -e "$mb_old" ] || [ -L "$mb_old" ]; } || continue
          [ "$mb_old" = "$mb_oldest" ] && continue
          rm -rf -- "$mb_old"
        done
        BACKED_UP_FILES+=("$target|$mb_oldest")
        return 0
      fi
      backup="$target.pre-mb-backup.$(date +%s).$$"
    fi
    mv "$target" "$backup"
    BACKED_UP_FILES+=("$target|$backup")
  fi
}

quarantine_legacy_opencode_skill_backups() {
  # Old installers used ~/.opencode/skills/memory-bank.backup.*. OpenCode still
  # scans that root, so those backup directories can shadow the current skill.
  # Move only MB-generated backup directories, preserving them outside discovery.
  local legacy_skills="$OPENCODE_LEGACY_DIR/skills"
  local backup_root="$OPENCODE_LEGACY_DIR/.memory-bank-backups"
  local old base dest i
  [ -d "$legacy_skills" ] || return 0

  for old in "$legacy_skills"/memory-bank.backup.* "$legacy_skills"/memory-bank.pre-mb-backup.*; do
    [ -e "$old" ] || [ -L "$old" ] || continue
    [ -e "$old/SKILL.md" ] || [ -L "$old/SKILL.md" ] || continue
    mkdir -p "$backup_root"
    base="$(basename "$old")"
    dest="$backup_root/$base"
    i=2
    while [ -e "$dest" ] || [ -L "$dest" ]; do
      dest="$backup_root/$base.$i"
      i=$((i + 1))
    done
    mv "$old" "$dest"
    BACKED_UP_FILES+=("$old|$dest")
  done
}

quarantine_legacy_opencode_managed_plugin() {
  # OpenCode also auto-discovers ~/.opencode/plugins/*. A legacy MB-managed plugin
  # there loads alongside the project plugin, so move only marker-confirmed MB files.
  local old="$OPENCODE_LEGACY_DIR/plugins/memory-bank.js"
  local backup_root="$OPENCODE_LEGACY_DIR/.memory-bank-backups/plugins"
  local dest i
  { [ -e "$old" ] || [ -L "$old" ]; } || return 0
  grep -q "memory-bank: managed plugin" "$old" 2>/dev/null || return 0

  mkdir -p "$backup_root"
  dest="$backup_root/memory-bank.js.pre-mb-backup.$(date +%s)"
  i=2
  while [ -e "$dest" ] || [ -L "$dest" ]; do
    dest="$backup_root/memory-bank.js.pre-mb-backup.$(date +%s).$i"
    i=$((i + 1))
  done
  mv "$old" "$dest"
  BACKED_UP_FILES+=("$old|$dest")
}

install_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  # Content-identity shortcut — avoid spurious .pre-mb-backup.* on repeat installs.
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    [[ "$dst" == *.sh || "$dst" == *.py ]] && chmod +x "$dst"
    INSTALLED_FILES+=("$dst")
    return 0
  fi

  backup_if_exists "$dst"
  cp "$src" "$dst"
  [[ "$dst" == *.sh || "$dst" == *.py ]] && chmod +x "$dst"
  INSTALLED_FILES+=("$dst")
}

# A18 (CDX-I4): the language-rule strings are resolved through
# memory_bank_skill._texttools (single source of truth, pytest-covered)
# instead of these bash case statements — es/zh used to fall through both
# with an empty string (`> **Language** — ` with nothing after the dash).
# Locales without a vetted translation fall back to the English strings and
# report it once via a stderr warning, resolved lazily and memoized so the
# `run_texttool` subprocess only runs once per install even though
# language_rule_full/short/comments_language_name are each called multiple
# times (CLAUDE.md merge branches, settings.json, memory-bank-config.json).
LANG_STRINGS_RESOLVED=0
LANG_RULE_FULL=""
LANG_RULE_SHORT=""
LANG_COMMENTS_NAME=""

resolve_language_strings() {
  [ "$LANG_STRINGS_RESOLVED" = "1" ] && return 0
  local out used_fallback
  out="$(run_texttool language-strings --language "$LANGUAGE" ${COMMENTS_LANGUAGE:+--comments-language "$COMMENTS_LANGUAGE"})"
  LANG_RULE_FULL="$(printf '%s\n' "$out" | sed -n 's/^RULE_FULL=//p')"
  LANG_RULE_SHORT="$(printf '%s\n' "$out" | sed -n 's/^RULE_SHORT=//p')"
  LANG_COMMENTS_NAME="$(printf '%s\n' "$out" | sed -n 's/^COMMENTS_LANGUAGE=//p')"
  used_fallback="$(printf '%s\n' "$out" | sed -n 's/^USED_FALLBACK=//p')"
  if [ "$used_fallback" = "1" ]; then
    echo "[install] language '$LANGUAGE' not yet localized — using en" >&2
  fi
  LANG_STRINGS_RESOLVED=1
}

language_rule_full() {
  resolve_language_strings
  printf '%s' "$LANG_RULE_FULL"
}

language_rule_short() {
  resolve_language_strings
  printf '%s' "$LANG_RULE_SHORT"
}

comments_language_name() {
  resolve_language_strings
  printf '%s' "$LANG_COMMENTS_NAME"
}

run_texttool() {
  PYTHONPATH="$SOURCE_SKILL_DIR${PYTHONPATH:+:$PYTHONPATH}" \
    "$MB_PY" -m memory_bank_skill._texttools "$@"
}

localize_installed_file() {
  local file="$1"
  local after_marker="${2:-}"
  [ -f "$file" ] || return 0
  run_texttool localize-file \
    --path "$file" \
    --rule-full "$(language_rule_full)" \
    --rule-short "$(language_rule_short)" \
    --comments-language "$(comments_language_name)" \
    --after-marker "$after_marker"
}

# Apply localization in-place to an arbitrary file (not bound to "standard" target).
# Uses the same language-substitution logic as localize_installed_file() but skips the
# file-existence-is-acceptable short-circuit; caller guarantees the file exists.
localize_path_inplace() {
  local file="$1"
  local after_marker="${2:-}"
  [ -f "$file" ] || return 0
  run_texttool localize-file \
    --path "$file" \
    --rule-full "$(language_rule_full)" \
    --rule-short "$(language_rule_short)" \
    --comments-language "$(comments_language_name)" \
    --after-marker "$after_marker"
}

# Idempotent copy+localize: compose expected post-install content in a temp file,
# compare with the current dst, and skip the backup+write entirely when they match.
install_file_localized() {
  local src="$1" dst="$2" marker="${3:-}"
  mkdir -p "$(dirname "$dst")"

  local tmp
  tmp="$(mktemp)"
  cp "$src" "$tmp"
  localize_path_inplace "$tmp" "$marker"

  if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then
    rm -f "$tmp"
    INSTALLED_FILES+=("$dst")
    return 0
  fi

  backup_if_exists "$dst"
  mv "$tmp" "$dst"
  INSTALLED_FILES+=("$dst")
}

write_language_config() {
  local config_path="$CLAUDE_DIR/memory-bank-config.json"
  mkdir -p "$CLAUDE_DIR"
  cat > "$config_path" <<EOF
{
  "preferred_language": "$LANGUAGE",
  "comments_language": "$COMMENTS_LANGUAGE",
  "language_rule": "$(language_rule_full)"
}
EOF
  INSTALLED_FILES+=("$config_path")
}

install_symlink() {
  local source="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$source" ]; then
    INSTALLED_FILES+=("$dest")
    return
  fi

  if [ -L "$dest" ]; then
    # Replacing a symlink is safe: remove the link itself, never its target.
    # This supports upgrades from pipx/share aliases outside ~/.claude.
    rm -f "$dest"
  else
    backup_if_exists "$dest"
  fi
  ln -s "$source" "$dest"
  INSTALLED_FILES+=("$dest")
}

resolve_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

ensure_skill_aliases() {
  mkdir -p "$CLAUDE_DIR/skills" "$CODEX_DIR/skills" "$CURSOR_DIR/skills" "$PI_AGENT_DIR/skills" \
    "$OPENCODE_DIR/skills"
  quarantine_legacy_opencode_skill_backups
  quarantine_legacy_opencode_managed_plugin

  local source_real canonical_real
  source_real="$(resolve_dir "$SOURCE_SKILL_DIR")"
  canonical_real=""
  if [ -e "$CANONICAL_SKILL_DIR" ] || [ -L "$CANONICAL_SKILL_DIR" ]; then
    canonical_real="$(resolve_dir "$CANONICAL_SKILL_DIR")"
  fi

  if [ "$canonical_real" != "$source_real" ]; then
    install_symlink "$SOURCE_SKILL_DIR" "$CANONICAL_SKILL_DIR"
    echo -e "  ${GREEN}✓${NC} canonical skill: $CANONICAL_SKILL_DIR"
  else
    INSTALLED_FILES+=("$CANONICAL_SKILL_DIR")
    echo -e "  ${YELLOW}~${NC} canonical skill already points to source"
  fi

  install_symlink "$CANONICAL_SKILL_DIR" "$CLAUDE_SKILL_ALIAS"
  install_symlink "$CANONICAL_SKILL_DIR" "$CODEX_SKILL_ALIAS"
  install_symlink "$CANONICAL_SKILL_DIR" "$CURSOR_SKILL_ALIAS"
  install_symlink "$CANONICAL_SKILL_DIR" "$PI_SKILL_ALIAS"
  install_symlink "$CANONICAL_SKILL_DIR" "$OPENCODE_SKILL_ALIAS"
  echo -e "  ${GREEN}✓${NC} Claude/Codex/Cursor/Pi/OpenCode skill aliases"
}

# Global host blocks (Codex / OpenCode / Pi): a short host header plus the compact
# rules core (CLAUDE-GLOBAL.md). The Key rules block above them is written by
# Step 5.5 (mb-rules.sh sync --scope=user); detailed rules stay in the skill's
# rules/RULES.md (AGR-063, AGR-066).
opencode_agents_section() {
  cat <<EOF
$OPENCODE_START_MARKER

# Memory Bank — OpenCode Global Entry Point

OpenCode loads this file at startup. Skill: \`~/.config/opencode/skills/memory-bank/SKILL.md\`.
- Subagent roles are dispatched by name with \`task(subagent_type=<name>)\`.
- On a bare OpenCode host (parity extensions not installed yet), suggest running
  \`install.sh --with-extensions=opencode\` once per session, then stay silent once installed.

EOF
  sed 's#~/.claude/RULES.md#~/.config/opencode/skills/memory-bank/rules/RULES.md#g; s#~/.claude/skills/memory-bank#~/.config/opencode/skills/memory-bank#g' "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  cat <<EOF

$OPENCODE_END_MARKER
EOF
}

install_opencode_global_agents() {
  local section state file="$OPENCODE_DIR/AGENTS.md" tmp
  # Upgrade: rename the old shared marker pair in place so the upsert below
  # refreshes the block instead of appending a second one.
  if [ -f "$file" ] && grep -qxF -- "<!-- memory-bank:start -->" "$file"; then
    tmp="$(mktemp "$file.XXXXXX")"
    cp -p "$file" "$tmp"
    awk -v os="<!-- memory-bank:start -->" -v oe="<!-- memory-bank:end -->" \
      -v ns="$OPENCODE_START_MARKER" -v ne="$OPENCODE_END_MARKER" '
      $0 == os { $0 = ns } $0 == oe { $0 = ne } { print }
    ' "$file" > "$tmp" && mv -f "$tmp" "$file" || rm -f "$tmp"
  fi
  section="$(mktemp)"
  opencode_agents_section > "$section"
  localize_path_inplace "$section" "$OPENCODE_START_MARKER"
  state="$(mb_upsert_marked_block "$file" "$OPENCODE_START_MARKER" "$OPENCODE_END_MARKER" "$section")"
  rm -f "$section"
  INSTALLED_FILES+=("$OPENCODE_DIR/AGENTS.md")
  echo -e "  ${GREEN}✓${NC} OpenCode AGENTS.md ($state)"
}

codex_agents_section() {
  cat <<EOF
$CODEX_START_MARKER

# Memory Bank — Codex Global Entry Point

Codex loads this file at startup. Skill: \`~/.codex/skills/memory-bank/SKILL.md\`.
- Codex has no native \`/mb\` slash commands: for \`/mb <command>\` read
  \`~/.codex/skills/memory-bank/commands/mb.md\` (it routes to \`commands/<command>.md\`) and follow it.
- Subagent roles: \`~/.codex/agents/<name>.toml\` — dispatch by name with
  \`spawn_agent(agent_type="<name>", message=…)\`; a pipeline \`thinking\` goes to \`reasoning_effort\`.
- Global lifecycle hooks are not guaranteed on Codex; the project \`.codex/\` adapter files carry them.

EOF
  sed 's#~/.claude/RULES.md#~/.codex/skills/memory-bank/rules/RULES.md#g; s#~/.claude/skills/memory-bank#~/.codex/skills/memory-bank#g' "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  cat <<EOF

$CODEX_END_MARKER
EOF
}

install_codex_global_agents() {
  local section state
  # Localize the section like the Claude/Pi blocks — without this a `--language ru`
  # install left "respond in English" inside ~/.codex/AGENTS.md.
  section="$(mktemp)"
  codex_agents_section > "$section"
  localize_path_inplace "$section" "$CODEX_START_MARKER"
  state="$(mb_upsert_marked_block "$CODEX_DIR/AGENTS.md" "$CODEX_START_MARKER" "$CODEX_END_MARKER" "$section")"
  rm -f "$section"
  INSTALLED_FILES+=("$CODEX_DIR/AGENTS.md")
  echo -e "  ${GREEN}✓${NC} Codex AGENTS.md ($state)"
}

# Codex discovers subagent roles as TOML in ~/.codex/agents/ and runs them through
# `spawn_agent(agent_type=<name>)`; the renderer composes partials and maps `effort`.
# The tier model comes from the same pipeline as `adapters/codex.sh render-agents`
# (`/mb config init --host codex`): the project's .memory-bank/pipeline.yaml, else
# the shipped default — so a reinstall keeps the `model = "…"` lines byte-identical.
install_codex_agent_roles() {
  local f name roles_tmp count=0 pipeline="$PROJECT_ROOT/.memory-bank/pipeline.yaml"
  [ -f "$pipeline" ] || pipeline="$SOURCE_SKILL_DIR/references/pipeline.default.yaml"
  roles_tmp="$(mktemp -d)"
  for f in "$SOURCE_SKILL_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    head -5 "$f" | grep -qiE '^partial:[[:space:]]*true[[:space:]]*$' && continue
    name="$(basename "$f" .md)"
    "$MB_PY" "$SOURCE_SKILL_DIR/scripts/mb-agent-render.py" "$f" --skill-dir "$SOURCE_SKILL_DIR" \
      --host codex --pipeline "$pipeline" > "$roles_tmp/$name.toml"
    install_file "$roles_tmp/$name.toml" "$CODEX_DIR/agents/$name.toml"
    count=$((count + 1))
  done
  rm -rf "$roles_tmp"
  echo -e "  ${GREEN}✓${NC} Codex subagent roles ($count in $CODEX_DIR/agents)"
}


# ═══ Step 1: Rules ═══
echo -e "${BLUE}[1/7] Rules${NC}"
install_file_localized "$SOURCE_SKILL_DIR/rules/RULES.md" "$CLAUDE_DIR/RULES.md"
echo -e "  ${GREEN}✓${NC} RULES.md"

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  claude_has_start=0
  claude_has_end=0
  grep -qF -- "$CLAUDE_MB_START_MARKER" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null && claude_has_start=1
  grep -qF -- "$CLAUDE_MB_END_MARKER" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null && claude_has_end=1

  if [ "$claude_has_start" -eq 0 ]; then
    # No MB start marker at all yet — the whole current file is 100% user
    # content. Capture it BEFORE backup_if_exists moves it aside (same
    # capture-then-backup order as the paired-marker branch below) so the
    # live file stays self-contained from THIS install onward: [original
    # content][MB block]. Previously this branch backed the original up and
    # then `>>`-appended to a path backup_if_exists had already `mv`'d away,
    # which silently behaves like `>` — the live file ended up with ONLY the
    # MB block, and the original content was recoverable ONLY by uninstall.sh
    # blind-restoring the backup (which also clobbered any edits made after
    # install — CDX-I9 / A20).
    claude_orig_tmp="$CLAUDE_DIR/CLAUDE.md.orig.tmp"
    cp "$CLAUDE_DIR/CLAUDE.md" "$claude_orig_tmp"
    MB_BLOCK_FILE=1 backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
    {
      if grep -q '[^[:space:]]' "$claude_orig_tmp"; then
        awk 'NF { last=NR } { lines[NR]=$0 } END { for (i=1; i<=last; i++) print lines[i] }' "$claude_orig_tmp"
        printf '\n\n'
      fi
      printf '%s\n\n' "$CLAUDE_MB_START_MARKER"
      cat "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
      printf '\n%s\n' "$CLAUDE_MB_END_MARKER"
    } > "$CLAUDE_DIR/CLAUDE.md"
    rm -f "$claude_orig_tmp"
    localize_installed_file "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_MB_START_MARKER"
    INSTALLED_FILES+=("$CLAUDE_DIR/CLAUDE.md")
    echo -e "  ${GREEN}✓${NC} CLAUDE.md (merged)"
  elif [ "$claude_has_end" -eq 0 ]; then
    # Legacy/hand-edited file: a start marker with no matching end marker
    # (pre-A13 files never wrote one). We do NOT try to guess where "our"
    # content ends without a paired end marker — take a full backup first
    # (recoverable via uninstall.sh's backup-restore step) and append a
    # fresh, properly paired block rather than destructively consuming
    # start..EOF (the old M-5 bug).
    MB_ALWAYS_BACKUP=1 backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
    {
      printf '\n%s\n\n' "$CLAUDE_MB_START_MARKER"
      cat "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
      printf '\n%s\n' "$CLAUDE_MB_END_MARKER"
    } >> "$CLAUDE_DIR/CLAUDE.md"
    localize_installed_file "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_MB_START_MARKER"
    INSTALLED_FILES+=("$CLAUDE_DIR/CLAUDE.md")
    echo -e "  ${GREEN}✓${NC} CLAUDE.md (merged)"
  else
    # A13 (M-5): paired markers present — replace strictly between them,
    # preserving anything before the start marker AND after the end marker.
    # Capture both slices BEFORE backup_if_exists runs: it `mv`s the live
    # file out to the backup path on its first call for a given target, so
    # reading "$CLAUDE_DIR/CLAUDE.md" afterwards would hit a file that no
    # longer exists at that path.
    claude_before_tmp="$CLAUDE_DIR/CLAUDE.md.before.tmp"
    claude_after_tmp="$CLAUDE_DIR/CLAUDE.md.after.tmp"
    # The Key rules block is ours too (re-rendered at Step 5.5): leave it out of
    # the user slice so it never triggers a backup.
    awk -v s="$CLAUDE_MB_START_MARKER" '
      index($0, "<!-- mb-key-rules:start -->") { kr = 1 }
      kr { if (index($0, "<!-- mb-key-rules:end -->")) kr = 0; next }
      index($0, s) { exit }
      { print }
    ' "$CLAUDE_DIR/CLAUDE.md" > "$claude_before_tmp"
    awk -v e="$CLAUDE_MB_END_MARKER" '
      found { print; next }
      index($0, e) { found=1; next }
    ' "$CLAUDE_DIR/CLAUDE.md" > "$claude_after_tmp"
    # Back up ONLY when real user content lives outside our managed block. Both
    # slices are preserved verbatim by the rewrite below, so a file that is
    # nothing but our own block has nothing to lose — snapshotting it would mint
    # a fresh .pre-mb-backup.* on every repeat install and make the manifest
    # non-idempotent. When user content IS present, backup_if_exists still
    # applies H-4 (keep the oldest true original, re-record it, take no new one).
    if grep -q '[^[:space:]]' "$claude_before_tmp" || grep -q '[^[:space:]]' "$claude_after_tmp"; then
      MB_BLOCK_FILE=1 backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
    fi
    {
      if grep -q '[^[:space:]]' "$claude_before_tmp"; then
        awk 'NF { last=NR } { lines[NR]=$0 } END { for (i=1; i<=last; i++) print lines[i] }' "$claude_before_tmp"
        printf '\n\n'
      fi
      printf '%s\n\n' "$CLAUDE_MB_START_MARKER"
      cat "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
      printf '\n%s\n' "$CLAUDE_MB_END_MARKER"
      if grep -q '[^[:space:]]' "$claude_after_tmp"; then
        printf '\n'
        cat "$claude_after_tmp"
      fi
    } > "$CLAUDE_DIR/CLAUDE.md"
    rm -f "$claude_before_tmp" "$claude_after_tmp"
    localize_installed_file "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_MB_START_MARKER"
    INSTALLED_FILES+=("$CLAUDE_DIR/CLAUDE.md")
    echo -e "  ${YELLOW}~${NC} CLAUDE.md (MB section refreshed)"
  fi
else
  mkdir -p "$CLAUDE_DIR"
  {
    printf '%s\n\n' "$CLAUDE_MB_START_MARKER"
    cat "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
    printf '\n%s\n' "$CLAUDE_MB_END_MARKER"
  } > "$CLAUDE_DIR/CLAUDE.md"
  localize_installed_file "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_MB_START_MARKER"
  INSTALLED_FILES+=("$CLAUDE_DIR/CLAUDE.md")
  echo -e "  ${GREEN}✓${NC} CLAUDE.md (created with marker)"
fi

write_language_config
echo -e "  ${GREEN}✓${NC} language preference ($LANGUAGE)"

# A25 (CDX-I13): these three ALWAYS run — independent of `--clients` — because
# the global agent-resources they install (skill alias + AGENTS.md + prompt
# templates under ~/.codex, ~/.config/opencode, ~/.pi/agent) are cheap,
# idempotent, and useful the moment a user opens that host, even before they
# ever pick it as a --clients target for THIS project. Gating global install
# by selected clients is a separate product decision, intentionally not
# implemented here (see docs/cross-agent-setup.md "Global agent resources").
install_opencode_global_agents
install_codex_global_agents
install_codex_agent_roles
pi_agents_state="$(SKILL_DIR="$SOURCE_SKILL_DIR" install_pi_global_agents)"
INSTALLED_FILES+=("$PI_AGENT_DIR/AGENTS.md")
echo -e "  ${GREEN}✓${NC} Pi AGENTS.md ($pi_agents_state)"
MB_PYTHON="$MB_PY" install_pi_settings_skill
INSTALLED_FILES+=("$PI_AGENT_DIR/settings.json")
echo -e "  ${GREEN}✓${NC} Pi settings.json (memory-bank skill merged)"

# ═══ Step 2: Agents ═══
echo -e "${BLUE}[2/7] Agents${NC}"
agents_installed=0
agents_render_dir="$(mktemp -d)"
for f in "$SOURCE_SKILL_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  # Skip partials (frontmatter `partial: true`, e.g. mb-engineering-core): they are
  # composed into the agents that declare `compose:` (scripts/mb-agent-render.py),
  # not standalone subagents — keep them out of the ~/.claude/agents/ registry.
  if head -5 "$f" | grep -qiE '^partial:[[:space:]]*true[[:space:]]*$'; then
    continue
  fi
  "$MB_PY" "$SOURCE_SKILL_DIR/scripts/mb-agent-render.py" "$f" --skill-dir "$SOURCE_SKILL_DIR" \
    > "$agents_render_dir/$(basename "$f")"
  install_file "$agents_render_dir/$(basename "$f")" "$CLAUDE_DIR/agents/$(basename "$f")"
  agents_installed=$((agents_installed + 1))
done
rm -rf "$agents_render_dir"
echo -e "  ${GREEN}✓${NC} ${agents_installed} agents (partials excluded from registry)"

# ═══ Step 3: Hooks ═══
echo -e "${BLUE}[3/7] Hooks${NC}"
# Bash hooks + the semantic-recall python CLI (mb-semantic.py) live side by side.
for f in "$SOURCE_SKILL_DIR"/hooks/*.sh "$SOURCE_SKILL_DIR"/hooks/*.py; do
  [ -f "$f" ] || continue
  install_file "$f" "$CLAUDE_DIR/hooks/$(basename "$f")"
done
# Shared helpers sourced/imported by the hooks via "$HOOK_DIR/lib/..." — bash session
# helpers AND the semantic python libs (semantic_*.py, indexer.py, searcher.py). The
# copied-path hooks (e.g. ~/.claude/hooks/mb-recall.sh) need lib/ as a sibling.
if [ -d "$SOURCE_SKILL_DIR/hooks/lib" ]; then
  mkdir -p "$CLAUDE_DIR/hooks/lib"
  for f in "$SOURCE_SKILL_DIR"/hooks/lib/*.sh "$SOURCE_SKILL_DIR"/hooks/lib/*.py; do
    [ -f "$f" ] || continue
    install_file "$f" "$CLAUDE_DIR/hooks/lib/$(basename "$f")"
  done
fi
echo -e "  ${GREEN}✓${NC} $(count_matching_files "$SOURCE_SKILL_DIR/hooks" '*.sh') hooks + semantic CLI"

# ═══ Step 4: Commands ═══
echo -e "${BLUE}[4/7] Commands${NC}"
for f in "$SOURCE_SKILL_DIR"/commands/*.md; do
  [ -f "$f" ] || continue
  install_file "$f" "$CLAUDE_DIR/commands/$(basename "$f")"
  install_file "$f" "$OPENCODE_DIR/commands/$(basename "$f")"
  install_file "$f" "$PI_AGENT_DIR/prompts/$(basename "$f")"
  # Codex CLI reads slash-commands from ~/.codex/prompts/ (unknown frontmatter
  # fields are ignored by Codex, so the same source file is reused as-is).
  install_file "$f" "$CODEX_DIR/prompts/$(basename "$f")"
done
echo -e "  ${GREEN}✓${NC} $(count_matching_files "$SOURCE_SKILL_DIR/commands" '*.md') commands/prompts"

# ═══ Step 5: Skill files ═══
echo -e "${BLUE}[5/7] Skill registration${NC}"
ensure_skill_aliases
# Idempotency guard: install-global is safe to repeat but wasteful on every run
# (redundant writes + backup rotation). Skip it ONLY when the Cursor global
# manifest already records BOTH the current skill version AND the requested
# locale — a version bump OR a language switch (e.g. re-running with
# --language ru after an en install) must force a re-install so the localized
# rules are regenerated; a version-only guard would leave stale-language rules.
_cursor_global_up_to_date() {
  local manifest="$CURSOR_DIR/.mb-manifest.json" want have want_lang have_lang
  [ -f "$manifest" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  want="$(cat "$SOURCE_SKILL_DIR/VERSION" 2>/dev/null || echo unknown)"
  have="$(jq -r '.skill_version // empty' "$manifest" 2>/dev/null || true)"
  want_lang="${LANGUAGE:-en}"
  have_lang="$(jq -r '.lang // empty' "$manifest" 2>/dev/null || true)"
  [ -n "$have" ] && [ "$have" = "$want" ] && [ "$have_lang" = "$want_lang" ] || return 1
  # Same VERSION can still ship a changed ~/.cursor/AGENTS.md section: compare its hash.
  [ "$(jq -r '.section_sha // empty' "$manifest" 2>/dev/null)" = \
    "$(bash "$SOURCE_SKILL_DIR/adapters/cursor.sh" section-sha 2>/dev/null)" ] || return 1
  # Version + language alone left installs that predate ~/.cursor/agents (or lost
  # files since) without them: every managed file must exist, subagents included.
  local f agents=0
  while IFS= read -r f; do
    [ -e "$f" ] || return 1
    case "$f" in */.cursor/agents/*) agents=1 ;; esac
  done < <(jq -r '.files[]? // empty' "$manifest" 2>/dev/null)
  [ "$agents" -eq 1 ]
}
if _cursor_global_up_to_date; then
  echo -e "  ${GREEN}✓${NC} Cursor global artifacts already current (skip)"
elif MB_LANGUAGE="$LANGUAGE" bash "$SOURCE_SKILL_DIR/adapters/cursor.sh" install-global; then
  echo -e "  ${GREEN}✓${NC} Cursor global artifacts via adapter"
else
  echo -e "  ${YELLOW}~${NC} Cursor global adapter install failed" >&2
fi

if [ -f "$HOME/.cursor/memory-bank-user-rules.md" ]; then
  echo -e "  ${BLUE}→${NC} Cursor User Rules: paste ~/.cursor/memory-bank-user-rules.md into Settings → Rules → User Rules"
  if [ -t 0 ]; then
    echo -e "       (interactive paste prompt runs at end of cursor adapter install-global)"
  fi
fi

# ═══ Step 5.5: Key rules ═══
# The managed `## Key rules` block at the top of the global CLAUDE.md / AGENTS.md
# files (scripts/mb-rules.sh). The selection lives in the user rules profile.
# On a TTY, `init --interactive` asks the checklist, own rules, then the Quality
# step (architecture, TDD, Trophy, coverage — memory_bank_skill/key_rules_prompt.py).
MB_RULES_SH="$SOURCE_SKILL_DIR/scripts/mb-rules.sh"
if [ -z "$KEY_RULES_MODE" ] && [ "$NON_INTERACTIVE" -eq 0 ] && [ -t 0 ]; then
  MB_PYTHON="$MB_PY" bash "$MB_RULES_SH" init --interactive --scope=user
elif [ "$KEY_RULES_MODE" = default ]; then
  MB_PYTHON="$MB_PY" bash "$MB_RULES_SH" init --scope=user >/dev/null
fi
MB_PYTHON="$MB_PY" bash "$MB_RULES_SH" sync --scope=user >/dev/null
echo -e "  ${GREEN}✓${NC} Key rules + Quality (/mb rules to change)"

# ═══ Step 6: Settings hooks ═══
echo -e "${BLUE}[6/7] Settings${NC}"
if [ -f "$SOURCE_SKILL_DIR/settings/hooks.json" ] && command -v "$MB_PY" &>/dev/null; then
  "$MB_PY" "$SOURCE_SKILL_DIR/settings/merge-hooks.py" \
    "$CLAUDE_DIR/settings.json" \
    "$SOURCE_SKILL_DIR/settings/hooks.json" \
    2>/dev/null && echo -e "  ${GREEN}✓${NC} Hooks merged" \
    || echo -e "  ${YELLOW}~${NC} Manual hook setup may be needed"
  localize_installed_file "$CLAUDE_DIR/settings.json"
  INSTALLED_FILES+=("$CLAUDE_DIR/settings.json")
else
  echo -e "  ${YELLOW}~${NC} Skipped (python3 required for merge)"
fi

# ═══ Step 6.5: superpowers reviewer probe (informational) ═══
# Detects whether the `superpowers` skill / plugin (e.g. for the
# `requesting-code-review` flow) is installed alongside this skill.
# Detection is informational only — `scripts/mb-reviewer-resolve.sh` reads
# pipeline.yaml at /mb work runtime to honour the override, regardless of
# what this probe prints.
SUPERPOWERS_DIR="$CLAUDE_DIR/skills/superpowers"
if [ -d "$SUPERPOWERS_DIR" ]; then
  echo -e "  ${GREEN}✓${NC} superpowers skill detected — /mb work review will route to superpowers:requesting-code-review when pipeline.yaml override is enabled"
else
  echo -e "  ${YELLOW}~${NC} superpowers skill not detected — /mb work review uses bundled mb-reviewer (default)"
fi

# ═══ Step 7: Manifest ═══
# Single canonical writer is flush_manifest() (defined up top). Calling it here on
# the success path sets MB_MANIFEST_FLUSHED so the EXIT trap becomes a no-op; on a
# partial failure BEFORE this line, the trap flushes the same manifest instead.
echo -e "${BLUE}[7/7] Manifest${NC}"
flush_manifest
echo "  Manifest saved"

# ═══ Step 8: Cross-agent adapters (optional) ═══
# A17: a failing (or missing/not-executable) adapter no longer disappears into
# a stderr line while the top-level install reports success — it's collected
# in ADAPTERS_FAILED and fails the overall exit code AFTER every adapter has
# had its turn, so one broken adapter can't block its healthy siblings.
# Cursor runs last: its .mdc leaves out the Key rules when the project AGENTS.md
# (written by the codex/opencode/pi adapters) already carries them.
ORDERED_CLIENTS=()
for c in "${CLIENTS_ARR[@]}"; do [ "${c// /}" = cursor ] || ORDERED_CLIENTS+=("$c"); done
for c in "${CLIENTS_ARR[@]}"; do [ "${c// /}" != cursor ] || ORDERED_CLIENTS+=("$c"); done
for c in "${ORDERED_CLIENTS[@]}"; do
  c_trimmed="${c// /}"
  [ "$c_trimmed" = "claude-code" ] && continue  # already done above
  adapter="$SOURCE_SKILL_DIR/adapters/$c_trimmed.sh"
  if [ ! -x "$adapter" ]; then
    echo -e "  ${RED}✗${NC} adapter missing or not executable: $adapter" >&2
    ADAPTERS_FAILED+=("$c_trimmed")
    continue
  fi
  echo -e "${BLUE}[8/8] Cross-agent: $c_trimmed${NC}"
  if MB_LANGUAGE="$LANGUAGE" bash "$adapter" install "$PROJECT_ROOT"; then
    ADAPTERS_INVOKED+=("$c_trimmed")
  else
    echo -e "  ${RED}✗${NC} adapter $c_trimmed failed" >&2
    ADAPTERS_FAILED+=("$c_trimmed")
  fi
done

# Files the previous install wrote and this one did not (an older version's
# leftovers, e.g. a retired hook). Unchanged since then (sha256 recorded in the
# manifest; older manifests: not modified after their install time) → removed.
# Edited → moved to <file>.pre-mb-backup.<epoch> with a warning. Only regular
# files and symlinks under the global dirs this script manages; anything this
# run (re)wrote, adapters included, is skipped.
remove_previous_orphans() {
  [ -s "$PREV_OWNED" ] || return 0
  INSTALLED_FILES_STR="$(printf '%s\n' ${INSTALLED_FILES[@]+"${INSTALLED_FILES[@]}"})" \
  MB_ROOTS="$(printf '%s\n' "$CLAUDE_DIR" "$CODEX_DIR" "$OPENCODE_DIR" "$PI_AGENT_DIR")" \
    "$MB_PY" - "$PREV_OWNED" "$PREV_UNCHANGED" "$MB_RUN_START" <<'PY'
import os, sys, time
owned, unchanged = ([l for l in open(p).read().split("\n") if l] for p in sys.argv[1:3])
unchanged = set(unchanged)
run_start = os.path.getmtime(sys.argv[3])
current = set(os.environ.get("INSTALLED_FILES_STR", "").split("\n"))
roots = [r.rstrip("/") + "/" for r in os.environ["MB_ROOTS"].split("\n") if r]
removed = 0
for path in owned:
    if path in current or not any(path.startswith(r) for r in roots):
        continue
    if os.path.islink(path) or path in unchanged:
        os.unlink(path)
        removed += 1
    elif os.path.isfile(path) and os.path.getmtime(path) < run_start:
        backup = f"{path}.pre-mb-backup.{int(time.time())}"
        os.replace(path, backup)
        print(f"  ! {path} is no longer part of Memory Bank but was edited — moved to {backup}", file=sys.stderr)
if removed:
    print(f"  ~ removed {removed} file(s) left by the previous version")
PY
}
remove_previous_orphans

# A10/A17: re-flush the manifest now that ADAPTERS_INVOKED/ADAPTERS_FAILED/
# PROJECT_ROOT are known, so uninstall.sh can look up which per-project
# adapters to uninstall and the manifest reflects any adapter failure.
flush_manifest

echo ""
echo -e "${GREEN}═══ Memory Bank installed ═══${NC}"
if [ "${#ADAPTERS_INVOKED[@]}" -gt 0 ]; then
  echo -e "  Cross-agent adapters: ${ADAPTERS_INVOKED[*]} (project: $PROJECT_ROOT)"
fi
if [ "${#EXTENSIONS_INSTALLED[@]}" -gt 0 ]; then
  echo -e "  Parity extensions accepted: ${EXTENSIONS_INSTALLED[*]}"
fi
echo ""
echo "  Next: /mb init — init .memory-bank/ + auto-generate CLAUDE.md (--full, default)"
echo "  Canonical skill: $CANONICAL_SKILL_DIR"
echo "  Claude alias:    $CLAUDE_SKILL_ALIAS"
echo "  Codex alias:     $CODEX_SKILL_ALIAS"
echo "  Cursor alias:    $CURSOR_SKILL_ALIAS"
echo "  Pi alias:        $PI_SKILL_ALIAS"
echo "  Pi prompts:      $PI_AGENT_DIR/prompts/"
echo "  Uninstall: $SOURCE_SKILL_DIR/uninstall.sh"
echo ""
echo "  Optional — multi-language code graph (Go/JS/TS/Rust/Java via tree-sitter):"
echo "    bash $SOURCE_SKILL_DIR/hooks/mb-semantic-bootstrap.sh  (tree-sitter + grammars + networkx)"
echo "  Without these, /mb graph covers Python/Bash/Bats only (stdlib ast/re), no clusters."

# A17: surface adapter failures in the exit code. Everything else above has
# already run to completion (global install + every other adapter) — this is
# reported last, after the user sees what DID succeed, and is the reason the
# script exits nonzero despite the "installed" banner above.
if [ "${#ADAPTERS_FAILED[@]}" -gt 0 ]; then
  echo ""
  echo -e "${RED}✗${NC} ${#ADAPTERS_FAILED[@]} adapter(s) failed: ${ADAPTERS_FAILED[*]} (see errors above)" >&2
  exit 1
fi
echo ""
