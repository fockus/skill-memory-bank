#!/usr/bin/env bash
# mb-flow-route.sh — deterministic route resolver (dynamic-flow Task 8).
#
# The testable CORE of the dynamic-flow router. It takes a PROPOSED starting
# route (an LLM candidate or an explicit user override — identical here), applies
# the deterministic route-floor (REQ-DF-022), and writes the resolved `route:`
# into the `<!-- mb-flow -->` fence in status.md by REUSING mb-flow-sync.sh.
#
# This is a RESOLVER, not the firewall (ADR-3): it does not gate work, it routes.
# The firewall (mb-flow-verify.sh) owns the done-gate exit code; this script only
# decides which route to enter and records it.
#
# Usage:
#   mb-flow-route.sh [mb_path] [--route R | --candidate R] [--repo <path>]
#                    [--changed <csv>] [--changed-file <f>]... [--depends-on N]
#                    [--dry-run] [-h|--help]
#
#   mb_path            Memory Bank path (default via _lib.sh::mb_resolve_path).
#   --route R          Explicit override route (REQ-DF-025). Synonym of
#   --candidate R      the LLM candidate route (REQ-DF-020). The floor applies
#                      IDENTICALLY to both — the "skip classification" distinction
#                      lives in the command layer, not in this resolver.
#                      Default candidate when neither is given: code-change
#                      (the dominant case — ADR-6/7).
#   --repo <path>      git repo used to derive changed files (default: cwd).
#   --changed <csv>    explicit comma-separated changed-file list (TEST SEAM —
#                      lets callers drive the floor with no git repo).
#   --changed-file <f> repeatable single changed file (TEST SEAM). When NEITHER
#                      --changed nor --changed-file is given, the changed list is
#                      derived from git (diff --name-only [+ --cached], sort -u).
#   --depends-on N     integer dependency count (default 0). When omitted it is
#                      auto-derived (best-effort, fail-open to 0) from goal.md's
#                      linked_plans → each linked plan's depends_on. The explicit
#                      flag always wins.
#   --dry-run          resolve + print JSON but do NOT write the fence.
#
# Route ranking (the floor only ever RAISES a route, never lowers it):
#   research = 0, bugfix = 1, code-change = 2, arch = 3, migration = 4.
#
# Floor triggers (REQ-DF-022 — conservative; false-positives are acceptable,
# false-negatives are NOT — ADR-4). If ANY changed file matches, the floor is
# `arch` (rank 3):
#   - a `domain/` path segment
#   - an `application/ports` path
#   - an interface/Protocol/ABC/contract file
#   - a declared protected_path (via mb-work-protected-check.sh exit 1)
#   - depends_on > 0 (explicit flag or auto-derived)
#
# Resolution: floor_rank = 3 if any_trigger else 0;
#             resolved_rank = max(rank(candidate), floor_rank).
#
# Output (stdout — ALWAYS exactly one JSON object, write or dry-run):
#   {"candidate":"<c>","floor":"<arch|none>","route":"<resolved>",
#    "floor_triggered":true|false,"reasons":["<concrete trigger>", ...]}
#
# Exit: 0 resolved (and written unless --dry-run);
#       1 usage / unknown route / bad bank (write target missing);
#       2 internal error (fence writer lock/internal failure).

set -euo pipefail

