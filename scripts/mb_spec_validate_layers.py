"""Test-layer gates C3/C4 and the Contract-checkers schema, for mb-spec-validate.sh.

svp-contract-test-loop Task 3 (REQ-001/007/008/014). A sibling of
``mb_spec_validate_tasks.py`` / ``mb_spec_validate_v2.py``: the shell script is
the driver, each gate family is a module it runs as a subprocess with the same
env-var contract.

Env contract:
  TASKS_DATA     JSONL of parsed work items (one object per line, file order)
  REQ_PATH       path to requirements.md
  SPEC_DIR       the spec directory (its basename is the topic)
  PIPELINE_YAML  resolved pipeline config (``sdd.layers`` defaults)
  MB_SCRIPT_DIR  scripts/ dir

Violations go to stdout, one per line, for the caller to append to its
violations file. The layer REPORT (REQ-014) goes to stderr, so ``--json`` mode
keeps a single JSON object on stdout.

THE ONE RULE THAT DECIDES WHETHER ANY OF THIS RUNS
──────────────────────────────────────────────────
A spec with no ``layers`` block is LEGACY (R3-001): not one gate applies, and
the spec is judged exactly as it was before S8. Without that, every spec
written before this slice becomes invalid the moment the gates land —
including this slice's OWN spec, which has gated requirements, no block, and
its ``**Layer:**`` tasks at the end.

The trap the rule sets, and why the code below refuses it: "no block" and "the
block is broken" must NOT collapse into the same answer. ``read_spec_layers``
raises on a block in the wrong file, on a layer switched off without a reason,
on a malformed pipeline default. Treating a raise as "no block → legacy" would
switch every gate off exactly when the block is wrong — a gate that disappears
on bad input is not a gate. A raise is recorded as a violation instead, and the
gates are skipped only because their input is unknown, not because the spec was
found innocent.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
sys.path.insert(0, str(Path(os.environ["MB_SCRIPT_DIR"]).resolve().parent))

import mb_contract_registry as registry  # noqa: E402
import mb_req_id as rq  # noqa: E402

from memory_bank_skill.spec_layers import SpecLayersError, read_spec_layers  # noqa: E402

LAYERS = registry.LAYERS
LAYER_FLAGS = ("contract_first", "integration_tests", "e2e_tests")

violations: list[str] = []


def bad(msg: str) -> None:
    violations.append(msg)


def note(msg: str) -> None:
    """The layer report (REQ-014) — stderr, and only on a HUMAN run.

    ``--json`` mode carries a standing contract that stderr stays EMPTY
    (``tests/pytest/test_mb_spec_validate.py``): a machine caller reads that
    stream as the error channel, so one informational line there turns a clean
    validation into an apparent failure. A machine that wants the layer state
    asks the API that owns it -- ``python3 -m memory_bank_skill.spec_layers
    --requirements PATH --pipeline PATH --json`` (C1) -- rather than scraping a
    human report out of a second channel.
    """
    if os.environ.get("MB_SPEC_VALIDATE_JSON") == "1":
        return
    sys.stderr.write("[spec-validate] %s\n" % msg)


# Both predicates are shared on purpose. `gated_definitions` decides here
# whether a contract task is REQUIRED and in `mb-sdd-layers-render.py` what it
# COVERS; two copies would let a spec be told it needs a contract task for
# requirements that task does not name.
gated_reqs = rq.gated_definitions
layer_of = registry.layer_of


# ── C3a: the Contract-checkers registry ─────────────────────────────────────


_TEST_TOKEN_RE = re.compile(
    r"`[^`]*(?:pytest|bats|go test|cargo test|npm test|jest|rspec)[^`]*`"
    r"|`[^`]*/[^`]*test[^`]*`",
    re.IGNORECASE,
)


def _names_checker_tests(task: dict) -> bool:
    """Does a DoD line name a runnable command or path for the checker tests?"""
    return any(_TEST_TOKEN_RE.search(line) for line in task.get("dod_lines") or [])


def check_registry(task: dict, topic: str, gated: list) -> None:
    """The Contract-checkers registry (C3a).

    PRESENCE is required only on closure: the registry is written by the
    orchestrator between the task's two implementer dispatches, so demanding it
    from an open task would fail the task for not yet having reached its own
    second step.

    CONTENT is checked whenever a registry exists, open or closed. Gating
    completeness on closure put the "every gated REQ has a checker" guarantee
    after the work it governs: the registry is written while the task is still
    open, and Dispatch B, the red gate and every business dispatch all happen
    in that state. A gate that first speaks once the job is done is a report.

    The schema itself lives in ``mb_contract_registry`` because
    ``mb-contract-gate.sh`` enforces the same closed shape at run time. Two
    implementations of one schema drift apart in exactly one direction: a
    registry this validator calls fine and the gate refuses at exit 2.
    """
    item = task.get("item_no")
    if task.get("status") == "done" and not _names_checker_tests(task):
        # Step 2 of the contract task demands unit tests showing every checker
        # REJECT a violating fixture and ACCEPT a conforming one, and step 4
        # demands they be green. Both were prose: `commands/work.md`'s "Once
        # the checker unit tests are green" was read by nothing, so a closed
        # contract task could carry checkers whose tests were never written.
        # No code can run tests it cannot name — so on closure the DoD has to
        # name them. That is not proof they assert both halves; it is the
        # difference between a claim anyone can check and one nobody can.
        bad(
            "Contract-checkers: the closed contract task (task %s) does not name the "
            "checker unit tests in its DoD (a runnable command or test path)" % item
        )
    text = registry.find_registry(task.get("body", ""))
    if text is None:
        if task.get("status") == "done":
            bad(
                "Contract-checkers: the closed contract task (task %s) carries no "
                "```json Contract-checkers``` block" % item
            )
        return

    checkers, errors = registry.parse_registry(text, topic)
    for err in errors:
        bad(err)

    # WHAT THIS GUARANTEE IS, EXACTLY: every gated REQ-ID appears in some
    # checker's `covers`. It is ID MEMBERSHIP, not evidence that the checker
    # observes the requirement — no code can decide the latter, and claiming
    # otherwise would be the decorative kind of promise this slice removes.
    # Relabelling one checker to cover three requirements satisfies it, so the
    # relabelling is made VISIBLE instead of being silently sufficient: a
    # checker carrying several gated REQs is named in the report for a human
    # to judge.
    covered = registry.covered_reqs(checkers)
    for req in gated:
        if rq.canon(req) not in covered:
            bad("Contract-checkers: %s is gated but is covered by no checker" % req)

    gated_set = {rq.canon(r) for r in gated}
    for entry in checkers:
        if not isinstance(entry, dict):
            continue
        claimed = sorted(
            {t.split(":")[-1] for t in entry.get("covers") or [] if isinstance(t, str)} & gated_set
        )
        if len(claimed) > 1:
            note(
                "contract_checkers: `%s` claims %d gated requirements (%s) — "
                "one checker per requirement is the reviewable shape"
                % (entry.get("id"), len(claimed), ", ".join(claimed))
            )


# ── C3/C4: the gates ────────────────────────────────────────────────────────


def contract_gate(layers, contract: list, impl: list, gated: list) -> None:
    if not layers.contract_first:
        for _pos, task in contract:
            bad(
                "layers: contract_first is off, but task %s declares `**Layer:** contract`"
                % task.get("item_no")
            )
        return
    if not gated:
        # REQ-001 is state-driven on BOTH conditions; without a gated
        # requirement there is nothing for a checker to observe.
        note("contract_layer=not_applicable")
        return
    if len(contract) != 1:
        bad(
            "layers: contract_first is on with gated requirements, but tasks.md has %d "
            "`**Layer:** contract` tasks (exactly one required)" % len(contract)
        )
    if contract and impl and contract[0][0] > impl[0][0]:
        bad(
            "layers: the `**Layer:** contract` task (task %s) must come before every "
            "implementation task (task %s is first)"
            % (contract[0][1].get("item_no"), impl[0][1].get("item_no"))
        )


def forbid_disabled_layer(name: str, flag: str, tasks_of: list) -> None:
    """A layer switched off must not still carry its task.

    `contract_first` already refused this; the other two only stopped
    REQUIRING their task, which let a spec record "no e2e, because <reason>"
    and carry an e2e task anyway. Two statements, opposite meanings, no way for
    a reader to tell which is current — and the recorded refusal, the one thing
    REQ-011 exists to preserve, is the one that loses.
    """
    for _pos, task in tasks_of:
        bad(
            "layers: %s is off, but task %s declares `**Layer:** %s`"
            % (flag, task.get("item_no"), name)
        )


def order_gate(name: str, flag: str, tasks_of: list, after_pos: int, after_what: str) -> int:
    """One row of the C4 matrix. Returns the layer task's position, or -1."""
    if len(tasks_of) != 1:
        bad(
            "layers: %s is on, but tasks.md has %d `**Layer:** %s` tasks (exactly one required)"
            % (flag, len(tasks_of), name)
        )
        return -1
    pos, task = tasks_of[0]
    if pos < after_pos:
        bad(
            "layers: the `**Layer:** %s` task (task %s) must come after %s"
            % (name, task.get("item_no"), after_what)
        )
    return pos


