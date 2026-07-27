#!/usr/bin/env bash
# mb-brief.sh — deterministic helper behind /mb brief (svp-brief C6).
#
#   mb-brief.sh create  --mb <bank> --topic <topic> --candidate <path>
#                       [--input <path>]... [--auto]
#   mb-brief.sh context --mb <bank> --topic <topic>
#
# DIVISION OF LABOUR. The prompt layer (commands/brief.md) owns judgement: it
# analyses the request, asks the light questions and writes the COMPLETE brief
# text into a candidate file. This helper owns the filesystem: validation,
# scanning, staging and one atomic publish. It never generates text and has no
# --request flags.
#
# `create` runs a fixed step order, and every refusal happens BEFORE a single
# byte is written under briefs/:
#   1 usage        — topic grammar, candidate and inputs are readable regular
#                    files (never symlinks, never a `..` component), no
#                    basename collision
#   2 bootstrap    — create tmp/ and briefs/, take the publish mutex, and
#                    re-check the destination UNDER it (file, dir or symlink)
#   3 validate     — scripts/mb-brief-validate.sh (C1) on the candidate
#   4 --auto       — assumptions_note required with it, forbidden without it
#   5 inputs       — frontmatter == Attachments links == argv basenames (C2)
#   6 secret-scan  — every --input, aggregated: usage > unsupported > blocked
#   7 staging      — a private mktemp dir inside the bank's tmp/
#   8 publish      — ONE rename(2) of the staging dir onto briefs/<topic>
#
# THE `candidate=` RULE (R3-007). A step-1 usage error prints no `candidate=`
# line: there is nothing to keep, because the path was either not given or does
# not name a readable file. Once the candidate has been accepted, any later
# refusal keeps it and names it on the LAST line of stderr, so the user fixes
# the source or the secret and retries without paying for LLM generation again.
#
# exit: 0 success · 1 blocked (a `brief=` line is on stdout) · 2 usage/regression.

set -euo pipefail

# Physical self-directory through the FULL symlink chain: the validator, the
# scanner and _lib.sh are loaded as siblings, so resolving from a symlink's
# directory would let an attacker tree supply a neutered validator or scanner.
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
SCRIPT_DIR="$(_mb_resolve_self_dir "${BASH_SOURCE[0]}")"
VALIDATE="$SCRIPT_DIR/mb-brief-validate.sh"
SCANNER="$SCRIPT_DIR/mb-secret-scan.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/_lib.sh"

LOCK_TIMEOUT=30
LOCK_TTL=120

usage_error() { printf 'error=usage\n' >&2; exit 2; }

# ── argument parsing ────────────────────────────────────────────────────────
SUB="${1:-}"
[ "$#" -gt 0 ] && shift
case "$SUB" in create | context) ;; *) usage_error ;; esac

MB=""
TOPIC=""
CANDIDATE=""
AUTO=0
have_cand=0
INPUTS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) [ "$#" -ge 2 ] || usage_error; MB="$2"; shift ;;
    --topic) [ "$#" -ge 2 ] || usage_error; TOPIC="$2"; shift ;;
    --candidate)
      [ "$SUB" = create ] || usage_error
      [ "$#" -ge 2 ] || usage_error
      [ "$have_cand" -eq 0 ] || usage_error
      CANDIDATE="$2"; have_cand=1; shift ;;
    --input)
      [ "$SUB" = create ] || usage_error
      [ "$#" -ge 2 ] || usage_error
      INPUTS[${#INPUTS[@]}]="$2"; shift ;;
    --auto) [ "$SUB" = create ] || usage_error; AUTO=1 ;;
    *) usage_error ;;
  esac
  shift
done

[ -n "$MB" ] || usage_error
[ -n "$TOPIC" ] || usage_error
# The topic is pasted straight into paths, so its grammar is proven BEFORE any
# path is built: `../escape` must never reach a mkdir.
printf '%s' "$TOPIC" | grep -qE '^[a-z0-9][a-z0-9-]*$' || usage_error
[ -d "$MB" ] || usage_error

DEST="$MB/briefs/$TOPIC"

# ── context: a manifest of paths, never the brief body ──────────────────────
if [ "$SUB" = context ]; then
  if [ ! -f "$DEST/brief.md" ] || [ -L "$DEST" ]; then
    printf 'brief=absent\n'
    exit 0
  fi
  printf 'brief=present\n'
  printf 'brief_path=briefs/%s/brief.md\n' "$TOPIC"
  if [ -d "$DEST/inputs" ]; then
    python3 - "$DEST/inputs" "$TOPIC" <<'PY'
