"""Task 8 (svp-contract-test-loop) — the whole path, end to end.

spec → contract task → checker registry → `mb-contract-gate.sh red` →
business code → `mb-contract-gate.sh verify`.

Real bank, real scripts, real checker processes, a real product file that
starts without the behaviour and gains it. Deterministic by construction: no
network, no clock, no sleeps, and no assertion about anything outside the
per-test `tmp_path`. The evidence schema carries no timestamp, so two runs of
this file are byte-comparable.

THE ONE OUTCOME THAT MUST NOT HIDE
──────────────────────────────────
"The checkers passed" and "the checkers never ran" produce the same silence.
That confusion is the most expensive defect this slice has met, so every
assertion about a checker running is backed by a MARKER the checker itself
writes on entry. Absence of a marker is OBSERVED, never inferred from an exit
code — and `test_REQ_020__verify_runs_the_contract_checkers` separates all
three outcomes (ran-and-green, ran-and-red, never-ran) rather than two.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
GATE = REPO_ROOT / "scripts" / "mb-contract-gate.sh"
VALIDATE = REPO_ROOT / "scripts" / "mb-spec-validate.sh"

DASH = "—"
GUARD = "raise ValueError('ledger unreachable')"


class World:
    """A throwaway checkout + bank, wired the way a real project is."""

    def __init__(self, tmp_path: Path):
        self.root = tmp_path / "checkout"
        self.bank = self.root / ".memory-bank"
        self.spec = self.bank / "specs" / "inventory-sync"
        self.markers = tmp_path / "markers"
        self.product = self.root / "src" / "ledger.py"
        for d in (self.spec, self.markers, self.root / "src", self.root / "tests" / "checkers"):
            d.mkdir(parents=True, exist_ok=True)
        # The product starts WITHOUT the behaviour the requirement demands.
        self.product.write_text("def submit(batch):\n    return len(batch)\n", encoding="utf-8")

    # -- product -----------------------------------------------------------

    def implement(self) -> None:
        """What an implementer would do: make the requirement true."""
        self.product.write_text(
            "def submit(batch):\n    if not batch:\n        %s\n    return len(batch)\n" % GUARD,
            encoding="utf-8",
        )

    # -- checkers ----------------------------------------------------------

    def checker(self, name: str, kind: str = "behavioural") -> None:
        """Write a checker script.

        `behavioural` observes the product and fails while the guard is absent.
        `positive_only` is the shape a checker takes when its unit tests never
        forced it to REJECT anything: it reports success unconditionally.
        """
        body = {
            "behavioural": (
                'if grep -q %s "$1"; then\n'
                "  printf '%%s\\n' '%s: OK'\n"
                "else\n"
                "  printf '%%s\\n' '%s: FAIL guard absent'\n"
                "  exit 1\n"
                "fi\n" % ("'ledger unreachable'", name, name)
            ),
            "positive_only": "printf '%%s\\n' '%s: OK'\n" % name,
        }[kind]
        path = self.root / "tests" / "checkers" / ("%s.sh" % name)
        path.write_text(
            '#!/usr/bin/env bash\ntouch "%s/%s.ran"\n%s' % (self.markers, name, body),
            encoding="utf-8",
        )
        path.chmod(0o755)

    def ran(self, name: str) -> bool:
        return (self.markers / ("%s.ran" % name)).exists()

    def forget_runs(self) -> None:
        for marker in self.markers.glob("*.ran"):
            marker.unlink()

    # -- spec --------------------------------------------------------------

    def registry(self, name: str, covers: str = "REQ-001", argv: list | None = None) -> str:
        return json.dumps(
            {
                "checkers": [
                    {
                        "id": name,
                        "covers": [c.strip() for c in covers.split(",")],
                        "path": "tests/checkers/%s.sh" % name,
                        "argv": argv or ["bash", "tests/checkers/%s.sh" % name, "src/ledger.py"],
                        "evidence": "tmp/contract-gate/inventory-sync/%s.{phase}.json" % name,
                        "output_ere": "%s: FAIL" % name,
                    }
                ]
            },
            indent=1,
        )

    def write_spec(
        self, *, registry: str | None = None, closed: bool = True, extra_req: str = ""
    ) -> None:
        """A spec the SHIPPED validator accepts.

        A gated requirement owes more than a bullet: a covering GWT scenario
        and a covering Eval declaration, byte-identical between tasks.md and
        design.md (CPR-D). Leaving those out produced a fixture that could
        never validate — and the defect was in the fixture, not in the gates it
        was written to exercise.
        """
        reqs = ["REQ-001"] + (["REQ-002"] if extra_req else [])
        covers = ", ".join(reqs)
        scenarios = "".join(
            "<!-- mb-scenario:%d -->\n### Scenario: %s holds\n**Covers:** %s\n\n"
            "- GIVEN the system\n- WHEN a batch is submitted\n- THEN %s holds\n"
            "<!-- /mb-scenario:%d -->\n\n" % (i, r.lower().replace("-", "_"), r, r, i)
            for i, r in enumerate(reqs, 1)
        )
        (self.spec / "requirements.md").write_text(
            "---\ntopic: inventory-sync\nlayers:\n  contract_first: true\n"
            "  integration_tests: false\n"
            '  integration_tests_reason: "covered by the parent slice"\n'
            "  e2e_tests: false\n"
            '  e2e_tests_reason: "no external surface"\n---\n\n'
            "# Requirements: inventory-sync\n\n## Requirements (EARS)\n\n"
            "- **REQ-001** (unwanted): If the ledger is unreachable, then the system shall "
            "fail the batch loudly.\n" + extra_req + "\n## Scenarios\n\n" + scenarios,
            encoding="utf-8",
        )
        eval_line = (
            "**Eval:** `pytest tests/pytest/test_ledger.py` %s red: guard absent; exit: 1; "
            "output~: `FAILED tests/pytest/test_ledger\\.py::test_batch_fails_loudly`" % DASH
        )
        (self.spec / "design.md").write_text(
            "# Design: inventory-sync\n\n## Contract\n\n**Seams:**\n- the ledger write "
            "boundary\n\n## Eval declarations\n\n- **T2** %s Loud batch failure:\n  %s\n"
            % (DASH, eval_line),
            encoding="utf-8",
        )
        block = "\n```json Contract-checkers\n%s\n```\n" % registry if registry else ""
        (self.spec / "tasks.md").write_text(
            "# Tasks: inventory-sync\n\n<!-- mb-task:1 -->\n## Task 1: Contract checkers\n\n"
            "**Stage:** 1\n**Layer:** contract\n**Covers:** %s\n**Role:** backend\n"
            "**Blocked-by:** none\n**Scope:** tests/**\n**Budget:** 100000\n\n"
            "**What to do:**\n- declare and build the checkers.\n"
            % covers
            + block
            + "\n**Testing (TDD %s tests BEFORE implementation):**\n- checker unit tests.\n\n"
            "**DoD:**\n- [%s] checkers red against the product\n<!-- /mb-task:1 -->\n\n"
            "<!-- mb-task:2 -->\n## Task 2: Loud batch failure\n\n"
            "**Stage:** 2\n**Covers:** %s\n**Role:** backend\n**Blocked-by:** 1\n"
            "**Scope:** src/**\n**Budget:** 100000\n%s\n\n**What to do:**\n- add the guard.\n\n"
            "**Testing (TDD):**\n- unit test.\n\n**DoD:**\n- [ ] guard present\n"
            "<!-- /mb-task:2 -->\n" % (DASH, "x" if closed else " ", covers, eval_line),
            encoding="utf-8",
        )

    # -- the gate ----------------------------------------------------------

    def gate(self, phase: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(GATE), phase, "--spec", str(self.spec), "--mb", str(self.bank)],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
        )

    def evidence(self, name: str, phase: str) -> dict:
        path = (
            self.bank / "tmp" / "contract-gate" / "inventory-sync" / ("%s.%s.json" % (name, phase))
        )
        return json.loads(path.read_text(encoding="utf-8"))

    def evidence_exists(self, name: str, phase: str) -> bool:
        return (
            self.bank / "tmp" / "contract-gate" / "inventory-sync" / ("%s.%s.json" % (name, phase))
        ).exists()


def world(tmp_path: Path, *, kind: str = "behavioural", covers: str = "REQ-001") -> World:
    w = World(tmp_path)
    w.checker("ledger_gate", kind)
    w.write_spec(registry=w.registry("ledger_gate", covers))
    return w


# ── REQ-020: verify runs the checkers — THREE outcomes, not two ────────────


def test_REQ_020__verify_runs_the_contract_checkers(tmp_path: Path) -> None:
    """ran-and-green · ran-and-red · never-ran. The third must not read as the first."""
    w = world(tmp_path)

    # red phase: the guard is absent, so the checker fails for its declared reason
    red = w.gate("red")
    assert red.returncode == 0, red.stdout + red.stderr
    assert w.evidence("ledger_gate", "red")["verdict"] == "pass"
    assert w.ran("ledger_gate")

    # ── outcome A: implementation landed → checkers RUN and are green
    w.implement()
    w.forget_runs()
    green = w.gate("verify")
    assert green.returncode == 0, green.stdout + green.stderr
    assert w.ran("ledger_gate"), "verify reported success without running the checker"
    assert json.loads(green.stdout)["verdict"] == "pass"
    assert w.evidence("ledger_gate", "verify")["phase"] == "verify"

    # ── outcome B: implementation reverted → checkers RUN and are red
    w.product.write_text("def submit(batch):\n    return len(batch)\n", encoding="utf-8")
    w.forget_runs()
    still_red = w.gate("verify")
    assert still_red.returncode == 1, still_red.stdout
    assert w.ran("ledger_gate")
    assert json.loads(still_red.stdout)["verdict"] == "red_checker"

    # ── outcome C: the red was never observed → checkers DO NOT RUN
    # Distinguished by the marker, not by the exit code: this is the outcome
    # that has repeatedly been mistaken for outcome A.
    fresh = world(tmp_path / "unwitnessed")
    fresh.implement()
    unwitnessed = fresh.gate("verify")
    assert unwitnessed.returncode == 2, unwitnessed.stdout
    assert not fresh.ran("ledger_gate"), "verify executed a checker whose red was never observed"
    assert unwitnessed.stdout == "", "a refused verify must not print a verdict"
    assert not fresh.evidence_exists("ledger_gate", "verify")


def test_REQ_020__registry_edited_after_red_does_not_verify(tmp_path: Path) -> None:
    """Outcome C's other door: the red belongs to a command that changed."""
    w = world(tmp_path)
    assert w.gate("red").returncode == 0
    w.implement()
    # Same checker, different argv — the observed red is not this command's.
    # Built rather than string-replaced: the first version patched a formatting
    # that json.dumps does not emit, so the registry was never changed and the
    # test proved nothing while passing.
    w.write_spec(
        registry=w.registry(
            "ledger_gate",
            argv=["bash", "-c", "bash tests/checkers/ledger_gate.sh src/ledger.py"],
        )
    )
    w.forget_runs()
    drifted = w.gate("verify")
    assert drifted.returncode == 2, drifted.stdout
    assert not w.ran("ledger_gate")


