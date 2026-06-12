"""Import-aware call-resolution layer for the Memory Bank Python code graph.

Extracted from ``codegraph_python.py`` (kept ≤400 lines per the spec
constraint). Holds the namespace + binding logic shared between the AST
extractor and the orchestrator:

  * ``file_to_module`` — canonical dotted module namespace for a file path.
  * ``resolve_relative_module`` — resolve a relative ``from .x import y`` to an
    absolute dotted module, given the caller file and the ``ImportFrom.level``.
  * ``bind_calls`` — apply import-aware resolution to call edges.

Design contract (design.md § A2): **Python-first**. Non-Python languages
(Go/JS/TS/Rust/Java via tree-sitter) keep their CURRENT name-matching
behaviour unchanged — ``bind_calls`` never rewrites or suppresses an edge whose
caller file is not a ``.py`` file, and the unique-fallback / suppression logic
only ever binds to ``.py`` definitions.
"""

from __future__ import annotations

from typing import Any


def file_to_module(file_rel: str) -> str:
    """Convert a relative file path to a canonical dotted module namespace.

    ``pkg/sub/b.py`` → ``pkg.sub.b``; a package ``pkg/__init__.py`` → ``pkg``;
    a ROOT-level ``__init__.py`` → ``""`` (the package root has no name).
    This is the single dst namespace used for ALL bound call edges so that
    import-target form and path-derived form never diverge (see bind_calls).
    """
    stem = file_rel.removesuffix(".py")
    dotted = stem.replace("/", ".").replace("\\", ".")
    # Drop a trailing ``__init__`` component: nested ``pkg.__init__`` → ``pkg``,
    # and a bare root ``__init__`` → ``""`` (otherwise a root package init would
    # leak ``__init__`` into resolved module namespaces).
    if dotted == "__init__":
        return ""
    return dotted.removesuffix(".__init__")


def resolve_relative_module(file_rel: str, module: str | None, level: int) -> str:
    """Resolve a relative ImportFrom to an absolute dotted module.

    ``level`` is the number of leading dots. The caller's package is derived
    from ``file_rel`` (drop the filename, treat directories as package parts).
    ``from . import x`` → ``module`` is None → the package itself. Climbs
    ``level - 1`` packages up for extra dots.
    """
    caller_module = file_to_module(file_rel)
    # Package parts of the caller = its dotted module minus the final component
    # (the module's own name). A package __init__ collapses to the package
    # itself in file_to_module, so its parts ARE the package.
    is_package = file_rel.endswith("__init__.py")
    pkg_parts = caller_module.split(".") if caller_module else []
    if not is_package and pkg_parts:
        pkg_parts = pkg_parts[:-1]
    # Each extra dot beyond the first climbs one package up.
    climb = level - 1
    if climb > 0:
        pkg_parts = pkg_parts[: len(pkg_parts) - climb] if climb <= len(pkg_parts) else []
    prefix = ".".join(pkg_parts)
    if module:
        return f"{prefix}.{module}" if prefix else module
    return prefix


