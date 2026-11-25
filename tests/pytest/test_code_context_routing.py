"""Retrieval routing contracts for mb-code-context.py and its evidence API."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"


def cli(root: Path, question: str, *args: str) -> dict:
    run = subprocess.run(
        [sys.executable, str(SCRIPTS / "mb-code-context.py"), "--project-root", str(root),
         "--mb-path", str(root / ".memory-bank"), "--query", question, "--json", *args],
        text=True, capture_output=True,
    )
    assert run.returncode == 0, run.stderr
    return json.loads(run.stdout)


@pytest.mark.parametrize("mode", ["semantic", "auto"])
@pytest.mark.parametrize("source_only", [False, True])
def test_project_search_uses_paraphrase_and_ranked_chunk_budget(tmp_path, monkeypatch, mode, source_only):
    monkeypatch.syspath_prepend(str(SCRIPTS))
    import mb_project_rag
    from mb_code_context_core import build_evidence

    original = "Где вычисляется налог?"
    english = "calculate sales tax"
    (tmp_path / "decoy.py").write_text("# sales tax mentioned in passing")
    winner = {"file": "Store/Tax.py", "line": 70, "end_line": 91}
    chunks = [{"file": "tax.spec.ts"}] * 38 + [winner, {**winner, "line": 1}]
    chunks += [{"file": f"lib/{i}.py"} for i in range(10)]

    def search(root, bank, query, k):
        assert query == english and k == (50 if source_only else 10)
        return chunks[:k]

    monkeypatch.setattr(mb_project_rag, "candidates", search)
    pack = build_evidence(query=original, search_query=english, source_only=source_only,
                          project_root=tmp_path, mb_path=tmp_path / ".memory-bank", mode=mode,
                          semantic_provider="none", semantic_candidates_path=None)

    expected = [winner, *chunks[40:49]] if source_only else chunks[:10]
    assert pack["semantic_candidates"] == expected
    assert pack["candidate_files"] == list(dict.fromkeys(hit["file"] for hit in expected))
    assert pack["recommended_next_reads"] == pack["candidate_files"]
    assert pack["query"] == original


def test_blank_search_query_uses_original_at_provider(tmp_path, monkeypatch):
    monkeypatch.syspath_prepend(str(SCRIPTS))
    import mb_project_rag
    from mb_code_context_core import build_evidence

    original = "Какие тесты проверяют TTL?"
    hit = {"file": "ttl_test.go", "line": 12, "end_line": 19}
    monkeypatch.setattr(mb_project_rag, "candidates",
                        lambda root, bank, query, k: [hit] if query == original else [])
    pack = build_evidence(query=original, search_query="  ", project_root=tmp_path,
                          mb_path=tmp_path / ".memory-bank", mode="semantic",
                          semantic_provider="none", semantic_candidates_path=None)
    assert pack["semantic_candidates"] == [hit]
    assert pack["recommended_next_reads"] == [hit["file"]]


def test_cli_source_only_keeps_original_graph_evidence_and_filters_injected_hits(tmp_path):
    graph = tmp_path / ".memory-bank/codebase/graph.json"
    graph.parent.mkdir(parents=True)
    records = [
        {"type": "node", "kind": "function", "name": "charge_card", "file": "billing.py"},
        {"type": "node", "kind": "function", "name": "test_charge_card", "file": "test/billing.py"},
        {"type": "edge", "kind": "call", "src": "test/billing.py:test_charge_card", "dst": "charge_card"},
        {"type": "edge", "kind": "tests", "src": "tests/test_billing.py", "dst": "billing.py"},
    ]
    graph.write_text("\n".join(map(json.dumps, records)) + "\n")
    candidates = tmp_path / "hits.json"
    hit = {"file": "latest.py", "line": 31, "end_line": 46}
    candidates.write_text(json.dumps({"candidates": [
        {"file": "__tests__/billing.js"}, hit, {**hit, "line": 1},
    ]}))
    question = "Где вызывается charge_card?"
    pack = cli(tmp_path, question, "--search-query", "billing payments", "--source-only",
               "--semantic-candidates", str(candidates))

    assert pack["query"] == question
    assert pack["semantic_candidates"] == [hit]
    assert pack["candidate_files"] == ["billing.py", "latest.py"]
    assert pack["recommended_next_reads"] == pack["candidate_files"]
    assert "tests/test_billing.py" in pack["test_files"]
    assert records[2] in pack["graph_facts"]


@pytest.mark.parametrize("provider_args", [[], ["--semantic-provider", "unavailable"]])
def test_cli_without_rag_finds_source_after_test_matches_using_english(tmp_path, monkeypatch, provider_args):
    state = tmp_path / "state"
    monkeypatch.setenv("XDG_STATE_HOME", str(state))
    for name in [*(f"{n}.test.ts" for n in range(12)), "worker.ts"]:
        (tmp_path / name).write_text("schedule();")
    pack = cli(tmp_path, "Где назначаются задания?", "--search-query", "schedule",
               "--source-only", *provider_args)

    assert pack["candidate_files"] == pack["recommended_next_reads"] == ["worker.ts"]
    assert not state.exists()
    if not provider_args:
        assert not any("rag" in warning.lower() for warning in pack["warnings"])


def test_graph_mode_keeps_original_literal_without_using_semantic_provider(tmp_path, monkeypatch):
    monkeypatch.syspath_prepend(str(SCRIPTS))
    import mb_project_rag
    from mb_code_context_core import build_evidence

    monkeypatch.setattr(mb_project_rag, "candidates", lambda *a, **kw: pytest.fail("graph only"))
    (tmp_path / "Ledger.py").touch()
    pack = build_evidence(query="Где используется Ledger.py?", search_query="billing balances",
                          source_only=True, project_root=tmp_path, mb_path=tmp_path / ".memory-bank",
                          mode="graph", semantic_candidates_path=None, semantic_provider="none")

    assert pack["candidate_files"] == ["Ledger.py"]


def test_cli_from_git_subdirectory_uses_repository_paths(tmp_path):
    subprocess.run(["git", "init", "-q", tmp_path], check=True)
    nested = tmp_path / "src"
    nested.mkdir()
    (tmp_path / "recovery.py").write_text("def restore_archive(): pass\n")
    question = "Где найти restore_archive?"
    result = subprocess.run(
        [sys.executable, str(SCRIPTS / "mb-code-context.py"), "--query", question,
         "--search-query", "restore_archive", "--source-only", "--json"],
        cwd=nested, capture_output=True, text=True, check=True,
    )
    assert json.loads(result.stdout)["recommended_next_reads"] == ["recovery.py"]
