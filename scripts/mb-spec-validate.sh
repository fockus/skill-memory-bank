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

# Cross-spec `Blocked-by` always resolves against the BANK's specs root when a
# bank is known (review [19]): a staged candidate under `<bank>/tmp/sdd/<topic>`
# used to take `<bank>/tmp/sdd` as its specs root, so every valid dependency on
# an accepted spec was reported unknown on the mandatory pre-promotion C8.
BANK_ROOT=""
if [ -n "$MB_ARG" ]; then
  BANK_ROOT=$(cd "$MB_ARG" 2>/dev/null && pwd) || BANK_ROOT=""
elif [ -n "${MB_PATH:-}" ]; then
  BANK_ROOT=$(cd "$MB_PATH" 2>/dev/null && pwd) || BANK_ROOT=""
fi
if [ -n "$BANK_ROOT" ] && [ -d "$BANK_ROOT/specs" ]; then
  SPECS_ROOT="$BANK_ROOT/specs"
else
  SPECS_ROOT=$(dirname "$SPEC_DIR")
fi

# Roles are normative in the pipeline config, not a hardcoded enum (review [20]).
PIPELINE_YAML=$(bash "$SCRIPT_DIR/mb-pipeline.sh" path "$MB_ARG" 2>/dev/null || true)
[ -n "$PIPELINE_YAML" ] && [ -f "$PIPELINE_YAML" ] || \
  PIPELINE_YAML="$SCRIPT_DIR/../references/pipeline.default.yaml"

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
    python3 "$SCRIPT_DIR/mb_spec_validate_tasks.py" >>"$VIOLATIONS_FILE"
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
  # The checkout is resolved independently of where the bank is stored (review
  # [22]): a registered GLOBAL bank lives under the agent config dir, whose
  # parent is not the project, so deriving the repo from the bank's parent made
  # the scan search a config directory and report every REQ as uncovered.
  MB_GUESS="$BANK_ROOT"
  [ -n "$MB_GUESS" ] || MB_GUESS=$(cd "$SPEC_DIR/../.." 2>/dev/null && pwd) || MB_GUESS=""
  REPO_GUESS=""
  # A LOCAL bank (`<repo>/.memory-bank`) sits inside its checkout, so its parent
  # IS the repo — unchanged. A global/registered bank does not, and its parent is
  # an agent-config directory; there the checkout is resolved from the working
  # directory instead of being guessed from storage layout (review [22]).
  if [ "$(basename "$MB_GUESS")" = ".memory-bank" ]; then
    REPO_GUESS=$(cd "$MB_GUESS/.." 2>/dev/null && pwd) || REPO_GUESS=""
  else
    REPO_GUESS=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -z "$REPO_GUESS" ] && [ -n "$MB_GUESS" ]; then
      REPO_GUESS=$(cd "$MB_GUESS/.." 2>/dev/null && pwd) || REPO_GUESS=""
    fi
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
    PIPELINE_YAML="$PIPELINE_YAML" \
    python3 "$SCRIPT_DIR/mb_spec_validate_v2.py" >>"$VIOLATIONS_FILE"
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