# ── REQ-004: a checker green before the code is not evidence ──────────────


def test_REQ_004__fake_red_fails_the_contract_task(tmp_path: Path) -> None:
    """Caught by a REAL run of a real checker, never by a planted evidence file."""
    w = World(tmp_path)
    # The checker passes unconditionally — and the product has no guard, so a
    # green here is decided by the checker's own emptiness, not by the code.
    w.checker("ledger_gate", "positive_only")
    w.write_spec(registry=w.registry("ledger_gate"))
    tasks_before = hashlib.sha256((w.spec / "tasks.md").read_bytes()).hexdigest()

    red = w.gate("red")
    assert red.returncode == 1, red.stdout
    assert w.ran("ledger_gate"), "the verdict must come from running it, not from inspection"
    assert json.loads(red.stdout)["verdict"] == "fake_red"
    assert w.evidence("ledger_gate", "red")["verdict"] == "fake_red"

    # The hard stop is real: the item stays open and verify remains locked.
    assert hashlib.sha256((w.spec / "tasks.md").read_bytes()).hexdigest() == tasks_before, (
        "the gate edited the task — the checkbox is the orchestrator's to flip"
    )
    w.implement()
    w.forget_runs()
    locked = w.gate("verify")
    assert locked.returncode == 2, locked.stdout
    assert not w.ran("ledger_gate"), "a fake_red unlocked verify"


