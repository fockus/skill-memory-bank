"""Regex-based Bash / Bats extractor for the Memory Bank code graph.

Always available (stdlib ``re`` only), exactly like the Python ``ast`` extractor
in ``codegraph_python`` — no opt-in flag, no new dependency. Emits the canonical
schema shared with every other extractor::

    nodes: {kind: module|function, name, file, line}
    edges: {src, dst, kind: import|call}

``.sh``
    * ``module`` node per file;
    * ``function`` node per ``name() {`` / ``function name {`` definition;
    * ``import`` edge for ``source|. <path>`` and for every other ``*.sh`` path
      mentioned in code (``bash "$SCRIPT_DIR/x.sh"``);
    * ``call`` edge for a command-position token that names a function of the
      same file or of a (transitively) sourced file.

``.bats``
    * ``module`` node per file;
    * ``function`` node per ``@test "…"`` (plus plain ``setup()``-style defs);
    * ``import`` edge per ``*.sh`` path mentioned and per ``load '<helper>'``.

Two-phase, like the Python extractor: ``parse_file`` is pure and file-local and
emits *raw* destinations; ``bind_shell_edges`` runs once in the orchestrator when
every file is known and (a) resolves path destinations against the files actually
walked (``"$REPO_ROOT/scripts/x.sh"`` → ``scripts/x.sh``) and (b) drops call
candidates that do not name a reachable function — so a bare ``grep`` or a
homonymous ``usage`` in an unrelated script never becomes an edge.

tree-sitter-bash is deliberately not used: regexes cover definitions, sourcing
and command-position calls, which is what the graph queries need. Upgrade path
if nested constructs ever matter: add ``.sh`` to ``codegraph_treesitter.LANG_CONFIG``.
"""

from __future__ import annotations

import re
from collections import deque
from pathlib import Path
from typing import Any

from memory_bank_skill.codegraph_common import rel, sha256

__all__ = ["SHELL_EXTS", "bind_shell_edges", "parse_file"]

# Extensions owned by this extractor (dispatch key in the orchestrator).
SHELL_EXTS = frozenset({".sh", ".bats"})

_IDENT = r"[A-Za-z_][A-Za-z0-9_:.-]*"

# `name() {`  /  `function name {`  /  `function name() {`
_FUNC_RE = re.compile(
    rf"^(?P<indent>[ \t]*)"
    rf"(?:function[ \t]+(?P<fname>{_IDENT})[ \t]*(?:\([ \t]*\)[ \t]*)?\{{"
    rf"|(?P<pname>{_IDENT})[ \t]*\([ \t]*\)[ \t]*\{{?)"
)
_BATS_TEST_RE = re.compile(r"^[ \t]*@test[ \t]+(?P<q>['\"])(?P<name>.*?)(?P=q)[ \t]*\{")
_SOURCE_RE = re.compile(r"^[ \t]*(?:source|\.)[ \t]+(?P<path>\S+)")
_LOAD_RE = re.compile(r"^[ \t]*load[ \t]+(?P<path>\S+)")
_SH_PATH_RE = re.compile(r"[\w$./{}-]*[\w}]\.sh\b")
# Command position: line start, a shell operator, or a keyword that introduces a
# command list. Good enough for `x="$(f)"`, `f || g`, `if f; then`.
_CALL_RE = re.compile(
    rf"(?:^|\$\(|[;&|(){{}}`!]|\b(?:then|else|elif|do|if|while|until|not)\b)"
    rf"[ \t]*(?P<name>{_IDENT})"
)
_HEREDOC_RE = re.compile(r"<<-?[ \t]*(?P<q>['\"]?)(?P<tag>[A-Za-z_][A-Za-z0-9_]*)(?P=q)")


def _strip_comment(line: str) -> str:
    """Drop a ``#`` comment. ``${x#y}`` is safe (``#`` not preceded by space)."""
    for i, ch in enumerate(line):
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i]
    return line


def _unquote(token: str) -> str:
    return token.strip().strip("\"'")


def _norm_load_target(arg: str, file_rel: str) -> str:
    """``load 'lib/assert'`` in ``tests/bats/x.bats`` → ``tests/bats/lib/assert.bash``."""
    target = _unquote(arg)
    if not target:
        return ""
    if "." not in target.rsplit("/", 1)[-1]:
        target += ".bash"
    parent = file_rel.rsplit("/", 1)[0] if "/" in file_rel else ""
    return f"{parent}/{target}" if parent and not target.startswith("/") else target


