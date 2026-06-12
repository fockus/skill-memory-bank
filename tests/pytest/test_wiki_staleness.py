"""Tests for wiki staleness — incremental rebuild (REQ-027, Scenario 10).

`/mb wiki plan` must rebuild only the articles of communities whose member files
changed in the graph since the last build, and skip unchanged communities. The
staleness check is deterministic ($0 — no LLM): per-community graph hashes are
recorded in ``wiki/index.md`` and re-derived from the current graph on each plan.

Covered behaviours:
- ``community_hash`` is content-addressed (changes iff a member file's graph
  nodes/edges change) and order-independent.
- ``write_index`` records one hash line per community; ``parse_index_hashes``
  round-trips them.
- ``plan`` schedules ONLY changed communities; unchanged → ``skipped (fresh)``.
- ``--force`` schedules all; missing/legacy cache → full rebuild (no crash).
- Hash recording is idempotent (two index writes → byte-identical file).
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import wiki_store as wstore  # noqa: E402

WIKI_SCRIPT = REPO_ROOT / "scripts" / "mb-wiki.py"


def _load_wiki():
    spec = importlib.util.spec_from_file_location("mb_wiki", WIKI_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ── community_hash (pure, content-addressed) ─────────────────────────


def test_community_hash_changes_when_member_node_changes():
    nodes = [{"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1}]
    edges: list[dict] = []
    before = wstore.community_hash(nodes, edges, ["a.py"])
    nodes2 = [{"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 99}]
    after = wstore.community_hash(nodes2, edges, ["a.py"])
    assert before != after


def test_community_hash_changes_when_member_edge_changes():
    nodes = [{"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1}]
    edges_before = [{"type": "edge", "kind": "call", "src": "a.py:f", "dst": "g"}]
    edges_after = [{"type": "edge", "kind": "call", "src": "a.py:f", "dst": "h"}]
    h1 = wstore.community_hash(nodes, edges_before, ["a.py"])
    h2 = wstore.community_hash(nodes, edges_after, ["a.py"])
    assert h1 != h2


def test_community_hash_stable_when_unrelated_file_changes():
    nodes = [
        {"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1},
        {"type": "node", "kind": "function", "name": "z", "file": "b.py", "line": 1},
    ]
    edges: list[dict] = []
    h_a = wstore.community_hash(nodes, edges, ["a.py"])
    nodes2 = [
        {"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1},
        {
            "type": "node",
            "kind": "function",
            "name": "z",
            "file": "b.py",
            "line": 50,
        },  # b.py changed
    ]
    h_a2 = wstore.community_hash(nodes2, edges, ["a.py"])
    assert h_a == h_a2  # a.py's hash unaffected by b.py churn


def test_community_hash_order_independent():
    n1 = {"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1}
    n2 = {"type": "node", "kind": "function", "name": "g", "file": "a.py", "line": 2}
    h1 = wstore.community_hash([n1, n2], [], ["a.py"])
    h2 = wstore.community_hash([n2, n1], [], ["a.py"])
    assert h1 == h2


def test_community_hash_changes_when_edge_targets_member_bare_symbol():
    """An edge whose dst is a BARE symbol defined in a member file is part of the
    community hash — changing that edge must change the hash (relationship change)."""
    nodes = [
        {"type": "node", "kind": "function", "name": "target", "file": "a.py", "line": 1},
        {"type": "node", "kind": "function", "name": "caller", "file": "other.py", "line": 1},
    ]
    # dst="target" is a bare symbol defined in member file a.py.
    edges_before = [{"type": "edge", "kind": "call", "src": "other.py:caller", "dst": "target"}]
    edges_after = [
        {"type": "edge", "kind": "call", "src": "other.py:caller", "dst": "target", "line": 9}
    ]
    h1 = wstore.community_hash(nodes, edges_before, ["a.py"])
    h2 = wstore.community_hash(nodes, edges_after, ["a.py"])
    assert h1 != h2


def test_community_hash_changes_when_edge_targets_member_dotted_symbol():
    """Dotted dst (module.symbol) resolving to a member file's symbol is included."""
    nodes = [
        {
            "type": "node",
            "kind": "function",
            "name": "atomic_write",
            "file": "pkg/io.py",
            "line": 1,
        },
        {"type": "node", "kind": "function", "name": "caller", "file": "other.py", "line": 1},
    ]
    edges_before = [
        {"type": "edge", "kind": "call", "src": "other.py:caller", "dst": "pkg.io.atomic_write"}
    ]
    edges_after = [
        {
            "type": "edge",
            "kind": "call",
            "src": "other.py:caller",
            "dst": "pkg.io.atomic_write",
            "line": 9,
        }
    ]
    h1 = wstore.community_hash(nodes, edges_before, ["pkg/io.py"])
    h2 = wstore.community_hash(nodes, edges_after, ["pkg/io.py"])
    assert h1 != h2


