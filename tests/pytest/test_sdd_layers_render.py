"""Task 4 (svp-contract-test-loop) — the C8 layer/Quality-DoD renderer.

    python3 scripts/mb-sdd-layers-render.py --requirements P --pipeline P \
                                            --rules-json P --json

THE RENDERER IS INVOKED AS A SUBPROCESS, NEVER IMPORTED
───────────────────────────────────────────────────────
Not a style choice. A module-level `import` of a script that does not exist yet
aborts pytest at COLLECTION: exit 2, and not one `FAILED …::test_x` line in the
output. This task's declared red anchor IS such a line, so an import here would
declare an anchor that can never appear — the same defect this whole spec was
written to kill. Running the CLI also happens to be the real contract: the
renderer's interface is stdout, not a Python API.

WHAT THE RENDERER IS AND IS NOT RESPONSIBLE FOR
───────────────────────────────────────────────
It renders the CONTENT of the layer tasks (the five contract steps, DoD lines
carrying full test_ids, the canonical relative order) and exactly one
`## Quality DoD` section. It does NOT own where the generator splices them or
the final task numbering — that is checked afterwards by `mb-spec-validate.sh`
(C3/C4) and the C8 battery. Tests here assert what the renderer decides.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
RENDER = REPO_ROOT / "scripts" / "mb-sdd-layers-render.py"

ALL_ON = """layers:
  contract_first: true
  integration_tests: true
  e2e_tests: true"""

REQUIREMENTS = """# Requirements: demo

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall persist work items to disk.
- **REQ-002** (event-driven): When a work item is read, the system shall return it unchanged.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: persist round trip
**Covers:** REQ-001

- GIVEN a work item
- WHEN it is persisted
- THEN it round-trips
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: unreadable store fails loudly
**Covers:** REQ-002

- GIVEN an unreadable store
- WHEN a read is attempted
- THEN it fails loudly
<!-- /mb-scenario:2 -->
"""

PIPELINE = """version: "1"
sdd:
  layers: {contract_first: true, integration_tests: true, e2e_tests: true}
"""

RULES_JSON = {
    "sources": [
        {"kind": "project", "path": "AGENTS.md"},
        {"kind": "skill", "path": "rules/RULES.md"},
    ],
    "review_rubric": [
        "logic: Every EARS requirement has at least one assertion in tests",
        "tests: Integration tests > unit tests (Testing Trophy)",
    ],
    "fallback_used": False,
    "checker": "scripts/mb-rules-check.sh",
}


def build(tmp_path: Path, layers: str = ALL_ON, rules: dict | None = None) -> dict:
    """Write the three inputs; return the argv the renderer is called with."""
    spec = tmp_path / "spec"
    spec.mkdir(exist_ok=True)
    front = "---\ntopic: demo\n%s\n---\n\n" % layers if layers else ""
    (spec / "requirements.md").write_text(front + REQUIREMENTS, encoding="utf-8")
    pipeline = tmp_path / "pipeline.yaml"
    pipeline.write_text(PIPELINE, encoding="utf-8")
    rules_path = tmp_path / "rules.json"
    rules_path.write_text(json.dumps(RULES_JSON if rules is None else rules), encoding="utf-8")
    return {
        "argv": [
            sys.executable,
            str(RENDER),
            "--requirements",
            str(spec / "requirements.md"),
            "--pipeline",
            str(pipeline),
            "--rules-json",
            str(rules_path),
            "--json",
        ],
        "spec": spec,
    }


def run(built: dict) -> subprocess.CompletedProcess:
    return subprocess.run(built["argv"], capture_output=True, text=True, cwd=str(REPO_ROOT))


def render(tmp_path: Path, layers: str = ALL_ON, rules: dict | None = None) -> dict:
    """Render and return the parsed envelope; fails loudly on a non-zero exit."""
    proc = run(build(tmp_path, layers, rules))
    assert proc.returncode == 0, "renderer failed (%d): %s" % (proc.returncode, proc.stderr)
    return json.loads(proc.stdout)


def tasks_of(markdown: str) -> list[str]:
    """Heading titles in document order — the renderer's canonical ordering."""
    return [
        line.split(":", 1)[1].strip()
        for line in markdown.splitlines()
        if line.startswith("## Task ")
    ]


