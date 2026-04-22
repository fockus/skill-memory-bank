#!/usr/bin/env bash
# mb-roadmap-sync.sh — regenerate roadmap.md autosync block from plans/*.md frontmatter.
#
# Usage: mb-roadmap-sync.sh [mb_path]
#
# Effects:
#   - Scan `.memory-bank/plans/*.md` (not plans/done/) for frontmatter
#   - Between `<!-- mb-roadmap-auto -->` and `<!-- /mb-roadmap-auto -->` fences,
#     emit these sections:
#       ## Now (in progress)            — status: in_progress
#       ## Next (strict order — depends) — status: queued AND parallel_safe: false
#       ## Parallel-safe (can run now)  — status: queued AND parallel_safe: true AND depends_on empty
#       ## Paused / Archived             — status: paused|cancelled
#       ## Linked Specs (active)        — distinct linked_specs entries from non-done plans
#   - Content OUTSIDE the fence is preserved byte-for-byte
#   - If fence is missing, inject it after the `# Roadmap` H1 line
#   - Idempotent
#
# NOTE: if roadmap.md has multiple `<!-- mb-roadmap-auto -->` fence pairs,
# only the FIRST is regenerated. This is by design — the file is intended to
# have one autosync block. Multi-fence usage is silently ignored (not an error).
#
# Warnings (emitted to stderr, do not fail the run):
#   - Plans without frontmatter are skipped with `[warn] skipping plan without frontmatter: <path>`
#   - Plans using block-style YAML lists (`depends_on:\n  - a`) warn:
#     `[warn] plan <path>: <key> uses block-style list; use flow-style [a, b]`
#
# Exit: 0 OK, 1 missing mb_path / missing roadmap / plans dir, 2 unexpected internal error.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MB_PATH=$(mb_resolve_path "${1:-}")
[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }

ROADMAP="$MB_PATH/roadmap.md"
PLANS_DIR="$MB_PATH/plans"

[ -f "$ROADMAP" ] || { echo "[error] roadmap.md not found: $ROADMAP" >&2; exit 1; }
[ -d "$PLANS_DIR" ] || { echo "[error] plans/ not found: $PLANS_DIR" >&2; exit 1; }

# Delegate the heavy lifting to python3 — YAML-ish frontmatter + section composition.
python3 - "$MB_PATH" <<'PY'
import re
import sys
from pathlib import Path

mb = Path(sys.argv[1])
roadmap_path = mb / "roadmap.md"
plans_dir = mb / "plans"

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def parse_frontmatter(text: str) -> dict[str, str]:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        out[k.strip()] = v.strip()
    return out


def parse_list(raw: str) -> list[str]:
    """Parse a YAML flow-style list like `[a, b, c]` or `[]`. Returns [] on failure."""
    raw = raw.strip()
    if not (raw.startswith("[") and raw.endswith("]")):
        return []
    inner = raw[1:-1].strip()
    if not inner:
        return []
    return [item.strip().strip('"\'') for item in inner.split(",") if item.strip()]


