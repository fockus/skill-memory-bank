#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# skill-memory-bank — Installer
# Long-term project memory + global rules + 29 dev commands
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SOURCE_SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SOURCE_SKILL_DIR/scripts/_lib.sh"
# Interpreter that owns the memory_bank_skill package. The `memory-bank` CLI
# exports MB_PYTHON=sys.executable so pipx/pip/Homebrew installs invoke the
# venv's python (a bare system python3 cannot import the package). Falls back
# to python3 for a direct `bash install.sh` from a git checkout.
MB_PY="${MB_PYTHON:-python3}"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
CURSOR_DIR="$HOME/.cursor"
OPENCODE_DIR="$HOME/.config/opencode"
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
PI_START_MARKER="<!-- memory-bank-pi:start -->"
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
    MANIFEST_CLIENTS_REQUESTED="${CLIENTS:-}" \
    MANIFEST_PATH="$MANIFEST" \
    INSTALL_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$MB_PY" << 'PYEOF' 2>&1
import json, os, tempfile
files = [f for f in os.environ.get("INSTALLED_FILES_STR", "").split("\n") if f]
raw_backups = [b for b in os.environ.get("BACKED_UP_STR", "").split("\n") if b]
clients = [c for c in os.environ.get("CLIENTS_INSTALLED_STR", "").split("\n") if c]
clients_failed = [c for c in os.environ.get("CLIENTS_FAILED_STR", "").split("\n") if c]
extensions_installed = [e for e in os.environ.get("EXTENSIONS_INSTALLED_STR", "").split("\n") if e]


def _ordered_unique(items):
    return list(dict.fromkeys(items))


def _backup_path(entry: str) -> str:
    parts = entry.split("|", 1)
    return parts[1] if len(parts) == 2 else ""


backups = _ordered_unique([b for b in raw_backups if os.path.exists(_backup_path(b))])
manifest = {
    "schema_version": 1,
    "installed_at": os.environ["INSTALL_DATE"],
    "skill": "skill-memory-bank",
    "files": _ordered_unique(files),
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
    # A21: the install options as requested (language, full --clients list
    # including claude-code) so `mb-upgrade.sh` can reapply them non-interactively
    # on the next re-install instead of silently resetting to en/claude-code-only.
    "language": os.environ.get("MANIFEST_LANGUAGE", ""),
    "clients_requested": os.environ.get("MANIFEST_CLIENTS_REQUESTED", ""),
}
path = os.environ["MANIFEST_PATH"]
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
    echo "$mf_output" | sed 's/^/    /' >&2
  fi
  MB_MANIFEST_FLUSHED=1
}

_mb_on_exit() {
  local rc=$?   # preserve the triggering exit code across the flush
  [ "$MB_MANIFEST_FLUSHED" = "1" ] && return "$rc"
  flush_manifest
  return "$rc"
}

# shellcheck disable=SC1091
. "$SOURCE_SKILL_DIR/adapters/_lib_agents_md.sh"
# scripts/_lib.sh already sourced above (needed early for mb_resolve_manifest_path).

count_matching_files() {
  find "$1" -maxdepth 1 -type f -name "$2" | wc -l | tr -d ' '
}

# ═══ Arg parsing ═══
VALID_CLIENTS=(claude-code cursor windsurf cline kilo opencode pi codex)
VALID_LANGUAGES=(en ru es zh)
CLIENTS=""                  # unset sentinel — triggers interactive or default
LANGUAGE=""                 # unset sentinel — triggers interactive or default
PROJECT_ROOT="$PWD"
NON_INTERACTIVE=0
# adapter-parity T2: opt-in host parity-extension offer (pi/opencode only).
# WITH_EXTENSIONS_FLAG=1 means "don't prompt — decide from WITH_EXTENSIONS_VALUE".
# Empty value = accept every offered host; non-empty = comma list of hosts.
WITH_EXTENSIONS_FLAG=0
WITH_EXTENSIONS_VALUE=""

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
  --language <code>       Preferred locale for rules + .memory-bank/ templates.
                          Valid: en, ru, es, zh
                          (es/zh ship as scaffolds awaiting community translations)
                          If omitted and running in a TTY → interactive prompt.
                          Non-TTY default: en.
  --project-root <path>   Target directory for cross-agent adapters (default: PWD).
  --non-interactive       Never prompt; use defaults when --clients not passed.
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
    --non-interactive)
      NON_INTERACTIVE=1; shift ;;
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
# adapter-parity T2 (REQ-005): MB_WITH_EXTENSIONS env has the same contract as
# --with-extensions[=<list>] — an explicit CLI flag always wins. `+x` (not
# `-n`) so an env var set to the empty string still means "accept every
# offered host", matching the bare-flag behavior.
if [ "$WITH_EXTENSIONS_FLAG" != "1" ] && [ -n "${MB_WITH_EXTENSIONS+x}" ]; then
  WITH_EXTENSIONS_FLAG=1
  WITH_EXTENSIONS_VALUE="$MB_WITH_EXTENSIONS"