# ── ordering (C4 matrix) ────────────────────────────────────────────────────


def test_task_order_contract_impl_integration_e2e(tmp_path: Path) -> None:
    payload = render(tmp_path)
    md = payload["tasks_markdown"]
    contract = md.index("**Layer:** contract")
    integration = md.index("**Layer:** integration")
    e2e = md.index("**Layer:** e2e")
    assert contract < integration < e2e, tasks_of(md)


def test_e2e_without_integration_order(tmp_path: Path) -> None:
    """R3-003: with integration off there is no object to anchor e2e behind."""
    payload = render(
        tmp_path,
        """layers:
  contract_first: true
  integration_tests: false
  integration_tests_reason: "no component seam in this slice"
  e2e_tests: true""",
    )
    md = payload["tasks_markdown"]
    assert "**Layer:** integration" not in md
    assert md.index("**Layer:** contract") < md.index("**Layer:** e2e")


def test_disabled_layer_renders_no_task(tmp_path: Path) -> None:
    payload = render(
        tmp_path,
        """layers:
  contract_first: false
  contract_first_reason: "checkers land in the parent slice"
  integration_tests: true
  e2e_tests: false
  e2e_tests_reason: "library without an external surface\"""",
    )
    md = payload["tasks_markdown"]
    assert "**Layer:** contract" not in md
    assert "**Layer:** e2e" not in md
    assert "**Layer:** integration" in md


# ── the contract task (C3) ──────────────────────────────────────────────────


def test_contract_task_has_five_steps_no_business_code(tmp_path: Path) -> None:
    md = render(tmp_path)["tasks_markdown"]
    block = md.split("**Layer:** contract", 1)[1].split("<!-- /mb-task:", 1)[0]
    steps = [
        line
        for line in block.splitlines()
        if line.strip().startswith(("1.", "2.", "3.", "4.", "5."))
    ]
    assert len(steps) == 5, block
    # Step 5 is the one that cannot be self-reported: the checkers must be
    # observed red against a product that does not implement them yet.
    assert "red" in steps[4].lower()
    dod = block.split("**DoD:**", 1)[1]
    assert "green" in dod.lower() and "red" in dod.lower(), dod


def test_contract_task_declares_no_product_scope(tmp_path: Path) -> None:
    """The contract task carries checkers and their tests — never business code."""
    md = render(tmp_path)["tasks_markdown"]
    block = md.split("**Layer:** contract", 1)[1].split("<!-- /mb-task:", 1)[0]
    assert "no business code" in block.lower()


# ── test ids (C4 mapping rule) ──────────────────────────────────────────────


def test_layer_tasks_list_full_test_ids(tmp_path: Path) -> None:
    """Full ids from mb-scenario-extract.py, `-` → `_`, never abbreviated."""
    md = render(tmp_path)["tasks_markdown"]
    for expected in (
        "test_REQ_001__persist_round_trip",
        "test_REQ_002__unreadable_store_fails_loudly",
    ):
        assert md.count(expected) >= 2, "%s missing from both layer tasks:\n%s" % (expected, md)
    assert "…" not in md and "..." not in md


def test_scenario_ids_come_from_the_extractor(tmp_path: Path) -> None:
    """The renderer must not invent a second id scheme (REQ-009)."""
    built = build(tmp_path)
    payload = json.loads(run(built).stdout)
    extractor = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts" / "mb-scenario-extract.py"),
            str(built["spec"] / "requirements.md"),
        ],
        capture_output=True,
        text=True,
    )
    ids = [json.loads(line)["test_id"] for line in extractor.stdout.splitlines() if line.strip()]
    assert ids, extractor.stderr
    for test_id in ids:
        assert "test_" + test_id.replace("-", "_") in payload["tasks_markdown"]


