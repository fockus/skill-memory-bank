#!/usr/bin/env python3
"""Deterministic converter — :class:`OSChange` → Memory Bank spec-triple strings.

``convert()`` never touches disk except for read-only/no-write subprocess
shell-outs it reuses (``mb-ears-validate.sh`` for warn-mode EARS checking,
``mb-req-next-id.sh`` for REQ-ID allocation on re-import) and — only when
``normalize=True`` — the small JSON cache written by
``mb_openspec_normalize.NormalizeCache`` under ``<mb_path>/.index/openspec/``.
It only *returns* three Markdown strings (requirements.md, design.md,
tasks.md). The format is a fixed skeleton (headers, ``- **REQ-NNN**``,
``<!-- openspec-req: ... -->``, ``<!-- mb-task:N -->``) — 100% template-driven,
never LLM-generated even with ``--normalize`` (REQ-002, REQ-006, REQ-009, D-04).

``prior_triple`` (anchor reuse across re-import, D-06/D-05, REQ-016/018) makes
``convert()`` reuse the existing ``REQ-NNN`` for an OpenSpec requirement name
already anchored in the prior ``requirements.md``, re-anchor RENAMED deltas
FROM -> TO while preserving the ID, and allocate the next ID (via
``mb-req-next-id.sh --spec <topic>``, or a pure in-memory fallback when no
topic/bank is supplied) for a genuinely new name. ``normalize`` (T6, LLM slot
filling, D-03/D-04) fills the requirement text/scenario/covers *text slots*
via ``mb_openspec_normalize`` — never the skeleton itself — cached by
source-requirement hash so an unchanged requirement never regenerates
(REQ-008) and a failed/unavailable LLM falls back to the same deterministic
text this module already produces with ``normalize=False`` (REQ-010).
``normalize=False`` (the default) never touches the cache or an ``llm``
callable at all — byte-identical to the pre-T6 path (NFR-001).

Task check-state preservation across re-import (REQ-016/017) is a SEPARATE
function, :func:`merge_task_state` — ``convert()`` always returns a freshly
rendered ``tasks_md`` reflecting the current source only; the caller (the
``import``/``sync`` writer) is responsible for merging it against the prior
``tasks.md`` and appending any orphaned task to ``backlog.md``.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

try:
    from mb_openspec_model import OSChange, OSScenario
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_model import OSChange, OSScenario

try:
    from mb_openspec_normalize import (
        LlmDispatch,
        NormalizeCache,
        normalize_requirement,
        scenario_from_slot,
    )
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))

_TRIGGER_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"^when\b", re.IGNORECASE), "event-driven"),
    (re.compile(r"^while\b", re.IGNORECASE), "state-driven"),
    (re.compile(r"^where\b", re.IGNORECASE), "optional"),
    (re.compile(r"^if\b", re.IGNORECASE), "unwanted"),
)


def _flatten(text: str) -> str:
    """Collapse a (possibly multi-line) requirement body into one line."""
    return " ".join(text.split())


def _classify_pattern(text: str) -> str:
    """Auto-classify the EARS pattern from the leading trigger word (REQ-009)."""
    stripped = text.strip()
    for pattern, name in _TRIGGER_PATTERNS:
        if pattern.match(stripped):
            return name
    return "ubiquitous"


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


def merge_task_state(new_tasks_md: str, prior_tasks_md: str) -> tuple[str, list[str]]:
    """Preserve `/mb work` check-state across re-import (D-05, REQ-016/REQ-017).

    Checkbox items are matched between ``prior_tasks_md`` (the previously
    written tasks.md, possibly hand-edited by ``/mb work``) and
    ``new_tasks_md`` (freshly regenerated from the current OpenSpec source)
    by *normalized task text* (trim + collapse internal whitespace) — never
    by position, for the same reason anchors key requirements by name rather
    than document order (D-06).

    - A prior checked task whose text still exists in the new source stays
      checked.
    - A task text that is genuinely new always arrives UNCHECKED, regardless
      of whatever checkbox state the OpenSpec source itself renders for it —
      the OpenSpec side's own progress tracking is not ours to inherit.
    - A prior task text that no longer exists anywhere in the new source is
      never silently dropped: its original raw checklist line is returned in
      ``orphaned_task_lines`` for the caller to append to ``backlog.md``
      (REQ-017).

    Returns ``(merged_tasks_md, orphaned_task_lines)``.
    """
    prior_checked: dict[str, bool] = {}
    prior_raw: dict[str, str] = {}
    for line in prior_tasks_md.splitlines():
        m = _MB_CHECKBOX_RE.match(line)
        if not m:
            continue
        norm = _normalize_task_text(m.group("text"))
        prior_checked[norm] = m.group("mark").lower() == "x"
        prior_raw[norm] = line

    matched: set[str] = set()
    merged_lines: list[str] = []
    for line in new_tasks_md.splitlines():
        m = _MB_CHECKBOX_RE.match(line)
        if not m:
            merged_lines.append(line)
            continue
        norm = _normalize_task_text(m.group("text"))
        if norm in prior_checked:
            matched.add(norm)
            mark = "x" if prior_checked[norm] else " "
        else:
            mark = " "  # a genuinely new task always arrives unchecked (D-05)
        merged_lines.append(f"- [{mark}] {m.group('text')}")

    orphaned_task_lines = [prior_raw[norm] for norm in prior_checked if norm not in matched]
    merged_md = "\n".join(merged_lines).rstrip() + "\n"
    return merged_md, orphaned_task_lines


_MB_CHECKBOX_RE = re.compile(r"^-\s\[(?P<mark>[ xX])\]\s+(?P<text>.+)$")


def _normalize_task_text(text: str) -> str:
    return " ".join(text.split())


def _empty_scenario_stub() -> OSScenario:
    """Deterministic fallback for a requirement with zero scenarios."""
    return OSScenario(
        name="(none provided)",
        steps=[("WHEN", "not specified"), ("THEN", "not specified")],
    )


def _render_scenario(no: int, req_id: str, scenario: OSScenario) -> list[str]:
    lines = [
        f"<!-- mb-scenario:{no} -->",
        f"### Scenario: {scenario.name}",
        f"**Covers:** {req_id}",
        "",
    ]
    for keyword, text in scenario.steps:
        lines.append(f"- {keyword} {text}".rstrip())
    lines.append(f"<!-- /mb-scenario:{no} -->")
    lines.append("")
    return lines


def _build_requirements(
    ch: OSChange,
    prior_map: dict[str, str] | None,
    prior_index: dict[str, tuple[str, str, str]],
    allocator: _IdAllocator | None,
    *,
    normalize: bool = False,
    normalize_cache: NormalizeCache | None = None,
    llm: LlmDispatch | None = None,
) -> tuple[str, set[str]]:
    """Render the requirements skeleton.

    ``prior_map``/``prior_index``/``allocator`` are ``None``/empty on a fresh
    import (``prior_triple`` was not supplied to :func:`convert`) — that path
    is untouched from T2 and numbers every ADDED/MODIFIED requirement
    sequentially in document order (NFR-001 golden fixture). On a re-import
    (``prior_map`` is not ``None``), a requirement whose ``anchor_safe`` name
    is already anchored reuses its REQ-NNN (D-06); a RENAMED delta whose
    ``renamed_from`` is anchored moves that anchor to the new name, reusing
    both the ID and the prior text (a pure rename carries no new body text —
    D-07); anything genuinely new is allocated the next ID.

    ``normalize`` (T6, D-03/D-04): when set (with a ``normalize_cache``),
    every non-removed/non-renamed requirement's text/scenario/covers slots
    are filled via :func:`normalize_requirement` instead of the deterministic
    fallback — cached by source-requirement hash, so an unchanged
    requirement never re-invokes ``llm`` (REQ-008) and a failed/unavailable
    ``llm`` degrades to the exact same deterministic values (REQ-010). A
    RENAMED requirement's text is never normalized — it carries no new body
    text of its own (D-07), so there is nothing to rewrite.

    Returns ``(requirements_md, resolved_renamed_names)`` — the second value
    is the set of RENAMED "TO" names that were actually re-anchored this call,
    so ``_build_design`` does not also list them as still-deferred.
    """
    lines = [
        f"# Requirements: {ch.change_id}",
        "",
        f"> Imported from OpenSpec change `{ch.change_id}` — see design.md for Why/What Changes.",
        "> Deterministic skeleton (T2) — REQ-IDs assigned in document order; "
        "`--normalize` (T6) fills text slots.",
        "",
        "## Requirements (EARS)",
        "",
    ]
    req_no = 0
    scenario_no = 0
    resolved_renamed_names: set[str] = set()
    name_occurrence: dict[str, int] = {}
    emitted_anchors: set[str] = set()
    for req in ch.requirements:
        if req.change_kind == "removed":
            continue  # becomes a design.md "Removed scope" note instead (REQ-004)

        req_id: str | None = None
        text_line = _flatten(req.text) or "(no requirement text provided)"
        slots: dict[str, object] | None = None
        if normalize and req.change_kind != "renamed" and normalize_cache is not None:
            slots = normalize_requirement(req, cache=normalize_cache, llm=llm)
            slot_text = slots.get("text")
            if isinstance(slot_text, str) and slot_text.strip():
                text_line = slot_text

        anchor_name = anchor_safe(req.name)
        if req.change_kind == "renamed":
            resolved_id = None
            safe_from = anchor_safe(req.renamed_from or "")
            if prior_map is not None:
                resolved_id = prior_map.get(safe_from)
            if resolved_id is None:
                print(
                    f"[warn] RENAMED requirement '{req.name}' deferred to re-import (T5); "
                    "not emitted in this import",
                    file=sys.stderr,
                )
                continue
            req_id = resolved_id
            prior_entry = prior_index.get(safe_from)
            if prior_entry is not None:
                text_line = prior_entry[2]  # a pure rename carries no new body text
            resolved_renamed_names.add(req.name)
            # Register the anchor even on the renamed path (R2): a later
            # duplicate ADDED requirement's disambiguation loop must skip
            # past a name this rename already occupies, not just past names
            # produced by the `else` branch.
            emitted_anchors.add(anchor_name)
        else:
            # Disambiguate the anchor BEFORE the prior_map lookup (F3, design.md
            # § Risks): two source requirements sharing a name must never
            # collapse onto the same `<!-- openspec-req: ... -->` anchor / same
            # dict key — the second (and any further) occurrence gets `#2`,
            # `#3`, ... appended, both when reading the prior map and when
            # emitting the new anchor, so neither identity is silently lost.
            # R2: the candidate loop inside `_disambiguate_anchor_name` also
            # skips past any name ALREADY emitted this call (`emitted_anchors`)
            # -- including a distinct requirement's own literal name that
            # happens to look like `<name>#N` -- so two unrelated
            # requirements never collapse onto the same anchor.
            disambiguated = _disambiguate_anchor_name(anchor_name, name_occurrence, emitted_anchors)
            if disambiguated != anchor_name:
                print(
                    f"[warn] duplicate requirement name '{req.name}'; "
                    f"anchor disambiguated to '{disambiguated}'",
                    file=sys.stderr,
                )
            anchor_name = disambiguated
            if prior_map is not None:
                req_id = prior_map.get(anchor_name)
                if req_id is None:
                    assert allocator is not None
                    req_id = allocator.allocate()

        req_no += 1
        if req_id is None:
            req_id = f"REQ-{req_no:03d}"  # fresh import: sequential document order
        pattern = _classify_pattern(text_line)
        safe_name = anchor_safe(req.name)
        if safe_name != req.name:
            print(
                f"[warn] requirement name contains comment delimiters; "
                f"neutralized in anchor: '{req.name}'",
                file=sys.stderr,
            )
        # The heading stays human-readable (no disambiguation suffix); the
        # anchor comment is what re-import matches on, so IT carries the
        # disambiguated name for a duplicate (`anchor_name`) — a raw
        # `<!-- mb-task:N -->`-shaped name would also be a forged marker
        # regardless of which line it appears on, hence the same
        # `anchor_safe` neutralization either way.
        lines.append(f"### Requirement {req_no}: {safe_name}")
        lines.append("")
        lines.append(f"<!-- openspec-req: {anchor_name} -->")
        lines.append(f"- **{req_id}** ({pattern}): {text_line}")
        covers = slots.get("covers") if slots else None
        if covers:
            lines.append(f"**Covers:** {', '.join(str(c) for c in covers)}")
        lines.append("")
        scenarios = req.scenarios
        if not scenarios:
            generated = slots.get("scenario") if slots else None
            if generated:
                scenarios = [scenario_from_slot(generated)]
            else:
                print(
                    f"[warn] requirement '{req.name}' has no scenarios; using a deterministic stub",
                    file=sys.stderr,
                )
                scenarios = [_empty_scenario_stub()]
        for scenario in scenarios:
            scenario_no += 1
            lines.extend(_render_scenario(scenario_no, req_id, scenario))
    return "\n".join(lines).rstrip() + "\n", resolved_renamed_names


def _demote_headings(text: str) -> str:
    """Demote every Markdown heading one level (nests under a parent section)."""
    return re.sub(r"(?m)^(#{1,5})(\s)", r"#\1\2", text)


def _build_design(ch: OSChange, resolved_renamed_names: set[str] | None = None) -> str:
    resolved_renamed_names = resolved_renamed_names or set()
    lines = [
        f"# Design: {ch.change_id}",
        "",
        "## Why",
        "",
        ch.why or "(not provided)",
        "",
        "## What Changes",
        "",
        ch.what_changes or "(not provided)",
        "",
    ]
    if ch.design_md:
        lines.append("## OpenSpec Design Notes")
        lines.append("")
        lines.append(_demote_headings(ch.design_md.strip()))
        lines.append("")

    removed = [r for r in ch.requirements if r.change_kind == "removed"]
    if removed:
        lines.append("## Removed scope")
        lines.append("")
        for r in removed:
            lines.append(f"### {r.name}")
            lines.append("")
            lines.append(f"**Reason:** {r.reason or '(no reason recorded)'}")
            lines.append("")

    renamed = [
        r
        for r in ch.requirements
        if r.change_kind == "renamed" and r.name not in resolved_renamed_names
    ]
    if renamed:
        lines.append("## Deferred renames (re-import required)")
        lines.append("")
        for r in renamed:
            lines.append(
                f"- `{r.renamed_from}` -> `{r.name}` — anchor move handled on re-import (T5)."
            )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _build_tasks(ch: OSChange) -> str:
    lines = [
        f"# Tasks: {ch.change_id}",
        "",
        f"> Imported from OpenSpec change `{ch.change_id}` tasks.md.",
        "",
    ]
    if not ch.task_groups:
        lines.append("_(no tasks.md found in the source change)_")
        return "\n".join(lines).rstrip() + "\n"

    for group in ch.task_groups:
        lines.append(f"<!-- mb-task:{group.number} -->")
        lines.append(f"## Task {group.number}: {group.title}")
        lines.append("")
        lines.append("**Covers:** N/A")
        lines.append("**Role:** backend")
        lines.append("")
        for checked, item_text in group.items:
            if checked is None:
                lines.append(f"- {item_text}")
            else:
                mark = "x" if checked else " "
                lines.append(f"- [{mark}] {item_text}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _run_ears_warn(requirements_md: str, change_id: str) -> None:
    """Warn-mode EARS validation over the emitted requirements (REQ-020).

    Never aborts the import — warnings are surfaced to stderr only.
    """
    script = Path(__file__).with_name("mb-ears-validate.sh")
    if not script.is_file():
        return
    try:
        proc = subprocess.run(
            ["bash", str(script), "-"],
            input=requirements_md,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return
    for line in proc.stderr.splitlines():
        if line.strip():
            print(f"[warn][ears:{change_id}] {line}", file=sys.stderr)


def convert(
    ch: OSChange,
    prior_triple: tuple[str, str, str] | None = None,
    normalize: bool = False,
    *,
    topic: str | None = None,
    mb_path: str | Path | None = None,
    llm: LlmDispatch | None = None,
) -> tuple[str, str, str]:
    """Convert a parsed OpenSpec change into (requirements_md, design_md, tasks_md).

    Pure function w.r.t. disk writes — returns strings only, never writes to
    disk (REQ-003); it may shell out read-only to ``mb-req-next-id.sh``/
    ``mb-ears-validate.sh``.

    ``prior_triple`` (``(prior_requirements_md, prior_design_md,
    prior_tasks_md)``), when supplied, enables re-import anchor reuse (D-06):
    a requirement already anchored in ``prior_triple[0]`` keeps its REQ-NNN;
    a RENAMED delta re-anchors FROM -> TO while preserving the ID (REQ-018); a
    genuinely new name is allocated the next ID via ``topic``/``mb_path``
    (``mb-req-next-id.sh --spec <topic>``) or, absent those, a pure in-memory
    fallback. ``prior_triple[2]`` (tasks.md) is accepted for interface
    symmetry but is NOT used here — task check-state merging is the caller's
    job via the separate :func:`merge_task_state`.

    ``normalize`` (T6, D-03/D-04): ``False`` (default) is byte-identical to
    the pre-T6 deterministic path (NFR-001) — no cache is touched, no
    ``llm`` call happens. ``True`` fills the requirement text/scenario/covers
    slots via :func:`mb_openspec_normalize.normalize_requirement`, cached
    under ``<mb_path>/.index/openspec/normalize-cache.json`` keyed by
    source-requirement hash (REQ-008); an unavailable/failing ``llm``
    degrades to the exact deterministic slot values instead of failing the
    import (REQ-010). ``llm`` overrides the real dispatcher — used by tests
    to mock the LLM call; production callers leave it ``None``.
    """
    prior_map: dict[str, str] | None = None
    prior_index: dict[str, tuple[str, str, str]] = {}
    allocator: _IdAllocator | None = None
    if prior_triple is not None:
        prior_index = _prior_requirement_index(prior_triple[0])
        prior_map = {name: info[0] for name, info in prior_index.items()}
        allocator = _IdAllocator(prior_map, topic, mb_path)

    normalize_cache = NormalizeCache(mb_path) if normalize else None
    requirements_md, resolved_renamed_names = _build_requirements(
        ch,
        prior_map,
        prior_index,
        allocator,
        normalize=normalize,
        normalize_cache=normalize_cache,
        llm=llm,
    )
    if normalize_cache is not None:
        normalize_cache.flush()
    design_md = _build_design(ch, resolved_renamed_names)
    tasks_md = _build_tasks(ch)
    _run_ears_warn(requirements_md, ch.change_id)
    return requirements_md, design_md, tasks_md