# Resolve own dir via BASH_SOURCE so the script works even if sourced by tests.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,58p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---- JSON emitter -----------------------------------------------------------
# Emit the single result object via python3 json.dumps (mirrors
# mb-flow-verify.sh::emit_summary) so ALL control characters in a changed-file
# path are escaped correctly. Scalars via env; reasons via argv.
emit_json() {
  local candidate="$1" floor_field="$2" route="$3" floor_bool="$4"
  shift 4
  MB_ROUTE_CANDIDATE="$candidate" \
  MB_ROUTE_FLOOR="$floor_field" \
  MB_ROUTE_ROUTE="$route" \
  MB_ROUTE_FLOORBOOL="$floor_bool" \
  "${MB_PYTHON:-python3}" - "$@" <<'PY'
import json
import os
import sys

obj = {
    "candidate": os.environ["MB_ROUTE_CANDIDATE"],
    "floor": os.environ["MB_ROUTE_FLOOR"],
    "route": os.environ["MB_ROUTE_ROUTE"],
    "floor_triggered": os.environ["MB_ROUTE_FLOORBOOL"] == "true",
    "reasons": sys.argv[1:],
}
print(json.dumps(obj, separators=(",", ":")))
PY
}

# ---- route <-> rank lookups -------------------------------------------------
route_rank() {
  case "$1" in
    research)    printf '0' ;;
    bugfix)      printf '1' ;;
    code-change) printf '2' ;;
    arch)        printf '3' ;;
    migration)   printf '4' ;;
    *)           printf '%s' '-1' ;;
  esac
}

rank_name() {
  case "$1" in
    0) printf 'research' ;;
    1) printf 'bugfix' ;;
    2) printf 'code-change' ;;
    3) printf 'arch' ;;
    4) printf 'migration' ;;
    *) printf 'code-change' ;;
  esac
}

# ---- depends_on auto-derivation from goal.md linked_plans -------------------
# Best-effort, ALWAYS fail-open to 0. Counts linked plans whose own depends_on
# is a non-empty list OR an integer > 0.
derive_depends_on() {
  local mb="$1"
  local goal="$mb/goal.md"
  if [ ! -f "$goal" ]; then
    printf '0'
    return 0
  fi
  MB_ROUTE_BANK="$mb" "${MB_PYTHON:-python3}" - "$goal" 2>/dev/null <<'PY' || printf '0'
import os
import re
import sys


def read_frontmatter(path):
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except Exception:
        return None
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    body = []
    for line in lines[1:]:
        if line.strip() == "---":
            return "\n".join(body)
        body.append(line)
    return None  # unterminated frontmatter


def strip_comment(line):
    """Drop a trailing YAML `#` comment that is OUTSIDE quotes and brackets.

    Mirrors mb-work-protected-check.sh::strip_comment but is also bracket-aware
    (so `[plans/p.md] # active` → `[plans/p.md]`) and requires the `#` to be at
    line start or preceded by whitespace (so an unquoted `foo#bar` is kept).
    """
    in_single = False
    in_double = False
    depth = 0
    for idx, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif not in_single and not in_double:
            if char in "[{":
                depth += 1
            elif char in "]}":
                if depth > 0:
                    depth -= 1
            elif (
                char == "#"
                and depth == 0
                and (idx == 0 or line[idx - 1] in " \t")
            ):
                return line[:idx]
    return line


def get_value(fm, key):
    """Return (kind, payload): kind in {'list','scalar','none'}."""
    lines = fm.splitlines()
    pat = re.compile(r"^(\s*)" + re.escape(key) + r"\s*:\s*(.*?)\s*$")
    for idx, line in enumerate(lines):
        m = pat.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        # Strip an inline comment (outside quotes/brackets) before parsing.
        rest = strip_comment(m.group(2)).strip()
        if rest.startswith("["):
            inner = rest[1:]
            if inner.endswith("]"):
                inner = inner[:-1]
            parts = [p.strip().strip('"').strip("'") for p in inner.split(",")]
            return ("list", [p for p in parts if p])
        if rest and not rest.startswith("#"):
            return ("scalar", rest.strip('"').strip("'"))
        items = []
        for nxt in lines[idx + 1:]:
            if not nxt.strip():
                continue
            ind = len(nxt) - len(nxt.lstrip())
            if ind <= indent:
                break
            s = strip_comment(nxt).strip()
            if s.startswith("- "):
                items.append(s[2:].strip().strip('"').strip("'"))
            else:
                break
        return ("list", items)
    return ("none", None)


def depends_contributes(plan_path):
    fm = read_frontmatter(plan_path)
    if fm is None:
        return False
    kind, payload = get_value(fm, "depends_on")
    if kind == "list":
        return len([p for p in payload if p]) > 0
    if kind == "scalar":
        try:
            return int(payload) > 0
        except ValueError:
            return bool(payload)
    return False


def resolve_plan(bank, entry):
    for cand in (
        os.path.join(bank, entry),
        os.path.join(bank, "plans", entry),
        entry,
    ):
        if os.path.isfile(cand):
            return cand
    return None


def main():
    goal = sys.argv[1]
    bank = os.environ.get("MB_ROUTE_BANK", os.path.dirname(goal))
    fm = read_frontmatter(goal)
    if fm is None:
        print(0)
        return
    kind, payload = get_value(fm, "linked_plans")
    plans = payload if kind == "list" else []
    count = 0
    for entry in plans or []:
        plan = resolve_plan(bank, entry)
        if plan and depends_contributes(plan):
            count += 1
    print(count)


try:
    main()
except Exception:
    print(0)
PY
}

