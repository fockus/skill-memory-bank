#!/usr/bin/env bash
# hooks/mb-update-notify.sh — SessionStart hook: "a newer release is out" notice.
#
# The contract is silence: an up-to-date user sees NOTHING on stdout — not
# even a "you're current" line. Only an "update available" answer produces a
# short (<=3 line) notice naming current -> latest and the exact command for
# the DETECTED install flavor (a pipx user is never told `git pull`). Every
# other path — disabled, missing/broken resolver, garbage JSON, a malformed
# "available" answer, a HANGING resolver, a resolver that never stops
# writing — also produces nothing. This hook never writes to stderr, never
# touches the bank, and exits 0 unconditionally: a hook that can hang,
# crash, or nag gets disabled by users, and then the whole feature is worth
# less than nothing.
#
# This hook does not know how to check for an update itself — that is
# scripts/mb-version-check.sh's job (the single authority for that
# question). This hook only renders ITS answer, and only when interesting.
#
# Design: THIS HOOK NEVER TOUCHES THE NETWORK. It calls the resolver with
# `--cache-only` (local disk only — no curl, no fork of a fetch at all), so
# the normal case is a handful of local forks, not a network round trip
# (the resolver's own network path is bounded up to ~6s on a slow link —
# `curl --max-time 3` for GitHub plus 3 more for the PyPI fallback — which
# is why a synchronous SessionStart call used to either block a session or
# get killed by its own watchdog before a legitimate slow answer arrived).
# When the cache is missing/stale (source: cache-miss), this hook
# fire-and-forgets a DETACHED background resolver run in its normal
# (network-allowed) mode so the cache is warm for the NEXT session — see
# the "source: cache-miss" comment below for the detachment contract. A
# brand-new install therefore shows its first notice one session later
# than it theoretically could; a session that never stalls is worth that
# trade every time.
#
# Env:
#   MB_UPDATE_CHECK=off        short-circuit before the resolver is even
#                              invoked (cheapest possible path: no fork at
#                              all) — and no background refresh either.
#   MB_VERSION_CHECK_BIN       override the resolver binary (tests /
#                              advanced) — same seam pattern
#                              mb-version-check.sh itself uses for
#                              MB_VERSION_CHECK_FETCH_BIN. Default: resolved
#                              via the shared _skill_root.sh helper, so this
#                              hook finds scripts/mb-version-check.sh
#                              whether it's running from the repo, a
#                              flattened ~/.claude/hooks/ copy, or the
#                              ~/.claude/skills/memory-bank/ bundle.
#   MB_UPDATE_NOTIFY_TIMEOUT   watchdog deadline, seconds, for the resolver
#                              call. Default 2 — the `--cache-only` resolver
#                              call is local-only and normally answers in a
#                              handful of milliseconds; this only bounds
#                              the pathological case (a hanging stub, a
#                              wedged filesystem/cache read), a backstop
#                              against pathology rather than a race against
#                              the network (the network call, if any, now
#                              happens in the detached background refresh,
#                              which this watchdog does not — and must
#                              not — bound). This hook owns its own timeout
#                              rather than trusting the resolver's internal
#                              `curl --max-time` — MB_VERSION_CHECK_BIN is a
#                              supported override seam that bypasses the
#                              resolver (and its curl call) entirely.
#   MB_UPDATE_NOTIFY_MAX_BYTES cap on the resolver's captured stdout.
#                              Default 65536 (matches the resolver's own
#                              MB_VERSION_CHECK_MAX_BODY default) — an
#                              infinite-output stub is the same denial of a
#                              session start as a hang, and is bounded
#                              separately from the time-based watchdog.
#
# Portability note: this hook does NOT depend on `timeout(1)` — it is GNU
# coreutils and absent on stock macOS bash (`gtimeout` requires Homebrew
# coreutils). The watchdog below is hand-rolled from `set -m` + a negative-
# PID `kill` so the resolver's whole process group (including anything it
# forks, e.g. curl) is reaped on timeout, not just its own PID — no orphans,
# and no shell job-control "Terminated" notice on stderr (verified on both
# bash 3.2 and bash 5.x, macOS and Linux).
set -u