def bind_calls(
    all_edges: list[dict[str, Any]],
    import_bindings: dict[str, dict[str, str]],
    definitions: dict[str, list[str]],
    star_imports: dict[str, list[str]] | None = None,
) -> list[dict[str, Any]]:
    """Apply import-aware resolution to call edges and return the filtered list.

    Binding decision order (per design.md § A2, corrected for Python name
    resolution where the caller's own module definition wins first):
      0. Local-definition shadowing: the caller's file defines the bare name
         → bind to the local definition (caller's own module wins; the edge is
         never rewritten to / suppressed by an external homonym).
      1. Explicit import: the caller's file imports the bare name (or aliases
         it) → replace dst with the bound fully-qualified definition.
      2. Star import: exactly one ``from mod import *`` module of the caller
         defines the name → bind to ``mod.name``; several → suppress (ambiguous).
      3. Unique project-wide fallback: exactly one external definition
         → keep the edge, bound to the canonical dotted module form.
      4. Multiple external definitions and none of the above resolved
         → suppress the cross-module edge (no homonym guessing).

    All bound dsts use one canonical dotted module namespace
    (``pkg.mod.symbol``) — never the slash path form — so import-target and
    path-derived bindings never diverge.

    Attribute calls (dst contains ".") keep current behaviour — they already
    carry enough context; type inference is out of scope.

    Non-call edges (import, inherit) pass through unchanged.

    Cross-language safety (§ A2, Python-first): a call edge whose caller file is
    not a ``.py`` file passes through UNCHANGED — Go/JS/TS/Rust/Java homonym
    rules are never applied to it. The ``definitions`` map is expected to be
    built from ``.py`` nodes only; any non-``.py`` defining file is filtered out
    defensively here so a Python bare call can never bind to a foreign symbol.

    Args:
        all_edges: flat list of all edges from build_graph (mixed kinds).
        import_bindings: {file_rel: {local_name: "mod.symbol"}}
                         as produced by parse_file["import_bindings"].
        definitions: {bare_name: [list_of_files_that_define_it]}
                     built from all function/class nodes (Python only).
        star_imports: {file_rel: ["module", ...]} from
                      ``from module import *`` (dotted module form).
    """
    star_imports = star_imports or {}
    result: list[dict[str, Any]] = []
    for edge in all_edges:
        if edge.get("kind") != "call":
            result.append(edge)
            continue

        dst: str = edge["dst"]

        # Attribute calls (obj.method, b1.process) — keep unchanged.
        if "." in dst:
            result.append(edge)
            continue

        # Bare-name call — determine the caller file.
        src: str = edge["src"]
        caller_file = src.split(":")[0]  # "a.py:runner" → "a.py"

        # --- Cross-language guard: non-Python callers pass through verbatim ---
        # Python name-resolution rules below must never rewrite or suppress a
        # call edge originating in a tree-sitter language (Go/JS/TS/Rust/Java).
        if not caller_file.endswith(".py"):
            result.append(edge)
            continue

        # Only Python definitions are valid bind targets — a bare Python call
        # must never resolve to a .go/.ts/... homonym.
        defining_files = [f for f in definitions.get(dst, []) if f.endswith(".py")]

        # --- Rule 0: local-definition shadowing (caller's own module wins) ---
        if caller_file in defining_files:
            # Python resolves a bare name to the caller's own module-level
            # definition before any import. Keep the edge bare (same-module);
            # it is never rewritten to or suppressed by an external homonym.
            result.append(edge)
            continue

        # --- Rule 1: explicit import binding ---
        bindings = import_bindings.get(caller_file, {})
        if dst in bindings:
            result.append({**edge, "dst": bindings[dst]})
            continue

        # --- Rule 2: star import (`from mod import *`) ---
        caller_stars = star_imports.get(caller_file, [])
        if caller_stars:
            # A defining file is reachable via a star import when its dotted
            # module matches one of the caller's star-imported modules.
            star_matches = [
                file_to_module(f)
                for f in defining_files
                if f != caller_file and file_to_module(f) in caller_stars
            ]
            if len(star_matches) == 1:
                result.append({**edge, "dst": f"{star_matches[0]}.{dst}"})
                continue
            if len(star_matches) > 1:
                # Several star-imported modules define it → ambiguous, suppress.
                continue
            # No star module defines it → fall through to the remaining rules.

        # --- Rule 3: unique project-wide fallback ---
        external_files = [f for f in defining_files if f != caller_file]
        if len(external_files) == 1:
            # Unique external definition — keep, bound to the dotted module form.
            result.append({**edge, "dst": f"{file_to_module(external_files[0])}.{dst}"})
            continue
        if external_files:
            # --- Rule 4: multiple external definitions, none resolved → suppress.
            continue

        # No external definitions — keep the edge as-is (same-module or
        # stdlib/third-party call that has no node in the graph).
        result.append(edge)

    return result
