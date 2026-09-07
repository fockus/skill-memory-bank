"""Checklist v2 model — one block per plan, parsed from v1 / v2 / mixed markdown.

v1 (per-stage, written by pre-Sprint-1 ``mb-plan-sync.sh``)::

    <!-- mb-plan:FILE.md -->
    ## Stage 1: do a thing
    - ⬜ do a thing

v2 (one block per plan)::

    <!-- mb-plan:FILE.md -->
    ## Plan title — 1/3
    - ✅ Stage 1 — do a thing
    - ⬜ Stage 2 — do another

Mixed input is the normal transitional state: a plan may own v1 blocks and a v2
block at once. Parsing accepts both; rendering always emits v2. Nothing is ever
deleted here — the caller archives removed content to ``progress.md`` first.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

MARKER_RE = re.compile(r"^<!--\s*mb-plan:(.+?)\s*-->\s*$")
ANY_HEADING_RE = re.compile(r"^#{1,6}\s")
V1_HEAD_RE = re.compile(r"^##\s+(?:Stage|Task|Phase|Sprint)\s+(\d+):\s*(.*?)\s*$")
V2_HEAD_RE = re.compile(r"^##\s+(.*?)(?:\s+—\s+\d+/\d+)?\s*$")
V2_ITEM_RE = re.compile(r"^-\s+(✅|⬜)\s+Stage\s+(\d+)\s+—\s+(.*?)\s*$")
ITEM_RE = re.compile(r"^-\s+(✅|⬜)\s+(.*?)\s*$")
H3_RE = re.compile(r"^###\s+(.+?)\s*$")
PLAN_DONE_RE = re.compile(r"\(([^)]*plans/done/[^)]+\.md)\)")
OPEN_RE = re.compile(r"(⬜|\[ \])")
PROTECTED_RE = re.compile(r"^##\s+(⏳\s*In\s*flight|⏭\s*Next\s*planned)", re.IGNORECASE)
TITLE_PREFIX_RE = re.compile(r"^#\s+(?:[^:：]{1,40}[:：]\s*)?(.*?)\s*$")


@dataclass
class Stage:
    n: int
    done: bool
    name: str


@dataclass
class PlanBlock:
    """One `<!-- mb-plan:… -->` block: either a v1 stage section or a v2 plan block."""

    plan: str
    start: int
    end: int
    title: str | None = None
    stages: dict[int, Stage] = field(default_factory=dict)
    extra: list[str] = field(default_factory=list)


@dataclass
class LegacySection:
    """A `### ` section linking a `plans/done/…` plan with no open item left."""

    heading: str
    link: str
    start: int
    end: int


def _is_boundary(line: str) -> bool:
    return bool(MARKER_RE.match(line) or ANY_HEADING_RE.match(line))


def _protected(lines: list[str], idx: int) -> bool:
    for j in range(idx - 1, -1, -1):
        if lines[j].startswith("## "):
            return bool(PROTECTED_RE.match(lines[j]))
    return False


def _parse_plan_block(lines: list[str], i: int, plan: str) -> PlanBlock:
    j = i + 1
    while j < len(lines) and not lines[j].strip():
        j += 1
    if j >= len(lines) or not lines[j].startswith("## "):
        # Orphan marker (marker followed by another marker / EOF) — never useful.
        return PlanBlock(plan=plan, start=i, end=i + 1)
    heading, body_start = lines[j], j + 1
    end = body_start
    while end < len(lines) and not _is_boundary(lines[end]):
        end += 1
    body = lines[body_start:end]

    v1 = V1_HEAD_RE.match(heading)
    if v1:
        n, name = int(v1.group(1)), v1.group(2)
        items = [m for m in (ITEM_RE.match(ln) for ln in body) if m]
        # The first item line carries the stage text, often richer than the heading
        # (`- ✅ <heading text> — <closeout detail>`); keep it, never the shorter one.
        done = bool(items) and items[0].group(1) == "✅"
        if items and items[0].group(2):
            name = items[0].group(2)
        rest = [ln for ln in body[body.index(items[0].string) + 1:] if ln.strip()] if items else [
            ln for ln in body if ln.strip()
        ]
        return PlanBlock(plan, i, end, None, {n: Stage(n, done, name)}, rest)

    block = PlanBlock(plan, i, end, V2_HEAD_RE.match(heading).group(1))
    for ln in body:
        m = V2_ITEM_RE.match(ln)
        if m:
            block.stages[int(m.group(2))] = Stage(int(m.group(2)), m.group(1) == "✅", m.group(3))
        elif ln.strip():
            block.extra.append(ln)
    return block


def parse(lines: list[str]) -> tuple[list[PlanBlock], list[LegacySection]]:
    """Split a checklist into plan blocks and archivable legacy `### ` sections."""
    blocks: list[PlanBlock] = []
    legacy: list[LegacySection] = []
    i = 0
    while i < len(lines):
        marker = MARKER_RE.match(lines[i])
        if marker:
            block = _parse_plan_block(lines, i, marker.group(1))
            blocks.append(block)
            i = block.end
            continue
        h3 = H3_RE.match(lines[i])
        if h3 and not _protected(lines, i):
            end = i + 1
            while end < len(lines) and not _is_boundary(lines[end]):
                end += 1
            body = "\n".join(lines[i + 1:end])
            link = PLAN_DONE_RE.search(lines[i] + "\n" + body)
            if link and not OPEN_RE.search(body):
                legacy.append(LegacySection(h3.group(1), link.group(1), i, end))
            i = end
            continue
        i += 1
    return blocks, legacy


def merge(blocks: list[PlanBlock]) -> tuple[str | None, dict[int, Stage], list[str]]:
    """Fold every block of one plan into (title, stages, extra).

    A stage seen twice keeps the ✅ the checklist already recorded — the flip is
    the newer fact, and inventing a ⬜ over it would undo real work.
    """
    title: str | None = None
    stages: dict[int, Stage] = {}
    extra: list[str] = []
    for b in blocks:
        title = b.title or title
        extra.extend(x for x in b.extra if x not in extra)
        for n, st in b.stages.items():
            prev = stages.get(n)
            stages[n] = Stage(n, st.done or (prev.done if prev else False), st.name or (prev.name if prev else ""))
    return title, stages, extra


def render_block(plan: str, title: str, stages: dict[int, Stage], extra: list[str] | None = None) -> list[str]:
    """Render one v2 block: marker, `## <title> — k/n`, one line per stage."""
    ordered = [stages[n] for n in sorted(stages)]
    done = sum(1 for s in ordered if s.done)
    out = [f"<!-- mb-plan:{plan} -->", f"## {title} — {done}/{len(ordered)}"]
    out += [f"- {'✅' if s.done else '⬜'} Stage {s.n} — {s.name}" for s in ordered]
    out += list(extra or [])
    return out


def block_key(block: PlanBlock) -> str:
    return f"plan:{block.plan}"


def legacy_key(section: LegacySection) -> str:
    return f"legacy:{section.heading}"


def plan_title(plan_text: str, fallback: str) -> str:
    """First `# ` line of a plan file, minus a leading `Plan: <type> — ` style prefix."""
    for line in plan_text.splitlines():
        if line.startswith("# "):
            title = TITLE_PREFIX_RE.match(line).group(1)
            title = re.sub(r"^[a-zA-Z][\w-]*\s+—\s+", "", title)
            return title or fallback
    return fallback


def _squeeze_blanks(lines: list[str]) -> list[str]:
    out: list[str] = []
    streak = 0
    for ln in lines:
        if ln.strip():
            streak = 0
            out.append(ln)
            continue
        streak += 1
        if streak <= 1:
            out.append(ln)
    return out


def rewrite(
    lines: list[str],
    titles: dict[str, str] | None = None,
    drop: set[str] | None = None,
    add: dict[str, list[tuple[int, str]]] | None = None,
    flips: dict[str, set[int]] | None = None,
) -> list[str]:
    """Fold every plan into one v2 block in place.

    `titles` supplies a display title for a plan that has no v2 block yet (an
    existing v2 title always wins, so re-running never churns the file). `drop`
    removes whole blocks by key, `add` appends new ⬜ stages, `flips` marks
    stages ✅ — all three keyed by plan basename, applied to the merged block.
    """
    titles, drop, add, flips = titles or {}, drop or set(), add or {}, flips or {}
    blocks, legacy = parse(lines)
    by_plan: dict[str, list[PlanBlock]] = {}
    for b in blocks:
        by_plan.setdefault(b.plan, []).append(b)

    replace: dict[int, list[str] | None] = {}
    skip: set[int] = set()
    for plan, group in by_plan.items():
        title, stages, extra = merge(group)
        for n, name in add.get(plan, []):
            stages.setdefault(n, Stage(n, False, name))
        for n in flips.get(plan, set()):
            if n in stages:
                stages[n].done = True
        if not stages:
            # Nothing foldable: drop bare orphan markers, leave real content alone.
            for b in group:
                if b.end == b.start + 1 and not b.extra:
                    replace[b.start] = None
                    skip.add(b.start)
            continue
        rendered = None
        if f"plan:{plan}" not in drop:
            rendered = render_block(plan, title or titles.get(plan) or plan, stages, extra)
        replace[group[0].start] = rendered
        for b in group:
            skip.update(range(b.start, b.end))
    for sec in legacy:
        if f"legacy:{sec.heading}" in drop:
            replace[sec.start] = None
            skip.update(range(sec.start, sec.end))

    out: list[str] = []
    i = 0
    while i < len(lines):
        if i in replace:
            block = replace.pop(i)
            if block is not None:
                out.extend(block)
                out.append("")
            i += 1
            continue
        if i in skip:
            i += 1
            continue
        out.append(lines[i])
        i += 1
    return _squeeze_blanks(out)


def upsert(
    lines: list[str], plan: str, title: str, stages: list[tuple[int, str]]
) -> tuple[list[str], int]:
    """Add the plan's missing stages to its v2 block, creating the block if absent."""
    blocks, _ = parse(lines)
    group = [b for b in blocks if b.plan == plan]
    _, existing, extra = merge(group)
    missing = [(n, name) for n, name in stages if n not in existing]
    if not group:
        for n, name in missing:
            existing[n] = Stage(n, False, name)
        body = _squeeze_blanks(lines)
        if body and body[-1].strip():
            body.append("")
        return body + render_block(plan, title, existing, extra) + [""], len(missing)
    return rewrite(lines, {plan: title}, add={plan: missing}), len(missing)


def flip(lines: list[str], plan: str, stage_no: int) -> tuple[list[str], bool]:
    """Mark one stage ✅ in the plan's v2 block; False when that stage is not there."""
    blocks, _ = parse(lines)
    _, stages, _ = merge([b for b in blocks if b.plan == plan])
    if stage_no not in stages:
        return lines, False
    return rewrite(lines, flips={plan: {stage_no}}), True
