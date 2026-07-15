#!/usr/bin/env bash
# mb-agree.sh — Running List of Agreements CLI (spec: specs/agreements/*.md).
#
# Usage:
#   mb-agree.sh add "<statement>" [--supersedes N] [--adr NNN] [--source S] [mb_path]
#   mb-agree.sh defer N [mb_path]
#   mb-agree.sh reject N [mb_path]
#   mb-agree.sh question "<text>" [mb_path]
#   mb-agree.sh resolve N [mb_path]
#   mb-agree.sh list [--all] [mb_path]
#   mb-agree.sh sync [mb_path]
#
# Effect: `<bank>/agreements.md` is the single source of truth for confirmed
# decisions (sections Active / Deferred / Open Questions / Archive, IDs
# AGR-NNN / Q-NNN, never reused). Every mutating subcommand takes an
# owner-token `mkdir` lock at `<bank>/.agreements.lock`, writes via
# temp-file + `mv`/`os.replace`, then regenerates the managed block
# (`<!-- mb-agreements:start/end -->`) in the project-root CLAUDE.md AND
# AGENTS.md — replacing only between the markers, byte-preserving everything
# else. `question`/`resolve` never touch the managed block.
#
# Lazy activation: `agreements.md` and the managed block are created on the
# first `add`, not before (REQ-003/REQ-006). Kill-switch: `MB_AGREEMENTS=off`
# (env, or a `MB_AGREEMENTS=off` line in `<bank>/.mb-config`) turns every
# subcommand into an explained no-op — zero writes, exit 0. Env wins over
# the config file.
#
# Exit codes:
#   0  success, or kill-switch no-op
#   1  domain error (target not active/found, damaged managed block, lock
#      timeout) — zero writes
#   2  usage error (missing/invalid args, multiline statement) — zero writes
#
# Env overrides:
#   MB_AGREEMENTS_PROJECT_ROOT   project root for CLAUDE.md/AGENTS.md
#                                (default: parent of a ".memory-bank"-named
#                                bank, else $PWD)
#   MB_AGREEMENTS_LOCK_TIMEOUT   seconds to wait for the lock (default 10)
#   MB_AGREEMENTS_LOCK_TTL       seconds before a held lock is stale (default 120)
#   MB_AGREEMENTS                "off" disables the whole feature

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

LOCK_TIMEOUT="${MB_AGREEMENTS_LOCK_TIMEOUT:-10}"
LOCK_TTL="${MB_AGREEMENTS_LOCK_TTL:-120}"

usage() {
  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
}

