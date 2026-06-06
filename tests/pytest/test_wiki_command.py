"""Tests for the /mb wiki orchestration layer — scripts/mb-wiki.py + command/agent docs.

The LLM steps run as host subagents (not in pytest); here we lock the deterministic
dispatch plan, the CLI verbs (packs / merge-edges), and the command + agent-prompt
registration.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

WIKI_SCRIPT = REPO_ROOT / "scripts" / "mb-wiki.py"


def _load_wiki():
    spec = importlib.util.spec_from_file_location("mb_wiki", WIKI_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _seed_graph(mb: Path):
    cb = mb / "codebase"
    cb.mkdir(parents=True)
    (cb / "graph.json").write_text(
        '{"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1}\n'
        '{"type": "edge", "kind": "call", "src": "a.py:f", "dst": "g"}\n',
        encoding="utf-8")
    return cb / "graph.json"


# ── plan_dispatch (pure) ─────────────────────────────────────────────

def test_plan_dispatch_counts_haiku_and_sonnet():
    mod = _load_wiki()
    packs = [
        {"community_id": 0, "files": ["a.py", "b.py"]},
        {"community_id": 1, "files": ["c.py"]},
    ]
    plan = mod.plan_dispatch(packs)
    assert plan["communities"] == 2
    assert len(plan["haiku_dispatches"]) == 2
    assert plan["sonnet_dispatches"] == 1
    assert plan["models"] == {"author": "haiku", "synthesizer": "sonnet"}


def test_plan_dispatch_empty_has_no_sonnet():
    mod = _load_wiki()
    plan = mod.plan_dispatch([])
    assert plan["communities"] == 0 and plan["sonnet_dispatches"] == 0


# ── CLI verbs ────────────────────────────────────────────────────────

def test_cli_plan_emits_valid_json(tmp_path: Path, capsys):
    mb = tmp_path / ".memory-bank"
    _seed_graph(mb)
    mod = _load_wiki()
    rc = mod.main(["mb-wiki.py", "plan", "--json", str(mb), str(tmp_path)])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert "communities" in out and "models" in out


def test_cli_packs_writes_packs_file(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    _seed_graph(mb)
    mod = _load_wiki()
    rc = mod.main(["mb-wiki.py", "packs", str(mb), str(tmp_path)])
    assert rc == 0
    assert (mb / "codebase" / ".wiki-packs.json").is_file()


def test_cli_merge_edges_adds_semantic_edge(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    graph = _seed_graph(mb)
    edges_file = tmp_path / "edges.json"
    edges_file.write_text(
        json.dumps([{"src": "a.py", "dst": "z.py", "confidence": 0.8, "rationale": "x"}]),
        encoding="utf-8")
    mod = _load_wiki()
    rc = mod.main(["mb-wiki.py", "merge-edges", "--edges", str(edges_file), str(mb)])
    assert rc == 0
    assert '"kind": "semantic"' in graph.read_text(encoding="utf-8")


def test_cli_missing_graph_returns_exit_3(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_wiki()
    rc = mod.main(["mb-wiki.py", "plan", str(mb), str(tmp_path)])
    assert rc == 3


# ── registration: command + agent prompts ───────────────────────────

def test_wiki_command_doc_exists_with_required_sections():
    # /mb wiki is a subcommand documented in commands/mb.md (like graph/search/tags),
    # not a standalone top-level command file.
    doc = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "### wiki" in doc
    assert "Haiku" in doc and "Sonnet" in doc
    assert "--dry-run" in doc


def test_wiki_agent_prompts_exist_and_declare_tiers():
    author = (REPO_ROOT / "agents" / "mb-wiki-author.md").read_text(encoding="utf-8")
    synth = (REPO_ROOT / "agents" / "mb-wiki-synthesizer.md").read_text(encoding="utf-8")
    assert "haiku" in author.lower()
    assert "sonnet" in synth.lower()
    assert "JSON" in synth  # strict-JSON contract for the merge step


def test_mb_router_lists_wiki_subcommand():
    router = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "`wiki" in router or "| `wiki`" in router
