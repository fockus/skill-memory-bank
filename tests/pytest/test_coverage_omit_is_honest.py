"""The `omit` list in .coveragerc must name tested code, never hide untested code.

Most of this skill's Python is a library behind a shell CLI. `mb-spec-validate.sh`
runs `python3 scripts/mb_spec_validate_v2.py`; the tests that exercise it are bats
files. Coverage only instruments the pytest process, so those modules reported 0%
while CI executed them on every run — a miscount that dragged the total under the
85% gate and said "untested" about tested code.

Omitting them fixes the number. It also opens an obvious hole: `omit` is exactly
where genuinely untested code would go to disappear. These tests close it. Every
omitted module must be mapped to a test that actually reaches it, that test must
exist, and it must reference either the module itself or the shell wrapper that
runs it. Adding a line to `omit` without adding it here turns the suite red.
"""

from __future__ import annotations

import configparser
import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
COVERAGERC = REPO_ROOT / ".coveragerc"

# omitted module -> the test that exercises it through its shell entry point.
OWNING_TEST = {
    "memory_bank_skill/__main__.py": "hooks/tests/graph-discipline.bats",
    "scripts/mb-code-context.py": "tests/bats/test_graph_rag_adapters.bats",
    "scripts/mb-context-slim.py": "tests/bats/test_cursor_adapter.bats",
    "scripts/mb-graph-query.py": "hooks/tests/graph-discipline.bats",
    "scripts/mb-scenario-extract.py": "tests/bats/test_idea_promote.bats",
    "scripts/mb-sdd-layers-render.py": "tests/bats/test_mb_sdd_self_check.bats",
    "scripts/mb-settings-ensure-timeout.py": "hooks/tests/session-end-timeout.bats",
    "scripts/mb-statusline.py": "tests/bats/test_cursor_adapter.bats",
    "scripts/mb_backlog_state_engine.py": "tests/bats/test_mb_backlog_duplicate_ids.bats",
    "scripts/mb_brief_candidate.py": "tests/bats/test_brief_discuss_handoff.bats",
    "scripts/mb_code_context_core.py": "tests/bats/test_graph_rag_adapters.bats",
    "scripts/mb_contract_gate.py": "tests/bats/test_mb_contract_gate.bats",
    "scripts/mb_contract_registry.py": "tests/bats/test_mb_contract_gate.bats",
    "scripts/mb_graph_query_render.py": "hooks/tests/graph-discipline.bats",
    "scripts/mb_pipeline_validate_blocks.py": "tests/bats/test_mb_pipeline_validate.bats",
    "scripts/mb_pipeline_validate_core.py": "tests/bats/test_mb_pipeline_validate.bats",
    "scripts/mb_quality_dod.py": "tests/pytest/test_quality_dod_delivery.py",
    "scripts/mb_roadmap_group.py": "tests/bats/test_mb_roadmap_fence_markers.bats",
    "scripts/mb_roadmap_plans.py": "tests/bats/test_mb_roadmap_fence_markers.bats",
    "scripts/mb_rules_resolve.py": "tests/bats/test_mb_rules_resolve.bats",
    "scripts/mb_sdd_judge_journal.py": "tests/bats/test_sdd_decide.bats",
    "scripts/mb_spec_validate_graph.py": "tests/bats/test_mb_spec_validate_hardening.bats",
    "scripts/mb_spec_validate_layers.py": "tests/bats/test_mb_spec_validate_hardening.bats",
    "scripts/mb_spec_validate_scope_eval.py": "tests/bats/test_mb_spec_validate_hardening.bats",
    "scripts/mb_spec_validate_tasks.py": "tests/bats/test_mb_spec_validate_hardening.bats",
    "scripts/mb_spec_validate_v2.py": "tests/bats/test_mb_spec_validate_hardening.bats",
    "scripts/mb_work_plan_wrapper.py": "tests/bats/test_mb_work_plan_range.bats",
}