# Atomic mkdir lock (no flock on macOS). Mirrors scripts/mb-handoff.sh::
# _lock_acquire/_lock_release — owner-token compare on release so a slow
# original never deletes a fresher owner's lock.
#
# BLOCKER 2 / FINDING 1 / NEW BUG A (Codex re-review, two rounds): the
# stale-break path went through FOUR designs before this one, each
# disproved by the "BLOCKER 2 regression" / "FINDING 1" / "NEW BUG A"
# stress tests in tests/bats/test_mb_agree.bats:
#   1. Blind `rm -rf "$lock"` on an mtime-old lock — a TOCTOU: two
#      contenders independently judging the SAME dir "stale" can have one
#      of them delete a directory a DIFFERENT contender just `mkdir`-ed
#      moments ago (a perfectly live lock), letting two processes into the
#      critical section at once.
#   2. `mv` instead of `rm -rf`, then owner-token / mtime re-verification
#      of the reclaimed copy — closed the "two racers destroy the SAME
#      dir" case, but every variant was STILL keying the decision off
#      mtime/TTL, which cannot distinguish "genuinely orphaned" from "the
#      owner is alive and just busy longer than TTL". A secondary
#      `.reclaiming` helper mutex serialized the DECISION but reintroduced
#      its own unprotected blind-rm-rf one level down (never trap-
#      protected against SIGKILL between its own `mkdir`/`rmdir`), and its
#      presence let a `continue` skip the timeout bookkeeping entirely —
#      LOCK_TIMEOUT silently became LOCK_TTL, a busy-spin, not a wait.
#
# Fix: mtime/TTL is NOT the reclaim signal at all. The reclaim decision is
# keyed on OWNER PID LIVENESS, which is the only signal that actually
# proves orphanhood:
#   - `mkdir "$lock"` can only ever succeed while $lock does NOT exist —
#     so no fresh, live lock can ever appear at this path while a
#     (possibly stale-looking) directory still occupies it.
#   - the only code that can make $lock vanish "properly" is its owner's
#     OWN `_lock_release` — and a genuinely DEAD process runs no code, so
#     it can never do that.
#   - therefore: `rm -rf "$lock"` is safe if-and-only-if we can PROVE the
#     owner recorded in `$lock/owner` (token format `PID-RANDOM`) is dead
#     (`kill -0 "$pid"` fails). We additionally re-read the owner token
#     immediately before the `rm -rf` and abort if it changed (someone
#     else already cycled the lock in the interim).
#   - a lock with NO readable owner (the owner-write step itself crashed,
#     a window of a single `printf`) falls back to mtime/TTL — the only
#     case with no PID to check at all; in practice such a lock is only
#     ever microseconds old, nowhere near a realistic TTL.
# No secondary mutex: two contenders can both observe a dead owner and
# both attempt the `rm -rf` — harmless (idempotent on an already-removed
# path), and only one of them can ever win the FOLLOWING `mkdir` (still
# atomic). The one residual this does NOT eliminate: OS PID reuse can make
# a genuinely-dead owner's PID look "alive" (owned by an unrelated live
# process) — that is a conservative NON-reclaim, so the primary loop just
# loud-times-out (exit 1, zero writes) instead of proceeding. That is a
# LIVENESS/availability limitation (a genuinely stuck bank needs a manual
# `rm -rf <bank>/.agreements.lock`), never a correctness/corruption one.
#
# Timeout bookkeeping is UNCONDITIONAL: every iteration that does not
# acquire the lock — whether or not a reclaim was attempted — falls
# through to the SAME `sleep 1; waited+=1; timeout check` at the loop
# tail. There is no `continue` anywhere in this function that can skip it,
# so LOCK_TIMEOUT is always honored and this can never busy-spin.
#
# NOTE: scripts/mb-handoff.sh and scripts/mb-work-progress-append.sh mirror
# the OLD (buggy) blind-rm-rf-on-mtime idiom — see this task's report for
# that pre-existing, out-of-scope finding; not fixed here.
_lock_acquire() {
  local lock="$1" timeout="$2" ttl="$3" waited=0 token
  local owner pid age now owner_now
  token="$$-${RANDOM:-0}"
  while true; do
    if mkdir "$lock" 2>/dev/null; then
      { printf '%s' "$token" >"$lock/owner"; } 2>/dev/null || true
      printf '%s' "$token"
      return 0
    fi

    owner="$(cat "$lock/owner" 2>/dev/null || true)"
    pid="${owner%%-*}"
    if printf '%s' "$pid" | grep -qE '^[0-9]+$' 2>/dev/null; then
      if ! kill -0 "$pid" 2>/dev/null; then
        # Owner PID confirmed dead. Re-read the token right before acting —
        # if it changed since the read above, someone else already cycled
        # this lock (a legitimate new holder, or another contender's own
        # reclaim); leave it alone rather than risk a redundant delete.
        owner_now="$(cat "$lock/owner" 2>/dev/null || true)"
        if [ -n "$owner_now" ] && [ "$owner_now" = "$owner" ]; then
          rm -rf "$lock" 2>/dev/null || true
        fi
      fi
      # else: PID parses but is alive (or reused by an unrelated live
      # process) — do NOT reclaim under any circumstance. Fall through to
      # the unconditional timeout below.
    elif [ -z "$owner" ]; then
      # No readable owner at all — the one case a PID check cannot cover
      # (a holder that crashed between its own `mkdir` and its owner-file
      # write). mtime/TTL fallback ONLY for this narrow case, never as the
      # general reclaim path.
      age="$(mb_mtime "$lock")"
      if [ -n "$age" ]; then
        now="$(date +%s)"
        if [ "$((now - age))" -gt "$ttl" ]; then
          rm -rf "$lock" 2>/dev/null || true
        fi
      fi
    fi

    if [ "$waited" -ge "$timeout" ]; then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

# shellcheck disable=SC2329  # invoked indirectly via `trap _lock_release EXIT`
_lock_release() {
  local lock="$1" token="${2:-}" current
  if [ -z "$token" ]; then
    return 0
  fi
  current="$(cat "$lock/owner" 2>/dev/null || true)"
  if [ "$current" = "$token" ]; then
    rm -rf "$lock" 2>/dev/null || true
  fi
}

# Kill-switch: env wins over `<bank>/.mb-config`.
_agreements_disabled() {
  local bank="$1" cfg
  if [ "${MB_AGREEMENTS:-}" = "off" ]; then
    return 0
  fi
  cfg="$bank/.mb-config"
  if [ -f "$cfg" ] && grep -qE '^MB_AGREEMENTS=off[[:space:]]*$' "$cfg" 2>/dev/null; then
    return 0
  fi
  return 1
}

_disabled_notice() {
  printf '[mb-agree] agreements are disabled (MB_AGREEMENTS=off) — "%s" is a no-op.\n' "$1"
  printf '[mb-agree] re-enable: unset MB_AGREEMENTS, or remove the MB_AGREEMENTS=off line from <bank>/.mb-config\n'
}

# Project root for CLAUDE.md/AGENTS.md — explicit override, else the parent
# of a local ".memory-bank"-named bank, else $PWD (global-storage fallback).
_project_root() {
  local bank="$1" base
  if [ -n "${MB_AGREEMENTS_PROJECT_ROOT:-}" ]; then
    printf '%s\n' "$MB_AGREEMENTS_PROJECT_ROOT"
    return 0
  fi
  base="$(basename "$bank")"
  if [ "$base" = ".memory-bank" ]; then
    dirname "$bank"
    return 0
  fi
  printf '%s\n' "$PWD"
}

# BLOCKER 1 (Codex review): reject any user text that could inject managed-
# block marker syntax. Free-text `add`/`question` values land verbatim inside
# the rendered block body (build_block/_entry_to_block_line); a statement
# containing a literal `<!-- mb-agreements:end -->` (or `:start`) would be
# indistinguishable from a REAL marker on the NEXT sync, so `_find_markers`
# would treat the injected text as the block boundary and truncate/clobber
# bytes outside it. Reject-don't-escape: any bare `-->` is already unsafe
# enough to refuse outright (it also covers `:start`/`:end` since both end
# in `-->`). Returns 0 (true — reject it) when marker-ish syntax is found,
# 1 (false — safe) otherwise.
_contains_marker_syntax() {
  case "$1" in
    *'-->'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Extract the first integer run from an id-ish token (e.g. "4", "004",
# "AGR-004", "Q-4") and zero-pad it to 3 digits. Empty output = invalid.
_normalize_id() {
  local raw="$1" digits
  digits="$(printf '%s' "$raw" | grep -Eo '[0-9]+' | head -n1)"
  [ -n "$digits" ] || return 1
  digits=$((10#$digits))
  printf '%03d\n' "$digits"
}

# ─────────────────────────────────────────────────────────────────────────
# Embedded Python engine — registry parsing/rendering + managed-block sync.
# Invoked as: run_engine <action> --key=value ...  (values arrive via argv,
# never interpolated into this source, so arbitrary statement text is safe).
# ─────────────────────────────────────────────────────────────────────────
ENGINE_SRC="$(cat <<'PYEOF'
import os
import re
import sys
import tempfile

MARKER_START = "<!-- mb-agreements:start -->"
MARKER_END = "<!-- mb-agreements:end -->"
SECTIONS = ["Active", "Deferred", "Open Questions", "Archive"]


def usage_error(msg):
    sys.stderr.write("[mb-agree] " + msg + "\n")
    sys.exit(2)


def domain_error(msg):
    sys.stderr.write("[mb-agree] " + msg + "\n")
    sys.exit(1)


def parse_args(argv):
    args = {}
    for tok in argv:
        if not tok.startswith("--"):
            continue
        key, sep, val = tok[2:].partition("=")
        if not sep:
            val = ""
        args[key.replace("-", "_")] = val
    return args


def read_text(path):
    if not os.path.exists(path):
        return ""
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def atomic_write(path, content):
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".mb-agree-", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def parse_registry(text):
    sections = dict((s, []) for s in SECTIONS)
    current = None
    for line in text.splitlines():
        m = re.match(r"^## (.+?)\s*$", line)
        if m and m.group(1) in sections:
            current = m.group(1)
            continue
        if current is not None and line.startswith("- "):
            sections[current].append(line)
    return sections


def render_registry(sections):
    out = ["# Agreements", ""]
    for name in SECTIONS:
        out.append("## " + name)
        out.append("")
        for line in sections[name]:
            out.append(line)
        if sections[name]:
            out.append("")
    text = "\n".join(out)
    return text.rstrip("\n") + "\n"


def next_id(sections, prefix):
    # MAJOR 3 (Codex review): anchor to the entry OWN leading id token
    # ("- AGR-NNN " / "- Q-NNN:") only — a bare `\b...\b` search used to
    # match "AGR-999" mentioned inside a statement prose too, so a
    # single `add "text about AGR-999"` could poison the counter straight to
    # AGR-1000. Every id that ever existed already has its OWN entry line
    # in exactly one section, so anchoring to the line own token is both
    # sufficient and correct.
    # NOTE: no single-quote characters anywhere in this heredoc block. bash
    # 3.2 mis-lexes a lone single quote inside a command-substitution-wrapped
    # quoted heredoc (ENGINE_SRC=$(cat <<QUOTEDTAG ... QUOTEDTAG)) even
    # though the heredoc body is nominally literal; confirmed via bash -n
    # under /bin/bash 3.2. Use double quotes / reword prose instead.
    max_n = 0
    pat = re.compile(r"^- " + re.escape(prefix) + r"-([0-9]+)\b")
    for name in SECTIONS:
        for line in sections[name]:
            m = pat.match(line)
            if m:
                n = int(m.group(1))
                if n > max_n:
                    max_n = n
    return max_n + 1


def find_line(sections, section, id_str):
    dash_prefix = "- " + id_str + " "
    colon_prefix = "- " + id_str + ":"
    for i, line in enumerate(sections[section]):
        if line.startswith(dash_prefix) or line.startswith(colon_prefix):
            return i
    return None


def require_file(args):
    f = args.get("file")
    if not f:
        usage_error("missing --file")
    return f


def cmd_add(args):
    file_path = require_file(args)
    statement = args.get("statement", "")
    date = args.get("date", "")
    source_val = args.get("source") or "user-confirmed"
    supersedes = args.get("supersedes") or None
    adr = args.get("adr") or None
    if not statement:
        usage_error("add requires a non-empty statement")
    if "\n" in statement:
        usage_error("statement must be single-line (no embedded newline)")

    sections = parse_registry(read_text(file_path))

    old_id = None
    old_idx = None
    if supersedes:
        old_id = "AGR-%03d" % int(supersedes)
        old_idx = find_line(sections, "Active", old_id)
        if old_idx is None:
            domain_error("%s is not active" % old_id)

    new_num = next_id(sections, "AGR")
    new_id = "AGR-%03d" % new_num
    line = "- %s (%s, %s): %s" % (new_id, date, source_val, statement)
    if supersedes:
        line += " [supersedes %s]" % old_id
    if adr:
        line += " → ADR-%03d" % int(adr)
    sections["Active"].append(line)

    if supersedes:
        old_line = sections["Active"].pop(old_idx)
        old_line = old_line + " [superseded by %s]" % new_id
        sections["Archive"].append(old_line)

    atomic_write(file_path, render_registry(sections))
    print(new_id)

    active_count = len(sections["Active"])
    if active_count > 25:
        sys.stderr.write(
            "[mb-agree] prune warning: %d active agreements (>25) — "
            "consider deferring/rejecting stale ones\n" % active_count
        )


def _move_active(args, target_section, extra_marker):
    file_path = require_file(args)
    id_raw = args.get("id")
    if not id_raw:
        usage_error("missing --id")
    num = int(id_raw)
    id_str = "AGR-%03d" % num

    sections = parse_registry(read_text(file_path))
    idx = find_line(sections, "Active", id_str)
    if idx is None:
        domain_error("%s is not active" % id_str)

    line = sections["Active"].pop(idx)
    if extra_marker:
        line = line + extra_marker
    sections[target_section].append(line)

    atomic_write(file_path, render_registry(sections))
    print(id_str)


def cmd_defer(args):
    _move_active(args, "Deferred", None)


def cmd_reject(args):
    _move_active(args, "Archive", " [rejected]")


def cmd_question(args):
    file_path = require_file(args)
    text = args.get("text", "")
    if not text:
        usage_error("question requires a non-empty text")
    if "\n" in text:
        usage_error("text must be single-line (no embedded newline)")

    sections = parse_registry(read_text(file_path))
    new_num = next_id(sections, "Q")
    new_id = "Q-%03d" % new_num
    sections["Open Questions"].append("- %s: %s" % (new_id, text))

    atomic_write(file_path, render_registry(sections))
    print(new_id)


def cmd_resolve(args):
    file_path = require_file(args)
    id_raw = args.get("id")
    if not id_raw:
        usage_error("missing --id")
    num = int(id_raw)
    date = args.get("date", "")
    id_str = "Q-%03d" % num

    sections = parse_registry(read_text(file_path))
    idx = find_line(sections, "Open Questions", id_str)
    if idx is None:
        domain_error("%s not found" % id_str)

    # MAJOR (Codex re-review): keep a BARE leading "- Q-NNN" token on the
    # resolved line — only the id-less remainder gets struck through.
    # Striking the WHOLE line (id included) made the next_id line-anchored
    # scan blind to it, so the id silently became reissuable, violating
    # REQ-001 (ids are never reused).
    line = sections["Open Questions"][idx]
    prefix = "- " + id_str + ": "
    text = line[len(prefix):] if line.startswith(prefix) else line[2:]
    sections["Open Questions"][idx] = "- %s: ~~%s~~ (resolved %s)" % (id_str, text, date)

    atomic_write(file_path, render_registry(sections))
    print(id_str)


def cmd_list(args):
    file_path = require_file(args)
    mode = args.get("mode") or "active"
    if not os.path.exists(file_path):
        print("[mb-agree] no agreements recorded yet.")
        return

    sections = parse_registry(read_text(file_path))
    if mode == "all":
        for name in SECTIONS:
            print("## " + name)
            for line in sections[name]:
                print(line)
            print("")
        return

    print("## Active")
    if sections["Active"]:
        for line in sections["Active"]:
            print(line)
    else:
        print("(none)")


def _entry_to_block_line(line):
    m = re.match(r"^- (AGR-[0-9]+) \([^)]*\):\s?(.*)$", line)
    if m:
        return "- %s: %s" % (m.group(1), m.group(2))
    return line


def build_block(sections, pointer_path):
    active = sections["Active"]
    lines = ["## Active Agreements"]
    for line in active:
        lines.append(_entry_to_block_line(line))
    lines.append("")
    lines.append(
        "История, superseded и "
        "правила ведения "
        "→ %s (`/mb agree`)" % pointer_path
    )
    body = "\n".join(lines)
    return "%s\n%s\n%s" % (MARKER_START, body, MARKER_END), len(active)


def _find_markers(text):
    return text.find(MARKER_START), text.find(MARKER_END)


def _validate_file(path):
    if not os.path.exists(path):
        return "absent", ""
    text = read_text(path)
    # MINOR (Codex re-review): require EXACTLY one of each marker. A
    # first-occurrence-only search (via `_find_markers`/`str.find`) treated
    # a file with a DUPLICATE start or end marker as well-formed the
    # instant the first valid pair was found, silently ignoring the extra
    # copy instead of flagging it — a duplicate is exactly as damaged as a
    # missing marker (both are "the boundaries are not unambiguous").
    start_count = text.count(MARKER_START)
    end_count = text.count(MARKER_END)
    if start_count == 0 and end_count == 0:
        return "none", text
    if start_count == 1 and end_count == 1:
        s, e = _find_markers(text)
        if s < e:
            return "both", text
    return "damaged", text


def _patch_content(text, block):
    s, e = _find_markers(text)
    if s != -1 and e != -1 and s < e:
        end_pos = e + len(MARKER_END)
        return text[:s] + block + text[end_pos:]
    new_text = text
    if new_text and not new_text.endswith("\n"):
        new_text += "\n"
    if new_text:
        new_text += "\n"
    return new_text + block + "\n"


# Validate marker well-formedness of every target WITHOUT writing anything.
# Shared by `check-targets` (the MAJOR 5 preflight, called BEFORE a
# registry mutation commits) and `sync` (called again right before it
# actually patches the files). domain_error() exits the process — a damaged
# target aborts the whole batch, nothing gets written to ANY target.
def _check_targets(targets):
    plan = []
    for path in targets:
        status, text = _validate_file(path)
        if status == "damaged":
            marker_seen = MARKER_START if MARKER_START in text else MARKER_END
            domain_error(
                "damaged managed block in %s: found %s without its "
                "matching marker — fix or remove it, then re-run sync"
                % (path, marker_seen)
            )
        plan.append((path, status, text))
    return plan


def _resolve_targets(args):
    targets_raw = args.get("targets") or ""
    targets = [t for t in targets_raw.split(",") if t]
    create_target = args.get("create_target") or None
    if not targets and create_target:
        targets = [create_target]
    return targets


# MAJOR 5 (Codex review): a pure preflight — validates every sync target
# markers and exits 1 (zero writes, anywhere) if any is damaged. The CLI
# calls this BEFORE running the add/defer/reject registry mutation, so a
# damaged CLAUDE.md/AGENTS.md can never leave agreements.md holding an
# entry that the managed block never actually reflected.
def cmd_check_targets(args):
    targets = _resolve_targets(args)
    _check_targets(targets)
    print("ok")


def cmd_sync(args):
    registry = args.get("registry")
    if not registry:
        usage_error("missing --registry")
    if not os.path.exists(registry):
        print("[mb-agree] no agreements.md yet — nothing to sync.")
        return

    project_root = args.get("project_root") or os.path.dirname(registry)
    try:
        pointer_path = os.path.relpath(registry, project_root)
        if pointer_path.startswith(".."):
            pointer_path = registry
    except ValueError:
        pointer_path = registry

    sections = parse_registry(read_text(registry))
    block, active_count = build_block(sections, pointer_path)

    targets = _resolve_targets(args)
    plan = _check_targets(targets)

    for path, status, text in plan:
        if status == "absent":
            new_text = block + "\n"
        else:
            new_text = _patch_content(text, block)
        if status != "absent" and new_text == text:
            continue
        atomic_write(path, new_text)

    print("[mb-agree] managed block synced (%d active)" % active_count)
    if active_count > 25:
        sys.stderr.write(
            "[mb-agree] prune warning: %d active agreements (>25) — "
            "consider deferring/rejecting stale ones\n" % active_count
        )


ACTIONS = {
    "add": cmd_add,
    "defer": cmd_defer,
    "reject": cmd_reject,
    "question": cmd_question,
    "resolve": cmd_resolve,
    "list": cmd_list,
    "sync": cmd_sync,
    "check-targets": cmd_check_targets,
}


def main():
    if len(sys.argv) < 2:
        usage_error("missing action")
    action = sys.argv[1]
    fn = ACTIONS.get(action)
    if fn is None:
        usage_error("unknown action: %s" % action)
    fn(parse_args(sys.argv[2:]))


if __name__ == "__main__":
    main()
PYEOF
)"

run_engine() {
  printf '%s\n' "$ENGINE_SRC" | "${MB_PYTHON:-python3}" - "$@"
}

# Comma-separated list of EXISTING sync targets under project_root (CLAUDE.md
# and/or AGENTS.md, whichever already exist — mirrors REQ-006's "write only
# to files that already exist" rule). Empty when neither exists (sync will
# then create AGENTS.md fresh — nothing to preflight-validate in that case).
_existing_sync_targets() {
  local project_root="$1"
  local claude="$project_root/CLAUDE.md"
  local agents="$project_root/AGENTS.md"
  local targets=""
  if [ -f "$claude" ]; then
    targets="$claude"
  fi
  if [ -f "$agents" ]; then
    if [ -n "$targets" ]; then targets="$targets,$agents"; else targets="$agents"; fi
  fi
  printf '%s' "$targets"
}

# MAJOR 5 (Codex review): pure preflight, zero writes. Validates that every
# EXISTING sync target has well-formed markers BEFORE the caller commits a
# registry mutation. Without this, add/defer/reject used to write
# agreements.md FIRST and only discover a damaged CLAUDE.md/AGENTS.md when
# the follow-up `_sync_block` ran afterward — leaving agreements.md holding
# an entry the managed block never actually reflected (and a retry would
# then duplicate it). A bank where neither file exists yet has nothing to
# validate (sync will just create AGENTS.md fresh).
_preflight_sync_targets() {
  local project_root="$1" targets
  targets="$(_existing_sync_targets "$project_root")"
  [ -z "$targets" ] && return 0
  run_engine check-targets --targets="$targets"
}

# Regenerate the managed block in project-root CLAUDE.md/AGENTS.md from the
# current registry. Writes only to files that already exist; if neither
# exists, creates AGENTS.md with only the block (REQ-006). Returns the
# engine's exit code (0 ok, 1 damaged block — zero writes).
_sync_block() {
  local project_root="$1" reg="$2"
  local agents="$project_root/AGENTS.md"
  local targets
  targets="$(_existing_sync_targets "$project_root")"
  local create_target=""
  if [ -z "$targets" ]; then
    create_target="$agents"
  fi
  run_engine sync --registry="$reg" --project-root="$project_root" \
    --targets="$targets" --create-target="$create_target"
}

main() {
  local sub="${1:-}"
  case "$sub" in
    -h | --help | "")
      usage
      exit 0
      ;;
  esac
  shift

  case "$sub" in
    add | defer | reject | question | resolve | list | sync) ;;
    *)
      echo "[mb-agree] unknown subcommand: $sub" >&2
      usage >&2
      exit 2
      ;;
  esac

  local statement="" supersedes_raw="" adr_raw="" source_val="user-confirmed"
  local mb_arg="" id_arg="" text_arg="" list_all=0

  case "$sub" in
    add)
      if [ "$#" -lt 1 ]; then
        echo '[mb-agree] usage: mb-agree.sh add "<statement>" [--supersedes N] [--adr NNN] [--source S] [mb_path]' >&2
        exit 2
      fi
      statement="$1"
      shift
      case "$statement" in
        *$'\n'*)
          echo "[mb-agree] usage: statement must be single-line (no embedded newline)" >&2
          exit 2
          ;;
      esac
      if _contains_marker_syntax "$statement"; then
        echo "[mb-agree] usage: statement must not contain '-->' (managed-block marker syntax)" >&2
        exit 2
      fi
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --supersedes)
            supersedes_raw="${2:-}"
            shift 2
            ;;
          --supersedes=*)
            supersedes_raw="${1#--supersedes=}"
            shift
            ;;
          --adr)
            adr_raw="${2:-}"
            shift 2
            ;;
          --adr=*)
            adr_raw="${1#--adr=}"
            shift
            ;;
          --source)
            source_val="${2:-}"
            shift 2
            ;;
          --source=*)
            source_val="${1#--source=}"
            shift
            ;;
          *)
            mb_arg="$1"
            shift
            ;;
        esac
      done
      ;;
    defer | reject | resolve)
      if [ "$#" -lt 1 ]; then
        echo "[mb-agree] usage: mb-agree.sh $sub N [mb_path]" >&2
        exit 2
      fi
      id_arg="$1"
      shift
      if [ "$#" -gt 0 ]; then
        mb_arg="$1"
        shift
      fi
      ;;
    question)
      if [ "$#" -lt 1 ]; then
        echo '[mb-agree] usage: mb-agree.sh question "<text>" [mb_path]' >&2
        exit 2
      fi
      text_arg="$1"
      shift
      case "$text_arg" in
        *$'\n'*)
          echo "[mb-agree] usage: text must be single-line (no embedded newline)" >&2
          exit 2
          ;;
      esac
      if _contains_marker_syntax "$text_arg"; then
        echo "[mb-agree] usage: text must not contain '-->' (managed-block marker syntax)" >&2
        exit 2
      fi
      if [ "$#" -gt 0 ]; then
        mb_arg="$1"
        shift
      fi
      ;;
    list)
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --all)
            list_all=1
            shift
            ;;
          *)
            mb_arg="$1"
            shift
            ;;
        esac
      done
      ;;
    sync)
      if [ "$#" -gt 0 ]; then
        mb_arg="$1"
        shift
      fi
      ;;
  esac

  local bank
  bank="$(mb_resolve_path "$mb_arg")"
  local project_root
  project_root="$(_project_root "$bank")"

  if _agreements_disabled "$bank"; then
    _disabled_notice "$sub"
    exit 0
  fi

  local reg="$bank/agreements.md"

  if [ "$sub" = "list" ]; then
    if [ ! -f "$reg" ]; then
      echo "[mb-agree] no agreements recorded yet — run 'mb-agree.sh add' first."
      exit 0
    fi
    local mode="active"
    [ "$list_all" -eq 1 ] && mode="all"
    run_engine list --file="$reg" --mode="$mode"
    exit 0
  fi

  if [ "$sub" = "sync" ] && [ ! -f "$reg" ]; then
    echo "[mb-agree] no agreements.md yet — nothing to sync."
    exit 0
  fi

  # `add` and `question` both lazily create agreements.md on first use
  # (REQ-003 names `add`; `question` gets the same courtesy so an unconfirmed
  # hypothesis never requires an unrelated confirmed decision first). Every
  # other mutating subcommand needs a pre-existing registry to act on.
  if [ "$sub" != "add" ] && [ "$sub" != "question" ] && [ "$sub" != "sync" ] && [ ! -f "$reg" ]; then
    echo "[mb-agree] $reg not found — run 'mb-agree.sh add' first." >&2
    exit 1
  fi

  local supersedes_num="" adr_num="" id_num=""
  if [ -n "$supersedes_raw" ]; then
    if ! supersedes_num="$(_normalize_id "$supersedes_raw")"; then
      echo "[mb-agree] usage: --supersedes expects a numeric id, got '$supersedes_raw'" >&2
      exit 2
    fi
  fi
  if [ -n "$adr_raw" ]; then
    if ! adr_num="$(_normalize_id "$adr_raw")"; then
      echo "[mb-agree] usage: --adr expects a numeric id, got '$adr_raw'" >&2
      exit 2
    fi
  fi
  if [ -n "$id_arg" ]; then
    if ! id_num="$(_normalize_id "$id_arg")"; then
      echo "[mb-agree] usage: '$id_arg' is not a valid id" >&2
      exit 2
    fi
  fi

  mkdir -p "$bank"
  local lock="$bank/.agreements.lock"
  local token=""
  if ! token="$(_lock_acquire "$lock" "$LOCK_TIMEOUT" "$LOCK_TTL")"; then
    echo "[mb-agree] could not acquire lock '$lock' within ${LOCK_TIMEOUT}s — no changes were made." >&2
    exit 1
  fi
  # shellcheck disable=SC2064
  trap "_lock_release '$lock' '$token'" EXIT

  # NOTE: deliberately NOT `if ! cmd; then rc=$?; fi` — `!` rewrites the exit
  # status of the compound command to a plain 0/1 negation, so `$?` inside the
  # then-branch is the NEGATION's status, not the original failing command's
  # real code (2 usage vs 1 domain error would both collapse to the same
  # value). `cmd || rc=$?` preserves the real code and is equally `-e`-safe.
  local result="" rc=0

  # MAJOR 5 (Codex review): preflight-validate every EXISTING sync target
  # BEFORE the registry mutation runs, for every subcommand that triggers a
  # follow-up sync. A damaged CLAUDE.md/AGENTS.md must abort before
  # agreements.md changes, not after — otherwise a failed `add` still left
  # a committed entry the managed block never reflected, and a retry would
  # duplicate it.
  case "$sub" in
    add | defer | reject)
      _preflight_sync_targets "$project_root" || rc=$?
      ;;
  esac
  if [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi

  # NOTE (MAJOR 4, Codex review): no more "lazily `cp` the template into
  # place before validating" here. `add`/`question` no longer pre-create
  # agreements.md at all — `read_text()` on a missing file already returns
  # "" (== an empty, freshly-templated registry) to the engine, so
  # `cmd_add`'s `--supersedes` check runs — and can fail — BEFORE any write
  # happens. `atomic_write()` creates the file from scratch on first
  # success, rendering byte-identical content to templates/agreements.md
  # (both are the canonical empty-sections render), so REQ-003's lazy-init
  # contract still holds without a premature filesystem write.
  case "$sub" in
    add)
      local today
      today="$(date +%F)"
      result="$(run_engine add --file="$reg" --statement="$statement" \
        --date="$today" --source="$source_val" \
        --supersedes="$supersedes_num" --adr="$adr_num")" || rc=$?
      ;;
    defer)
      result="$(run_engine defer --file="$reg" --id="$id_num")" || rc=$?
      ;;
    reject)
      result="$(run_engine reject --file="$reg" --id="$id_num")" || rc=$?
      ;;
    question)
      result="$(run_engine question --file="$reg" --text="$text_arg")" || rc=$?
      ;;
    resolve)
      local today
      today="$(date +%F)"
      result="$(run_engine resolve --file="$reg" --id="$id_num" --date="$today")" || rc=$?
      ;;
    sync)
      _sync_block "$project_root" "$reg" || rc=$?
      ;;
  esac

  if [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi

  case "$sub" in
    add | defer | reject)
      _sync_block "$project_root" "$reg" || rc=$?
      ;;
  esac

  if [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi

  if [ -n "$result" ]; then
    printf '%s\n' "$result"
  fi
  exit 0
}

main "$@"