def plan_title(path: Path, text: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            t = line[2:].strip()
            # Strip `Type:` prefix if any
            t = re.sub(r"^[A-Za-zА-Яа-я][\w\s/-]*:[\s　]*", "", t)
            return t or path.name
    return path.name


BLOCK_LIST_RE = re.compile(
    r"^(depends_on|linked_specs):\s*$\n(\s+-\s+)",
    re.MULTILINE,
)


def detect_block_style_keys(text: str) -> list[str]:
    """Return frontmatter keys that use block-style YAML lists."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return []
    raw = m.group(1)
    return [match.group(1) for match in BLOCK_LIST_RE.finditer(raw + "\n")]


# Collect plans (not plans/done/)
plans: list[dict[str, object]] = []
for path in sorted(plans_dir.glob("*.md")):
    if path.parent.name == "done":
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        continue
    fm = parse_frontmatter(text)
    if not fm:
        print(f"[warn] skipping plan without frontmatter: {path}", file=sys.stderr)
        continue
    for key in detect_block_style_keys(text):
        print(
            f"[warn] plan {path}: {key} uses block-style list; use flow-style [a, b]",
            file=sys.stderr,
        )
    plans.append(
        {
            "path": path,
            "rel": f"plans/{path.name}",
            "status": fm.get("status", "").strip(),
            "depends_on": parse_list(fm.get("depends_on", "[]")),
            "parallel_safe": fm.get("parallel_safe", "false").strip().lower() == "true",
            "linked_specs": parse_list(fm.get("linked_specs", "[]")),
            "topic": fm.get("topic", path.stem).strip(),
            "sprint": fm.get("sprint", "").strip(),
            "phase_of": fm.get("phase_of", "").strip(),
            "title": plan_title(path, text),
        }
    )


def fmt_plan_line(p: dict[str, object], prefix: str = "- ") -> str:
    return f"{prefix}[{p['topic']}]({p['rel']}) — {p['title']}"


now_plans = [p for p in plans if p["status"] == "in_progress"]
queued = [p for p in plans if p["status"] == "queued"]
next_plans = [p for p in queued if not p["parallel_safe"]]
parallel_plans = [p for p in queued if p["parallel_safe"] and not p["depends_on"]]
paused_plans = [p for p in plans if p["status"] in ("paused", "cancelled")]

linked_specs_set: list[str] = []
seen: set[str] = set()
for p in plans:
    if p["status"] in ("cancelled",):
        continue
    for spec in p["linked_specs"]:  # type: ignore[union-attr]
        if spec not in seen:
            seen.add(spec)
            linked_specs_set.append(spec)


def render_section(title: str, items: list[str]) -> str:
    if not items:
        return f"## {title}\n\n_None._\n"
    body = "\n".join(items)
    return f"## {title}\n\n{body}\n"


lines_now = [fmt_plan_line(p) for p in now_plans]
lines_next = [fmt_plan_line(p) for p in next_plans]
lines_parallel = [fmt_plan_line(p) for p in parallel_plans]
lines_paused = [fmt_plan_line(p) for p in paused_plans]
lines_specs = [f"- {s}" for s in linked_specs_set]

auto_body = "\n".join(
    [
        render_section("Now (in progress)", lines_now),
        render_section("Next (strict order — depends)", lines_next),
        render_section("Parallel-safe (can run now)", lines_parallel),
        render_section("Paused / Archived", lines_paused),
        render_section("Linked Specs (active)", lines_specs),
    ]
)

roadmap_text = roadmap_path.read_text(encoding="utf-8")

fence_open = "<!-- mb-roadmap-auto -->"
fence_close = "<!-- /mb-roadmap-auto -->"

block = f"{fence_open}\n{auto_body}{fence_close}\n"

if fence_open in roadmap_text and fence_close in roadmap_text:
    pattern = re.compile(
        re.escape(fence_open) + r".*?" + re.escape(fence_close) + r"\n?",
        re.DOTALL,
    )
    new_text = pattern.sub(block, roadmap_text, count=1)
else:
    # Inject after first `# Roadmap` H1 (or append at end if absent)
    h1 = re.search(r"^# Roadmap.*?$", roadmap_text, re.MULTILINE)
    if h1:
        insertion_point = h1.end()
        # Skip blank lines immediately after the H1
        m = re.match(r"\n+", roadmap_text[insertion_point:])
        if m:
            insertion_point += m.end()
        new_text = (
            roadmap_text[:insertion_point]
            + block
            + "\n"
            + roadmap_text[insertion_point:]
        )
    else:
        new_text = roadmap_text.rstrip() + "\n\n" + block

if new_text != roadmap_text:
    roadmap_path.write_text(new_text, encoding="utf-8")

print(f"[roadmap-sync] plans={len(plans)} now={len(now_plans)} next={len(next_plans)} parallel={len(parallel_plans)} paused={len(paused_plans)} specs={len(linked_specs_set)}")
PY
