#!/usr/bin/env python3
"""Group-section rendering + progress for mb-roadmap-sync.sh (S4 Task 6).

Design.md C2 / REQ-002/003/012/013. Scans ``specs/*/requirements.md`` and
``plans/*.md`` frontmatter for a ``group:`` and renders one ``## Group: <slug>``
block per group inside the autosync fence, with members ordered by the shared
priority comparator (blocked_by as the dependency edge), per-member progress
(counters + percentage from mb_work_items), an aggregated group progress, an
``(unconfirmed)`` suffix for valid-but-unconfirmed ICE, and the observable
``unconfirmed_ice`` escalation set (AGR-021).

Kept out of the shell heredoc so the shell stays under the 400-line SRP gate;
member ordering reuses scripts/mb_roadmap_order.py and progress reuses
scripts/mb_work_items.py — no reimplementation.
"""

from __future__ import annotations

import re
import sys

from mb_roadmap_order import parse_ice_score, parse_pin, priority_order

_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
_CHECKED_RE = re.compile(r"^- \[[xX]\] ")
_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class SpecReadError(Exception):
    """An existing spec-side source file could not be read or decoded.

    Distinct from "no such file", which is a legitimate empty. The consumer
    (mb-roadmap-sync.sh) must exit 4 without writing rather than publish a
    roadmap with the unreadable spec's group silently deleted.
    """


class ProgressError(Exception):
    """A work-item source (tasks.md / plan) exists but cannot be read or parsed.

    Distinct from "no file yet", which is a legitimate 0%. The consumer
    (mb-roadmap-sync.sh) must exit 4 without writing rather than publish a
    fabricated zero over real progress.
    """


class GroupOrderingError(Exception):
    """Malformed member ordering input (pin / created / blocked_by).

    Per design C2 the shared group-ordering contract degrades a missing/invalid
    ``ice`` to a warning + legacy tail, but a malformed ``pin``/``created``/
    ``blocked_by`` is a hard error: the consumer (mb-roadmap-sync.sh, and S3's
    mb-work-resolve.sh --group) must exit 3, never silently normalize it.
    """


def _parse_blocked_by_strict(raw, topic):
    """Parse a flow-list of unique slugs; raise GroupOrderingError if malformed."""
    raw = (raw or "").strip()
    if raw == "":
        return []
    if not (raw.startswith("[") and raw.endswith("]")):
        raise GroupOrderingError(f"code=invalid_blocked_by spec={topic} value={raw}")
    inner = raw[1:-1].strip()
    if not inner:
        return []
    slugs: list[str] = []
    seen: set[str] = set()
    for part in inner.split(","):
        tok = part.strip().strip("\"'")
        if not tok or not _SLUG_RE.match(tok) or tok in seen:
            raise GroupOrderingError(f"code=invalid_blocked_by spec={topic} value={raw}")
        seen.add(tok)
        slugs.append(tok)
    return slugs


def _parse_frontmatter(text):
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        out[k.strip()] = v.strip()
    return out


def _read(path):
    """Read a spec-side source file.

    A MISSING file is legitimately empty (an optional context/<topic>.md simply
    may not exist). An existing file that cannot be read is NOT: turning that
    OSError into empty text dropped the member from scan_members, made the
    in-fence header look like an orphan, and let sync exit 0 after publishing a
    roadmap with the whole group deleted (finding 6). Same principle as
    compute_progress: absent is fine, unreadable is loud.
    """
    if not path.exists():
        return ""
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise SpecReadError(
            f"code=spec_read_error path={path} reason=not_utf8 detail={exc}"
        ) from exc
    except OSError as exc:
        raise SpecReadError(
            f"code=spec_read_error path={path} reason=unreadable detail={exc}"
        ) from exc


