#!/usr/bin/env bash
# mb-interview-artifact-write.sh — deterministic writer for /mb discuss file
# effects (svp-interview-upgrade design C11, SVP-IU-002). The orchestrator calls
# this instead of a raw prompt `mv`, so the atomic write and the byte-identity of
# a rejected target are objective, script-proven facts.
#
# Usage:
#   mb-interview-artifact-write.sh install-plan       --mb <bank> --topic <topic> --candidate <file> [--print-digest]
#   mb-interview-artifact-write.sh publish-transcript --mb <bank> --topic <topic> --candidate <file> [--require-inherited]
#
# `install-plan` (this task): validate <candidate> with C8 `plan`; on
# `artifact=ok` atomically replace <bank>/tmp/interview-plan-<topic>.md
# (same-FS rename). A failed check leaves the target byte-identical (no partial
# write). The check runs WITHOUT --require-closed: the plan is installed at
# interview start with topics still open — only structural breakage rejects it.
#
# stdout : `artifact_write=installed kind=plan`, plus ` digest=<sha256>` with
#          --print-digest — the hash of the bytes actually installed, so the
#          close gate can later prove the plan it validates is still this one
#          and not a competing /mb discuss run's (r5 review [2]).
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
# An owned candidate is ATOMICALLY CLAIMED (rename) into a private 0700 staging
# directory BEFORE any validation runs, then FROZEN into a fresh inode there;
# the scan / grammar check / publish all read those same frozen bytes. Three
# separate defects live behind that sentence: re-opening the candidate path for
# each gate let a candidate swapped after a clean scan publish a live credential
# with exit 0; keeping the renamed inode let a concurrent run append to it
# through an fd it already held; and remembering the shared PATHNAME for cleanup
# let a signal delete a file that had meanwhile become another run's candidate.
#
# `install-plan` takes the same one-snapshot rule with a copy instead of a
# rename: its candidate must survive the call (the interview resumes from it).

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
# Two things may need scrubbing, and the trap covers both:
#   _SCRUB_DIR   the private staging directory holding the claimed candidate(s)
#   _INSTALL_TMP the atomic-install sibling copy, between `cp` and `mv`
# _INSTALL_TMP used to be untracked, so a signal landing in the post-copy window
# left a complete, readable transcript next to the target.
#
# What this list deliberately no longer holds is a PATHNAME under <bank>/tmp.
# commands/discuss.md gives two concurrent runs the same candidate name, so a
# remembered path is only "ours" until the other run writes there — and a
# SIGTERM then made this run delete the newcomer's file (r5 review [1]). An
# inode check does not save it either: a second run that rewrites the shared
# path in place keeps the very inode we recorded. The only sound answer is to
# stop owning a name at all: the candidate is MOVED into a private directory the
# moment it is recognised, and from then on cleanup only ever removes files that
# are already unreachable to anybody else.
_SCRUB_DIR=""
_INSTALL_TMP=""

_scrub_candidate() {
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
PRINT_DIGEST=0
STAGED=""
SNAP=""
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
    --print-digest) PRINT_DIGEST=1 ;;
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

# _ensure_stage <dir> — the private 0700 directory that holds claimed bytes,
# created in <dir> so the claim is a same-filesystem rename.
#
# The NAME is assigned BEFORE the directory exists, deliberately: `d="$(mktemp
# -d ...)"; _SCRUB_DIR="$d"` leaves a window in which a signal strands a 0700
# directory that is about to hold the raw candidate. `mkdir` refuses an existing
# path (a planted symlink included) instead of following it, so a predictable
# name is safe here in a way that an `open`/`cp` destination would not be.
_ensure_stage() {
  local dir="$1" i=0
  [ -n "$_SCRUB_DIR" ] && return 0
  while [ "$i" -lt 20 ]; do
    _SCRUB_DIR="$dir/.mb-iaw.$$.${RANDOM:-0}$i"
    if mkdir -m 700 "$_SCRUB_DIR" 2>/dev/null; then
      return 0
    fi
    i=$((i + 1))
  done
  _SCRUB_DIR=""
  return 1
}