main() {
  local mb_arg=""
  local candidate=""
  local repo="."
  local depends_on=""
  local depends_on_explicit=0
  local dry_run=0
  local changed_explicit=0
  local changed
  changed=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --route|--candidate)
        if [ "$#" -lt 2 ]; then
          printf '[mb-flow-route] flag %s needs a value\n' "$1" >&2
          return 1
        fi
        candidate="$2"
        shift 2
        ;;
      --repo)
        if [ "$#" -lt 2 ]; then
          printf '[mb-flow-route] flag %s needs a value\n' "$1" >&2
          return 1
        fi
        repo="$2"
        shift 2
        ;;
      --changed)
        if [ "$#" -lt 2 ]; then
          printf '[mb-flow-route] flag %s needs a value\n' "$1" >&2
          return 1
        fi
        changed_explicit=1
        # Split on commas WITHOUT pathname expansion (mirrors mb-diff-scope.sh).
        local _parts part
        IFS=',' read -r -a _parts <<<"$2"
        if [ "${#_parts[@]}" -gt 0 ]; then
          for part in "${_parts[@]}"; do
            [ -n "$part" ] && changed+=("$part")
          done
        fi
        shift 2
        ;;
      --changed-file)
        if [ "$#" -lt 2 ]; then
          printf '[mb-flow-route] flag %s needs a value\n' "$1" >&2
          return 1
        fi
        changed_explicit=1
        [ -n "$2" ] && changed+=("$2")
        shift 2
        ;;
      --depends-on)
        if [ "$#" -lt 2 ]; then
          printf '[mb-flow-route] flag %s needs a value\n' "$1" >&2
          return 1
        fi
        case "$2" in
          ''|*[!0-9]*)
            printf '[mb-flow-route] --depends-on needs a non-negative integer: %s\n' "$2" >&2
            return 1
            ;;
        esac
        depends_on="$2"
        depends_on_explicit=1
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --)
        shift
        ;;
      -*)
        printf '[mb-flow-route] unknown flag: %s\n' "$1" >&2
        usage >&2
        return 1
        ;;
      *)
        if [ -z "$mb_arg" ]; then
          mb_arg="$1"
        else
          printf '[mb-flow-route] unexpected argument: %s\n' "$1" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  # Default candidate is the dominant code-change route (ADR-6/7).
  [ -z "$candidate" ] && candidate="code-change"

  # Validate the candidate is one of the five known routes (REQ-DF-020).
  local candidate_rank
  candidate_rank="$(route_rank "$candidate")"
  if [ "$candidate_rank" -lt 0 ]; then
    printf '[mb-flow-route] unknown route: %s (expected one of: bugfix|code-change|arch|migration|research)\n' "$candidate" >&2
    return 1
  fi

  # Resolve the bank. For a real write we require it to exist (mb-flow-sync.sh
  # treats a missing bank as a bad-bank error); for --dry-run we tolerate a
  # missing bank so the resolver runs anywhere.
  local mb
  mb="$(mb_resolve_path "$mb_arg")"

  # --- assemble the changed-file list --------------------------------------
  if [ "$changed_explicit" -eq 0 ]; then
    if command -v git >/dev/null 2>&1; then
      local f
      while IFS= read -r f; do
        [ -n "$f" ] && changed+=("$f")
      done < <(
        {
          git -C "$repo" diff --name-only 2>/dev/null
          git -C "$repo" diff --name-only --cached 2>/dev/null
          git -C "$repo" ls-files --others --exclude-standard 2>/dev/null
        } | sort -u
      )
    fi
  fi

  # --- compute the floor ----------------------------------------------------
  local floor_triggered=0
  local reasons
  reasons=()

  if [ "${#changed[@]}" -gt 0 ]; then
    local file
    for file in "${changed[@]}"; do
      [ -n "$file" ] || continue
      # Normalize Windows separators BEFORE matching so `src\domain\User.py`
      # trips the same globs as `src/domain/User.py` (REQ-DF-022, ADR-4).
      file="${file//\\//}"
      # Conservative globs (false-positives ACCEPTABLE, false-negatives NOT —
      # ADR-4). Each pattern is leading-anchored, so `domain.*|*/domain.*` does
      # NOT match `maindomain.py` (no leading "domain" and no "/domain.").
      case "$file" in
        domain/*|*/domain/*|domains/*|*/domains/*|domain.*|domains.*|*/domain.*|*/domains.*)
          floor_triggered=1
          reasons+=("domain path touched: $file")
          continue
          ;;
      esac
      case "$file" in
        *application/ports*)
          floor_triggered=1
          reasons+=("application/ports touched: $file")
          continue
          ;;
      esac
      case "$file" in
        interface/*|interfaces/*|*/interface/*|*/interfaces/*|interface.*|interfaces.*|*/interface.*|*/interfaces.*|*Interface*)
          floor_triggered=1
          reasons+=("interface file: $file")
          continue
          ;;
      esac
      case "$file" in
        contract/*|contracts/*|*/contract/*|*/contracts/*|contract.*|contracts.*|*/contract.*|*/contracts.*|*Contract*)
          floor_triggered=1
          reasons+=("contract file: $file")
          continue
          ;;
      esac
      case "$file" in
        protocol/*|protocols/*|*/protocol/*|*/protocols/*|protocol.*|protocols.*|*/protocol.*|*/protocols.*|*Protocol*)
          floor_triggered=1
          reasons+=("protocol file: $file")
          continue
          ;;
      esac
      case "$file" in
        port/*|ports/*|*/port/*|*/ports/*|port.*|ports.*|*/port.*|*/ports.*|*Port.*|*Ports.*)
          floor_triggered=1
          reasons+=("port/interface file: $file")
          continue
          ;;
      esac
      case "$file" in
        abc/*|abcs/*|*/abc/*|*/abcs/*|abc.*|*/abc.*|*ABC.*|*_abc.*)
          floor_triggered=1
          reasons+=("ABC file: $file")
          continue
          ;;
      esac
      local lc
      lc="$(printf '%s' "$file" | tr '[:upper:]' '[:lower:]')"
      case "$lc" in
        *interface*)
          floor_triggered=1
          reasons+=("interface file (lowercase): $file")
          continue
          ;;
      esac
      case "$lc" in
        *contract*)
          floor_triggered=1
          reasons+=("contract file (lowercase): $file")
          continue
          ;;
      esac
      case "$lc" in
        *protocol*)
          floor_triggered=1
          reasons+=("protocol file (lowercase): $file")
          continue
          ;;
      esac
      case "$lc" in
        *_abc*|*abc.*|*/abc/*|abc/*)
          floor_triggered=1
          reasons+=("ABC file (lowercase): $file")
          continue
          ;;
      esac
    done

    # Protected-path trigger — REUSE mb-work-protected-check.sh (exit 1 == match).
    # Capture its stderr (the `[protected] <f> matches <g>` lines) while
    # discarding stdout, then name the concrete files in the reasons.
    local protected_out protected_rc
    set +e
    protected_out="$(bash "$SCRIPT_DIR/mb-work-protected-check.sh" "${changed[@]}" --mb "$mb" 2>&1 >/dev/null)"
    protected_rc=$?
    set -e
    if [ "$protected_rc" -eq 1 ]; then
      # A concrete protected match. Name each breaching file in the reasons.
      floor_triggered=1
      local line pf
      while IFS= read -r line; do
        case "$line" in
          "[protected] "*" matches "*)
            pf="${line#\[protected\] }"
            pf="${pf%% matches *}"
            reasons+=("protected_path: $pf")
            ;;
        esac
      done <<EOF
$protected_out
EOF
    elif [ "$protected_rc" -ne 0 ]; then
      # INDETERMINATE (e.g. malformed pipeline.yaml → rc 2). Per ADR-4 an
      # inconclusive protected check must escalate conservatively rather than
      # let a possibly-protected change route below arch.
      floor_triggered=1
      reasons+=("protected-check inconclusive (rc=$protected_rc) — escalating to arch (conservative)")
      printf '[mb-flow-route] WARN: protected-check returned rc=%s — escalating route to arch (conservative)\n' \
        "$protected_rc" >&2
    fi
  fi

  # depends_on: explicit flag wins; else best-effort auto-derive from goal.md.
  if [ "$depends_on_explicit" -eq 0 ]; then
    depends_on="$(derive_depends_on "$mb")"
  fi
  case "$depends_on" in
    ''|*[!0-9]*) depends_on=0 ;;
  esac
  if [ "$depends_on" -gt 0 ]; then
    floor_triggered=1
    reasons+=("depends_on>0 (=$depends_on)")
  fi

  # --- resolve the route ----------------------------------------------------
  local floor_rank=0
  local floor_field="none"
  local floor_bool="false"
  if [ "$floor_triggered" -eq 1 ]; then
    floor_rank=3
    floor_field="arch"
    floor_bool="true"
  fi

  local resolved_rank="$candidate_rank"
  if [ "$floor_rank" -gt "$resolved_rank" ]; then
    resolved_rank="$floor_rank"
  fi
  local resolved
  resolved="$(rank_name "$resolved_rank")"

  # --- write the fence (unless dry-run) — REUSE mb-flow-sync.sh -------------
  if [ "$dry_run" -eq 0 ]; then
    local sync_rc=0
    bash "$SCRIPT_DIR/mb-flow-sync.sh" "$mb" --route "$resolved" >&2 || sync_rc=$?
    if [ "$sync_rc" -ne 0 ]; then
      printf '[mb-flow-route] failed to write route into the mb-flow fence (mb-flow-sync rc=%s)\n' "$sync_rc" >&2
      return "$sync_rc"
    fi
  fi

  # --- emit the single JSON object -----------------------------------------
  # Build the JSON via python3 json.dumps so EVERY control character
  # (U+0000..U+001F) is correctly escaped — a hand-rolled escaper cannot
  # guarantee the "always exactly one VALID JSON object" contract. Scalars go
  # through the environment; reasons go through argv (guarded for the empty
  # case so bash 3.2 set -u never expands an empty array).
  if [ "${#reasons[@]}" -gt 0 ]; then
    emit_json "$candidate" "$floor_field" "$resolved" "$floor_bool" "${reasons[@]}"
  else
    emit_json "$candidate" "$floor_field" "$resolved" "$floor_bool"
  fi

  return 0
}

main "$@"
