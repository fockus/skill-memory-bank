"""REQ-049 scope classification + structural Eval grammar for mb-spec-validate.

Split out of mb_spec_validate_v2.py so every file stays <=400 lines (S2 review
[24]). Owns one question: does a task have a runtime surface, and if not, is its
Eval one of the three structural forms REQ-049 allows?

REQ-049 (verbatim): "While a task has no runtime surface - documentation or
configuration only - the generated spec shall declare a structural Eval whose
red is observable before implementation: file presence, section presence or
linter exit."

A behavioural Eval on a docs-only task is rejected because its red is not
observable before the code exists (review [16]).
"""

from __future__ import annotations

import os
import shlex

_DOC_DIRS = ("docs/", "doc/", "references/", "commands/", "agents/", "notes/")
# Directories holding test/Eval artifacts — never the product surface (review [3]).
_TEST_DIRS = ("tests/", "test/", "spec/", "specs/", "fixtures/")
_DOC_EXTS = (
    ".md",
    ".markdown",
    ".rst",
    ".txt",
    ".yaml",
    ".yml",
    ".json",
    ".toml",
    ".ini",
    ".cfg",
    ".conf",
)
# Runners whose exit code is itself the structural check (REQ-049 "linter exit").
_LINTERS = {
    "shellcheck",
    "ruff",
    "flake8",
    "eslint",
    "markdownlint",
    "mdl",
    "yamllint",
    "jsonlint",
    "tomllint",
    "actionlint",
    "hadolint",
    "jq",
    "yq",
    "black",
    "prettier",
    "mypy",
}


def is_test_artifact(el: str) -> bool:
    """True when a scope element is a test/Eval artifact rather than product.

    A task's own test files are what its Eval *runs*, not the surface it
    changes, so they must not decide whether the task has a runtime surface.
    """
    el = el.strip().strip("`")
    base = el.split("*", 1)[0]
    if base.startswith(_TEST_DIRS):
        return True
    name = os.path.basename(el.rstrip("/"))
    return name.startswith("test_") or name.startswith("test-") or ".bats" in name


def is_no_runtime(scope: list[str]) -> bool:
    """True when the PRODUCT surface is documentation/configuration only.

    Test/Eval artifacts are excluded before the decision (review [3]): a scope
    of `docs/**, tests/bats/test_demo.bats` is a documentation-only task whose
    Eval happens to live in tests/, and counting that .bats file as runtime let
    it declare a behavioural Eval and skip the REQ-049 structural requirement.
    A scope consisting ONLY of test artifacts keeps its previous answer (False)
    — it has a real runtime surface, just a test-shaped one.
    """
    if not scope:
        return False
    product = [el for el in scope if not is_test_artifact(el)]
    if not product:
        return False
    for el in product:
        el = el.strip().strip("`")
        if not el:
            return False
        base = el.split("*", 1)[0]
        if base.startswith(_DOC_DIRS):
            continue
        if el.endswith(_DOC_EXTS):
            continue
        return False
    return True


def structural_form(cmd: str) -> str | None:
    """Which REQ-049 structural form `cmd` is, or None when behavioural."""
    try:
        toks = shlex.split(cmd)
    except ValueError:
        return None
    if not toks:
        return None
    head = os.path.basename(toks[0])
    if head in ("test", "["):
        return "file_presence" if any(t in ("-f", "-e", "-d", "-s") for t in toks) else None
    if head in ("grep", "rg", "egrep"):
        return "section_presence"
    if head in _LINTERS:
        return "linter_exit"
    if head in ("python", "python3") and "json.tool" in toks:
        return "linter_exit"
    return None


def eval_targets(cmd: str) -> list[str]:
    """Path-ish tokens of an Eval command (C1: contain '/', not a flag)."""
    try:
        toks = shlex.split(cmd)
    except ValueError:
        toks = cmd.split()
    return [t for t in toks if "/" in t and not t.startswith("-")]