# Absolute first short-circuit, before any fork (flavor detection inside the
# resolver can fork `brew --prefix`) — the cheapest possible disabled path.
[ "${MB_UPDATE_CHECK:-on}" = "off" ] && exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || exit 0

CHECK_BIN="${MB_VERSION_CHECK_BIN:-}"
if [ -z "$CHECK_BIN" ] && [ -f "$HOOK_DIR/_skill_root.sh" ]; then
  # shellcheck source=hooks/_skill_root.sh
  . "$HOOK_DIR/_skill_root.sh"
  CHECK_BIN="$(mb_skill_script_path "mb-version-check.sh" "$HOOK_DIR" 2>/dev/null || true)"
fi
[ -n "$CHECK_BIN" ] || exit 0
[ -r "$CHECK_BIN" ] || exit 0

MB_UAN_TIMEOUT="${MB_UPDATE_NOTIFY_TIMEOUT:-2}"
MB_UAN_MAX_BYTES="${MB_UPDATE_NOTIFY_MAX_BYTES:-65536}"
# Digit-only validation, same '' | *[!0-9]* shape check used elsewhere in
# this repo's shell scripts — an invalid override (e.g. `abc`) falls back
# to the default BEFORE it ever reaches `head -c`, whose own stderr
# ("head: illegal byte count -- abc") is not covered by the resolver's
# `2>/dev/null` a few lines below (that redirect only silences the
# resolver, not `head`). This hook's contract is zero stderr bytes on
# every input, valid or not.
case "$MB_UAN_MAX_BYTES" in ''|*[!0-9]*) MB_UAN_MAX_BYTES=65536 ;; esac

# Scratch files for the watchdog below — a plain tmp dir, never the bank.
# Any failure to even create them degrades to silence, same as every other
# path in this hook.
MB_UAN_TMP_BASE="${TMPDIR:-/tmp}"
MB_UAN_OUT="$(mktemp "$MB_UAN_TMP_BASE/mb-update-notify-out.XXXXXX" 2>/dev/null)" || exit 0
MB_UAN_RC="$(mktemp "$MB_UAN_TMP_BASE/mb-update-notify-rc.XXXXXX" 2>/dev/null)" || {
  rm -f "$MB_UAN_OUT"
  exit 0
}
trap 'rm -f "$MB_UAN_OUT" "$MB_UAN_RC"' EXIT

# Run via `bash`, not direct exec — a resolver that lost its +x bit (or a
# test stub that forgot to chmod) still answers; this hook only reads its
# stdout, it never depends on it being independently executable.
#
# The pipe through `head -c` bounds captured bytes; `${PIPESTATUS[0]}` (not
# the pipeline's own exit code, which is head's) is the resolver's real exit
# status. `set -m` gives the backgrounded pipeline its own process group
# (PGID == the subshell's PID) so a timeout can kill the resolver AND every
# process it forked with one negative-PID signal, instead of leaving
# orphans behind. The WATCHDOG (the `sleep` timer below) is backgrounded
# under `set -m` too, for the same reason and one more: `sleep` inherits
# this hook's own stdout fd. Every SessionStart transport reads that fd to
# EOF, not just watches this process exit — so a `sleep` that outlives the
# hook (reaped only as a lone PID, its own `sleep` grandchild left running)
# holds that fd open and blocks the HOST, even though this hook's own
# process already exited printing nothing. `set +m` is deferred until BOTH
# backgrounded jobs have their own process group, so a `kill -KILL --
# "-$pid"` on either one always reaps the timer along with its subshell —
# never just the subshell, leaving `sleep` to run out its full duration as
# an orphan. The `>/dev/null 2>&1` on the watchdog is belt-and-suspenders:
# even if the group-kill ever raced, the watchdog's own fds are never the
# hook's inherited stdout to begin with.
set -m
(
  bash "$CHECK_BIN" --cache-only 2>/dev/null | head -c "$MB_UAN_MAX_BYTES" 2>/dev/null >"$MB_UAN_OUT"
  echo "${PIPESTATUS[0]:-1}" >"$MB_UAN_RC"
) &
MB_UAN_PID=$!

