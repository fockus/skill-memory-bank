#!/usr/bin/env python3
"""Requirement anchors and REQ-ID allocation for the OpenSpec adapter.

An imported requirement is anchored to its OpenSpec name by a hidden
``<!-- openspec-req: <name> -->`` marker (D-06), preceded by a
``<!-- openspec: cap=…; kind=… -->`` meta line (AGR-105). Re-import reuses the
anchored ``REQ-NNN``; a genuinely new name gets the next ID from
``mb-req-next-id.sh`` (NFR-005) or an in-memory fallback.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

try:
    from mb_openspec_model import OSRequirement
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_model import OSRequirement


def anchor_safe(name: str) -> str:
    """Neutralize HTML-comment delimiters inside a value placed in a comment.

    A source requirement name may itself contain `-->` (closes the comment
    early) or `<!--` (opens a nested one) — adversarial/malformed OpenSpec
    input must not be able to forge extra markers (e.g. a fake
    `<!-- mb-task:99 -->`) or leave dangling `-->` text in the output
    (REQ-005). The transform is reversible/non-lossy (HTML-entity-escape the
    delimiter sequences only) and canonical: T5's `anchor_map()` MUST apply
    this same transform to OpenSpec names before matching against anchors
    emitted here, or re-import lookups will miss (see design.md D-06).
    """
    return name.replace("<!--", "&lt;!--").replace("-->", "--&gt;")


def _disambiguate_anchor_name(name: str, seen: dict[str, int], emitted: set[str]) -> str:
    """Give a stable, distinct anchor name for a duplicate requirement name (F3/R2).

    First occurrence of ``name`` (within one :func:`_build_requirements` call)
    returns ``name`` unchanged; the second returns ``name#2``, the third
    ``name#3``, and so on — so two source requirements sharing a name never
    collapse onto the same ``<!-- openspec-req: ... -->`` anchor (design.md
    § Risks: "Duplicate requirement names collide on the anchor" — "append an
    index to the anchor marker + warn"). ``seen`` counts occurrences of the
    base ``name`` and is mutated in place; it must be a fresh dict per
    :func:`convert` call so counts don't leak across imports.

    R2 (Codex round-2 residual): a naive ``name#2`` candidate can ALSO be a
    distinct requirement's own literal name (e.g. one requirement is named
    ``Widget`` twice, and a THIRD, unrelated requirement is literally named
    ``Widget#2``) — blindly returning the candidate would collapse two
    unrelated requirements onto the same anchor/REQ-NNN. ``emitted`` is the
    set of every anchor name already WRITTEN so far this call (also a fresh
    set per :func:`convert` call); the candidate loop skips past any name
    already in ``emitted`` — whether it got there via a prior disambiguation
    or is simply another requirement's own literal name — so no two
    requirements ever end up sharing an anchor.
    """
    seen[name] = seen.get(name, 0) + 1
    n = seen[name]
    candidate = name if n == 1 else f"{name}#{n}"
    while candidate in emitted:
        n += 1
        candidate = f"{name}#{n}"
    seen[name] = n
    emitted.add(candidate)
    return candidate


def meta_line(req: OSRequirement) -> str:
    """The ``<!-- openspec: cap=…; kind=…[; from=…] -->`` line placed before an
    anchor (or a Removed-scope heading) so export knows where a unit goes (AGR-105)."""
    parts = [f"cap={anchor_safe(req.capability)}", f"kind={req.change_kind}"]
    if req.change_kind == "renamed" and req.renamed_from:
        parts.append(f"from={anchor_safe(req.renamed_from)}")
    return f"<!-- openspec: {'; '.join(parts)} -->"


def assign_anchors(requirements: list[OSRequirement]) -> list[str | None]:
    """The anchor name of each requirement in document order (``None`` for REMOVED).

    A RENAMED entry anchors on its ``TO`` name as-is; every other entry goes
    through :func:`_disambiguate_anchor_name` with fresh per-call state, so the
    converter and the sync sidecar always agree on unit keys.
    """
    seen: dict[str, int] = {}
    emitted: set[str] = set()
    out: list[str | None] = []
    for req in requirements:
        if req.change_kind == "removed":
            out.append(None)
            continue
        name = anchor_safe(req.name)
        if req.change_kind == "renamed":
            emitted.add(name)
            out.append(name)
            continue
        out.append(_disambiguate_anchor_name(name, seen, emitted))
    return out


_ANCHOR_AND_BULLET_RE = re.compile(
    r"^<!-- openspec-req: (?P<name>.*) -->$\n"
    r"-\s+\*\*(?P<req_id>REQ-\d{3,})\*\*\s+\((?P<pattern>[^)]*)\):\s*(?P<text>.*)$",
    re.MULTILINE,
)


def _prior_requirement_index(prior_requirements_md: str) -> dict[str, tuple[str, str, str]]:
    """Escaped-name -> (req_id, pattern, text) parsed from a prior requirements.md.

    Reads exactly the shape ``_build_requirements`` writes: an
    ``<!-- openspec-req: <name> -->`` anchor immediately followed by its
    ``- **REQ-NNN** (pattern): text`` bullet, with no blank line between them.
    """
    out: dict[str, tuple[str, str, str]] = {}
    for m in _ANCHOR_AND_BULLET_RE.finditer(prior_requirements_md):
        out[m.group("name")] = (m.group("req_id"), m.group("pattern"), m.group("text"))
    return out


def anchor_map(prior_requirements_md: str) -> dict[str, str]:
    """OpenSpec requirement name (escaped via `anchor_safe`) -> its REQ-NNN (D-06).

    Reads the ``<!-- openspec-req: <name> -->`` anchor + the REQ bullet that
    immediately follows it, as written by ``_build_requirements``. Callers
    MUST run a candidate OpenSpec requirement name through :func:`anchor_safe`
    before looking it up here — the keys are the same escaped form used when
    the anchor was written, so a name containing ``<!--``/``-->`` still
    round-trips instead of silently missing the map (see ``anchor_safe``'s
    docstring / design.md D-06).
    """
    return {name: info[0] for name, info in _prior_requirement_index(prior_requirements_md).items()}


class _IdAllocator:
    """Allocates the next REQ-NNN for a genuinely new re-import requirement.

    Seeded once per :func:`convert` call — from ``mb-req-next-id.sh --spec
    <topic>`` when a topic/bank path are supplied (NFR-005: reuse the
    project's existing per-spec-local ID allocator instead of reinventing
    numbering rules), else from the highest ID already present in the prior
    anchor map — then incremented in-process for any further new
    requirements found in the same call. The script only reflects the
    ON-DISK prior file at the moment it is invoked; calling it again per
    requirement would hand out the SAME "next" id to every new name in one
    import, so it is seeded once and advanced locally instead.
    """

    def __init__(
        self,
        prior_map: dict[str, str],
        topic: str | None,
        mb_path: str | Path | None,
    ) -> None:
        start = None
        if topic and mb_path is not None:
            start = _next_id_via_script(topic, mb_path)
        if start is None:
            start = _fallback_next_id(prior_map.values())
        match = re.match(r"REQ-(\d+)", start)
        self._next_n = int(match.group(1)) if match else 1

    def allocate(self) -> str:
        req_id = f"REQ-{self._next_n:03d}"
        self._next_n += 1
        return req_id


def _next_id_via_script(topic: str, mb_path: str | Path) -> str | None:
    """Shell out to the project's own REQ-ID allocator (NFR-005)."""
    script = Path(__file__).with_name("mb-req-next-id.sh")
    if not script.is_file():
        return None
    try:
        proc = subprocess.run(
            ["bash", str(script), "--spec", topic, str(mb_path)],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    out = proc.stdout.strip()
    return out or None


def _fallback_next_id(existing_ids) -> str:
    """Pure in-memory next-id, used when no topic/bank is available to shell out to."""
    max_n = 0
    for rid in existing_ids:
        m = re.match(r"REQ-(\d+)", rid)
        if m:
            max_n = max(max_n, int(m.group(1)))
    return f"REQ-{max_n + 1:03d}"
