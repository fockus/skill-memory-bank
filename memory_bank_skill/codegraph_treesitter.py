"""Tree-sitter multi-language adapter for the Memory Bank code graph (opt-in).

Extends the Python-only graph with Go / JavaScript / TypeScript / Rust / Java.
Languages are loaded lazily; if ``tree_sitter`` or a matching binding is not
installed the handler is simply absent and files of that type are skipped (with a
warning). Python always works via stdlib ``ast`` in ``codegraph_python``.

Public surface (consumed by ``mb-codegraph.py``):
    ``HAS_TREE_SITTER`` · ``LANG_CONFIG`` · ``get_ts_parser`` · ``parse_ts_file``

Emits the same node/edge schema as the Python extractor. Node-type whitelists are
intentionally minimal — this is an MVP, not full semantic analysis.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from memory_bank_skill.codegraph_common import rel, sha256

HAS_TREE_SITTER = False
_TS_PARSERS: dict[str, Any] = {}
try:
    from tree_sitter import Language, Parser
    HAS_TREE_SITTER = True
except ImportError:
    pass


# Config: extension → (language_name, module_import_name)
LANG_CONFIG = {
    ".go":  ("go", "tree_sitter_go"),
    ".js":  ("javascript", "tree_sitter_javascript"),
    ".mjs": ("javascript", "tree_sitter_javascript"),
    ".jsx": ("javascript", "tree_sitter_javascript"),
    ".ts":  ("typescript", "tree_sitter_typescript"),
    ".tsx": ("tsx", "tree_sitter_typescript"),
    ".rs":  ("rust", "tree_sitter_rust"),
    ".java": ("java", "tree_sitter_java"),
}


def get_ts_parser(lang_name: str, module_name: str) -> Any | None:
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


_TS_DOC_MAX = 200  # match the Python extractor's docstring cap


def _ts_node_text(node: Any, source: bytes) -> str:
    return source[node.start_byte:node.end_byte].decode("utf-8", errors="replace")


def _ts_signature(node: Any, source: bytes) -> str | None:
    """Declaration head (everything before the body block), collapsed + capped.

    Uses the tree-sitter ``body`` child boundary so a ``{`` inside generic
    constraints (``<T extends {…}>``) or default object params (``= {…}``) does
    NOT truncate the signature. Falls back to a naive ``{``-split / first line
    for body-less declarations (interfaces, method signatures).
    e.g. ``function greet(u: User): string`` / ``class Service`` / ``interface User``.
    """
    body = node.child_by_field_name("body")
    if body is not None:
        head = source[node.start_byte:body.start_byte].decode("utf-8", errors="replace")
    else:
        text = _ts_node_text(node, source)
        head = text.split("{", 1)[0] or (text.splitlines()[0] if text else "")
    collapsed = " ".join(head.split())
    return collapsed[:_TS_DOC_MAX] or None


def _ts_leading_doc(node: Any, source: bytes) -> str | None:
    """JSDoc (`/** … */`) immediately preceding the declaration, else None.

    Gated on ``/**`` to skip banner/line comments. Degrades to None when the
    binding lacks ``prev_named_sibling`` (older tree-sitter).
    """
    prev = getattr(node, "prev_named_sibling", None)
    if prev is None or prev.type != "comment":
        return None
    raw = _ts_node_text(prev, source).strip()
    if not raw.startswith("/**"):
        return None
    inner = raw.removeprefix("/**").removesuffix("*/")
    parts = [ln.strip().lstrip("*").strip() for ln in inner.splitlines()]
    text = " ".join(p for p in parts if p)
    return text[:_TS_DOC_MAX] or None


def _ts_enrich(node_dict: dict[str, Any], node: Any, source: bytes) -> dict[str, Any]:
    """Add optional ``signature``/``doc`` to a function/class node (omit when empty)."""
    sig = _ts_signature(node, source)
    if sig:
        node_dict["signature"] = sig
    doc = _ts_leading_doc(node, source)
    if doc:
        node_dict["doc"] = doc
    return node_dict


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


def parse_ts_file(py_path: Path, src_root: Path, lang_name: str, module_name: str,
                  include_docs: bool = False) -> dict[str, Any]:
    """Parse non-Python file via tree-sitter. Returns same schema as parse_file.

    ``include_docs`` (opt-in) adds optional ``signature``/``doc`` to function and
    class nodes; default off keeps graph.json output byte-identical.
    """
    parser = get_ts_parser(lang_name, module_name)
    if parser is None:
        raise RuntimeError(f"tree-sitter parser unavailable for {lang_name}")
    source = py_path.read_bytes()
    tree = parser.parse(source)
    file_rel = rel(py_path, src_root)
    nodes: list[dict[str, Any]] = [{"kind": "module", "name": file_rel, "file": file_rel, "line": 1}]
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
                fn_node = {"kind": "function", "name": name, "file": file_rel,
                           "line": n.start_point[0] + 1}
                nodes.append(_ts_enrich(fn_node, n, source) if include_docs else fn_node)
        elif t in class_types:
            name = _ts_find_name(n, source)
            if name:
                cls_node = {"kind": "class", "name": name, "file": file_rel,
                            "line": n.start_point[0] + 1}
                nodes.append(_ts_enrich(cls_node, n, source) if include_docs else cls_node)
        elif t in import_types:
            for target in _ts_find_import_target(n, source, lang_name):
                edges.append({"src": file_rel, "dst": target, "kind": "import"})
        elif t in call_types:
            target = _ts_find_call_target(n, source)
            if target:
                edges.append({"src": file_rel, "dst": target, "kind": "call"})
        elif t in inherit_types:
            for target in _ts_find_inherit_targets(n, source, lang_name):
                edges.append({"src": file_rel, "dst": target, "kind": "inherit"})
        # Enqueue children
        stack.extend(n.children)

    return {"nodes": nodes, "edges": edges,
            "hash": sha256(source.decode("utf-8", errors="replace")),
            "file": file_rel}