# ── Quality DoD (C5) ────────────────────────────────────────────────────────


def test_all_layers_false_empty_tasks_keeps_quality_dod(tmp_path: Path) -> None:
    """Speed switches off tasks, never the rules criterion (R2-010 / REQ-015)."""
    payload = render(
        tmp_path,
        """layers:
  contract_first: false
  contract_first_reason: "checkers land in the parent slice"
  integration_tests: false
  integration_tests_reason: "no component seam in this slice"
  e2e_tests: false
  e2e_tests_reason: "library without an external surface\"""",
    )
    assert payload["tasks_markdown"] == ""
    assert payload["quality_dod_markdown"].count("## Quality DoD") == 1


def test_quality_dod_has_exactly_one_section(tmp_path: Path) -> None:
    payload = render(tmp_path)
    assert payload["quality_dod_markdown"].count("## Quality DoD") == 1


def test_quality_dod_references_paths_not_text(tmp_path: Path) -> None:
    block = render(tmp_path)["quality_dod_markdown"]
    assert "- [project] AGENTS.md" in block
    assert "- [skill] rules/RULES.md" in block
    for bullet in RULES_JSON["review_rubric"]:
        assert bullet in block
    assert "scripts/mb-rules-check.sh" in block
    # The rules' TEXT is never copied — only their paths (REQ-015).
    assert "Feature-Sliced Design" not in block
    assert "Testing Trophy" in block  # …but a rubric BULLET quoting it is fine


def test_quality_dod_sources_sorted_by_path(tmp_path: Path) -> None:
    """Deterministic ordering (NFR-003) — the same resolve renders identically."""
    rules = dict(RULES_JSON)
    rules["sources"] = [
        {"kind": "skill", "path": "rules/RULES.md"},
        {"kind": "project", "path": "AGENTS.md"},
    ]
    block = render(tmp_path, rules=rules)["quality_dod_markdown"]
    assert block.index("AGENTS.md") < block.index("rules/RULES.md")


# ── envelope, purity, refusals ──────────────────────────────────────────────


def test_renderer_writes_no_files(tmp_path: Path) -> None:
    built = build(tmp_path, ALL_ON)
    before = {p: p.stat().st_mtime_ns for p in sorted(tmp_path.rglob("*")) if p.is_file()}
    before_bytes = {p: p.read_bytes() for p in before}
    assert run(built).returncode == 0
    after = {p: p.stat().st_mtime_ns for p in sorted(tmp_path.rglob("*")) if p.is_file()}
    assert set(after) == set(before), "the tree gained or lost files"
    assert all(p.read_bytes() == before_bytes[p] for p in after), "a file was rewritten"


def test_envelope_has_exactly_two_keys(tmp_path: Path) -> None:
    payload = render(tmp_path)
    assert set(payload) == {"tasks_markdown", "quality_dod_markdown"}
    assert all(isinstance(v, str) for v in payload.values())


def test_render_is_deterministic(tmp_path: Path) -> None:
    built = build(tmp_path)
    first, second = run(built).stdout, run(built).stdout
    # Non-emptiness is asserted FIRST: "" == "" is the shape this test takes
    # when the renderer produces nothing at all, and it went green on exactly
    # that before the renderer existed.
    assert first.strip(), "renderer produced no output"
    assert first == second


