"""`svp-sdd-core` may not declare `status: ready` while its own gate rejects it.

Round-4 judge, blocker B1. The spec's frontmatter said `status: ready` while
`mb-sdd-self-check.sh --spec svp-sdd-core` exited 1 — and REQ-015, an acceptance
criterion of THIS spec, says the system "shall keep the spec in draft status
until every check passes". So the line was not a premature promise; it was a
false statement about the present, and it had stood unrevised since the spec was
created (8bac761).

Fixing the line without a check would leave the guarantee resting on everyone
remembering it. This binds it: while the structural gate refuses the triple, the
frontmatter may not call it ready.

WHY `mb-spec-validate.sh` AND NOT THE C8 BATTERY
------------------------------------------------
C7 keys `ready` on `mb-sdd-self-check.sh` exit 0, and spec-validate is a
necessary condition of it (the battery delegates its structural half and, since
round-4 finding [1], short-circuits on its failure). Calling the battery here
instead would EXECUTE every `**Eval:**` command of the spec as a side effect —
the whole zone's pytest+bats suites — turning one assertion into a multi-minute
recursive test run. The cheap necessary condition is the right predicate for a
unit test; the full battery stays where it belongs, in the pipeline.

DELIBERATELY SCOPED TO ONE SPEC
-------------------------------
The corpus version of this check ("no spec may claim ready while its gate
refuses it") is what the judge ran by hand: 10 of 10 program specs fail the
battery and 9 of 9 declare `ready`. Landing that here would red the suite for
nine specs owned by other tracks, which is a program decision, not a test's.
This file asserts the rule where it has already been paid for.
"""

from __future__ import annotations

import pathlib
import re
import subprocess

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = "svp-sdd-core"
REQ = REPO_ROOT / ".memory-bank" / "specs" / SPEC / "requirements.md"


def _frontmatter_status() -> str | None:
    text = REQ.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r"^status:\s*(\S+)\s*$", line)
        if m:
            return m.group(1)
    return None


def _structural_gate_rc() -> int:
    return subprocess.run(
        ["bash", str(REPO_ROOT / "scripts" / "mb-spec-validate.sh"), SPEC],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    ).returncode


def test_status_key_is_declared() -> None:
    """A missing key must fail loudly rather than read as "not ready"."""
    assert _frontmatter_status() is not None, (
        f"{REQ.relative_to(REPO_ROOT)} declares no frontmatter `status:`"
    )


def test_not_ready_while_its_own_structural_gate_refuses_it() -> None:
    rc = _structural_gate_rc()
    status = _frontmatter_status()
    if rc != 0:
        assert status != "ready", (
            f"{SPEC} declares status: ready while mb-spec-validate.sh refuses it "
            f"(rc={rc}) — REQ-015 requires draft until every check passes"
        )
    # rc == 0 imposes nothing: a spec whose gate passes is allowed to be ready
    # (C7 additionally requires review resolution, which this test does not judge).
