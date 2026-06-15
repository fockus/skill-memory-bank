#!/usr/bin/env bash
# mb-flow-sync.sh — regenerate the `mb-flow` runtime fence in status.md (dynamic-flow Task 3).
#
# Usage:
#   mb-flow-sync.sh [mb_path] [--route R] [--phase k/n] [--phases a,b,c]
#                   [--checks JSON] [--gate PASS|FAIL]
#                   [--last-verify-sha SHA] [--stall-count N]
#
# Effects (REQ-DF-030/031/032; design ADR-5 + L4 Interfaces):
#   - Between `<!-- mb-flow -->` and `<!-- /mb-flow -->` fences in status.md, emit ONLY
#     the genuinely-new runtime fields: route, current_phase, phases, checks{8}, gate,
#     last_verify_sha, stall_count. Everything else stays a POINTER to its SSOT — no
#     goal/DoD/tasks are duplicated into the fence.
#   - First write CREATES the fence (appended to status.md; status.md is created if absent).
#   - Re-write is IDEMPOTENT: same inputs → byte-identical status.md.
#   - Content OUTSIDE the fence is preserved byte-for-byte (including CRLF line endings).
#   - Unset fields render as the `-` placeholder; they are never dropped.
#   - Fence markers inside Markdown code blocks (``` or ~~~, CommonMark style:
#     0-3 leading spaces, ≥3 of same char; closer ≥ opener length, same char)
#     are ignored; only real (non-code-fenced) markers are the runtime fence.
#   - Malformed marker state (orphan open, orphan close, duplicate pairs) causes a
#     non-zero exit and leaves status.md completely unchanged.
#   - goal.md is NEVER opened for writing (durable-only, REQ-DF-031).
#   - No standalone flow-state.json is authored as primary state (REQ-DF-032); the fence
#     in status.md is the only runtime store.
#
# Flags (all optional; first-write defaults fill the rest with `-`):
#   --route R              chosen route name (e.g. code-change|bugfix|arch|migration|research)
#   --phase k/n            current phase as "k/n"
#   --phases a,b,c         phase names (CSV) → rendered flow-style `[a, b, c]`
#   --checks JSON          object with any of: tests rules lint build mb_updated no_todo
#                          diff_scope acceptance (missing keys render as `-`)
#   --gate PASS|FAIL       firewall gate verdict
#   --last-verify-sha SHA  sha of the last mb-flow-verify run
#   --stall-count N        consecutive no-progress iterations
#
# Portability:
#   - single-writer lock is mkdir-based (macOS bash 3.2 has no flock)
#   - bash 3.2 safe: empty array expansion guarded with ${#arr[@]} > 0 check
#   - byte-preservation uses binary-mode read/write (newline="") to keep CRLF intact
#   - bank resolution goes through _lib.sh::mb_resolve_path
#
# Exit: 0 OK, 1 bad bank / malformed fence / write error, 2 lock timeout / internal error.

set -euo pipefail

# Use BASH_SOURCE so the script resolves its own dir even when sourced by tests.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

LOCK_TIMEOUT="${MB_FLOW_LOCK_TIMEOUT:-10}"
LOCK_TTL="${MB_FLOW_LOCK_TTL:-120}"

