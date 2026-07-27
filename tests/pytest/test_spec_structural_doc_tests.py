"""AGR-036: a `pytest`/`bats` Eval counts as a REQ-049 structural Eval only when
the files the test actually checks are documentation or configuration.

The rule is worth exactly what it REFUSES. Widening `structural_form` to "any
pytest is structural" would delete REQ-049 for every docs-only task, so most of
this file is negative: a test that drives a script, a test nobody has written
yet, a bare `pytest`, and prose that merely looks like a path must all stay
non-structural. The positive cases use the repository's own Eval commands
because that is the input the gate is judged on.
"""

from __future__ import annotations

import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from mb_spec_validate_structural import (  # noqa: E402
    referenced_paths,
    structural_form,
)

# Real Eval commands taken from `.memory-bank/specs/*/tasks.md`. Each names a
# test that exists and asserts the normative structure of a prompt file.
DOC_CONTRACT_EVALS = [
    "pytest tests/pytest/test_sdd_command_contract_v2.py",
    "bats tests/bats/test_discuss_self_interview.bats",
    "bats tests/bats/test_discuss_final_gate_batch.bats",
    "bats tests/bats/test_mb_brief_docs.bats",
]


def test_doc_contract_evals_are_structural() -> None:
    for cmd in DOC_CONTRACT_EVALS:
        assert structural_form(cmd) == "doc_contract_test", cmd


def test_the_named_tests_exist_and_target_only_docs() -> None:
    """Guards the case above from passing for the wrong reason.

    If one of these files disappeared, `structural_form` would answer None and
    the assertion above would still be meaningful — but a reader could not tell
    whether the rule admitted a document test or simply matched a runner name.
    """
    for cmd in DOC_CONTRACT_EVALS:
        rel = cmd.split()[1]
        path = REPO_ROOT / rel
        assert path.is_file(), f"{rel} vanished; the case above proves nothing"
        targets = referenced_paths(str(path), str(REPO_ROOT))
        assert targets, f"{rel} references no repo file"
        assert not [t for t in targets if t.startswith("scripts/")], targets


def test_a_test_that_drives_a_script_is_not_structural() -> None:
    """The discriminating case, and a real one.

    `tests/bats/test_brief_discuss_handoff.bats` checks a prompt file AND runs
    `scripts/mb-brief.sh`. Its red therefore needs the script to exist, which is
    precisely what REQ-049 forbids a documentation-only task to depend on. It
    stays a violation in `svp-brief` task 3 after this change.
    """
    cmd = "bats tests/bats/test_brief_discuss_handoff.bats"
    targets = referenced_paths(
        str(REPO_ROOT / "tests/bats/test_brief_discuss_handoff.bats"), str(REPO_ROOT)
    )
    assert "scripts/mb-brief.sh" in targets, targets
    assert structural_form(cmd) is None


def test_a_behavioural_python_test_is_not_structural() -> None:
    assert structural_form("pytest tests/pytest/test_s4_r3_data_safety.py") is None
    assert structural_form("pytest tests/pytest/test_mb_spec_validate.py") is None


def test_an_unwritten_test_is_not_structural() -> None:
    """Fail closed: a claim about a file nobody can read is not a claim.

    This is also what keeps the change from being a widening — before AGR-036
    every runner answered None, and a test that does not exist still does.
    """
    assert structural_form("bats tests/bats/test_does_not_exist_yet.bats") is None
    assert structural_form("pytest tests/pytest/test_not_written.py") is None


def test_a_bare_runner_is_not_structural() -> None:
    """`pytest` with no file runs everything, so it certifies nothing."""
    assert structural_form("pytest") is None
    assert structural_form("bats") is None
    assert structural_form("pytest -q") is None


def _write(tmp_path: pathlib.Path, name: str, body: str) -> str:
    p = tmp_path / name
    p.write_text(body, encoding="utf-8")
    return str(p)


def test_pathlib_join_to_scripts_is_seen_as_runtime(tmp_path) -> None:
    """`REPO_ROOT / "scripts"` carries no slash — it must still count.

    A python test that puts `scripts/` on `sys.path` imports first-party code;
    reading only slash-separated tokens would have missed it and admitted a
    behavioural test as structural.
    """
    f = _write(
        tmp_path,
        "test_fixture_runtime.py",
        "import sys, pathlib\n"
        "REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]\n"
        'sys.path.insert(0, str(REPO_ROOT / "scripts"))\n'
        'DOC = REPO_ROOT / "commands" / "sdd.md"\n'
        "def test_x():\n"
        "    assert DOC.exists()\n",
    )
    targets = referenced_paths(f, str(REPO_ROOT))
    assert "scripts/" in targets or "scripts" in targets, targets
    assert structural_form(f"pytest {f}") is None


def test_pathlib_join_to_a_doc_is_seen_as_a_doc(tmp_path) -> None:
    f = _write(
        tmp_path,
        "test_fixture_doc.py",
        "import pathlib\n"
        "REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]\n"
        'DOC = REPO_ROOT / "references" / "templates.md"\n'
        "def test_x():\n"
        '    assert "## Interview plan template" in DOC.read_text()\n',
    )
    assert referenced_paths(f, str(REPO_ROOT)) == ["references/templates.md"]
    assert structural_form(f"pytest {f}") == "doc_contract_test"


def test_prose_that_looks_like_a_path_is_not_a_target(tmp_path) -> None:
    """`edit/overwrite/cancel` is English, not a file.

    Anchoring every candidate at a real repo-root entry is what tells them
    apart; without it a test full of slash-separated prose would look like it
    targeted documentation.
    """
    f = _write(
        tmp_path,
        "test_fixture_prose.py",
        '"""Covers the edit/overwrite/cancel choice and the yes/no gate."""\n'
        "def test_x():\n"
        "    assert len('edit/overwrite/cancel'.split('/')) == 3\n",
    )
    assert referenced_paths(f, str(REPO_ROOT)) == []
    assert structural_form(f"pytest {f}") is None


def test_a_test_touching_only_its_own_fixtures_is_not_structural(tmp_path) -> None:
    """Test artifacts are not a product surface, so they cannot make a doc claim."""
    f = _write(
        tmp_path,
        "test_fixture_selfonly.py",
        "import pathlib\n"
        "REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]\n"
        'FIX = REPO_ROOT / "tests" / "fixtures" / "mb-empty"\n'
        "def test_x():\n"
        "    assert FIX.exists()\n",
    )
    assert structural_form(f"pytest {f}") is None


def test_python_m_pytest_is_recognised_like_pytest() -> None:
    cmd = "python3 -m pytest tests/pytest/test_sdd_command_contract_v2.py"
    assert structural_form(cmd) == "doc_contract_test"
    assert structural_form("python3 -m pytest tests/pytest/test_s4_r3_data_safety.py") is None


def test_the_three_original_forms_are_untouched() -> None:
    """Regression guard: AGR-036 adds a form, it does not relax the others."""
    assert structural_form("test -f commands/sdd.md") == "file_presence"
    assert structural_form("grep -q '## Topics' commands/discuss.md") == "section_presence"
    assert structural_form("shellcheck scripts/mb-glossary.sh") == "linter_exit"
    assert structural_form("python3 -m json.tool settings/hooks.json") == "linter_exit"
    # ...and a plain behavioural command is still nothing.
    assert structural_form("bash scripts/mb-glossary.sh upsert --mb .") is None
    assert structural_form("test commands/sdd.md") is None
