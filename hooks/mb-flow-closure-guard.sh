#!/usr/bin/env bash
# mb-flow-closure-guard.sh — Claude Code Stop-hook closure gate (dynamic-flow
# Task 6, REQ-DF-045).
#
# When a dynamic-flow is active, this hook gates "finished" on THE firewall
# (scripts/mb-flow-verify.sh — the SOLE exit-code authority, Task 5). A red
# verify physically BLOCKS the stop so the agent cannot declare done on red.
#
# CC Stop-hook contract:
#   - A JSON object arrives on STDIN (fields incl. `stop_hook_active`, `cwd`).
#   - To BLOCK the stop: print {"decision":"block","reason":"<text>"} on stdout
#     and exit 0. The host shows the reason and keeps the turn going.
#   - To ALLOW: exit 0 with NO decision (an empty/absent decision = allow).
#   - LOOP-GUARD: if `stop_hook_active` is true the host is RE-entering after a
#     prior block — we MUST allow immediately, or we wedge an infinite stop loop.
#
# Flow-active predicate (REQ-DF-045): a flow is active IFF <bank>/goal.md exists
#   AND its frontmatter `status:` is `active` (or absent — back-compat). With no
#   goal.md, a paused/done goal, or MB_FLOW_CLOSURE=off, the gate is INERT
#   (allow) so it never blocks unrelated stops on a bank not running a flow.
#
# Cost contract (I-131). This hook runs on EVERY Stop, so it must never wait on
#   the whole test battery:
#     - MB_FLOW_VERIFY_SKIP (default `tests`) drops the whole-suite check from
#       the firewall's default set — the remaining four take about a second.
#     - MB_FLOW_VERIFY_BUDGET (default 20s) hard-kills the firewall's process
#       GROUP on overrun and degrades to allow-with-systemMessage.
#     - MB_FLOW_VERIFY_CACHE reuses the verdict while the tree is unchanged.
#   Red tests still have their own gates: /mb work's verify step, /mb drive, and
#   a manual scripts/mb-flow-verify.sh run.
#
# Exit-code mapping from the firewall:
#   verify exit 0 → allow (closure certified).
#   verify exit 1 → block ("a red verify"): name the red + how to repair.
#   verify exit 2 → block ("a check script broke; cannot certify closure").
#
# Fail-safe: ANY infrastructure problem (empty/garbage stdin, missing jq/python3,
# missing firewall, unreadable bank) resolves to ALLOW (exit 0). A closure gate
# must never WEDGE a session — its job is to block a *certified-red* flow, not to
# punish a broken toolchain. The firewall's own stderr is captured, never leaked
# as a hard error.
#
# Bank resolution (Defect 1 fix): uses mb_hook_resolve_mb_path from
# hooks/_skill_root.sh — the global-aware resolver (MB_PATH → <cwd>/.memory-bank
# → registry) that every other hook uses, so global-storage banks are visible.
#
# Stdin discipline (Defect 3 fix): parse success is tracked explicitly. When
# stdin is empty, non-JSON, or not a JSON object, the hook allows BEFORE
# resolving CWD/bank — it never falls back to $PWD and runs the firewall on a
# red cwd. Only a successfully-parsed JSON object can drive CWD resolution.

set -u

# Kill-switch (I-131 b): MB_FLOW_CLOSURE=off disables the gate entirely, the same
# opt-out shape every other MB layer carries.
[ "${MB_FLOW_CLOSURE:-on}" = "off" ] && exit 0

# Loop-guard sentinel for our own subprocess re-entry (mirrors mb-session-turn.sh).
[ -n "${MB_CAPTURE_SUBPROCESS:-}" ] && exit 0

# ---------------------------------------------------------------------------
# Allow helper — the safe default. Print nothing + exit 0.
# ---------------------------------------------------------------------------
allow() {
  exit 0
}

# Block helper — emit the CC block JSON and exit 0 (a block is still exit 0).
block() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
  else
    # Bash-only fallback: hand-roll the JSON, escaping backslashes then quotes.
    local esc="$reason"
    esc="${esc//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    printf '{"decision":"block","reason":"%s"}\n' "$esc"
  fi
  exit 0
}

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || allow

# ---------------------------------------------------------------------------
# Source the global-aware bank resolver early (Defect 1 fix).
# The functions it defines are used below in bank resolution.
# If _skill_root.sh is absent we still degrade safely via allow().
# ---------------------------------------------------------------------------
if [ -f "$HOOK_DIR/_skill_root.sh" ]; then
  # shellcheck source=hooks/_skill_root.sh
  . "$HOOK_DIR/_skill_root.sh"
