#!/usr/bin/env python3
"""Multi-language code graph builder for Memory Bank (orchestrator).

Usage:
    mb-codegraph.py [--dry-run|--apply] [--cochange] [mb_path] [src_root]

Walks ``src_root`` and extracts functions/classes/imports/calls/inherits,
builds a graph, writes outputs (``--apply`` only):

  * ``<mb>/codebase/graph.json`` — JSON Lines (one node/edge per line)
  * ``<mb>/codebase/god-nodes.md`` — degree-ranked hubs + analytics
  * ``<mb>/codebase/.cache/<file-slug>.json`` — per-file SHA256 → parsed entities

Extraction engines live in the ``memory_bank_skill`` package:
  * ``codegraph_python``      — Python via stdlib ``ast`` (always on)
  * ``codegraph_treesitter``  — Go/JS/TS/Rust/Java via tree-sitter (opt-in extras)
  * ``codegraph_analytics``   — degree split, communities, betweenness, render
  * ``codegraph_cochange``    — git co-change file edges (opt-in via ``--cochange``)

Incremental: files whose SHA256 matches cache are skipped (summary reports
``reparsed=N cached=M``). Default output (no extra flags) is byte-identical
across releases — every new capability is opt-in.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def _generated_at_now() -> str:
    """Return the ``generated_at`` timestamp for a fresh build.

    Honours the reproducible-builds convention ``SOURCE_DATE_EPOCH``: when set
    to a valid integer (Unix seconds), it is used instead of the wall clock so
    two builds of the same inputs produce byte-identical ``graph.json`` output
    (tests set it explicitly instead of racing the real clock). Unset is the
    normal case (real wall clock); a malformed value falls back to the wall
    clock rather than crashing.
    """
    raw = os.environ.get("SOURCE_DATE_EPOCH")
    if raw is not None:
        try:
            epoch = int(raw)
        except ValueError:
            epoch = None
        if epoch is not None:
            return datetime.fromtimestamp(epoch, tz=UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


try:
    from memory_bank_skill import codegraph_analytics as cga
    from memory_bank_skill import codegraph_cochange as cgco
    from memory_bank_skill import codegraph_python as cgpy
    from memory_bank_skill import codegraph_questions as cgq
    from memory_bank_skill import codegraph_sessions as cgs
    from memory_bank_skill import codegraph_treesitter as cgts
    from memory_bank_skill._io import atomic_write
    from memory_bank_skill.codegraph_common import rel, sha256
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill import codegraph_analytics as cga
    from memory_bank_skill import codegraph_cochange as cgco
    from memory_bank_skill import codegraph_python as cgpy
    from memory_bank_skill import codegraph_questions as cgq
    from memory_bank_skill import codegraph_sessions as cgs
    from memory_bank_skill import codegraph_treesitter as cgts
    from memory_bank_skill._io import atomic_write
    from memory_bank_skill.codegraph_common import rel, sha256

# ── Back-compat re-exports (loaded via spec_from_file_location in tests) ──
parse_file = cgpy.parse_file
HAS_TREE_SITTER = cgts.HAS_TREE_SITTER
_get_ts_parser = cgts.get_ts_parser


def _cache_slug(rel_path: str) -> str:
    return sha256(rel_path)[:16]


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


def _filter_gitignored(files: list[Path], src_root: Path) -> list[Path]:
    """Drop files matched by .gitignore via `git check-ignore --stdin`.

    Single git subprocess per call — accurate and fast. Graceful no-op when
    src_root is outside a git repo, when git binary is missing, or on any
    subprocess error. Files outside the discovered git toplevel are kept.
    """
    if not files:
        return files
    try:
        toplevel = subprocess.run(
            ["git", "-C", str(src_root), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if toplevel.returncode != 0:
            return files
        git_root = Path(toplevel.stdout.strip())
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return files

    rel_inputs: list[str] = []
    for f in files:
        try:
            rel_inputs.append(str(f.resolve().relative_to(git_root.resolve())))
        except ValueError:
            rel_inputs.append("")  # outside git_root — kept unconditionally

    payload = "\n".join(p for p in rel_inputs if p)
    if not payload:
        return files
    try:
        check = subprocess.run(
            ["git", "-C", str(git_root), "check-ignore", "--stdin"],
            input=payload,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return files

    # `git check-ignore` exits 0 if any matched, 1 if none, 128 on error.
    if check.returncode not in (0, 1):
        return files

    ignored = set(check.stdout.splitlines())
    return [
        f
        for f, rel_path in zip(files, rel_inputs, strict=True)
        if not rel_path or rel_path not in ignored
    ]


def build_graph(
    src_root: Path,
    cache_dir: Path | None = None,
    include_docs: bool = False,
) -> dict[str, Any]:
    """Walk src_root, parse each supported file, aggregate nodes+edges.

    If cache_dir provided: skip re-parse when file hash AND docs-mode AND
    cache_version all match; any mismatch forces a re-parse.
    ``include_docs`` (opt-in) emits optional ``doc``/``signature`` node fields.
    Returns aggregated {"nodes": [...], "edges": [...], "reparsed": N, "cached": M}.

    After all files are parsed, import-aware call resolution is applied via
    ``cgpy.bind_calls``: bare-name cross-module calls are resolved against the
    per-file import map; ambiguous unimported homonyms are suppressed.
    """
    all_nodes: list[dict[str, Any]] = []
    all_edges: list[dict[str, Any]] = []
    # per-file import bindings: {file_rel: {local_name: "mod.symbol"}}
    all_import_bindings: dict[str, dict[str, str]] = {}
    # per-file star imports: {file_rel: ["module", ...]} from `from mod import *`
    all_star_imports: dict[str, list[str]] = {}
    reparsed = 0
    cached = 0

    if not src_root.exists():
        return {"nodes": [], "edges": [], "reparsed": 0, "cached": 0}

    # Collect all files: Python via `ast` + tree-sitter-supported types if installed.
    supported_exts = {".py"}
    if cgts.HAS_TREE_SITTER:
        supported_exts.update(cgts.LANG_CONFIG.keys())

    all_source_files: list[Path] = []
    for ext in sorted(supported_exts):
        all_source_files.extend(src_root.rglob(f"*{ext}"))
    all_source_files = sorted(set(all_source_files))
    all_source_files = _filter_gitignored(all_source_files, src_root)

    for src_file in all_source_files:
        # Skip hidden dirs (like .venv, __pycache__, node_modules)
        try:
            parts = src_file.relative_to(src_root).parts
        except ValueError:
            continue
        skip_dirs = {".venv", "__pycache__", "node_modules", ".git", "target", "dist", "build"}
        if any(p.startswith(".") or p in skip_dirs for p in parts[:-1]):
            continue

        rel_path = rel(src_file, src_root)
        ext = src_file.suffix.lower()
        try:
            if ext == ".py":
                text = src_file.read_text(encoding="utf-8")
                content_hash = sha256(text)
            else:
                content_hash = sha256(src_file.read_bytes().decode("utf-8", errors="replace"))
        except (OSError, UnicodeDecodeError):
            continue

        # Cache check: hash AND docs-mode AND cache_version must all match.
        if cache_dir is not None:
            cached_data = _load_cache(cache_dir, rel_path)
            if (
                cached_data
                and cached_data.get("hash") == content_hash
                and bool(cached_data.get("docs", False)) == include_docs
                and cached_data.get("cache_version") == cgpy.CACHE_VERSION
            ):
                all_nodes.extend(cached_data.get("nodes", []))
                all_edges.extend(cached_data.get("edges", []))
                # Restore import_bindings from cache (needed for bind_calls pass)
                file_bindings = cached_data.get("import_bindings")
                if isinstance(file_bindings, dict):
                    all_import_bindings[rel_path] = file_bindings
                file_stars = cached_data.get("star_imports")
                if isinstance(file_stars, list):
                    all_star_imports[rel_path] = file_stars
                cached += 1
                continue

        # Dispatch parser
        try:
            if ext == ".py":
                result = cgpy.parse_file(src_file, src_root, include_docs=include_docs)
            elif ext in cgts.LANG_CONFIG and cgts.HAS_TREE_SITTER:
                lang_name, module_name = cgts.LANG_CONFIG[ext]
                result = cgts.parse_ts_file(
                    src_file, src_root, lang_name, module_name, include_docs=include_docs
                )
            else:
                continue
        except SyntaxError as e:
            print(f"[warn] {rel_path}: syntax error skipped — {e.msg}", file=sys.stderr)
            continue
        except Exception as e:  # noqa: BLE001 — robust batch
            print(f"[warn] {rel_path}: parse failed — {e}", file=sys.stderr)
            continue

        all_nodes.extend(result["nodes"])
        all_edges.extend(result["edges"])
        # Collect per-file import bindings for the bind_calls pass
        file_bindings = result.get("import_bindings")
        if isinstance(file_bindings, dict):
            all_import_bindings[rel_path] = file_bindings
        file_stars = result.get("star_imports")
        if isinstance(file_stars, list):
            all_star_imports[rel_path] = file_stars
        reparsed += 1

        if cache_dir is not None:
            result["docs"] = include_docs  # stamp docs-mode so a flag toggle re-parses
            result["cache_version"] = cgpy.CACHE_VERSION
            _save_cache(cache_dir, rel_path, result)

    # ── Import-aware call resolution (Python files only) ──────────────────────
    # Build the unique-fallback candidate map: bare_name → [file_rel, ...].
    # Constraints (so the fallback never invents a false edge):
    #   * function/class nodes only (never modules);
    #   * Python files only — a Python bare call must never bind to a
    #     Go/JS/TS/Rust/Java homonym (design.md § A2 — Python-first);
    #   * MODULE-LEVEL definitions only (I-066): a node whose qualified ``name``
    #     contains a dot is a class method (``Worker.process``) or a nested
    #     function (``outer.helper``) — neither is reachable by a bare unqualified
    #     call, so including it would let the unique-fallback bind to a method /
    #     nested def that merely happens to be the only one of that name.
    definitions: dict[str, list[str]] = {}
    for node in all_nodes:
        if node.get("kind") not in ("function", "class"):
            continue
        file_rel = node.get("file", "")
        if not file_rel.endswith(".py"):
            continue
        name: str = node.get("name", "")
        # Skip non-module-level definitions: a dotted qualname is a method or a
        # nested function and must never seed the bare-name fallback set.
        if "." in name:
            continue
        if name:
            definitions.setdefault(name, [])
            if file_rel and file_rel not in definitions[name]:
                definitions[name].append(file_rel)

    all_edges = cgpy.bind_calls(all_edges, all_import_bindings, definitions, all_star_imports)

    return {"nodes": all_nodes, "edges": all_edges, "reparsed": reparsed, "cached": cached}


def _render_god_nodes(
    graph: dict[str, Any],
    communities: dict[str, int] | None = None,
    betweenness: dict[str, float] | None = None,
    cochange_edges: list[dict[str, Any]] | None = None,
    questions: list[dict[str, Any]] | None = None,
    pagerank: dict[str, float] | None = None,
) -> str:
    """Delegate to analytics renderer; append co-change / questions sections when present."""
    body = cga.render_god_nodes_md(graph, communities, betweenness, pagerank=pagerank)
    if cochange_edges:
        body = body.rstrip("\n") + "\n\n" + cgco.render_cochange_section(cochange_edges) + "\n"
    if questions:
        body = body.rstrip("\n") + "\n\n" + cgq.render_questions_md(questions) + "\n"
    return body


def _git_head_commit(src_root: Path) -> str | None:
    """Return the short HEAD commit of ``src_root``'s repo, or ``None``.

    Fail-open (mirrors the ``rev-parse --show-toplevel`` guard): detached HEAD,
    no commits yet, git missing, or src outside a repo all degrade to ``None`` so
    freshness falls back to age-only. Never raises, never prints git noise.
    """
    try:
        result = subprocess.run(
            ["git", "-C", str(src_root), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return None
    if result.returncode != 0:
        return None
    commit = result.stdout.strip()
    return commit[:12] if commit else None


def _write_graph_jsonl(
    graph: dict[str, Any],
    target: Path,
    communities: dict[str, int] | None = None,
    node_attrs: list[dict[str, Any]] | None = None,
    meta: dict[str, Any] | None = None,
) -> None:
    communities = communities or {}
    lines: list[str] = []
    # Always-on ``meta`` freshness row (PREPENDED, first line). Additive +
    # backward-compatible: every reader filters by row ``type``, so node/edge
    # bytes after it are unchanged. Freshness must exist on every graph.
    if meta is not None:
        lines.append(json.dumps(meta, ensure_ascii=False))
    for n in graph["nodes"]:
        record = {"type": "node", **n}
        cid = communities.get(n.get("file", ""))
        if cid is not None:
            record["community"] = cid
        lines.append(json.dumps(record, ensure_ascii=False))
    for e in graph["edges"]:
        lines.append(json.dumps({"type": "edge", **e}, ensure_ascii=False))
    # Additive ``node-attr`` rows (e.g. churn_30d) — a new, opt-in row type that
    # existing consumers ignore. Default build emits none → byte-identical.
    for a in node_attrs or []:
        lines.append(json.dumps(a, ensure_ascii=False))
    atomic_write(target, "\n".join(lines) + "\n")


def _apply_session_layer(mb: Path, graph: dict[str, Any], summary: dict[str, Any]) -> None:
    """Merge the ``--sessions`` layer into ``graph`` in place (apply-mode only).

    Adds ``session`` nodes + ``worked_on`` edges and appends each session summary
    to the touched ``module`` node's ``doc`` (so it feeds the embedding corpus).
    Heavy lifting + redaction lives in ``codegraph_sessions``; this keeps the
    orchestrator thin.
    """
    module_files = {
        n["file"] for n in graph["nodes"] if n.get("kind") == "module" and n.get("file")
    }
    layer = cgs.extract_session_layer(mb, module_files)
    if not layer.nodes:
        summary["session_nodes"] = 0
        summary["worked_on_edges"] = 0
        print("session_nodes=0")
        print("worked_on_edges=0")
        return
    # Append summaries to the matching module node's doc field.
    for node in graph["nodes"]:
        if node.get("kind") != "module":
            continue
        appends = layer.doc_appends.get(node.get("file", ""))
        if not appends:
            continue
        suffix = " | ".join(appends)
        node["doc"] = f"{node['doc']} | {suffix}" if node.get("doc") else suffix
    graph["nodes"].extend(layer.nodes)
    graph["edges"].extend(layer.edges)
    summary["session_nodes"] = len(layer.nodes)
    summary["worked_on_edges"] = len(layer.edges)
    print(f"session_nodes={len(layer.nodes)}")
    print(f"worked_on_edges={len(layer.edges)}")


def run(
    *,
    mb_path: str,
    src_root: str,
    mode: str = "dry-run",
    cochange: bool = False,
    questions: bool = False,
    docs: bool = False,
    sessions: bool = False,
) -> dict[str, Any]:
    """Build graph, optionally write outputs. Returns summary dict.

    ``docs`` (opt-in) enriches function/class/module nodes with ``doc``/``signature``.
    ``sessions`` (opt-in) bridges ``session/*.md`` work history into the graph as
    ``session`` nodes + ``worked_on`` edges and module ``doc`` appends. All
    session-derived strings are secret-redacted and ``<private>``-stripped at
    write time (privacy: ``graph.json`` is committable). Base output without the
    flag is byte-identical.
    """
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

    graph = build_graph(src, cache_dir, include_docs=docs)
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

    # Opt-in: append git co-change file edges + per-file churn attrs
    # (deterministic, $0, single git pass). Default off keeps graph.json
    # byte-identical.
    cochange_edges: list[dict[str, Any]] = []
    churn_attrs: list[dict[str, Any]] = []
    if cochange:
        known_files = {n["file"] for n in graph["nodes"] if n.get("file")}
        cochange_edges, churn_attrs = cgco.co_change_and_churn(src, known_files)
        graph["edges"].extend(cochange_edges)
        summary["cochange_edges"] = len(cochange_edges)
        summary["churn_files"] = len(churn_attrs)
        print(f"cochange_edges={len(cochange_edges)}")
        print(f"churn_files={len(churn_attrs)}")

    # Structural analytics run on the CODE graph (base + co-change). Co-change
    # edges are module↔module, so they legitimately shape communities/centrality;
    # the session layer (session↔module) is applied later so work history never
    # skews structural god-node ranking.
    communities = cga.detect_communities(graph)
    betweenness = cga.file_betweenness(graph)
    pagerank = cga.compute_pagerank(graph)
    community_count = len(set(communities.values())) if communities else 0
    summary["communities"] = community_count
    print(f"communities={community_count}")

    # Opt-in: deterministic suggested questions ($0). Default off keeps god-nodes.md
    # byte-identical.
    suggested: list[dict[str, Any]] | None = None
    if questions:
        suggested = cgq.suggest_questions(graph, communities=communities, betweenness=betweenness)
        summary["questions"] = len(suggested)
        print(f"questions={len(suggested)}")

    # Render god-nodes.md from the structural graph BEFORE the session layer, so a
    # busy session never appears as a structural god-node (work history ≠ code
    # structure). graph.json (written below) still carries the session rows.
    god_nodes_md = _render_god_nodes(
        graph, communities, betweenness, cochange_edges, suggested, pagerank
    )

    # Opt-in: bridge session work-history into the graph (session nodes +
    # worked_on edges + module doc appends) as the LAST mutation — after analytics
    # and god-node rendering — so it enriches graph.json's embedding corpus without
    # skewing structural ranking. All session-derived strings are secret-redacted
    # and <private>-stripped (graph.json is committable). Default off keeps
    # graph.json byte-identical.
    if sessions:
        _apply_session_layer(mb, graph, summary)

    meta = {
        "type": "meta",
        "schema": 1,
        "generated_at": _generated_at_now(),
        "commit": _git_head_commit(src),
        "nodes": len(graph["nodes"]),
        "edges": len(graph["edges"]),
        "src_root": str(src),
    }
    _write_graph_jsonl(graph, codebase / "graph.json", communities, churn_attrs, meta=meta)
    atomic_write(codebase / "god-nodes.md", god_nodes_md)

    return summary


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Code graph builder for Memory Bank")
    parser.add_argument(
        "--apply", action="store_true", help="Write graph.json + god-nodes.md (default: dry-run)"
    )
    parser.add_argument("--dry-run", action="store_true", help="Stdout summary only (default)")
    parser.add_argument(
        "--cochange",
        action="store_true",
        help="Add git co-change file edges (opt-in; requires --apply)",
    )
    parser.add_argument(
        "--questions",
        action="store_true",
        help="Append deterministic suggested questions to god-nodes.md (opt-in; requires --apply)",
    )
    parser.add_argument(
        "--docs",
        action="store_true",
        help="Enrich nodes with doc/signature for richer semantic search "
        "(opt-in; changes graph.json — clears nothing, re-parses on toggle)",
    )
    parser.add_argument(
        "--sessions",
        action="store_true",
        help="Bridge session/*.md work history into the graph as session nodes + "
        "worked_on edges + module doc appends (opt-in; requires --apply). "
        "Privacy: like --cochange, this writes session-derived text into the "
        "committable graph.json — every string is secret-redacted and "
        "<private>-stripped at write time (REQ-026 defense-in-depth).",
    )
    parser.add_argument("mb_path", nargs="?", default=".memory-bank")
    parser.add_argument("src_root", nargs="?", default=".")
    args = parser.parse_args(argv[1:])

    mode = "apply" if args.apply else "dry-run"
    try:
        run(
            mb_path=args.mb_path,
            src_root=args.src_root,
            mode=mode,
            cochange=args.cochange,
            questions=args.questions,
            docs=args.docs,
            sessions=args.sessions,
        )
    except FileNotFoundError as e:
        print(f"[error] {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
