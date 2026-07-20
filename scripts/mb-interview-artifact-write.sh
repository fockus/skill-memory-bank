#!/usr/bin/env bash
# mb-interview-artifact-write.sh — deterministic writer for /mb discuss file
# effects (svp-interview-upgrade design C11, SVP-IU-002). The orchestrator calls
# this instead of a raw prompt `mv`, so the atomic write and the byte-identity of
# a rejected target are objective, script-proven facts.
#
# Usage:
#   mb-interview-artifact-write.sh install-plan       --mb <bank> --topic <topic> --candidate <file>
#   mb-interview-artifact-write.sh publish-transcript --mb <bank> --topic <topic> --candidate <file> [--require-inherited]
#
# `install-plan` (this task): validate <candidate> with C8 `plan`; on
# `artifact=ok` atomically replace <bank>/tmp/interview-plan-<topic>.md
# (same-FS rename). A failed check leaves the target byte-identical (no partial
# write). The check runs WITHOUT --require-closed: the plan is installed at
# interview start with topics still open — only structural breakage rejects it.
#
# stdout : `artifact_write=installed kind=plan`
# exit   : 0 installed · 1 content rejected (check invalid) · 2 usage / I/O.
#          On exit 1/2 stdout is empty; the reason is forwarded from C8 stderr.
#          stderr codes: `error=usage`, `error=topic`, `error=candidate`.
#
# `publish-transcript` owns EXACTLY ONE candidate path —
# <bank>/tmp/interview-transcript-<topic>.candidate.md, which must be a regular,
# non-symlink file physically inside the resolved <bank>/tmp. Anything else is
# `error=candidate` (exit 2) and is left untouched: the writer deletes the
# candidate, so it may only ever delete a path it demonstrably owns. Handing it
# the published target, an arbitrary file, or a symlink to a credential-bearing
# file used to make it destroy the target or unlink only the link.
#
# Once ownership is proven the candidate is ATOMICALLY CLAIMED (rename) into a
# private 0700 staging directory, and the scan / grammar check / publish all read
# those same staged bytes. Re-opening the candidate path for each gate let a
# candidate swapped after a clean scan publish a live credential with exit 0.

set -euo pipefail

# Resolve this script's own PHYSICAL directory through its FULL symlink chain.
# Deriving SCRIPT_DIR from the symlink's directory let an attacker tree place a
# stub `mb-secret-scan.sh` / `mb-interview-artifact-check.sh` beside the link
# and publish a live credential with exit 0 — the gates MUST come from the real
# writer's directory (REQ-007 / C11).
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
CHECK="$SCRIPT_DIR/mb-interview-artifact-check.sh"
SCAN="$SCRIPT_DIR/mb-secret-scan.sh"

usage_error() { printf 'error=usage\n' >&2; exit 2; }
topic_error() { printf 'error=topic\n' >&2; exit 2; }
candidate_error() { printf 'error=candidate\n' >&2; exit 2; }

# Candidate lifecycle (REQ-007): on the transcript path the candidate holds the
# RAW interview text, credentials included. It is a throwaway owned by this
# writer and is removed on EVERY exit path — publication, scan block, grammar
# reject, I/O error, or signal — so a rejected credential never lingers as
# readable plaintext under <bank>/tmp.
#
# Three things may need scrubbing, and the trap covers all of them:
#   _SCRUB_CAND  the candidate, until it is claimed into staging
#   _SCRUB_DIR   the private staging directory holding the claimed bytes
#   _INSTALL_TMP the atomic-install sibling copy, between `cp` and `mv`
# _INSTALL_TMP used to be untracked, so a signal landing in the post-copy window
# left a complete, readable transcript next to the target.
_SCRUB_CAND=""
_SCRUB_DIR=""
_INSTALL_TMP=""
_scrub_candidate() {
  # _SCRUB_CAND is a newline-separated LIST: a duplicated --candidate must not
  # let the first, credential-bearing path escape cleanup.
  if [ -n "$_SCRUB_CAND" ]; then
    while IFS= read -r _p; do
      [ -n "$_p" ] && rm -f "$_p" 2>/dev/null
    done <<EOF
$_SCRUB_CAND
EOF
  fi
  if [ -n "$_SCRUB_DIR" ]; then rm -rf "$_SCRUB_DIR" 2>/dev/null || true; fi
  if [ -n "$_INSTALL_TMP" ]; then rm -f "$_INSTALL_TMP" 2>/dev/null || true; fi
  return 0
}
# A bare `trap ... TERM` handler RESUMES the script once it returns, which would
# let a signalled run carry on and publish. Scrub, then terminate with the
# conventional 128+signal status.
_on_signal() {
  _scrub_candidate
  trap - EXIT
  exit $((128 + $1))
}