fi

# ---------------------------------------------------------------------------
# Read + parse stdin (guarded). Empty / unparseable → allow IMMEDIATELY,
# before resolving CWD (Defect 3 fix: a successful parse is REQUIRED before
# any bank lookup; we must not fall back to $PWD on a parse failure).
# ---------------------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"

STOP_ACTIVE="false"
CWD=""
PARSE_OK="false"   # Defect 3: track whether stdin was a valid JSON object.

if [ -n "$INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    # jq exits non-zero on invalid JSON. Check that the input IS a JSON object
    # before extracting fields — an invalid input must not fall through to $PWD.
    if printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
      PARSE_OK="true"
      STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
      CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    # A heredoc nested inside $(...) mis-parses on /bin/bash 3.2 (same gotcha the
    # firewall documents), so route the python output through a temp file.
    _pjson="$(mktemp 2>/dev/null || echo "/tmp/mb-closure-parse.$$")"
    MB_GUARD_INPUT="$INPUT" python3 - >"$_pjson" 2>/dev/null <<'PY' || true
import json
import os

try:
    obj = json.loads(os.environ.get("MB_GUARD_INPUT", ""))
    if not isinstance(obj, dict):
        raise ValueError
except Exception:
    # Not a JSON object — signal parse failure with a special prefix.
    print("FAIL\t")
else:
    active = "true" if obj.get("stop_hook_active") is True else "false"
    print("OK\t" + active + "\t" + (obj.get("cwd") or ""))
PY
    _parsed="$(head -n1 "$_pjson" 2>/dev/null || true)"
    rm -f "$_pjson"
    case "$_parsed" in
      OK*)
        PARSE_OK="true"
        _rest="${_parsed#OK	}"
        STOP_ACTIVE="${_rest%%	*}"
        CWD="${_rest#*	}"
        [ "$STOP_ACTIVE" = "true" ] || STOP_ACTIVE="false"
        ;;
      *)
        # FAIL or empty — parse failed; allow immediately (Defect 3).
        PARSE_OK="false"
        ;;
    esac
  fi
fi

# Defect 3: if stdin was empty or unparseable, allow immediately.
# Do NOT fall back to $PWD — that could fire the firewall on a red cwd.
[ "$PARSE_OK" = "true" ] || allow

# LOOP-GUARD: a re-entrant Stop (host already blocked once) must ALWAYS allow.
[ "$STOP_ACTIVE" = "true" ] && allow

# CWD from parsed JSON; fall back to $PWD only when the JSON had no usable cwd
# (Defect 3: the fallback now happens ONLY after a successful parse).
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

# ---------------------------------------------------------------------------
# Resolve the bank via the global-aware resolver (Defect 1 fix).
# mb_hook_resolve_mb_path: MB_PATH → <cwd>/.memory-bank → registry lookup.
# If the resolver is available, use it; otherwise fall back to the two-step
# MB_PATH / local check (mirrors the pre-fix behavior but keeps the safe path).
# ---------------------------------------------------------------------------
BANK=""
if command -v mb_hook_resolve_mb_path >/dev/null 2>&1; then
  BANK="$(mb_hook_resolve_mb_path "$CWD" 2>/dev/null || true)"
else
  # _skill_root.sh was absent — minimal two-step fallback.
  if [ -n "${MB_PATH:-}" ]; then
    BANK="$MB_PATH"
  elif [ -d "$CWD/.memory-bank" ]; then
    BANK="$CWD/.memory-bank"
  fi
fi

# Flow-active predicate: inert unless the bank exists AND carries a goal.md.
[ -n "$BANK" ] || allow
[ -d "$BANK" ] || allow
[ -f "$BANK/goal.md" ] || allow

# Also inert unless that goal is actually being driven (I-131 a). A `status:` of
# anything other than `active` — paused, done, abandoned — is not a running flow,
# so gating a stop on it costs a wedge and buys nothing. A goal.md with no
# frontmatter status keeps the original behaviour (gate on existence alone).
_goal_status="$(sed -n '1,20{/^status:[[:space:]]*/{s/^status:[[:space:]]*//;s/[[:space:]]*$//;p;q;};}' \
  "$BANK/goal.md" 2>/dev/null || true)"
if [ -n "$_goal_status" ] && [ "$_goal_status" != "active" ]; then
  allow
fi

