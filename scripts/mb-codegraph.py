#!/usr/bin/env python3
"""Python AST-based code graph builder for Memory Bank.

Usage:
    mb-codegraph.py [--dry-run|--apply] [mb_path] [src_root]

Parses ``src_root/**/*.py``, extracts functions/classes/imports/calls/inherits,
builds a graph, writes outputs (``--apply`` only):

  * ``<mb>/codebase/graph.json`` — JSON Lines (one node/edge per line)
  * ``<mb>/codebase/god-nodes.md`` — top-20 by in+out degree
  * ``<mb>/codebase/.cache/<file-slug>.json`` — per-file SHA256 → parsed entities

Incremental: files whose SHA256 matches cache are skipped (summary reports
``reparsed=N cached=M``). Tree-sitter adapter for non-Python languages —
Stage 6.5 opt-in extras (see BACKLOG).
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

try:
    from memory_bank_skill._io import atomic_write
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill._io import atomic_write

TOP_GOD_NODES = 20

# ═══ Tree-sitter adapter (Stage 6.5 — opt-in) ═══
# Languages are loaded lazily. If tree-sitter or the matching binding
# is not installed, the handler is simply absent and files of that type are skipped
# (with a warning). Python always works via stdlib `ast`.
HAS_TREE_SITTER = False
_TS_PARSERS: dict[str, Any] = {}
try:
    from tree_sitter import Language, Parser  # noqa: PLC0415
    HAS_TREE_SITTER = True
except ImportError:
    pass


# Config: extension → (language_name, module_import_name)
_TS_LANG_CONFIG = {
    ".go":  ("go", "tree_sitter_go"),
    ".js":  ("javascript", "tree_sitter_javascript"),
    ".mjs": ("javascript", "tree_sitter_javascript"),
    ".jsx": ("javascript", "tree_sitter_javascript"),
    ".ts":  ("typescript", "tree_sitter_typescript"),
    ".tsx": ("tsx", "tree_sitter_typescript"),
    ".rs":  ("rust", "tree_sitter_rust"),
    ".java": ("java", "tree_sitter_java"),
}


def _get_ts_parser(lang_name: str, module_name: str) -> Any | None:
    """Lazy-load tree-sitter parser for a language. Returns None on failure."""
    if not HAS_TREE_SITTER:
        return None
    if lang_name in _TS_PARSERS:
        return _TS_PARSERS[lang_name]
    try:
        mod = __import__(module_name)
    except ImportError:
        _TS_PARSERS[lang_name] = None
        return None
    try:
        # The typescript module exposes `language_typescript()` / `language_tsx()`
        if lang_name == "typescript":
            lang_fn = getattr(mod, "language_typescript", None) or getattr(mod, "language", None)
        elif lang_name == "tsx":
            lang_fn = getattr(mod, "language_tsx", None) or getattr(mod, "language", None)
        else:
            lang_fn = getattr(mod, "language", None)
        if lang_fn is None:
            _TS_PARSERS[lang_name] = None
            return None
        lang = Language(lang_fn())
        parser = Parser(lang)
        _TS_PARSERS[lang_name] = parser
        return parser
    except Exception as e:  # noqa: BLE001 — robust fallback
        print(f"[warn] tree-sitter {lang_name}: {e}", file=sys.stderr)
        _TS_PARSERS[lang_name] = None
        return None


# Node type whitelists per language. Keep minimal — MVP not full semantic analysis.
_TS_NODE_KINDS = {
    "go": {
        "function": ("function_declaration", "method_declaration"),
        "class":    ("type_spec",),
        "import":   ("import_spec",),
        "call":     ("call_expression",),
    },
    "javascript": {
        "function": ("function_declaration", "method_definition", "arrow_function"),
        "class":    ("class_declaration",),
        "import":   ("import_statement",),
        "call":     ("call_expression",),
        "inherit":  ("class_heritage",),
    },
    "typescript": {
        "function": ("function_declaration", "method_definition", "method_signature"),
        "class":    ("class_declaration", "interface_declaration"),
        "import":   ("import_statement",),
        "call":     ("call_expression",),
        "inherit":  ("class_heritage", "extends_clause"),
    },
    "tsx": {
        "function": ("function_declaration", "method_definition"),
        "class":    ("class_declaration", "interface_declaration"),
        "import":   ("import_statement",),
        "call":     ("call_expression",),
    },
    "rust": {
        "function": ("function_item",),
        "class":    ("struct_item", "enum_item", "trait_item"),
        "import":   ("use_declaration",),
        "call":     ("call_expression",),
    },
    "java": {
        "function": ("method_declaration", "constructor_declaration"),
        "class":    ("class_declaration", "interface_declaration"),
        "import":   ("import_declaration",),
        "call":     ("method_invocation",),
        "inherit":  ("superclass", "extends_interfaces"),
    },
}


def _ts_node_text(node: Any, source: bytes) -> str:
    return source[node.start_byte:node.end_byte].decode("utf-8", errors="replace")


def _ts_find_name(node: Any, source: bytes) -> str:
    """Best-effort: find the child identifier for a function/class name."""
    # Try field "name" first (tree-sitter grammars typically have it)
    name_node = node.child_by_field_name("name")
    if name_node is not None:
        return _ts_node_text(name_node, source)
    # Fallback: first identifier child
    for child in node.children:
        if child.type in ("identifier", "type_identifier", "property_identifier",
                          "field_identifier", "simple_identifier"):
            return _ts_node_text(child, source)
    return ""


def _ts_find_call_target(node: Any, source: bytes) -> str:
    """For `call_expression` / `method_invocation` — name of the called function."""
    # Go/JS/Rust: "function" field
    fn = node.child_by_field_name("function")
    if fn is not None:
        return _ts_node_text(fn, source).strip()
    # Java method_invocation: "name" field
    name = node.child_by_field_name("name")
    if name is not None:
        obj = node.child_by_field_name("object")
        if obj is not None:
            return f"{_ts_node_text(obj, source)}.{_ts_node_text(name, source)}"
        return _ts_node_text(name, source)
    # Fallback: first child text trimmed
    return _ts_node_text(node, source).split("(")[0].strip()


def _ts_find_import_target(node: Any, source: bytes, lang: str) -> list[str]:
    """Extract import path(s) from language-specific node."""
    text = _ts_node_text(node, source)
    targets: list[str] = []
    if lang == "go":
        # import_spec: "path" [string_literal]
        path_node = node.child_by_field_name("path")
        if path_node is not None:
            targets.append(_ts_node_text(path_node, source).strip('"`'))
    elif lang in ("javascript", "typescript", "tsx"):
        # import_statement: source [string]
        src_node = node.child_by_field_name("source")
        if src_node is not None:
            targets.append(_ts_node_text(src_node, source).strip("'\""))
    elif lang == "rust":
        # use_declaration: argument is the path
        for child in node.children:
            if child.type in ("scoped_use_list", "use_list", "scoped_identifier", "identifier"):
                targets.append(_ts_node_text(child, source))
                break
        if not targets:
            targets.append(text.removeprefix("use").rstrip(";").strip())
    elif lang == "java":
        # import_declaration: first identifier chain after "import"
        for child in node.children:
            if child.type in ("scoped_identifier", "identifier"):
                targets.append(_ts_node_text(child, source))
                break
    return [t for t in targets if t]


def _ts_find_inherit_targets(node: Any, source: bytes, lang: str) -> list[str]:
    """Parent class/interface names for class_heritage / extends / superclass."""
    targets: list[str] = []
    text = _ts_node_text(node, source)
    # Simple heuristic: identifiers in the node text. Better to walk children.
    for child in node.children:
        if child.type in ("identifier", "type_identifier",
                          "type_reference", "scoped_type_identifier"):
            targets.append(_ts_node_text(child, source))
    if not targets and text:
        # Fallback: strip 'extends ' / 'implements '
        cleaned = text.replace("extends", "").replace("implements", "").strip()
        if cleaned:
            targets.append(cleaned.split(",")[0].strip())
    return targets


def _parse_ts_file(py_path: Path, src_root: Path, lang_name: str, module_name: str) -> dict[str, Any]:
    """Parse non-Python file via tree-sitter. Returns same schema as parse_file."""
    parser = _get_ts_parser(lang_name, module_name)
    if parser is None:
        raise RuntimeError(f"tree-sitter parser unavailable for {lang_name}")
    source = py_path.read_bytes()
    tree = parser.parse(source)
    rel = _rel(py_path, src_root)
    nodes: list[dict[str, Any]] = [{"kind": "module", "name": rel, "file": rel, "line": 1}]
    edges: list[dict[str, Any]] = []
    kinds = _TS_NODE_KINDS.get(lang_name, {})
    func_types = kinds.get("function", ())
    class_types = kinds.get("class", ())
    import_types = kinds.get("import", ())
    call_types = kinds.get("call", ())
    inherit_types = kinds.get("inherit", ())

    # Walk full tree iteratively (avoid recursion limit).
    stack = [tree.root_node]
    while stack:
        n = stack.pop()
        t = n.type
        if t in func_types:
            name = _ts_find_name(n, source)
            if name:
                nodes.append({"kind": "function", "name": name, "file": rel,
                              "line": n.start_point[0] + 1})
        elif t in class_types:
            name = _ts_find_name(n, source)
            if name:
                nodes.append({"kind": "class", "name": name, "file": rel,
                              "line": n.start_point[0] + 1})
        elif t in import_types:
            for target in _ts_find_import_target(n, source, lang_name):
                edges.append({"src": rel, "dst": target, "kind": "import"})
        elif t in call_types:
            target = _ts_find_call_target(n, source)
            if target:
                edges.append({"src": rel, "dst": target, "kind": "call"})
        elif t in inherit_types:
            for target in _ts_find_inherit_targets(n, source, lang_name):
                edges.append({"src": rel, "dst": target, "kind": "inherit"})
        # Enqueue children
        stack.extend(n.children)

    return {"nodes": nodes, "edges": edges, "hash": _sha256(source.decode("utf-8", errors="replace")),
            "file": rel}


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _rel(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


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
    rel = _rel(py_path, src_root)
    extractor = _Extractor(rel)
    # Module node
    extractor.nodes.append({
        "kind": "module",
        "name": rel,
        "file": rel,
        "line": 1,
    })
    extractor.visit(tree)
    return {
        "nodes": extractor.nodes,
        "edges": extractor.edges,
        "hash": _sha256(text),
        "file": rel,
    }


def _cache_slug(rel_path: str) -> str:
    return hashlib.sha256(rel_path.encode("utf-8")).hexdigest()[:16]


def _load_cache(cache_dir: Path, rel_path: str) -> dict[str, Any] | None:
    cache_file = cache_dir / f"{_cache_slug(rel_path)}.json"
    if not cache_file.exists():
        return None
    try:
        return json.loads(cache_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _save_cache(cache_dir: Path, rel_path: str, data: dict[str, Any]) -> None:
    cache_file = cache_dir / f"{_cache_slug(rel_path)}.json"
    atomic_write(cache_file, json.dumps(data, ensure_ascii=False, indent=2))


def build_graph(
    src_root: Path,
    cache_dir: Path | None = None,
) -> dict[str, Any]:
    """Walk src_root/**/*.py, parse each, aggregate nodes+edges.

    If cache_dir provided: skip re-parse when file hash matches cache.
    Returns aggregated {"nodes": [...], "edges": [...], "reparsed": N, "cached": M}.
    """
    all_nodes: list[dict[str, Any]] = []
    all_edges: list[dict[str, Any]] = []
    reparsed = 0
    cached = 0

    if not src_root.exists():
        return {"nodes": [], "edges": [], "reparsed": 0, "cached": 0}

    # Collect all files: Python via `ast` + tree-sitter-supported types if installed.
    supported_exts = {".py"}
    if HAS_TREE_SITTER:
        supported_exts.update(_TS_LANG_CONFIG.keys())

    all_source_files: list[Path] = []
    for ext in sorted(supported_exts):
        all_source_files.extend(src_root.rglob(f"*{ext}"))
    all_source_files = sorted(set(all_source_files))

    for src_file in all_source_files:
        # Skip hidden dirs (like .venv, __pycache__, node_modules)
        try:
            parts = src_file.relative_to(src_root).parts
        except ValueError:
            continue
        skip_dirs = {".venv", "__pycache__", "node_modules", ".git", "target", "dist", "build"}
        if any(p.startswith(".") or p in skip_dirs for p in parts[:-1]):
            continue

        rel = _rel(src_file, src_root)
        ext = src_file.suffix.lower()
        try:
            if ext == ".py":
                text = src_file.read_text(encoding="utf-8")
                content_hash = _sha256(text)
            else:
                content_hash = _sha256(
                    src_file.read_bytes().decode("utf-8", errors="replace")
                )
        except (OSError, UnicodeDecodeError):
            continue

        # Cache check
        if cache_dir is not None:
            cached_data = _load_cache(cache_dir, rel)
            if cached_data and cached_data.get("hash") == content_hash:
                all_nodes.extend(cached_data.get("nodes", []))
                all_edges.extend(cached_data.get("edges", []))
                cached += 1
                continue

        # Dispatch parser
        try:
            if ext == ".py":
                result = parse_file(src_file, src_root)
            elif ext in _TS_LANG_CONFIG and HAS_TREE_SITTER:
                lang_name, module_name = _TS_LANG_CONFIG[ext]
                result = _parse_ts_file(src_file, src_root, lang_name, module_name)
            else:
                continue
        except SyntaxError as e:
            print(f"[warn] {rel}: syntax error skipped — {e.msg}", file=sys.stderr)
            continue
        except Exception as e:  # noqa: BLE001 — robust batch
            print(f"[warn] {rel}: parse failed — {e}", file=sys.stderr)
            continue

        all_nodes.extend(result["nodes"])
        all_edges.extend(result["edges"])
        reparsed += 1

        if cache_dir is not None:
            _save_cache(cache_dir, rel, result)

    return {"nodes": all_nodes, "edges": all_edges, "reparsed": reparsed, "cached": cached}


def _compute_degree(graph: dict[str, Any]) -> dict[str, int]:
    """Return {node_name: in+out degree}. Uses name matching (target in edge.dst)."""
    degree: dict[str, int] = {}
    node_names = {n["name"] for n in graph["nodes"]}
    for e in graph["edges"]:
        # Out-degree: edge starts at src (file or file:qualname)
        src_key = e["src"].split(":")[-1] if ":" in e["src"] else e["src"]
        degree[src_key] = degree.get(src_key, 0) + 1
        # In-degree: dst matches one of node names (suffix match for qualified names)
        dst = e["dst"]
        for name in node_names:
            short = name.split(".")[-1]
            if dst in (name, short) or dst.endswith(f".{short}"):
                degree[name] = degree.get(name, 0) + 1
                break
    return degree


def _render_god_nodes(graph: dict[str, Any]) -> str:
    """Top-N nodes by degree → markdown with file:line links."""
    degree = _compute_degree(graph)
    ranked = sorted(degree.items(), key=lambda kv: -kv[1])[:TOP_GOD_NODES]
    node_lookup = {n["name"]: n for n in graph["nodes"]}

    lines = [
        "# God nodes — top by degree (in + out)",
        "",
        "Automatically generated by `mb-codegraph.py`. Top connectivity nodes are candidates for refactoring or decomposition when complexity is high.",
        "",
        "| # | Name | Kind | File:Line | Degree |",
        "|---|------|------|-----------|--------|",
    ]
    for i, (name, deg) in enumerate(ranked, 1):
        node = node_lookup.get(name)
        kind = node.get("kind", "?") if node else "?"
        loc = (f"{node.get('file', '?')}:{node.get('line', '?')}" if node else "—")
        lines.append(f"| {i} | `{name}` | {kind} | {loc} | {deg} |")
    lines.append("")
    return "\n".join(lines)


def _write_graph_jsonl(graph: dict[str, Any], target: Path) -> None:
    lines: list[str] = []
    for n in graph["nodes"]:
        lines.append(json.dumps({"type": "node", **n}, ensure_ascii=False))
    for e in graph["edges"]:
        lines.append(json.dumps({"type": "edge", **e}, ensure_ascii=False))
    atomic_write(target, "\n".join(lines) + "\n")


def run(
    *,
    mb_path: str,
    src_root: str,
    mode: str = "dry-run",
) -> dict[str, Any]:
    """Build graph, optionally write outputs. Returns summary dict."""
    mb = Path(mb_path)
    src = Path(src_root)
    if not mb.is_dir():
        raise FileNotFoundError(f"mb_path not found: {mb}")
    if not src.is_dir():
        raise FileNotFoundError(f"src_root not found: {src}")

    codebase = mb / "codebase"
    codebase.mkdir(exist_ok=True)
    cache_dir = codebase / ".cache" if mode == "apply" else None
    if cache_dir is not None:
        cache_dir.mkdir(exist_ok=True)

    graph = build_graph(src, cache_dir)
    node_count = len(graph["nodes"])
    edge_count = len(graph["edges"])

    summary = {
        "nodes": node_count,
        "edges": edge_count,
        "reparsed": graph.get("reparsed", 0),
        "cached": graph.get("cached", 0),
        "mode": mode,
    }

    print(f"nodes={node_count}")
    print(f"edges={edge_count}")
    print(f"reparsed={summary['reparsed']}")
    print(f"cached={summary['cached']}")
    print(f"mode={mode}")

    if mode != "apply":
        return summary

    _write_graph_jsonl(graph, codebase / "graph.json")
    atomic_write(codebase / "god-nodes.md", _render_god_nodes(graph))

    return summary


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Python code graph builder for Memory Bank")
    parser.add_argument("--apply", action="store_true",
                        help="Write graph.json + god-nodes.md (default: dry-run)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Stdout summary only (default)")
    parser.add_argument("mb_path", nargs="?", default=".memory-bank")
    parser.add_argument("src_root", nargs="?", default=".")
    args = parser.parse_args(argv[1:])

    mode = "apply" if args.apply else "dry-run"
    try:
        run(mb_path=args.mb_path, src_root=args.src_root, mode=mode)
    except FileNotFoundError as e:
        print(f"[error] {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