import os
import sys

directory, topic = sys.argv[1], sys.argv[2]
names = [
    n for n in os.listdir(directory)
    if os.path.isfile(os.path.join(directory, n))
    and not os.path.islink(os.path.join(directory, n))
]
# LC_ALL=C order is byte order, not locale collation.
for name in sorted(names, key=lambda s: s.encode("utf-8", "surrogateescape")):
    sys.stdout.write("input_path=briefs/%s/inputs/%s\n" % (topic, name))
PY
  fi
  exit 0
fi

# ── step 1: usage guards (no `candidate=` line may be printed from here) ────
[ "$have_cand" -eq 1 ] || usage_error
if [ -L "$CANDIDATE" ] || [ ! -f "$CANDIDATE" ] || [ ! -r "$CANDIDATE" ]; then
  printf 'error=candidate_unreadable path=%s\n' "$CANDIDATE" >&2
  exit 2
fi

input_reject() { printf 'error=input_unreadable path=%s\n' "$1" >&2; exit 2; }

for p in ${INPUTS[@]+"${INPUTS[@]}"}; do
  # A `..` PATH SEGMENT is refused; `a..b.md` is a perfectly ordinary filename.
  case "/$p/" in */../*) input_reject "$p" ;; esac
  # A symlink is refused rather than followed: the scan would inspect the link
  # target while the copy could resolve elsewhere.
  if [ -L "$p" ] || [ ! -f "$p" ] || [ ! -r "$p" ]; then input_reject "$p"; fi
done

n=${#INPUTS[@]}
i=0
while [ "$i" -lt "$n" ]; do
  j=$((i + 1))
  while [ "$j" -lt "$n" ]; do
    if [ "$(basename "${INPUTS[$i]}")" = "$(basename "${INPUTS[$j]}")" ]; then
      printf 'error=basename_collision basename=%s\n' "$(basename "${INPUTS[$i]}")" >&2
      exit 2
    fi
    j=$((j + 1))
  done
  i=$((i + 1))
done

# ── the candidate is now accepted: every later refusal names it ─────────────
STAGING=""
LOCK_DIR=""
LOCK_TOKEN=""

# shellcheck disable=SC2329  # invoked indirectly via `trap`
cleanup() {
  [ -n "$STAGING" ] && rm -rf "$STAGING"
  [ -n "$LOCK_TOKEN" ] && mb_lock_release "$LOCK_DIR" "$LOCK_TOKEN" >/dev/null 2>&1
  return 0
}
trap cleanup EXIT INT TERM

# fail_late <exit-code> — `candidate=` is always the LAST line of stderr.
fail_late() {
  printf 'candidate=%s\n' "$CANDIDATE" >&2
  exit "$1"
}

# ── step 2: bootstrap the roots, then the exists gate UNDER the mutex ───────
# A fresh bank has neither directory: `/mb init` creates experiments, plans,
# notes, reports and codebase only.
mkdir -p "$MB/tmp" "$MB/briefs"

LOCK_DIR="$MB/tmp/.brief-$TOPIC.lock"
if ! LOCK_TOKEN="$(mb_lock_acquire "$LOCK_DIR" "$LOCK_TIMEOUT" "$LOCK_TTL" 2>/dev/null)"; then
  LOCK_TOKEN=""
  printf 'error=lock path=tmp/.brief-%s.lock\n' "$TOPIC" >&2
  fail_late 2
fi

# `-e` is false for a DANGLING symlink, so `-L` is tested separately: without it
# `mv` would follow the link and publish the brief, with its scanned inputs,
# into an attacker-chosen directory outside the bank.
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  printf 'brief=blocked reason=exists\n'
  printf 'error=exists path=briefs/%s\n' "$TOPIC" >&2
  fail_late 1
fi

# ── step 3: structural validation of the candidate (C1) ────────────────────
VERR="$(mktemp "${TMPDIR:-/tmp}/mb-brief-verr.XXXXXX")"
vrc=0
"$VALIDATE" "$CANDIDATE" >/dev/null 2>"$VERR" || vrc=$?
if [ "$vrc" -ne 0 ]; then
  printf 'brief=blocked reason=invalid\n'
  cat "$VERR" >&2
  rm -f "$VERR"
  fail_late 1
fi
# A warning (oversize) leaves vrc 0 but still belongs to the user.
cat "$VERR" >&2
rm -f "$VERR"

# ── steps 4-5: --auto agreement and the inputs invariant (C2) ──────────────
CERR="$(mktemp "${TMPDIR:-/tmp}/mb-brief-cerr.XXXXXX")"
crc=0
python3 "$SCRIPT_DIR/mb_brief_candidate.py" \
  "$CANDIDATE" "$AUTO" ${INPUTS[@]+"${INPUTS[@]}"} >"$CERR" 2>&1 || crc=$?
if [ "$crc" -ne 0 ]; then
  printf 'brief=blocked reason=invalid\n'
  cat "$CERR" >&2
  rm -f "$CERR"
  fail_late 1
fi
rm -f "$CERR"

# ── step 6: scan every source, then decide from the WHOLE set (R3-006) ─────
SCAN_ERR=()
SCAN_CLASS=()
have_usage=0
have_unsupported=0
have_blocked=0

for p in ${INPUTS[@]+"${INPUTS[@]}"}; do
  so="$(mktemp "${TMPDIR:-/tmp}/mb-brief-so.XXXXXX")"
  se="$(mktemp "${TMPDIR:-/tmp}/mb-brief-se.XXXXXX")"
  src=0
  "$SCANNER" --policy brief-input "$p" >"$so" 2>"$se" || src=$?
  verdict="$(head -1 "$so" 2>/dev/null || true)"
  case "$verdict" in
    scan=clean) class=clean ;;
    scan=blocked) class=blocked; have_blocked=1 ;;
    scan=unsupported) class=unsupported; have_unsupported=1 ;;
    # exit 2 with an EMPTY stdout is a scanner contract regression, not a
    # verdict. "Clean" is never derived from it — that would copy an
    # UNSCANNED source, which is the exact failure this gate exists to stop.
    *) class=usage; have_usage=1 ;;
  esac
  SCAN_CLASS[${#SCAN_CLASS[@]}]="$class"
  SCAN_ERR[${#SCAN_ERR[@]}]="$se"
  rm -f "$so"
done

# Diagnostics for every non-clean source, in argv order — REQ-010 requires
# naming EVERY unscannable source, not just the first one to fail.
emit_scan_diagnostics() {
  local k=0
  while [ "$k" -lt "${#SCAN_CLASS[@]}" ]; do
    if [ "${SCAN_CLASS[$k]}" != clean ]; then
      cat "${SCAN_ERR[$k]}" >&2
    fi
    k=$((k + 1))
  done
}

drop_scan_temps() {
  local k=0
  while [ "$k" -lt "${#SCAN_ERR[@]}" ]; do
    rm -f "${SCAN_ERR[$k]}"
    k=$((k + 1))
  done
}

if [ "$have_usage" -eq 1 ]; then
  k=0
  while [ "$k" -lt "${#SCAN_CLASS[@]}" ]; do
    if [ "${SCAN_CLASS[$k]}" = usage ]; then
      printf 'error=scan_usage path=%s\n' "${INPUTS[$k]}" >&2
    fi
    k=$((k + 1))
  done
  drop_scan_temps
  fail_late 2
elif [ "$have_unsupported" -eq 1 ]; then
  printf 'brief=blocked reason=scan_unsupported\n'
  emit_scan_diagnostics
  drop_scan_temps
  fail_late 1
elif [ "$have_blocked" -eq 1 ]; then
  printf 'brief=blocked reason=secret\n'
  emit_scan_diagnostics
  drop_scan_temps
  fail_late 1
fi
drop_scan_temps

# ── step 7: staging inside the bank, on the same filesystem as briefs/ ─────
# `mktemp -d` is atomic and unpredictable: a fixed `<pid>-<rand>` name in a
# world-writable tmp/ could be pre-created as a symlink by another process.
STAGING="$(mktemp -d "$MB/tmp/brief-$TOPIC.staging.XXXXXX")"
cp -p "$CANDIDATE" "$STAGING/brief.md"
if [ "${#INPUTS[@]}" -gt 0 ]; then
  mkdir "$STAGING/inputs"
  for p in "${INPUTS[@]}"; do
    # -p keeps the source mode verbatim rather than widening it to the umask.
    cp -p "$p" "$STAGING/inputs/$(basename "$p")"
  done
fi
# mktemp gives the staging dir 0700; the published directory should sit at the
# same permissions as its siblings rather than at a private temp mode.
python3 -c 'import os,stat,sys; os.chmod(sys.argv[1], stat.S_IMODE(os.stat(sys.argv[2]).st_mode))' \
  "$STAGING" "$MB/briefs"

# ── step 8: publish — one rename(2), still under the mutex ─────────────────
mv "$STAGING" "$DEST"
STAGING=""
printf 'brief=created path=briefs/%s/brief.md\n' "$TOPIC"
rm -f "$CANDIDATE"
exit 0
