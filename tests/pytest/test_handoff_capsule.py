"""Unit tests for the handoff capsule builder (handoff-v2, Stage 1).

These tests pin three behaviours that a governed dual review flagged as
broken against the project's own ``.memory-bank/``:

* MAJOR #1 — truncation must never drop a required ``## `` section: the
  five headers + the Next-step + Pointers skeleton always survive; only the
  variable-length bullet lists get trimmed, and individual over-long bullets
  are clipped rather than allowed to evict whole sections.
* MAJOR #2 — ``unchecked_items`` must understand the live emoji checklist
  format (``⬜`` / ``✅``) as well as the GitHub ``- [ ]`` / ``- [x]`` form.
* MAJOR #3 — ``high_backlog`` must surface only OPEN HIGH items and exclude
  closed ones (DONE / RESOLVED / DECLINED / DEFERRED / CANCELLED).

Builder contract (spec §4): the five ``## `` sections in order are
``Now`` / ``Done since last capsule`` / ``Open blockers`` /
``Next concrete step`` / ``Pointers``, with a hard 1500-byte cap.
"""

from __future__ import annotations

from pathlib import Path

from memory_bank_skill import handoff_capsule as hc

REQUIRED_HEADERS = [
    "## Now",
    "## Done since last capsule",
    "## Open blockers",
    "## Next concrete step",
    "## Pointers",
]


def _bank(tmp_path: Path, **files: str) -> Path:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    for name, content in files.items():
        (bank / f"{name}.md").write_text(content, encoding="utf-8")
    return bank


def _build(bank: Path, **kw: object) -> str:
    params: dict[str, object] = dict(
        created="2026-06-15T09:00:00Z",
        trigger="manual_update",
        session_id="x",
    )
    params.update(kw)
    return hc.build_capsule(bank, **params)  # type: ignore[arg-type]


# --------------------------------------------------------------------------
# MAJOR #1 — truncation must preserve all five sections under oversized input
# --------------------------------------------------------------------------


def test_build_capsule_keeps_all_five_sections_under_oversized_input(tmp_path: Path):
    """A single huge bullet must not evict the trailing required sections."""
    long_entries = "\n\n".join(
        f"### Entry {i} — " + ("X" * 450) + f"\nbody line for entry {i} " + ("y" * 420)
        for i in range(1, 6)
    )
    progress = "# Progress\n\n## 2026-06-15\n\n" + long_entries + "\n"
    checklist = "# Checklist\n\n- ⬜ first unchecked task\n- ⬜ second unchecked task\n"
    backlog = "# Backlog\n\n### I-001 — open thing [HIGH, NEW, 2026-01-01]\nbody\n"
    bank = _bank(tmp_path, progress=progress, checklist=checklist, backlog=backlog)

    out = _build(bank, cap=1500)

    # (a) all five headers survive
    for header in REQUIRED_HEADERS:
        assert header in out, f"missing required section header: {header!r}"
    section_count = sum(1 for line in out.splitlines() if line.startswith("## "))
    assert section_count == 5, f"expected exactly 5 sections, got {section_count}"

    # (b) byte cap holds
    assert len(out.encode("utf-8")) <= 1500

    # (c) valid UTF-8, no split codepoint
    out.encode("utf-8").decode("utf-8")

    # (d) ellipsis present because content was actually clipped
    assert hc.ELLIPSIS_LINE in out


def test_build_capsule_clips_individual_overlong_bullet(tmp_path: Path):
    """One pathologically long bullet is clipped, not allowed to overflow."""
    progress = "# Progress\n\n## 2026-06-15\n\n### Single — " + ("Z" * 2000) + "\nbody\n"
    bank = _bank(tmp_path, progress=progress)

    out = _build(bank, cap=1500)

    section_count = sum(1 for line in out.splitlines() if line.startswith("## "))
    assert section_count == 5
    assert len(out.encode("utf-8")) <= 1500
    # the clipped bullet carries the ellipsis marker
    assert "…" in out or hc.ELLIPSIS_LINE in out


def test_build_capsule_no_ellipsis_when_content_fits(tmp_path: Path):
    """Small banks render without any clip marker."""
    progress = "# Progress\n\n## 2026-06-15\n\n### Short — done\nbody\n"
    checklist = "# Checklist\n\n- ⬜ pick next item\n"
    bank = _bank(tmp_path, progress=progress, checklist=checklist)

    out = _build(bank, cap=1500)

    section_count = sum(1 for line in out.splitlines() if line.startswith("## "))
    assert section_count == 5
    assert len(out.encode("utf-8")) <= 1500
    # No standalone ellipsis line and no clipped-bullet marker for tiny content.
    assert not any(line.strip() == hc.ELLIPSIS_LINE for line in out.splitlines())
    assert "…" not in out