# ---------------------------------------------------------------------------
# Locate the firewall. The hook lives in hooks/, the firewall in scripts/ — both
# siblings under the skill root. Fall back to the shared resolver for installed
# layouts where hooks/ and scripts/ are not co-located under one parent.
# ---------------------------------------------------------------------------
VERIFY="$HOOK_DIR/../scripts/mb-flow-verify.sh"
if [ ! -f "$VERIFY" ]; then
  if command -v mb_skill_script_path >/dev/null 2>&1; then
    _resolved="$(mb_skill_script_path "mb-flow-verify.sh" "$HOOK_DIR" 2>/dev/null || true)"
    [ -n "$_resolved" ] && VERIFY="$_resolved"
  fi
fi
# Firewall missing → cannot certify; fail SAFE (allow), never wedge the session.
[ -f "$VERIFY" ] || allow

# ---------------------------------------------------------------------------
# Light-mode verdict cache (MB_FLOW_VERIFY_CACHE, default on; off to disable).
# The firewall's verdict is a pure function of the working tree (HEAD + diff +
# untracked files) plus goal.md. Re-running its full check suite on EVERY Stop is
# wasteful when the tree is byte-identical to the last verified state. Cache the
# exit code keyed by a content signature: an unchanged tree reuses the prior
# verdict; ANY tracked change or untracked-file change busts the cache and
# re-runs. This can never weaken the gate — identical tree ⇒ identical verdict,
# so a cached red still blocks. Fail-open: any signature error falls through to a
# real run. TTL backstop (MB_FLOW_VERIFY_CACHE_TTL, default 3600s) bounds staleness
# from out-of-tree factors (e.g. a toolchain change git cannot see).
# ---------------------------------------------------------------------------
VERIFY_RC=""
_cache_mode="${MB_FLOW_VERIFY_CACHE:-on}"
_cache_ttl="${MB_FLOW_VERIFY_CACHE_TTL:-3600}"
_sig=""
_cache_file="$BANK/tmp/flow-verify-cache"
if [ "$_cache_mode" != "off" ]; then
  _root="$(cd "$BANK/.." 2>/dev/null && pwd || true)"
  _sig="$(MB_FV_ROOT="$_root" python3 - 2>/dev/null <<'PY' || true
import os, subprocess, hashlib
root = os.environ.get("MB_FV_ROOT") or "."
def git(*a):
    return subprocess.run(["git", "-C", root, *a], capture_output=True, text=True).stdout
try:
    head = git("rev-parse", "HEAD").strip()
    diff = git("diff", "HEAD")
    # Exclude the bank's scratch dir: the cache file itself lives under
    # .memory-bank/tmp/ as an untracked file — including it would mutate the
    # signature on every write and defeat the cache (perpetual miss). The
    # firewall's verdict never depends on scratch.
    others = [
        p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
        if p and "/.memory-bank/tmp/" not in ("/" + p) and not p.startswith(".memory-bank/tmp/")
    ]
    h = hashlib.sha256()
    h.update(head.encode()); h.update(b"\0")
    h.update(diff.encode("utf-8", "replace")); h.update(b"\0")
    for p in sorted(others):
        h.update(p.encode("utf-8", "replace")); h.update(b"\0")
        try:
            with open(os.path.join(root, p), "rb") as fh:
                h.update(hashlib.sha256(fh.read()).digest())
        except OSError:
            h.update(b"?")
        h.update(b"\0")
    print(h.hexdigest())
except Exception:
    pass
