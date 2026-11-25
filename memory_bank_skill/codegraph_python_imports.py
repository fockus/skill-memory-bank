"""Lexical import evidence for Python graph edges; never import the indexed code."""

from __future__ import annotations

import ast
from collections.abc import Iterator
from pathlib import Path

from memory_bank_skill.codegraph_binding import resolve_relative_module
from memory_bank_skill.codegraph_invocations import _path

# Module, imported member (if any), additional repository-local import roots.
ImportRef = tuple[str, str, tuple[str, ...] | None]
_DEFS = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
_SCOPES = (*_DEFS, ast.Lambda, ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)


def _scope_nodes(scope: ast.AST) -> Iterator[ast.AST]:
    pending = list(ast.iter_child_nodes(scope))
    while pending:
        node = pending.pop()
        yield node
        if not isinstance(node, _SCOPES):
            pending.extend(ast.iter_child_nodes(node))


def _dotted(expr: ast.AST) -> str:
    if isinstance(expr, ast.Name):
        return expr.id
    if isinstance(expr, ast.Attribute) and (base := _dotted(expr.value)):
        return f"{base}.{expr.attr}"
    return ""


def _bound_name(n: ast.AST) -> str:
    if isinstance(n, ast.Name) and not isinstance(n.ctx, ast.Load):
        return n.id
    if isinstance(n, ast.arg):
        return n.arg
    if isinstance(n, (*_DEFS, ast.ExceptHandler, ast.MatchAs, ast.MatchStar)):
        return n.name or ""
    if isinstance(n, ast.MatchMapping):
        return n.rest or ""
    return ""


def _inserted_roots(tree: ast.Module, path: Path, root: Path) -> list[tuple[int, str]]:
    """Only direct module-level sys.path.insert(0, static_path) before an import."""
    additions = []
    constructors = {"str"}
    sys_names: set[str] = set()
    for stmt in tree.body:
        # Recognize the APIs, not just their spellings. A rebound `sys` can
        # have a path.insert method that does not change Python's search path.
        changed = {_bound_name(stmt)} if isinstance(stmt, _DEFS) else {
            a.asname or a.name.partition(".")[0] if isinstance(a, ast.alias) else _bound_name(a)
            for a in _scope_nodes(stmt)
        }
        sys_names -= changed
        constructors = {c for c in constructors if c.partition(".")[0] not in changed}
        if isinstance(stmt, ast.Import):
            for a in stmt.names:
                if a.name == "sys":
                    sys_names.add(a.asname or a.name)
                if a.name == "pathlib":
                    constructors.add(f"{a.asname or a.name}.Path")
        elif isinstance(stmt, ast.ImportFrom) and stmt.module == "pathlib" and not stmt.level:
            constructors.update(a.asname or a.name for a in stmt.names if a.name == "Path")
        elif isinstance(stmt, ast.Expr) and isinstance(call := stmt.value, ast.Call):
            if (_dotted(call.func) not in {f"{s}.path.insert" for s in sys_names}
                    or len(call.args) != 2 or call.keywords
                    or not isinstance(call.args[0], ast.Constant) or call.args[0].value != 0):
                continue
            value = _path(call.args[1], {"__file__": path}, constructors)
            if value is not None:
                try:
                    directory = value.resolve().relative_to(root)
                except (OSError, RuntimeError, ValueError):
                    continue
                additions.append((stmt.lineno, directory.as_posix()))
    return additions


def import_refs(tree: ast.Module, path: Path, root: Path, file: str) -> dict[ast.AST, ImportRef | None]:
    """None means literal call spelling only (no binding to a graph definition)."""
    roots = _inserted_roots(tree, path.resolve(), root.resolve())
    refs: dict[ast.AST, ImportRef | None] = {}
    imported_names = {a.asname or a.name.partition(".")[0] for a in ast.walk(tree)
                      if isinstance(a, ast.alias)}

    def visit(scope: ast.AST, inherited: dict[str, ImportRef | None]) -> None:
        nodes = list(_scope_nodes(scope))
        bindings: dict[str, ImportRef | None] = {}
        for n in nodes:
            if isinstance(n, (ast.Import, ast.ImportFrom)):
                relative = isinstance(n, ast.ImportFrom) and n.level > 0
                dirs = None if relative else tuple(d for line, d in roots if line < n.lineno)
                for a in n.names:
                    if isinstance(n, ast.ImportFrom):
                        mod = (resolve_relative_module(file, n.module, n.level) if relative
                               else n.module or "")
                        ref: ImportRef = mod, a.name, dirs
                    else:
                        ref = a.name, "", dirs
                    refs[a] = ref
                    local = a.asname or a.name
                    bindings[local] = ref if bindings.get(local, ref) == ref else None
            elif local := _bound_name(n):
                bindings[local] = None

        visible = inherited | bindings
        for n in nodes:
            if isinstance(n, _SCOPES):
                # A method does not close over its class namespace.
                visit(n, inherited if isinstance(scope, ast.ClassDef) else visible)
            elif isinstance(n, ast.Call) and isinstance(n.func, (ast.Name, ast.Attribute)):
                name = _dotted(n.func)
                base, dot, member = name.rpartition(".")
                local = base if dot else name
                binding = visible.get(local)
                if binding and not ("." in local and local.partition(".")[0] in visible):
                    mod, imported, dirs = binding
                    refs[n] = (f"{mod}.{imported}" if mod and imported else mod or imported,
                               member, dirs) if dot else binding
                elif isinstance(n.func, ast.Attribute) or name in imported_names:
                    refs[n] = None

    visit(tree, {})
    return refs
