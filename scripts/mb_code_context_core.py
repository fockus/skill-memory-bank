"""Core GraphRAG-lite evidence pack builder."""

from __future__ import annotations

import fnmatch
import json
import re
from pathlib import Path
from typing import Any

import mb_graph_query_core as graph_query

MAX_FILES = 10
MAX_GRAPH_FACTS = 20
TEXT_EXTENSIONS = {".py", ".sh", ".md", ".txt", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".java"}
PROTECTED_NAMES = {".env", ".envrc"}
PROTECTED_PATTERNS = (".env.*", "*.env", "*secret*", "*credentials*")

JsonObj = dict[str, Any]


def is_protected(path: Path) -> bool:
    return any(
        part in PROTECTED_NAMES
        or any(fnmatch.fnmatch(part.lower(), pattern) for pattern in PROTECTED_PATTERNS)
        for part in path.parts
    )


def safe_rel(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def tokenize(query: str) -> list[str]:
    tokens = [token.lower() for token in re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", query)]
    return [
        token
        for token in tokens
        if token not in {"where", "logic", "find", "similar", "the", "for"}
    ]


def read_semantic_candidates(
    path: Path | None, provider: str, warnings: list[str]
) -> list[JsonObj]:
    if provider == "unavailable":
        warnings.append("semantic provider unavailable; using graph/text fallback")
        return []
    if path is None:
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        warnings.append(f"semantic candidates unavailable: {exc}")
        return []
    candidates = payload.get("candidates", [])
    if not isinstance(candidates, list):
        warnings.append("semantic candidates unavailable: candidates must be a list")
        return []
    return [
        candidate
        for candidate in candidates
        if isinstance(candidate, dict) and isinstance(candidate.get("file"), str)
    ]


def text_search(project_root: Path, query: str) -> list[str]:
    tokens = tokenize(query)
    if not tokens:
        return []
    matches: list[str] = []
    for path in sorted(project_root.rglob("*")):
        if not path.is_file() or is_protected(path) or ".git" in path.parts:
            continue
        if path.suffix not in TEXT_EXTENSIONS:
            continue
        rel = safe_rel(path, project_root)
        haystacks = [rel.lower()]
        try:
            haystacks.append(path.read_text(encoding="utf-8", errors="ignore").lower())
        except OSError:
            continue
        if any(token in haystack for token in tokens for haystack in haystacks):
            matches.append(rel)
        if len(matches) >= MAX_FILES:
            break
    return matches


def load_graph(graph_path: Path, warnings: list[str]) -> tuple[list[JsonObj], list[JsonObj]]:
    try:
        return graph_query.load_graph(graph_path)
    except FileNotFoundError:
        warnings.append("missing graph: run /mb graph --apply to enable structural expansion")
    except ValueError as exc:
        warnings.append(f"stale graph or invalid graph: {exc}")
    return [], []


def add_unique(items: list[str], value: str) -> None:
    if value and value not in items and len(items) < MAX_FILES:
        items.append(value)


def seed_candidates(
    *,
    project_root: Path,
    query: str,
    semantic_candidates: list[JsonObj],
    text_candidates: list[str],
    nodes: list[JsonObj],
) -> list[str]:
    files: list[str] = []
    for candidate in semantic_candidates:
        add_unique(files, str(candidate.get("file", "")))
    for file_name in text_candidates:
        add_unique(files, file_name)

    tokens = set(tokenize(query))
    for node in nodes:
        name = str(node.get("name", ""))
        file_name = str(node.get("file", ""))
        if any(token in name.lower() for token in tokens):
            add_unique(files, file_name)
    return [file_name for file_name in files if not is_protected(project_root / file_name)]


def graph_expand(
    nodes: list[JsonObj], edges: list[JsonObj], candidate_files: list[str], query: str
) -> tuple[list[JsonObj], list[str]]:
    facts: list[JsonObj] = []
    tests: set[str] = set()
    seen: set[tuple[str, str, str]] = set()
    selectors: list[tuple[str | None, str | None]] = [(None, name) for name in candidate_files]
    selectors.extend(
        (token, None) for token in tokenize(query) if "_" in token or token.isidentifier()
    )

    for symbol, file_name in selectors:
        matches, target_names, target_files = graph_query.resolve_target(
            nodes, symbol=symbol, file_name=file_name
        )
        if not matches and not target_names and not target_files:
            continue
        edges_for_target = [
            edge
            for edge in edges
            if graph_query.edge_matches_target(edge, target_names, target_files)
        ]
        for edge in graph_query.dedupe_edges(edges_for_target):
            key = (str(edge.get("kind", "")), str(edge.get("src", "")), str(edge.get("dst", "")))
            if key not in seen and len(facts) < MAX_GRAPH_FACTS:
                seen.add(key)
                facts.append(edge)
        for test_file in graph_query.find_tests(edges, target_names, target_files):
            tests.add(test_file)
    return facts, sorted(tests)


def recommended_reads(
    candidate_files: list[str], graph_facts: list[JsonObj], test_files: list[str]
) -> list[str]:
    reads: list[str] = []
    for file_name in candidate_files:
        add_unique(reads, file_name)
    for edge in graph_facts:
        for raw in (str(edge.get("src", "")), str(edge.get("dst", ""))):
            if ":" in raw:
                add_unique(reads, raw.split(":", 1)[0])
    for test_file in test_files:
        add_unique(reads, test_file)
    return reads


def build_evidence(
    *,
    query: str,
    project_root: Path,
    mb_path: Path,
    mode: str,
    semantic_candidates_path: Path | None,
    semantic_provider: str,
) -> JsonObj:
    warnings: list[str] = []
    channels_used: list[str] = []
    semantic_candidates: list[JsonObj] = []
    if mode in {"auto", "semantic"}:
        semantic_candidates = read_semantic_candidates(
            semantic_candidates_path, semantic_provider, warnings
        )
        if semantic_candidates:
            channels_used.append("semantic")

    nodes: list[JsonObj] = []
    edges: list[JsonObj] = []
    if mode in {"auto", "graph"}:
        nodes, edges = load_graph(mb_path / "codebase" / "graph.json", warnings)
        if nodes or edges:
            channels_used.append("graph")

    text_candidates: list[str] = []
    if mode in {"auto", "graph"}:
        text_candidates = text_search(project_root, query)
        if text_candidates:
            channels_used.append("text")

    candidate_files = seed_candidates(
        project_root=project_root,
        query=query,
        semantic_candidates=semantic_candidates,
        text_candidates=text_candidates,
        nodes=nodes,
    )
    graph_facts, test_files = (
        graph_expand(nodes, edges, candidate_files, query) if nodes or edges else ([], [])
    )
    reads = recommended_reads(candidate_files, graph_facts, test_files)
    if reads:
        channels_used.append("read")

    ordered_channels = [
        name for name in ["semantic", "graph", "text", "read"] if name in channels_used
    ]
    return {
        "ok": True,
        "query": query,
        "mode": mode,
        "channels_used": ordered_channels,
        "warnings": warnings,
        "candidate_files": candidate_files[:MAX_FILES],
        "semantic_candidates": semantic_candidates[:MAX_FILES],
        "graph_facts": graph_facts[:MAX_GRAPH_FACTS],
        "test_files": test_files[:MAX_FILES],
        "recommended_next_reads": reads[:MAX_FILES],
        "limits": {"max_files": MAX_FILES, "max_graph_facts": MAX_GRAPH_FACTS},
    }