def test_REQ_004__foreign_failure_is_not_a_red_either(tmp_path: Path) -> None:
    """Failing is not enough — it has to fail for the declared reason."""
    w = World(tmp_path)
    path = w.root / "tests" / "checkers" / "ledger_gate.sh"
    w.checker("ledger_gate")
    path.write_text(
        '#!/usr/bin/env bash\ntouch "%s/ledger_gate.ran"\n'
        "printf '%%s\\n' 'ImportError: no module named ledger'\nexit 1\n" % w.markers,
        encoding="utf-8",
    )
    path.chmod(0o755)
    w.write_spec(registry=w.registry("ledger_gate"))
    red = w.gate("red")
    assert red.returncode == 1, red.stdout
    assert json.loads(red.stdout)["verdict"] == "foreign_failure"
    assert w.evidence("ledger_gate", "red")["output_match"] is False


# ── REQ-003: a checker with no negative half cannot be evidence ───────────


def test_REQ_003__checker_without_a_negative_fixture_rejected(tmp_path: Path) -> None:
    """A checker whose tests never made it REJECT is one that never rejects.

    There is no way to inspect a checker's unit tests from here, and inventing
    one would be theatre. What IS observable is the consequence: a checker with
    only a positive half returns 0 against an unimplemented product, and the
    red gate refuses it. The rule and its mechanical shadow are the same event.
    """
    positive_only = world(tmp_path, kind="positive_only")
    verdict = positive_only.gate("red")
    assert verdict.returncode == 1
    assert json.loads(verdict.stdout)["verdict"] == "fake_red"

    # A checker carrying both halves passes the same gate on the same product.
    both_halves = world(tmp_path / "both")
    assert both_halves.gate("red").returncode == 0

    # And the generated contract task demands both halves in writing, so the
    # rule reaches the implementer rather than living only in this test.
    rendered = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts" / "mb-sdd-layers-render.py"),
            "--requirements",
            str(positive_only.spec / "requirements.md"),
            "--pipeline",
            str(REPO_ROOT / "references" / "pipeline.default.yaml"),
            "--rules-json",
            str(_rules_json(tmp_path)),
        ],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert rendered.returncode == 0, rendered.stderr
    contract = json.loads(rendered.stdout)["tasks_markdown"]
    assert "REJECTING" in contract and "ACCEPTING" in contract, contract


