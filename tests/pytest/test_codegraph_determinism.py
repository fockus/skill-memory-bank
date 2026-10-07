"""Determinism of the code-graph clusters and bridge files (I-219, Stage 11).

``detect_communities`` / ``file_betweenness`` feed git-tracked output
(``graph.json`` ``community`` fields, ``god-nodes.md`` Communities + Bridge
files). A fixed louvain/betweenness ``seed`` is not enough: the file graph must
not depend on ``PYTHONHASHSEED`` (set/dict iteration order), or the background
catchup rewrites those files with no code change.

The fixture is large on purpose: >500 files switches betweenness to sampling,
and louvain only diverges on graphs with real freedom — a 6-file toy graph is
deterministic even on the broken code.
"""

from __future__ import annotations

import json
import os
import random
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import codegraph_analytics as cga  # noqa: E402

CODEGRAPH_SCRIPT = REPO_ROOT / "scripts" / "mb-codegraph.py"
needs_nx = pytest.mark.skipif(not cga.HAS_NETWORKX, reason="networkx not installed")

_N_FILES = 600
_N_CLUSTERS = 30


def _synthetic_graph() -> dict:
    """600 files in 30 loosely coupled clusters (15% cross-cluster calls)."""
    rng = random.Random(7)
    nodes, edges = [], []
    files = [f"pkg{i % _N_CLUSTERS:02d}/mod{i:04d}.py" for i in range(_N_FILES)]
    for i, f in enumerate(files):
        nodes.append({"kind": "module", "name": f, "file": f, "line": 1})
        nodes.append({"kind": "function", "name": f"fn{i:04d}", "file": f, "line": 2})
    for i, f in enumerate(files):
        for _ in range(3):
            if rng.random() < 0.15:
                j = rng.randrange(_N_FILES)
            else:
                j = rng.choice(range(i % _N_CLUSTERS, _N_FILES, _N_CLUSTERS))
            edges.append({"src": f"{f}:fn{i:04d}", "dst": f"fn{j:04d}", "kind": "call"})
    return {"nodes": nodes, "edges": edges}


_PROBE = """
import json, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, sys.argv[2])
from memory_bank_skill import codegraph_analytics as cga
from test_codegraph_determinism import _synthetic_graph
g = _synthetic_graph()
print(json.dumps({"communities": cga.detect_communities(g),
                  "betweenness": cga.file_betweenness(g)}, sort_keys=True))
"""


def _probe_under_hashseeds(key: str) -> list:
    out = []
    for seed in ("0", "1", "2"):
        env = {**os.environ, "PYTHONHASHSEED": seed, "PYTHONDONTWRITEBYTECODE": "1"}
        proc = subprocess.run(
            [sys.executable, "-c", _PROBE, str(REPO_ROOT), str(Path(__file__).parent)],
            capture_output=True,
            text=True,
            env=env,
            check=True,
        )
        out.append(json.loads(proc.stdout)[key])
    return out


@needs_nx
def test_detect_communities_hashseed_independent_same_mapping():
    first, *rest = _probe_under_hashseeds("communities")
    assert all(r == first for r in rest), "community ids depend on PYTHONHASHSEED"


@needs_nx
def test_file_betweenness_hashseed_independent_same_scores():
    first, *rest = _probe_under_hashseeds("betweenness")
    assert all(r == first for r in rest), "bridge scores depend on PYTHONHASHSEED"


@needs_nx
def test_detect_communities_singletons_get_no_id():
    """A file with no file-level edge is not a cluster: no id, not counted."""
    graph = {
        "nodes": [
            {"kind": "module", "name": f, "file": f, "line": 1}
            for f in ("a1.py", "a2.py", "b1.py", "b2.py", "lonely.py")
        ]
        + [
            {"kind": "function", "name": fn, "file": f, "line": 2}
            for f, fn in (("a1.py", "fa1"), ("a2.py", "fa2"), ("b1.py", "fb1"), ("b2.py", "fb2"))
        ],
        "edges": [
            {"src": "a1.py:fa1", "dst": "fa2", "kind": "call"},
            {"src": "b1.py:fb1", "dst": "fb2", "kind": "call"},
        ],
    }
    mapping = cga.detect_communities(graph)
    assert "lonely.py" not in mapping
    assert sorted(set(mapping.values())) == [0, 1]


def _write_src(src: Path) -> None:
    """The synthetic graph as real Python sources, plus one isolated file."""
    graph = _synthetic_graph()
    calls: dict[str, list[str]] = {}
    for e in graph["edges"]:
        calls.setdefault(e["src"], []).append(e["dst"])
    for n in graph["nodes"]:
        if n["kind"] != "function":
            continue
        path = src / n["file"]
        path.parent.mkdir(parents=True, exist_ok=True)
        body = "".join(f"    {d}()\n" for d in calls.get(f"{n['file']}:{n['name']}", []))
        path.write_text(f"def {n['name']}():\n" + (body or "    pass\n"))
    (src / "lonely.py").write_text("def lonely():\n    pass\n")


@needs_nx
def test_apply_under_two_hashseeds_is_byte_identical(tmp_path):
    """Two builds of unchanged code → identical graph.json and god-nodes.md."""
    src = tmp_path / "src"
    _write_src(src)
    outputs = []
    for seed in ("0", "1"):
        mb = tmp_path / f"mb{seed}"
        (mb / "codebase").mkdir(parents=True)
        env = {
            **os.environ,
            "PYTHONHASHSEED": seed,
            "SOURCE_DATE_EPOCH": "1700000000",
            "MB_CODEGRAPH_REEXEC": "1",  # stay in this interpreter
        }
        subprocess.run(
            [sys.executable, str(CODEGRAPH_SCRIPT), "--apply", str(mb), str(src)],
            capture_output=True,
            env=env,
            check=True,
        )
        outputs.append(
            [(mb / "codebase" / name).read_bytes() for name in ("graph.json", "god-nodes.md")]
        )
    assert outputs[0] == outputs[1]


@needs_nx
def test_apply_isolated_file_has_no_community_field(tmp_path):
    src = tmp_path / "src"
    _write_src(src)
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    env = {**os.environ, "MB_CODEGRAPH_REEXEC": "1"}
    proc = subprocess.run(
        [sys.executable, str(CODEGRAPH_SCRIPT), "--apply", str(mb), str(src)],
        capture_output=True,
        text=True,
        env=env,
        check=True,
    )
    rows = [json.loads(line) for line in (mb / "codebase" / "graph.json").read_text().splitlines()]
    lonely = [r for r in rows if r.get("type") == "node" and r.get("file") == "lonely.py"]
    clustered = {r["community"] for r in rows if r.get("type") == "node" and "community" in r}
    assert lonely and all("community" not in r for r in lonely)
    assert f"communities={len(clustered)}" in proc.stdout.splitlines()