(
  sleep "$MB_UAN_TIMEOUT"
  kill -KILL -- "-$MB_UAN_PID" 2>/dev/null
) >/dev/null 2>&1 &
MB_UAN_WATCHDOG=$!
set +m

wait "$MB_UAN_PID" 2>/dev/null

# The watchdog either already fired (resolver was killed) or is still
# sleeping (resolver finished on its own) — either way, kill its WHOLE
# process group now (negative PID — same reasoning as the resolver kill
# above) rather than just its subshell PID, so the `sleep` itself dies
# immediately instead of lingering for up to $MB_UAN_TIMEOUT (holding this
# hook's inherited stdout fd open the entire time) after this hook is done.
kill -KILL -- "-$MB_UAN_WATCHDOG" 2>/dev/null
wait "$MB_UAN_WATCHDOG" 2>/dev/null

rc=1
if [ -s "$MB_UAN_RC" ]; then
  rc="$(cat "$MB_UAN_RC" 2>/dev/null)"
fi
case "$rc" in
  '' | *[!0-9]*) rc=1 ;;
esac

# NUL bytes must never reach a bash command-substitution assignment — bash
# itself prints "warning: command substitution: ignored null byte in input"
# to the PARENT shell's stderr when they do (the resolver's own
# `2>/dev/null` above only silences the CHILD, not this). Strip them from
# the captured file, not from a variable that already has them: by the time
# a NUL byte is inside `$(...)`, the warning has already fired.
json="$(tr -d '\000' <"$MB_UAN_OUT" 2>/dev/null)"

[ "$rc" -eq 0 ] || exit 0
[ -n "$json" ] || exit 0

# The resolver's own contract: strict SINGLE-LINE JSON (scripts/mb-version-
# check.sh header). A multi-line answer (a truncated/garbled write, a
# malicious stub) is rejected outright rather than field-extracted — this
# also closes off any embedded-newline trick to fake extra notice lines.
case "$json" in
  *$'\n'*) exit 0 ;;
esac

# `_mb_uan_field`'s sed captures up to the FIRST unescaped-looking `"` —
# it has no JSON-escape awareness, so a value containing an escaped quote
# (`\"`, e.g. a literal `"` inside an install path) truncates the match at
# that inner quote instead of the field's real closing quote, producing a
# silently WRONG (truncated) command rather than the real one. Real
# install paths never contain a literal quote — reject outright (silence,
# same posture as the multi-line guard above) rather than risk rendering a
# half-a-command notice.
case "$json" in
  *'\"'*) exit 0 ;;
esac

