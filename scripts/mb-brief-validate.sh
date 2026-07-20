#!/usr/bin/env bash
# mb-brief-validate.sh — structural validator for a brief one-pager (svp-brief C1).
#
# Usage:  mb-brief-validate.sh <brief.md>
#
# Checks, in this order:
#   * frontmatter — a CLOSED key set: required `topic` (non-empty scalar),
#     `created` (calendar-real ISO YYYY-MM-DD), `status` (ready|draft), `inputs`
#     (list of relative `inputs/...` paths, `[]` allowed); optional
#     `assumptions_note` (non-empty scalar when present). Missing, mistyped,
#     duplicated or unknown keys all collapse into ONE aggregate line.
#   * exactly one `## ` heading per required section, exact spelling, case
#     sensitive, no aliases and no duplicates.
#   * `Essence` and `Goal & Impact` each carry at least one non-blank,
#     non-comment line.
#   * file size (NFR-001): >120 lines warns without changing the exit code.
#
# stdout: exactly one line — `brief=ok` | `brief=invalid` (nothing on exit 2).
# stderr: deterministic — the single frontmatter aggregate, then section
#         diagnostics in the canonical nine-section order (within a section
#         missing/duplicate before empty_*), then `warning=oversize` LAST.
#         Two correct implementations must produce a byte-identical stream.
# exit:   0 valid (a warning does not change this) · 1 content violation ·
#         2 usage / unreadable input.

set -euo pipefail

usage_error() { printf 'error=usage\n' >&2; exit 2; }

TARGET=""
have_target=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --) usage_error ;;
    -*) usage_error ;;
    *) [ "$have_target" -eq 0 ] || usage_error; TARGET="$1"; have_target=1 ;;
  esac
  shift
done
[ "$have_target" -eq 1 ] || usage_error

# A directory or a missing path is a usage error; an existing regular file that
# cannot be read is an I/O error and must be distinguishable from it, otherwise
# a permission problem reads as "you called me wrong" (SVP-BRIEF-004).
[ -f "$TARGET" ] || usage_error
if [ ! -r "$TARGET" ]; then
  printf 'error=io path=%s\n' "$TARGET" >&2
  exit 2
fi

python3 - "$TARGET" <<'PY'
import re
import sys

path = sys.argv[1]

try:
    with open(path, "rb") as fh:
        raw = fh.read()
except OSError:
    sys.stderr.write("error=io path=%s\n" % path)
    sys.exit(2)

try:
    text = raw.decode("utf-8")
except UnicodeDecodeError:
    sys.stderr.write("error=io path=%s\n" % path)
    sys.exit(2)

# ── size ────────────────────────────────────────────────────────────────────
# `wc -l` semantics, plus an unterminated final line still counts as a line.
LINE_LIMIT = 120
line_count = text.count("\n")
if text and not text.endswith("\n"):
    line_count += 1

lines = text.split("\n")
if lines and lines[-1] == "":
    lines.pop()

# ── frontmatter ─────────────────────────────────────────────────────────────
KNOWN = ["topic", "created", "status", "inputs", "assumptions_note"]
REQUIRED = ["topic", "created", "status", "inputs"]

KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(.*)$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

bad_fields = []          # violated known keys
unknown_fields = []      # unknown keys, in order of appearance


def flag(name):
    if name not in bad_fields:
        bad_fields.append(name)


def parse_frontmatter(src):
    """Return (values, order) or None when there is no delimited frontmatter.

    `values[key]` is (scalar-or-None, [list-items] or None, seen-count).
    """
    if not src or src[0] != "---":
        return None
    end = None
    for i in range(1, len(src)):
        if src[i] == "---":
            end = i
            break
    if end is None:
        return None

    values, order = {}, []
    key = None
    for line in src[1:end]:
        if not line.strip():
            continue
        if line[:1] in (" ", "\t"):
            if key is not None and values[key][1] is not None:
                item = line.strip()
                if item.startswith("- "):
                    values[key][1].append(item[2:].strip())
                elif item == "-":
                    values[key][1].append("")
                else:
                    flag_key(key)
            continue
        mo = KEY_RE.match(line)
        if not mo:
            continue
        key = mo.group(1)
        scalar = mo.group(2).strip()
        if key in values:
            values[key][2] += 1
            continue
        order.append(key)
        if scalar.startswith("[") and scalar.endswith("]"):
            inner = scalar[1:-1].strip()
            items = [p.strip() for p in inner.split(",")] if inner else []
            values[key] = [None, items, 1]
        elif scalar == "":
            # Either an empty scalar or the head of a block list; the indented
            # branch above fills the list in.
            values[key] = ["", [], 1]
        else:
            values[key] = [scalar, None, 1]
    return values, order