@pytest.mark.parametrize(
    "mutate",
    [
        pytest.param(lambda r: r.pop("sources"), id="missing_sources"),
        pytest.param(lambda r: r.pop("checker"), id="missing_checker"),
        pytest.param(lambda r: r.pop("review_rubric"), id="missing_rubric"),
        pytest.param(lambda r: r.update(surprise=1), id="unknown_key"),
        pytest.param(lambda r: r.update(sources="AGENTS.md"), id="sources_not_a_list"),
    ],
)
def test_broken_rules_json_exits_1(tmp_path: Path, mutate) -> None:
    rules = json.loads(json.dumps(RULES_JSON))
    mutate(rules)
    proc = run(build(tmp_path, rules=rules))
    assert proc.returncode == 1, proc.stdout
    assert proc.stdout == "", "a refusal must not print a half-rendered envelope"
    # An uncaught KeyError also exits 1 with an empty stdout. The diagnostic
    # prefix is what distinguishes a refusal from a crash.
    assert "[sdd-layers-render]" in proc.stderr, proc.stderr


def test_legacy_spec_exits_1(tmp_path: Path) -> None:
    """A spec with no `layers` block declares no layers to render (R3-001)."""
    proc = run(build(tmp_path, layers=""))
    assert proc.returncode == 1
    assert "legacy" in proc.stderr


def test_layer_false_without_reason_exits_1(tmp_path: Path) -> None:
    proc = run(
        build(
            tmp_path,
            """layers:
  contract_first: true
  integration_tests: false
  e2e_tests: true""",
        )
    )
    assert proc.returncode == 1
    assert "missing_reason" in proc.stderr


