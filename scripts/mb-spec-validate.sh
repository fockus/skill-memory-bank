#!/usr/bin/env bash
# mb-spec-validate.sh — validate the integrity of a Kiro-style spec triple.
#
# A spec triple lives at `<mb>/specs/<topic>/` and contains:
#   - requirements.md  (EARS REQ list)
#   - design.md        (architecture / interfaces / decisions / risks)
#   - tasks.md         (numbered tasks with <!-- mb-task:N --> markers)
#
# Checks performed (each violation → one entry on stderr / JSON list):
#   1. requirements.md exists and passes `mb-ears-validate.sh`.
#   2. tasks.md exists and `mb_work_items.parse_work_items()` returns ≥ 1 item.
#   3. Each task has a non-empty `**Covers:**` field.
#   4. Each task has ≥ 1 DoD checkbox line.
#   5. Each task body contains a `Testing` section (case-insensitive).
#   6. Each REQ-NNN from requirements.md is referenced by ≥ 1 task's covers.
#   7. Any GIVEN/WHEN/THEN scenarios present in requirements.md are well-formed
#      (each has a name, Covers, and ≥1 GIVEN/WHEN/THEN). Specs WITHOUT scenarios
#      are unaffected — this check is a no-op when no scenario blocks exist.
#   8. (--require-scenarios, opt-in) Each REQ-NNN is covered by ≥ 1 scenario.
#      OFF by default so existing EARS-only specs stay valid.
#   9. (--require-tests, opt-in) Each REQ-NNN is referenced by ≥ 1 test under
#      `<repo>/tests/` or `<mb>/tests/` (the same scan traceability uses). Closes
#      the REQ→test loop: a requirement with no covering test is a violation.
#      OFF by default. Pair with `/mb verify` (which proves the tests pass).
#      NOTE: the repo root is derived from the bank's parent (local-mode `.memory-bank`).
#      For a GLOBAL-storage bank — or tests in a sub-package — pass an ABSOLUTE
#      `MB_TEST_ROOTS` so the scan hits the real checkout. Coverage is matched on the
#      canonical REQ-ID; under per-spec-local numbering a bare `REQ-NNN` shared by two
#      specs can be satisfied by either spec's test — prefer prefixed schemes
#      (`REQ-RS-008`) or spec-qualified markers to avoid cross-spec attribution.
#
# Usage:
#   mb-spec-validate.sh [--json] [--require-scenarios] [--require-tests] <topic|spec-dir|spec-file> [mb_path]
#
# Resolver:
#   - If the first non-flag argument points to an existing directory or file →
#     used directly (a file is treated as its parent directory).
#   - Otherwise → resolved to `<mb>/specs/<arg>/` (mb defaults via `mb_resolve_path`).
#
# Exit codes:
#   0 — clean (no violations)
#   1 — one or more violations (details on stderr; --json prints structured)
#   2 — usage / resolver error

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

JSON_MODE=0
REQUIRE_SCENARIOS=0
REQUIRE_TESTS=0
TARGET=""
MB_ARG=""

for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=1 ;;
    --require-scenarios) REQUIRE_SCENARIOS=1 ;;
    --require-tests) REQUIRE_TESTS=1 ;;
    -h|--help)
      sed -n '2,44p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$arg"
      else
        MB_ARG="$arg"
      fi
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: mb-spec-validate.sh [--json] <topic|spec-dir|spec-file> [mb_path]" >&2
  exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
EARS_SCRIPT="$SCRIPT_DIR/mb-ears-validate.sh"
WORK_ITEMS_SCRIPT="$SCRIPT_DIR/mb_work_items.py"
SCENARIO_SCRIPT="$SCRIPT_DIR/mb-scenario-extract.py"

# ─────────────────────────────────────────────────────────────────────────────
# Resolve the spec directory.
# ─────────────────────────────────────────────────────────────────────────────

SPEC_DIR=""
if [ -d "$TARGET" ]; then
  SPEC_DIR="$TARGET"
elif [ -f "$TARGET" ]; then
  SPEC_DIR=$(dirname "$TARGET")
