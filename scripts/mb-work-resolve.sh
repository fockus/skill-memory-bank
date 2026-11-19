#!/usr/bin/env bash
# mb-work-resolve.sh — resolve <target> arg into a plan/spec path (spec §8.2).
#
# Resolution order:
#   1. Existing path → use as-is
#   2. Substring search in <bank>/plans/*.md (excluding done/)
#   3. Topic name → <bank>/specs/<safe>/tasks.md
#   3b. OpenSpec change (<id> or openspec/changes/<id>) → import/sync into the bank
#      triple, then specs/<topic>/tasks.md; never falls back to a native topic
#      (collision / conflict / unsafe path exit 1; id also matching a plan exit 2)
#   4. Freeform (≥3 words) → exit 3 (driver delegates to LLM-driven match)
#   5. Empty → a plan link inside <bank>/roadmap.md mb-active-plans block, picked by
#      scripts/mb_work_active.py: paused/cancelled/done/blocked plans and plans with an
#      open depends_on are skipped; the only eligible one, else the only in_progress one
#
# Exit codes:
#   0  resolved (single absolute path printed to stdout)
#   1  not found / no (eligible) active plan / parse error / all active plans claimed
#   2  ambiguous (multiple substring matches; list printed to stderr)
#   3  freeform target (driver must resolve via LLM; candidate list to stderr)
#
# Parallel runs (I-094 T2, opt-in MB_WORK_PARALLEL=1): `--skip-claimed` makes
# the empty-target branch (Form 5) skip active-plan links whose source is
# claimed by a live (phase != done) foreign run — see scripts/mb-work-slots.sh
# — returning the first unclaimed one; if every active plan is claimed, exits
# 1 with "all active plans claimed" on stderr. Independently, whenever
# MB_WORK_PARALLEL is on, any successfully resolved path (any form) that is
# claimed by a live foreign run gets an informational stderr claim-note
# ("claimed by run <id>; pass --takeover") — the hard enforcement gate stays
# `mb-work-state.sh init` exit 4; this script never refuses on its own.
# Without `--skip-claimed`/`MB_WORK_PARALLEL`, resolution is byte-identical
# to pre-I-094 behaviour.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

abs() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
  else
    printf '%s\n' "$1"
  fi
}

count_words() {
  echo "$1" | awk '{print NF}'
}

# $1 = bank, $2 = resolved absolute path → prints an informational
# claim-note to stderr when $2 is claimed by a live foreign run under
# MB_WORK_PARALLEL. No-op (and never fails) when parallel mode is off, or
# when the path is unclaimed/self-claimed/claimed by a finished run.
claim_note() {
  local bank="$1" path="$2" claimant
  mbw_parallel_on || return 0
  claimant=$(mbw_claim_conflict "$bank" "$path" "")
  if [ -n "$claimant" ]; then
    echo "[work-resolve] claimed by run $claimant; pass --takeover" >&2
  fi
  return 0
}

list_active_plan_links_portable() {
  local bank
  local rm
  bank="$1"
  rm="$bank/roadmap.md"
  [ -f "$rm" ] || return 1
  python3 - "$rm" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<!--\s*mb-active-plans\s*-->(.*?)<!--\s*/mb-active-plans\s*-->", text, re.S)
if not m:
    sys.exit(0)
for line in m.group(1).splitlines():
    mo = re.search(r"\(([^)]+)\)", line)
    if mo:
        print(mo.group(1))
PY
}

TARGET=""
MB_ARG=""
SKIP_CLAIMED=0
positional=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    --skip-claimed) SKIP_CLAIMED=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *) positional+=("$1"); shift ;;
  esac
done

# Heuristic for backwards compatibility: if exactly one positional and it's a
# directory, treat it as mb_path. Two positionals → first is target, second is
# mb_path.
case "${#positional[@]}" in
  0) ;;
  1)
    pdir="${positional[0]%/}"
    if [ -z "$MB_ARG" ] && [ -d "$pdir" ] \
      && ! { [ "$(basename "$(dirname "$pdir")")" = "changes" ] \
        && [ "$(basename "$(dirname "$(dirname "$pdir")")")" = "openspec" ]; }; then
      MB_ARG="${positional[0]}"
    else
      TARGET="${positional[0]}"
    fi
    ;;
  2)
    TARGET="${positional[0]}"
    if [ -z "$MB_ARG" ]; then
      MB_ARG="${positional[1]}"
    fi
    ;;
  *)
    echo "[work-resolve] too many positional arguments" >&2
    exit 1
    ;;
esac

BANK=$(mb_resolve_path "$MB_ARG")

# ── Form 5: empty target ────────────────────────────────────────────
if [ -z "$TARGET" ]; then
  links=$(list_active_plan_links_portable "$BANK" || true)
  count=0
  if [ -n "$links" ]; then
    count=$(printf '%s\n' "$links" | grep -c .)
  fi
  if [ "$count" -eq 0 ]; then
    echo "[work-resolve] no active plan in $BANK/roadmap.md" >&2
    exit 1
  fi

  # --skip-claimed (only honored under MB_WORK_PARALLEL): drop links whose
  # source is claimed by a live foreign run before picking one.
  if mbw_parallel_on && [ "$SKIP_CLAIMED" = "1" ]; then
    unclaimed=""
    while IFS= read -r rel; do
      [ -z "$rel" ] && continue
      cand_abs=$(abs "$BANK/$rel")
      if [ -z "$(mbw_claim_conflict "$BANK" "$cand_abs" "")" ]; then
        unclaimed="${unclaimed}${rel}
