#!/usr/bin/env bash
# mb-rules-resolve.sh — resolve the rule sources a spec is judged against
# (svp-contract-test-loop C2). Two modes, one JSON contract.
#
#   discovery:  mb-rules-resolve.sh [--repo PATH] [--mb BANK] [--json]
#   validation: mb-rules-resolve.sh --spec SPEC_DIR [--declared-source PATH]...
#                                   [--repo PATH] [--mb BANK] [--json]
#
# DISCOVERY answers "what rules govern this repo": every project source that
# exists — <repo>/AGENTS.md, <repo>/RULES.md, <bank>/RULES.md, the active rule
# profile — and, ONLY when no project source exists at all, the bundled
# rules/RULES.md as an explicitly flagged fallback.
#
# VALIDATION answers "are the sources this spec DECLARED actually there". The
# declarations live as `- [<kind>] <path>` lines in the `## Quality DoD` section
# of <spec-dir>/design.md — the exact block C5 generates, so the loop is closed:
# C5 writes it, C2 reads it. A declared source that is missing is a LOUD failure
# (exit 1), never a quiet fallback: answering a question about the project's
# rules with the bundled rules would let a reviewer cite a criterion the project
# never adopted (REQ-017).
#
# Declared paths are repo-relative BY CONTRACT, and the grammar is enforced
# before the filesystem is touched: an absolute path or a `..` segment is
# malformed (exit 2), not "missing" — otherwise the exit code of this script
# would answer "does /etc/shadow exist" for any path an attacker can get into a
# spec file.
#
# stdout: {"sources":[{"path","kind"}...],"review_rubric":[...],
#          "fallback_used":bool,"checker":"scripts/mb-rules-check.sh"}
#         `sources` sorted by path (LC_ALL=C) so one input gives one
#         byte-identical output — that byte-identity is what lets implementer,
#         reviewer and judge be shown provably the same criterion (NFR-003, C6).
# stderr: `rule_source_missing=<path>` (exit 1) · `quality_dod_malformed=<detail>`
#         or `error=usage` (exit 2).
# exit:   0 resolved · 1 a declared source is missing · 2 usage/malformed.
#
# No network, no LLM. Bash 3.2 compatible (NFR-004).

set -euo pipefail

# Physical self-directory through the FULL symlink chain: rules/RULES.md and
# mb-profile.sh are resolved as bundle siblings, so resolving from a symlink's
# directory would let an attacker tree supply a different rule set.
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
SKILL_ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd)"

usage_error() { printf 'error=usage\n' >&2; exit 2; }

REPO=""
BANK=""
SPEC=""
DECLARED=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ "$#" -ge 2 ] || usage_error; REPO="$2"; shift ;;
    --mb) [ "$#" -ge 2 ] || usage_error; BANK="$2"; shift ;;
    --spec) [ "$#" -ge 2 ] || usage_error; SPEC="$2"; shift ;;
    --declared-source)
      [ "$#" -ge 2 ] || usage_error
      DECLARED[${#DECLARED[@]}]="$2"; shift ;;
    # stdout is JSON in both modes by contract; the flag is accepted so the
    # documented invocations work verbatim.
    --json) ;;
    *) usage_error ;;
  esac
  shift
done

[ -n "$REPO" ] || REPO="$(pwd)"
[ -d "$REPO" ] || usage_error
REPO="$(cd -P "$REPO" && pwd)"
[ -n "$BANK" ] || BANK="$REPO/.memory-bank"
# Canonicalise the bank the same way as the repo. Without this, comparing a raw
# `/var/...` bank against a `cd -P`-resolved `/private/var/...` repo on macOS
# produced a `../../../..` chain in the output — a path that reads as
# repo-relative and is not.
[ ! -d "$BANK" ] || BANK="$(cd -P "$BANK" && pwd)"
if [ -n "$SPEC" ]; then
  [ -d "$SPEC" ] || usage_error
  SPEC="$(cd -P "$SPEC" && pwd)"
fi

# The active profile is read through the sanctioned subcommand, with cwd at the
# repo under inspection so the answer is about THAT repo and not this one.
PROFILE_JSON="$(cd "$REPO" && bash "$SCRIPT_DIR/mb-profile.sh" path 2>/dev/null || printf '{}')"

PIPELINE="$BANK/pipeline.yaml"
[ -f "$PIPELINE" ] || PIPELINE="$SKILL_ROOT/references/pipeline.default.yaml"

export MBR_REPO="$REPO" MBR_BANK="$BANK" MBR_SPEC="$SPEC" \
       MBR_SKILL_ROOT="$SKILL_ROOT" MBR_PIPELINE="$PIPELINE" \
       MBR_PROFILE_JSON="$PROFILE_JSON"

python3 "$SCRIPT_DIR/mb_rules_resolve.py" ${DECLARED[@]+"${DECLARED[@]}"}
