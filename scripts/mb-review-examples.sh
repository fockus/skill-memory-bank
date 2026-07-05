#!/usr/bin/env bash
# mb-review-examples.sh — layered rubric-examples loader for the reviewer-2.0
# orchestrator (scripts/mb-review.sh:render_examples_section). Design:
# .memory-bank/specs/reviewer-2.0/design.md §4 "Few-shot examples — format
# and resolution", REQ-101.
#
# Layered resolver, precedence (highest wins on `example_id` collision):
#   1. .memory-bank/rubric-examples/<stack>.md   <- project override (per stack)
#   2. .memory-bank/rubric-examples/common.md    <- project override (cross-stack)
#   3. references/rubric-examples/<stack>.md      <- skill baseline (per stack)
#   4. references/rubric-examples/common.md       <- skill baseline (cross-stack)
#
# `<stack>` resolves from `.memory-bank/rules-profile.json:stack` unless
# --stack is given explicitly (absent profile -> common only, fail-safe).
#
# File format: markdown, `---`-delimited blocks: YAML front-matter
# (example_id/stack/category/severity) then `### Bad` + `### Expected
# verdict fragment` (only these inject -- `### Good` is read but excluded).
# category in logic|code_rules|security|scalability|tests; severity in
# blocker|major|minor. Fenced code (```) is tracked so `---`/`###` inside a
# fence is snippet text; malformed/duplicate/unclosed blocks warn on
# stderr, never crash.
#
# Security: `--stack` is allowlisted (fullmatch `[A-Za-z0-9_-]+`) before path
# interpolation, and every candidate's REAL path (symlinks resolved) must
# stay inside its declared root -- an escape is skipped, never opened.
#
# Usage:
#   mb-review-examples.sh render [--mb <path>] [--stack <s>] [--max <n>]
#                                 [--rotation hash_run_id|none] [--run-id <r>]
#   mb-review-examples.sh --help
#
# `render` always prints the full "## Calibration examples ..." section to
# stdout and exits 0, even with zero resolved files (empty body, no error).
#
# Selection (design.md §4): at most --max examples (default 8), covering
# >=1 per category then filling by stack-specificity (over `common`).
# --rotation hash_run_id (default) orders by sha256(run_id:example_id);
# --rotation none orders by example_id.
#
# Testability: MB_REVIEW_EXAMPLES_BUNDLED_DIR overrides the "skill
# baseline" directory (same pattern as MB_CAPS_FIXTURE in mb-agent-caps.sh).
#
# Exit codes:
#   0  success (render always exits 0)
#   2  usage / validation error (unknown flag, missing value, bad --rotation)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

BUNDLED_DIR_DEFAULT="$SCRIPT_DIR/../references/rubric-examples"

usage() {
  echo "Usage: mb-review-examples.sh render [--mb <path>] [--stack <s>] [--max <n>] [--rotation hash_run_id|none] [--run-id <r>]" >&2
  echo "       mb-review-examples.sh --help" >&2
}

# Guards against the bash "shift count out of range" crash when a
# value-taking flag is the LAST arg with no following value (see
# scripts/mb-review-cache.sh for the same pattern).
require_value() {
  local subcmd="$1"
  shift
  [ "$#" -ge 2 ] || { echo "[review-examples] $subcmd: $1 requires a value" >&2; usage; exit 2; }
}

cmd_render() {
  local mb_arg="" stack="" max="8" rotation="hash_run_id" run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) require_value render "$@"; mb_arg="$2"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      --stack) require_value render "$@"; stack="$2"; shift 2 ;;
      --stack=*) stack="${1#--stack=}"; shift ;;
      --max) require_value render "$@"; max="$2"; shift 2 ;;
      --max=*) max="${1#--max=}"; shift ;;
      --rotation) require_value render "$@"; rotation="$2"; shift 2 ;;
      --rotation=*) rotation="${1#--rotation=}"; shift ;;
      --run-id) require_value render "$@"; run_id="$2"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      *) echo "[review-examples] render: unknown arg '$1'" >&2; usage; exit 2 ;;
    esac
  done

  [[ "$max" =~ ^[1-9][0-9]*$ ]] || { echo "[review-examples] render: --max must be a positive integer" >&2; exit 2; }
  case "$rotation" in
    hash_run_id|none) ;;
    *) echo "[review-examples] render: --rotation must be hash_run_id or none" >&2; exit 2 ;;
  esac

  local bank bundled_dir project_dir
  bank=$(mb_resolve_path "$mb_arg")
  bundled_dir="${MB_REVIEW_EXAMPLES_BUNDLED_DIR:-$BUNDLED_DIR_DEFAULT}"
  project_dir="$bank/rubric-examples"

  BANK="$bank" \
  STACK_OVERRIDE="$stack" \
  BUNDLED_DIR="$bundled_dir" \
  PROJECT_DIR="$project_dir" \
  MAX_COUNT="$max" \
  ROTATION="$rotation" \
  RUN_ID="$run_id" \
  python3 - <<'PY'
