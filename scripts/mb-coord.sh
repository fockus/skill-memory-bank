#!/usr/bin/env bash
# mb-coord.sh — read and write the cross-session coordination board without
# loading all of it into context.
#
# Usage:
#   mb-coord.sh active [--tail N] [--mb <path>]
#   mb-coord.sh append --type <FREEZE|LIFT|HANDOVER|ACK|STATUS> --title <t>
#                      [--body-file <f>] [--mb <path>]
#
# Why: `<bank>/COORDINATION.md` is append-only and grows without bound (200 KB /
# 2000 lines in this repo). Every agent was told to "read the board" before
# stages, commits and shared-file edits — i.e. to pay for the whole history to
# learn the three facts it needs. `active` prints those three facts:
#
#   1. active FREEZEs      — a frozen file must not be touched until it is lifted
#   2. HANDOVERs with no ACK — someone is waiting on a receipt
#   3. the last N entries (default 3) verbatim — what just happened
#   + one `board:` line with the totals and the path, for when you must dig.
#
# Entry grammar (canonical, what `append` writes):
#
#   ## <TYPE> · YYYY-MM-DD · <scope/title>
#
# TYPE ∈ FREEZE | LIFT | HANDOVER | ACK | STATUS. `scope` is the text after the
# LAST `·`; a LIFT cancels an EARLIER freeze with the same scope, an ACK cancels
# an earlier HANDOVER with the same scope.
#
# Untagged headings (the entire legacy corpus) are STATUS — EXCEPT an entry
# whose body declares a freeze in a **bolded** marker line (`FREEZE REQUEST` or
# `⚠️ FREEZE`), which is reported as a `[legacy]` freeze. Rationale: the one
# freeze in force on this board predates the tag grammar, and a freeze the
# reader never sees invites a `git rebase` that eats another session's work,
# while a freeze reported once too often costs one line. Bold is required
# because prose *referring* to a freeze ("despite the FREEZE REQUEST above")
# is not a declaration. Legacy freezes are never auto-lifted: prose lifts are
# not parsed, so append a tagged `## LIFT · … · <scope>` to clear one.
#
# Exit codes:
#   0  printed (including the fail-open "no board" case)
#   1  usage error, or an `append` that could not be published (lock/write)
#
# Env overrides:
#   MB_COORD_LOCK_TIMEOUT   seconds to wait for the append lock (default 10)
#   MB_COORD_LOCK_TTL       seconds before a held lock is stale (default 120)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

LOCK_TIMEOUT="${MB_COORD_LOCK_TIMEOUT:-10}"
LOCK_TTL="${MB_COORD_LOCK_TTL:-120}"

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2
}

die() {
  printf '[coord] %s\n' "$1" >&2
  exit 1
}

# Portable mtime (epoch seconds); empty if missing/unknown. GNU-first +
# validate — see scripts/mb-work-progress-append.sh::_mtime.
_mtime() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || true)"
  case "$m" in '' | *[!0-9]*) : ;; *)
    printf '%s\n' "$m"
    return 0
    ;;
  esac
  m="$(stat -f %m "$1" 2>/dev/null || true)"
  case "$m" in '' | *[!0-9]*) return 0 ;; *)
    printf '%s\n' "$m"
    return 0
    ;;
  esac
}

