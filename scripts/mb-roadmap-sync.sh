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
#       ## Linked Specs (active)        — distinct linked_specs / linked_spec entries from non-done plans
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

MODE="write"
MB_ARG=""
for arg in "$@"; do
	case "$arg" in
		--check) MODE="check" ;;
		*) MB_ARG="$arg" ;;
	esac
done

MB_PATH=$(mb_resolve_path "$MB_ARG")
[ -d "$MB_PATH" ] || {
	echo "[error] .memory-bank not found at: $MB_PATH" >&2
	exit 1
}

ROADMAP="$MB_PATH/roadmap.md"
PLANS_DIR="$MB_PATH/plans"

[ -f "$ROADMAP" ] || {
	echo "[error] roadmap.md not found: $ROADMAP" >&2
	exit 1
}
[ -d "$PLANS_DIR" ] || {
	echo "[error] plans/ not found: $PLANS_DIR" >&2
	exit 1
}

# Delegate the heavy lifting to python3 — YAML-ish frontmatter + section composition.
# --check computes the expected block in memory and exits 1 when stale (no write).
python3 - "$MB_PATH" "$(cd "$(dirname "$0")" && pwd)" "$MODE" <<'PY'
import re
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[2])
from mb_roadmap_group import (  # noqa: E402
    GroupOrderingError,
    compute_progress,
    fence_group_slugs,
    render_groups,
)
from mb_roadmap_order import (  # noqa: E402
    has_priority,
    ice_is_block_style,
    parse_ice_score,
    parse_pin,
    priority_order,
)

mb = Path(sys.argv[1])
mode = sys.argv[3] if len(sys.argv) > 3 else "write"
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


_TRUE_TOKENS = {"true", "yes", "on", "1"}
_FALSE_TOKENS = {"false", "no", "off", "0", ""}


def parse_bool(raw: str, key: str, plan_rel: str) -> bool:
    v = raw.strip().lower()
    if v in _TRUE_TOKENS:
        return True
    if v in _FALSE_TOKENS:
        return False
    print(
        f"[warn] plan {plan_rel}: {key}='{raw}' is not a recognized boolean; treating as false",
        file=sys.stderr,
    )
    return False