import hashlib
import json
import os
import re
import sys

STACK_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def sanitize_stack(stack: str) -> str:
    # Allowlist before path interpolation ({dir}/{stack}.md) -- rejects
    # traversal chars (/, .) so --stack can never escape the rubric roots.
    if not stack:
        return ""
    if STACK_RE.fullmatch(stack):
        return stack
    sys.stderr.write(
        f"[review-examples] invalid --stack value '{stack}' (must match ^[A-Za-z0-9_-]+$), degrading to common-only\n"
    )
    return ""


def resolve_stack() -> str:
    override = os.environ.get("STACK_OVERRIDE", "")
    if override:
        return sanitize_stack(override)
    profile_path = os.path.join(os.environ["BANK"], "rules-profile.json")
    try:
        with open(profile_path, encoding="utf-8") as fh:
            data = json.load(fh)
        stack = data.get("stack", "")
        return sanitize_stack(stack if isinstance(stack, str) else "")
    except Exception:
        return ""


VALID_CATEGORIES = {"logic", "code_rules", "security", "scalability", "tests"}
VALID_SEVERITIES = {"blocker", "major", "minor"}


def parse_frontmatter(lines):
    fm = {}
    for line in lines:
        if not line.strip() or ":" not in line:
            continue
        key, _, value = line.partition(":")
        fm[key.strip()] = value.strip().strip('"').strip("'")
    return fm


def parse_sections(path, lines):
    # Extracts "### <Heading>" sections, ignoring "###"-looking lines inside
    # an open ``` fence. A duplicate heading warns (first occurrence wins).
    sections = {}
    header = None
    content = []
    in_fence = False

    def flush():
        nonlocal header, content
        if header is not None:
            if header in sections:
                sys.stderr.write(
                    f"[review-examples] {path}: duplicate '### {header}' section in one block, ignoring the later one\n"
                )
            else:
                sections[header] = "\n".join(content).strip("\n")
        header = None
        content = []

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            content.append(line)
            continue
        if not in_fence:
            m = re.match(r"^###\s+(.*)$", line)
            if m:
                flush()
                header = m.group(1).strip()
                continue
        content.append(line)
    flush()
    return sections


def parse_file(path):
    # Yields valid example dicts from one file. State machine: SEEK -(---)->
    # FRONTMATTER -(---)-> BODY -(---)-> SEEK; a bare "---" inside an open
    # ``` fence is snippet text, not a delimiter. Malformed blocks are
    # skipped with a stderr warning -- never a crash; see module docstring.
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except Exception:
        return

    state = 0  # 0=SEEK 1=FRONTMATTER 2=BODY
    fm_lines = []
    body_lines = []
    in_fence = False
    current_id = ""
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            if state == 1:
                fm_lines.append(raw_line)
            elif state == 2:
                body_lines.append(raw_line)
            continue
        if stripped == "---" and not in_fence:
            if state == 0:
                state = 1
                fm_lines = []
                current_id = ""
            elif state == 1:
                state = 2
                body_lines = []
                current_id = parse_frontmatter(fm_lines).get("example_id", "")
            else:
                fm = parse_frontmatter(fm_lines)
                sections = parse_sections(path, body_lines)
                block = validate_block(path, fm, sections)
                if block is not None:
                    yield block
                state = 0
                in_fence = False
                current_id = ""
            continue
        if state == 1:
            fm_lines.append(raw_line)
        elif state == 2:
            body_lines.append(raw_line)

    if state != 0:
        if not current_id and state == 1:
            current_id = parse_frontmatter(fm_lines).get("example_id", "")
        sys.stderr.write(
            f"[review-examples] {path}: unclosed block at EOF (last example_id seen: '{current_id or 'unknown'}'), skipped\n"
        )


