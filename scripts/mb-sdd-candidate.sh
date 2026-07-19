#!/usr/bin/env bash
# mb-sdd-candidate.sh — deterministic candidate lifecycle for the /mb sdd
# generation pipeline (svp-sdd-core design C4a, REQ-010/053; closes R3-002/R3-003).
#
# The candidate seam separates a GENERATED tasks.md from an ACCEPTED one: the
# pipeline writes `<bank>/tmp/sdd/<topic>/tasks.candidate.md`, sizes it (C3), and
# only this helper moves it into `<bank>/specs/<topic>/tasks.md`. Mechanical
# transfer/deletion is code, not prompt judgement — an atomic same-filesystem
# rename with a byte-identical-final invariant on every refusal.
#
# Usage:
#   mb-sdd-candidate.sh publish --topic <topic> --candidate <path> \
#        --estimate-file <path> [--override user] [--force] [--mb <bank>]
#   mb-sdd-candidate.sh discard --topic <topic> --candidate <path> [--mb <bank>]
#
# --candidate MUST be the canonical `<bank>/tmp/sdd/<topic>/tasks.candidate.md`
# (else usage, exit 2). --estimate-file is the stdout of
# `mb-estimate-check.sh --tasks-file`, parsed as key=value (spec=, task_over=,
# stage_over=).
#
# publish rule (R3-003 — override narrowed to the spec rubicon):
#   - task_over != none OR stage_over != none → ALWAYS blocked
#     (reason=task_overflow | stage_overflow), candidate deleted; --override is
#     ignored — the D-13 hard caps (task ≤120000, stage ≤400000) are unbreakable.
#   - else spec ∈ {ok, near} → publish; spec=over → publish ONLY with
#     `--override user`, otherwise blocked (reason=spec_overflow), candidate deleted.
#   - an EXISTING <bank>/specs/<topic>/tasks.md is refused (reason=spec_exists)
#     unless --force is passed — the gate commands/sdd.md documents (review [14]).
#   - publish = same-filesystem rename(2) candidate → <bank>/specs/<topic>/tasks.md.
#
# stdout : exactly one line `candidate=published|discarded|blocked reason=<code>`
#          (reason=none for published/discarded).
# exit   : 0 published/discarded · 1 domain block (spec/task/stage overflow)
#          · 2 usage / malformed verdict / non-canonical path / missing input.
#
# The triple is published as DRAFT — this helper never changes requirements.md
# status; acceptance is the orchestrator's C7 state-machine decision.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage_error() { printf 'error=usage\n' >&2; exit 2; }

[ "$#" -ge 1 ] || usage_error
ACTION="$1"; shift

TOPIC=""
CANDIDATE=""
ESTIMATE_FILE=""
OVERRIDE=""
FORCE=0
MB_BANK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --topic)         [ "$#" -ge 2 ] || usage_error; TOPIC="$2"; shift ;;
    --candidate)     [ "$#" -ge 2 ] || usage_error; CANDIDATE="$2"; shift ;;
    --estimate-file) [ "$#" -ge 2 ] || usage_error; ESTIMATE_FILE="$2"; shift ;;
    --override)      [ "$#" -ge 2 ] || usage_error; OVERRIDE="$2"; shift ;;
    --force)         FORCE=1 ;;
    --mb)            [ "$#" -ge 2 ] || usage_error; MB_BANK="$2"; shift ;;
    *) usage_error ;;
  esac
  shift
done

[ -n "$TOPIC" ] || usage_error
[ -n "$CANDIDATE" ] || usage_error

# Topic must be a safe slug — no path traversal, no separators (blocker #3):
# only [A-Za-z0-9._-], must start alphanumeric, and no `..` anywhere.
case "$TOPIC" in
  *[!A-Za-z0-9._-]*|*..*) usage_error ;;
esac
case "$TOPIC" in
  [A-Za-z0-9]*) : ;;
  *) usage_error ;;
esac

# The bank is NEVER inferred from the candidate path (review [6]): without --mb
# the ACTIVE bank is resolved through mb_resolve_path, exactly like every other
# helper, so naming `/tmp/foreign/tmp/sdd/<topic>/tasks.candidate.md` can no
# longer nominate `/tmp/foreign` as its own bank and publish into it.
RESOLVED_BANK="$(mb_resolve_path "$MB_BANK")"

# Canonicalize + contain the candidate to exactly <bank>/tmp/sdd/<topic>/
# tasks.candidate.md, on the SAME filesystem as the accepted target (blocker
# #3). realpath resolves `..`/symlinks so a candidate from another bank, or an
# escaped path, cannot masquerade as canonical.
CANON="$(
  MB_BANK="$RESOLVED_BANK" TOPIC="$TOPIC" CANDIDATE="$CANDIDATE" python3 - <<'PY'
import os, sys
topic = os.environ["TOPIC"]
cand = os.path.realpath(os.environ["CANDIDATE"])
suffix = os.path.join("tmp", "sdd", topic, "tasks.candidate.md")
bank = os.path.realpath(os.environ["MB_BANK"])
if not os.path.isdir(bank):
    print("ERR bank_not_dir"); sys.exit(0)
expected = os.path.join(bank, suffix)
if cand != expected:
    print("ERR noncanonical"); sys.exit(0)
if os.path.commonpath([cand, bank]) != bank:
    print("ERR escaped_bank"); sys.exit(0)

# Containment is checked on the FINAL WRITE PATH, not on its parent (review
# [7]): a symlinked `<bank>/specs/<topic>` (or a symlinked `tasks.md` inside
# it) used to resolve elsewhere while the rename still followed the unresolved
# path. Both the directory and the file must canonically stay under the bank,
# and neither may itself be a symlink.
final_dir = os.path.join(bank, "specs", topic)
final = os.path.join(final_dir, "tasks.md")
if os.path.islink(final_dir) or os.path.islink(final):
    print("ERR symlink_target"); sys.exit(0)
