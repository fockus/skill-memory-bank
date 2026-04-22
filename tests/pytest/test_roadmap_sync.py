"""Contract tests for mb-roadmap-sync.sh.

Public contract (what the script MUST do):
  C1. Scan `.memory-bank/plans/*.md` frontmatter
  C2. Between `<!-- mb-roadmap-auto -->` and `<!-- /mb-roadmap-auto -->`
      fences in roadmap.md, regenerate these sections:
        - `## Now (in progress)` — plans with status: in_progress
        - `## Next (strict order — depends)` — plans with status: queued AND parallel_safe: false
        - `## Parallel-safe (can run now)` — plans with status: queued AND parallel_safe: true AND depends_on empty
        - `## Paused / Archived` — plans with status: paused | cancelled
        - `## Linked Specs (active)` — distinct values from plans' linked_specs
  C3. Content outside the fence is preserved byte-for-byte
  C4. If fence is missing, script injects it after the `# Roadmap` H1
  C5. Idempotent: second run → byte-identical output
  C6. Exit 0 on success; non-zero on missing .memory-bank/; malformed plans are
      skipped with a stderr warning
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from textwrap import dedent

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-roadmap-sync.sh"


def _make_plan(
    plans_dir: Path,
    filename: str,
    *,
    type_: str = "feature",
    topic: str = "demo",
    status: str = "in_progress",
    depends_on: str = "[]",
    parallel_safe: str = "false",
    linked_specs: str = "[]",
    sprint: int = 1,
    phase_of: str = "demo",
) -> Path:
    body = dedent(f"""\
        ---
        type: {type_}
        topic: {topic}
        status: {status}
        depends_on: {depends_on}
        parallel_safe: {parallel_safe}
        linked_specs: {linked_specs}
        sprint: {sprint}
        phase_of: {phase_of}
        created: 2026-04-22
        ---

        # Plan: {topic}

        ## Task 1: Demo

        - [ ] Step 1
        """)
    path = plans_dir / filename
    path.write_text(body, encoding="utf-8")
    return path


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "plans").mkdir()
    (mb / "plans" / "done").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        dedent("""\
            # Roadmap

            _Last updated: stub_

            <!-- mb-roadmap-auto -->
            OLD CONTENT TO BE REPLACED
            <!-- /mb-roadmap-auto -->

            ## See also
            - traceability.md
            """),
        encoding="utf-8",
    )
    return mb


def _run(mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_contract_c1_c2_c5_basic_sync(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_now-demo.md",
        status="in_progress",
        topic="now-demo",
    )
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_next-demo.md",
        status="queued",
        depends_on="[plans/2026-04-22_feature_now-demo.md]",
        topic="next-demo",
    )
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_parallel-demo.md",
        status="queued",
        parallel_safe="true",
        topic="parallel-demo",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    assert "## Now (in progress)" in roadmap
    assert "now-demo" in roadmap
    assert "## Next (strict order — depends)" in roadmap
    assert "next-demo" in roadmap
    assert "## Parallel-safe (can run now)" in roadmap
    assert "parallel-demo" in roadmap
    # Old content gone
    assert "OLD CONTENT TO BE REPLACED" not in roadmap
    # Outside-fence content preserved
    assert "## See also" in roadmap
    # Section ordering (I4): Now → Next → Parallel-safe → Paused → Linked Specs
    idx_now = roadmap.index("## Now (in progress)")
    idx_next = roadmap.index("## Next (strict order — depends)")
    idx_par = roadmap.index("## Parallel-safe (can run now)")
    idx_paus = roadmap.index("## Paused / Archived")
    idx_spec = roadmap.index("## Linked Specs (active)")
    assert idx_now < idx_next < idx_par < idx_paus < idx_spec


def test_contract_c3_outside_fence_preserved(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    # Rewrite roadmap with distinctive outside-fence content
    (mb / "roadmap.md").write_text(
        dedent("""\
            # Roadmap

            SENTINEL-OUTSIDE-A

            <!-- mb-roadmap-auto -->
            replace me
            <!-- /mb-roadmap-auto -->

            SENTINEL-OUTSIDE-B
            """),
        encoding="utf-8",
    )
    _make_plan(mb / "plans", "2026-04-22_feature_x.md", topic="x")

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    assert "SENTINEL-OUTSIDE-A" in roadmap
    assert "SENTINEL-OUTSIDE-B" in roadmap
    assert "replace me" not in roadmap


def test_contract_c4_injects_fence_when_missing(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    (mb / "roadmap.md").write_text("# Roadmap\n\nno fence yet\n", encoding="utf-8")
    _make_plan(mb / "plans", "2026-04-22_feature_y.md", topic="y")

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    assert "<!-- mb-roadmap-auto -->" in roadmap
    assert "<!-- /mb-roadmap-auto -->" in roadmap
    assert "# Roadmap" in roadmap


def test_contract_c5_idempotent(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_plan(mb / "plans", "2026-04-22_feature_a.md", topic="a")
    _make_plan(mb / "plans", "2026-04-22_feature_b.md", status="paused", topic="b")

    first = _run(mb)
    assert first.returncode == 0, first.stderr
    after_first = (mb / "roadmap.md").read_text(encoding="utf-8")

    second = _run(mb)
    assert second.returncode == 0, second.stderr
    after_second = (mb / "roadmap.md").read_text(encoding="utf-8")

    assert after_first == after_second


def test_contract_c6_missing_mb_exits_nonzero(tmp_path: Path) -> None:
    result = subprocess.run(
        ["bash", str(SCRIPT), str(tmp_path / "nonexistent")],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0


def test_paused_and_linked_specs_sections(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_paused.md",
        status="paused",
        topic="paused-one",
    )
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_with-spec.md",
        status="in_progress",
        linked_specs="[specs/demo-spec]",
        topic="with-spec",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    assert "## Paused / Archived" in roadmap
    assert "paused-one" in roadmap
    assert "## Linked Specs (active)" in roadmap
    assert "specs/demo-spec" in roadmap


# ---------------------------------------------------------------------------
# Batch B reviewer findings — regression tests (I1/I2/I3/I4)
# ---------------------------------------------------------------------------


def test_malformed_plan_emits_warning_and_is_skipped(tmp_path: Path) -> None:
    """I1: plan without frontmatter → stderr warning, exit 0, plan omitted."""
    mb = _init_mb(tmp_path)
    # Valid plan alongside
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_ok.md",
        status="in_progress",
        topic="ok",
    )
    # Malformed plan (no frontmatter at all)
    bad = mb / "plans" / "2026-04-22_feature_bad.md"
    bad.write_text("# Plan: bad\n\nNo frontmatter here.\n", encoding="utf-8")

    result = _run(mb)
    assert result.returncode == 0, result.stderr
    assert "[warn] skipping plan without frontmatter" in result.stderr
    assert str(bad) in result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    # Valid plan rendered; malformed is not
    assert "ok" in roadmap
    assert "bad" not in roadmap.replace("bad", "") or "Plan: bad" not in roadmap


def test_queued_no_deps_not_parallel_lands_in_next(tmp_path: Path) -> None:
    """I2: queued plan with empty depends_on AND parallel_safe: false → Next section."""
    mb = _init_mb(tmp_path)
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_serial.md",
        status="queued",
        depends_on="[]",
        parallel_safe="false",
        topic="serial-queued",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    # Extract the Next section body only
    next_idx = roadmap.index("## Next (strict order — depends)")
    parallel_idx = roadmap.index("## Parallel-safe (can run now)")
    next_section = roadmap[next_idx:parallel_idx]
    assert "serial-queued" in next_section
    # And NOT in Parallel-safe
    paused_idx = roadmap.index("## Paused / Archived")
    parallel_section = roadmap[parallel_idx:paused_idx]
    assert "serial-queued" not in parallel_section


def test_block_style_list_emits_warning(tmp_path: Path) -> None:
    """I3: block-style YAML list in frontmatter → stderr warning."""
    mb = _init_mb(tmp_path)
    block_plan = mb / "plans" / "2026-04-22_feature_block.md"
    block_plan.write_text(
        dedent("""\
            ---
            type: feature
            topic: block-demo
            status: queued
            depends_on:
              - plans/some-other.md
              - plans/another.md
            parallel_safe: false
            linked_specs: []
            sprint: 1
            phase_of: demo
            created: 2026-04-22
            ---

            # Plan: block-demo

            ## Task 1: Demo
            """),
        encoding="utf-8",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr
    assert "uses block-style list" in result.stderr
    assert "depends_on" in result.stderr


def test_empty_sections_render_none_placeholder(tmp_path: Path) -> None:
    """I4: no plans → all sections render with `_None._` placeholder."""
    mb = _init_mb(tmp_path)
    # No plans at all

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    # Each section should have the _None._ placeholder
    for title in (
        "## Now (in progress)",
        "## Next (strict order — depends)",
        "## Parallel-safe (can run now)",
        "## Paused / Archived",
        "## Linked Specs (active)",
    ):
        idx = roadmap.index(title)
        # Expect the next non-blank content after the title to be `_None._`
        tail = roadmap[idx + len(title):]
        assert "_None._" in tail.split("##", 1)[0], f"Missing _None._ under {title}"


def test_link_format_in_plan_line(tmp_path: Path) -> None:
    """I4: plan line format is `- [topic](plans/<filename>) — title`."""
    mb = _init_mb(tmp_path)
    _make_plan(
        mb / "plans",
        "2026-04-22_feature_linkfmt.md",
        status="in_progress",
        topic="linkfmt-topic",
    )

    result = _run(mb)
    assert result.returncode == 0, result.stderr

    roadmap = (mb / "roadmap.md").read_text(encoding="utf-8")
    expected = "- [linkfmt-topic](plans/2026-04-22_feature_linkfmt.md) — linkfmt-topic"
    assert expected in roadmap, (
        f"Expected link format not found.\nLooking for: {expected!r}\n"
        f"Roadmap:\n{roadmap}"
    )