fi

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
    *)
      echo "[install.sh] invalid language '$reply' (valid: en, ru)" >&2
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
# T5 (opencode: parity plugin + global agents) still replaces its stub body
# with the real installer while keeping the exact signature — the offer
# plumbing above/below this function does not change again when it lands.
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
      echo -e "  ${YELLOW}~${NC} opencode parity extensions: install arrives in T5 (parity plugin + global agents) — no files written yet"
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
echo "  • Settings hooks (Setup, PreCompact, Stop)"
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

backup_if_exists() {
  # Skip-when-identical backup with rotation (keeps only the latest backup).
  # Args: $1 = target path, $2 (optional) = expected content path.
  # If $2 is given and target content already matches expected, return 2 (skip marker).
  # Legacy 1-arg callers keep previous behavior: unconditional backup.
  local target="$1"
  local expected="${2:-}"
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
  out="$(run_texttool language-strings --language "$LANGUAGE")"
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

# include_ext_nudge is hardcoded to 1 in every _agents_md_section call below:
# this writes ~/.config/opencode/AGENTS.md specifically, so the host is
# opencode by construction regardless of what --clients was passed for THIS
# project (see the A25 note above this function's call site).
install_opencode_global_agents() {
  local agents_file="$OPENCODE_DIR/AGENTS.md"
  local tmp
  mkdir -p "$OPENCODE_DIR"

  if [ -f "$agents_file" ] && grep -q "$MB_START_MARKER" "$agents_file" 2>/dev/null; then
    tmp="$agents_file.tmp"
    awk -v s="$MB_START_MARKER" -v e="$MB_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_file" > "$tmp"
    {
      cat "$tmp"
      printf '\n'
      _agents_md_section "$SOURCE_SKILL_DIR" 1
    } > "$agents_file"
    rm -f "$tmp"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} OpenCode AGENTS.md (refreshed)"
    return
  fi

  if [ -f "$agents_file" ]; then
    {
      printf '\n'
      _agents_md_section "$SOURCE_SKILL_DIR" 1
    } >> "$agents_file"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} OpenCode AGENTS.md (merged)"
    return
  fi

  _agents_md_section "$SOURCE_SKILL_DIR" 1 > "$agents_file"
  INSTALLED_FILES+=("$agents_file")
  echo -e "  ${GREEN}✓${NC} OpenCode AGENTS.md (created)"
}

