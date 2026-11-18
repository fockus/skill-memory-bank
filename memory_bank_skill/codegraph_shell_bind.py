"""Binding pass for shell edges: resolve path literals, keep only real call targets.

Split out of ``codegraph_shell`` (SRP); runs once in the orchestrator when every
file is known. Pure functions, no dependency on the parser module.
"""

from __future__ import annotations

from collections import deque
from typing import Any

__all__ = ["SHELL_EXTS", "bind_shell_edges"]

# Extensions owned by the shell extractor (dispatch key in the orchestrator).
SHELL_EXTS = frozenset({".sh", ".bats"})


def _unquote(token: str) -> str:
    return token.strip().strip("\"'")


def _resolve_path(raw: str, known: list[str]) -> str:
    """Best-effort repo-relative path for a shell path literal.

    Variable-bearing segments are dropped (``"$REPO_ROOT/scripts/x.sh"`` →
    ``scripts/x.sh``), then the remaining suffix — and failing that the bare
    basename — must match exactly one walked file. Ambiguity resolves to nothing:
    the cleaned path is kept as-is rather than inventing an edge to a homonym.
    """
    parts = [p for p in _unquote(raw).replace("\\", "/").split("/") if p not in ("", ".", "..")]
    while parts and "$" in parts[0]:
        parts.pop(0)
    if not parts:
        return _unquote(raw)
    if any("$" in p for p in parts):
        parts = parts[-1:]
        if "$" in parts[0]:
            return _unquote(raw)
    suffix = "/".join(parts)
    if suffix in known:
        return suffix
    matches = [f for f in known if f.endswith("/" + suffix)]
    if len(matches) != 1:
        base = parts[-1]
        matches = [f for f in known if f.rsplit("/", 1)[-1] == base]
    return matches[0] if len(matches) == 1 else suffix


def _is_shell(file_rel: str) -> bool:
    return any(file_rel.endswith(ext) for ext in SHELL_EXTS)


def _src_file(edge: dict[str, Any]) -> str:
    return str(edge.get("src", "")).split(":", 1)[0]


def _reachable_funcs(start: str, sourced: dict[str, set[str]], funcs: dict[str, set[str]]) -> set[str]:
    """Functions callable from ``start``: its own plus those of sourced files (transitive)."""
    seen = {start}
    queue = deque([start])
    names: set[str] = set()
    while queue:
        current = queue.popleft()
        names |= funcs.get(current, set())
        for target in sorted(sourced.get(current, set())):
            if target not in seen:
                seen.add(target)
                queue.append(target)
    return names


def bind_shell_edges(
    nodes: list[dict[str, Any]], edges: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Resolve shell import paths and keep only call edges that name a real function.

    Non-shell edges (Python, tree-sitter languages) are passed through untouched
    and in order, so the rest of ``graph.json`` stays byte-identical. Shell edges
    are de-duplicated: the same script mentioned twice is one import edge.
    """
    known_sh = sorted(
        {
            str(n.get("file", ""))
            for n in nodes
            if n.get("kind") == "module" and str(n.get("file", "")).endswith(".sh")
        }
    )
    known_py = sorted(
        {
            str(n.get("file", ""))
            for n in nodes
            if n.get("kind") == "module" and str(n.get("file", "")).endswith(".py")
        }
    )
    funcs: dict[str, set[str]] = {}
    for node in nodes:
        file_rel = str(node.get("file", ""))
        if node.get("kind") == "function" and _is_shell(file_rel):
            funcs.setdefault(file_rel, set()).add(str(node.get("name", "")))

    # Pass 1 — resolve import destinations and build the `source` adjacency.
    sourced: dict[str, set[str]] = {}
    resolved: list[dict[str, Any] | None] = []
    for edge in edges:
        if edge.get("kind") != "import" or not _is_shell(_src_file(edge)):
            resolved.append(None)
            continue
        dst = str(edge.get("dst", ""))
        if dst.endswith(".sh"):
            dst = _resolve_path(dst, known_sh)
        elif dst.endswith(".py"):
            dst = _resolve_path(dst, known_py)
            if dst not in known_py:  # unresolved or ambiguous mention — no edge
                resolved.append({"src": "", "dst": "", "kind": "drop"})
                continue
        new_edge = {"src": edge["src"], "dst": dst, "kind": "import"}
        if edge.get("via") == "source" and dst in funcs:
            sourced.setdefault(_src_file(edge), set()).add(dst)
        resolved.append(new_edge)

    # Pass 2 — emit, filtering call candidates against reachable functions.
    reachable: dict[str, set[str]] = {}
    seen: set[tuple[str, str, str]] = set()
    out: list[dict[str, Any]] = []
    for edge, rebound in zip(edges, resolved, strict=True):
        src_file = _src_file(edge)
        if not _is_shell(src_file):
            out.append(edge)
            continue
        if rebound is not None:
            if rebound["kind"] == "drop":
                continue
            candidate = rebound
        elif edge.get("kind") == "call":
            if src_file not in reachable:
                reachable[src_file] = _reachable_funcs(src_file, sourced, funcs)
            if str(edge.get("dst", "")) not in reachable[src_file]:
                continue
            candidate = {"src": edge["src"], "dst": edge["dst"], "kind": "call"}
        else:
            candidate = edge
        key = (candidate["kind"], str(candidate["src"]), str(candidate["dst"]))
        if key in seen:
            continue
        seen.add(key)
        out.append(candidate)
    return out
