#!/usr/bin/env bash
# mb-consolidate.sh — /mb consolidate: fold OLD sessions + their contiguous
# auto-capture progress STUBS into durable notes/ patterns + an archive, with
# ZERO LLM calls. Dry-run is the DEFAULT and writes NOTHING; --apply performs the
# (verbatim) moves and note writes.
#
# Usage: mb-consolidate.sh [mb_path] [--apply] [--days N]
#   mb_path   optional explicit Memory Bank path (default: resolver)
#   --apply   perform the writes/moves (default is a dry-run that writes nothing)
#   --days N   age window in days (default: MB_CONSOLIDATE_DAYS or 30). Sessions
#             whose file mtime is OLDER than N days fall inside the window.
#   -h|--help print this header.
#
# Contract (spec tier1-graph-memory — REQ-012, REQ-013, REQ-014, Scenario 11):
#   - Window: sessions older than the window (file mtime age > N days) + the
#     contiguous auto-capture STUB entries in progress.md.
#   - Pass 1 (memory_bank_skill/consolidate.py, deterministic): cluster windowed
#     sessions by shared files-touched + lexical overlap; a fact recurring in >=2
#     sessions becomes a note candidate in the notes/ 5-15 line pattern format.
#   - Dry-run (DEFAULT) prints the plan and writes NOTHING — the bank is provably
#     byte-identical afterward.
#   - --apply: (a) writes note candidate(s) to notes/; (b) moves windowed session
#     files VERBATIM into session/archive/ (byte-for-byte; via `mv`); (c) moves the
#     contiguous progress STUB entries VERBATIM into progress-archive.md and
#     appends one pointer line per batch to progress.md; (d) rebuilds _recent.md.
#     REAL (non-stub) progress entries are immutable and NEVER move (v1).
#   - Fail-open: <2 windowed sessions, or nothing to consolidate → empty output,
#     exit 0, no writes.
#
# No LLM calls in either mode. This shell is a THIN dispatcher: all deterministic
# decision logic (windowing/clustering/note-body building + the byte-preserving
# progress.md splitter) lives in memory_bank_skill/consolidate.py as pure functions.
# The shell owns ONLY arg parsing, the verbatim `mv`/`cat >>`/`mv` filesystem moves,
# and the _recent.md rebuild.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

RECENT_REBUILD="$(dirname "$0")/mb-session-recent-rebuild.sh"
# Repo root (scripts/..) so `python3 -m memory_bank_skill.consolidate` resolves.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY_MODULE="memory_bank_skill.consolidate"

# ── Parse args ───────────────────────────────────────────────────────────────
MB_ARG=""
APPLY=0
DAYS="${MB_CONSOLIDATE_DAYS:-30}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --days)
      DAYS="${2:-}"
      [ -n "$DAYS" ] || { echo "mb-consolidate: --days needs a value" >&2; exit 64; }
      shift 2 ;;
    --days=*) DAYS="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,21p' "$0"
      exit 0 ;;
    -*) echo "mb-consolidate: unknown option '$1'" >&2; exit 64 ;;
    *)
      if [ -z "$MB_ARG" ]; then MB_ARG="$1"; else
        echo "mb-consolidate: unexpected argument '$1'" >&2; exit 64
      fi
      shift ;;
  esac
done

case "$DAYS" in
  ''|*[!0-9]*) echo "mb-consolidate: --days must be a non-negative integer" >&2; exit 64 ;;
esac

MB_PATH="$(mb_resolve_path "$MB_ARG")"
# Make the bank path absolute NOW — against the caller's CWD — before the Python
# passes below `cd "$REPO_ROOT"` (needed for `python3 -m` module resolution). A
# relative resolver result (e.g. the local `.memory-bank` fallback or a relative
# arg) would otherwise be re-resolved against the repo root and silently plan the
# wrong directory.
MB_PATH="$(mb_normalize_path "$MB_PATH")"

# ── Pass 1: deterministic plan (Python module, stdlib only) ──────────────────
# Emits one tab-separated directive per line; nothing else goes to stdout. Kinds:
#   SESSION\t<abs session file path>\t<sid8>         (windowed → to archive verbatim)
#   NOTE\t<abs note file path>\t<base64 utf-8 body>  (note candidate to write)
#   POINTER\t<text>                                  (pointer line for progress.md)
#   CLUSTER\t<human-readable summary>                (dry-run plan line; never a write)
# Fewer than two windowed sessions / nothing clusters → no lines → bank untouched.
PLAN="$(
  cd "$REPO_ROOT" && \
  MB_PATH="$MB_PATH" MB_DAYS="$DAYS" python3 -m "$PY_MODULE" plan
)"

# ── Nothing to consolidate → empty output, exit 0, no writes ─────────────────
if [ -z "$PLAN" ]; then
  exit 0
fi

