#!/usr/bin/env python3
"""Deterministic renderer for the test-layer tasks and the Quality DoD (C8).

    python3 scripts/mb-sdd-layers-render.py --requirements PATH --pipeline PATH \
                                            --rules-json PATH --json

stdout is exactly one envelope:

    {"tasks_markdown": "<string>", "quality_dod_markdown": "<string>"}

`tasks_markdown` goes ONLY into `tasks.candidate.md`; `quality_dod_markdown`
goes ONLY into the staged `design.md`. This script writes no files at all —
the accepted triple is written by the orchestrator (S2-C3).

WHY A RENDERER EXISTS AT ALL
────────────────────────────
The spec generator is an LLM prompt, and there is no honest way to unit-test a
prompt. So the parts that CAN be decided by code are taken away from it: which
layer tasks exist, in what order, with which scenario ids in their DoD, and
what the Quality DoD section says. What remains prompt-shaped — which checkers
to declare, how to word a requirement — is caught afterwards by
`mb-spec-validate.sh` (C3/C4) and the C8 battery, not pretended away here.

TWO REFUSALS WORTH KNOWING
──────────────────────────
* A spec with NO `layers` block is legacy and cannot be rendered (exit 1).
  Rendering it as "all layers off" would silently turn a missing decision into
  a recorded one.
* All three layers off still emits a Quality DoD (REQ-015). Turning layers off
  is a speed decision about TASKS; it was never a decision to drop the rules
  the work is judged by, and an empty envelope would quietly make it one.

Exit: 0 rendered · 1 invalid layers / unusable rules JSON / unresolvable
scenarios · 2 usage.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(SCRIPT_DIR.parent))

import mb_req_id as rq  # noqa: E402

from memory_bank_skill.spec_layers import SpecLayersError, read_spec_layers  # noqa: E402

RULES_KEYS = {"sources", "review_rubric", "fallback_used", "checker"}
SOURCE_KEYS = {"kind", "path"}


def fail(message: str, code: int = 1) -> int:
    """Refuse on stderr, print NOTHING on stdout.

    A caller that reads only stdout must not be able to mistake a refusal for
    an empty-but-valid render.
    """
    sys.stderr.write("[sdd-layers-render] %s\n" % message)
    return code


# ── inputs ──────────────────────────────────────────────────────────────────


def load_rules(path: Path) -> dict:
    """The canonical JSON from `mb-rules-resolve.sh`, schema-checked."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("rules JSON must be an object")
    unknown = sorted(set(data) - RULES_KEYS)
    if unknown:
        raise ValueError("unknown key(s) in rules JSON: %s" % ", ".join(unknown))
    missing = sorted(RULES_KEYS - set(data))
    if missing:
        raise ValueError("missing key(s) in rules JSON: %s" % ", ".join(missing))
    if not isinstance(data["sources"], list) or not data["sources"]:
        raise ValueError("rules JSON `sources` must be a non-empty array")
    for entry in data["sources"]:
        if not isinstance(entry, dict) or set(entry) != SOURCE_KEYS:
            raise ValueError("each rules source needs exactly {kind, path}")
    if not isinstance(data["review_rubric"], list):
        raise ValueError("rules JSON `review_rubric` must be an array")
    if not isinstance(data["checker"], str) or not data["checker"]:
        raise ValueError("rules JSON `checker` must be a non-empty string")
    return data


def scenario_test_names(requirements: Path) -> list[str]:
    """`test_` + test_id with `-` → `_`, in document order (C4 mapping rule).

    The ids come from `mb-scenario-extract.py`, the tool that already owns
    them; inventing a second id scheme here would give the DoD and the test
    files two different names for the same scenario.
    """
    proc = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "mb-scenario-extract.py"), str(requirements)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise ValueError("mb-scenario-extract.py failed: %s" % proc.stderr.strip())
    names = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        test_id = json.loads(line).get("test_id")
        if not test_id:
            raise ValueError("a scenario has no test_id")
        names.append("test_" + test_id.replace("-", "_"))
    return names


# ── rendering ───────────────────────────────────────────────────────────────


def block(number: int, title: str, fields: list, body: str, testing: str, dod: list) -> str:
    lines = ["<!-- mb-task:%d -->" % number, "## Task %d: %s" % (number, title), ""]
    lines += fields + ["", "**What to do:**", body.rstrip(), ""]
    lines += ["**Testing (TDD — tests BEFORE implementation):**", testing.rstrip(), ""]
    lines += ["**DoD:**"] + ["- [ ] %s" % d for d in dod]
    lines += ["<!-- /mb-task:%d -->" % number, ""]
    return "\n".join(lines)