"
      fi
    done < <(printf '%s\n' "$links")
    if [ -z "$unclaimed" ]; then
      echo "[work-resolve] all active plans claimed" >&2
      exit 1
    fi
    links="$unclaimed"
  fi

  # Plan status and depends_on pick among the links (scripts/mb_work_active.py).
  rels=()
  while IFS= read -r rel; do
    [ -n "$rel" ] && rels+=("$rel")
  done < <(printf '%s\n' "$links")
  sel_rc=0
  rel=$(python3 "$SCRIPT_DIR/mb_work_active.py" "$BANK" "${rels[@]}") || sel_rc=$?
  [ "$sel_rc" -eq 0 ] || exit "$sel_rc"

  case "$rel" in
    /*|*..*)
      echo "[work-resolve] active plan link rejected (absolute or traversal): $rel" >&2
      exit 1
      ;;
  esac
  abs_path=$(mb_canonical_under "$BANK" "$BANK/$rel") || {
    echo "[work-resolve] active plan link escapes bank: $rel" >&2
    exit 1
  }
  if ! mb_is_allowed_plan_path "$BANK" "$abs_path"; then
    echo "[work-resolve] active plan link is not a plan or spec tasks file: $abs_path" >&2
    exit 1
  fi
  if [ ! -f "$abs_path" ]; then
    echo "[work-resolve] active plan link points at missing file: $abs_path" >&2
    exit 1
  fi
  claim_note "$BANK" "$abs_path"
  printf '%s\n' "$abs_path"
  exit 0
fi

# ── Form 2c: OpenSpec change (dir or bare id) → sync/import → bank triple ──
# The merge logic lives in mb-openspec.sh; a conflict or error stops here,
# before any work starts. An explicit OpenSpec target never falls back to a
# native topic: the python guard prints "<change_dir>\t<topic>\t<import|sync>"
# (exit 0), exits 1 when TARGET is not an OpenSpec change, 2 with a message
# when it is one but unsafe or colliding.
openspec_plan() {
  python3 - "$1" "$BANK" "$PWD" "$SCRIPT_DIR" <<'PY'
import os, sys
target, bank, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, sys.argv[4])
from pathlib import Path
from mb_openspec_bank import parse_frontmatter, resolve_stored_source, slugify
t = target.rstrip("/")
if not t:
    sys.exit(1)
real = os.path.realpath
projects = []
for p in (cwd, os.path.dirname(os.path.abspath(bank))):
    if real(p) not in projects:
        projects.append(real(p))

def fail(msg):
    print(f"[work-resolve] {msg}", file=sys.stderr)
    sys.exit(2)

if "/" in t:
    cands = [os.path.abspath(t)]
    if not os.path.isdir(cands[0]) or "openspec/changes" not in cands[0]:
        sys.exit(1)
else:
    if t in (".", "..") or t.startswith("."):
        sys.exit(1)
    cands = [os.path.join(p, "openspec", "changes", t) for p in projects]
cand = next((c for c in cands if os.path.lexists(c)), None)
if cand is None:
    sys.exit(1)
changes = os.path.dirname(cand)
osdir = os.path.dirname(changes)
project = os.path.dirname(osdir)
if (os.path.basename(changes) != "changes" or os.path.basename(osdir) != "openspec"
        or real(project) not in projects):
    fail(f"OpenSpec change must be <project>/openspec/changes/<id> (one id segment, not archived): {target}")
if os.path.basename(cand) == "archive":
    fail(f"archived OpenSpec changes are not workable: {target}")
for q in (cand, changes, osdir):
    if os.path.islink(q):
        fail(f"OpenSpec change path contains a symlink: {q}")
if not os.path.isdir(cand):
    sys.exit(1)
cand = real(cand)
topic = slugify(os.path.basename(cand))
req = os.path.join(bank, "specs", topic, "requirements.md")
if not os.path.isdir(os.path.join(bank, "specs", topic)):
    action = "import"
else:
    fm = parse_frontmatter(open(req, encoding="utf-8").read()) if os.path.isfile(req) else {}
    src = fm.get("openspec_source")
    if not src:
        fail(f"specs/{topic} is a native topic, not imported from OpenSpec; "
             f"rename or move it, or import the change under a distinct topic: "
             f"mb-openspec.sh import {cand} --as <topic>")
    if real(resolve_stored_source(src, Path(bank))) != cand:
        fail(f"specs/{topic} is linked to a different change ({src}); "
             f"import this one under a distinct topic: mb-openspec.sh import {cand} --as <topic>")
    action = "sync"
print(f"{cand}\t{topic}\t{action}")
PY
}

# ── Form 1: existing path ───────────────────────────────────────────
if [ -f "$TARGET" ]; then
  target_abs=$(abs "$TARGET")
  claim_note "$BANK" "$target_abs"
  printf '%s\n' "$target_abs"
  exit 0
fi

# ── Form 2: substring search in plans/ (excluding done/) ────────────
plans_dir="$BANK/plans"
if [ -d "$plans_dir" ]; then
  # Match the file name only: a parent directory (e.g. TMPDIR) may contain the target.
  matches=$(find "$plans_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | T="$TARGET" awk -F/ 'index($NF, ENVIRON["T"])' || true)
  count=0
  if [ -n "$matches" ]; then
    count=$(printf '%s\n' "$matches" | grep -c .)
  fi
  case "$TARGET" in
    */*) ;;
    *)
      if [ "$count" -ge 1 ] && openspec_plan "$TARGET" >/dev/null 2>&1; then
        echo "[work-resolve] ambiguous: openspec change '$TARGET' and plan $(printf '%s\n' "$matches" | head -1)" >&2
        echo "  use openspec/changes/$TARGET for the change, or the full plan file name for the plan" >&2
        exit 2
      fi
      ;;
  esac
  if [ "$count" -eq 1 ]; then
    match_abs=$(abs "$matches")
    claim_note "$BANK" "$match_abs"
    printf '%s\n' "$match_abs"
    exit 0
  elif [ "$count" -gt 1 ]; then
    echo "[work-resolve] ambiguous substring '$TARGET' matches:" >&2
    printf '%s\n' "$matches" >&2
    exit 2
  fi