# Portable mtime (epoch seconds); empty if missing.
_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# Atomic mkdir lock (mirrors mb-handoff.sh::_lock_acquire). Breaks a lock older than TTL.
# On acquire, writes a unique owner token and echoes it for ownership-proof at release.
_lock_acquire() {
  local lock="$1" timeout="$2" ttl="$3" waited=0 age now token
  token="$$-${RANDOM:-0}"
  while true; do
    if mkdir "$lock" 2>/dev/null; then
      printf '%s' "$token" > "$lock/owner" 2>/dev/null || true
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

# Release a lock ONLY if we still own it (token compare guards against a newer writer).
_lock_release() {
  local lock="$1" token="${2:-}" current
  [ -z "$token" ] && return 0
  current="$(cat "$lock/owner" 2>/dev/null || true)"
  if [ "$current" = "$token" ]; then
    rm -rf "$lock" 2>/dev/null || true
  fi
}

usage() {
  sed -n '2,42p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Regenerate the fence under a single-writer lock with copy-then-atomic-rename.
# FIX-CYCLE1 Defect 1: called without extra args when pass_through is empty, so
# we never expand an empty array under set -u (bash 3.2 "unbound variable" bug).
sync_flow() {
  local mb="$1"; shift
  local status_file="$mb/status.md"
  local lock="$mb/.flow.lock"

  mkdir -p "$mb"

  local token
  if ! token="$(_lock_acquire "$lock" "$LOCK_TIMEOUT" "$LOCK_TTL")"; then
    printf '[mb-flow-sync] could not acquire lock %s within %ss\n' "$lock" "$LOCK_TIMEOUT" >&2
    return 2
  fi
  # shellcheck disable=SC2064
  trap "_lock_release '$lock' '$token'" EXIT

  local tmp="$mb/.status.flow.tmp.$$"
  # Render into a temp file; Python handles fence detection, byte-preservation, and
  # CRLF-safe I/O. status.md is the ONLY file this script writes; goal.md is never opened.
  if ! MB_FLOW_STATUS="$status_file" MB_FLOW_TMP="$tmp" \
        "${MB_PYTHON:-python3}" - "$@" <<'PY'
import json
import os
import re
import sys

status_path = os.environ["MB_FLOW_STATUS"]
tmp_path = os.environ["MB_FLOW_TMP"]

PLACEHOLDER = "-"
CHECK_KEYS = [
    "tests", "rules", "lint", "build",
    "mb_updated", "no_todo", "diff_scope", "acceptance",
]
FENCE_OPEN  = "<!-- mb-flow -->"
FENCE_CLOSE = "<!-- /mb-flow -->"

# ---------------------------------------------------------------------------
# Flag parser
# ---------------------------------------------------------------------------
args = sys.argv[1:]
opts = {
    "route": None,
    "phase": None,
    "phases": None,
    "checks": None,
    "gate": None,
    "last-verify-sha": None,
    "stall-count": None,
}
i = 0
while i < len(args):
    a = args[i]
    if a.startswith("--"):
        key = a[2:]
        if key not in opts:
            print(f"[mb-flow-sync] unknown flag: {a}", file=sys.stderr)
            sys.exit(1)
        if i + 1 >= len(args):
            print(f"[mb-flow-sync] flag {a} needs a value", file=sys.stderr)
            sys.exit(1)
        opts[key] = args[i + 1]
        i += 2
    else:
        print(f"[mb-flow-sync] unexpected argument: {a}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Field renderers
# ---------------------------------------------------------------------------
def render_scalar(v):
    v = (v or "").strip()
    return v if v else PLACEHOLDER


def render_phases(raw):
    if raw is None:
        return PLACEHOLDER
    items = [p.strip() for p in raw.split(",") if p.strip()]
    if not items:
        return PLACEHOLDER
    return "[" + ", ".join(items) + "]"


def render_checks(raw):
    parsed = {}
    if raw:
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as exc:
            print(f"[mb-flow-sync] --checks is not valid JSON: {exc}", file=sys.stderr)
            sys.exit(1)
        if not isinstance(parsed, dict):
            print("[mb-flow-sync] --checks must be a JSON object", file=sys.stderr)
            sys.exit(1)
    parts = []
    for k in CHECK_KEYS:
        val = parsed.get(k)
        val = str(val).strip() if val is not None and str(val).strip() else PLACEHOLDER
        parts.append(f"{k}: {val}")
    return "{ " + ", ".join(parts) + " }"


# ---------------------------------------------------------------------------
# FIX-CYCLE2: CommonMark-compliant fenced-code-block detector.
#
# A code fence opener is: 0-3 leading spaces, then a run of ≥3 of the SAME
# character (all backticks OR all tildes).  A closer must use the SAME char
# and a run of AT LEAST the opener length (trailing whitespace allowed).
# A line of a DIFFERENT char, or a SHORTER run, does NOT close the fence.
# Markers are "real" only when found OUTSIDE any open code fence.
#
# Returns a list of (line_index, marker_type) tuples where marker_type is
# "open" or "close", only for markers that are NOT inside a code block.
# ---------------------------------------------------------------------------
def find_real_fence_markers(lines):
    """Return list of (lineno, 'open'|'close') for markers outside code blocks."""
    # opener_re captures: up to 3 leading spaces, then the fence char and run.
    opener_re = re.compile(r"^( {0,3})(`{3,}|~{3,})")
    in_code = False
    code_char = ""
    code_len = 0
    result = []
    for idx, line in enumerate(lines):
        bare = line.rstrip("\r\n")
        m = opener_re.match(bare)
        if not in_code:
            if m:
                fence_run = m.group(2)
                after = bare[m.end():]
                # CommonMark: a BACKTICK fence's info string may NOT contain a
                # backtick (tilde fences are exempt). A line like ```js`weird is
                # therefore NOT a valid opener — treat it as ordinary text so any
                # real mb-flow markers that follow are not hidden inside phantom code.
                if not (fence_run[0] == "`" and "`" in after):
                    code_char = fence_run[0]
                    code_len = len(fence_run)
                    in_code = True
                    continue  # opener line: never a marker
        else:
            # Inside a code block: look for a closing fence.
            # Closer: 0-3 leading spaces, ≥ opener-length of the SAME char,
            # then only optional trailing whitespace.
            if m:
                fence_run = m.group(2)
                if fence_run[0] == code_char and len(fence_run) >= code_len:
                    # Trailing content after the fence run must be whitespace only.
                    after = bare[m.end():]
                    if not after.strip():
                        in_code = False
                        code_char = ""
                        code_len = 0
                        continue  # closer line: never a marker
            # Still inside: skip marker check.
            continue
        # Outside a code block: check for runtime markers (exact match after
        # stripping line endings; leading/trailing spaces are NOT stripped
        # because the markers themselves must appear verbatim at the line start).
        if bare == FENCE_OPEN:
            result.append((idx, "open"))
        elif bare == FENCE_CLOSE:
            result.append((idx, "close"))
    # `in_code` is still True iff EOF was reached inside an unterminated fence —
    # the caller treats that as "no safe insertion point outside code".
    return result, in_code


def validate_markers(markers):
    """
    Validate that markers are either:
      - [] (no fence yet — first write)
      - [(i,'open'), (j,'close')] with i < j (exactly one well-formed pair)
    Returns (is_valid, error_message_or_none, open_lineno_or_None, close_lineno_or_None).
    """
    if not markers:
        return True, None, None, None
    if len(markers) == 2:
        (i, t1), (j, t2) = markers
        if t1 == "open" and t2 == "close" and i < j:
            return True, None, i, j
    # Any other count or order is malformed.
    types = [t for _, t in markers]
    msg = (
        f"[mb-flow-sync] malformed fence state in status.md: found {len(markers)} "
        f"real marker(s) {types}; expected 0 or exactly one open/close pair. "
        "Fix status.md manually and re-run."
    )
    return False, msg, None, None


# ---------------------------------------------------------------------------
# Build the replacement fence block (always LF line endings — it's newly generated).
# ---------------------------------------------------------------------------
route     = render_scalar(opts["route"])
phase     = render_scalar(opts["phase"])
phases    = render_phases(opts["phases"])
checks    = render_checks(opts["checks"])
gate      = render_scalar(opts["gate"])
last_sha  = render_scalar(opts["last-verify-sha"])
stall     = render_scalar(opts["stall-count"])

body = "\n".join([
    f"route: {route}",
    f"current_phase: {phase}",
    f"phases: {phases}",
    f"checks: {checks}",
    f"gate: {gate}",
    f"last_verify_sha: {last_sha}",
    f"stall_count: {stall}",
])
new_block_str = f"{FENCE_OPEN}\n{body}\n{FENCE_CLOSE}\n"
new_block_bytes = new_block_str.encode("utf-8")

# ---------------------------------------------------------------------------
# FIX-CYCLE1 Defect 3: Read in binary mode (newline="") so CRLF bytes are
# preserved exactly. We work with the raw bytes for the outside regions and
# only touch the fence span.
# ---------------------------------------------------------------------------
if os.path.exists(status_path):
    with open(status_path, "rb") as fh:
        raw_bytes = fh.read()
else:
    raw_bytes = b""

# Decode as UTF-8 text (keeping line endings intact via splitlines(keepends=True))
# for line-aware fence detection, then reconstruct bytes from slices.
text = raw_bytes.decode("utf-8")
lines = text.splitlines(keepends=True)

markers, eof_in_code = find_real_fence_markers(lines)
valid, err_msg, open_idx, close_idx = validate_markers(markers)
if not valid:
    print(err_msg, file=sys.stderr)
    sys.exit(1)
if eof_in_code and open_idx is None:
    # No existing mb-flow pair to update in place, AND status.md ends inside an
    # unterminated Markdown code fence: appending the fence at EOF would bury it
    # INSIDE that open code block (breaking idempotency on the next run). There is
    # no safe insertion point — fail loud, leave status.md byte-unchanged.
    # (When a real pair DOES exist we update it in place and the trailing content,
    # broken fence included, is preserved verbatim — so that case is allowed.)
    print(
        "[mb-flow-sync] status.md ends inside an unterminated Markdown code "
        "fence — no safe place to write the mb-flow fence. Fix status.md and re-run.",
        file=sys.stderr,
    )
    sys.exit(1)

if open_idx is None:
    # --- First write: append a fresh fence, preserving prior bytes exactly. ---
    if raw_bytes == b"":
        new_bytes = new_block_bytes
    elif raw_bytes.endswith(b"\n\n"):
        new_bytes = raw_bytes + new_block_bytes
    elif raw_bytes.endswith(b"\n"):
        new_bytes = raw_bytes + b"\n" + new_block_bytes
    else:
        new_bytes = raw_bytes + b"\n\n" + new_block_bytes
else:
    # --- Replace exactly the open→close span (byte offsets), preserving everything
    # outside in raw binary form.
    # Compute byte offset of the start of the open-marker line.
    prefix_bytes = "".join(lines[:open_idx]).encode("utf-8")
    # Byte offset of end of the close-marker line (including its trailing newline).
    suffix_start_line = close_idx + 1
    if suffix_start_line < len(lines):
        suffix_bytes = "".join(lines[suffix_start_line:]).encode("utf-8")
    else:
        suffix_bytes = b""
    new_bytes = prefix_bytes + new_block_bytes + suffix_bytes

# Write to tmp; the shell does the atomic rename.
with open(tmp_path, "wb") as fh:
    fh.write(new_bytes)
PY
  then
    rm -f "$tmp" 2>/dev/null || true
    _lock_release "$lock" "$token"
    trap - EXIT
    printf '[mb-flow-sync] fence render failed\n' >&2
    return 1
  fi

  # Atomic replace: the old status.md stays intact until this rename succeeds.
  mv -f "$tmp" "$status_file"

  _lock_release "$lock" "$token"
  trap - EXIT

  printf '[mb-flow-sync] status=%s\n' "$status_file"
  return 0
}

main() {
  local mb_arg=""
  # FIX-CYCLE1 Defect 1: Use an explicit counter instead of relying on an array
  # that may be empty, which triggers "unbound variable" under bash 3.2 set -u.
  # We still collect into pass_through[] but guard the call site with ${#} > 0.
  local pass_through
  pass_through=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --route|--phase|--phases|--checks|--gate|--last-verify-sha|--stall-count)
        if [ "$#" -lt 2 ]; then
          printf '[mb-flow-sync] flag %s needs a value\n' "$1" >&2
          return 1
        fi
        pass_through+=("$1" "$2")
        shift 2
        ;;
      --)
        shift
        ;;
      -*)
        printf '[mb-flow-sync] unknown flag: %s\n' "$1" >&2
        usage >&2
        return 1
        ;;
      *)
        if [ -z "$mb_arg" ]; then
          mb_arg="$1"
        else
          printf '[mb-flow-sync] unexpected argument: %s\n' "$1" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  local mb
  mb="$(mb_resolve_path "$mb_arg")"
  if [ ! -d "$mb" ]; then
    printf '[mb-flow-sync] .memory-bank not found at: %s\n' "$mb" >&2
    return 1
  fi

  # FIX-CYCLE1 Defect 1: Guard expansion of pass_through — bash 3.2 raises
  # "unbound variable" for "${empty_array[@]}" under set -u. By checking the
  # count first, we never expand an empty array.
  if [ "${#pass_through[@]}" -gt 0 ]; then
    sync_flow "$mb" "${pass_through[@]}"
  else
    sync_flow "$mb"
  fi
}

main "$@"
