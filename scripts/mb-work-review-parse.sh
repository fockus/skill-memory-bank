#!/usr/bin/env bash
# mb-work-review-parse.sh — validate reviewer output for /mb work review-loop.
#
# Reads structured reviewer output from stdin, validates schema, and emits a
# normalized JSON document on stdout that the review-loop driver can consume.
#
# Usage:
#   mb-work-review-parse.sh [--lenient|--external] [--require-tests-blocker] < reviewer-output
#
# Schema (strict):
#   {
#     "verdict": "APPROVED" | "CHANGES_REQUESTED",
#     "counts": {"blocker": int, "major": int, "minor": int},   # all >= 0
#     "issues": [
#       {"severity": "blocker|major|minor",
#        "category": "...",
#        "file": "...",
#        "line": int,
#        "message": "...",
#        "fix": "..."}    # optional
#     ]
#   }
#
# Cross-checks:
#   - verdict == CHANGES_REQUESTED requires len(issues) > 0
#   - verdict == APPROVED requires len(issues) == 0 and all counts == 0
#
# Lenient mode (--lenient): if JSON parse fails, attempt Markdown fallback —
# regex `verdict:` and `counts:` lines, with empty issues list.
#
# External mode (--external): lenient normalization for cross-model reviewers
# (e.g. the codex-reviewer subagent contract, ~/.claude/agents/codex-reviewer.md).
# Implies --lenient's Markdown fallback, plus:
#   - top-level {"status":"SKIPPED","reason":...} passes through as
#     {"verdict":"SKIPPED","reason":...,"counts":{blocker:0,major:0,minor:0},
#     "issues":[]}, exit 0 — the parser never fabricates a verdict for a
#     skipped review.
#   - issue schema mapping: description->message, recommendation->fix,
#     severity "info" (or any value outside blocker|major|minor)->"minor",
#     missing/invalid line->0.
#   - counts are always recomputed from the normalized issues — a cross-model
#     reviewer's self-reported counts are never trusted.
#   - an APPROVED verdict carrying non-empty issues is downgraded to
#     CHANGES_REQUESTED (stricter, never looser).
#
# --require-tests-blocker (opt-in safety net, reviewer-2.0 design.md §5
# "Reviewer obligation"; REQ-103): pass this ONLY when the caller already
# knows this item's touched-file tests were failing (e.g. mb-review.sh's
# payload carried a "## Auto-generated findings (MUST INCLUDE)" section).
# After normalization, if the issue list has no entry with
# category=="tests" AND severity=="blocker", the parser PREPENDS one
# (auto-generated, file="", line=0), sets verdict to CHANGES_REQUESTED,
# increments counts.blocker, and logs a one-line WARNING to stderr. This
# also fires when the review itself parsed as an external SKIPPED
# passthrough — a cross-model review that never ran must not let a red
# test slip through the gate either. Idempotent: a tests/blocker issue
# already present (severity not downgraded) is left untouched, never
# duplicated. Without this flag, output is byte-identical to today's
# behavior (REQ-105) — it is dead code unless explicitly requested.
#
# Exit codes:
#   0  valid, normalized JSON on stdout
#   1  schema/cross-check error (details on stderr)
#   2  usage error (empty stdin, --help)

set -eu

LENIENT=0
EXTERNAL=0
REQUIRE_TESTS_BLOCKER=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --lenient) LENIENT=1; shift ;;
    --external) EXTERNAL=1; shift ;;
    --require-tests-blocker) REQUIRE_TESTS_BLOCKER=1; shift ;;
    -h|--help) sed -n '2,64p' "$0" >&2; exit 0 ;;
    *) echo "[review-parse] unknown arg '$1'" >&2; exit 2 ;;
  esac
done

INPUT=$(cat -)
if [ -z "$INPUT" ]; then
  echo "[review-parse] empty stdin" >&2
  exit 2
fi

REVIEW_INPUT="$INPUT" LENIENT="$LENIENT" EXTERNAL="$EXTERNAL" \
REQUIRE_TESTS_BLOCKER="$REQUIRE_TESTS_BLOCKER" python3 - <<'PY'
import json
import os
import re
import sys

text = os.environ.get("REVIEW_INPUT", "")
lenient = os.environ.get("LENIENT") == "1"
external = os.environ.get("EXTERNAL") == "1"
require_tests_blocker = os.environ.get("REQUIRE_TESTS_BLOCKER") == "1"

