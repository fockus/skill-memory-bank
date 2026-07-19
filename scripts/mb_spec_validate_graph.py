"""Blocked-by dependency graph gates for mb-spec-validate.sh (REQ-052 / C8.5).

Split out of mb_spec_validate_v2.py so both stay <=400 lines (S2 review [24]).
Owns everything that reasons about task DEPENDENCIES: resolving a sibling
spec's task numbers, reading its own Blocked-by edges, and the combined
local + cross-spec cycle search.

`check_graph(tasks, this_topic, specs_root, emit)` runs the whole gate; the
caller supplies the emit callback so violation formatting stays in one place.

Local edges naming a task that does not exist are reported instead of being
skipped, and cross-spec edges take part in the SAME cycle search as local ones
(review [14]/[15]): a#1 -> b#1 -> a#1 is a deadlock the validator must catch.
"""

from __future__ import annotations

import os
import re


def _read(p: str) -> str:
    return open(p, encoding="utf-8").read() if p and os.path.exists(p) else ""


def task_nums(topic: str, specs_root: str, _cache: dict | None = None) -> set[str] | None:
    """Task numbers declared by a sibling spec, or None when it does not exist."""
    p = os.path.join(specs_root, topic, "tasks.md")
    if not specs_root or not os.path.exists(p):
        return None
    return set(re.findall(r"<!--\s*mb-task:(\d+)\s*-->", _read(p)))


def blocked_by_of(topic: str, specs_root: str) -> dict[str, list[str]]:
    """`<topic>#<n>` -> its own Blocked-by edges, for cross-spec cycle search."""
    text = _read(os.path.join(specs_root, topic, "tasks.md"))
    if not text:
        return {}
    edges: dict[str, list[str]] = {}
    cur = None
    for ln in text.splitlines():
        m = re.match(r"<!--\s*mb-task:(\d+)\s*-->", ln.strip())
        if m:
            cur = f"{topic}#{m.group(1)}"
            edges.setdefault(cur, [])
            continue
        if cur and ln.strip().startswith("**Blocked-by:**"):
            for raw in ln.split(":**", 1)[1].split(","):
                dep = raw.strip().strip("`")
                # `none` is the grammar's explicit "no dependencies" literal, not
                # a task named none. The local branch in check_graph already
                # drops it (it is not a digit); without the same filter here it
                # became a phantom `<topic>#none` node, which stayed invisible
                # only because the DFS skipped unknown nodes (review [5]).
                if dep and dep.lower() != "none":
                    edges[cur].append(dep if "#" in dep else f"{topic}#{dep}")
    return edges


def check_graph(tasks: list[dict], this_topic: str, specs_root: str, emit) -> None:
    """Report unresolved local Blocked-by refs and any dependency cycle."""
    local_nums = {str(t["item_no"]) for t in tasks}
    graph: dict[str, list[str]] = {}
    for t in tasks:
        deps: list[str] = []
        for b in t.get("blocked_by", []):
            b = str(b)
            if "#" in b:
                deps.append(b)
            elif b.isdigit():
                if b not in local_nums:
                    emit(
                        f"REQ-052: task {t['item_no']} Blocked-by '{b}' — no such task in this spec"
                    )
                    continue
                deps.append(f"{this_topic}#{b}")
        graph[f"{this_topic}#{t['item_no']}"] = deps

    # Pull in reachable cross-spec nodes so a cycle spanning specs is visible.
    seen = {this_topic}
    frontier = [d for deps in graph.values() for d in deps if d.split("#", 1)[0] != this_topic]
    while frontier:
        topic = frontier.pop().split("#", 1)[0]
        if topic in seen:
            continue
        seen.add(topic)
        for node, deps in blocked_by_of(topic, specs_root).items():
            graph.setdefault(node, deps)
            frontier.extend(d for d in deps if d.split("#", 1)[0] not in seen)

    # Every reachable dependency must EXIST before the cycle search runs. The
    # DFS below skips nodes absent from the graph (`if v not in graph`), so a
    # dangling cross-spec ref — alpha#1 → beta#1 → ghost#1 — used to validate
    # clean: the missing topic was simply never visited (review [5]). Local
    # refs are already reported above; this covers the cross-spec ones,
    # including those pulled in transitively.
    for node in sorted(graph):
        for dep in graph[node]:
            if dep in graph:
                continue
            dep_topic, _, dep_no = dep.partition("#")
            if dep_topic == this_topic:
                continue  # already reported as a local unresolved ref
            known = blocked_by_of(dep_topic, specs_root)
            if not known:
                emit(
                    f"REQ-052: {node} Blocked-by '{dep}' — spec topic '{dep_topic}' not found under {specs_root or 'specs/'}"
                )
            else:
                emit(f"REQ-052: {node} Blocked-by '{dep}' — no task {dep_no} in spec '{dep_topic}'")

    color: dict[str, int] = {n: 0 for n in graph}
    found: list[str] | None = None

    def dfs(u: str, stack: list[str]) -> bool:
        nonlocal found
        color[u] = 1
        stack.append(u)
        for v in graph.get(u, []):
            if v not in graph:
                continue
            if color.get(v) == 1:
                found = stack[stack.index(v) :] + [v]
                return True
            if color.get(v, 0) == 0 and dfs(v, stack):
                return True
        color[u] = 2
        stack.pop()
        return False

    for n in list(graph):
        if color.get(n, 0) == 0 and dfs(n, []):
            break
    if found:
        # A cycle confined to this spec prints bare task numbers (the
        # long-standing message contract); a cross-spec one prints `<topic>#<n>`.
        path = found
        if all(n.split("#", 1)[0] == this_topic for n in path):
            path = [n.split("#", 1)[1] for n in path]
        emit("REQ-052: Blocked-by cycle: " + " -> ".join(path))
