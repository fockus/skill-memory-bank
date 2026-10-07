"""Stage 9 (graph-semantic-adoption, I-225): ``--apply`` without networkx must not
wipe ``## Communities`` / ``## Bridge files`` from ``god-nodes.md``.

Without networkx the sections cannot be recomputed, so they are carried over
verbatim from the previous report under an explicit marker. With networkx they
are recomputed from scratch (the marker never accumulates). Tests compare the
carried text, never recomputed cluster contents (Louvain is non-deterministic, I-219).
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import codegraph_analytics as cga  # noqa: E402

MARKER_HEAD = "_Carried over from "
MARKER_TAIL = "networkx is unavailable in this interpreter, so these sections were not recomputed."
PRUNED_NOTE = "Files no longer in the graph were removed from these rows."
SOURCE_A = "the build of commit aaa111 at 2026-09-01T10:00:00Z"
SOURCE_B = "the build of commit bbb222 at 2026-09-20T10:00:00Z"


def _markers(md: str) -> list[str]:
    return [ln for ln in md.splitlines() if ln.startswith(MARKER_HEAD)]


COMMUNITIES_BLOCK = """## Communities (auto-detected module clusters)

_Cohesion = intra-cluster file-edge density (1.0 = fully coupled)._

| Community | Files | Cohesion | Sample |
|---|---|---|---|
| 0 | 12 | 0.42 | `scripts/old_cluster.py` |"""

BRIDGE_BLOCK = """## Bridge files (highest betweenness)

_Removing these fragments the module graph — refactor with care._

| # | File | Betweenness |
|---|---|---|
| 1 | `scripts/old_bridge.py` | 0.314 |"""

NEIGHBOUR_BLOCK = """## Co-change pairs

| a | b |
|---|---|
| `x.py` | `y.py` |"""


def _graph() -> dict:
    return {
        "nodes": [
            {"type": "node", "kind": "module", "name": "hub.py", "file": "hub.py", "line": 1},
            {"type": "node", "kind": "function", "name": "fresh_hub", "file": "hub.py", "line": 2},
            {"type": "node", "kind": "module", "name": "a.py", "file": "a.py", "line": 1},
            {"type": "node", "kind": "function", "name": "a", "file": "a.py", "line": 1},
            {
                "type": "node",
                "kind": "module",
                "name": "scripts/old_cluster.py",
                "file": "scripts/old_cluster.py",
                "line": 1,
            },
            {
                "type": "node",
                "kind": "module",
                "name": "scripts/old_bridge.py",
                "file": "scripts/old_bridge.py",
                "line": 1,
            },
        ],
        "edges": [{"type": "edge", "kind": "call", "src": "a.py:a", "dst": "fresh_hub"}],
    }


def _previous_md(*blocks: str) -> str:
    head = "# God nodes & code-graph analytics\n\n## Top symbols (functions / classes)\n\n| stale_sym |\n"
    return head + "\n" + "\n\n".join(blocks) + "\n"


def test_carryover_without_networkx_keeps_both_sections_verbatim_with_marker(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    prev = _previous_md(COMMUNITIES_BLOCK, BRIDGE_BLOCK)

    md = cga.render_god_nodes_md(_graph(), previous_md=prev)

    # every non-heading line of both blocks survives verbatim
    for block in (COMMUNITIES_BLOCK, BRIDGE_BLOCK):
        for line in block.splitlines()[1:]:
            assert line in md.splitlines()
    assert md.count("## Communities (auto-detected module clusters)") == 1
    assert md.count("## Bridge files (highest betweenness)") == 1
    # marker sits right under each carried heading
    lines = md.splitlines()
    for heading in ("## Communities", "## Bridge files"):
        idx = next(i for i, ln in enumerate(lines) if ln.startswith(heading))
        assert lines[idx + 2].startswith(MARKER_HEAD) and MARKER_TAIL in lines[idx + 2]
    # nothing was pruned → no pruned note
    assert PRUNED_NOTE not in md
    # Top symbols are recomputed from the new graph, not carried
    assert "fresh_hub" in md
    assert "stale_sym" not in md
    # install hint stays
    assert "Install `networkx`" in md


def test_carryover_absent_previous_file_is_byte_identical_to_today(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    baseline = cga.render_god_nodes_md(_graph())

    assert cga.render_god_nodes_md(_graph(), previous_md=None) == baseline
    assert cga.render_god_nodes_md(_graph(), previous_md="# no sections here\n") == baseline
    assert "## Communities" not in baseline
    assert "Install `networkx`" in baseline


def test_carryover_marker_not_accumulated_when_networkx_recomputes():
    prev = _previous_md(
        COMMUNITIES_BLOCK.replace("\n\n", f"\n\n{MARKER_HEAD}{SOURCE_A}: {MARKER_TAIL}_\n\n", 1),
        BRIDGE_BLOCK,
    )
    md = cga.render_god_nodes_md(
        _graph(),
        communities={"hub.py": 0, "a.py": 0},
        betweenness={"a.py": 0.5},
        previous_md=prev,
    )

    assert not _markers(md)
    assert "old_cluster.py" not in md
    assert "## Communities" in md


def test_carryover_repeated_without_networkx_keeps_single_marker(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    once = cga.render_god_nodes_md(
        _graph(), previous_md=_previous_md(COMMUNITIES_BLOCK, BRIDGE_BLOCK)
    )

    twice = cga.render_god_nodes_md(_graph(), previous_md=once)

    assert twice == once
    assert len(_markers(twice)) == 2  # one per section, never stacked


def test_carryover_block_stops_at_next_heading(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    prev = _previous_md(COMMUNITIES_BLOCK, NEIGHBOUR_BLOCK, BRIDGE_BLOCK)

    md = cga.render_god_nodes_md(_graph(), previous_md=prev)

    assert "## Co-change pairs" not in md
    assert "`x.py`" not in md
    assert "old_bridge.py" in md


def test_apply_without_networkx_preserves_sections_in_written_file(tmp_path, monkeypatch):
    """Wiring: ``mb-codegraph.py --apply`` feeds the existing god-nodes.md to the renderer."""
    spec = importlib.util.spec_from_file_location(
        "mb_codegraph_s9", REPO_ROOT / "scripts" / "mb-codegraph.py"
    )
    cg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cg)
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.py").write_text("def a():\n    return 1\n")
    (src / "scripts").mkdir()
    (src / "scripts" / "old_cluster.py").write_text("X = 1\n")
    (src / "scripts" / "old_bridge.py").write_text("Y = 1\n")
    god = mb / "codebase" / "god-nodes.md"
    gone_row = "| 7 | 2 | 1.00 | a.py, gone.py |"
    god.write_text(_previous_md(COMMUNITIES_BLOCK + "\n" + gone_row, BRIDGE_BLOCK))
    # the previous build's stamp names the source of the carried sections
    (mb / "codebase" / "graph.json").write_text(
        '{"type": "meta", "schema": 1, "generated_at": "2026-09-01T10:00:00Z", '
        '"commit": "aaa111", "nodes": 0, "edges": 0}\n'
    )

    cg.run(mb_path=str(mb), src_root=str(src), mode="apply")

    written = god.read_text()
    assert "old_cluster.py" in written
    assert "old_bridge.py" in written
    assert len(_markers(written)) == 2
    assert all(SOURCE_A in m for m in _markers(written))
    # repro of the verify finding: a deleted file does not linger in the carried rows
    assert "gone.py" not in written
    assert "| 7 | 1 | 1.00 | a.py |" in written


def test_apply_unreadable_previous_file_fails_open(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location(
        "mb_codegraph_s9b", REPO_ROOT / "scripts" / "mb-codegraph.py"
    )
    cg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cg)
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.py").write_text("def a():\n    return 1\n")
    god = mb / "codebase" / "god-nodes.md"
    god.write_bytes(b"\xff\xfe## Communities \x80 broken")

    cg.run(mb_path=str(mb), src_root=str(src), mode="apply")

    written = god.read_text()
    assert "## Communities" not in written
    assert "Install `networkx`" in written


def test_carryover_marker_names_source_commit_and_date(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)

    md = cga.render_god_nodes_md(
        _graph(), previous_md=_previous_md(COMMUNITIES_BLOCK, BRIDGE_BLOCK), carry_source=SOURCE_A
    )

    assert _markers(md) == [f"{MARKER_HEAD}{SOURCE_A}: {MARKER_TAIL}_"] * 2


def test_carryover_repeated_keeps_original_source_not_intermediate_build(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    once = cga.render_god_nodes_md(
        _graph(), previous_md=_previous_md(COMMUNITIES_BLOCK, BRIDGE_BLOCK), carry_source=SOURCE_A
    )

    # the intermediate networkx-less build has its own stamp; it must not become the source
    twice = cga.render_god_nodes_md(_graph(), previous_md=once, carry_source=SOURCE_B)

    assert all(SOURCE_A in m for m in _markers(twice))
    assert SOURCE_B not in twice
    assert twice == once


PRUNE_COMMUNITIES = """## Communities (auto-detected module clusters)