def test_community_hash_ignores_edge_to_nonmember_symbol():
    """An edge targeting a symbol defined OUTSIDE the member set does not affect it."""
    nodes = [
        {"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1},
        {"type": "node", "kind": "function", "name": "elsewhere", "file": "z.py", "line": 1},
        {"type": "node", "kind": "function", "name": "caller", "file": "z.py", "line": 2},
    ]
    edges_before = [{"type": "edge", "kind": "call", "src": "z.py:caller", "dst": "elsewhere"}]
    edges_after = [
        {"type": "edge", "kind": "call", "src": "z.py:caller", "dst": "elsewhere", "line": 5}
    ]
    h1 = wstore.community_hash(nodes, edges_before, ["a.py"])
    h2 = wstore.community_hash(nodes, edges_after, ["a.py"])
    assert h1 == h2  # the edge touches only z.py symbols → a.py's hash is unaffected


# ── homonyms / determinism (multi-map symbol→files, intersection membership) ──


def test_community_hash_homonym_edge_marks_member_stale_regardless_of_node_order():
    """A bare ``dst`` naming a symbol defined in MULTIPLE files (a homonym) belongs to
    EVERY defining file's community. When one of those files is a member, the edge is
    part of the member community's hash — so changing the edge changes the hash. This
    must hold no matter the order graph records appear in (no last-wins resolution).
    """
    # "dup" is defined in both a.py (member) and b.py (non-member).
    dup_a = {"type": "node", "kind": "function", "name": "dup", "file": "a.py", "line": 1}
    dup_b = {"type": "node", "kind": "function", "name": "dup", "file": "b.py", "line": 1}
    caller = {"type": "node", "kind": "function", "name": "caller", "file": "other.py", "line": 1}
    edge_before = {"type": "edge", "kind": "call", "src": "other.py:caller", "dst": "dup"}
    edge_after = {"type": "edge", "kind": "call", "src": "other.py:caller", "dst": "dup", "line": 9}

    for nodes in ([dup_a, dup_b, caller], [dup_b, dup_a, caller]):  # both record orders
        h1 = wstore.community_hash(nodes, [edge_before], ["a.py"])
        h2 = wstore.community_hash(nodes, [edge_after], ["a.py"])
        assert h1 != h2, (
            f"member community must go stale for node order {[n['file'] for n in nodes]}"
        )


def test_community_hash_homonym_order_independent():
    """Same logical graph with a homonym, reversed node order → identical hash."""
    dup_a = {"type": "node", "kind": "function", "name": "dup", "file": "a.py", "line": 1}
    dup_b = {"type": "node", "kind": "function", "name": "dup", "file": "b.py", "line": 1}
    caller = {"type": "node", "kind": "function", "name": "caller", "file": "other.py", "line": 1}
    edge = {"type": "edge", "kind": "call", "src": "other.py:caller", "dst": "dup"}
    forward = wstore.community_hash([dup_a, dup_b, caller], [edge], ["a.py"])
    reversed_ = wstore.community_hash([caller, dup_b, dup_a], [edge], ["a.py"])
    assert forward == reversed_


def test_community_hash_unrelated_homonym_in_nonmember_file_does_not_flip_member():
    """Intersection semantics, asserted honestly: a member community's hash is derived
    from records whose endpoint candidate-files intersect the member set. Introducing
    an extra homonymous definition in a NON-member file does not add the member file to
    any *new* edge's intersection, so the member community hash is unchanged. (The new
    node itself touches only non-member files.)
    """
    base_nodes = [
        {"type": "node", "kind": "function", "name": "dup", "file": "a.py", "line": 1},
        {"type": "node", "kind": "function", "name": "caller", "file": "other.py", "line": 1},
    ]
    edge = {"type": "edge", "kind": "call", "src": "other.py:caller", "dst": "dup"}
    before = wstore.community_hash(base_nodes, [edge], ["a.py"])
    # Add an unrelated homonym "dup" defined in a non-member file c.py.
    extra = {"type": "node", "kind": "function", "name": "dup", "file": "c.py", "line": 1}
    after = wstore.community_hash([*base_nodes, extra], [edge], ["a.py"])
    assert before == after  # member set {a.py} ∩ candidate files of "dup" still includes a.py


# ── index hash recording + parse round-trip ─────────────────────────


def test_write_index_records_per_community_hash(tmp_path: Path):
    wiki = tmp_path / "wiki"
    packs = [{"community_id": 0, "files": ["a.py"], "key_symbols": [], "excerpts": {}}]
    idx = wstore.write_index(wiki, packs, hashes={0: "deadbeef"})
    text = idx.read_text(encoding="utf-8")
    assert "deadbeef" in text
    assert wstore.parse_index_hashes(text) == {0: "deadbeef"}


def test_write_index_hash_recording_is_idempotent(tmp_path: Path):
    wiki = tmp_path / "wiki"
    packs = [{"community_id": 0, "files": ["a.py"], "key_symbols": [], "excerpts": {}}]
    idx = wstore.write_index(wiki, packs, hashes={0: "cafe1234"})
    first = idx.read_bytes()
    idx2 = wstore.write_index(wiki, packs, hashes={0: "cafe1234"})
    assert idx2.read_bytes() == first  # two runs → byte-identical index.md


def test_parse_index_hashes_legacy_index_returns_empty():
    legacy = "# Codebase wiki\n\n- [Community 0](community-0.md) — 1 files: a.py\n"
    assert wstore.parse_index_hashes(legacy) == {}


def test_parse_index_hashes_missing_file_returns_empty(tmp_path: Path):
    assert wstore.parse_index_hashes(tmp_path / "nope.md") == {}


# ── plan staleness scheduling ────────────────────────────────────────


def _seed_two_communities(mb: Path) -> Path:
    """Two clusters with no cross-edges → Louvain yields two communities.

    Cluster X: a.py↔a2.py (mutual calls). Cluster Y: b.py↔b2.py.
    """
    cb = mb / "codebase"
    cb.mkdir(parents=True)
    graph = cb / "graph.json"
    graph.write_text(
        '{"type": "node", "kind": "function", "name": "fa", "file": "a.py", "line": 1}\n'
        '{"type": "node", "kind": "function", "name": "fa2", "file": "a2.py", "line": 1}\n'
        '{"type": "node", "kind": "function", "name": "fb", "file": "b.py", "line": 1}\n'
        '{"type": "node", "kind": "function", "name": "fb2", "file": "b2.py", "line": 1}\n'
        '{"type": "edge", "kind": "call", "src": "a.py:fa", "dst": "fa2"}\n'
        '{"type": "edge", "kind": "call", "src": "a2.py:fa2", "dst": "fa"}\n'
        '{"type": "edge", "kind": "call", "src": "b.py:fb", "dst": "fb2"}\n'
        '{"type": "edge", "kind": "call", "src": "b2.py:fb2", "dst": "fb"}\n',
        encoding="utf-8",
    )
    return graph


def _community_files(mod, mb: Path, src_root: Path) -> dict[int, list[str]]:
    _, packs, _ = mod._prep(str(mb), str(src_root))
    return {p["community_id"]: p["files"] for p in packs}


def test_plan_no_cache_schedules_all(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    _seed_two_communities(mb)
    mod = _load_wiki()
    rc = mod.main(["mb-wiki.py", "plan", "--json", str(mb), str(tmp_path)])
    assert rc == 0
    # No index.md cache → every community scheduled, none skipped.
    plan = mod.plan_staleness(str(mb), str(tmp_path))
    assert len(plan["scheduled"]) >= 2
    assert plan["skipped"] == []


def test_plan_force_schedules_all_even_with_cache(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    _seed_two_communities(mb)
    mod = _load_wiki()
    # Build a fresh cache that matches the current graph exactly.
    cur = mod.current_hashes(str(mb), str(tmp_path))
    cb = mb / "codebase"
    cf = _community_files(mod, mb, tmp_path)
    packs = [
        {"community_id": c, "files": cf[c], "key_symbols": [], "excerpts": {}} for c in sorted(cf)
    ]
    wstore.write_index(cb / "wiki", packs, hashes=cur)
    plan = mod.plan_staleness(str(mb), str(tmp_path), force=True)
    assert sorted(plan["scheduled"]) == sorted(cf)
    assert plan["skipped"] == []


def test_plan_skips_unchanged_schedules_only_changed(tmp_path: Path):
    """Scenario 10: only one community's member file changed → exactly 1 rewrite."""
    mb = tmp_path / ".memory-bank"
    graph = _seed_two_communities(mb)
    mod = _load_wiki()

    cf = _community_files(mod, mb, tmp_path)
    assert len(cf) == 2, f"fixture must yield 2 communities, got {cf}"
    # Identify which community owns a.py and which owns b.py.
    comm_a = next(c for c, files in cf.items() if "a.py" in files)
    comm_b = next(c for c, files in cf.items() if "b.py" in files)
    assert comm_a != comm_b

    # 1) Record the cache matching the current graph (all fresh).
    cur = mod.current_hashes(str(mb), str(tmp_path))
    packs = [
        {"community_id": c, "files": cf[c], "key_symbols": [], "excerpts": {}} for c in sorted(cf)
    ]
    wstore.write_index(mb / "codebase" / "wiki", packs, hashes=cur)

    # 2) Mutate ONLY community-b's member file (b.py node line bump).
    text = graph.read_text(encoding="utf-8")
    text = text.replace(
        '"name": "fb", "file": "b.py", "line": 1', '"name": "fb", "file": "b.py", "line": 42'
    )
    graph.write_text(text, encoding="utf-8")

    # 3) Re-plan: only community_b scheduled, community_a skipped (fresh).
    plan = mod.plan_staleness(str(mb), str(tmp_path))
    assert plan["scheduled"] == [comm_b]
    assert plan["skipped"] == [comm_a]


def test_plan_legacy_index_without_hashes_full_rebuild(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    _seed_two_communities(mb)
    mod = _load_wiki()
    wiki = mb / "codebase" / "wiki"
    wiki.mkdir(parents=True)
    # Legacy index.md: lists communities but records NO hash lines.
    (wiki / "index.md").write_text(
        "# Codebase wiki\n\n- [Community 0](community-0.md) — 2 files: a.py, a2.py\n",
        encoding="utf-8",
    )
    plan = mod.plan_staleness(str(mb), str(tmp_path))  # must not crash
    cf = _community_files(mod, mb, tmp_path)
    assert sorted(plan["scheduled"]) == sorted(cf)
    assert plan["skipped"] == []


def test_index_then_plan_skips_all_fresh(tmp_path: Path, capsys):
    """End-to-end via CLI verbs: `packs` → `index` records hashes → `plan` skips all."""
    mb = tmp_path / ".memory-bank"
    _seed_two_communities(mb)
    mod = _load_wiki()
    assert mod.main(["mb-wiki.py", "packs", str(mb), str(tmp_path)]) == 0
    assert mod.main(["mb-wiki.py", "index", str(mb)]) == 0
    capsys.readouterr()  # drain
    rc = mod.main(["mb-wiki.py", "plan", "--json", str(mb), str(tmp_path)])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert out["scheduled"] == []  # everything fresh after a matching index write
    assert out["cache_present"] is True


def test_index_hash_recording_idempotent_via_cli(tmp_path: Path, capsys):
    mb = tmp_path / ".memory-bank"
    _seed_two_communities(mb)
    mod = _load_wiki()
    mod.main(["mb-wiki.py", "packs", str(mb), str(tmp_path)])
    index_path = mb / "codebase" / "wiki" / "index.md"
    mod.main(["mb-wiki.py", "index", str(mb)])
    first = index_path.read_bytes()
    mod.main(["mb-wiki.py", "index", str(mb)])  # re-run, no graph change
    assert index_path.read_bytes() == first  # idempotent hash recording


def test_cli_plan_force_flag_accepted(tmp_path: Path, capsys):
    mb = tmp_path / ".memory-bank"
    _seed_two_communities(mb)
    mod = _load_wiki()
    rc = mod.main(["mb-wiki.py", "plan", "--force", "--json", str(mb), str(tmp_path)])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0
    # --force surfaces a full rebuild in the JSON plan (nothing skipped).
    assert out["scheduled"] and out["skipped"] == []


# ── dispatch plan honours staleness (Scenario 10: schedule ONLY changed) ─────


def test_plan_dispatches_empty_when_cache_fully_fresh(tmp_path: Path, capsys):
    """Fully-fresh cache → NO haiku dispatches and sonnet_dispatches == 0.

    The dispatch plan, not just the staleness split, must reflect "nothing to do".
    """
    mb = tmp_path / ".memory-bank"
    _seed_two_communities(mb)
    mod = _load_wiki()
    # Record a cache that matches the current graph exactly (all fresh).
    assert mod.main(["mb-wiki.py", "packs", str(mb), str(tmp_path)]) == 0
    assert mod.main(["mb-wiki.py", "index", str(mb)]) == 0
    capsys.readouterr()  # drain
    rc = mod.main(["mb-wiki.py", "plan", "--json", str(mb), str(tmp_path)])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert out["scheduled"] == []
    assert out["haiku_dispatches"] == []
    assert out["sonnet_dispatches"] == 0


def test_plan_dispatches_only_changed_community(tmp_path: Path, capsys):
    """Partial change → haiku_dispatches contains ONLY the changed community id;
    sonnet runs (1) because there is cross-cutting work to synthesise."""
    mb = tmp_path / ".memory-bank"
    graph = _seed_two_communities(mb)
    mod = _load_wiki()

    cf = _community_files(mod, mb, tmp_path)
    comm_a = next(c for c, files in cf.items() if "a.py" in files)
    comm_b = next(c for c, files in cf.items() if "b.py" in files)

    # Record fresh cache, then mutate ONLY community-b's member file.
    cur = mod.current_hashes(str(mb), str(tmp_path))
    packs = [
        {"community_id": c, "files": cf[c], "key_symbols": [], "excerpts": {}} for c in sorted(cf)
    ]
    wstore.write_index(mb / "codebase" / "wiki", packs, hashes=cur)
    text = graph.read_text(encoding="utf-8")
    text = text.replace(
        '"name": "fb", "file": "b.py", "line": 1', '"name": "fb", "file": "b.py", "line": 42'
    )
    graph.write_text(text, encoding="utf-8")

    capsys.readouterr()  # drain
    rc = mod.main(["mb-wiki.py", "plan", "--json", str(mb), str(tmp_path)])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert out["scheduled"] == [comm_b]
    dispatched_ids = [d["community_id"] for d in out["haiku_dispatches"]]
    assert dispatched_ids == [comm_b]
    assert comm_a not in dispatched_ids
    assert out["sonnet_dispatches"] == 1


def test_plan_force_dispatches_all(tmp_path: Path, capsys):
    """--force ignores the fresh cache → every community is dispatched again."""
    mb = tmp_path / ".memory-bank"
    _seed_two_communities(mb)
    mod = _load_wiki()
    assert mod.main(["mb-wiki.py", "packs", str(mb), str(tmp_path)]) == 0
    assert mod.main(["mb-wiki.py", "index", str(mb)]) == 0
    cf = _community_files(mod, mb, tmp_path)
    capsys.readouterr()  # drain
    rc = mod.main(["mb-wiki.py", "plan", "--force", "--json", str(mb), str(tmp_path)])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0
    dispatched_ids = sorted(d["community_id"] for d in out["haiku_dispatches"])
    assert dispatched_ids == sorted(cf)
    assert out["sonnet_dispatches"] == 1
