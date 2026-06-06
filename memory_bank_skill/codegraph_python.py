"""Python `ast`-based extractor for the Memory Bank code graph.

Always available (stdlib only). Walks a single ``.py`` file and emits the
canonical node/edge schema shared with the tree-sitter adapter:

    nodes: {kind: module|function|class, name, file, line}
    edges: {src, dst, kind: import|call|inherit}

``src`` for a call edge is ``file:qualname`` (the enclosing scope); for an
import/module-level edge it is just the file. Names are best-effort
(``Name``/``Attribute``/``Subscript``) — same limitation as the rest of the graph.
"""

from __future__ import annotations

import ast
from pathlib import Path
from typing import Any

from memory_bank_skill.codegraph_common import rel, sha256


class _Extractor(ast.NodeVisitor):
    """Walk AST, collect nodes + edges for a single file."""

    def __init__(self, file_rel: str) -> None:
        self.file = file_rel
        self.nodes: list[dict[str, Any]] = []
        self.edges: list[dict[str, Any]] = []
        self._scope: list[str] = []

    def _qualname(self, name: str) -> str:
        return ".".join(self._scope + [name]) if self._scope else name

    def _current_src(self) -> str:
        return f"{self.file}:{self._qualname('')}".rstrip(".:")

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._handle_function(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._handle_function(node)

    def _handle_function(self, node: ast.AST) -> None:
        name = getattr(node, "name", "?")
        self.nodes.append({
            "kind": "function",
            "name": self._qualname(name),
            "file": self.file,
            "line": getattr(node, "lineno", 0),
        })
        self._scope.append(name)
        try:
            self.generic_visit(node)
        finally:
            self._scope.pop()

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        name = node.name
        self.nodes.append({
            "kind": "class",
            "name": self._qualname(name),
            "file": self.file,
            "line": node.lineno,
        })
        # Inheritance edges
        for base in node.bases:
            base_name = _name_of(base)
            if base_name:
                self.edges.append({
                    "src": f"{self.file}:{self._qualname(name)}",
                    "dst": base_name,
                    "kind": "inherit",
                })
        self._scope.append(name)
        try:
            self.generic_visit(node)
        finally:
            self._scope.pop()

    def visit_Import(self, node: ast.Import) -> None:
        for alias in node.names:
            self.edges.append({
                "src": self.file,
                "dst": alias.name,
                "kind": "import",
            })

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        mod = node.module or ""
        for alias in node.names:
            target = f"{mod}.{alias.name}" if mod else alias.name
            self.edges.append({
                "src": self.file,
                "dst": target,
                "kind": "import",
            })

    def visit_Call(self, node: ast.Call) -> None:
        target = _name_of(node.func)
        if target:
            src = f"{self.file}:{self._qualname('')}".rstrip(".:")
            self.edges.append({
                "src": src or self.file,
                "dst": target,
                "kind": "call",
            })
        self.generic_visit(node)


def _name_of(expr: ast.AST) -> str:
    """Best-effort name extraction from Name / Attribute / Subscript expressions."""
    if isinstance(expr, ast.Name):
        return expr.id
    if isinstance(expr, ast.Attribute):
        inner = _name_of(expr.value)
        return f"{inner}.{expr.attr}" if inner else expr.attr
    if isinstance(expr, ast.Call):
        return _name_of(expr.func)
    return ""


def parse_file(py_path: Path, src_root: Path) -> dict[str, Any]:
    """Parse a single .py file → {nodes, edges, hash}. Raises SyntaxError on bad syntax."""
    text = py_path.read_text(encoding="utf-8")
    tree = ast.parse(text, filename=str(py_path))
    file_rel = rel(py_path, src_root)
    extractor = _Extractor(file_rel)
    # Module node
    extractor.nodes.append({
        "kind": "module",
        "name": file_rel,
        "file": file_rel,
        "line": 1,
    })
    extractor.visit(tree)
    return {
        "nodes": extractor.nodes,
        "edges": extractor.edges,
        "hash": sha256(text),
        "file": file_rel,
    }