# Physical directory of an EXISTING path (no realpath on bare macOS).
phys_dir() { cd -P "$1" 2>/dev/null && pwd -P; }

# valid_topic <topic> — strict kebab-case slug: lowercase letters/digits joined
# by single dashes, no leading/trailing/double dash. A '/', '.', or '..' cannot
# appear, so <topic> can never widen the target path outside <bank> (R3-001,
# path-traversal guard). Returns 0 when valid.
valid_topic() {
  case "$1" in
    ''|*[!a-z0-9-]*) return 1 ;;
    -*|*-|*--*) return 1 ;;
  esac
  return 0
}

SUB="${1:-}"
[ -n "$SUB" ] || usage_error
shift

MB=""
TOPIC=""
CAND=""
REQUIRE_INHERITED=0
STAGED=""
# A usage fault is REMEMBERED, not raised inside the parse loop. Bailing out
# early meant a credential-bearing candidate named later on the command line was
# never scrubbed, and made scrubbing depend on flag ORDER. The whole line is
# parsed first; the error is raised after cleanup has been armed.
ARG_ERR=0
_N_MB=0; _N_TOPIC=0; _N_CAND=0
# EVERY --candidate seen, newline separated. A repeated singleton flag kept only
# the LAST value, so `--candidate <secret> --candidate <notes>` exited
# error=candidate and left the first, credential-bearing candidate on disk.
_ALL_CANDS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) if [ "$#" -ge 2 ]; then MB="$2"; _N_MB=$((_N_MB+1)); shift; else ARG_ERR=1; fi ;;
    --topic) if [ "$#" -ge 2 ]; then TOPIC="$2"; _N_TOPIC=$((_N_TOPIC+1)); shift; else ARG_ERR=1; fi ;;
    --candidate)
      if [ "$#" -ge 2 ]; then
        CAND="$2"; _N_CAND=$((_N_CAND+1)); _ALL_CANDS="$_ALL_CANDS$2
"; shift
      else ARG_ERR=1; fi ;;
    --require-inherited) REQUIRE_INHERITED=1 ;;
    *) ARG_ERR=1 ;;
  esac
  shift
done
# A singleton flag given twice is ambiguous, not a preference for the last one.
if [ "$_N_MB" -gt 1 ] || [ "$_N_TOPIC" -gt 1 ] || [ "$_N_CAND" -gt 1 ]; then ARG_ERR=1; fi

# Arm cleanup BEFORE any validation. Ownership is established from the bank/tmp
# location alone — independent of topic validity, flag validity, and
# readability — because those are exactly the rejections that used to leave the
# raw credential readable on disk.
trap _scrub_candidate EXIT
trap '_on_signal 2' INT
trap '_on_signal 15' TERM
trap '_on_signal 1' HUP

# _owned_candidate <path> — echoes the physical path when <path> is a candidate
# THIS invocation owns, else nothing. Three narrowing rules, each from a real
# data-loss or leak report:
#   * must be a regular, non-symlink file physically inside <bank>/tmp — an
#     unlinked symlink would destroy the link and leave the backing file (r2);
#   * living in <bank>/tmp is not enough: the name must be a canonical candidate
#     name, or a rejected `--candidate <bank>/tmp/notes.md` deletes those notes (r3);
#   * when the topic is VALID the name must be exactly this topic's — otherwise
#     `--topic foo --candidate ...-bar.candidate.md` deleted bar's candidate (r4).
#     With no valid topic the exact name is uncomputable, so the canonical
#     pattern still applies: the caller explicitly handed us that file.
_owned_candidate() {
  local c="$1" bank_real cand_dir base
  [ -n "$MB" ] && [ -d "$MB" ] || return 1
  bank_real="$(phys_dir "$MB")" || return 1
  [ -n "$bank_real" ] || return 1
  { [ -f "$c" ] && [ ! -L "$c" ]; } || return 1
  cand_dir="$(phys_dir "$(dirname "$c")")" || return 1
  [ "$cand_dir" = "$bank_real/tmp" ] || return 1
  base="$(basename "$c")"
  if valid_topic "$TOPIC"; then
    [ "$base" = "interview-transcript-$TOPIC.candidate.md" ] || return 1
  else
    case "$base" in interview-transcript-?*.candidate.md) ;; *) return 1 ;; esac
  fi
  printf '%s/%s' "$cand_dir" "$base"
}