PY
)"
  if [ -n "$_sig" ] && [ -f "$_cache_file" ]; then
    _c_sig="$(cut -d' ' -f1 "$_cache_file" 2>/dev/null || true)"
    _c_rc="$(cut -d' ' -f2 "$_cache_file" 2>/dev/null || true)"
    _c_ts="$(cut -d' ' -f3 "$_cache_file" 2>/dev/null || echo 0)"
    _now="$(date +%s 2>/dev/null || echo 0)"
    if [ "$_c_sig" = "$_sig" ] && [ -n "$_c_rc" ] && [ "$(( _now - ${_c_ts:-0} ))" -lt "$_cache_ttl" ]; then
      VERIFY_RC="$_c_rc"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Run the firewall ONLY for its exit code (cache miss). Its stdout (the JSON
# summary) and stderr (breach lines) are both discarded here so neither leaks
# into the Stop event nor surfaces as a hard hook error — exit code is the whole
# contract. Cache only the contracted 0/1/2 verdicts (never a transient infra
# fault like 127) so a fixed check re-runs cleanly.
# ---------------------------------------------------------------------------
if [ -z "$VERIFY_RC" ]; then
  # Hard time budget (MB_FLOW_VERIFY_BUDGET, default 20s; `off`/`0` restores the
  # unbounded wait). The firewall's default check set includes `tests`, i.e. the
  # project's WHOLE suite — minutes on a real repo — and a Stop hook that waits
  # for it wedges the session instead of ending it. An overrun is an
  # infrastructure fault like a missing firewall, so it takes the same fail-safe
  # exit: allow, uncached, and say so rather than pretend closure was certified.
  _budget="${MB_FLOW_VERIFY_BUDGET:-20}"

  # Which checks the Stop path drops (MB_FLOW_VERIFY_SKIP, default `tests`; set
  # it empty to run the firewall's full default set). `tests` is the project's
  # entire suite — the one check no interactive hook can wait for — while the
  # remaining four run in about a second and still yield a REAL verdict rather
  # than the budget's degraded "could not certify". Red tests keep their own
  # gates: /mb work's verify step, /mb drive, and a manual mb-flow-verify run.
  _skip="${MB_FLOW_VERIFY_SKIP-tests}"
  set -- "$BANK"
  [ -n "$_skip" ] && set -- "$@" --skip "$_skip"

  if [ "$_budget" = "off" ] || [ "$_budget" = "0" ] || ! command -v python3 >/dev/null 2>&1; then
    bash "$VERIFY" "$@" >/dev/null 2>&1
    VERIFY_RC=$?
  else
    # python3 owns the watchdog: it can start the firewall in its own session
    # and kill the whole PROCESS GROUP on overrun. Killing just the wrapper
    # would leave the fan-out's children (pytest, bats, linters) running.
    _rcf="$(mktemp 2>/dev/null || echo "/tmp/mb-closure-rc.$$")"
    # Args go through separate env vars, never one flattened string: a bank path
    # with a space would not survive re-splitting.
    MB_FV_VERIFY="$VERIFY" MB_FV_BANK="$BANK" MB_FV_SKIP="$_skip" MB_FV_BUDGET="$_budget" \
      python3 - >"$_rcf" 2>/dev/null <<'PY' || true
import os
import signal
import subprocess

try:
    budget = float(os.environ.get("MB_FV_BUDGET", "20"))
except ValueError:
    budget = 20.0

argv = ["bash", os.environ["MB_FV_VERIFY"], os.environ["MB_FV_BANK"]]
if os.environ.get("MB_FV_SKIP"):
    argv += ["--skip", os.environ["MB_FV_SKIP"]]

proc = subprocess.Popen(
    argv,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
)
try:
    print(proc.wait(timeout=budget))
except subprocess.TimeoutExpired:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(os.getpgid(proc.pid), sig)
        except OSError:
            break
        try:
            proc.wait(timeout=2)
            break
        except subprocess.TimeoutExpired:
            continue
    print("TIMEOUT")
PY
    VERIFY_RC="$(head -n1 "$_rcf" 2>/dev/null || true)"
    rm -f "$_rcf"
    if [ "$VERIFY_RC" = "TIMEOUT" ]; then
      # Honest degradation: the gate did not run to a verdict, so it certifies
      # nothing — allow, and report that instead of a silent green.
      printf '{"systemMessage":"Closure gate skipped: mb-flow-verify exceeded its %ss budget (MB_FLOW_VERIFY_BUDGET) and was killed. The flow was NOT certified — run scripts/mb-flow-verify.sh manually before treating it as finished."}\n' "$_budget"
      exit 0
    fi
    [ -n "$VERIFY_RC" ] || allow
  fi
  if [ "$_cache_mode" != "off" ] && [ -n "$_sig" ]; then
    case "$VERIFY_RC" in
      0|1|2)
        mkdir -p "$BANK/tmp" 2>/dev/null || true
        printf '%s %s %s\n' "$_sig" "$VERIFY_RC" "$(date +%s 2>/dev/null || echo 0)" \
          > "$_cache_file" 2>/dev/null || true
        ;;
    esac
  fi
fi

case "$VERIFY_RC" in
  0)
    allow
    ;;
  1)
    block "Dynamic-flow closure blocked: mb-flow-verify reported a red flow (verify exit 1). The flow is NOT finished — repair the breach and re-run mb-flow-verify until it exits 0 before stopping."
    ;;
  2)
    block "Dynamic-flow closure blocked: a check script broke (mb-flow-verify exit 2) — cannot certify closure. Fix the broken check, then re-run mb-flow-verify before stopping."
    ;;
  *)
    # The firewall is contracted to 0/1/2. Anything else means the firewall ITSELF
    # could not run (e.g. 127). Infrastructure fault → fail SAFE (allow).
    allow
    ;;
esac
