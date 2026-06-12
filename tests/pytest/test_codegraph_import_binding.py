"""Tests for import-aware call resolution in the Python extractor.

Scenarios (REQ-003, REQ-004):
  3. Ambiguous unimported call → no cross-module call edge.
  4. `from b1 import process` + call process() → exactly one edge to b1.process.

Additional cases:
  - `import x` + `x.f()` → attribute call kept (unchanged behavior).
  - `from b1 import process as proc` (as-alias) → edge to b1.process.
  - Unique project-wide fallback → edge kept even if unimported.
  - Same-module call → always kept.
  - Cache version bump → stale cache entry (old version) forces re-parse.

Resolution-correctness cases (judge fixes):
  - Local-definition shadowing: caller's own module definition wins over
    external homonyms; the call is never rewritten to / suppressed by them.
  - Relative imports honor ImportFrom.level (`from .b1 import x` in pkg/a.py
    → pkg.b1.x).
  - Star imports (`from b1 import *`) bind a bare call to the single
    star-imported module that defines it; ambiguous → suppress.
  - dst namespace is one canonical dotted module form for ALL bound calls.
"""

from __future__ import annotations

import importlib.util
import json
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CODEGRAPH_SCRIPT = REPO_ROOT / "scripts" / "mb-codegraph.py"
CODEGRAPH_PY = REPO_ROOT / "memory_bank_skill" / "codegraph_python.py"


# ── helpers ──────────────────────────────────────────────────────────────────