AUTO_TESTS_BLOCKER_MESSAGE = (
    "auto-generated tests blocker restored; touched-file tests failing and "
    "the reviewer omitted the mandatory finding"
)


def fail(msg: str) -> None:
    sys.stderr.write(f"[review-parse] {msg}\n")
    sys.exit(1)


def parse_markdown(s: str) -> dict | None:
    m_v = re.search(r"verdict\s*:\s*([A-Z_]+)", s)
    if not m_v:
        return None
    verdict = m_v.group(1)
    counts = {"blocker": 0, "major": 0, "minor": 0}
    m_c = re.search(r"counts\s*:\s*\{([^}]*)\}", s)
    if m_c:
        for k in counts:
            mm = re.search(rf"{k}\s*:\s*(\d+)", m_c.group(1))
            if mm:
                counts[k] = int(mm.group(1))
    return {"verdict": verdict, "counts": counts, "issues": []}


def has_tests_blocker(issues: list) -> bool:
    """True if `issues` already carries a category=="tests"/severity=="blocker"
    entry (REQ-103 "cannot drop" — a demoted severity or moved category does
    NOT count as present; the reviewer must not be allowed to soften it)."""
    return any(
        isinstance(i, dict) and i.get("category") == "tests" and i.get("severity") == "blocker"
        for i in issues
    )


def build_auto_tests_blocker() -> dict:
    return {
        "severity": "blocker",
        "category": "tests",
        "file": "",
        "line": 0,
        "message": AUTO_TESTS_BLOCKER_MESSAGE,
    }


try:
    data = json.loads(text)
except json.JSONDecodeError as exc:
    if lenient or external:
        data = parse_markdown(text)
        if data is None:
            fail(f"JSON parse failed and Markdown fallback found no verdict: {exc}")
    else:
        fail(f"JSON parse error: {exc}")

if not isinstance(data, dict):
    fail("top-level must be an object")

if external and data.get("status") == "SKIPPED":
    reason = data.get("reason") or "cross-model review unavailable"
    if require_tests_blocker:
        # --require-tests-blocker is only ever passed when the caller already
        # knows this item's touched-file tests were failing. A review that
        # never ran (SKIPPED) had no chance to include the mandatory finding
        # either -- so the same safety net applies: restore the blocker,
        # force CHANGES_REQUESTED, never let a red test slip through a
        # skipped cross-model review (REQ-103).
        sys.stderr.write(
            "[review-parse] WARNING: tests blocker restored "
            f"(cross-model review SKIPPED: {reason})\n"
        )
        print(json.dumps({
            "verdict": "CHANGES_REQUESTED",
            "reason": reason,
            "counts": {"blocker": 1, "major": 0, "minor": 0},
            "issues": [build_auto_tests_blocker()],
        }, ensure_ascii=False))
        sys.exit(0)
    print(json.dumps({
        "verdict": "SKIPPED",
        "reason": reason,
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": [],
    }, ensure_ascii=False))
    sys.exit(0)

verdict = data.get("verdict")
if verdict not in ("APPROVED", "CHANGES_REQUESTED"):
    fail(f"verdict: must be APPROVED or CHANGES_REQUESTED (got {verdict!r})")

issues = data.get("issues", [])
if not isinstance(issues, list):
    fail("issues: must be a list")

normalized_issues = []
if external:
    # Lenient normalization for cross-model reviewers (e.g. codex-reviewer):
    # map the alternate schema and never trust self-reported counts.
    for idx, raw in enumerate(issues):
        if not isinstance(raw, dict):
            fail(f"issues[{idx}]: must be an object")
        sev = raw.get("severity")
        if sev not in ("blocker", "major", "minor"):
            sev = "minor"
        message = raw.get("message") or raw.get("description") or ""
        line = raw.get("line")
        if not isinstance(line, int) or isinstance(line, bool) or line < 0:
            line = 0
        item = {
            "severity": sev,
            "category": raw.get("category") or "",
            "file": raw.get("file") or "",
            "line": line,
            "message": message,
        }
        fix = raw.get("fix") or raw.get("recommendation")
        if fix:
            item["fix"] = fix
        normalized_issues.append(item)

    normalized_counts = {"blocker": 0, "major": 0, "minor": 0}
    for item in normalized_issues:
        normalized_counts[item["severity"]] += 1

    if verdict == "APPROVED" and normalized_issues:
        verdict = "CHANGES_REQUESTED"
    # Fix-cycle 1 MAJOR #2: under --require-tests-blocker, a fully-omitted
    # mandatory finding (verdict:CHANGES_REQUESTED, issues:[]) must be silently
    # RESTORED by the safety net below, not rejected here -- rejecting it burns
    # the review-loop's one bounded retry on exactly the failure mode the flag
    # exists to recover from. Without the flag, behavior is unchanged (REQ-105).
    if verdict == "CHANGES_REQUESTED" and not normalized_issues and not require_tests_blocker:
        fail("CHANGES_REQUESTED verdict requires non-empty issues list")