class _Scopes:
    """Innermost open function for call attribution.

    ponytail: a scope closes at the first ``}`` indented like its ``def`` line.
    Non-standard layouts just fall back to file-level attribution — never a wrong
    function, only a coarser one.
    """

    def __init__(self) -> None:
        self._stack: list[tuple[str, str]] = []  # (indent, name)

    def open(self, indent: str, name: str) -> None:
        self._stack.append((indent, name))

    def close_at(self, line: str) -> None:
        while self._stack:
            indent, _ = self._stack[-1]
            if re.match(rf"^{re.escape(indent)}\}}", line):
                self._stack.pop()
                return
            if len(line) - len(line.lstrip(" \t")) < len(indent):
                self._stack.pop()  # dedented past the def — scope cannot still be open
                continue
            return

    def current(self) -> str:
        return self._stack[-1][1] if self._stack else ""


def parse_file(path: Path, src_root: Path, include_docs: bool = False) -> dict[str, Any]:
    """Parse one ``.sh``/``.bats`` file → ``{nodes, edges, hash, file}``.

    Raises ``UnicodeDecodeError`` when the file is not UTF-8 text (the
    orchestrator turns that into a warning and keeps going). ``include_docs`` is
    accepted for signature parity with the other extractors; shell files carry no
    structured docstrings, so it is intentionally a no-op.
    """
    text = path.read_text(encoding="utf-8")
    file_rel = rel(path, src_root)
    is_bats = path.suffix.lower() == ".bats"

    nodes: list[dict[str, Any]] = [
        {"kind": "module", "name": file_rel, "file": file_rel, "line": 1}
    ]
    edges: list[dict[str, Any]] = []
    defined: set[str] = set()
    scopes = _Scopes()
    heredoc_tag: str | None = None

    def add_import(dst: str, via: str) -> None:
        if dst:
            edges.append({"src": file_rel, "dst": dst, "kind": "import", "via": via})

    for lineno, raw_line in enumerate(text.splitlines(), 1):
        if heredoc_tag is not None:
            if raw_line.strip() == heredoc_tag:
                heredoc_tag = None
            continue
        line = _strip_comment(raw_line)
        opener = _HEREDOC_RE.search(line)

        scopes.close_at(line)

        bats_test = _BATS_TEST_RE.match(line) if is_bats else None
        func = None if bats_test else _FUNC_RE.match(line)
        if bats_test or func:
            name = (
                bats_test.group("name")
                if bats_test
                else (func.group("fname") or func.group("pname"))
            )
            indent = "" if bats_test else func.group("indent")
            nodes.append({"kind": "function", "name": name, "file": file_rel, "line": lineno})
            defined.add(name)
            body = line[(bats_test or func).end() :]
            if "{" in line and "}" not in body:  # one-liner `f() { …; }` opens nothing
                scopes.open(indent, name)
        else:
            source = _SOURCE_RE.match(line)
            if is_bats and (load := _LOAD_RE.match(line)) is not None:
                add_import(_norm_load_target(load.group("path"), file_rel), "load")
            # Take the path from the `*.sh` literal, not from the first token:
            # `source "$(dirname "$0")/_lib.sh"` has a space inside the command
            # substitution, so a `\S+` capture would stop at `"$(dirname`.
            paths = [_unquote(m.group(0)) for m in _SH_PATH_RE.finditer(line)]
            for found in paths:
                add_import(found, "source" if source else "invoke")
            if source and not paths:  # e.g. `. /etc/os-release` — no .sh literal
                add_import(_unquote(source.group("path")), "source")
            for match in _CALL_RE.finditer(line):
                scope = scopes.current()
                edges.append(
                    {
                        "src": f"{file_rel}:{scope}" if scope else file_rel,
                        "dst": match.group("name"),
                        "kind": "call",
                    }
                )

        if opener:
            heredoc_tag = opener.group("tag")

    return {
        "nodes": nodes,
        "edges": edges,
        "hash": sha256(text),
        "file": file_rel,
        # Function names defined here — consumed by bind_shell_edges.
        "shell_defs": sorted(defined),
    }


# ── binding pass (orchestrator, once all files are known) ────────────────────


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