def main() -> int:
    tasks = []
    for line in os.environ.get("TASKS_DATA", "").splitlines():
        line = line.strip()
        if line:
            try:
                tasks.append(json.loads(line))
            except json.JSONDecodeError:
                pass

    req_path = Path(os.environ["REQ_PATH"])
    spec_dir = Path(os.environ.get("SPEC_DIR") or req_path.parent)
    pipeline = Path(os.environ.get("PIPELINE_YAML", ""))

    try:
        layers = read_spec_layers(req_path, pipeline)
    except SpecLayersError as exc:
        bad("layers: %s (%s)" % (exc.code, exc.field or "-"))
        return emit()
    except OSError as exc:
        bad("layers: requirements.md could not be read (%s)" % exc)
        return emit()

    note("layers=%s" % layers.source)
    if layers.source == "legacy":
        return emit()

    disabled = [flag for flag in LAYER_FLAGS if not getattr(layers, flag)]
    if disabled:
        note("layers_disabled=%s" % ",".join(disabled))

    by_layer: dict = {}
    impl: list = []
    for pos, task in enumerate(tasks):
        value = layer_of(task.get("body", ""))
        if value is None:
            impl.append((pos, task))
        elif value in LAYERS:
            by_layer.setdefault(value, []).append((pos, task))
        else:
            bad(
                "layers: task %s declares an unknown `**Layer:** %s` (allowed: %s)"
                % (task.get("item_no"), value or "<empty>", ", ".join(LAYERS))
            )

    gated = gated_reqs(req_path.read_text(encoding="utf-8"))
    contract = by_layer.get("contract", [])
    contract_gate(layers, contract, impl, gated)

    last_impl = max([pos for pos, _ in impl], default=-1)
    integration_pos = -1
    if layers.integration_tests:
        integration_pos = order_gate(
            "integration",
            "integration_tests",
            by_layer.get("integration", []),
            last_impl,
            "every implementation task",
        )
    else:
        forbid_disabled_layer("integration", "integration_tests", by_layer.get("integration", []))
    if layers.e2e_tests:
        after, what = last_impl, "every implementation task"
        if integration_pos > after:
            after, what = integration_pos, "the `**Layer:** integration` task"
        order_gate("e2e", "e2e_tests", by_layer.get("e2e", []), after, what)
    else:
        forbid_disabled_layer("e2e", "e2e_tests", by_layer.get("e2e", []))

    if layers.contract_first and gated and len(contract) == 1:
        # Always called: `check_registry` itself decides that ABSENCE is only a
        # violation once the task is closed, while CONTENT is judged whenever a
        # registry exists. The status test used to live here, which skipped the
        # content checks for the whole window in which the registry is written
        # and acted upon.
        check_registry(contract[0][1], spec_dir.name, gated)
    return emit()


def emit() -> int:
    """Violations to stdout; the exit code stays 0, as every sibling gate does.

    The caller decides the verdict from the collected violation lines, so a
    non-zero exit here would be indistinguishable from the module itself
    crashing.
    """
    for line in violations:
        sys.stdout.write(line + "\n")
    return 0


main()