real_final_dir = os.path.realpath(final_dir)
real_final = os.path.join(real_final_dir, "tasks.md")
expected_dir = os.path.join(bank, "specs", topic)
if real_final_dir != expected_dir or os.path.realpath(final) != real_final:
    print("ERR escaped_final"); sys.exit(0)
if os.path.commonpath([real_final, bank]) != bank:
    print("ERR escaped_final"); sys.exit(0)

cand_dir = os.path.dirname(cand)
try:
    ref = real_final_dir if os.path.isdir(real_final_dir) else bank
    if os.path.isdir(cand_dir) and os.stat(cand_dir).st_dev != os.stat(ref).st_dev:
        print("ERR cross_fs"); sys.exit(0)
except OSError:
    print("ERR stat"); sys.exit(0)
print("OK\t%s\t%s\t%s" % (cand, real_final_dir, real_final))
PY
)"
case "$CANON" in
  OK*) : ;;
  *) usage_error ;;
esac
CANDIDATE="$(printf '%s' "$CANON" | cut -f2)"
FINAL_DIR="$(printf '%s' "$CANON" | cut -f3)"
FINAL="$(printf '%s' "$CANON" | cut -f4)"

# ── discard ──────────────────────────────────────────────────────────────────
if [ "$ACTION" = "discard" ]; then
  [ -f "$CANDIDATE" ] && rm -f "$CANDIDATE"
  printf 'candidate=discarded reason=none\n'
  exit 0
fi

[ "$ACTION" = "publish" ] || usage_error

# publish requires an existing candidate + estimate verdict file.
{ [ -f "$CANDIDATE" ] && [ -r "$CANDIDATE" ]; } || usage_error
[ -n "$ESTIMATE_FILE" ] || usage_error
{ [ -f "$ESTIMATE_FILE" ] && [ -r "$ESTIMATE_FILE" ]; } || usage_error

# Strict full C3 grammar (blocker #8): only spec/task_over/stage_over/spec.total/
# legacy_missing and well-formed task.<id>/stage.<id> lines. Any unknown,
# duplicate or malformed line → exit 2 BEFORE any write; spec/task_over/
# stage_over are mandatory.
VERDICT="$(
  ESTIMATE_FILE="$ESTIMATE_FILE" python3 - <<'PY'
import os, re, sys
simple = {"spec", "task_over", "stage_over", "spec.total", "legacy_missing"}
seen = {}
task_re = re.compile(r"^task\.[0-9]+$")
stage_re = re.compile(r"^stage\.[0-9]+$")
try:
    lines = open(os.environ["ESTIMATE_FILE"], encoding="utf-8").read().splitlines()
except OSError:
    print("ERR read"); sys.exit(0)
for raw in lines:
    if raw.strip() == "":
        continue
    if "=" not in raw:
        print("ERR malformed_line"); sys.exit(0)
    key, val = raw.split("=", 1)
    if key in simple:
        if key in seen:
            print("ERR duplicate"); sys.exit(0)
        seen[key] = val
    elif task_re.match(key) or stage_re.match(key):
        if not re.match(r"^[0-9]+$", val):
            print("ERR bad_number"); sys.exit(0)
    else:
        print("ERR unknown_key"); sys.exit(0)
if seen.get("spec") not in ("ok", "near", "over"):
    print("ERR spec"); sys.exit(0)
if "task_over" not in seen or "stage_over" not in seen:
    print("ERR missing"); sys.exit(0)
if seen.get("spec.total") is not None and not re.match(r"^[0-9]+$", seen["spec.total"]):
    print("ERR spec_total"); sys.exit(0)
print("OK\t%s\t%s\t%s" % (seen["spec"], seen["task_over"], seen["stage_over"]))
PY
)"
case "$VERDICT" in
  OK*) : ;;
  *) printf 'error=malformed_verdict\n' >&2; exit 2 ;;
esac
spec="$(printf '%s' "$VERDICT" | cut -f2)"
task_over="$(printf '%s' "$VERDICT" | cut -f3)"
stage_over="$(printf '%s' "$VERDICT" | cut -f4)"

# discard the candidate + report a domain block, leaving the final untouched.
block() {
  rm -f "$CANDIDATE"
  printf 'candidate=blocked reason=%s\n' "$1"
  exit 1
}

# R3-003: hard D-13 caps first — override never lifts task/stage overflow.
if [ "$task_over" != "none" ]; then block task_overflow; fi
if [ "$stage_over" != "none" ]; then block stage_overflow; fi

# Spec rubicon: over needs `--override user`; ok/near publish freely.
if [ "$spec" = "over" ] && [ "$OVERRIDE" != "user" ]; then
  block spec_overflow
fi

# Existence preflight (review [14]): commands/sdd.md documents "--force —
# overwrite an existing spec triple (refuses without it)", but nothing enforced
# it and publish renamed straight over an accepted tasks.md. Re-checked HERE, in
# the helper that performs the write, so the guarantee cannot be lost by a
# caller that skips a prompt-level check.
if [ -e "$FINAL" ] && [ "$FORCE" -ne 1 ]; then
  printf 'candidate=blocked reason=spec_exists\n'
  exit 1
fi

# Publish: atomic same-filesystem rename candidate → final (draft).
mkdir -p "$FINAL_DIR"
CANDIDATE="$CANDIDATE" FINAL="$FINAL" python3 - <<'PY'
import os
os.rename(os.environ["CANDIDATE"], os.environ["FINAL"])
PY
printf 'candidate=published reason=none\n'
exit 0
