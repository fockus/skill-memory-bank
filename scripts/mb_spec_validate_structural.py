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


def is_no_runtime(scope: list[str]) -> bool:
    """True when EVERY scope element is documentation/configuration only."""
    if not scope:
        return False
    for el in scope:
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