codex_agents_section() {
  cat <<EOF
$CODEX_START_MARKER

# Memory Bank — Codex Global Entry Point

Global Memory Bank skill is registered at:
- \`~/.codex/skills/memory-bank/SKILL.md\`

Codex loads this file at startup and injects it into the agent prompt. Treat the section below as always-on Memory Bank guidance.

Bundled resources available to Codex:
- Commands: \`~/.codex/skills/memory-bank/commands/\`
- Agents: \`~/.codex/skills/memory-bank/agents/\`
- Hooks: \`~/.codex/skills/memory-bank/hooks/\`

## Storage modes

Memory Bank supports three storage modes — choose the right one for your workflow:

- **Local** (default): \`/mb init\` or \`/mb init --storage=local\` — bank lives in the repo (\`./.memory-bank/\`), committable, team-shared.
- **Global** (opt-in personal storage): \`/mb init --storage=global --agent=codex\` — bank lives under \`~/.codex/memory-bank/projects/<id>/.memory-bank\`, NOT in the repo, must not be committed.
- **Rules-only**: no \`/mb init\` at all — \`[MEMORY BANK: ABSENT]\` state; \`/mb\` lifecycle commands stay inactive until explicit init; all engineering rules below still apply unconditionally.

Resolve the active bank through \`scripts/_lib.sh::mb_resolve_path\` (precedence: explicit arg → \`MB_PATH\` env → local → registered global → legacy \`.claude-workspace\`).

## Recommended workflow

- Storage resolver determines active bank — do NOT assume \`./.memory-bank/\` is always the bank location.
- If \`./.memory-bank/\` exists OR a global bank is registered, Memory Bank is active: read \`status.md\`, \`checklist.md\`, \`roadmap.md\`, and \`research.md\` at session start.
- Use \`/mb start\` to restore project context and \`/mb done\` to save progress.
- Before implementation, prefer \`/mb plan <feature|fix|refactor|experiment> <topic>\` and follow TDD.
- Detailed rules live at \`~/.codex/skills/memory-bank/rules/RULES.md\`.

## Engineering baseline — TDD, SOLID, Clean Architecture, DRY, KISS, YAGNI

Always-on rules that apply regardless of Memory Bank state (including \`[MEMORY BANK: ABSENT]\`):

- **TDD** — tests first, then code.
- **SOLID** — SRP (≤300 lines/class), ISP (≤5 methods/interface), DIP (constructor injection).
- **Clean Architecture** — Infrastructure → Application → Domain; never the reverse.
- **DRY / KISS / YAGNI** — extract after 3+ duplications; simplest solution; no future-proofing.

See "## Core Memory Bank rules" below for the full baseline.

Codex hooks support is conservative:
- Global Claude-style lifecycle parity is NOT guaranteed.
- Prefer project-level \`.codex/\` adapter files for Codex hook/config integration.
- Treat \`.codex/hooks.json\` as experimental unless documented otherwise.

## Core Memory Bank rules

EOF
  sed 's#~/.claude/RULES.md#~/.codex/skills/memory-bank/rules/RULES.md#g; s#~/.claude/skills/memory-bank#~/.codex/skills/memory-bank#g' "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  cat <<EOF

$CODEX_END_MARKER
EOF
}

install_codex_global_agents() {
  local agents_file="$CODEX_DIR/AGENTS.md"
  local tmp
  mkdir -p "$CODEX_DIR"

  if [ -f "$agents_file" ] && grep -q "$CODEX_START_MARKER" "$agents_file" 2>/dev/null; then
    tmp="$agents_file.tmp"
    awk -v s="$CODEX_START_MARKER" -v e="$CODEX_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_file" > "$tmp"
    {
      cat "$tmp"
      printf '\n'
      codex_agents_section
    } > "$agents_file"
    rm -f "$tmp"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} Codex AGENTS.md (refreshed)"
    return
  fi

  if [ -f "$agents_file" ]; then
    {
      printf '\n'
      codex_agents_section
    } >> "$agents_file"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} Codex AGENTS.md (merged)"
    return
  fi

  codex_agents_section > "$agents_file"
  INSTALLED_FILES+=("$agents_file")
  echo -e "  ${GREEN}✓${NC} Codex AGENTS.md (created)"
}

pi_agents_section() {
  cat <<EOF
$PI_START_MARKER

# Memory Bank — Pi Global Entry Point

Global Memory Bank skill is registered at:
- \`~/.pi/agent/skills/memory-bank/SKILL.md\`

Pi loads this file at startup and injects it into the agent prompt. Treat the section below as always-on Memory Bank guidance.

Bundled resources available to Pi:
- Slash prompt templates: \`~/.pi/agent/prompts/\` (for \`/mb\`, \`/start\`, \`/done\`, \`/plan\`, etc.)
- Skill resources: \`~/.pi/agent/skills/memory-bank/{commands,agents,hooks,scripts,references,rules}/\`

Recommended workflow:
- If \`./.memory-bank/\` exists, Memory Bank is active: read \`status.md\`, \`checklist.md\`, \`roadmap.md\`, and \`research.md\` at session start.
- Use \`/mb start\` to restore project context and \`/mb done\` to save progress.
- Before implementation, prefer \`/mb plan <feature|fix|refactor|experiment> <topic>\` and follow TDD.
- Detailed rules live at \`~/.pi/agent/skills/memory-bank/rules/RULES.md\`.

### Mandatory \`/mb work\` execution gate

When Memory Bank is ACTIVE and the user asks to implement, fix, continue, resume, "do the next step", "go by the plan", or work from an existing plan/spec, **do not implement manually first**. Before editing production code or restoring paused WIP, resolve the Memory Bank work item and workflow:

1. Resolve the effective workflow from \`<bank>/pipeline.yaml\` via \`mb-workflow.sh\` (default may be project-specific, e.g. governed execution).
2. Resolve the target/range via \`mb-work-resolve.sh\` and \`mb-work-plan.sh\`; spec tasks with \`<!-- mb-task:N -->\` are executable source of truth.
3. If a wrapper plan points to a spec, ensure \`linked_spec\` is present; if no executable \`mb-stage\`/\`mb-task\` exists, stop and repair the plan/spec before implementation.
4. Follow the resolved workflow steps exactly (\`implement\`, \`verify\`, \`review\`, \`judge\`, \`fix\`, \`done\`). If \`review\`/\`judge\` are configured, do not claim completion before those gates or an explicit user-approved workflow override.
5. Dispatch agents with the exact \`model\` and \`thinking\` from the JSON line / \`pipeline.yaml\`; never rely on fuzzy model aliases or agent frontmatter defaults.
6. Manual inline work is allowed only for trivial non-plan tasks or when the user explicitly says to skip \`/mb work\`; still apply TDD and verification.

This gate exists to prevent the agent from rationalizing around Memory Bank after compaction, stash restores, or mid-session pivots.

## Core Memory Bank rules

EOF
  sed 's#~/.claude/RULES.md#~/.pi/agent/skills/memory-bank/rules/RULES.md#g; s#~/.claude/skills/memory-bank#~/.pi/agent/skills/memory-bank#g' "$SOURCE_SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  cat <<EOF

$PI_END_MARKER
EOF
}

install_pi_global_agents() {
  local agents_file="$PI_AGENT_DIR/AGENTS.md"
  local tmp section_tmp
  mkdir -p "$PI_AGENT_DIR"
  section_tmp="$(mktemp)"
  pi_agents_section > "$section_tmp"
  localize_path_inplace "$section_tmp" "$PI_START_MARKER"

  if [ -f "$agents_file" ] && grep -q "$PI_START_MARKER" "$agents_file" 2>/dev/null; then
    tmp="$agents_file.tmp"
    awk -v s="$PI_START_MARKER" -v e="$PI_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_file" > "$tmp"
    {
      if grep -q '[^[:space:]]' "$tmp"; then
        awk 'NF { last=NR } { lines[NR]=$0 } END { for (i=1; i<=last; i++) print lines[i] }' "$tmp"
        printf '\n\n'
      fi
      cat "$section_tmp"
    } > "$agents_file"
    rm -f "$tmp" "$section_tmp"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} Pi AGENTS.md (refreshed)"
    return
  fi

  if [ -f "$agents_file" ]; then
    {
      printf '\n'
      cat "$section_tmp"
    } >> "$agents_file"
    rm -f "$section_tmp"
    INSTALLED_FILES+=("$agents_file")
    echo -e "  ${GREEN}✓${NC} Pi AGENTS.md (merged)"
    return
  fi

  mv "$section_tmp" "$agents_file"
  INSTALLED_FILES+=("$agents_file")
  echo -e "  ${GREEN}✓${NC} Pi AGENTS.md (created)"
}

install_pi_settings_skill() {
  local settings_file="$PI_AGENT_DIR/settings.json"
  mkdir -p "$PI_AGENT_DIR"

  SETTINGS_FILE="$settings_file" "$MB_PY" <<'PYEOF'
import json
import os
from pathlib import Path

path = Path(os.environ["SETTINGS_FILE"])
skill = "~/.pi/agent/skills/memory-bank"

if path.exists():
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid Pi settings.json, refusing to overwrite: {exc}")
    if not isinstance(data, dict):
        raise SystemExit("invalid Pi settings.json: root must be an object")
else:
    data = {}

raw_skills = data.get("skills", [])
if raw_skills is None:
    raw_skills = []
if not isinstance(raw_skills, list):
    raise SystemExit("invalid Pi settings.json: skills must be an array")

skills = []
for item in [skill, *raw_skills]:
    if item not in skills:
        skills.append(item)

data["skills"] = skills
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PYEOF

  INSTALLED_FILES+=("$settings_file")
  echo -e "  ${GREEN}✓${NC} Pi settings.json (memory-bank skill merged)"
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
    backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
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
    backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
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
    awk -v s="$CLAUDE_MB_START_MARKER" '
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
      backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
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
install_pi_global_agents
install_pi_settings_skill

# ═══ Step 2: Agents ═══
echo -e "${BLUE}[2/7] Agents${NC}"
agents_installed=0
for f in "$SOURCE_SKILL_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  # Skip partials (frontmatter `partial: true`, e.g. mb-engineering-core): they are
  # prepended by /mb work via the skill alias, not standalone subagents — keep them
  # out of the ~/.claude/agents/ registry so they never show up as dispatchable.
  if head -5 "$f" | grep -qiE '^partial:[[:space:]]*true[[:space:]]*$'; then
    continue
  fi
  install_file "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
  agents_installed=$((agents_installed + 1))
done
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
  [ -n "$have" ] && [ "$have" = "$want" ] && [ "$have_lang" = "$want_lang" ]
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
for c in "${CLIENTS_ARR[@]}"; do
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

# A10/A17: re-flush the manifest now that ADAPTERS_INVOKED/ADAPTERS_FAILED/
# PROJECT_ROOT are known, so uninstall.sh can look up which per-project
# adapters to uninstall and the manifest reflects any adapter failure.
if [ "${#ADAPTERS_INVOKED[@]}" -gt 0 ] || [ "${#ADAPTERS_FAILED[@]}" -gt 0 ]; then
  flush_manifest
fi

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
echo "    pip install tree-sitter tree-sitter-python tree-sitter-go \\"
echo "                tree-sitter-javascript tree-sitter-typescript tree-sitter-rust tree-sitter-java"
echo "  Without these, /mb graph works for Python-only (via stdlib ast)."

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
