"""I-174: a task's `**Eval:**` must run the test files its `**Scope:**` claims.

WHY THIS EXISTS
═══════════════
`eval.<N>=ready` reads as "task N is green". It means "the files named in the
Eval command are green". When a task owns three test files and its Eval names
one, the battery measures a third of the task and reports for all of it, and no
existing check can see the gap: CPR-D compares the design and tasks copies of
the Eval line byte-for-byte, so two identically incomplete declarations agree.

The instance that produced this module: a file split added the new test file to
`**Scope:**` and not to `**Eval:**`, in one edit, because the author checked the
Eval against what he had split out — his intent — instead of against the Scope
line he had just written. A structural check does not have intent, which is the
entire reason to move this judgement into code.

WHY IT LIVES BESIDE CPR-D AND NOT IN THE C8 BATTERY
═══════════════════════════════════════════════════
1. It compares a declaration to a declaration. No filesystem, no execution.
2. It must fire at SPEC time — at the moment of the split, before any run.
3. In the battery it would be dead exactly when needed: a structural failure
   short-circuits the battery before the behavioural half, so a declaration
   check placed after execution never runs on a spec that has any other
   structural problem.

THREE OUTCOMES, NOT ONE — AND WHY THE OBVIOUS CLASSIFIER IS WRONG
═════════════════════════════════════════════════════════════════
Measured over the eight group specs before this was written: 7 raw mismatches,
2 of them false positives of `is_test_artifact()` — `tests/fixtures/*.json` and
`tests/bats/lib/*.bash`. Those are INPUTS to tests: no runner can take them as
a target, so demanding them would make the gate impossible to satisfy, and a
gate that demands the impossible is ignored within days. `is_test_artifact()`
answers a different question (REQ-049: "is this product surface?") and must not
be reused here — if you are here to widen a whitelist, widen THIS one, and keep
it to files a runner can actually be pointed at.

The two remaining cases need a human decision rather than a fix, so they are
named without blocking:
  * a GLOB Scope element (`tests/**`) is not resolvable without the filesystem.
    Silence would make it the standard bypass; blocking would reject a legal
    declaration. It is said out loud instead.
  * a CROSS-RUNNER file (a pytest file under a `bats` Eval) cannot be appended
    to the command without changing what its `exit:` / `output~:` anchors mean.
    That is a decision about the declaration, not a typo.

Notices go to stderr (non-fatal, visible when the validator is run directly).
Known limit, stated rather than hidden: `mb-sdd-self-check.sh` captures the
validator's output and re-emits it only on failure, so notices from a PASSING
spec are not visible through the battery.
"""

from __future__ import annotations

import os
import re
import shlex
import sys

# A file a runner can be pointed at. Deliberately narrow: the repo has exactly
# two runners, and everything else under tests/ is an input.
_RUNNABLE_RE = re.compile(r"^(test_.+\.py|.+\.bats)$")
# Path segments that hold test INPUTS, never runnable tests.
_INPUT_SEGMENTS = {"lib", "fixtures"}


def _runnable_test_file(path: str) -> bool:
    parts = path.split("/")
    if any(seg in _INPUT_SEGMENTS for seg in parts[:-1]):
        return False
    return bool(_RUNNABLE_RE.match(parts[-1]))


def _file_runner(path: str) -> str | None:
    if path.endswith(".bats"):
        return "bats"
    if path.endswith(".py"):
        return "pytest"
    return None


def _cmd_runner(cmd: str) -> str | None:
    """The runner a command actually invokes, or None when unrecognised."""
    try:
        toks = shlex.split(cmd)
    except ValueError:
        return None
    # `VAR=value cmd …` — leading assignments are environment, not the runner
    # (the same rule mb-sdd-self-check.sh applies when it resolves a runner).
    while toks and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[0]):
        toks.pop(0)
    if not toks:
        return None
    head = os.path.basename(toks[0])
    if head == "bats":
        return "bats"
    if head in ("pytest", "py.test"):
        return "pytest"
    if head in ("python", "python3") and "pytest" in toks:
        return "pytest"
    return None


def _targets(cmd: str) -> set[str]:
    try:
        toks = shlex.split(cmd)
    except ValueError:
        toks = cmd.split()
    return {t for t in toks if "/" in t and not t.startswith("-")}


def notice(msg: str) -> None:
    sys.stderr.write(f"[spec-validate] notice: {msg}\n")


def check(tasks: list[dict], emit) -> None:
    """Emit one violation per runnable test file a task owns but never runs."""
    for t in tasks:
        no = t.get("item_no")
        ev = t.get("eval") or {}
        cmd = (ev.get("cmd") or "").strip()
        scope = [str(s).strip().strip("`") for s in (t.get("scope") or [])]
        # A waived or undeclared Eval has nothing to run: exempt by construction.
        if not cmd or cmd.lower() == "none" or not scope:
            continue
        targets = _targets(cmd)
        runner = _cmd_runner(cmd)
        for el in scope:
            if not el:
                continue
            if "*" in el:
                # Only test-ward globs are worth naming; `scripts/*.sh` is not
                # about this rule and must not add noise to every spec.
                if el.startswith("tests/") or "/tests/" in el:
                    notice(
                        f"I-174: task {no} Scope glob '{el}' may cover test files the "
                        f"Eval does not run — not decidable without the filesystem"
                    )
                continue
            if not _runnable_test_file(el):
                continue
            if el in targets:
                continue
            if _file_runner(el) != runner:
                notice(
                    f"I-174: task {no} Scope carries '{el}' but its Eval runs "
                    f"{runner or 'an unrecognised runner'} — appending it would change what "
                    f"the declared exit:/output~: anchors mean; decide, do not concatenate"
                )
                continue
            emit(
                f"I-174: task {no} Scope declares test file '{el}' but its Eval never runs it "
                f"— the task reports green for a subset of its own tests"
            )