# Atomic mkdir lock with owner token (no flock on macOS), mirroring
# scripts/mb-work-progress-append.sh. Breaks a lock older than $ttl.
_lock_acquire() {
  local lock="$1" timeout="$2" ttl="$3" waited=0 age now token
  token="$$-${RANDOM:-0}"
  while true; do
    if mkdir "$lock" 2>/dev/null; then
      printf '%s' "$token" >"$lock/owner" 2>/dev/null || true
      printf '%s' "$token"
      return 0
    fi
    age="$(_mtime "$lock")"
    if [ -n "$age" ]; then
      now="$(date +%s)"
      if [ "$((now - age))" -gt "$ttl" ]; then
        rm -rf "$lock" 2>/dev/null || true
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

_lock_release() {
  local lock="$1" token="${2:-}" current
  [ -z "$token" ] && return 0
  current="$(cat "$lock/owner" 2>/dev/null || true)"
  [ "$current" = "$token" ] && rm -rf "$lock" 2>/dev/null || true
  return 0
}

cmd_active() {
  local tail_n=3 mb_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tail)
        tail_n="${2:-}"
        shift 2
        ;;
      --tail=*)
        tail_n="${1#--tail=}"
        shift
        ;;
      --mb)
        mb_arg="${2:-}"
        shift 2
        ;;
      --mb=*)
        mb_arg="${1#--mb=}"
        shift
        ;;
      *) die "unknown arg for active: $1" ;;
    esac
  done
  case "$tail_n" in '' | *[!0-9]*) die "--tail expects a non-negative integer, got: '$tail_n'" ;; esac

  local bank board
  bank="$(mb_resolve_path "$mb_arg")"
  board="$bank/COORDINATION.md"
  if [ ! -f "$board" ]; then
    # Fail-open: no board = no parallel session = no protocol overhead.
    printf 'no board: %s\n' "$board"
    return 0
  fi

  MB_COORD_BOARD="$board" MB_COORD_TAIL="$tail_n" python3 - <<'PY'
import os
import re
import sys

board = os.environ["MB_COORD_BOARD"]
tail_n = int(os.environ["MB_COORD_TAIL"])

raw = open(board, "rb").read()
text = raw.decode("utf-8", "replace")
lines = text.splitlines()

TAG_RE = re.compile(r"^##\s+(FREEZE|LIFT|HANDOVER|ACK|STATUS)\s+·\s*(.*)$")
FREEZE_MARKER_RE = re.compile(r"FREEZE REQUEST|⚠️\s*FREEZE")

entries = []
for idx, line in enumerate(lines):
    if line.startswith("## "):
        entries.append({"heading": line, "start": idx, "body": []})
    elif entries:
        entries[-1]["body"].append(line)


def scope_of(rest: str) -> str:
    return rest.rsplit("·", 1)[-1].strip().casefold()


def clip(s: str, n: int = 120) -> str:
    s = s.strip()
    return s if len(s) <= n else s[: n - 1] + "…"


for e in entries:
    m = TAG_RE.match(e["heading"])
    if m:
        e["type"], e["scope"] = m.group(1), scope_of(m.group(2))
        e["legacy_freeze"] = None
    else:
        e["type"], e["scope"] = "STATUS", ""
        # A declaration is bolded; a mention of someone else's freeze is not.
        e["legacy_freeze"] = next(
            (ln for ln in e["body"] if "**" in ln and FREEZE_MARKER_RE.search(ln)), None
        )


def cancelled(entry, canceller_type):
    """True when a later entry of `canceller_type` carries the same scope."""
    return any(
        o["type"] == canceller_type and o["scope"] == entry["scope"] and o["start"] > entry["start"]
        for o in entries
    )


freezes = []
for e in entries:
    if e["legacy_freeze"] is not None:
        freezes.append(("legacy", e))
    elif e["type"] == "FREEZE" and not cancelled(e, "LIFT"):
        freezes.append(("tagged", e))

handovers = [e for e in entries if e["type"] == "HANDOVER" and not cancelled(e, "ACK")]

out = []
out.append("FREEZE (active): %d" % len(freezes))
for kind, e in freezes:
    prefix = "[legacy] " if kind == "legacy" else ""
    out.append("- %s%s" % (prefix, clip(e["heading"].lstrip("# "))))
    if kind == "legacy":
        out.append("  %s" % clip(e["legacy_freeze"], 160))

out.append("")
out.append("HANDOVER (no ACK): %d" % len(handovers))
for e in handovers:
    out.append("- %s" % clip(e["heading"].lstrip("# ")))

if tail_n > 0 and entries:
    shown = entries[-tail_n:]
    out.append("")
    out.append("Last %d entries:" % len(shown))
    out.append("")
    out.extend(lines[shown[0]["start"]:])