else:
    counts = data.get("counts")
    if not isinstance(counts, dict):
        fail("counts: must be an object")

    normalized_counts = {"blocker": 0, "major": 0, "minor": 0}
    for k in ("blocker", "major", "minor"):
        if k in counts:
            v = counts[k]
            if not isinstance(v, int) or isinstance(v, bool) or v < 0:
                fail(f"counts.{k}: must be int >= 0 (got {v!r})")
            normalized_counts[k] = v

    for idx, raw in enumerate(issues):
        if not isinstance(raw, dict):
            fail(f"issues[{idx}]: must be an object")
        sev = raw.get("severity")
        if sev not in ("blocker", "major", "minor"):
            fail(f"issues[{idx}].severity: must be blocker|major|minor (got {sev!r})")
        for required in ("category", "file", "message"):
            if not raw.get(required):
                fail(f"issues[{idx}].{required}: required, missing or empty")
        line = raw.get("line")
        if not isinstance(line, int) or isinstance(line, bool) or line < 0:
            fail(f"issues[{idx}].line: must be int >= 0 (got {line!r})")
        item = {
            "severity": sev,
            "category": raw["category"],
            "file": raw["file"],
            "line": line,
            "message": raw["message"],
        }
        if raw.get("fix"):
            item["fix"] = raw["fix"]
        normalized_issues.append(item)

    # Fix-cycle 1 MAJOR #2: same restore-not-reject rule as the --external
    # branch above -- see its comment.
    if verdict == "CHANGES_REQUESTED" and len(normalized_issues) == 0 and not require_tests_blocker:
        fail("CHANGES_REQUESTED verdict requires non-empty issues list")

    if verdict == "APPROVED":
        if normalized_issues:
            fail("APPROVED verdict requires an empty issues list")
        nonzero = {k: v for k, v in normalized_counts.items() if v != 0}
        if nonzero:
            fail(f"APPROVED verdict requires zero counts (got {nonzero})")

    if require_tests_blocker:
        # Fix-cycle 1 BLOCKER #1 (codex NO_GO): strict mode must not trust
        # self-reported counts under the flag either. A reviewer can emit a
        # genuine category=="tests"/severity=="blocker" issue -- which makes
        # has_tests_blocker() below TRUE, so the safety net correctly stays
        # silent -- while self-reporting counts.blocker=0.
        # mb-work-severity-gate.sh reads ONLY counts, never issues, so with
        # blocker_max=0 that self-reported lie would let a real red-test
        # blocker pass the gate. Recomputing from the now-validated issues
        # (same technique --external already always applies) closes the whole
        # count-lie class. Only runs under the opt-in flag -- self-reported
        # counts stay authoritative without it, so REQ-105 byte-identity holds.
        normalized_counts = {"blocker": 0, "major": 0, "minor": 0}
        for item in normalized_issues:
            normalized_counts[item["severity"]] += 1

# REQ-103 safety net (design.md §5 "Reviewer obligation") -- shared by both
# --external and strict-mode callers, applied once normalization/validation
# above has produced a final verdict/counts/issues. verdict is never
# "SKIPPED" here (that path already exited above); the check stays anyway so
# this stays correct if a future caller reaches this point with one.
# Idempotent: a tests/blocker issue already present short-circuits the `not`.
if require_tests_blocker and verdict != "SKIPPED" and not has_tests_blocker(normalized_issues):
    sys.stderr.write(
        "[review-parse] WARNING: reviewer output omitted the mandatory tests/blocker "
        "finding for failing touched-file tests -- restoring it and forcing "
        "CHANGES_REQUESTED\n"
    )
    normalized_issues = [build_auto_tests_blocker()] + normalized_issues
    normalized_counts["blocker"] += 1
    verdict = "CHANGES_REQUESTED"

print(json.dumps({
    "verdict": verdict,
    "counts": normalized_counts,
    "issues": normalized_issues,
}, ensure_ascii=False))
PY
