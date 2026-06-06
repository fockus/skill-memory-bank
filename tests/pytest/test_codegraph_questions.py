"""Tests for memory_bank_skill/codegraph_questions.py — deterministic suggested questions.

Generated purely from graph structure + analytics (god-nodes / bridges / communities /
co-change). No LLM, no IO. Each question is a dict {kind, text, evidence, command?}.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import codegraph_questions as cgq  # noqa: E402


def _graph_with_hub():
    """A graph where `process` is the clear high-degree symbol."""
    nodes = [
        {"kind": "module", "name": "a.py", "file": "a.py", "line": 1},
        {"kind": "function", "name": "process", "file": "a.py", "line": 5},
        {"kind": "module", "name": "b.py", "file": "b.py", "line": 1},
        {"kind": "function", "name": "caller", "file": "b.py", "line": 3},
        {"kind": "module", "name": "c.py", "file": "c.py", "line": 1},
    ]
    edges = [
        {"src": "b.py:caller", "dst": "process", "kind": "call"},
        {"src": "c.py", "dst": "process", "kind": "call"},
        {"src": "a.py", "dst": "process", "kind": "call"},
    ]
    return {"nodes": nodes, "edges": edges}


def test_suggests_god_node_question():
    qs = cgq.suggest_questions(_graph_with_hub())
    god = [q for q in qs if q["kind"] == "god_node"]
    assert god, "expected at least one god-node question"
    assert "process" in god[0]["text"]
    assert "impact" in god[0].get("command", "")


def test_suggests_bridge_question_when_betweenness_given():
    qs = cgq.suggest_questions(_graph_with_hub(), betweenness={"a.py": 0.9, "b.py": 0.0})
    bridges = [q for q in qs if q["kind"] == "bridge"]
    assert bridges and "a.py" in bridges[0]["text"]


def test_suggests_community_question_when_communities_given():
    communities = {"a.py": 0, "b.py": 0, "c.py": 1}
    qs = cgq.suggest_questions(_graph_with_hub(), communities=communities)
    comm = [q for q in qs if q["kind"] == "community"]
    assert comm, "expected a community question for the 2-file cluster"


def test_suggests_co_change_question():
    g = _graph_with_hub()
    g["edges"].append({"src": "a.py", "dst": "b.py", "kind": "co_change", "weight": 4})
    qs = cgq.suggest_questions(g)
    cc = [q for q in qs if q["kind"] == "co_change"]
    assert cc and "a.py" in cc[0]["text"] and "b.py" in cc[0]["text"]


def test_empty_graph_yields_no_questions():
    assert cgq.suggest_questions({"nodes": [], "edges": []}) == []


def test_no_networkx_signal_only_godnode_and_cochange():
    g = _graph_with_hub()
    g["edges"].append({"src": "a.py", "dst": "b.py", "kind": "co_change", "weight": 2})
    qs = cgq.suggest_questions(g, communities=None, betweenness=None)
    kinds = {q["kind"] for q in qs}
    assert "bridge" not in kinds and "community" not in kinds
    assert "god_node" in kinds and "co_change" in kinds


def test_top_n_cap_is_respected():
    qs = cgq.suggest_questions(_graph_with_hub(), top_n=2)
    assert len(qs) <= 2


def test_deterministic_across_calls():
    g = _graph_with_hub()
    assert cgq.suggest_questions(g) == cgq.suggest_questions(g)


def test_render_questions_md_table_shape():
    qs = cgq.suggest_questions(_graph_with_hub())
    md = cgq.render_questions_md(qs)
    assert md.startswith("## Suggested questions")
    assert "1." in md


def test_render_questions_md_empty_is_graceful():
    md = cgq.render_questions_md([])
    assert "## Suggested questions" in md
    assert "Not enough graph signal" in md


# ── wiring: scripts/mb-codegraph.py run(..., questions=) ─────────────

import importlib.util  # noqa: E402


def _load_script():
    spec = importlib.util.spec_from_file_location(
        "mb_codegraph", REPO_ROOT / "scripts" / "mb-codegraph.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _make_src(tmp_path: Path) -> Path:
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.py").write_text(
        "class Base:\n    def greet(self):\n        return 1\n\n"
        "class Child(Base):\n    def run(self):\n        return self.greet()\n",
        encoding="utf-8")
    (src / "b.py").write_text("from a import Child\n\ndef main():\n    return Child().run()\n",
                              encoding="utf-8")
    return src


def test_run_questions_off_godnodes_has_no_section(tmp_path: Path):
    src = _make_src(tmp_path)
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(src), mode="apply", questions=False)
    god = (mb / "codebase" / "god-nodes.md").read_text(encoding="utf-8")
    assert "## Suggested questions" not in god


def test_run_questions_on_appends_section(tmp_path: Path):
    src = _make_src(tmp_path)
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_script()
    summary = mod.run(mb_path=str(mb), src_root=str(src), mode="apply", questions=True)
    god = (mb / "codebase" / "god-nodes.md").read_text(encoding="utf-8")
    assert "## Suggested questions" in god
    assert "questions" in summary