fi

# ── Form 2b: bank-relative plans/* or specs/* (from any CWD) ───────
case "$TARGET" in
  plans/*|specs/*)
    case "$TARGET" in
      /*|*..*) ;;
      *)
        abs_path=$(mb_canonical_under "$BANK" "$BANK/$TARGET") || {
          echo "[work-resolve] bank-relative target escapes bank: $TARGET" >&2
          exit 1
        }
        if ! mb_is_allowed_plan_path "$BANK" "$abs_path"; then
          echo "[work-resolve] bank-relative target is not a plan or spec tasks file: $TARGET" >&2
          exit 1
        fi
        if [ -f "$abs_path" ]; then
          printf '%s\n' "$abs_path"
          exit 0
        fi
        ;;
    esac
    ;;
esac

# ── Form 2c (run): OpenSpec target
set +e
plan_out=$(openspec_plan "$TARGET")
plan_rc=$?
set -e
if [ "$plan_rc" -eq 2 ]; then
  exit 1
elif [ "$plan_rc" -eq 0 ]; then
  IFS=$'\t' read -r change_dir topic action <<<"$plan_out"
  if [ "$action" = "sync" ]; then
    sync_cmd=(sync "$topic" --mb "$BANK")
  else
    sync_cmd=(import "$change_dir" --as "$topic" --mb "$BANK")
  fi
  if ! sync_out=$(bash "$SCRIPT_DIR/mb-openspec.sh" "${sync_cmd[@]}" 2>&1); then
    printf '%s\n' "$sync_out" >&2
    echo "[work-resolve] OpenSpec change '$topic' did not sync (conflict or error); resolve it first: mb-openspec.sh sync $topic --take openspec|bank" >&2
    exit 1
  fi
  printf '%s\n' "$sync_out" >&2
  tasks_abs=$(abs "$BANK/specs/$topic/tasks.md")
  claim_note "$BANK" "$tasks_abs"
  printf '%s\n' "$tasks_abs"
  exit 0
fi

# ── Form 3: topic → specs/<topic>/tasks.md ─────────────────────────
safe=$(mb_sanitize_topic "$TARGET")
if [ -n "$safe" ]; then
  tasks="$BANK/specs/$safe/tasks.md"
  if [ -f "$tasks" ]; then
    tasks_abs=$(abs "$tasks")
    claim_note "$BANK" "$tasks_abs"
    printf '%s\n' "$tasks_abs"
    exit 0
  fi
fi

# ── Form 4: freeform (≥3 words) ─────────────────────────────────────
words=$(count_words "$TARGET")
if [ "$words" -ge 3 ]; then
  echo "[work-resolve] freeform target ($words words); driver must match against active plans" >&2
  echo "candidates:" >&2
  if [ -d "$plans_dir" ]; then
    find "$plans_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sed 's/^/  /' >&2 || true
  fi
  # Also include specs/*/tasks.md files that contain mb-task or mb-stage markers.
  if [ -d "$BANK/specs" ]; then
    while IFS= read -r spec_tasks; do
      if grep -qE '<!--[[:space:]]*mb-(task|stage):[0-9]+[[:space:]]*-->' "$spec_tasks" 2>/dev/null; then
        printf '  %s\n' "$spec_tasks" >&2
      fi
    done < <(find "$BANK/specs" -mindepth 2 -maxdepth 2 -name 'tasks.md' 2>/dev/null)
  fi
  exit 3
fi

echo "[work-resolve] target '$TARGET' not found (no plan, spec topic or OpenSpec change under openspec/changes/)" >&2
exit 1