# ── Dry-run (DEFAULT): print the plan, write NOTHING ─────────────────────────
if [ "$APPLY" -eq 0 ]; then
  echo "Consolidation plan (dry-run — nothing written; pass --apply to perform it):"
  while IFS=$'\t' read -r kind a _b; do
    [ -n "$kind" ] || continue
    case "$kind" in
      CLUSTER) printf '  - cluster → note %s\n' "$a" ;;
      NOTE)    printf '      would write note: %s\n' "$a" ;;
      SESSION) printf '      would archive session: %s\n' "$(basename "$a")" ;;
      POINTER) printf '  - %s\n' "$a" ;;
    esac
  done <<< "$PLAN"
  exit 0
fi

# ── --apply: perform the writes/moves ────────────────────────────────────────
ARCHIVE_DIR="$MB_PATH/session/archive"
PROGRESS="$MB_PATH/progress.md"
PROGRESS_ARCHIVE="$MB_PATH/progress-archive.md"
NOTES_DIR="$MB_PATH/notes"
mkdir -p "$ARCHIVE_DIR" "$NOTES_DIR"

POINTER_TEXT=""
ARCHIVED_SIDS=""   # newline-separated sid8 set of the sessions consolidated this run
while IFS=$'\t' read -r kind a b; do
  [ -n "$kind" ] || continue
  case "$kind" in
    NOTE)
      # Write the note candidate (collision-safe). Body is base64 to survive the
      # tab-separated transport without mangling newlines.
      dest="$(mb_collision_safe_filename "$a")"
      printf '%s' "$b" | base64 --decode > "$dest"
      ;;
    SESSION)
      # VERBATIM move (byte-for-byte) via `mv` — never read/rewrite the content.
      if [ -f "$a" ]; then
        target="$ARCHIVE_DIR/$(basename "$a")"
        mv "$a" "$target"
      fi
      # Record the sid8 so the stub move is scoped to exactly these sessions (#1).
      [ -n "$b" ] && ARCHIVED_SIDS="${ARCHIVED_SIDS}${b}"$'\n'
      ;;
    POINTER)
      POINTER_TEXT="$a"
      ;;
    CLUSTER) : ;;  # plan-only, no side effect on --apply
  esac
done <<< "$PLAN"

# ── Move the auto-capture STUB entries out of progress.md BYTE-VERBATIM ───────
# The splitter (consolidate.py `split`) is a byte-preserving Python pass: it slices
# the original file on top-level `## ` boundaries (fence-aware) and re-emits the
# original byte ranges UNCHANGED — kept real entries stay byte-identical, the
# archived slice equals the original bytes. The shell only consumes the KEEP/STUBS
# files it produced via `cat >>` (append) + an atomic `mv KEEP→PROGRESS`.
if [ -f "$PROGRESS" ]; then
  STUBS_FILE="$PROGRESS.stubs.$$"
  KEEP_FILE="$PROGRESS.keep.$$"
  MOVED_FLAG="$PROGRESS.moved.$$"

  ( cd "$REPO_ROOT" && \
    MB_PROGRESS="$PROGRESS" MB_KEEP="$KEEP_FILE" MB_STUBS="$STUBS_FILE" \
    MB_MOVEDFLAG="$MOVED_FLAG" MB_ARCHIVED_SIDS="$ARCHIVED_SIDS" \
    python3 -m "$PY_MODULE" split )

  MOVED="$(cat "$MOVED_FLAG" 2>/dev/null || echo 0)"
  rm -f "$MOVED_FLAG"

  if [ "$MOVED" = "1" ] && [ -s "$STUBS_FILE" ]; then
    # Append the moved stub blocks VERBATIM to the archive (append-only).
    if [ ! -f "$PROGRESS_ARCHIVE" ]; then
      printf '# Progress Archive\n\n> Auto-capture stubs folded out of progress.md by /mb consolidate.\n\n' > "$PROGRESS_ARCHIVE"
    fi
    cat "$STUBS_FILE" >> "$PROGRESS_ARCHIVE"

    # Replace progress.md with the kept (stub-free) content, then append one
    # pointer line per run so the trail back to the archive is preserved.
    mv "$KEEP_FILE" "$PROGRESS"
    [ -n "$POINTER_TEXT" ] || POINTER_TEXT="Older auto-capture stubs archived → progress-archive.md (see /mb consolidate)"
    printf '\n## %s (consolidation pointer)\n\n- %s\n' "$(date +%Y-%m-%d)" "$POINTER_TEXT" >> "$PROGRESS"
  else
    # No stub moved — leave progress.md byte-identical.
    rm -f "$KEEP_FILE"
  fi
  rm -f "$STUBS_FILE"
fi

# ── Rebuild _recent.md so it carries no dangling refs to archived sessions ───
if [ -x "$RECENT_REBUILD" ]; then
  "$RECENT_REBUILD" "$MB_PATH" >/dev/null 2>&1 || true
else
  bash "$RECENT_REBUILD" "$MB_PATH" >/dev/null 2>&1 || true
fi

echo "mb-consolidate: applied — notes written, sessions archived, _recent.md rebuilt."
exit 0
