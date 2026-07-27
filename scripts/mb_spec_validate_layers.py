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
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
sys.path.insert(0, str(Path(os.environ["MB_SCRIPT_DIR"]).resolve().parent))

import mb_req_id as rq  # noqa: E402

from memory_bank_skill.spec_layers import SpecLayersError, read_spec_layers  # noqa: E402

LAYERS = ("contract", "integration", "e2e")
LAYER_FLAGS = ("contract_first", "integration_tests", "e2e_tests")
CHECKER_KEYS = ("id", "covers", "path", "argv", "evidence", "output_ere")

_LAYER_FIELD_RE = re.compile(r"^\*\*Layer:\*\*[ \t]*(.*?)[ \t]*$", re.IGNORECASE | re.MULTILINE)
# Normative SHALL/MUST only: SHOULD and MAY do not gate (D-06).
_NORMATIVE_RE = re.compile(r"\b(shall|must)\b", re.IGNORECASE)
_CHECKER_ID_RE = re.compile(r"^[a-z0-9_]+$")
_REGISTRY_RE = re.compile(
    r"^```json[ \t]+Contract-checkers[ \t]*\n(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL
)

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


def ere_ok(pattern: str) -> bool:
    """Compile with the SAME engine used at execution time (grep -E, exit 2)."""
    try:
        return (
            subprocess.run(
                ["grep", "-E", "--", pattern],
                input="",
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            ).returncode
            != 2
        )
    except OSError:
        return False


def gated_reqs(text: str) -> list[str]:
    """REQ-IDs whose EARS criterion carries a normative SHALL or MUST.

    The chunking mirrors ``mb-ears-validate.sh``: a requirement may wrap onto
    indented continuation lines, and the chunk stops at a blank line, the next
    REQ bullet, or any new list item / heading — so one requirement's verb
    never leaks into its neighbour's.
    """
    lines = text.splitlines()
    n = len(lines)
    out: list[str] = []
    i = 0
    while i < n:
        m = rq.EARS_REQ_LINE_RE.match(lines[i])
        if not m:
            i += 1
            continue
        chunk = [lines[i]]
        j = i + 1
        while j < n:
            nxt = lines[j]
            if not nxt.strip() or rq.EARS_REQ_LINE_RE.match(nxt) or nxt.lstrip()[:1] in "-*+#":
                break
            chunk.append(nxt)
            j += 1
        if _NORMATIVE_RE.search(" ".join(chunk)):
            out.append("REQ-" + m.group(1))
        i = j
    return out


def layer_of(body: str) -> str | None:
    """The task's ``**Layer:**`` value, or None for an implementation task."""
    m = _LAYER_FIELD_RE.search(body or "")
    return m.group(1) if m else None


# ── C3a: the Contract-checkers registry ─────────────────────────────────────


def _check_evidence(label: str, value: str, prefix: str) -> None:
    if not isinstance(value, str) or not value:
        bad("Contract-checkers: checker %s evidence must be a non-empty string" % label)
        return
    if value.startswith("/"):
        bad(
            "Contract-checkers: checker %s evidence must be bank-relative, got `%s`"
            % (label, value)
        )
        return
    if ".." in Path(value).parts:
        bad(
            "Contract-checkers: checker %s evidence must not escape the bank: `%s`" % (label, value)
        )
        return
    if not value.startswith(prefix):
        bad(
            "Contract-checkers: checker %s evidence must live under `%s`, got `%s`"
            % (label, prefix, value)
        )
        return
    if "{phase}" not in value:
        bad("Contract-checkers: checker %s evidence needs the `{phase}` placeholder" % label)


def _check_checker(entry, index: int, prefix: str, covered: set, ids: set) -> None:
    label = "#%d" % index
    if not isinstance(entry, dict):
        bad("Contract-checkers: checker %s must be an object" % label)
        return
    if isinstance(entry.get("id"), str):
        label = "`%s`" % entry["id"]

    for key in entry:
        if key not in CHECKER_KEYS:
            bad("Contract-checkers: checker %s has an unknown key `%s`" % (label, key))
    for key in CHECKER_KEYS:
        if key not in entry:
            bad("Contract-checkers: checker %s is missing key `%s`" % (label, key))

    ident = entry.get("id")
    if not isinstance(ident, str) or not _CHECKER_ID_RE.match(ident):
        bad("Contract-checkers: checker %s id must match [a-z0-9_]+" % label)
    elif ident in ids:
        bad("Contract-checkers: checker id `%s` is used more than once" % ident)
    else:
        ids.add(ident)

    covers = entry.get("covers")
    if not isinstance(covers, list) or not covers:
        bad("Contract-checkers: checker %s covers must be a non-empty array" % label)
    else:
        for token in covers:
            if not isinstance(token, str) or not rq.COVERS_TOKEN_RE.match(token):
                bad("Contract-checkers: checker %s covers `%s` is not a REQ-ID" % (label, token))
            else:
                covered.add(rq.canon(token))

    if not isinstance(entry.get("path"), str) or not entry["path"]:
        bad("Contract-checkers: checker %s path must be a non-empty string" % label)

    argv = entry.get("argv")
    if not isinstance(argv, list) or not argv or not all(isinstance(a, str) for a in argv):
        bad("Contract-checkers: checker %s argv must be a non-empty array of strings" % label)

    if "evidence" in entry:
        _check_evidence(label, entry["evidence"], prefix)

    ere = entry.get("output_ere")
    if not isinstance(ere, str) or not ere:
        bad("Contract-checkers: checker %s output_ere must be a non-empty string" % label)
    elif not ere_ok(ere):
        bad("Contract-checkers: checker %s output_ere does not compile as a POSIX ERE" % label)


def check_registry(task: dict, topic: str, gated: list) -> None:
    """Schema of the registry carried by a CLOSED contract task (C3a).

    Checked on closure and not before: the registry is written by the
    orchestrator between the task's two implementer dispatches, so demanding it
    from an open task would fail the task for not yet having reached its own
    second step.
    """
    item = task.get("item_no")
    m = _REGISTRY_RE.search(task.get("body", ""))
    if not m:
        bad(
            "Contract-checkers: the closed contract task (task %s) carries no "
            "```json Contract-checkers``` block" % item
        )
        return
    try:
        data = json.loads(m.group(1))
    except ValueError as exc:
        bad("Contract-checkers: task %s block is not valid JSON — %s" % (item, exc))
        return

    if not isinstance(data, dict):
        bad("Contract-checkers: task %s block must be a JSON object" % item)
        return
    for key in data:
        if key != "checkers":
            bad("Contract-checkers: unknown top-level key `%s`" % key)
    checkers = data.get("checkers")
    if not isinstance(checkers, list) or not checkers:
        bad("Contract-checkers: task %s needs a non-empty `checkers` array" % item)
        return

    prefix = "tmp/contract-gate/%s/" % topic
    covered: set = set()
    ids: set = set()
    for index, entry in enumerate(checkers, 1):
        _check_checker(entry, index, prefix, covered, ids)

    for req in gated:
        if rq.canon(req) not in covered:
            bad("Contract-checkers: %s is gated but is covered by no checker" % req)


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
    if layers.e2e_tests:
        after, what = last_impl, "every implementation task"
        if integration_pos > after:
            after, what = integration_pos, "the `**Layer:** integration` task"
        order_gate("e2e", "e2e_tests", by_layer.get("e2e", []), after, what)

    if layers.contract_first and gated and len(contract) == 1:
        task = contract[0][1]
        if task.get("status") == "done":
            check_registry(task, spec_dir.name, gated)
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