def _rules_json(tmp_path: Path) -> Path:
    path = tmp_path / "rules.json"
    if not path.exists():
        resolved = subprocess.run(
            ["bash", str(REPO_ROOT / "scripts" / "mb-rules-resolve.sh"), "--json"],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
        )
        assert resolved.returncode == 0, resolved.stderr
        path.write_text(resolved.stdout, encoding="utf-8")
    return path


# ── REQ-006: a requirement no checker can observe is escalated ────────────


def test_REQ_006__unobservable_requirement_escalates(tmp_path: Path) -> None:
    """A gated REQ with no checker covering it stops the spec, loudly.

    This is the escalation with teeth: the contract task cannot be closed while
    a gated requirement has nothing that can observe it, so "we could not think
    of a checker" surfaces as a refusal instead of a quietly missing check.
    """
    w = World(tmp_path)
    w.checker("ledger_gate")
    w.write_spec(
        registry=w.registry("ledger_gate", covers="REQ-001"),
        extra_req="- **REQ-002** (ubiquitous): The system shall feel intuitive to operators.\n",
    )
    result = subprocess.run(
        ["bash", str(VALIDATE), str(w.spec)], capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    assert result.returncode == 1, result.stdout + result.stderr
    assert "REQ-002 is gated but is covered by no checker" in result.stdout + result.stderr

    # Cover it, and the same spec is accepted — the refusal is about coverage,
    # not about the number of requirements.
    w.write_spec(
        registry=w.registry("ledger_gate", covers="REQ-001, REQ-002"),
        extra_req="- **REQ-002** (ubiquitous): The system shall feel intuitive to operators.\n",
    )
    covered = subprocess.run(
        ["bash", str(VALIDATE), str(w.spec)], capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    assert covered.returncode == 0, covered.stdout + covered.stderr


def test_REQ_006__open_contract_task_owes_no_registry(tmp_path: Path) -> None:
    """The escalation fires on closure, not on a task that has not got there."""
    w = World(tmp_path)
    w.checker("ledger_gate")
    w.write_spec(registry=None, closed=False)
    result = subprocess.run(
        ["bash", str(VALIDATE), str(w.spec)], capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    assert result.returncode == 0, result.stdout + result.stderr


# ── determinism ───────────────────────────────────────────────────────────


def test_e2e_run_is_deterministic(tmp_path: Path) -> None:
    """Two independent runs produce byte-identical evidence (no clock, no net)."""
    first = world(tmp_path / "a")
    second = world(tmp_path / "b")
    assert first.gate("red").returncode == 0
    assert second.gate("red").returncode == 0
    assert first.evidence("ledger_gate", "red") == second.evidence("ledger_gate", "red")
