#!/usr/bin/env bash
# mb-work-review-parse.sh — validate reviewer output for /mb work review-loop.
#
# Reads structured reviewer output from stdin, validates schema, and emits a
# normalized JSON document on stdout that the review-loop driver can consume.
#
# Usage:
#   mb-work-review-parse.sh [--lenient] < reviewer-output
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
#   - verdict == APPROVED allows 0+ issues
#
# Lenient mode (--lenient): if JSON parse fails, attempt Markdown fallback —
# regex `verdict:` and `counts:` lines, with empty issues list.
#
# Exit codes:
#   0  valid, normalized JSON on stdout
#   1  schema/cross-check error (details on stderr)
#   2  usage error (empty stdin, --help)

set -eu

LENIENT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --lenient) LENIENT=1; shift ;;
    -h|--help) sed -n '2,32p' "$0" >&2; exit 0 ;;
    *) echo "[review-parse] unknown arg '$1'" >&2; exit 2 ;;
  esac
done

INPUT=$(cat -)
if [ -z "$INPUT" ]; then
  echo "[review-parse] empty stdin" >&2
  exit 2
fi

REVIEW_INPUT="$INPUT" LENIENT="$LENIENT" python3 - <<'PY'
import json
import os
import re
import sys

text = os.environ.get("REVIEW_INPUT", "")
lenient = os.environ.get("LENIENT") == "1"


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


try:
    data = json.loads(text)
except json.JSONDecodeError as exc:
    if lenient:
        data = parse_markdown(text)
        if data is None:
            fail(f"JSON parse failed and Markdown fallback found no verdict: {exc}")
    else:
        fail(f"JSON parse error: {exc}")

if not isinstance(data, dict):
    fail("top-level must be an object")

verdict = data.get("verdict")
if verdict not in ("APPROVED", "CHANGES_REQUESTED"):
    fail(f"verdict: must be APPROVED or CHANGES_REQUESTED (got {verdict!r})")

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

issues = data.get("issues", [])
if not isinstance(issues, list):
    fail("issues: must be a list")

normalized_issues = []
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

if verdict == "CHANGES_REQUESTED" and len(normalized_issues) == 0:
    fail("CHANGES_REQUESTED verdict requires non-empty issues list")

print(json.dumps({
    "verdict": verdict,
    "counts": normalized_counts,
    "issues": normalized_issues,
}, ensure_ascii=False))
PY