if [ "$SUB" = "publish-transcript" ]; then
  # Arm over EVERY passed --candidate, not just the surviving one, so a
  # duplicated flag cannot strand the first credential-bearing file.
  while IFS= read -r _c; do
    [ -n "$_c" ] || continue
    _o="$(_owned_candidate "$_c")" || continue
    _SCRUB_CAND="$_SCRUB_CAND$_o
"
  done <<EOF
$_ALL_CANDS
EOF
fi

[ "$ARG_ERR" -eq 0 ] || usage_error
[ -n "$MB" ] && [ -n "$TOPIC" ] && [ -n "$CAND" ] || usage_error
[ -f "$CAND" ] && [ -r "$CAND" ] || usage_error
valid_topic "$TOPIC" || topic_error

# require_owned_candidate — publish-transcript only. Proves the candidate is the
# exact path this writer owns before anything is deleted or published, and
# normalizes CAND to its physical form.
require_owned_candidate() {
  local bank_real cand_dir expect
  bank_real="$(phys_dir "$MB")" || candidate_error
  [ -n "$bank_real" ] || candidate_error
  if [ -L "$CAND" ]; then candidate_error; fi
  if [ ! -f "$CAND" ]; then candidate_error; fi
  cand_dir="$(phys_dir "$(dirname "$CAND")")" || candidate_error
  if [ "$cand_dir" != "$bank_real/tmp" ]; then candidate_error; fi
  expect="interview-transcript-$TOPIC.candidate.md"
  if [ "$(basename "$CAND")" != "$expect" ]; then candidate_error; fi
  CAND="$cand_dir/$expect"
  _SCRUB_CAND="$CAND
"
}

# claim_candidate — atomically RENAME the proven candidate into a private 0700
# staging directory and work only on those bytes from here on. Every gate used
# to re-open the candidate path, so replacing the file after a clean scan
# published the replacement.
claim_candidate() {
  local stage
  stage="$(mktemp -d "$(dirname "$CAND")/.mb-iaw.XXXXXX")" || return 2
  chmod 700 "$stage" 2>/dev/null || { rm -rf "$stage"; return 2; }
  _SCRUB_DIR="$stage"
  STAGED="$stage/staged.md"
  mv -f "$CAND" "$STAGED" || return 2
  # The path is no longer ours: a file recreated there belongs to whoever made
  # it, and this writer must not delete other people's files.
  _SCRUB_CAND=""
  return 0
}

run_check() {
  # $1 = file; $2 = mode; remaining = extra flags. Forwards check stderr.
  local file="$1" mode="$2"; shift 2
  local errf rc
  errf="$(mktemp "${TMPDIR:-/tmp}/mb-artifact-check.XXXXXX")"
  if "$CHECK" "$mode" "$file" "$@" >/dev/null 2>"$errf"; then
    rc=0
  else
    rc=$?
  fi
  cat "$errf" >&2
  rm -f "$errf"
  return "$rc"
}

run_scan() {
  # $1 = file. Secret-scan under the transcript policy. Forwards scan stderr;
  # returns scan rc (0 clean · 1 blocked · 2 unsupported).
  local file="$1" errf rc
  errf="$(mktemp "${TMPDIR:-/tmp}/mb-artifact-scan.XXXXXX")"
  if "$SCAN" --policy transcript "$file" >/dev/null 2>"$errf"; then
    rc=0
  else
    rc=$?
  fi
  cat "$errf" >&2
  rm -f "$errf"
  return "$rc"
}

# title_names_topic <file> <topic> — the C4 title must name the topic actually
# being published. The checker validates the title's SHAPE and date but has no
# idea which topic the writer was asked for, so a candidate titled `foo`
# published cleanly as context/bar-interview.md and the transcript on disk
# contradicted its own filename.
title_names_topic() {
  local file="$1" topic="$2" first
  first="$(awk 'NF { print; exit }' "$file")"
  case "$first" in
    "# Interview transcript: $topic ("*) return 0 ;;
  esac
  return 1
}