# Original path of the candidate this run took, and where it lives now.
_CLAIMED_SRC=""
_CLAIMED_FILE=""
_N_CLAIMED=0

if [ "$SUB" = "publish-transcript" ]; then
  # CLAIM every passed --candidate, not just the surviving one, so a duplicated
  # flag cannot strand the first credential-bearing file — and claim it HERE,
  # before any validation, because the rejections below (bad flag, bad topic)
  # are exactly the ones that used to leave the raw credential readable on disk.
  #
  # Claiming is a rename into private staging, not a note to delete a path
  # later: it is the same atomic step, minus the window in which the shared name
  # can come to mean another run's file (r5 review [1]).
  while IFS= read -r _c; do
    [ -n "$_c" ] || continue
    _o="$(_owned_candidate "$_c")" || continue
    _ensure_stage "$(dirname "$_o")" || { printf 'error=io\n' >&2; exit 2; }
    _N_CLAIMED=$((_N_CLAIMED + 1))
    _dst="$_SCRUB_DIR/claimed-$_N_CLAIMED.md"
    mv -f "$_o" "$_dst" 2>/dev/null || continue
    if [ -z "$_CLAIMED_SRC" ]; then _CLAIMED_SRC="$_o"; _CLAIMED_FILE="$_dst"; fi
  done <<EOF
$_ALL_CANDS
EOF
fi

[ "$ARG_ERR" -eq 0 ] || usage_error
[ -n "$MB" ] && [ -n "$TOPIC" ] && [ -n "$CAND" ] || usage_error
# Readability is judged on the claimed copy when there is one — the candidate's
# own path is deliberately empty by now.
if [ -n "$_CLAIMED_FILE" ]; then
  [ -f "$_CLAIMED_FILE" ] && [ -r "$_CLAIMED_FILE" ] || usage_error
else
  [ -f "$CAND" ] && [ -r "$CAND" ] || usage_error
fi
valid_topic "$TOPIC" || topic_error

# require_owned_candidate — publish-transcript only. The ownership rules (regular
# non-symlink file, physically in <bank>/tmp, canonical name) were applied by
# _owned_candidate at CLAIM time; what is left to prove here is that the file
# actually claimed is the one --mb/--topic asks to publish. Nothing is re-stat'd
# at the shared path, because that path no longer holds our file — and by now it
# may legitimately hold somebody else's.
require_owned_candidate() {
  local bank_real
  [ -n "$_CLAIMED_SRC" ] || candidate_error
  bank_real="$(phys_dir "$MB")" || candidate_error
  [ -n "$bank_real" ] || candidate_error
  [ "$_CLAIMED_SRC" = "$bank_real/tmp/interview-transcript-$TOPIC.candidate.md" ] \
    || candidate_error
  CAND="$_CLAIMED_SRC"
}

# freeze_claimed — copy the claimed file into a brand-new inode and drop the old
# one. The claim moved the NAME; this moves the BYTES out of reach.
#
# `mv` keeps the inode, and commands/discuss.md hands two concurrent runs the
# same candidate path — so the other run could still hold that inode open. It
# appended a credential through its old fd AFTER the clean secret scan, and the
# writer published the mutated inode with exit 0 (r5 review [1]). Nothing
# outside this process has a handle on the copy, so the bytes the scan reads are
# the bytes that get published, whatever the other run does next.
# file_digest <path> — sha256 of the bytes at <path>, the handle a caller uses
# to prove later that the plan it is about to generate from is still the plan
# this run installed (r5 review [2]).
file_digest() {
  MB_F="$1" python3 -c 'import hashlib, os, sys
h = hashlib.sha256()
with open(os.environ["MB_F"], "rb") as fh:
    for chunk in iter(lambda: fh.read(65536), b""):
        h.update(chunk)
sys.stdout.write(h.hexdigest())'
}

# snapshot_plan_candidate — install-plan's equivalent of freeze_claimed. The
# candidate survives (REQ-019 resume), so its bytes are copied into a private
# inode and everything downstream — the C8 check and the install — reads only
# that copy.
snapshot_plan_candidate() {
  _ensure_stage "${TMPDIR:-/tmp}" || return 2
  SNAP="$_SCRUB_DIR/snapshot.md"
  cp "$CAND" "$SNAP" || return 2
  [ -f "$SNAP" ] || return 2
  return 0
}