def contract_block(number: int, gated: list) -> str:
    return block(
        number,
        "Contract checkers",
        [
            "**Stage:** 1",
            "**Layer:** contract",
            "**Covers:** %s" % ", ".join(gated),
            "**Role:** backend",
            "**Blocked-by:** none",
            "**Scope:** tests/**",
            "**Budget:** 100000",
        ],
        "\n".join(
            [
                "1. Declare one checker per gated requirement — id, covers, the argv that runs it,"
                " its bank-relative evidence path, and the ERE its genuine failure prints."
                " This step writes no product files and no business code.",
                "2. Write the checker unit tests on fixtures: every checker is shown REJECTING a"
                " violating fixture AND ACCEPTING a conforming one. One half alone is not a test.",
                "3. Implement the checkers.",
                "4. Make the checker unit tests green.",
                "5. Observe the checkers red against the product that does not implement the"
                " requirement yet: `bash scripts/mb-contract-gate.sh red --spec <spec-dir>"
                " --mb <bank>`.",
            ]
        ),
        "- Checker unit tests on fixtures, both halves for each checker.",
        [
            "Checker unit tests green (step 4)",
            "`mb-contract-gate.sh red` exits 0 — every checker failed for the reason it declared"
            " (step 5). A checker that is green before the implementation is `fake_red` and leaves"
            " this task open; one that failed for another reason is `foreign_failure`.",
        ],
    )


def layer_block(number: int, layer: str, stage: int, covers: list, names: list) -> str:
    kind = "Integration" if layer == "integration" else "E2E"
    scope = "tests/**" if layer == "integration" else "tests/e2e/**"
    return block(
        number,
        "%s tests" % kind,
        [
            "**Stage:** %d" % stage,
            "**Layer:** %s" % layer,
            "**Covers:** %s" % ", ".join(covers),
            "**Role:** qa",
            "**Scope:** %s" % scope,
            "**Budget:** 100000",
        ],
        "\n".join(
            [
                "- %s tests over the real wiring; mock only external boundaries." % kind,
                "- Test function names follow the C4 mapping rule: `test_` + the scenario's"
                " `test_id` with `-` replaced by `_`.",
            ]
        ),
        "- The success scenario plus the spec's main edge scenarios.",
        [
            "Covers scenario test ids: %s; green (were red)" % ", ".join("`%s`" % n for n in names),
            "External mocks ≤5 (Testing Trophy)",
        ],
    )


def render_tasks(layers, gated: list, all_reqs: list, names: list) -> str:
    """Layer task blocks in the canonical C4 order; a disabled layer is absent.

    Numbering starts at 1 and is contiguous WITHIN this fragment only. The
    generator splices its implementation tasks between the contract task and
    the test-layer tasks and renumbers; `mb-spec-validate.sh` then checks the
    resulting order (C3/C4), so a splice mistake is caught by code rather than
    trusted to the prompt.
    """
    blocks = []
    number = 0
    if layers.contract_first and gated:
        number += 1
        blocks.append(contract_block(number, gated))
    if layers.integration_tests:
        number += 1
        blocks.append(layer_block(number, "integration", 4, all_reqs, names))
    if layers.e2e_tests:
        number += 1
        blocks.append(layer_block(number, "e2e", 4, all_reqs, names))
    return "\n".join(blocks)


def render_quality_dod(rules: dict) -> str:
    """Exactly one `## Quality DoD` section in the C5 format.

    Paths only, never the rules' text (REQ-015), and the sources sorted by path
    so the same resolve renders byte-identically (NFR-003) — that byte-identity
    is what lets implementer, reviewer and judge be given the same block.
    """
    lines = [
        "## Quality DoD",
        "",
        "Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):",
    ]
    for entry in sorted(rules["sources"], key=lambda e: e["path"]):
        lines.append("- [%s] %s" % (entry["kind"], entry["path"]))
    lines += ["", "Review rubric (from `pipeline.yaml:review_rubric`):"]
    lines += ["- %s" % bullet for bullet in rules["review_rubric"]]
    lines += [
        "",
        "Checker: `bash %s --files <touched-files-csv> --out json` — no violations"
        % rules["checker"],
        "on this item's touched files.",
        "",
    ]
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="mb-sdd-layers-render", add_help=True)
    parser.add_argument("--requirements", required=True)
    parser.add_argument("--pipeline", required=True)
    parser.add_argument("--rules-json", required=True)
    parser.add_argument("--json", action="store_true")
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2

    requirements = Path(args.requirements)
    try:
        layers = read_spec_layers(requirements, Path(args.pipeline))
    except SpecLayersError as exc:
        return fail("spec_layers_error=%s field=%s" % (exc.code, exc.field or "-"))
    except OSError as exc:
        return fail("requirements.md could not be read: %s" % exc)

    if layers.source == "legacy":
        return fail(
            "the spec declares no `layers` block (source=legacy); a generated spec must"
            " declare one, and rendering it as all-off would invent a decision nobody made"
        )

    try:
        rules = load_rules(Path(args.rules_json))
        names = scenario_test_names(requirements)
    except (ValueError, OSError) as exc:
        return fail(str(exc))

    text = requirements.read_text(encoding="utf-8")
    gated = rq.gated_definitions(text)
    all_reqs = rq.find_definitions(text) or gated

    envelope = {
        "tasks_markdown": render_tasks(layers, gated, all_reqs, names),
        "quality_dod_markdown": render_quality_dod(rules),
    }
    sys.stdout.write(json.dumps(envelope, ensure_ascii=False, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