def _load_codegraph_module():
    spec = importlib.util.spec_from_file_location("mb_codegraph_ib", CODEGRAPH_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def cg_mod():
    if not CODEGRAPH_SCRIPT.exists():
        pytest.skip("scripts/mb-codegraph.py not found")
    return _load_codegraph_module()


@pytest.fixture
def mb_path(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    return mb


@pytest.fixture
def src_root(tmp_path: Path) -> Path:
    src = tmp_path / "src"
    src.mkdir()
    return src


def write_py(dir_path: Path, name: str, body: str) -> Path:
    f = dir_path / name
    f.write_text(textwrap.dedent(body).lstrip("\n"))
    return f


def _call_edges(graph: dict) -> list[dict]:
    return [e for e in graph["edges"] if e["kind"] == "call"]


# ── Scenario 3: ambiguous unimported → no cross-module call edge ──────────────


def test_scenario3_ambiguous_unimported_no_call_edge(cg_mod, src_root):
    """GIVEN b1.py and b2.py both defining process(), and a.py calling
    process() WITHOUT importing either; WHEN graph is built; THEN no call
    edge a→b1.process or a→b2.process exists.
    """
    write_py(src_root, "b1.py", "def process(): pass\n")
    write_py(src_root, "b2.py", "def process(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        def runner():
            process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    calls = _call_edges(graph)
    a_calls = [e for e in calls if "a.py" in e["src"]]

    cross_to_b1 = [e for e in a_calls if "b1" in e["dst"] and "process" in e["dst"]]
    cross_to_b2 = [e for e in a_calls if "b2" in e["dst"] and "process" in e["dst"]]

    assert cross_to_b1 == [], f"Expected no cross-module edge a→b1.process but got: {cross_to_b1}"
    assert cross_to_b2 == [], f"Expected no cross-module edge a→b2.process but got: {cross_to_b2}"


# ── Scenario 4: imported call binds to the imported definition ────────────────


def test_scenario4_from_import_binds_exactly_one_edge(cg_mod, src_root):
    """GIVEN a.py with `from b1 import process` and call process(); WHEN graph
    built; THEN exactly one call edge a→b1.process, none to b2.process.
    """
    write_py(src_root, "b1.py", "def process(): pass\n")
    write_py(src_root, "b2.py", "def process(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        from b1 import process

        def runner():
            process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    calls = _call_edges(graph)
    a_calls = [e for e in calls if "a.py" in e["src"]]

    to_b1_process = [e for e in a_calls if e["dst"] == "b1.process"]
    to_b2_process = [e for e in a_calls if "b2" in e["dst"] and "process" in e["dst"]]

    assert len(to_b1_process) == 1, (
        f"Expected exactly one edge a→b1.process but got: {to_b1_process}; "
        f"all a.py call edges: {a_calls}"
    )
    assert to_b2_process == [], f"Expected no edge a→b2.process but got: {to_b2_process}"


# ── `import x` + `x.f()` (attribute call) — unchanged behavior ───────────────


def test_attribute_call_unchanged_import_x_dot_f(cg_mod, src_root):
    """`import b1` followed by `b1.process()` is an attribute call — the
    existing attribute-call behavior is kept unchanged (not suppressed).
    """
    write_py(src_root, "b1.py", "def process(): pass\n")
    write_py(src_root, "b2.py", "def process(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        import b1

        def runner():
            b1.process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    calls = _call_edges(graph)
    a_calls = [e for e in calls if "a.py" in e["src"]]

    # b1.process is an Attribute node — dst is "b1.process" or similar
    attr_calls = [e for e in a_calls if "b1" in e["dst"]]
    assert len(attr_calls) >= 1, f"Expected attribute call edge involving 'b1' but got: {a_calls}"


# ── as-alias binding ──────────────────────────────────────────────────────────


def test_as_alias_binds_to_original_module(cg_mod, src_root):
    """`from b1 import process as proc` + call `proc()` → bound to b1.process."""
    write_py(src_root, "b1.py", "def process(): pass\n")
    write_py(src_root, "b2.py", "def process(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        from b1 import process as proc

        def runner():
            proc()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    calls = _call_edges(graph)
    a_calls = [e for e in calls if "a.py" in e["src"]]

    to_b1_process = [e for e in a_calls if e["dst"] == "b1.process"]
    to_b2 = [e for e in a_calls if "b2" in e["dst"]]

    assert len(to_b1_process) == 1, (
        f"Expected edge a→b1.process for aliased import but got: {a_calls}"
    )
    assert to_b2 == [], f"Unexpected edge to b2: {to_b2}"


# ── unique project-wide fallback kept ─────────────────────────────────────────


def test_unique_fallback_kept_when_only_one_definition(cg_mod, src_root):
    """If `uniquefn()` is defined exactly once project-wide (in sub/b.py) and
    a.py calls it without importing, the edge is kept (unique-fallback rule)
    and dst uses the canonical dotted module form ``sub.b.uniquefn`` — never
    the slash path form.
    """
    sub = src_root / "sub"
    sub.mkdir()
    write_py(sub, "b.py", "def uniquefn(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        def runner():
            uniquefn()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    calls = _call_edges(graph)
    a_calls = [e for e in calls if "a.py" in e["src"]]

    # Should keep the edge because uniquefn is defined only in sub/b.py
    unique_edges = [e for e in a_calls if "uniquefn" in e["dst"]]
    assert len(unique_edges) >= 1, f"Expected unique-fallback edge for uniquefn but got: {a_calls}"
    # Issue 4: canonical dotted namespace, no slashes.
    assert all("/" not in e["dst"] for e in unique_edges), (
        f"Bound dst must use dotted module form, not slashes: {unique_edges}"
    )
    assert any(e["dst"] == "sub.b.uniquefn" for e in unique_edges), (
        f"Expected canonical dotted dst sub.b.uniquefn but got: {unique_edges}"
    )


# ── same-module call always kept ──────────────────────────────────────────────


def test_same_module_call_always_kept(cg_mod, src_root):
    """A call from function f() to g() in the same file is always kept
    regardless of import-binding rules.
    """
    write_py(
        src_root,
        "a.py",
        """\
        def g():
            pass

        def f():
            g()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    calls = _call_edges(graph)
    a_calls = [e for e in calls if "a.py" in e["src"]]

    # g is in a.py itself — call edge must appear
    same_module_calls = [e for e in a_calls if "g" in e["dst"]]
    assert len(same_module_calls) >= 1, (
        f"Expected same-module call edge a.py:f→g but got: {a_calls}"
    )


# ── cache version: stale entry must be re-parsed ──────────────────────────────


def test_cache_version_bump_forces_reparse(cg_mod, mb_path, src_root):
    """A cache entry written with a lower CACHE_VERSION than the current one
    must be treated as stale and trigger a re-parse, even when the file SHA256
    is identical.
    """
    import importlib.util as _ilu

    # Load codegraph_python to read its CACHE_VERSION constant
    cgpy_spec = _ilu.spec_from_file_location("cgpy_ib", CODEGRAPH_PY)
    cgpy = _ilu.module_from_spec(cgpy_spec)
    cgpy_spec.loader.exec_module(cgpy)

    current_version = getattr(cgpy, "CACHE_VERSION", None)
    assert current_version is not None, (
        "CACHE_VERSION constant not found in codegraph_python.py — "
        "it must be added as part of this task"
    )
    assert isinstance(current_version, int), (
        f"CACHE_VERSION must be an int, got: {type(current_version)}"
    )

    write_py(src_root, "m.py", "def f(): pass\n")

    # First apply: writes a valid cache
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")

    # Tamper: lower the cache_version in the stored cache file to simulate stale cache
    from memory_bank_skill.codegraph_common import sha256 as _sha256

    rel_path = "m.py"
    cache_dir = mb_path / "codebase" / ".cache"
    slug = _sha256(rel_path)[:16]
    cache_file = cache_dir / f"{slug}.json"
    assert cache_file.exists(), "Cache file should exist after first apply"

    cached_data = json.loads(cache_file.read_text(encoding="utf-8"))
    old_version = current_version - 1  # guaranteed to be lower
    cached_data["cache_version"] = old_version
    cache_file.write_text(json.dumps(cached_data, ensure_ascii=False, indent=2))

    # Second apply on an UNCHANGED file — because version is stale, must re-parse
    summary = cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    assert summary.get("reparsed", 0) >= 1, (
        f"Expected reparsed >= 1 when cache_version is stale, got: {summary}"
    )


# ── build_graph with import binding: cross-module call count check ────────────


def test_import_binding_reduces_false_cross_module_edges(cg_mod, src_root):
    """With two modules both defining 'helper', a third file calling helper()
    without importing either must emit 0 cross-module call edges to those
    modules (not 2 or 1).
    """
    write_py(src_root, "util1.py", "def helper(): pass\n")
    write_py(src_root, "util2.py", "def helper(): pass\n")
    write_py(
        src_root,
        "main.py",
        """\
        def run():
            helper()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    calls = _call_edges(graph)
    main_calls = [e for e in calls if "main.py" in e["src"]]

    cross_to_util1 = [e for e in main_calls if "util1" in e["dst"]]
    cross_to_util2 = [e for e in main_calls if "util2" in e["dst"]]

    assert cross_to_util1 == [], f"False cross-module edge to util1: {cross_to_util1}"
    assert cross_to_util2 == [], f"False cross-module edge to util2: {cross_to_util2}"


# ── Issue 1: local-definition shadowing — caller's own module wins ────────────


def test_local_definition_shadows_external_homonym(cg_mod, src_root):
    """GIVEN a.py defines process() and main() calls it, and b1.py ALSO defines
    process(), with NO imports anywhere; WHEN graph built; THEN the call binds
    to the caller's own definition — never rewritten to b1.process.
    """
    write_py(src_root, "b1.py", "def process(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        def process():
            pass

        def main():
            process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    a_calls = [e for e in _call_edges(graph) if "a.py" in e["src"]]
    proc_calls = [e for e in a_calls if "process" in e["dst"]]

    assert proc_calls, f"Expected a same-module process() call edge but got: {a_calls}"
    rewritten_to_b1 = [e for e in proc_calls if "b1" in e["dst"]]
    assert rewritten_to_b1 == [], (
        f"Caller's own process() must NOT be rewritten to b1.process: {rewritten_to_b1}"
    )


def test_local_definition_not_suppressed_by_multiple_homonyms(cg_mod, src_root):
    """GIVEN a.py defines+calls process(), and BOTH b1.py and b2.py define
    process() too (no imports); WHEN graph built; THEN the legitimate
    same-module call survives (must not be suppressed as ambiguous).
    """
    write_py(src_root, "b1.py", "def process(): pass\n")
    write_py(src_root, "b2.py", "def process(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        def process():
            pass

        def main():
            process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    a_calls = [e for e in _call_edges(graph) if "a.py" in e["src"]]
    proc_calls = [e for e in a_calls if "process" in e["dst"]]

    assert proc_calls, f"Same-module process() must survive even with external homonyms: {a_calls}"
    assert all("b1" not in e["dst"] and "b2" not in e["dst"] for e in proc_calls), (
        f"Same-module call must not bind to an external homonym: {proc_calls}"
    )


# ── Issue 2: relative imports honor ImportFrom.level ──────────────────────────


def test_relative_import_from_dot_module_binds_to_package(cg_mod, src_root):
    """`from .b1 import process` inside pkg/a.py binds the bare call to
    pkg.b1.process (NOT top-level b1.process).
    """
    pkg = src_root / "pkg"
    pkg.mkdir()
    write_py(pkg, "__init__.py", "\n")
    write_py(pkg, "b1.py", "def process(): pass\n")
    write_py(
        pkg,
        "a.py",
        """\
        from .b1 import process

        def runner():
            process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    a_calls = [e for e in _call_edges(graph) if "a.py" in e["src"]]
    proc_calls = [e for e in a_calls if "process" in e["dst"]]

    assert proc_calls, f"Expected bound process() call but got: {a_calls}"
    assert any(e["dst"] == "pkg.b1.process" for e in proc_calls), (
        f"Relative import must resolve to pkg.b1.process but got: {proc_calls}"
    )


def test_relative_import_bare_dot_keeps_attr_call(cg_mod, src_root):
    """`from . import b1` then `b1.f()` is an attribute call — kept unchanged
    (the relative-level fix must not mangle attribute calls).
    """
    pkg = src_root / "pkg"
    pkg.mkdir()
    write_py(pkg, "__init__.py", "\n")
    write_py(pkg, "b1.py", "def f(): pass\n")
    write_py(
        pkg,
        "a.py",
        """\
        from . import b1

        def runner():
            b1.f()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    a_calls = [e for e in _call_edges(graph) if "a.py" in e["src"]]
    attr_calls = [e for e in a_calls if e["dst"] == "b1.f"]

    assert attr_calls, f"Expected attribute call b1.f kept unchanged but got: {a_calls}"


# ── Issue 3: star imports — bind single match, suppress on ambiguity ──────────


def test_star_import_binds_single_match(cg_mod, src_root):
    """`from b1 import *` then bare process() (also defined in b2.py) binds to
    the star-imported module b1.process — NOT suppressed as ambiguous.
    """
    write_py(src_root, "b1.py", "def process(): pass\n")
    write_py(src_root, "b2.py", "def process(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        from b1 import *

        def runner():
            process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    a_calls = [e for e in _call_edges(graph) if "a.py" in e["src"]]
    to_b1 = [e for e in a_calls if e["dst"] == "b1.process"]
    to_b2 = [e for e in a_calls if "b2" in e["dst"]]

    assert len(to_b1) == 1, f"Star-imported process() must bind to b1.process but got: {a_calls}"
    assert to_b2 == [], f"Must not bind to non-star-imported b2: {to_b2}"


def test_star_import_no_false_suppress_when_only_one_defines(cg_mod, src_root):
    """`from b1 import *` then bare helper() where ONLY b1 defines helper →
    edge to b1.helper (single star match, no suppression).
    """
    write_py(src_root, "b1.py", "def helper(): pass\n")
    write_py(
        src_root,
        "a.py",
        """\
        from b1 import *

        def runner():
            helper()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    a_calls = [e for e in _call_edges(graph) if "a.py" in e["src"]]
    to_b1 = [e for e in a_calls if e["dst"] == "b1.helper"]

    assert len(to_b1) == 1, f"Single star match must bind to b1.helper but got: {a_calls}"


# ── Fix 1: root-level __init__.py relative import collapses to bare module ─────


def _load_cgpy():
    import importlib.util as _ilu

    spec = _ilu.spec_from_file_location("cgpy_fix", CODEGRAPH_PY)
    mod = _ilu.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_file_to_module_root_init_collapses_to_empty():
    """A bare root-level ``__init__.py`` is the package root: its dotted module
    namespace is the empty string, NOT ``__init__``.
    """
    cgpy = _load_cgpy()
    assert cgpy.file_to_module("__init__.py") == "", (
        "root __init__.py must collapse to '' (package root), not '__init__'"
    )
    # nested package init unchanged
    assert cgpy.file_to_module("pkg/__init__.py") == "pkg"
    assert cgpy.file_to_module("pkg/sub/__init__.py") == "pkg.sub"
    # ordinary module unchanged
    assert cgpy.file_to_module("pkg/b.py") == "pkg.b"


def test_root_init_relative_import_binds_to_bare_module(cg_mod, src_root):
    """`from .b import process` inside a ROOT-level __init__.py binds the bare
    call to ``b.process`` (NOT ``__init__.b.process``).
    """
    write_py(src_root, "b.py", "def process(): pass\n")
    write_py(
        src_root,
        "__init__.py",
        """\
        from .b import process

        def runner():
            process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    init_calls = [e for e in _call_edges(graph) if e["src"].startswith("__init__.py")]
    proc_calls = [e for e in init_calls if "process" in e["dst"]]

    assert proc_calls, f"Expected bound process() call from root __init__.py but got: {init_calls}"
    assert any(e["dst"] == "b.process" for e in proc_calls), (
        f"Root __init__.py relative import must resolve to b.process but got: {proc_calls}"
    )
    assert all("__init__" not in e["dst"] for e in proc_calls), (
        f"dst must not be contaminated with __init__: {proc_calls}"
    )


def test_nested_init_relative_import_unchanged(cg_mod, src_root):
    """Sanity: `from .b import process` inside pkg/__init__.py still resolves to
    ``pkg.b.process`` (nested case must not regress from the root-case fix).
    """
    pkg = src_root / "pkg"
    pkg.mkdir()
    write_py(pkg, "b.py", "def process(): pass\n")
    write_py(
        pkg,
        "__init__.py",
        """\
        from .b import process

        def runner():
            process()
    """,
    )

    graph = cg_mod.build_graph(src_root)
    init_calls = [
        e for e in _call_edges(graph) if e["src"].replace("\\", "/").startswith("pkg/__init__.py")
    ]
    proc_calls = [e for e in init_calls if "process" in e["dst"]]

    assert proc_calls, f"Expected bound process() call from pkg/__init__.py but got: {init_calls}"
    assert any(e["dst"] == "pkg.b.process" for e in proc_calls), (
        f"Nested __init__.py relative import must resolve to pkg.b.process but got: {proc_calls}"
    )


# ── Fix 2: cross-language contamination — non-.py callers pass through ─────────


def test_bind_calls_non_python_caller_passes_through_unchanged(cg_mod):
    """A call edge whose caller file is NOT a .py file (e.g. main.go) must pass
    through ``bind_calls`` verbatim, even when Python homonym/suppression rules
    would otherwise rewrite or drop it.
    """
    cgpy = _load_cgpy()
    edges = [
        # Go caller calling Helper — Python rules must NOT touch this.
        {"src": "main.go:main", "dst": "Helper", "kind": "call"},
    ]
    # Two Python homonyms for Helper would normally trigger suppression (Rule 4).
    import_bindings: dict[str, dict[str, str]] = {}
    definitions = {"Helper": ["util1.py", "util2.py"]}
    out = cgpy.bind_calls(edges, import_bindings, definitions, {})

    assert out == edges, f"Non-.py caller edge must pass through unchanged, got: {out}"


def test_bind_calls_definitions_built_from_python_only(cg_mod):
    """The unique-fallback rule must ignore non-.py definitions: a bare Python
    call whose ONLY graph definition lives in a .go file gets no rewrite (the
    .go definition is not a valid Python bind target).
    """
    cgpy = _load_cgpy()
    edges = [
        {"src": "a.py:runner", "dst": "Helper", "kind": "call"},
    ]
    # Mixed definitions map as build_graph would hand it: a .go definition must
    # NOT be used as a Python unique-fallback bind target.
    definitions = {"Helper": ["server.go"]}
    out = cgpy.bind_calls(edges, {}, definitions, {})

    # No .py definition exists → edge kept bare (no rewrite to server.Helper /
    # server.go.Helper garbage).
    assert out == edges, f"Python bare call must not bind to a .go definition; got: {out}"


def test_build_graph_go_edges_survive_python_homonyms(cg_mod, src_root):
    """End-to-end through build_graph: a synthetic mixed edge list with a Go
    caller edge + Python homonyms — the Go edge must survive bind_calls."""
    cgpy = _load_cgpy()
    # Definitions map built ONLY from .py nodes per the fix.
    definitions = {"Helper": ["util1.py", "util2.py"]}
    edges = [
        {"src": "main.go:run", "dst": "Helper", "kind": "call"},
        {"src": "a.py:run", "dst": "Helper", "kind": "call"},  # suppressed (2 .py homonyms)
    ]
    out = cgpy.bind_calls(edges, {}, definitions, {})

    go_edges = [e for e in out if e["src"].endswith(".go:run")]
    py_edges = [e for e in out if e["src"].endswith(".py:run")]

    assert go_edges == [{"src": "main.go:run", "dst": "Helper", "kind": "call"}], (
        f"Go caller edge must survive verbatim: {out}"
    )
    assert py_edges == [], f"Python ambiguous homonym call must still be suppressed: {out}"