freeze_claimed() {
  STAGED="$_SCRUB_DIR/staged.md"
  cp "$_CLAIMED_FILE" "$STAGED" || return 2
  rm -f "$_CLAIMED_FILE" || return 2
  [ -f "$STAGED" ] || return 2
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

atomic_install() {
  # $1 = source file; $2 = target path. Copies to a sibling temp, then renames
  # (same FS). The temp is tracked in _INSTALL_TMP for the whole cp→mv window so
  # a signal cannot strand a readable copy of the transcript next to the target.
  local src="$1" target="$2" target_dir tmp bank_real dir_real
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
  cp "$src" "$tmp" || { rm -f "$tmp"; _INSTALL_TMP=""; return 2; }
  # The publish goes through the ONE shared primitive (scripts/mb_fs_atomic.py),
  # which resolves the mode and renames inside a single directory lock:
  #
  #   * os.replace, not `mv` — rename(2) has no directory-descend semantics, so
  #     even a target created between the checks above and here cannot redirect
  #     the write, and a symlink/directory at the leaf is refused outright;
  #   * the mode is read THERE, immediately before the rename. Reading it up
  #     here (before `cp`) meant a run that found no target computed 0644 from
  #     its umask and then replaced the 0600 file another publisher had created
  #     in between — a widening nobody requested (r5 review [5]).
  MB_LIB="$SCRIPT_DIR" MB_TMP="$tmp" MB_TARGET="$target" python3 -c 'import os, sys
sys.path.insert(0, os.environ["MB_LIB"])
from mb_fs_atomic import publish_path
try:
    publish_path(os.environ["MB_TMP"], os.environ["MB_TARGET"], refuse_irregular=True)
except Exception:
    sys.exit(1)' || { rm -f "$tmp"; _INSTALL_TMP=""; return 2; }
  # Cleared only after the rename succeeded — before that the temp is live.
  _INSTALL_TMP=""
  return 0
}

case "$SUB" in
  install-plan)
    [ "$REQUIRE_INHERITED" -eq 0 ] || usage_error
    # ONE immutable snapshot is validated and installed. The candidate path used
    # to be opened twice — once by the C8 check, once by the copy — so a second
    # run rewriting it in between got unvalidated bytes published under
    # `artifact_write=installed`, and the installed plan then failed the very
    # check that had just passed (r5 review [3]). install-plan does NOT consume
    # its candidate (the interview resumes from it), so this is a copy, not the
    # rename publish-transcript uses.
    snapshot_plan_candidate || exit 2
    rc=0
    run_check "$SNAP" plan || rc=$?
    if [ "$rc" -ne 0 ]; then
      # rc 2 = check usage/read error → I/O class; rc 1 = invalid content.
      [ "$rc" -eq 2 ] && exit 2
      exit 1
    fi
    if atomic_install "$SNAP" "$MB/tmp/interview-plan-$TOPIC.md"; then
      if [ "$PRINT_DIGEST" -eq 1 ]; then
        # The digest names the SNAPSHOT, never a re-read of the published path:
        # that path is per-topic and a second /mb discuss run rewrites it, so a
        # digest taken from it could describe somebody else's plan.
        _d="$(file_digest "$SNAP")" || exit 2
        printf 'artifact_write=installed kind=plan digest=%s\n' "$_d"
      else
        printf 'artifact_write=installed kind=plan\n'
      fi
      exit 0
    fi
    exit 2
    ;;
  publish-transcript)
    # --print-digest belongs to install-plan: the transcript is published once
    # and never re-gated, so there is nothing to bind a later check to.
    [ "$PRINT_DIGEST" -eq 0 ] || usage_error
    # The candidate was CLAIMED (renamed into private staging) before any
    # validation ran. Prove it is the one this invocation asks to publish, then
    # freeze its bytes into a private inode, then gate them.
    require_owned_candidate
    freeze_claimed || exit 2
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
