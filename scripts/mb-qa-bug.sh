#!/usr/bin/env bash
# mb-qa-bug.sh — the QA bug registry <bank>/qa/bugs.md with monotonic BUG-NNN.
#
# Usage:
#   mb-qa-bug.sh [--mb <bank>] add <critical|major|medium|low> <title> [--run <id>]   # body from stdin
#   mb-qa-bug.sh [--mb <bank>] set <BUG-NNN> <open|fixed|wontfix>
#   mb-qa-bug.sh [--mb <bank>] list [--open]          # "<id> <severity> <status> <title>", critical first
#   mb-qa-bug.sh [--mb <bank>] list --json [--open] [--run <id>]
#   mb-qa-bug.sh [--mb <bank>] gate --run <id> [--gate '{"critical":0,"major":0}']
#
# `list --json` prints the normalized review shape mb-work-severity-gate.sh reads:
# {"verdict","counts":{blocker,major,medium,minor},"issues":[{severity,category:"qa",file,line,message,fix}]};
# critical→blocker, low→minor; file/line come from "- Scenario: <file>, step <N>" (else qa/bugs.md, 0);
# message is "<id> <title>".
# --run keeps bugs whose body has "- Run: <id>" or "- Seen again: <id>".
# `add` prints the id. An open bug with the same title is not duplicated: its id is printed and, with
# --run, "- Seen again: <run>" is appended to it. The same title after fixed/wontfix is a new bug.
# `gate` applies qa.gate (critical|major|medium|low → max open bugs) to the open bugs of one run through
# mb-work-severity-gate.sh; a level the gate does not name is unbounded. Exit 0 pass · 1 fail · 2 input error.
# Exit: 0 ok · 1 unknown id or lock timeout · 2 usage.
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

usage() { sed -n '4,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

mb=""
run_id=""
open_only=0
json=0
gate_json='{"critical":0,"major":0}'
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --mb) mb="${2:?--mb needs a path}"; shift 2 ;;
    --mb=*) mb="${1#--mb=}"; shift ;;
    --run) run_id="${2:?--run needs an id}"; shift 2 ;;
    --open) open_only=1; shift ;;
    --json) json=1; shift ;;
    --gate) gate_json="${2:?--gate needs JSON}"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -gt 0 ] || usage
set -- "${args[@]}"

FILE="$(mb_resolve_path "$mb")/qa/bugs.md"