def test_usage_error_exits_2(tmp_path: Path) -> None:
    proc = subprocess.run(
        [sys.executable, str(RENDER), "--requirements", "only-this"],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert proc.returncode == 2
    # A MISSING script also makes python3 exit 2 ("can't open file"), so the
    # exit code alone let this test pass before the renderer existed. The
    # diagnostic is what distinguishes "the tool refused" from "there is no tool".
    assert "--pipeline" in proc.stderr or "--rules-json" in proc.stderr, proc.stderr


# ── the rendered artifact through its REAL consumers ────────────────────────
#
# The tests above read the markdown as a string, which is exactly how two
# defects survived a fully green suite: `**Blocked-by:** previous` and a
# `**Scope:** tests/` with a trailing slash both parse fine as prose and are
# REJECTED by `mb_work_items.py`, taking the whole tasks.md to exit 2. A
# renderer is only correct if the thing that consumes its output accepts it.


def test_rendered_tasks_parse_with_the_real_work_items_parser(tmp_path: Path) -> None:
    md = render(tmp_path)["tasks_markdown"]
    tasks_file = tmp_path / "tasks.md"
    tasks_file.write_text("# Tasks: demo\n\n" + md, encoding="utf-8")
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    import mb_work_items

    items = mb_work_items.parse_work_items(tasks_file)
    assert len(items) == 3
    assert [i.item_no for i in items] == [1, 2, 3]


DASH = "—"
IMPL_EVAL = (
    "**Eval:** `pytest tests/pytest/test_demo.py` " + DASH + " red: not implemented; "
    "exit: 1; output~: `FAILED tests/pytest/test_demo\\.py::test_persist`"
)
IMPL_TASK = (
    """<!-- mb-task:9 -->
## Task 9: persist work items

**Stage:** 2
**Covers:** REQ-001, REQ-002
**Role:** backend
**Scope:** scripts/**
**Budget:** 100000
%s

**What to do:**
- persist.

**Testing (TDD):**
- round trip.

**DoD:**
- [ ] persists.
<!-- /mb-task:9 -->

"""
    % IMPL_EVAL
)


def test_rendered_triple_passes_spec_validate(tmp_path: Path) -> None:
    """Closes the loop: what Task 4 renders, Task 3's gates must accept.

    The fragment alone is NOT a spec — it carries no implementation task, and
    Eval coverage is checked per gated REQ rather than per task, so a spec made
    only of layer tasks is legitimately refused. What is asserted here is the
    realistic generator output: the rendered layer tasks spliced around one
    implementation task that carries the Eval.
    """
    spec = tmp_path / "specs" / "demo"
    spec.mkdir(parents=True)
    payload = render(tmp_path)
    contract, rest = payload["tasks_markdown"].split("<!-- mb-task:2 -->", 1)
    (spec / "requirements.md").write_text(
        "---\ntopic: demo\n%s\n---\n\n%s" % (ALL_ON, REQUIREMENTS), encoding="utf-8"
    )
    (spec / "design.md").write_text(
        "# Design: demo\n\n## Contract\n\n**Seams:**\n- the persistence boundary\n\n"
        + payload["quality_dod_markdown"]
        + "\n## Eval declarations\n\n- **T9** "
        + DASH
        + " persist work items:\n  "
        + IMPL_EVAL
        + "\n",
        encoding="utf-8",
    )
    (spec / "tasks.md").write_text(
        "# Tasks: demo\n\n" + contract + IMPL_TASK + "<!-- mb-task:2 -->" + rest,
        encoding="utf-8",
    )
    proc = subprocess.run(
        ["bash", str(REPO_ROOT / "scripts" / "mb-spec-validate.sh"), str(spec)],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr


def test_templates_md_and_renderer_do_not_drift(tmp_path: Path) -> None:
    """The documented skeleton and the rendered one are the same skeleton.

    `references/templates.md` describes what the renderer produces. Two places
    stating one format is the standing invitation to drift, so the FIXED lines
    of the Quality DoD — everything that is not per-spec data — must appear in
    both.
    """
    rendered = render(tmp_path)["quality_dod_markdown"]
    templates = (REPO_ROOT / "references" / "templates.md").read_text(encoding="utf-8")
    fixed = [
        "## Quality DoD",
        "Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):",
        "Review rubric (from `pipeline.yaml:review_rubric`):",
        "on this item's touched files.",
    ]
    for line in fixed:
        assert line in rendered, "renderer dropped: %s" % line
        assert line in templates, "templates.md never documented: %s" % line
    assert "scripts/mb-sdd-layers-render.py" in templates


def test_sdd_command_wires_the_renderer(tmp_path: Path) -> None:
    """A renderer nothing calls is a renderer that never runs (production wiring)."""
    sdd = (REPO_ROOT / "commands" / "sdd.md").read_text(encoding="utf-8")
    assert "scripts/mb-sdd-layers-render.py" in sdd
    assert "--rules-json" in sdd
    assert "quality_dod_markdown" in sdd and "tasks_markdown" in sdd


def test_contract_task_absent_without_a_gated_requirement(tmp_path: Path) -> None:
    """C3: contract_first ON but nothing gated → no contract task (M03).

    Mirrors the validator's `contract_layer=not_applicable`: with no SHALL/MUST
    criterion there is nothing for a checker to observe, so demanding the task
    would demand checkers for requirements that do not exist.
    """
    spec = tmp_path / "spec"
    spec.mkdir()
    # Scenarios are present because the test layers ARE on here: a layer task
    # whose DoD would name no scenario is refused outright, so a fixture that
    # leaves both out would be exercising that refusal instead of this rule.
    (spec / "requirements.md").write_text(
        "---\ntopic: demo\n%s\n---\n\n# Requirements: demo\n\n"
        "## Requirements (EARS)\n\nNo normative criteria yet.\n\n"
        "## Scenarios\n\n<!-- mb-scenario:1 -->\n### Scenario: intent is recorded\n"
        "**Covers:** REQ-100\n\n- GIVEN a draft\n- WHEN it is read\n- THEN intent is recorded\n"
        "<!-- /mb-scenario:1 -->\n" % ALL_ON,
        encoding="utf-8",
    )
    (tmp_path / "pipeline.yaml").write_text(PIPELINE, encoding="utf-8")
    (tmp_path / "rules.json").write_text(json.dumps(RULES_JSON), encoding="utf-8")
    proc = subprocess.run(
        [
            sys.executable,
            str(RENDER),
            "--requirements",
            str(spec / "requirements.md"),
            "--pipeline",
            str(tmp_path / "pipeline.yaml"),
            "--rules-json",
            str(tmp_path / "rules.json"),
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert proc.returncode == 0, proc.stderr
    md = json.loads(proc.stdout)["tasks_markdown"]
    assert "**Layer:** contract" not in md
    assert "**Layer:** integration" in md


def test_should_only_requirement_is_not_gated(tmp_path: Path) -> None:
    """D-06: SHOULD/MAY do not gate, so they are not what the checkers cover."""
    spec = tmp_path / "spec"
    spec.mkdir()
    (spec / "requirements.md").write_text(
        "---\ntopic: demo\n%s\n---\n\n# Requirements: demo\n\n"
        "## Requirements (EARS)\n\n"
        "- **REQ-001** (ubiquitous): The system shall persist work items to disk.\n"
        "- **REQ-009** (ubiquitous): The system should prefer the cached value.\n\n"
        "## Scenarios\n\n<!-- mb-scenario:1 -->\n### Scenario: persist round trip\n"
        "**Covers:** REQ-001\n\n- GIVEN a work item\n- WHEN it is persisted\n"
        "- THEN it round-trips\n<!-- /mb-scenario:1 -->\n" % ALL_ON,
        encoding="utf-8",
    )
    (tmp_path / "pipeline.yaml").write_text(PIPELINE, encoding="utf-8")
    (tmp_path / "rules.json").write_text(json.dumps(RULES_JSON), encoding="utf-8")
    proc = subprocess.run(
        [
            sys.executable,
            str(RENDER),
            "--requirements",
            str(spec / "requirements.md"),
            "--pipeline",
            str(tmp_path / "pipeline.yaml"),
            "--rules-json",
            str(tmp_path / "rules.json"),
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert proc.returncode == 0, proc.stderr
    md = json.loads(proc.stdout)["tasks_markdown"]
    contract = md.split("**Layer:** contract", 1)[1].split("<!-- /mb-task:", 1)[0]
    covers = [ln for ln in contract.splitlines() if ln.startswith("**Covers:**")][0]
    assert "REQ-001" in covers
    assert "REQ-009" not in covers, covers


# ── the documented Step 3a must be RUNNABLE, not merely plausible ──────────


def _step_3a_shell(sdd_text: str) -> str:
    """The bash block commands/sdd.md tells the generator to run in Step 3a."""
    step = sdd_text.split("### Step 3a", 1)[1].split("### Step 4", 1)[0]
    return step.split("```bash", 1)[1].split("```", 1)[0]


def test_sdd_step_3a_commands_run_on_a_fresh_triple(tmp_path: Path) -> None:
    """Run the documented commands against a spec that has just been generated.

    The order in Step 3a is only real if it works on the artifact it describes.
    It did not: the resolver was invoked in VALIDATION mode (`--spec`), which
    requires a `## Quality DoD` section in design.md — the section created by
    the very next line of the same step. Every fresh spec hit
    `quality_dod_malformed=section_absent`, so the documented pipeline could
    not be followed by anyone. Asserting the doc mentions a script would not
    have noticed; running it does.
    """
    repo = tmp_path / "repo"
    bank = repo / ".memory-bank"
    staging = bank / "tmp" / "sdd" / "fresh"
    staging.mkdir(parents=True)
    (repo / "AGENTS.md").write_text("# Project rules\n", encoding="utf-8")
    (staging / "requirements.md").write_text(
        "---\ntopic: fresh\n%s\n---\n\n%s" % (ALL_ON, REQUIREMENTS), encoding="utf-8"
    )
    # A freshly generated design.md — Step 3 wrote it, and it carries no
    # `## Quality DoD` yet, because Step 3a is what produces that section.
    (staging / "design.md").write_text(
        "# Design: fresh\n\n## Contract\n\n**Seams:**\n- the write boundary\n", encoding="utf-8"
    )
    (tmp_path / "pipeline.yaml").write_text(PIPELINE, encoding="utf-8")

    script = (
        _step_3a_shell((REPO_ROOT / "commands" / "sdd.md").read_text(encoding="utf-8"))
        .replace("<bank>/tmp/sdd/<topic>", str(staging))
        .replace("<bank>", str(bank))
        .replace("<pipeline.yaml>", str(tmp_path / "pipeline.yaml"))
    )
    proc = subprocess.run(
        ["bash", "-e", "-c", script], capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    assert proc.returncode == 0, "Step 3a is not runnable:\n%s\n%s" % (script, proc.stderr)
    payload = json.loads(proc.stdout)
    assert set(payload) == {"tasks_markdown", "quality_dod_markdown"}
    assert payload["quality_dod_markdown"].count("## Quality DoD") == 1


def test_layers_on_without_scenarios_is_refused(tmp_path: Path) -> None:
    """A layer task whose DoD cannot name what it covers is not a task.

    With the layers on and no `<!-- mb-scenario:N -->` blocks, the renderer
    emitted `Covers scenario test ids: ; green (were red)` — a DoD line with an
    empty list, which reads as satisfied by construction. REQ-009 requires the
    ids be NAMED; an empty naming is the decorative shape this slice exists to
    refuse, so the renderer stops instead.
    """
    spec = tmp_path / "spec"
    spec.mkdir()
    (spec / "requirements.md").write_text(
        "---\ntopic: demo\n%s\n---\n\n# Requirements: demo\n\n## Requirements (EARS)\n\n"
        "- **REQ-001** (ubiquitous): The system shall persist data.\n" % ALL_ON,
        encoding="utf-8",
    )
    (tmp_path / "pipeline.yaml").write_text(PIPELINE, encoding="utf-8")
    (tmp_path / "rules.json").write_text(json.dumps(RULES_JSON), encoding="utf-8")
    proc = subprocess.run(
        [
            sys.executable,
            str(RENDER),
            "--requirements",
            str(spec / "requirements.md"),
            "--pipeline",
            str(tmp_path / "pipeline.yaml"),
            "--rules-json",
            str(tmp_path / "rules.json"),
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert proc.returncode == 1, proc.stdout
    assert proc.stdout == "", "a refusal must not print a half-rendered envelope"
    assert "scenario" in proc.stderr.lower(), proc.stderr


def test_layers_off_without_scenarios_still_renders(tmp_path: Path) -> None:
    """The refusal is about layer tasks, not about specs that declare none."""
    spec = tmp_path / "spec"
    spec.mkdir()
    (spec / "requirements.md").write_text(
        "---\ntopic: demo\nlayers:\n  contract_first: false\n"
        '  contract_first_reason: "parent slice"\n  integration_tests: false\n'
        '  integration_tests_reason: "n/a"\n  e2e_tests: false\n'
        '  e2e_tests_reason: "n/a"\n---\n\n# Requirements: demo\n\n'
        "## Requirements (EARS)\n\n- **REQ-001** (ubiquitous): The system shall persist data.\n",
        encoding="utf-8",
    )
    (tmp_path / "pipeline.yaml").write_text(PIPELINE, encoding="utf-8")
    (tmp_path / "rules.json").write_text(json.dumps(RULES_JSON), encoding="utf-8")
    proc = subprocess.run(
        [
            sys.executable,
            str(RENDER),
            "--requirements",
            str(spec / "requirements.md"),
            "--pipeline",
            str(tmp_path / "pipeline.yaml"),
            "--rules-json",
            str(tmp_path / "rules.json"),
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert proc.returncode == 0, proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["tasks_markdown"] == ""
    assert payload["quality_dod_markdown"].count("## Quality DoD") == 1