def flag_key(key):
    if key in KNOWN:
        flag(key)
    elif key not in unknown_fields:
        unknown_fields.append(key)


def real_date(value):
    year, month, day = (int(p) for p in value.split("-"))
    if not 1 <= month <= 12:
        return False
    span = [31, 29 if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0 else 28,
            31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return 1 <= day <= span[month - 1]


def check_input_path(value):
    if not value:
        return False
    # The `inputs/` prefix is what rejects an absolute path; a backslash is
    # rejected separately because it survives the prefix (`inputs/a\..\b`) and
    # C6 copies from this list.
    if "\\" in value:
        return False
    if not value.startswith("inputs/"):
        return False
    rest = value[len("inputs/"):]
    if not rest or rest.endswith("/"):
        return False
    return ".." not in rest.split("/")


parsed = parse_frontmatter(lines)
if parsed is None:
    for name in REQUIRED:
        flag(name)
else:
    values, order = parsed
    for key in order:
        if key not in KNOWN:
            if key not in unknown_fields:
                unknown_fields.append(key)
            continue
        if values[key][2] > 1:
            flag(key)

    for name in REQUIRED:
        if name not in values:
            flag(name)

    if "topic" in values:
        scalar, items, _ = values["topic"]
        if items is not None or not scalar:
            flag("topic")

    if "created" in values:
        scalar, items, _ = values["created"]
        if items is not None or not scalar or not DATE_RE.match(scalar) \
                or not real_date(scalar):
            flag("created")

    if "status" in values:
        scalar, items, _ = values["status"]
        if items is not None or scalar not in ("ready", "draft"):
            flag("status")

    if "inputs" in values:
        scalar, items, _ = values["inputs"]
        if items is None:
            flag("inputs")
        else:
            for item in items:
                if not check_input_path(item):
                    flag("inputs")
                    break

    if "assumptions_note" in values:
        scalar, items, _ = values["assumptions_note"]
        if items is not None or not scalar:
            flag("assumptions_note")

fm_fields = [name for name in KNOWN if name in bad_fields] + unknown_fields

# ── sections ────────────────────────────────────────────────────────────────
SECTIONS = ["Essence", "Goal & Impact", "References", "Solution (JTBD)",
            "Scenarios", "Constraints", "UX", "Done Criteria", "Attachments"]
NON_EMPTY = {"Essence": "empty_essence", "Goal & Impact": "empty_goal"}

# Fence-aware, exactly like the prompt-contract harness reads headings: a `## `
# line inside a ``` fence is example content, not a heading, so a brief that
# quotes markdown cannot be failed for a heading it never declared.
headings = []   # (index, heading-text)
in_fence = False
for i, line in enumerate(lines):
    if line.lstrip().startswith("```"):
        in_fence = not in_fence
        continue
    if in_fence:
        continue
    if line.startswith("## "):
        headings.append((i, line[3:].rstrip()))

occurrences = {}
for i, title in headings:
    occurrences.setdefault(title, []).append(i)


def body_of(start):
    """Lines under the heading at `start`, up to the next heading of any level."""
    out = []
    fence = False
    for line in lines[start + 1:]:
        if line.lstrip().startswith("```"):
            fence = not fence
            out.append(line)
            continue
        if not fence and line.startswith("#"):
            break
        out.append(line)
    return out


def has_content(block):
    for line in block:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("<!--") or stripped == "-->":
            continue
        return True
    return False


section_errors = []
for name in SECTIONS:
    hits = occurrences.get(name, [])
    if not hits:
        section_errors.append("error=missing_section section=%s" % name)
        continue
    if len(hits) > 1:
        section_errors.append("error=duplicate_section section=%s" % name)
    if name in NON_EMPTY and not has_content(body_of(hits[0])):
        section_errors.append("error=%s section=%s" % (NON_EMPTY[name], name))

# ── report ──────────────────────────────────────────────────────────────────
diagnostics = []
if fm_fields:
    diagnostics.append(
        "error=frontmatter_invalid section=frontmatter fields=%s" % ",".join(fm_fields)
    )
diagnostics.extend(section_errors)

sys.stdout.write("brief=invalid\n" if diagnostics else "brief=ok\n")
for line in diagnostics:
    sys.stderr.write(line + "\n")
if line_count > LINE_LIMIT:
    sys.stderr.write("warning=oversize lines=%d limit=%d\n" % (line_count, LINE_LIMIT))

sys.exit(1 if diagnostics else 0)
PY