# Header: "### BUG-NNN — <title> [<severity>, <status>, <date>]"; the title may itself contain "[".
# shellcheck disable=SC2016
PARSE='
  function parse(line) {
    if (line !~ /^### BUG-[0-9]+ — / || !match(line, / \[[a-z]+, [a-z]+, [0-9-]+\]$/)) return 0
    id = substr(line, 5, index(line, " — ") - 5)
    start = index(line, " — ") + length(" — ")
    title = substr(line, start, RSTART - start)
    split(substr(line, RSTART + 2, RLENGTH - 3), meta, ", ")
    sev = meta[1]; st = meta[2]
    return 1
  }'

lock() {
  mkdir -p "$(dirname "$FILE")"
  local i=0
  until mkdir "$FILE.lock" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || { echo "[error] registry is locked: $FILE.lock (remove it if no QA run is active)" >&2; exit 1; }
    sleep 0.1
  done
  trap 'rmdir "$FILE.lock" 2>/dev/null || true' EXIT
}

case "$1" in
  add)
    [ $# -eq 3 ] || usage
    sev="$2"; title="$3"
    case "$sev" in critical|major|medium|low) ;; *) echo "[error] severity must be critical|major|medium|low: $sev" >&2; exit 2 ;; esac
    case "$title" in ""|*$'\n'*) echo "[error] title must be one non-empty line" >&2; exit 2 ;; esac
    body=""
    [ -t 0 ] || body="$(cat)"
    lock
    [ -f "$FILE" ] || printf '# Bugs\n' >"$FILE"
    existing=$(awk -v t="$title" "$PARSE"'
      parse($0) && title == t && st == "open" { print id; exit }' "$FILE")
    if [ -n "$existing" ]; then
      if [ -n "$run_id" ]; then
        tmp=$(mktemp)
        awk -v target="$existing" -v seen="- Seen again: $run_id" "$PARSE"'
          function flush() { for (; blanks > 0; blanks--) print "" }
          /^### / { if (in_target) { print seen; flush() } in_target = parse($0) && id == target }
          in_target && /^[[:space:]]*$/ { blanks++; next }
          { flush(); print }
          END { if (in_target) print seen; flush() }' "$FILE" >"$tmp"
        mv "$tmp" "$FILE"
      fi
      echo "$existing"
      exit 0
    fi
    max=$(grep -Eo '^### BUG-[0-9]+' "$FILE" | sed 's/.*BUG-0*//' | sort -n | tail -1 || true)
    id=$(printf 'BUG-%03d' $((${max:-0} + 1)))
    {
      printf '\n### %s — %s [%s, open, %s]\n' "$id" "$title" "$sev" "$(date +%Y-%m-%d)"
      [ -z "$body" ] || printf '%s\n' "$body"
    } >>"$FILE"
    echo "$id"
    ;;
  set)
    [ $# -eq 3 ] || usage
    target="$2"; status="$3"
    case "$status" in open|fixed|wontfix) ;; *) echo "[error] status must be open|fixed|wontfix: $status" >&2; exit 2 ;; esac
    lock
    [ -f "$FILE" ] || { echo "[error] no registry: $FILE" >&2; exit 1; }
    tmp=$(mktemp)
    awk -v target="$target" -v status="$status" "$PARSE"'
      parse($0) && id == target {
        sub(/ \[[a-z]+, [a-z]+, /, " [" sev ", " status ", ")
        found = 1
      }
      { print }
      END { exit found ? 0 : 1 }' "$FILE" >"$tmp" || { rm -f "$tmp"; echo "[error] unknown bug: $target" >&2; exit 1; }
    mv "$tmp" "$FILE"
    [ "$status" != fixed ] || FILE="$FILE" TARGET="$target" python3 - <<'PY'
import os, re

# Regression case for a fixed critical/major bug: reg-<bug id> beside the scenario that found it, never overwritten.
bank = os.path.dirname(os.path.dirname(os.environ["FILE"]))
head, hit, body = None, False, []
for line in open(os.environ["FILE"], encoding="utf-8").read().splitlines():
    m = re.match(r"^### (BUG-\d+) — .* \[([a-z]+), [a-z]+, [0-9-]+\]$", line)
    if m:
        head = m[1] == os.environ["TARGET"] and m[2] in ("critical", "major")
        hit = hit or head
    elif line.startswith("### "):
        head = None
    elif head:
        body.append(line.strip())
if not hit:
    raise SystemExit
field = lambda key: next((x[len(key):] for x in body if x.startswith(key)), "")
src = re.sub(r", step \d+$", "", field("- Scenario: "))
src_path = os.path.join(bank, src)
cases = os.path.realpath(os.path.join(bank, "qa", "test_cases"))
if src and not os.path.realpath(src_path).startswith(cases + os.sep):
    print("regression_case=none reason=scenario_outside_test_cases")
    raise SystemExit
if not src or not os.path.isfile(src_path):
    print("regression_case=none reason=no_scenario")
    raise SystemExit
stem = "reg-" + os.environ["TARGET"].lower()
rel = os.path.join(os.path.dirname(src), stem + ".md")
if os.path.exists(os.path.join(bank, rel)):
    print(f"regression_case={rel} exists")
    raise SystemExit
fm = open(src_path, encoding="utf-8").read().split("---")[1:2]
get = lambda key, default: next((x for x in (fm[0].splitlines() if fm else []) if x.startswith(key + ":")), f"{key}: {default}")
case = os.path.basename(src)
text = f"""---
id: {stem}
{get("tags", "[]")}
{get("driver", "cli")}
{get("covers", "[]")}
origin: regression
proof: both
---
# Regression {os.environ["TARGET"]}

## Preconditions
- as in {case}

## Steps
1. {field("- Steps: ")} -> {field("- Expected: ")}

## Pass criteria
- {field("- Expected: ")}

## Cleanup
- as in {case}
"""
open(os.path.join(bank, rel), "w", encoding="utf-8").write(text)
print(f"regression_case={rel}")
PY
    ;;
  list)
    [ $# -eq 1 ] || usage
    if [ "$json" = 1 ]; then
      FILE="$FILE" OPEN_ONLY="$open_only" RUN_ID="$run_id" python3 - <<'PY'
import json, os, re

SEVERITY = {"critical": "blocker", "major": "major", "medium": "medium", "low": "minor"}
HEADER = re.compile(r"^### (BUG-\d+) — (.*) \[([a-z]+), ([a-z]+), [0-9-]+\]$")
bugs, run = [], os.environ["RUN_ID"]
text = open(os.environ["FILE"], encoding="utf-8").read() if os.path.isfile(os.environ["FILE"]) else ""
for line in text.splitlines():
    m = HEADER.match(line)
    if m:
        bugs.append({"id": m[1], "title": m[2], "sev": m[3], "st": m[4], "body": []})
    elif line.startswith("### "):
        bugs.append({"sev": None, "body": []})  # a non-bug heading ends the previous body
    elif bugs:
        bugs[-1]["body"].append(line.strip())
issues = []
for b in bugs:
    if b["sev"] not in SEVERITY or (os.environ["OPEN_ONLY"] == "1" and b["st"] != "open"):
        continue
    if run and f"- Run: {run}" not in b["body"] and f"- Seen again: {run}" not in b["body"]:
        continue
    scen = next((x[len("- Scenario: "):] for x in b["body"] if x.startswith("- Scenario: ")), "")
    m = re.match(r"(.*), step (\d+)$", scen)
    issues.append({"severity": SEVERITY[b["sev"]], "category": "qa", "file": m[1] if m else scen or "qa/bugs.md",
                   "line": int(m[2]) if m else 0, "message": f"{b['id']} {b['title']}", "fix": ""})
order = list(SEVERITY.values())
issues.sort(key=lambda i: (order.index(i["severity"]), i["message"].split(" ", 1)[0]))
counts = {sev: sum(i["severity"] == sev for i in issues) for sev in order}
print(json.dumps({"verdict": "CHANGES_REQUESTED" if issues else "APPROVED", "counts": counts, "issues": issues}))
PY
      exit 0
    fi
    [ -z "$run_id" ] || usage
    [ -f "$FILE" ] || exit 0
    awk -v open_only="$open_only" "$PARSE"'
      BEGIN { rank["critical"] = 1; rank["major"] = 2; rank["medium"] = 3; rank["low"] = 4 }
      parse($0) && (!open_only || st == "open") { printf "%d\t%s %s %s %s\n", rank[sev], id, sev, st, title }
    ' "$FILE" | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2-
    ;;
  gate)
    [ $# -eq 1 ] && [ -n "$run_id" ] || usage
    mapped=$(GATE="$gate_json" python3 - <<'PY'
import json, os, sys

SEVERITY = {"critical": "blocker", "major": "major", "medium": "medium", "low": "minor"}
try:
    gate = json.loads(os.environ["GATE"])
    assert isinstance(gate, dict) and set(gate) <= set(SEVERITY), "keys must be critical|major|medium|low"
    assert all(type(v) is int and v >= 0 for v in gate.values()), "limits must be non-negative ints"
except (ValueError, AssertionError) as exc:
    sys.exit(f"[error] bad --gate {os.environ['GATE']!r}: {exc}")
# Unnamed levels get no limit: the severity gate treats a missing level as 0.
print(json.dumps({SEVERITY[k]: gate.get(k, sys.maxsize) for k in SEVERITY}))
PY
    ) || exit 2
    counts=$(bash "$0" ${mb:+--mb "$mb"} list --json --open --run "$run_id" |
      python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["counts"]))')
    exec bash "$(dirname "$0")/mb-work-severity-gate.sh" ${mb:+--mb "$mb"} --counts-stdin --ignore-approval \
      --gate "$mapped" <<<"$counts"
    ;;
  *) usage ;;
esac
