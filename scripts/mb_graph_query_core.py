"""Core graph query operations for Memory Bank graph.json JSONL files."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

try:
    from memory_bank_skill.codegraph_loader import load_graph as _load_graph
except ModuleNotFoundError:  # pragma: no cover - bootstrap when imported as a bare script module
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill.codegraph_loader import load_graph as _load_graph

EXIT_OK = 0
EXIT_NO_MATCH = 1
EXIT_INVALID_INPUT = 2
EXIT_MISSING_GRAPH = 3

JsonObj = dict[str, Any]


def load_graph(path: Path) -> tuple[list[JsonObj], list[JsonObj]]:
    """Delegate to the canonical package loader (kept as back-compat surface)."""
    return _load_graph(path)


def short_name(value: str) -> str:
    tail = value.rsplit(":", 1)[-1]
    return tail.rsplit(".", 1)[-1]


def is_test_file(file_name: str) -> bool:
    path = file_name.replace("\\", "/")
    base = path.rsplit("/", 1)[-1]
    return (
        path.startswith("tests/")
        or "/tests/" in path
        or base.startswith("test_")
        or base.endswith("_test.py")
        or base.endswith("_test.go")
        or ".test." in base
        or ".spec." in base
    )


def edge_file(edge_src: str) -> str:
    return edge_src.split(":", 1)[0]


def match_node(node: JsonObj, *, symbol: str | None, file_name: str | None) -> bool:
    node_name = str(node.get("name", ""))
    node_file = str(node.get("file", ""))
    if file_name is not None:
        return node_file == file_name or node_name == file_name
    if symbol is None:
        return False
    return node_name == symbol or short_name(node_name) == symbol


def edge_matches_target(edge: JsonObj, target_names: set[str], target_files: set[str]) -> bool:
    src = str(edge.get("src", ""))
    dst = str(edge.get("dst", ""))
    src_file = edge_file(src)
    src_symbol = src.rsplit(":", 1)[-1]
    return (
        src in target_names
        or src_symbol in target_names
        or dst in target_names
        or short_name(dst) in target_names
        or src_file in target_files
        or dst in target_files
    )


def edge_is_outgoing(edge: JsonObj, target_names: set[str], target_files: set[str]) -> bool:
    src = str(edge.get("src", ""))
    src_file = edge_file(src)
    src_symbol = src.rsplit(":", 1)[-1]
    return src in target_names or src_symbol in target_names or src_file in target_files


def edge_is_incoming(edge: JsonObj, target_names: set[str], target_files: set[str]) -> bool:
    dst = str(edge.get("dst", ""))
    return dst in target_names or short_name(dst) in target_names or dst in target_files


def resolve_target(
    nodes: list[JsonObj], *, symbol: str | None, file_name: str | None
) -> tuple[list[JsonObj], set[str], set[str]]:
    matches = [node for node in nodes if match_node(node, symbol=symbol, file_name=file_name)]
    target_names: set[str] = set()
    target_files: set[str] = set()

    if symbol is not None:
        target_names.add(symbol)
    if file_name is not None:
        target_files.add(file_name)

    for node in matches:
        name = str(node.get("name", ""))
        if name:
            target_names.add(name)
            target_names.add(short_name(name))
        file_value = str(node.get("file", ""))
        if file_value:
            target_files.add(file_value)
    return matches, target_names, target_files


def dedupe_edges(edges: list[JsonObj]) -> list[JsonObj]:
    seen: set[tuple[str, str, str]] = set()
    result: list[JsonObj] = []
    for edge in edges:
        key = (str(edge.get("kind", "")), str(edge.get("src", "")), str(edge.get("dst", "")))
        if key in seen:
            continue
        seen.add(key)
        result.append(edge)
    return result


def find_tests(edges: list[JsonObj], target_names: set[str], target_files: set[str]) -> list[str]:
    test_files: set[str] = set()
    for edge in edges:
        src = str(edge.get("src", ""))
        dst = str(edge.get("dst", ""))
        src_file = edge_file(src)
        kind = str(edge.get("kind", ""))
        graph_test_link = kind == "tests" and (
            dst in target_files or dst in target_names or short_name(dst) in target_names
        )
        test_file_call = is_test_file(src_file) and (
            dst in target_names or short_name(dst) in target_names or dst in target_files
        )
        if graph_test_link or test_file_call:
            test_files.add(src_file)
    return sorted(test_files)


def neighbors_payload(
    nodes: list[JsonObj], edges: list[JsonObj], symbol: str | None, file_name: str | None
) -> JsonObj:
    matches, target_names, target_files = resolve_target(nodes, symbol=symbol, file_name=file_name)
    incoming = dedupe_edges(
        [edge for edge in edges if edge_is_incoming(edge, target_names, target_files)]
    )
    outgoing = dedupe_edges(
        [edge for edge in edges if edge_is_outgoing(edge, target_names, target_files)]
    )
    if not matches and not incoming and not outgoing:
        return {"ok": False, "error": "no_match", "query": {"symbol": symbol, "file": file_name}}
    return {
        "ok": True,
        "query": {"symbol": symbol, "file": file_name},
        "matches": matches,
        "incoming": incoming,
        "outgoing": outgoing,
    }


def impact_payload(
    nodes: list[JsonObj], edges: list[JsonObj], symbol: str | None, file_name: str | None
) -> JsonObj:
    base = neighbors_payload(nodes, edges, symbol, file_name)
    if not base.get("ok"):
        return base
    matches, target_names, target_files = resolve_target(nodes, symbol=symbol, file_name=file_name)
    return {
        "ok": True,
        "query": base["query"],
        "matches": matches,
        "dependents": base["incoming"],
        "dependencies": base["outgoing"],
        "test_files": find_tests(edges, target_names, target_files),
    }


def tests_payload(
    nodes: list[JsonObj], edges: list[JsonObj], symbol: str | None, file_name: str | None
) -> JsonObj:
    matches, target_names, target_files = resolve_target(nodes, symbol=symbol, file_name=file_name)
    test_files = find_tests(edges, target_names, target_files)
    if not matches and not test_files:
        return {"ok": False, "error": "no_match", "query": {"symbol": symbol, "file": file_name}}
    return {
        "ok": True,
        "query": {"symbol": symbol, "file": file_name},
        "matches": matches,
        "test_files": test_files,
    }


def print_json(payload: JsonObj) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))


def error_payload(error: str, message: str) -> JsonObj:
    return {"ok": False, "error": error, "message": message}