else
  # Treat as topic; resolve under <mb>/specs/<topic>/.
  MB_PATH=$(mb_resolve_path "$MB_ARG")
  if [ -z "$MB_PATH" ] || [ ! -d "$MB_PATH" ]; then
    echo "[error] memory bank not found at: ${MB_PATH:-<unset>}" >&2
    exit 2
  fi
  SAFE_TOPIC=$(mb_sanitize_topic "$TARGET")
  if [ -z "$SAFE_TOPIC" ]; then
    echo "[error] topic contains only non-ASCII characters: $TARGET" >&2
    exit 2
  fi
  SPEC_DIR="$MB_PATH/specs/$SAFE_TOPIC"
  if [ ! -d "$SPEC_DIR" ]; then
    echo "[error] spec directory not found: $SPEC_DIR" >&2
    exit 2
  fi
fi

REQ_FILE="$SPEC_DIR/requirements.md"
TASKS_FILE="$SPEC_DIR/tasks.md"

# ─────────────────────────────────────────────────────────────────────────────
# Collect violations into a temp file so we can both print them and emit JSON.
# ─────────────────────────────────────────────────────────────────────────────

VIOLATIONS_FILE=$(mktemp -t mb-spec-validate.XXXXXX)
WAIVERS_FILE=$(mktemp -t mb-spec-validate-waivers.XXXXXX)
trap 'rm -f "$VIOLATIONS_FILE" "$WAIVERS_FILE"' EXIT

DESIGN_FILE="$SPEC_DIR/design.md"
SPECS_ROOT=$(dirname "$SPEC_DIR")

