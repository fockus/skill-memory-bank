#!/usr/bin/env bash
# mb-interview-artifact-write.sh — deterministic writer for /mb discuss file
# effects (svp-interview-upgrade design C11, SVP-IU-002). The orchestrator calls
# this instead of a raw prompt `mv`, so the atomic write and the byte-identity of
# a rejected target are objective, script-proven facts.
#
# Usage:
#   mb-interview-artifact-write.sh install-plan       --mb <bank> --topic <topic> --candidate <file>
#   mb-interview-artifact-write.sh publish-transcript --mb <bank> --topic <topic> --candidate <file> [--require-inherited] [--legacy-live-fixture]   # added in Task 4
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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/mb-interview-artifact-check.sh"
SCAN="$SCRIPT_DIR/mb-secret-scan.sh"

usage_error() { printf 'error=usage\n' >&2; exit 2; }

SUB="${1:-}"
[ -n "$SUB" ] || usage_error
shift

MB=""
TOPIC=""
CAND=""
REQUIRE_INHERITED=0
LEGACY_FIXTURE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) [ "$#" -ge 2 ] || usage_error; MB="$2"; shift ;;
    --topic) [ "$#" -ge 2 ] || usage_error; TOPIC="$2"; shift ;;
    --candidate) [ "$#" -ge 2 ] || usage_error; CAND="$2"; shift ;;
    --require-inherited) REQUIRE_INHERITED=1 ;;
    --legacy-live-fixture) LEGACY_FIXTURE=1 ;;
    *) usage_error ;;
  esac
  shift
done

[ -n "$MB" ] && [ -n "$TOPIC" ] && [ -n "$CAND" ] || usage_error
[ -f "$CAND" ] && [ -r "$CAND" ] || usage_error

run_check() {
  # $1 = mode; remaining = extra flags. Forwards check stderr; returns check rc.
  local mode="$1"; shift
  local errf rc
  errf="$(mktemp "${TMPDIR:-/tmp}/mb-artifact-check.XXXXXX")"
  if "$CHECK" "$mode" "$CAND" "$@" >/dev/null 2>"$errf"; then
    rc=0
  else
    rc=$?
  fi
  cat "$errf" >&2
  rm -f "$errf"
  return "$rc"
}

run_scan() {
  # Secret-scan the candidate under the transcript policy. Forwards scan stderr;
  # returns scan rc (0 clean · 1 blocked · 2 unsupported).
  local errf rc
  errf="$(mktemp "${TMPDIR:-/tmp}/mb-artifact-scan.XXXXXX")"
  if "$SCAN" --policy transcript "$CAND" >/dev/null 2>"$errf"; then
    rc=0
  else
    rc=$?
  fi
  cat "$errf" >&2
  rm -f "$errf"
  return "$rc"
}

atomic_install() {
  # $1 = target path. Copies CAND to a sibling temp then renames (same FS).
  local target="$1" target_dir tmp
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir" || return 2
  tmp="$target_dir/.$(basename "$target").$$.tmp"
  cp "$CAND" "$tmp" || { rm -f "$tmp"; return 2; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; return 2; }
  return 0
}

case "$SUB" in
  install-plan)
    [ "$REQUIRE_INHERITED" -eq 0 ] && [ "$LEGACY_FIXTURE" -eq 0 ] || usage_error
    rc=0
    run_check plan || rc=$?
    if [ "$rc" -ne 0 ]; then
      # rc 2 = check usage/read error → I/O class; rc 1 = invalid content.
      [ "$rc" -eq 2 ] && exit 2
      exit 1
    fi
    if atomic_install "$MB/tmp/interview-plan-$TOPIC.md"; then
      printf 'artifact_write=installed kind=plan\n'
      exit 0
    fi
    exit 2
    ;;
  publish-transcript)
    # C5 secret-scan + C8 transcript grammar must both pass before publishing.
    extra=()
    [ "$REQUIRE_INHERITED" -eq 1 ] && extra+=(--require-inherited)
    [ "$LEGACY_FIXTURE" -eq 1 ] && extra+=(--legacy-live-fixture)
    rc=0
    run_scan || rc=$?
    if [ "$rc" -ne 0 ]; then
      [ "$rc" -eq 2 ] && exit 2
      exit 1
    fi
    rc=0
    run_check transcript ${extra[@]+"${extra[@]}"} || rc=$?
    if [ "$rc" -ne 0 ]; then
      [ "$rc" -eq 2 ] && exit 2
      exit 1
    fi
    if atomic_install "$MB/context/$TOPIC-interview.md"; then
      printf 'artifact_write=installed kind=transcript\n'
      exit 0
    fi
    exit 2
    ;;
  *)
    usage_error
    ;;
esac