out.append("")
out.append(
    "board: %d entries, %d bytes — full file: %s" % (len(entries), len(raw), board)
)
sys.stdout.write("\n".join(out).rstrip("\n") + "\n")
PY
}

cmd_append() {
  local type="" title="" body_file="" mb_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type)
        type="${2:-}"
        shift 2
        ;;
      --type=*)
        type="${1#--type=}"
        shift
        ;;
      --title)
        title="${2:-}"
        shift 2
        ;;
      --title=*)
        title="${1#--title=}"
        shift
        ;;
      --body-file)
        body_file="${2:-}"
        shift 2
        ;;
      --body-file=*)
        body_file="${1#--body-file=}"
        shift
        ;;
      --mb)
        mb_arg="${2:-}"
        shift 2
        ;;
      --mb=*)
        mb_arg="${1#--mb=}"
        shift
        ;;
      *) die "unknown arg for append: $1" ;;
    esac
  done

  case "$type" in
    FREEZE | LIFT | HANDOVER | ACK | STATUS) : ;;
    *) die "--type must be one of FREEZE|LIFT|HANDOVER|ACK|STATUS, got: '$type'" ;;
  esac
  [ -n "$title" ] || die "--title is required and must be non-empty"

  local body=""
  if [ -n "$body_file" ]; then
    [ -f "$body_file" ] && [ -r "$body_file" ] || die "--body-file '$body_file' is missing or unreadable"
    body="$(cat "$body_file")"
  fi

  local bank board lock
  bank="$(mb_resolve_path "$mb_arg")"
  mkdir -p "$bank" || die "cannot create bank dir '$bank'"
  board="$bank/COORDINATION.md"
  lock="$bank/.coord-append.lock"

  local token=""
  if ! token="$(_lock_acquire "$lock" "$LOCK_TIMEOUT" "$LOCK_TTL")"; then
    # Loud, unlike the progress-append helper: a dropped FREEZE announcement is
    # exactly the failure this board exists to prevent. The caller must know.
    die "could not acquire append lock '$lock' within ${LOCK_TIMEOUT}s — nothing written"
  fi
  # shellcheck disable=SC2064
  trap "_lock_release '$lock' '$token'" EXIT

  local tmp=""
  tmp="$(mktemp "$bank/.coord.append.XXXXXX")" || die "mktemp failed in '$bank' — nothing written"

  if [ -f "$board" ]; then
    cp -p "$board" "$tmp" || {
      rm -f "$tmp"
      die "could not read existing board — nothing written"
    }
  else
    # shellcheck disable=SC2016  # backticks are literal markdown code-spans in the board header
    {
      printf '# COORDINATION (append-only)\n\n'
      printf 'Shared working tree — multiple sessions. Read it with `scripts/mb-coord.sh active`;\n'
      printf 'open the full file only when investigating history.\n'
      printf 'Scoped `git add <paths>` only, never `git add -A`. Do not revert another session'"'"'s WIP.\n'
    } >"$tmp"
  fi

  {
    printf '\n## %s · %s · %s\n' "$type" "$(date +%Y-%m-%d)" "$title"
    # `[ -n "$body" ] && printf` as the LAST command of the group makes the
    # group's status 1 on an empty body — a headline-only entry would then be
    # reported as a failed write. Keep the `if`.
    if [ -n "$body" ]; then
      printf '%s\n' "$body"
    fi
  } >>"$tmp" || {
    rm -f "$tmp"
    die "write failed — nothing published"
  }

  mv -f "$tmp" "$board" || {
    rm -f "$tmp"
    die "mv failed — nothing published"
  }
}

main() {
  [ $# -gt 0 ] || {
    usage
    exit 1
  }
  local sub="$1"
  shift
  case "$sub" in
    active) cmd_active "$@" ;;
    append) cmd_append "$@" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf '[coord] unknown subcommand: %s\n' "$sub" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