def test_build_capsule_multibyte_never_cuts_codepoint(tmp_path: Path):
    """Cyrillic-heavy progress must still decode cleanly under the byte cap."""
    body = "Длинная многобайтовая строка прогресса с кириллицей и хвостом. " * 12
    entries = "\n\n".join(f"### Запись {i} — {body}" for i in range(1, 6))
    progress = "# Progress\n\n## 2026-06-15\n\n" + entries + "\n"
    bank = _bank(tmp_path, progress=progress)

    out = _build(bank, cap=1500)

    assert len(out.encode("utf-8")) <= 1500
    # Round-trips cleanly (would raise on a split multibyte sequence).
    assert out.encode("utf-8").decode("utf-8") == out
    section_count = sum(1 for line in out.splitlines() if line.startswith("## "))
    assert section_count == 5


# --------------------------------------------------------------------------
# MAJOR #2 — emoji checklist format
# --------------------------------------------------------------------------


def test_unchecked_items_handles_emoji_and_bracket_formats(tmp_path: Path):
    checklist = (
        "# Checklist\n\n"
        "## Done\n"
        "- ✅ finished emoji item\n"
        "- [x] finished bracket item\n"
        "- [X] finished bracket caps item\n"
        "## Active\n"
        "- ⬜ open emoji item\n"
        "- [ ] open bracket item\n"
        "* ⬜ open star-bullet item\n"
    )
    bank = _bank(tmp_path, checklist=checklist)

    items = hc.unchecked_items(bank)

    assert items == [
        "open emoji item",
        "open bracket item",
        "open star-bullet item",
    ]
    # checked items never leak in, markers are stripped
    for it in items:
        assert "⬜" not in it and "[ ]" not in it
    assert "finished emoji item" not in items
    assert "finished bracket item" not in items


def test_unchecked_items_respects_top_n_cap(tmp_path: Path):
    lines = "\n".join(f"- ⬜ item {i}" for i in range(1, 20))
    bank = _bank(tmp_path, checklist="# Checklist\n\n" + lines + "\n")

    items = hc.unchecked_items(bank)

    assert len(items) == hc.N_CHECKLIST
    assert items[0] == "item 1"


# --------------------------------------------------------------------------
# MAJOR #3 — only OPEN HIGH backlog items are blockers
# --------------------------------------------------------------------------


def test_high_backlog_excludes_closed_statuses(tmp_path: Path):
    backlog = (
        "# Backlog\n\n"
        "### I-061 — open planned [HIGH, PLANNED, 2026-05-24]\nbody\n"
        "### I-070 — medium ignored [MEDIUM, NEW, 2026-05-24]\nbody\n"
        "### I-033 — closed done [HIGH, DONE, 2026-04-25]\nbody\n"
        "### I-003 — open new [HIGH, NEW, 2026-04-19]\nbody\n"
        "### I-020 — declined [HIGH, DECLINED, 2026-04-20]\nbody\n"
        "### I-099 — in progress [HIGH, IN_PROGRESS, 2026-06-01]\nbody\n"
        "### I-098 — in progress spaced [HIGH, IN PROGRESS, 2026-06-01]\nbody\n"
        "### I-001 — deferred [HIGH, DEFERRED, 2026-04-20]\nbody\n"
        "### I-066 — resolved no comma [HIGH, RESOLVED 2026-06-14 — abc]\nbody\n"
    )
    bank = _bank(tmp_path, backlog=backlog)

    items = hc.high_backlog(bank)

    # Only NEW / PLANNED / IN_PROGRESS HIGH items, capped at N_BACKLOG_HIGH, in order.
    assert len(items) == hc.N_BACKLOG_HIGH
    assert items[0].startswith("I-061")
    assert any(it.startswith("I-003") for it in items)
    assert any(it.startswith("I-099") for it in items)
    # closed statuses excluded
    joined = " ".join(items)
    for closed_id in ("I-033", "I-020", "I-001", "I-066"):
        assert closed_id not in joined, f"closed item {closed_id} leaked into blockers"
    # MEDIUM never appears
    assert "I-070" not in joined


def test_high_backlog_accepts_in_progress_spaced_variant(tmp_path: Path):
    backlog = "# Backlog\n\n### I-200 — spaced [HIGH, IN PROGRESS, 2026-06-01]\nbody\n"
    bank = _bank(tmp_path, backlog=backlog)

    items = hc.high_backlog(bank)

    assert len(items) == 1
    assert items[0].startswith("I-200")


def test_high_backlog_resolved_without_comma_is_excluded(tmp_path: Path):
    backlog = "# Backlog\n\n### I-066 — resolved [HIGH, RESOLVED 2026-06-14 — abc]\nbody\n"
    bank = _bank(tmp_path, backlog=backlog)

    assert hc.high_backlog(bank) == []