def detect_block_style_keys(text: str) -> list[str]:
    """Return frontmatter keys that use block-style YAML lists."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return []
    raw = m.group(1)
    return [match.group(1) for match in BLOCK_LIST_RE.finditer(raw + "\n")]


# ICE-component parsing + priority ordering live in the pure, unit-tested
# module scripts/mb_roadmap_order.py (design.md C1/C2) — imported above.
_DATE_PREFIX_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})_")


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
    rel = f"plans/{path.name}"
    ice_present = "ice" in fm
    ice_score = parse_ice_score(fm.get("ice", "")) if ice_present else None
    if ice_present and ice_score is None:
        if ice_is_block_style(text):
            print(
                f"[warn] plan {rel}: ice uses block-style mapping; "
                "use flow-style {impact: N, confidence: N, ease: N}",
                file=sys.stderr,
            )
        else:
            print(
                f"[warn] plan {rel}: ice is not a valid flow-mapping "
                "{impact: N, confidence: N, ease: N} with integer components "
                "1..10; ignoring",
                file=sys.stderr,
            )
    dm = _DATE_PREFIX_RE.match(path.name)
    plans.append(
        {
            "path": path,
            "rel": rel,
            "status": fm.get("status", "").strip(),
            "depends_on": parse_list(fm.get("depends_on", "[]")),
            "parallel_safe": parse_bool(fm.get("parallel_safe", "false"), "parallel_safe", rel),
            "linked_specs": parse_list(fm.get("linked_specs", "[]"))
            + ([fm["linked_spec"].strip()] if fm.get("linked_spec", "").strip() else []),
            "topic": fm.get("topic", path.stem).strip(),
            "sprint": fm.get("sprint", "").strip(),
            "phase_of": fm.get("phase_of", "").strip(),
            "title": plan_title(path, text),
            "ice_score": ice_score,
            "pin": parse_pin(fm.get("pin", "")) if "pin" in fm else None,
            "ice_confirmed": fm.get("ice_confirmed", "").strip().lower() == "true",
            "created": dm.group(1) if dm else None,
        }
    )


def _progress_counters(path, kind: str) -> str:
    """REQ-002/Task 6: `progress=<N>% stages(...)`/`tasks(...)` for a plan/spec.

    Per-item counters via scripts/mb_work_items.py (reused through
    mb_roadmap_group.compute_progress); recomputed every render, never parsed
    back from roadmap.md. total_dod==0 renders 0%.
    """
    pct, done, in_prog, planned, total = compute_progress(path)
    return (
        f"progress={pct}% {kind}(done={done},in_progress={in_prog},"
        f"planned={planned},total={total})"
    )


def fmt_plan_line(p: dict[str, object], prefix: str = "- ") -> str:
    prog = _progress_counters(p["path"], "stages")
    return f"{prefix}[{p['topic']}]({p['rel']}) — {p['title']} — {prog}"


now_plans = [p for p in plans if p["status"] == "in_progress"]
queued = [p for p in plans if p["status"] == "queued"]


def dependency_order(items: list[dict[str, object]]) -> list[dict[str, object]]:
    """Return queued plans with internal dependencies before dependents."""
    by_key: dict[str, dict[str, object]] = {}
    for item in items:
        path = item["path"]  # type: ignore[assignment]
        rel = str(item["rel"])
        name = path.name  # type: ignore[union-attr]
        by_key[name] = item
        by_key[rel] = item
        by_key[f"plans/{name}"] = item

    visiting: set[str] = set()
    visited: set[str] = set()
    out: list[dict[str, object]] = []

    def visit(item: dict[str, object]) -> None:
        name = item["path"].name  # type: ignore[union-attr]
        if name in visited:
            return
        if name in visiting:
            print(
                f"[warn] dependency cycle while sorting roadmap near {name}; keeping stable order",
                file=sys.stderr,
            )
            return
        visiting.add(name)
        for dep in item.get("depends_on", []):
            dep_name = str(dep).strip().strip('"\'')
            dep_item = by_key.get(dep_name) or by_key.get(dep_name.removeprefix("plans/"))
            if dep_item is not None:
                visit(dep_item)
        visiting.remove(name)
        visited.add(name)
        out.append(item)

    for item in items:
        visit(item)
    return out


# ── Per-section mode choice (S4 Task 1, design.md C2) ───────────────────────
# A section where NO element carries a valid ice OR a pin renders through the
# unmodified dependency_order() above (legacy mode, byte-identical). As soon as
# one element has a valid ice/pin the whole section goes through the round-based
# Kahn priority comparator (pure module scripts/mb_roadmap_order.py). The mode
# predicate is the SAME `has_priority` the comparator + its unit tests use — no
# second copy of the priority predicate (would drift out of test coverage).
def order_section(items: list[dict[str, object]]) -> list[dict[str, object]]:
    if any(has_priority(it) for it in items):
        return priority_order(items)
    return dependency_order(items)


next_plans = order_section([p for p in queued if (not p["parallel_safe"]) or p["depends_on"]])
parallel_plans = order_section([p for p in queued if p["parallel_safe"] and not p["depends_on"]])
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


def fmt_spec_line(slug: str) -> str:
    # REQ-002: ungrouped linked specs also carry progress (tasks counters). The
    # source is the spec's tasks.md; a referenced slug with no spec dir renders
    # progress=0% tasks(...,total=0).
    prog = _progress_counters(mb / "specs" / slug / "tasks.md", "tasks")
    return f"- {slug} — {prog}"


lines_now = [fmt_plan_line(p) for p in now_plans]
lines_next = [fmt_plan_line(p) for p in next_plans]
lines_parallel = [fmt_plan_line(p) for p in parallel_plans]
lines_paused = [fmt_plan_line(p) for p in paused_plans]
lines_specs = [fmt_spec_line(s) for s in linked_specs_set]

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

# Existing autoblock (used only for orphan_group detection — S4-A-02: manual
# `## Group:` headers OUTSIDE the fence are never treated as registry data).
old_m = re.search(re.escape(fence_open) + r"(.*?)" + re.escape(fence_close), roadmap_text, re.DOTALL)
old_autoblock = old_m.group(1) if old_m else ""

# Group sections (design.md C2, REQ-002/003/012): rendered after Linked Specs.
# Malformed member ordering fields (pin/created/blocked_by) are a HARD error
# (exit 3, shared S3/S4 ordering contract); invalid ICE only warns (inside).
try:
    group_info = render_groups(mb)
except GroupOrderingError as exc:
    print(str(exc), file=sys.stderr)
    sys.exit(3)
group_region = group_info["block"]
discovered = set(group_info["slugs"])

# orphan_group (R2-006): a `## Group:` slug present in the OLD fence but not
# among the discovered specs is stale — warn and drop it (regeneration already
# omits it since only discovered groups are rendered).
for slug in fence_group_slugs(old_autoblock):
    if slug not in discovered:
        print(f"[warn] orphan_group={slug}", file=sys.stderr)

# unconfirmed_ice escalation signal (REQ-013, AGR-021): a valid-but-unconfirmed
# ICE that is ACTUALLY USED to order a rendered section. Design C2 scopes the
# trigger to the ICE-ordered sections (Next, Parallel-safe) and Group members —
# NOT to plans excluded from ordering (in_progress→Now, paused/cancelled). The
# order is NEVER changed by confirmation state — pure escalation for the lead.
ordered_plans = next_plans + parallel_plans
plan_unconfirmed = [
    str(p["topic"])
    for p in ordered_plans
    if p.get("ice_score") is not None and not p.get("ice_confirmed")
]
unconfirmed = sorted(set(plan_unconfirmed) | set(group_info["unconfirmed"]))
if unconfirmed:
    print("unconfirmed_ice=" + ",".join(unconfirmed), file=sys.stderr)

def strip_bootstrap_groups(text: str, discovered_slugs: set[str]) -> str:
    """Bootstrap transfer (Task 6): remove a manual `## Group: <slug>` block that
    sits OUTSIDE the fence when <slug> is now rendered INSIDE it, so the autosync
    fence is the single source of the group. Manual `## Group:` blocks for
    NON-discovered slugs are left untouched (S4-A-02). A block runs from its
    header to the next heading / fence marker / EOF.
    """
    if not discovered_slugs:
        return text
    fm = re.search(
        re.escape(fence_open) + r".*?" + re.escape(fence_close), text, re.DOTALL
    )
    if not fm:
        return text
    head, fenced, tail = text[: fm.start()], text[fm.start() : fm.end()], text[fm.end() :]

    def scrub(seg: str) -> str:
        for slug in discovered_slugs:
            pat = re.compile(
                r"(?m)^## Group: "
                + re.escape(slug)
                + r"[ \t]*\n"
                + r"(?:^(?!#)(?!<!-- /?mb-roadmap-auto -->).*\n?)*"
            )
            seg = pat.sub("", seg)
        return re.sub(r"\n{3,}", "\n\n", seg)

    return scrub(head) + fenced + scrub(tail)


block = f"{fence_open}\n{auto_body}{group_region}{fence_close}\n"

if fence_open in roadmap_text and fence_close in roadmap_text:
    pattern = re.compile(
        re.escape(fence_open) + r".*?" + re.escape(fence_close) + r"\n?",
        re.DOTALL,
    )
    new_text = pattern.sub(lambda _m: block, roadmap_text, count=1)
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

# Bootstrap transfer: drop any out-of-fence manual block for a discovered group.
new_text = strip_bootstrap_groups(new_text, discovered)

# --check (F-008): read-only staleness probe — never writes.
if mode == "check":
    sys.exit(0 if new_text == roadmap_text else 1)

if new_text != roadmap_text:
    roadmap_path.write_text(new_text, encoding="utf-8")

print(f"[roadmap-sync] plans={len(plans)} now={len(now_plans)} next={len(next_plans)} parallel={len(parallel_plans)} paused={len(paused_plans)} specs={len(linked_specs_set)}")
PY
