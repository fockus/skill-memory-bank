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

AGR-036 adds a FOURTH form, `doc_contract_test`: a `pytest`/`bats` run counts as
structural when every repo file the named test touches is documentation or
configuration. The three original forms are unchanged, and the new one is
admitted on the test's TARGETS, never on the runner's name — see the block above
`_TEST_RUNNERS`. REQ-049's own wording still enumerates three forms; that text
belongs to the spec, which is not this module's to edit.
"""

from __future__ import annotations

import os
import re
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


# ── AGR-036: a test whose TARGETS are documentation is a structural Eval ─────
#
# `pytest`/`bats` were rejected outright, so the dominant idiom of this codebase
# — a test that asserts the normative structure of a markdown prompt file — could
# not be declared, and four specs would have had to restate their document checks
# as `grep`, which is strictly weaker than what they already had.
#
# The admission is keyed on WHAT THE TEST CHECKS, never on the runner: "any
# pytest is structural" would delete the rule. The targets are read out of the
# test file the Eval names, so the claim is derivable from the Eval itself. When
# the test cannot be read — it is not written yet — the claim is unproven and the
# Eval stays non-structural. That is the same verdict as before this change, so
# the gate can only ever get narrower here, never wider.

_TEST_RUNNERS = ("pytest", "bats")
# `$REPO_ROOT/commands/sdd.md`, `commands/sdd.md`, `../commands/sdd.md`.
_SLASH_PATH = re.compile(r"[A-Za-z0-9_.][A-Za-z0-9_.\-]*(?:/[A-Za-z0-9_.\-]+)+")
# `REPO_ROOT / "commands" / "sdd.md"` — the pathlib idiom, which carries no
# slash at all and is how the python tests in this repo actually name a file.
_JOIN_PATH = re.compile(r"""(?:\s*/\s*(?:"[^"\n]*"|'[^'\n]*'))+""")
_QUOTED = re.compile(r"""["']([^"'\n]*)["']""")


def _repo_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _root_entries(root: str) -> set[str]:
    try:
        return {e for e in os.listdir(root) if e != ".git"}
    except OSError:
        return set()


def _anchored(path_like: str, roots: set[str]) -> str | None:
    """Longest suffix of `path_like` that starts at a real repo-root entry.

    This is what separates a path from prose: `edit/overwrite/cancel` and
    `$BANK/briefs/t/brief.md` have no segment that names anything in the repo,
    while `$REPO_ROOT/commands/sdd.md` resolves to `commands/sdd.md`.
    """
    parts = [p for p in path_like.split("/") if p not in ("", ".")]
    for i, p in enumerate(parts):
        if p in roots:
            return "/".join(parts[i:])
    return None


def _normalise_target(t: str) -> str:
    """A path with no extension in its last segment is a DIRECTORY reference."""
    return t if "." in os.path.basename(t) else t.rstrip("/") + "/"


def _target_kind(t: str) -> str | None:
    """`doc` · `runtime` · None when the target is a test/Eval artifact."""
    t = _normalise_target(t.strip().strip("`").rstrip(".,;:)]}"))
    if is_test_artifact(t):
        return None
    base = t.split("*", 1)[0]
    if base.startswith(_DOC_DIRS):
        return "doc"
    if t.endswith(_DOC_EXTS):
        return "doc"
    return "runtime"


def referenced_paths(path: str, repo_root: str) -> list[str]:
    """Repo-relative paths a test file references, deduplicated and sorted."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return []
    roots = _root_entries(repo_root)
    found: set[str] = set()
    for tok in _SLASH_PATH.findall(text):
        anchored = _anchored(tok.rstrip(".,;:)]}"), roots)
        if anchored:
            found.add(anchored)
    for run in _JOIN_PATH.findall(text):
        segments = _QUOTED.findall(run)
        if segments:
            anchored = _anchored("/".join(segments), roots)
            if anchored:
                found.add(anchored)
    return sorted(found)


def _doc_contract_form(toks: list[str], repo_root: str) -> str | None:
    """`doc_contract_test` when every file the named test(s) touch is a doc."""
    files = [t for t in toks if "/" in t and not t.startswith("-")]
    if not files:
        # A bare `pytest` runs the whole suite: it checks everything, so it
        # certifies nothing about a document.
        return None
    targets: set[str] = set()
    for rel in files:
        full = rel if os.path.isabs(rel) else os.path.join(repo_root, rel)
        if not os.path.isfile(full):
            return None  # unwritten test — the claim cannot be checked
        targets.update(referenced_paths(full, repo_root))
    kinds = [k for k in (_target_kind(t) for t in targets) if k is not None]
    if not kinds:
        return None  # touches no repo file we can classify
    if any(k == "runtime" for k in kinds):
        return None  # it exercises code, so its red needs the code
    return "doc_contract_test"


def structural_form(cmd: str, repo_root: str | None = None) -> str | None:
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
    if head in _TEST_RUNNERS or (
        head in ("python", "python3") and "-m" in toks and "pytest" in toks
    ):
        return _doc_contract_form(toks, repo_root or _repo_root())
    return None


def eval_targets(cmd: str) -> list[str]:
    """Path-ish tokens of an Eval command (C1: contain '/', not a flag)."""
    try:
        toks = shlex.split(cmd)
    except ValueError:
        toks = cmd.split()
    return [t for t in toks if "/" in t and not t.startswith("-")]