def _omitted_paths() -> list[str]:
    parser = configparser.ConfigParser()
    parser.read(COVERAGERC, encoding="utf-8")
    raw = parser.get("run", "omit", fallback="")
    return [line.strip() for line in raw.splitlines() if line.strip()]


def test_every_omitted_module_is_mapped_to_a_test() -> None:
    """No silent additions: `omit` and the map above must agree exactly."""
    omitted = set(_omitted_paths())
    mapped = set(OWNING_TEST)

    unmapped = sorted(omitted - mapped)
    assert not unmapped, (
        "These modules are omitted from coverage but named no owning test:\n  "
        + "\n  ".join(unmapped)
        + "\nAdd each to OWNING_TEST with the test that exercises it, or drop it "
        "from .coveragerc's omit list and let coverage measure it."
    )

    stale = sorted(mapped - omitted)
    assert not stale, (
        "These modules are mapped here but no longer omitted:\n  "
        + "\n  ".join(stale)
        + "\nRemove them from OWNING_TEST — a stale map hides the next drift."
    )


@pytest.mark.parametrize("module,test_file", sorted(OWNING_TEST.items()))
def test_omitted_module_and_its_owning_test_both_exist(module: str, test_file: str) -> None:
    assert (REPO_ROOT / module).is_file(), (
        f"{module} is omitted from coverage but does not exist. Delete the entry."
    )
    assert (REPO_ROOT / test_file).is_file(), (
        f"{module} claims coverage from {test_file}, which does not exist."
    )


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def _mentions(text: str, name: str) -> bool:
    return bool(re.search(rf"\b{re.escape(name)}\b", text))


def _entry_points(stem: str) -> tuple[set[str], set[str]]:
    """Names through which `stem` can be driven: (python module stems, shell scripts).

    Several omitted modules are libraries imported by another module rather than
    CLI entry points of their own — `mb_spec_validate_graph` is imported by
    `mb_spec_validate_v2`, which `mb-spec-validate.sh` runs. Two import hops
    cover every such chain in this repo. Deliberately NOT a full transitive
    closure: with everything reachable from everything, the check would pass on
    any pairing and stop being evidence.
    """
    py_files = [
        path
        for directory in ("scripts", "memory_bank_skill", "hooks/lib")
        for path in (REPO_ROOT / directory).glob("*.py")
    ]
    reachable = {stem}
    for _ in range(2):
        grown = {
            path.stem
            for path in py_files
            if any(_mentions(_read(path), name) for name in reachable)
        }
        if grown <= reachable:
            break
        reachable |= grown

    shells = {
        path.name
        for directory in ("scripts", "hooks", "adapters")
        for path in (REPO_ROOT / directory).glob("*.sh")
        if any(_mentions(_read(path), name) for name in reachable)
    }
    return reachable, shells


@pytest.mark.parametrize("module,test_file", sorted(OWNING_TEST.items()))
def test_owning_test_actually_reaches_the_module(module: str, test_file: str) -> None:
    """The claim must be checkable, not just plausible.

    A test reaches the module when it names the module, a module that imports it,
    or a shell script that runs one of those. Anything weaker would let a file-size
    or naming test — which never executes a line of the module — be recorded as its
    coverage, which is the exact fiction this file exists to prevent.
    """
    assert Path(test_file) != Path(__file__).relative_to(REPO_ROOT), (
        f"{module} cannot cite this guard as its own coverage."
    )

    stem = Path(module).stem
    text = _read(REPO_ROOT / test_file)

    modules, shells = _entry_points(stem)
    hit = sorted(name for name in modules if _mentions(text, name))
    hit += sorted(name for name in shells if name in text)

    assert hit, (
        f"{test_file} is claimed to cover {module}, but it names neither the module, nor any "
        f"module importing it ({', '.join(sorted(modules - {stem})) or 'none'}), nor any script "
        f"running those ({', '.join(sorted(shells)) or 'none'}). Point the map at a test that "
        "really drives it, or drop the module from omit and let coverage measure it."
    )