# <json> <key> -> the string value of a `"key": "value"` field, or "" when
# absent/malformed. `[[:space:]]*` (not a literal space) so a tab or a
# compact `"key":"value"` (zero spaces) both still parse. POSIX BRE
# (portable to BSD and GNU sed alike).
_mb_uan_field() {
  printf '%s' "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# `source: cache-miss` (scripts/mb-version-check.sh's --cache-only contract)
# means the on-disk cache was missing/stale/corrupt: this run answered
# honestly with `update_available: false` rather than pay for a fetch.
# Fire-and-forget a normal-mode (network-allowed) resolver run in the
# background so the NEXT session finds a warm cache — this session already
# has its answer and must not wait on it.
#
# Fully detached, on purpose: `</dev/null` and `>/dev/null 2>&1` mean this
# background job shares NONE of the hook's own fds — an orphan holding
# this hook's inherited stdout open is exactly the regression a prior
# cycle shipped (a session stalling for the full watchdog timeout because
# something kept that fd alive after the hook itself had already printed
# its answer and exited). `disown` removes it from this shell's own job
# table so no "Terminated"/job-control notice can ever surface, and this
# hook never `wait`s on it — the refresh's own success or failure is none
# of this session's concern; only the NEXT session reads its result, from
# the cache. Two sessions racing this at once is safe without an extra
# lock: the resolver's own cache write is already atomic (tmp file +
# `os.replace`, verified under concurrent writers by scripts/mb-version-
# check.sh's own test suite) — worst case is a duplicate fetch, never a
# corrupt cache.
if [ "$(_mb_uan_field "$json" source)" = "cache-miss" ]; then
  ( bash "$CHECK_BIN" </dev/null >/dev/null 2>&1 & disown ) 2>/dev/null || true
fi

# <json> <key> -> the bare token (letters only — "true"/"false") of a
# `"key": true` field, or "" when absent/malformed. POSIX BRE (portable to
# BSD and GNU sed alike) — no `\|` alternation, which GNU supports but BSD/
# macOS sed does not; matching `[a-z]*` and comparing in shell sidesteps it.
_mb_uan_bool_field() {
  printf '%s' "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\([a-z]*\).*/\1/p'
}

[ "$(_mb_uan_bool_field "$json" update_available)" = "true" ] || exit 0

# Strip control bytes (NUL..US, DEL — includes ESC, so no ANSI escape
# sequence survives) from an extracted field before it is ever printed to a
# terminal. `current`/`latest`/`upgrade_command` are resolver-built today
# (scripts/mb-version-check.sh / `_lib.sh::mb_upgrade_command`), not
# attacker-controlled — but they originate from a network answer (GitHub/
# PyPI release metadata) flowing through this hook straight to a user's
# terminal, so this boundary defends itself rather than trusting the
# producer to stay honest.
_mb_uan_sanitize() {
  printf '%s' "$1" | tr -d '[:cntrl:]'
}

current="$(_mb_uan_sanitize "$(_mb_uan_field "$json" current)")"
latest="$(_mb_uan_sanitize "$(_mb_uan_field "$json" latest)")"
upgrade_command="$(_mb_uan_sanitize "$(_mb_uan_field "$json" upgrade_command)")"

# A truthy `update_available` without a usable latest/command is a malformed
# answer, not a real update to act on — stay silent rather than print a
# broken/half-empty notice.
[ -n "$latest" ] && [ -n "$upgrade_command" ] || exit 0
[ -n "$current" ] || current="unknown"

printf '[memory-bank-skill] update available: %s -> %s\n' "$current" "$latest"
printf '  upgrade: %s\n' "$upgrade_command"

# ═══ Opt-in auto-update (Stage 4) ═══
#
# Everything above this point is unconditional — the notice always prints
# when an update is available. This block ADDS an optional auto-apply on
# top of it, gated by a strict safety matrix; when any gate fails it is a
# silent no-op and the notice above is the whole story, byte-identical to
# pre-Stage-4 behaviour.
#
#   1. MB_AUTO_UPDATE unset/anything-but-"on" -> never upgrades (default off).
#   2. flavor "git" + a CLEAN working tree + update available -> runs
#      scripts/mb-upgrade.sh --force and records current -> latest.
#   3. flavor "git" + a DIRTY working tree -> refuses (never discards a
#      user's local edits), notice-only.
#   4. flavor pipx/pip/brew/unknown -> NEVER invoked; a package manager is
#      never run on the user's behalf, only ever printed (the notice above).
#   5. the upgrade command itself fails or hangs -> fail-open: the session
#      still starts, this hook still exits 0, and no false "auto-updated"
#      claim is printed.
#
# `flavor` is read straight from the resolver's OWN answer (scripts/mb-
# version-check.sh already computed it via _lib.sh::mb_install_flavor to
# build `upgrade_command` above) — one source of truth, not a second,
# independent detection that could drift from the command already printed.
if [ "${MB_AUTO_UPDATE:-off}" = "on" ]; then
  MB_AUN_FLAVOR="$(_mb_uan_sanitize "$(_mb_uan_field "$json" flavor)")"
  if [ "$MB_AUN_FLAVOR" = "git" ]; then
    # Resolve the install root independently of whichever resolver binary
    # answered above (tests routinely override MB_VERSION_CHECK_BIN with a
    # stub that never touches a real checkout) — MB_SKILL_ROOT is checked
    # FIRST by _skill_root.sh's own candidate list, so it is this block's
    # primary test seam, exactly like MB_VERSION_CHECK_BIN/MB_UPGRADE_BIN.
    if [ -z "${MB_AUN_ROOT_HELPER_LOADED:-}" ] && [ -f "$HOOK_DIR/_skill_root.sh" ]; then
      # shellcheck source=hooks/_skill_root.sh
      . "$HOOK_DIR/_skill_root.sh"
      MB_AUN_ROOT_HELPER_LOADED=1
    fi
    MB_AUN_ROOT=""
    [ -n "${MB_AUN_ROOT_HELPER_LOADED:-}" ] && MB_AUN_ROOT="$(mb_skill_root_resolve "$HOOK_DIR" 2>/dev/null || true)"

    # Defense-in-depth clean-tree gate: scripts/mb-upgrade.sh --force ALSO
    # refuses a dirty tree on its own, but this hook must never even shell
    # out to it on a dirty tree — belt AND suspenders, never discard a
    # user's local edits. `status --porcelain` empty AND git itself exiting
    # 0 (a non-repo/broken git call is treated as "not provably clean",
    # never as "clean" by an empty-but-erroring capture).
    #
    # `--untracked-files=all --ignore-submodules=none` are explicit, not
    # left to config: a plain `status --short`/`status --porcelain` honours
    # user/repo config like `status.showUntrackedFiles=no` or a submodule
    # ignore setting, so a repo configured that way could hide real
    # untracked/submodule changes and be misread as clean here. Passing
    # both flags explicitly makes this check config-independent — it always
    # sees the full truth, regardless of what the user's/repo's git config
    # says.
    if [ -n "$MB_AUN_ROOT" ] && [ -d "$MB_AUN_ROOT/.git" ] \
      && MB_AUN_STATUS="$(git -C "$MB_AUN_ROOT" status --porcelain --untracked-files=all --ignore-submodules=none 2>/dev/null)" \
      && [ -z "$MB_AUN_STATUS" ] \
      && [ -f "$MB_AUN_ROOT/SKILL.md" ] \
      && [ -f "$MB_AUN_ROOT/scripts/mb-upgrade.sh" ] \
      && [ -f "$MB_AUN_ROOT/scripts/_lib.sh" ]; then
      # Strong bundle-identity gate (M3 residual): the marker check inside
      # _skill_root.sh's own candidate list (SKILL.md OR VERSION) is
      # deliberately weak — it is a GENERAL resolver shared by 11 other
      # hooks, and tightening it there would risk regressing all of them.
      # Here, immediately before a DESTRUCTIVE action (mb-upgrade.sh
      # --force), this hook adds its own independent, strictly stronger
      # check: ALL THREE of SKILL.md + scripts/mb-upgrade.sh +
      # scripts/_lib.sh must be present together under $MB_AUN_ROOT. An
      # arbitrary git repo that merely happens to contain a stray VERSION
      # (or even a SKILL.md) file — enough to satisfy the general
      # resolver's own weak gate, whether reached via a stale/misconfigured
      # MB_SKILL_ROOT override or one of the hardcoded fallback candidates —
      # will not also have this exact scripts/ layout, so it is rejected
      # here regardless of how $MB_AUN_ROOT was resolved. This gate applies
      # independently of any MB_UPGRADE_BIN test/override seam: it checks
      # the ROOT's own on-disk layout, not which binary is about to run.
      MB_AUN_UPGRADE_BIN="${MB_UPGRADE_BIN:-$MB_AUN_ROOT/scripts/mb-upgrade.sh}"
      if [ -n "$MB_AUN_UPGRADE_BIN" ] && [ -r "$MB_AUN_UPGRADE_BIN" ]; then
        MB_AUN_UP_TIMEOUT="${MB_AUTO_UPDATE_TIMEOUT:-20}"
        case "$MB_AUN_UP_TIMEOUT" in '' | *[!0-9]*) MB_AUN_UP_TIMEOUT=20 ;; esac

        # Snapshot the on-disk VERSION file BEFORE the upgrade runs — the
        # after-the-fact re-read below is what proves the install genuinely
        # advanced (see the post-run comment for why exit code alone is not
        # enough).
        MB_AUN_VERSION_BEFORE=""
        [ -f "$MB_AUN_ROOT/VERSION" ] && MB_AUN_VERSION_BEFORE="$(tr -d '[:space:]' < "$MB_AUN_ROOT/VERSION" 2>/dev/null)"

        # Same hand-rolled, no-orphan watchdog discipline as the resolver
        # call above (own process group via `set -m`, negative-PID kill) —
        # a hanging/misbehaving upgrade must never hold this hook's
        # inherited stdout fd open, or outlive it as an orphan.
        set -m
        ( MB_SKILL_DIR="$MB_AUN_ROOT" bash "$MB_AUN_UPGRADE_BIN" --force >/dev/null 2>&1 ) &
        MB_AUN_PID=$!
        (
          sleep "$MB_AUN_UP_TIMEOUT"
          kill -KILL -- "-$MB_AUN_PID" 2>/dev/null
        ) >/dev/null 2>&1 &
        MB_AUN_WATCHDOG=$!
        set +m

        MB_AUN_UP_RC=0
        wait "$MB_AUN_PID" 2>/dev/null || MB_AUN_UP_RC=$?

        kill -KILL -- "-$MB_AUN_WATCHDOG" 2>/dev/null
        wait "$MB_AUN_WATCHDOG" 2>/dev/null

        # Re-read VERSION after the run. `scripts/mb-upgrade.sh` exits 0
        # even when `behind == 0` (already up to date) — a race with a
        # concurrent update, a stale resolver cache, or a branch/tag
        # mismatch can all trigger this, i.e. it can succeed while applying
        # NOTHING. Exit code alone is therefore not proof of a real
        # install: a truthy record requires BOTH the upgrade to have
        # genuinely succeeded (never on a failed or killed — SIGKILL -> 137
        # — attempt) AND the on-disk VERSION to have actually changed. A
        # rc==0 no-op stays silent about auto-update — the notice already
        # printed above is the whole story for that session.
        #
        # minor#1: "changed" alone is not enough either. Two extra guards:
        #   - VERSION_AFTER must string-equal `$latest` (the resolver's OWN
        #     target) — a concurrent/unrelated local VERSION write racing
        #     the upgrade window would otherwise still read as "changed"
        #     and produce a false "auto-updated to $latest" claim even
        #     though the checkout landed somewhere else entirely.
        #   - VERSION_BEFORE must be non-empty (a missing/unreadable
        #     baseline is inconclusive, not proof of a transition) — a
        #     first-ever snapshot with nothing to compare against must
        #     never be read as "genuinely advanced".
        MB_AUN_VERSION_AFTER=""
        [ -f "$MB_AUN_ROOT/VERSION" ] && MB_AUN_VERSION_AFTER="$(tr -d '[:space:]' < "$MB_AUN_ROOT/VERSION" 2>/dev/null)"
        if [ "$MB_AUN_UP_RC" -eq 0 ] && [ -n "$MB_AUN_VERSION_BEFORE" ] \
          && [ -n "$MB_AUN_VERSION_AFTER" ] \
          && [ "$MB_AUN_VERSION_AFTER" != "$MB_AUN_VERSION_BEFORE" ] \
          && [ "$MB_AUN_VERSION_AFTER" = "$latest" ]; then
          printf '[memory-bank-skill] auto-updated: %s -> %s\n' "$current" "$latest"
        fi
      fi
    fi
  fi
fi

exit 0