def validate_block(path, fm, sections):
    example_id = fm.get("example_id", "")
    stack = fm.get("stack", "")
    category = fm.get("category", "")
    severity = fm.get("severity", "")

    if not example_id or not stack or not category or not severity:
        sys.stderr.write(f"[review-examples] {path}: block missing required front-matter key, skipped\n")
        return None
    if category not in VALID_CATEGORIES:
        sys.stderr.write(f"[review-examples] {path}: {example_id} has invalid category '{category}', skipped\n")
        return None
    if severity not in VALID_SEVERITIES:
        sys.stderr.write(f"[review-examples] {path}: {example_id} has invalid severity '{severity}', skipped\n")
        return None

    bad = sections.get("Bad", "").strip()
    verdict = sections.get("Expected verdict fragment", "").strip()
    if not bad or not verdict:
        sys.stderr.write(f"[review-examples] {path}: {example_id} missing Bad/verdict section, skipped\n")
        return None

    return {
        "example_id": example_id,
        "stack": stack,
        "category": category,
        "severity": severity,
        "bad": bad,
        "verdict": verdict,
    }


def is_contained(path, root):
    # A candidate (incl. a symlink target) must resolve inside its declared
    # root -- blocks disclosure of arbitrary files via a planted symlink.
    try:
        real_path = os.path.realpath(path)
        real_root = os.path.realpath(root)
        return os.path.commonpath([real_path, real_root]) == real_root
    except ValueError:
        return False


def build_pool(bundled_dir, project_dir, stack):
    # Load order = precedence LOW -> HIGH so a later file overwrites an
    # earlier one on example_id collision (highest precedence wins).
    candidates = [(os.path.join(bundled_dir, "common.md"), bundled_dir)]
    if stack:
        candidates.append((os.path.join(bundled_dir, f"{stack}.md"), bundled_dir))
    candidates.append((os.path.join(project_dir, "common.md"), project_dir))
    if stack:
        candidates.append((os.path.join(project_dir, f"{stack}.md"), project_dir))

    pool = {}
    for path, root in candidates:
        if not os.path.isfile(path):
            continue
        if not is_contained(path, root):
            sys.stderr.write(f"[review-examples] {path}: escapes rubric root {root}, skipped\n")
            continue
        for block in parse_file(path):
            pool[block["example_id"]] = block
    return pool


def select_examples(pool, stack, max_count, rotation, run_id):
    if not pool:
        return []

    def specificity(block):
        return 0 if stack and block["stack"] == stack else 1

    if rotation == "none":
        def order_key(block):
            return (specificity(block), block["example_id"])
    else:
        def hkey(block):
            digest = hashlib.sha256(f"{run_id}:{block['example_id']}".encode("utf-8")).hexdigest()
            return digest

        def order_key(block):
            return (specificity(block), hkey(block))

    selected = []
    selected_ids = set()

    categories = sorted({b["category"] for b in pool.values()})
    for category in categories:
        if len(selected) >= max_count:
            break
        candidates = [b for b in pool.values() if b["category"] == category and b["example_id"] not in selected_ids]
        if not candidates:
            continue
        pick = min(candidates, key=order_key)
        selected.append(pick)
        selected_ids.add(pick["example_id"])

    if len(selected) < max_count:
        remaining = [b for b in pool.values() if b["example_id"] not in selected_ids]
        for block in sorted(remaining, key=order_key):
            if len(selected) >= max_count:
                break
            selected.append(block)
            selected_ids.add(block["example_id"])

    return sorted(selected, key=lambda b: b["example_id"])


def render(selected):
    print("## Calibration examples (reference patterns — not part of current diff)")
    print()
    if not selected:
        print("(no calibration examples available)")
        return
    for i, block in enumerate(selected):
        if i > 0:
            print()
            print("---")
            print()
        print(f"### {block['example_id']} ({block['stack']} / {block['category']} / {block['severity']})")
        print()
        print("**Bad:**")
        print()
        print(block["bad"])
        print()
        print("**Expected verdict fragment:**")
        print()
        print(block["verdict"])


stack = resolve_stack()
pool = build_pool(os.environ["BUNDLED_DIR"], os.environ["PROJECT_DIR"], stack)
selected = select_examples(pool, stack, int(os.environ["MAX_COUNT"]), os.environ["ROTATION"], os.environ.get("RUN_ID", ""))
render(selected)
PY
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
    exit 2
  fi
  case "$1" in
    -h|--help) sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    render) shift; cmd_render "$@" ;;
    *) echo "[review-examples] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
