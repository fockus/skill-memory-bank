"""Markdown renderers for Memory Bank graph query results."""

from __future__ import annotations

from pathlib import Path

from mb_graph_query_core import JsonObj, find_tests, impact_payload, resolve_target


def markdown_explain(payload: JsonObj) -> str:
    query = payload.get("query", {})
    title = query.get("symbol") or query.get("file") or "graph target"
    lines = ["# Graph explanation", "", f"Target: `{title}`", ""]
    if not payload.get("ok"):
        lines.append(f"No graph match: `{payload.get('error', 'unknown')}`")
        lines.append("")
        return "\n".join(lines)

    matches = payload.get("matches", [])
    if matches:
        lines.extend(["## Matches", ""])
        for node in matches:
            lines.append(
                f"- `{node.get('name')}` ({node.get('kind')}) — {node.get('file')}:{node.get('line')}"
            )
        lines.append("")

    for section, key in (
        ("Incoming", "incoming"),
        ("Outgoing", "outgoing"),
        ("Dependents", "dependents"),
        ("Dependencies", "dependencies"),
    ):
        edges = payload.get(key, [])
        if not edges:
            continue
        lines.extend([f"## {section}", ""])
        for edge in edges:
            lines.append(f"- {edge.get('kind')}: `{edge.get('src')}` → `{edge.get('dst')}`")
        lines.append("")

    test_files = payload.get("test_files", [])
    if test_files:
        lines.extend(["## Tests", ""])
        for test_file in test_files:
            lines.append(f"- `{test_file}`")
        lines.append("")
    return "\n".join(lines)


def render_graph_summary(nodes: list[JsonObj], edges: list[JsonObj]) -> str:
    lines = [
        "# Graph Summary",
        "",
        "Semantic-friendly summary generated from `.memory-bank/codebase/graph.json`.",
        "",
        f"- Nodes: {len(nodes)}",
        f"- Edges: {len(edges)}",
        "",
        "## Symbols",
        "",
    ]
    for node in sorted(
        nodes, key=lambda item: (str(item.get("file", "")), str(item.get("name", "")))
    ):
        lines.append(
            f"- `{node.get('name')}` ({node.get('kind')}) — {node.get('file')}:{node.get('line')}"
        )
    lines.append("")
    return "\n".join(lines)


def render_impact_map(nodes: list[JsonObj], edges: list[JsonObj]) -> str:
    lines = ["# Impact Map", "", "Structural dependencies extracted from the code graph.", ""]
    for node in sorted(nodes, key=lambda item: str(item.get("name", ""))):
        name = str(node.get("name", ""))
        file_name = str(node.get("file", ""))
        payload = impact_payload(nodes, edges, name, None)
        if not payload.get("ok"):
            continue
        deps = payload.get("dependencies", [])
        dependents = payload.get("dependents", [])
        if not deps and not dependents:
            continue
        lines.append(f"## `{name}` — {file_name}:{node.get('line')}")
        if deps:
            lines.append(
                "- Dependencies: " + ", ".join(f"`{edge.get('dst')}`" for edge in deps[:10])
            )
        if dependents:
            lines.append(
                "- Dependents: " + ", ".join(f"`{edge.get('src')}`" for edge in dependents[:10])
            )
        lines.append("")
    return "\n".join(lines)


def render_test_links(nodes: list[JsonObj], edges: list[JsonObj]) -> str:
    lines = ["# Test Links", "", "Best-effort test coverage links from graph edges.", ""]
    emitted = False
    for node in sorted(nodes, key=lambda item: str(item.get("name", ""))):
        name = str(node.get("name", ""))
        matches, target_names, target_files = resolve_target(nodes, symbol=name, file_name=None)
        test_files = find_tests(edges, target_names, target_files)
        if not matches or not test_files:
            continue
        emitted = True
        lines.append(f"## `{name}`")
        for test_file in test_files:
            lines.append(f"- `{test_file}`")
        lines.append("")
    if not emitted:
        lines.append("No structural test links found.")
        lines.append("")
    return "\n".join(lines)


def write_summary_files(nodes: list[JsonObj], edges: list[JsonObj], out_dir: Path) -> list[str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    outputs = {
        "GRAPH_SUMMARY.md": render_graph_summary(nodes, edges),
        "IMPACT_MAP.md": render_impact_map(nodes, edges),
        "TEST_LINKS.md": render_test_links(nodes, edges),
    }
    written: list[str] = []
    for name, content in outputs.items():
        target = out_dir / name
        target.write_text(content, encoding="utf-8")
        written.append(str(target))
    return written