# target_mode <path> — octal mode the published file must end up with: an
# EXISTING regular target keeps its mode verbatim; otherwise the ordinary
# creation default (0666 & ~umask), computed rather than hardcoded so a strict
# environment is never silently widened.
target_mode() {
  local m u
  if [ -f "$1" ] && [ ! -L "$1" ]; then
    m="$(stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null)" || return 1
    [ -n "$m" ] || return 1
    printf '%s\n' "$m"
    return 0
  fi
  u="$(umask)"
  printf '%o\n' $(( 0666 & ~(8#$u) ))
}

atomic_install() {
  # $1 = source file; $2 = target path. Copies to a sibling temp, then renames
  # (same FS). The temp is tracked in _INSTALL_TMP for the whole cp→mv window so
  # a signal cannot strand a readable copy of the transcript next to the target.
  local src="$1" target="$2" target_dir tmp bank_real dir_real mode
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir" || return 2
  # Containment (defence in depth beyond valid_topic): the resolved target
  # directory must live inside the resolved bank, never above or beside it.
  bank_real="$(cd "$MB" 2>/dev/null && pwd -P)" || return 2
  dir_real="$(cd "$target_dir" 2>/dev/null && pwd -P)" || return 2
  case "$dir_real/" in
    "$bank_real"/*) ;;
    *) return 2 ;;
  esac
  # The temp MUST be created exclusively. `.<target>.$$.tmp` was fully
  # predictable, and `cp` writes THROUGH an existing symlink: planting that path
  # on a victim overwrote the victim, left the target a symlink, and the writer
  # still reported success. mktemp creates with O_EXCL, so a pre-planted path is
  # refused rather than followed.
  tmp="$(mktemp "$target_dir/.$(basename "$target").XXXXXX")" || return 2
  _INSTALL_TMP="$tmp"
  # mktemp publishes at 0600. Carry the mode the target must actually end up
  # with: an existing target keeps its own mode verbatim (same rule as
  # scripts/mb_fs_atomic.py — never widen what somebody deliberately locked
  # down), a fresh one gets the ordinary creation default.
  mode="$(target_mode "$target")" || { rm -f "$tmp"; _INSTALL_TMP=""; return 2; }
  cp "$src" "$tmp" || { rm -f "$tmp"; _INSTALL_TMP=""; return 2; }
  chmod "$mode" "$tmp" || { rm -f "$tmp"; _INSTALL_TMP=""; return 2; }
  # os.replace, not `mv`: rename(2) has no directory-descend semantics, so even
  # a target created between the check above and here cannot redirect the write.
  MB_TMP="$tmp" MB_TARGET="$target" python3 -c 'import os, sys
tmp, target = os.environ["MB_TMP"], os.environ["MB_TARGET"]
try:
    st = os.lstat(target)
except FileNotFoundError:
    st = None
except OSError:
    sys.exit(1)
import stat as _s
if st is not None and (_s.S_ISLNK(st.st_mode) or not _s.S_ISREG(st.st_mode)):
    sys.exit(1)
os.replace(tmp, target)' || { rm -f "$tmp"; _INSTALL_TMP=""; return 2; }
  # Cleared only after the rename succeeded — before that the temp is live.
  _INSTALL_TMP=""
  return 0
}

case "$SUB" in
  install-plan)
    [ "$REQUIRE_INHERITED" -eq 0 ] || usage_error
    rc=0
    run_check "$CAND" plan || rc=$?
    if [ "$rc" -ne 0 ]; then
      # rc 2 = check usage/read error → I/O class; rc 1 = invalid content.
      [ "$rc" -eq 2 ] && exit 2
      exit 1
    fi
    if atomic_install "$CAND" "$MB/tmp/interview-plan-$TOPIC.md"; then
      printf 'artifact_write=installed kind=plan\n'
      exit 0
    fi
    exit 2
    ;;
  publish-transcript)
    # Prove ownership, THEN take the bytes out of reach, THEN gate them.
    require_owned_candidate
    claim_candidate || exit 2
    # C5 secret-scan + C8 transcript grammar must both pass before publishing —
    # both against the immutable staged bytes, which are also what gets copied.
    extra=()
    [ "$REQUIRE_INHERITED" -eq 1 ] && extra+=(--require-inherited)
    rc=0
    run_scan "$STAGED" || rc=$?
    if [ "$rc" -ne 0 ]; then
      [ "$rc" -eq 2 ] && exit 2
      exit 1
    fi
    rc=0
    run_check "$STAGED" transcript ${extra[@]+"${extra[@]}"} || rc=$?
    if [ "$rc" -ne 0 ]; then
      [ "$rc" -eq 2 ] && exit 2
      exit 1
    fi
    # The title must name THIS topic — checked on the staged bytes, before any
    # install, and reported with the declared C8 reason.
    if ! title_names_topic "$STAGED" "$TOPIC"; then
      printf '%s:1:missing_title\n' "$MB/context/$TOPIC-interview.md" >&2
      exit 1
    fi
    if atomic_install "$STAGED" "$MB/context/$TOPIC-interview.md"; then
      printf 'artifact_write=installed kind=transcript\n'
      exit 0
    fi
    exit 2
    ;;
  *)
    usage_error
    ;;
esac