record_violation() {
  printf '%s\n' "$1" >>"$VIOLATIONS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Check 1: requirements.md exists + EARS valid.
# ─────────────────────────────────────────────────────────────────────────────

if [ ! -f "$REQ_FILE" ]; then
  record_violation "requirements.md missing in $SPEC_DIR"
else
  EARS_STDERR=$(bash "$EARS_SCRIPT" "$REQ_FILE" 2>&1 >/dev/null) || EARS_EXIT=$?
  EARS_EXIT="${EARS_EXIT:-0}"
  if [ "$EARS_EXIT" -ne 0 ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && record_violation "EARS: $line"
    done <<<"$EARS_STDERR"
  fi
  unset EARS_EXIT
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 2: tasks.md exists + parses to ≥ 1 WorkItem.
# ─────────────────────────────────────────────────────────────────────────────

TASKS_JSONL=""
if [ ! -f "$TASKS_FILE" ]; then
  record_violation "tasks.md missing in $SPEC_DIR"
else
  PARSE_EXIT=0
  TASKS_JSONL=$(python3 "$WORK_ITEMS_SCRIPT" "$TASKS_FILE" 2>&1) || PARSE_EXIT=$?
  if [ "$PARSE_EXIT" -eq 2 ]; then
    # Malformed v2 field (e.g. restricted-glob Scope violation, R3-004): a
    # structural/format error, surfaced as usage exit 2 — not a content
    # violation. The accepted tasks.md is left untouched.
    printf '[spec-validate] tasks.md malformed field: %s\n' "${TASKS_JSONL//$'\n'/ | }" >&2
    exit 2
  elif [ "$PARSE_EXIT" -ne 0 ]; then
    record_violation "tasks.md unparseable: ${TASKS_JSONL//$'\n'/ | }"
    TASKS_JSONL=""
  fi

  if [ -n "$TASKS_JSONL" ]; then
    TASK_COUNT=$(printf '%s\n' "$TASKS_JSONL" | grep -c . || true)
    if [ "$TASK_COUNT" -eq 0 ]; then
      record_violation "tasks.md contains no <!-- mb-task:N --> markers"
    fi
  else
    # Empty stdout from parser is legitimate only when tasks.md is empty.
    # Treat that as "no tasks" violation too.
    if [ -f "$TASKS_FILE" ]; then
      record_violation "tasks.md contains no <!-- mb-task:N --> markers"
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Checks 3-5: per-task validation (covers, DoD, Testing section).
# Check 6: REQ orphan detection.
# ─────────────────────────────────────────────────────────────────────────────

if [ -n "$TASKS_JSONL" ] && [ -f "$REQ_FILE" ]; then
  TASKS_DATA="$TASKS_JSONL" REQ_PATH="$REQ_FILE" MB_SCRIPT_DIR="$SCRIPT_DIR" \
    python3 - >>"$VIOLATIONS_FILE" <<'PY'
import json
import os
import re
import sys

sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
import mb_req_id as rq  # shared REQ-ID grammar (scheme + slash + def-vs-mention)

tasks_raw = os.environ.get("TASKS_DATA", "")
req_path = os.environ.get("REQ_PATH", "")

tasks = []
for line in tasks_raw.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        tasks.append(json.loads(line))
    except json.JSONDecodeError:
        # Already reported by check 2; skip silently here.
        continue

req_text = ""
if req_path and os.path.exists(req_path):
    with open(req_path, encoding="utf-8") as fh:
        req_text = fh.read()
req_ids = set(rq.find_definitions(req_text))

covered: set[str] = set()
testing_re = re.compile(r"\btesting\b", re.IGNORECASE)
for item in tasks:
    no = item.get("item_no", "?")
    covers = item.get("covers") or []
    if not covers:
        print(f"task {no} missing Covers field")
    covered.update(rq.extract_req_ids(", ".join(str(c) for c in covers)))
    if not item.get("dod_lines"):
        print(f"task {no} missing DoD checkboxes")
    body = item.get("body") or ""
    if not testing_re.search(body):
        print(f"task {no} missing Testing section")

for req in sorted(req_ids):
    if req not in covered:
        print(f"{req} orphan (no task Covers)")
PY
fi

# ─────────────────────────────────────────────────────────────────────────────
# Checks 7-8: GIVEN/WHEN/THEN scenarios.
#   7 (always): present scenarios must be well-formed — no-op when none exist.
#   8 (--require-scenarios): every REQ must be covered by ≥1 scenario.
# ─────────────────────────────────────────────────────────────────────────────

if [ -f "$REQ_FILE" ] && [ -f "$SCENARIO_SCRIPT" ]; then
  SCEN_STDERR=$(python3 "$SCENARIO_SCRIPT" --validate "$REQ_FILE" 2>&1 >/dev/null) || SCEN_EXIT=$?
  SCEN_EXIT="${SCEN_EXIT:-0}"
  if [ "$SCEN_EXIT" -ne 0 ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && record_violation "${line#\[scenario\] }"
    done <<<"$SCEN_STDERR"
  fi
  unset SCEN_EXIT

  if [ "$REQUIRE_SCENARIOS" -eq 1 ]; then
    SCEN_JSONL=$(python3 "$SCENARIO_SCRIPT" "$REQ_FILE" 2>/dev/null || true)
    REQ_PATH="$REQ_FILE" SCEN_DATA="$SCEN_JSONL" MB_SCRIPT_DIR="$SCRIPT_DIR" \
      python3 - >>"$VIOLATIONS_FILE" <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
import mb_req_id as rq
req_text = open(os.environ["REQ_PATH"], encoding="utf-8").read()
req_ids = set(rq.find_definitions(req_text))
covered: set[str] = set()
for line in os.environ.get("SCEN_DATA", "").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        s = json.loads(line)
    except json.JSONDecodeError:
        continue
    covered.update(rq.extract_req_ids(", ".join(str(c) for c in s.get("covers") or [])))
for req in sorted(req_ids):
    if req not in covered:
        print(f"{req} has no scenario (--require-scenarios)")
PY
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 9: (--require-tests) every REQ referenced by ≥1 test file.
#   Scans <repo>/tests and <mb>/tests by default; MB_TEST_ROOTS (colon-separated,
#   relative to the repo root or absolute) points at a sub-package's tests.
# ─────────────────────────────────────────────────────────────────────────────

if [ "$REQUIRE_TESTS" -eq 1 ] && [ -f "$REQ_FILE" ]; then
  # SPEC_DIR is <mb>/specs/<topic>; derive <mb> and the repo root from it.
  MB_GUESS=$(cd "$SPEC_DIR/../.." 2>/dev/null && pwd) || MB_GUESS=""
  REPO_GUESS=""
  if [ -n "$MB_GUESS" ]; then
    REPO_GUESS=$(cd "$MB_GUESS/.." 2>/dev/null && pwd) || REPO_GUESS=""
  fi
  REQ_PATH="$REQ_FILE" MB_SCRIPT_DIR="$SCRIPT_DIR" \
    MB_GUESS="$MB_GUESS" REPO_GUESS="$REPO_GUESS" \
    python3 - >>"$VIOLATIONS_FILE" <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
import mb_req_id as rq

req_text = open(os.environ["REQ_PATH"], encoding="utf-8").read()
req_ids = set(rq.find_definitions(req_text))

repo = os.environ.get("REPO_GUESS", "")
mb = os.environ.get("MB_GUESS", "")
env_roots = os.environ.get("MB_TEST_ROOTS", "").strip()
roots: list[Path] = []
if env_roots and repo:
    for r in env_roots.split(":"):
        r = r.strip()
        if r:
            roots.append(Path(r) if os.path.isabs(r) else Path(repo) / r)
elif env_roots:
    roots = [Path(r.strip()) for r in env_roots.split(":") if r.strip()]
else:
    if repo:
        roots.append(Path(repo) / "tests")
    if mb:
        roots.append(Path(mb) / "tests")

exts = {".py", ".ts", ".tsx", ".js", ".go", ".rs", ".sh", ".kt", ".swift", ".rb", ".java"}
covered: set[str] = set()
for root in roots:
    if not root.is_dir():
        continue
    for tf in root.rglob("*"):
        if tf.is_file() and tf.suffix in exts:
            try:
                covered.update(rq.find_test_ids(tf.read_text(encoding="utf-8", errors="ignore")))
            except OSError:
                continue

for req in sorted(req_ids):
    if req not in covered:
        print(f"{req} has no covering test (--require-tests)")
PY
fi

# ─────────────────────────────────────────────────────────────────────────────
# Checks 10-16: tasks.md v2 / C8 battery gates.
#   Blocked-by cycle (REQ-052) runs on every spec. The Eval/waiver/seam/role/
#   parity/cross-spec/byte-identity gates run only when the spec uses the Eval
#   feature (≥1 **Eval:** field) — legacy specs gain zero new errors (D-26).
# ─────────────────────────────────────────────────────────────────────────────

if [ -n "$TASKS_JSONL" ] && [ -f "$REQ_FILE" ]; then
  TASKS_DATA="$TASKS_JSONL" REQ_PATH="$REQ_FILE" DESIGN_PATH="$DESIGN_FILE" \
    SPECS_ROOT="$SPECS_ROOT" WAIVERS_FILE="$WAIVERS_FILE" MB_SCRIPT_DIR="$SCRIPT_DIR" \
    python3 - >>"$VIOLATIONS_FILE" <<'PY'
import json, os, re, subprocess, sys
sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
import mb_req_id as rq

def ere_ok(pattern):
    # Validate with the SAME portable engine used at execution time (grep -E):
    # a bad ERE exits 2 (a Python-only construct like `(?=...)` is rejected).
    try:
        return subprocess.run(
            ["grep", "-E", "--", pattern], input="",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True,
        ).returncode != 2
    except OSError:
        return False

def read(p):
    return open(p, encoding="utf-8").read() if p and os.path.exists(p) else ""

tasks = []
for line in os.environ.get("TASKS_DATA", "").splitlines():
    line = line.strip()
    if line:
        try:
            tasks.append(json.loads(line))
        except json.JSONDecodeError:
            pass
req_text = read(os.environ.get("REQ_PATH", ""))
design_text = read(os.environ.get("DESIGN_PATH", ""))
specs_root = os.environ.get("SPECS_ROOT", "")

def covers_of(t):
    return set(rq.extract_req_ids(", ".join(str(c) for c in t.get("covers") or [])))

# Check 10 — Blocked-by cycle (REQ-052), always on (legacy chains are linear).
graph = {t["item_no"]: [int(b) for b in t.get("blocked_by", []) if str(b).isdigit()] for t in tasks}
color = {n: 0 for n in graph}
found = {"path": None}
def dfs(u, stack):
    color[u] = 1; stack.append(u)
    for v in graph.get(u, []):
        if v not in graph:
            continue
        if color[v] == 1:
            found["path"] = stack[stack.index(v):] + [v]; return True
        if color[v] == 0 and dfs(v, stack):
            return True
    color[u] = 2; stack.pop(); return False
for n in list(graph):
    if color[n] == 0 and dfs(n, []):
        break
if found["path"]:
    print("REQ-052: Blocked-by cycle: " + " -> ".join(str(x) for x in found["path"]))

# The remaining gates apply only to specs using the Eval feature. A legacy spec
# (no **Eval:** field) has gated reqs but no evals/seams/§Eval, so running them
# would flag every legacy req — guard the whole battery so it never runs there.
def run_v2_gates():
    # gated = defined REQ carrying a SHALL/MUST modal.
    all_defs = set(rq.find_definitions(req_text))
    gated = set()
    for ln in req_text.splitlines():
        if re.search(r"\b(shall|must)\b", ln, re.I):
            gated |= {r for r in rq.extract_req_ids(ln) if r in all_defs}

    # Checks 11-13 — per-task Eval/waiver/anchor gates.
    eval_covered = set()
    waivers = []
    for t in tasks:
        no = t["item_no"]; ev = t.get("eval"); cov = covers_of(t)
        is_gated = bool(cov & gated)
        if ev is None:
            continue
        if ev.get("cmd") == "none":
            w = ev.get("waiver")
            if is_gated:
                print(f"REQ-007: task {no} declares Eval: none but covers gated {sorted(cov & gated)}")
            elif w is None:
                print(f"REQ-049: task {no} declares Eval: none without a structural Eval or a waiver")
            elif not w.strip():
                print(f"REQ-050: task {no} declares a waiver with an empty reason")
            else:
                waivers.append((no, w.strip()))
            continue
        eval_covered |= cov
        if not (ev.get("red") or "").strip():
            print(f"task {no} Eval declaration is missing a non-empty red: prose")
        ore = ev.get("output_re")
        if is_gated and not ore:
            print(f"REQ-055: task {no} covers a gated req but its Eval has no output~: anchor (exit-only rejected)")
        if ore and not ere_ok(ore):
            print(f"task {no} Eval output~: is not a valid POSIX ERE (grep -E rejects it): {ore}")
        for tok in (ev.get("cmd") or "").split():
            if tok.startswith("/") and "/" in tok:
                print(f"task {no} Eval target is not repo-relative: {tok}")

    # Check 14 — REQ-006 Eval-coverage per gated req (scenario layer = --require-scenarios).
    for req in sorted(gated - eval_covered):
        print(f"REQ-006: gated {req} has no covering Eval declaration")

    # Check 15a — CPR-D: design.md §Eval line byte-identical (backtick/indent-normalized) to tasks.md.
    def norm_eval(s):
        return s.strip().lstrip("- ").replace("`", "").strip()
    d_eval = {}; cur = None
    for ln in design_text.splitlines():
        m = re.match(r"^- \*\*T(\d+)\*\*", ln)
        if m:
            cur = int(m.group(1))
        elif cur is not None and "**Eval:**" in ln:
            d_eval[cur] = norm_eval(ln); cur = None
    if d_eval:
        t_eval = {}
        for t in tasks:
            for bl in (t.get("body") or "").splitlines():
                if bl.strip().startswith("**Eval:**"):
                    t_eval[t["item_no"]] = norm_eval(bl); break
        for n in sorted(d_eval):
            if d_eval[n] != t_eval.get(n):
                print(f"CPR-D: design.md Eval for T{n} is not byte-identical to task {n} in tasks.md")

    # Check 15b — seam gate (REQ-051 / C9): >=2 seams need a non-empty rationale. Skip code fences.
    lines = design_text.splitlines(); in_fence = False; i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("```"):
            in_fence = not in_fence; i += 1; continue
        if not in_fence and s.startswith("**Seams:**"):
            j = i + 1; seams = []; rationale = None
            while j < len(lines):
                sj = lines[j].strip()
                if sj.startswith("- "):
                    seams.append(sj[2:].strip()); j += 1; continue
                if sj.startswith("**Seam rationale:**"):
                    rationale = sj.split(":**", 1)[1].strip(); j += 1
                break
            if len(seams) >= 2 and not rationale:
                print(f"REQ-051: {len(seams)} seams declared without a Seam rationale")
            i = j; continue
        i += 1

    # Check 16a — scenario parity + ASCII names (C8.2).
    headings = re.findall(r"^### Scenario:\s*(.+?)\s*$", req_text, re.M)
    markers = re.findall(r"^<!--\s*mb-scenario:\d+\s*-->\s*$", req_text, re.M)
    if len(headings) != len(markers):
        print(f"C8.2: scenario parity mismatch — {len(headings)} '### Scenario:' headings vs {len(markers)} markers")
    for h in headings:
        if any(ord(c) > 127 for c in h):
            print(f"C8.2: scenario name is not ASCII: {h!r}")

    # Check 16b — role resolution (C8.3): bare dev role required.
    roles = {"backend", "frontend", "developer", "qa", "architect", "ios", "android", "devops", "analyst"}
    for t in tasks:
        role = t.get("role", ""); no = t["item_no"]
        if role.startswith("mb-"):
            print(f"C8.3: task {no} Role '{role}' must be bare — use '{role[3:]}' not '{role}'")
        elif role not in roles:
            print(f"C8.3: task {no} Role '{role}' is not a known dev role")

    # Check 16c — cross-spec Blocked-by resolution (C8.5).
    if specs_root and os.path.isdir(specs_root):
        cache = {}
        def task_nums(topic):
            if topic not in cache:
                p = os.path.join(specs_root, topic, "tasks.md")
                cache[topic] = set(re.findall(r"<!--\s*mb-task:(\d+)\s*-->", read(p))) if os.path.exists(p) else None
            return cache[topic]
        for t in tasks:
            no = t["item_no"]
            for b in t.get("blocked_by", []):
                if "#" in str(b):
                    topic, num = str(b).split("#", 1)
                    nums = task_nums(topic)
                    if nums is None:
                        print(f"C8.5: task {no} Blocked-by '{b}' references unknown spec '{topic}'")
                    elif num not in nums:
                        print(f"C8.5: task {no} Blocked-by '{b}' — spec '{topic}' has no task {num}")

    wf = os.environ.get("WAIVERS_FILE", "")
    if waivers and wf:
        with open(wf, "a", encoding="utf-8") as fh:
            for no, reason in waivers:
                fh.write(f"task {no}: {reason}\n")

if any(t.get("eval") is not None for t in tasks):
    run_v2_gates()
PY
fi

# Accepted waivers are visible in the output even on a clean run (REQ-050).
if [ -s "$WAIVERS_FILE" ]; then
  while IFS= read -r wline; do
    [ -n "$wline" ] && printf '[spec-validate] accepted-waiver: %s\n' "$wline" >&2
  done <"$WAIVERS_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Emit results.
# ─────────────────────────────────────────────────────────────────────────────

if [ "$JSON_MODE" -eq 1 ]; then
  VIOL_FILE="$VIOLATIONS_FILE" python3 - <<'PY'
import json
import os

path = os.environ["VIOL_FILE"]
violations = []
if os.path.exists(path):
    with open(path, encoding="utf-8") as fh:
        violations = [line.rstrip("\n") for line in fh if line.strip()]
print(json.dumps({"violations": violations}, ensure_ascii=False))
PY
fi

if [ -s "$VIOLATIONS_FILE" ]; then
  if [ "$JSON_MODE" -eq 0 ]; then
    while IFS= read -r line; do
      printf '[spec-validate] %s\n' "$line" >&2
    done <"$VIOLATIONS_FILE"
  fi
  exit 1
fi

exit 0