_Cohesion = intra-cluster file-edge density (1.0 = fully coupled)._

| Community | Files | Cohesion | Sample |
|---|---|---|---|
| 0 | 12 | 0.42 | scripts/old_cluster.py |
| 1 | 2 | 1.00 | a.py, gone.py |
| 2 | 1 | 1.00 | only_gone.py |
| 3 | 5 | 0.10 | a.py, gone.py, hub.py … |"""

PRUNE_BRIDGE = """## Bridge files (highest betweenness)

_Removing these fragments the module graph — refactor with care._

| # | File | Betweenness |
|---|---|---|
| 1 | `gone.py` | 0.500 |
| 2 | `scripts/old_bridge.py` | 0.300 |"""


def test_carryover_drops_files_missing_from_current_graph(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)

    md = cga.render_god_nodes_md(
        _graph(), previous_md=_previous_md(PRUNE_COMMUNITIES, PRUNE_BRIDGE), carry_source=SOURCE_A
    )
    lines = md.splitlines()

    start = lines.index("| Community | Files | Cohesion | Sample |") + 2
    community_rows = lines[start : lines.index("", start)]
    # Files recounted over what is left; community 2 (no files left) drops out
    assert community_rows == [
        "| 0 | 12 | 0.42 | scripts/old_cluster.py |",
        "| 1 | 1 | 1.00 | a.py |",
        "| 3 | 4 | 0.10 | a.py, hub.py … |",
    ]
    assert "| 1 | `scripts/old_bridge.py` | 0.300 |" in lines  # bridge rows renumbered
    assert "gone.py" not in md
    assert all(PRUNED_NOTE in m for m in _markers(md))


def test_carryover_pruned_note_survives_repeated_carry(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    once = cga.render_god_nodes_md(
        _graph(), previous_md=_previous_md(PRUNE_COMMUNITIES, PRUNE_BRIDGE), carry_source=SOURCE_A
    )

    twice = cga.render_god_nodes_md(_graph(), previous_md=once, carry_source=SOURCE_B)

    assert twice == once
