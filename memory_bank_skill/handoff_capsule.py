"""Handoff capsule body builder for ``scripts/mb-handoff.sh`` (handoff-v2, Stage 1).

The shell script owns the lifecycle (lock, archive-rotate, file IO, arg parsing);
this module owns the *content*: it reads the active bank's core files and assembles
the capsule text — frontmatter plus the five fixed sections — then truncates the
whole thing to a hard character cap with a trailing ellipsis line.

Keeping the text assembly in Python (rather than awk/sed in the shell) buys robust
multi-line parsing and a precise, encoding-aware character count for the 1500-char
cap that the capsule is injected against verbatim. It has no third-party deps and
runs identically on Python 3.11/3.12.

CLI:
    python -m memory_bank_skill.handoff_capsule build \
        --bank <mb_path> --created <ISO8601Z> \
        [--trigger manual_update] [--session-id <id|null>] [--cap 1500]

Emits the full capsule on stdout.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CAP_DEFAULT = 1500
ELLIPSIS_LINE = "..."
# A single bullet is clipped to this many characters (plus a trailing ellipsis)
# so one pathologically long line can never evict a whole required section.
BULLET_CLIP = 160
BULLET_ELLIPSIS = "…"

# How many of each kind of item the capsule surfaces (spec §4).
N_PROGRESS = 5
N_PROGRESS_BODY_LINES = 2
N_CHECKLIST = 10
N_BACKLOG_HIGH = 3

_ACTIVE_PLANS_OPEN = "<!-- mb-active-plans -->"
_ACTIVE_PLANS_CLOSE = "<!-- /mb-active-plans -->"
# Markdown link target inside the active-plans block: [label](relative/path.md)
_LINK_RE = re.compile(r"\]\(([^)]+)\)")
# Backlog HIGH item heading: "### I-NNN ... [HIGH, <STATUS>...]".
# Capture the status token after the HIGH priority; it may be followed by a
# comma ("[HIGH, DONE, 2026-04-25]") or a space ("[HIGH, RESOLVED 2026-06-14 …]").
_BACKLOG_HIGH_RE = re.compile(r"^###\s+I-.*\[HIGH\s*,\s*([A-Za-z_][A-Za-z _]*?)\s*[,\]]")
# Backlog statuses that count as OPEN (a real, surfaceable blocker).
_BACKLOG_OPEN_STATUSES = {"NEW", "PLANNED", "IN_PROGRESS"}


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def active_plan(bank: Path) -> str | None:
    """First plan link inside the roadmap ``<!-- mb-active-plans -->`` block.

    Returns the relative path (link target), or ``None`` when the block is
    missing/empty or roadmap.md is absent.
    """
    text = _read(bank / "roadmap.md")
    if not text:
        return None
    inside = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == _ACTIVE_PLANS_OPEN:
            inside = True
            continue
        if stripped == _ACTIVE_PLANS_CLOSE:
            break
        if inside:
            m = _LINK_RE.search(line)
            if m:
                return m.group(1).strip()
    return None


def progress_entries(bank: Path) -> list[str]:
    """Last ``N_PROGRESS`` progress entries, each = its ``### `` heading line plus
    its first ``N_PROGRESS_BODY_LINES`` non-blank body lines (compact, one-per-entry).
    """
    text = _read(bank / "progress.md")
    if not text:
        return []
    lines = text.splitlines()
    entries: list[str] = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith("### "):
            heading = line[4:].strip()
            body: list[str] = []
            j = i + 1
            while j < n and len(body) < N_PROGRESS_BODY_LINES:
                nxt = lines[j]
                if nxt.startswith("### ") or nxt.startswith("## "):
                    break
                if nxt.strip():
                    body.append(nxt.strip())
                j += 1
            summary = heading
            if body:
                summary += " — " + "; ".join(body)
            entries.append(summary)
            i = j
            continue
        i += 1
    return entries[-N_PROGRESS:]


def unchecked_items(bank: Path) -> list[str]:
    """Top ``N_CHECKLIST`` UNCHECKED checklist items, marker stripped.

    Understands both checklist dialects this project uses interchangeably:

    * emoji form — ``- ⬜ label`` (unchecked) vs ``- ✅ label`` (checked);
    * GitHub task form — ``- [ ] label`` (unchecked) vs ``- [x]``/``- [X]``.

    The optional ``- ``/``* `` bullet prefix is tolerated, and the leading
    unchecked marker is stripped from the returned label.
    """
    text = _read(bank / "checklist.md")
    if not text:
        return []
    out: list[str] = []
    for line in text.splitlines():
        body = line.strip()
        # Drop an optional "- " / "* " bullet prefix.
        if body[:2] in ("- ", "* "):
            body = body[2:].lstrip()
        if body.startswith("⬜"):
            out.append(body[len("⬜") :].strip())
        elif body.startswith("[ ]"):
            out.append(body[len("[ ]") :].strip())
        else:
            # Checked (✅ / [x] / [X]) or non-item line → skip.
            continue
        if len(out) >= N_CHECKLIST:
            break
    return out


def high_backlog(bank: Path) -> list[str]:
    """Top ``N_BACKLOG_HIGH`` OPEN HIGH backlog headings, heading text only.

    Only items whose status token is ``NEW``/``PLANNED``/``IN_PROGRESS``
    (also ``IN PROGRESS``) count as open blockers; closed states
    (``DONE``/``RESOLVED``/``DECLINED``/``DEFERRED``/``CANCELLED`` …) are
    excluded. Both ``[HIGH, DONE, <date>]`` (comma after status) and
    ``[HIGH, RESOLVED <date> — …]`` (space after status) are handled.
    """
    text = _read(bank / "backlog.md")
    if not text:
        return []
    out: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        m = _BACKLOG_HIGH_RE.match(stripped)
        if not m:
            continue
        status = m.group(1).strip().upper().replace(" ", "_")
        if status not in _BACKLOG_OPEN_STATUSES:
            continue
        out.append(stripped.lstrip("# ").strip())
        if len(out) >= N_BACKLOG_HIGH:
            break
    return out


def _clip_bullet(text: str) -> tuple[str, bool]:
    """Clip one bullet's label to ``BULLET_CLIP`` chars, flagging if clipped.

    Returns ``(label, was_clipped)``. Clipping is character-based (never cuts a
    multibyte codepoint) and appends a single ``…`` so an over-long line can never
    consume the whole byte budget and evict a downstream required section.
    """
    if len(text) <= BULLET_CLIP:
        return text, False
    return text[:BULLET_CLIP].rstrip() + BULLET_ELLIPSIS, True


def _byte_len(line: str) -> int:
    """UTF-8 byte length of a rendered line including its trailing newline."""
    return len(line.encode("utf-8")) + 1  # +1 for the '\n' joiner/terminator


def build_capsule(
    bank: Path,
    *,
    created: str,
    trigger: str,
    session_id: str,
    active_stage: str = "null",
    cap: int = CAP_DEFAULT,
) -> str:
    """Assemble the capsule and enforce ``cap`` WITHOUT ever dropping a section.

    Truncation strategy (spec §4, MAJOR #1 fix): the *skeleton* — frontmatter,
    all five ``## `` headers, the single "Next concrete step" line and the
    "Pointers" list — is reserved first and always survives. Only the
    variable-length bullet lists (Now / Done / Open blockers) are trimmed to fit
    the remaining byte budget, and each individual bullet is pre-clipped to
    ``BULLET_CLIP`` chars. A trailing ``...`` line is appended only when content
    was actually clipped (a bullet shortened or a bullet dropped).
    """
    plan = active_plan(bank)
    plan_fm = plan if plan else "null"
    progress = progress_entries(bank)
    unchecked = unchecked_items(bank)
    backlog = high_backlog(bank)

    # Section content (spec §4 derivation rules).
    now_src: list[str] = []
    if plan:
        now_src.append(f"Active plan: {plan}")
    now_src.extend(unchecked[:2])
    if not now_src:
        now_src = ["(no active plan or unchecked items)"]

    done_src = list(reversed(progress)) if progress else ["(no recent progress entries)"]
    blockers_src = backlog if backlog else ["None"]

    next_step = unchecked[0] if unchecked else "Review status.md and pick the next item."
    next_step, next_clipped = _clip_bullet(next_step)
    pointers = ["status.md", "checklist.md"]
    if plan:
        pointers.append(plan)

    # Human-readable created stamp "YYYY-MM-DD HH:MM UTC" from the ISO instant.
    title_stamp = created
    if len(created) >= 16 and created.endswith("Z"):
        title_stamp = f"{created[0:10]} {created[11:16]} UTC"

    # Pre-clip every variable bullet so no single line can blow the budget.
    clipped_any = next_clipped
    now_items: list[str] = []
    for it in now_src:
        label, was = _clip_bullet(it)
        now_items.append(label)
        clipped_any = clipped_any or was
    done_items: list[str] = []
    for it in done_src:
        label, was = _clip_bullet(it)
        done_items.append(label)
        clipped_any = clipped_any or was
    blocker_items: list[str] = []
    for it in blockers_src:
        label, was = _clip_bullet(it)
        blocker_items.append(label)
        clipped_any = clipped_any or was

    # Fixed skeleton: frontmatter + headers + Next-step + Pointers. ALWAYS present.
    head: list[str] = [
        "---",
        "capsule_version: 1",
        f"created: {created}",
        f"trigger: {trigger}",
        f"session_id: {session_id}",
        f"active_plan: {plan_fm}",
        f"active_stage: {active_stage}",
        "---",
        "",
        f"# Handoff capsule — {title_stamp}",
        "",
    ]
    tail: list[str] = [
        "",
        "## Next concrete step",
        f"- {next_step}",
        "",
        "## Pointers (file paths the next session should read first)",
        *[f"- {p}" for p in pointers],
    ]

    # Reserve the skeleton's byte cost, plus one possible ellipsis line.
    ellipsis_cost = _byte_len(ELLIPSIS_LINE)
    fixed_lines = [
        *head,
        "## Now (what is in progress right this minute)",
        "## Done since last capsule",
        "## Open blockers",
        *tail,
    ]
    reserved = sum(_byte_len(line) for line in fixed_lines) + ellipsis_cost

    # Distribute the remaining budget across the three variable lists in order,
    # dropping bullets that don't fit (a section header still survives even if all
    # its bullets are dropped, because the headers are part of the reserved skeleton).
    remaining = cap - reserved
    fitted_now, dropped_n = _fit_bullets(now_items, remaining)
    remaining -= sum(_byte_len(f"- {b}") for b in fitted_now)
    fitted_done, dropped_d = _fit_bullets(done_items, remaining)
    remaining -= sum(_byte_len(f"- {b}") for b in fitted_done)
    fitted_blockers, dropped_b = _fit_bullets(blocker_items, remaining)

    dropped_any = dropped_n or dropped_d or dropped_b
    clipped_any = clipped_any or dropped_any

    lines: list[str] = [
        *head,
        "## Now (what is in progress right this minute)",
        *[f"- {b}" for b in fitted_now],
        "",
        "## Done since last capsule",
        *[f"- {b}" for b in fitted_done],
        "",
        "## Open blockers",
        *[f"- {b}" for b in fitted_blockers],
        *tail,
    ]
    if clipped_any:
        lines.append(ELLIPSIS_LINE)
    return "\n".join(lines) + "\n"


def _fit_bullets(items: list[str], budget_bytes: int) -> tuple[list[str], bool]:
    """Greedily keep leading bullets whose rendered bytes fit ``budget_bytes``.

    Returns ``(kept, dropped_any)``. At least one bullet is kept when the list is
    non-empty and the first bullet fits; if even the first does not fit, the list
    is emptied (the section header itself, reserved elsewhere, still survives).
    """
    kept: list[str] = []
    used = 0
    dropped = False
    for it in items:
        cost = _byte_len(f"- {it}")
        if used + cost <= budget_bytes:
            kept.append(it)
            used += cost
        else:
            dropped = True
    return kept, dropped


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="handoff_capsule")
    sub = parser.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="emit a handoff capsule on stdout")
    b.add_argument("--bank", required=True)
    b.add_argument("--created", required=True)
    b.add_argument("--trigger", default="manual_update")
    b.add_argument("--session-id", default="null")
    b.add_argument("--active-stage", default="null")
    b.add_argument("--cap", type=int, default=CAP_DEFAULT)
    args = parser.parse_args(argv)

    if args.cmd == "build":
        out = build_capsule(
            Path(args.bank),
            created=args.created,
            trigger=args.trigger,
            session_id=args.session_id,
            active_stage=args.active_stage,
            cap=args.cap,
        )
        sys.stdout.write(out)
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