def compute_progress(path):
    """Return (percent, done, in_progress, planned, total) from mb_work_items.

    percent = floor(100 * checked_dod / total_dod); 0 when there are no DoD
    checkboxes. Counters are per work-item (stage/task) by status.

    ONLY an absent file is a legitimate zero — a spec whose tasks.md has not
    been generated yet genuinely has no progress. Everything else (unreadable
    file, non-UTF-8 bytes, mixed stage/task markers, malformed task fields) is
    raised as :class:`ProgressError` so the caller fails loudly BEFORE writing.
    The previous blanket ``except Exception`` turned a corrupt or half-written
    tasks.md into a confident ``progress=0%``, hiding the corruption behind a
    plausible number (finding 7, REQ-012).
    """
    from mb_work_items import MalformedTaskField, parse_work_items

    if not path.exists():
        return 0, 0, 0, 0, 0
    try:
        items = parse_work_items(path)
    except UnicodeDecodeError as exc:
        raise ProgressError(
            f"code=progress_parse_error path={path} reason=not_utf8 detail={exc}"
        ) from exc
    except OSError as exc:
        raise ProgressError(
            f"code=progress_parse_error path={path} reason=unreadable detail={exc}"
        ) from exc
    except (MalformedTaskField, ValueError) as exc:
        raise ProgressError(
            f"code=progress_parse_error path={path} reason=malformed detail={exc}"
        ) from exc
    total = len(items)
    done = sum(1 for it in items if it.status == "done")
    in_progress = sum(1 for it in items if it.status == "in-progress")
    planned = sum(1 for it in items if it.status == "pending")
    total_dod = sum(len(it.dod_lines) for it in items)
    checked = sum(1 for it in items for ln in it.dod_lines if _CHECKED_RE.match(ln))
    percent = (checked * 100 // total_dod) if total_dod else 0
    return percent, done, in_progress, planned, total


def _created_for(mb, topic):
    ctx = mb / "context" / (topic + ".md")
    if ctx.exists():
        return _parse_frontmatter(_read(ctx)).get("created") or None
    return None


def _member_from_frontmatter(mb, fm, topic, kind, rel, progress_path):
    ice_present = "ice" in fm
    score = parse_ice_score(fm.get("ice", "")) if ice_present else None
    # Invalid ICE degrades to a warning + legacy tail (score=None), never a hard
    # error — a member with no usable ICE simply sorts as legacy_tail (design C2).
    if ice_present and score is None:
        print(f"[warn] spec {topic}: invalid ice mapping; ignoring", file=sys.stderr)
    confirmed = fm.get("ice_confirmed", "").strip().lower() == "true"
    # Malformed pin / created / blocked_by are HARD errors (exit 3 upstream), not
    # silent normalization (design C2 shared ordering contract).
    pin_raw = fm.get("pin")
    if pin_raw is not None and pin_raw.strip() != "":
        pin_val = parse_pin(pin_raw)
        if pin_val is None:
            raise GroupOrderingError(f"code=invalid_pin spec={topic} value={pin_raw.strip()}")
    else:
        pin_val = None
    blocked_by = _parse_blocked_by_strict(fm.get("blocked_by"), topic)
    created = _created_for(mb, topic)
    if created is not None and not _DATE_RE.match(created.strip()):
        raise GroupOrderingError(f"code=invalid_created spec={topic} value={created.strip()}")
    percent, done, in_prog, planned, total = compute_progress(progress_path)
    return {
        "name": topic,
        "topic": topic,
        "rel": rel,
        "ice_score": score,
        "ice_present": ice_present,
        "ice_confirmed": confirmed,
        "pin": pin_val,
        "created": created,
        "depends_on": blocked_by,
        "blocked_by": blocked_by,
        "status": fm.get("status", "").strip() or "draft",
        "kind": kind,
        "progress": (percent, done, in_prog, planned, total),
    }


def scan_members(mb):
    """Return {group_slug: [member dicts]} from specs/*/requirements.md.

    Design C2 declares ``specs/*/requirements.md`` the SOLE source of groups;
    plans are never group members (their progress renders in the ordinary
    roadmap sections, not in a Group block).
    """
    groups: dict[str, list] = {}
    specs_dir = mb / "specs"
    if specs_dir.is_dir():
        for req in sorted(specs_dir.glob("*/requirements.md")):
            topic = req.parent.name
            fm = _parse_frontmatter(_read(req))
            group = fm.get("group", "").strip()
            if not group:
                continue
            member = _member_from_frontmatter(
                mb, fm, topic, "task", f"specs/{topic}/requirements.md", req.parent / "tasks.md"
            )
            groups.setdefault(group, []).append(member)
    return groups


def _ice_display(member):
    if member["ice_score"] is not None:
        return str(member["ice_score"])
    return "invalid" if member["ice_present"] else "no-ice"


def _member_line(member):
    # Grammar:
    #   <topic> — ice=<score|no-ice|invalid>[ (unconfirmed)] — <status> —
    #   progress=<N>% tasks(done=..,in_progress=..,planned=..,total=..) —
    #   blocked_by=<csv|none>
    #
    # REQ-002 requires percentage AND counters for EVERY spec/plan. A spec that
    # belongs to a group but is not referenced from any plan's linked_specs has
    # the Group member line as its ONLY row, so emitting the percentage alone
    # left it without counters anywhere in the roadmap (finding 3).
    ice = _ice_display(member)
    suffix = (
        " (unconfirmed)"
        if (member["ice_score"] is not None and not member["ice_confirmed"])
        else ""
    )
    percent, done, in_prog, planned, total = member["progress"]
    blk = ",".join(member["blocked_by"]) if member["blocked_by"] else "none"
    return (
        f"{member['topic']} — ice={ice}{suffix} — {member['status']} — "
        f"progress={percent}% tasks(done={done},in_progress={in_prog},"
        f"planned={planned},total={total}) — blocked_by={blk}"
    )


def render_groups(mb):
    """Return {'block': str, 'slugs': [ordered slugs], 'unconfirmed': [slugs]}.

    'block' is the group region to append after the Linked Specs section (empty
    when no group exists). 'slugs' are the discovered groups (bytewise C-locale
    order). 'unconfirmed' are member topics with a valid but unconfirmed ICE.
    """
    groups = scan_members(mb)
    if not groups:
        return {"block": "", "slugs": [], "unconfirmed": []}
    slugs = sorted(groups.keys())
    blocks = []
    unconfirmed = []
    for slug in slugs:
        ordered = priority_order(groups[slug])
        percents = [m["progress"][0] for m in ordered]
        agg = (sum(percents) // len(percents)) if percents else 0
        lines = [f"## Group: {slug}", f"progress={agg}%"]
        for m in ordered:
            lines.append(_member_line(m))
            if m["ice_score"] is not None and not m["ice_confirmed"]:
                unconfirmed.append(m["topic"])
        blocks.append("\n".join(lines))
    region = "\n" + "\n\n".join(blocks) + "\n"
    return {"block": region, "slugs": slugs, "unconfirmed": unconfirmed}


def fence_group_slugs(autoblock_text):
    """Return the `## Group: <slug>` headers found inside an existing autoblock."""
    return re.findall(r"(?m)^## Group: (\S+)\s*$", autoblock_text or "")
