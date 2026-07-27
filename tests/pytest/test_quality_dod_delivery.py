"""Task 6 (svp-contract-test-loop) — Quality DoD delivered to three receivers.

C6. One canonical STATIC block, rendered once, delivered byte-identically to
the implementer, the reviewer and the judge. Plus a per-item dynamic piece —
the rules-checker's JSON — carried in `## Prior evidence`, deliberately OUTSIDE
the static block so its sha256 stays common to all three.

WHERE THE MECHANICAL SEAM IS, AND WHERE IT HONESTLY IS NOT
──────────────────────────────────────────────────────────
The reviewer is the only receiver with a deterministic seam: it never opens
files (`agents/mb-reviewer.md`), so `mb-review.sh --emit-payload` hands it one
self-contained payload, and that payload can be diffed byte for byte.

The implementer and the judge receive their copy through a PROMPT assembled by
the orchestrator (`commands/work.md` §5a and §5e). There is no seam to run in a
test. So what is asserted for those two is what can be asserted: that a single
renderer produces the bytes, and that work.md instructs passing that same file
to both. Pretending a prompt can be unit-tested is the failure this spec
exists to prevent; this docstring is the honest boundary instead.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
QDOD = REPO_ROOT / "scripts" / "mb-quality-dod.sh"
REVIEW = REPO_ROOT / "scripts" / "mb-review.sh"

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

CLEAN_CHECK = {"violations": [], "profile": {}, "stats": {"files_scanned": 2}}
CRITICAL_CHECK = {
    "violations": [
        {
            "rule": "solid/srp",
            "severity": "CRITICAL",
            "file": "scripts/huge.py",
            "excerpt": "900 lines",
        }
    ],
    "profile": {},
    "stats": {"files_scanned": 1},
}


def make_bank(tmp_path: Path) -> Path:
    bank = tmp_path / "repo" / ".memory-bank"
    (bank / "specs" / "demo").mkdir(parents=True, exist_ok=True)
    (bank / "tmp").mkdir(parents=True, exist_ok=True)
    return bank


def write_rules(tmp_path: Path, rules: dict | None = None) -> Path:
    path = tmp_path / "rules.json"
    path.write_text(json.dumps(RULES_JSON if rules is None else rules), encoding="utf-8")
    return path


def render_block(tmp_path: Path, rules: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(QDOD), "--rules-json", str(write_rules(tmp_path, rules))],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def has_section(payload: str, heading: str) -> bool:
    """A section heading is a WHOLE line.

    Substring matching is contaminated: the payload embeds `git diff` of the
    working tree, and this repo's own diff legitimately contains the text
    `## Quality DoD` inside added lines. In a diff those lines carry a `+`/`-`/
    space prefix, so a line-exact match separates a real section from the diff
    that merely mentions one.
    """
    return any(line == heading for line in payload.splitlines())


def section(payload: str, heading: str) -> str:
    """The named section of a payload, up to the next `## ` heading line."""
    lines = payload.splitlines()
    assert heading in lines, "payload has no %s section:\n%s" % (heading, payload)
    start = lines.index(heading)
    out = [lines[start]]
    for line in lines[start + 1 :]:
        if line.startswith("## "):
            break
        out.append(line)
    return "\n".join(out).rstrip("\n") + "\n"


def emit_payload(tmp_path: Path, *extra: str) -> subprocess.CompletedProcess:
    bank = make_bank(tmp_path)
    return subprocess.run(
        ["bash", str(REVIEW), "--emit-payload", "--mb", str(bank), *extra],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )


# ── the static block: one renderer, one set of bytes ────────────────────────


def test_three_payloads_share_one_sha256(tmp_path: Path) -> None:
    """The block the reviewer receives is byte-identical to the rendered one.

    The implementer's and judge's copies are the SAME FILE (work.md §5a/§5e
    pass the path the orchestrator rendered once), which is asserted by
    `test_work_md_delivers_the_same_file_to_implementer_and_judge`.
    """
    rendered = render_block(tmp_path)
    assert rendered.returncode == 0, rendered.stderr
    block_path = tmp_path / "quality-dod.md"
    block_path.write_text(rendered.stdout, encoding="utf-8")

    payload = emit_payload(tmp_path, "--quality-dod", str(block_path))
    assert payload.returncode == 0, payload.stderr
    delivered = section(payload.stdout, "## Quality DoD")
    assert sha(delivered) == sha(rendered.stdout.rstrip("\n") + "\n"), (
        "reviewer's copy diverged:\n--- rendered ---\n%s\n--- delivered ---\n%s"
        % (rendered.stdout, delivered)
    )


def test_block_render_is_deterministic(tmp_path: Path) -> None:
    first = render_block(tmp_path)
    second = render_block(tmp_path)
    assert first.returncode == 0 and first.stdout.strip(), first.stderr
    assert first.stdout == second.stdout


def test_one_renderer_serves_the_sdd_pipeline_too(tmp_path: Path) -> None:
    """The C8 spec generator and the C6 delivery path emit the SAME bytes.

    Asserted by rendering the same rules JSON through both entry points, not by
    grepping the source for an import: an import name proves nothing about the
    output, and the whole contract is byte-identity.
    """
    spec = tmp_path / "spec"
    spec.mkdir()
    (spec / "requirements.md").write_text(
        "---\ntopic: demo\nlayers:\n  contract_first: true\n  integration_tests: true\n"
        "  e2e_tests: true\n---\n\n# Requirements: demo\n\n## Requirements (EARS)\n\n"
        "- **REQ-001** (ubiquitous): The system shall persist work items to disk.\n\n"
        # With the test layers on, the renderer requires scenarios: their DoD
        # has to name the ids it covers, and naming nothing is not naming.
        "## Scenarios\n\n<!-- mb-scenario:1 -->\n### Scenario: persist round trip\n"
        "**Covers:** REQ-001\n\n- GIVEN a work item\n- WHEN it is persisted\n"
        "- THEN it round-trips\n<!-- /mb-scenario:1 -->\n",
        encoding="utf-8",
    )
    pipeline = tmp_path / "pipeline.yaml"
    pipeline.write_text(
        'version: "1"\nsdd:\n  layers: {contract_first: true, integration_tests: true,'
        " e2e_tests: true}\n",
        encoding="utf-8",
    )
    rules_path = write_rules(tmp_path)
    from_c8 = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts" / "mb-sdd-layers-render.py"),
            "--requirements",
            str(spec / "requirements.md"),
            "--pipeline",
            str(pipeline),
            "--rules-json",
            str(rules_path),
            "--json",
        ],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert from_c8.returncode == 0, from_c8.stderr
    from_c6 = render_block(tmp_path)
    assert from_c6.returncode == 0, from_c6.stderr
    assert json.loads(from_c8.stdout)["quality_dod_markdown"] == from_c6.stdout


# ── the rubric actually reaches the reviewer (R2-012) ───────────────────────


def test_reviewer_payload_carries_rubric_bullets(tmp_path: Path) -> None:
    """`mb-review.sh` never read `review_rubric`; the block is what carries it."""
    rendered = render_block(tmp_path)
    block_path = tmp_path / "quality-dod.md"
    block_path.write_text(rendered.stdout, encoding="utf-8")
    payload = emit_payload(tmp_path, "--quality-dod", str(block_path))
    for bullet in RULES_JSON["review_rubric"]:
        assert bullet in payload.stdout, "rubric bullet missing: %s" % bullet


def test_quality_dod_absent_when_not_requested(tmp_path: Path) -> None:
    """Opt-in: an existing caller's payload is unchanged (no new section)."""
    payload = emit_payload(tmp_path)
    assert payload.returncode == 0, payload.stderr
    assert not has_section(payload.stdout, "## Quality DoD")


# ── the dynamic half: checker evidence, outside the static block ────────────


def test_rules_check_json_in_prior_evidence(tmp_path: Path) -> None:
    rendered = render_block(tmp_path)
    block_path = tmp_path / "quality-dod.md"
    block_path.write_text(rendered.stdout, encoding="utf-8")
    check_path = tmp_path / "rules-check.json"
    check_path.write_text(json.dumps(CLEAN_CHECK), encoding="utf-8")

    payload = emit_payload(
        tmp_path, "--quality-dod", str(block_path), "--rules-check-json", str(check_path)
    )
    assert payload.returncode == 0, payload.stderr
    prior = section(payload.stdout, "## Prior evidence (from mb-test-runner)")
    assert "rules_check" in prior, prior
    assert "files_scanned" in prior, prior


def test_rules_check_evidence_leaves_the_static_block_byte_identical(tmp_path: Path) -> None:
    """Per-item data must NOT leak into the block, or the three sha256 diverge."""
    rendered = render_block(tmp_path)
    block_path = tmp_path / "quality-dod.md"
    block_path.write_text(rendered.stdout, encoding="utf-8")
    check_path = tmp_path / "rules-check.json"
    check_path.write_text(json.dumps(CLEAN_CHECK), encoding="utf-8")

    without = emit_payload(tmp_path, "--quality-dod", str(block_path))
    with_check = emit_payload(
        tmp_path, "--quality-dod", str(block_path), "--rules-check-json", str(check_path)
    )
    assert sha(section(without.stdout, "## Quality DoD")) == sha(
        section(with_check.stdout, "## Quality DoD")
    )


def test_rules_check_nonzero_blocks_dispatch(tmp_path: Path) -> None:
    """A CRITICAL rules violation refuses the payload — no review is dispatched.

    Deliberately keyed on the JSON's severity rather than the checker's exit
    code: `mb-rules-check.sh` only exits non-zero when the active profile says
    `strictness: block`, and this project's profile says `warn`, so the exit
    code is 0 with CRITICAL violations present. A gate keyed on it could never
    fire here.
    """
    rendered = render_block(tmp_path)
    block_path = tmp_path / "quality-dod.md"
    block_path.write_text(rendered.stdout, encoding="utf-8")
    check_path = tmp_path / "rules-check.json"
    check_path.write_text(json.dumps(CRITICAL_CHECK), encoding="utf-8")

    payload = emit_payload(
        tmp_path, "--quality-dod", str(block_path), "--rules-check-json", str(check_path)
    )
    assert payload.returncode == 1, payload.stdout
    assert payload.stdout == "", "a blocked dispatch must not emit a payload"
    assert "CRITICAL" in payload.stderr or "solid/srp" in payload.stderr, payload.stderr


def test_malformed_rules_check_json_blocks_dispatch(tmp_path: Path) -> None:
    """Unreadable evidence is not evidence — it must not pass silently."""
    rendered = render_block(tmp_path)
    block_path = tmp_path / "quality-dod.md"
    block_path.write_text(rendered.stdout, encoding="utf-8")
    check_path = tmp_path / "rules-check.json"
    check_path.write_text("not json", encoding="utf-8")
    payload = emit_payload(
        tmp_path, "--quality-dod", str(block_path), "--rules-check-json", str(check_path)
    )
    assert payload.returncode == 1, payload.stdout


# ── loud refusals (REQ-017) ─────────────────────────────────────────────────


def test_missing_rule_source_fails_dispatch(tmp_path: Path) -> None:
    """A declared rule source that does not exist is a loud stop, not a fallback."""
    spec = tmp_path / "spec"
    spec.mkdir()
    (spec / "design.md").write_text(
        "# Design\n\n## Quality DoD\n\n- [project] does/not/exist.md\n", encoding="utf-8"
    )
    proc = subprocess.run(
        ["bash", str(QDOD), "--spec", str(spec)],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    assert proc.returncode == 1, proc.stdout
    assert proc.stdout == "", "a refusal must not print a block"
    assert "does/not/exist.md" in proc.stderr, proc.stderr
    # The resolver's verdict must be PROPAGATED, not re-derived downstream: if
    # it fell through, the renderer would run and stamp its own prefix on the
    # failure. Reaching the renderer at all means the refusal was ignored.
    assert "[quality-dod]" not in proc.stderr, proc.stderr


def test_missing_quality_dod_file_is_a_usage_error(tmp_path: Path) -> None:
    missing = tmp_path / "nope.md"
    payload = emit_payload(tmp_path, "--quality-dod", str(missing))
    assert payload.returncode == 2, payload.stdout
    # An UNKNOWN flag also exits 2, which is how this passed before the flag
    # existed. Naming the path is what proves the flag was understood.
    assert str(missing) in payload.stderr, payload.stderr
    # And the refusal must land BEFORE assembly: a late check exits 2 with the
    # earlier sections already streamed, leaving the caller half a payload.
    assert payload.stdout == "", payload.stdout


# ── the configs are not mutated (C6 step 5) ─────────────────────────────────


def test_pipeline_files_not_mutated(tmp_path: Path) -> None:
    """Rendering must not become a second source of truth about the rules."""
    watched = [
        REPO_ROOT / "references" / "pipeline.default.yaml",
        REPO_ROOT / ".memory-bank" / "pipeline.yaml",
    ]
    before = {p: p.read_bytes() for p in watched if p.is_file()}
    assert before, "no pipeline config found to watch"
    rendered = render_block(tmp_path)
    # Asserted first: nothing that never ran can mutate anything, and this test
    # passed on exactly that before the renderer existed.
    assert rendered.returncode == 0, rendered.stderr
    block_path = tmp_path / "quality-dod.md"
    block_path.write_text(rendered.stdout, encoding="utf-8")
    payload = emit_payload(tmp_path, "--quality-dod", str(block_path))
    assert payload.returncode == 0, payload.stderr
    for path, blob in before.items():
        assert path.read_bytes() == blob, "%s was mutated" % path


# ── overlap is not a DRY defect (REQ-010) ───────────────────────────────────


def test_overlap_not_reported_as_dry_violation() -> None:
    """Reviewer and judge are told that contract/integration overlap is fine.

    Without this, the strongest specs look worst: a requirement covered by a
    contract checker AND an integration test reads as duplication to a
    reviewer whose rubric rewards DRY.
    """
    for agent in ("mb-reviewer.md", "mb-judge.md"):
        text = (REPO_ROOT / "agents" / agent).read_text(encoding="utf-8")
        lowered = text.lower()
        assert "overlap" in lowered, "%s never mentions coverage overlap" % agent
        assert "dry" in lowered, "%s does not tie the overlap rule to DRY" % agent


# ── production wiring: the two prompt receivers ─────────────────────────────


def _work_section(text: str, heading: str) -> str:
    """One `### 5x.` step of commands/work.md, up to the next step heading."""
    assert heading in text, "commands/work.md has no %s" % heading
    body = text.split(heading, 1)[1]
    marker = "\n   ### "
    return body.split(marker, 1)[0] if marker in body else body


def test_work_md_delivers_the_same_file_to_implementer_and_judge() -> None:
    """Each receiver is asserted IN ITS OWN dispatch step, never by a count.

    The first version asserted `work.count("$QUALITY_DOD") >= 3` against four
    occurrences. Deleting the one line that hands the block to the judge left
    three, and the test — whose name promises it watches judge delivery —
    stayed green. A threshold over a whole document cannot tell which receiver
    lost its copy, so each step is now checked where that step lives.
    """
    work = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")

    render = _work_section(work, "### 5a0b.")
    assert "mb-quality-dod.sh" in render, "the block is never rendered"
    assert "$QUALITY_DOD" in render

    reviewer = _work_section(work, "### 5d.")
    assert '--quality-dod "$QUALITY_DOD"' in reviewer, "the reviewer's copy is not passed"
    assert "--rules-check-json" in reviewer

    judge = _work_section(work, "### 5e.")
    assert "$QUALITY_DOD" in judge, "the judge step never receives the block:\n%s" % judge

    implementer = _work_section(work, "### 5a.")
    assert "$QUALITY_DOD" in implementer or "$QUALITY_DOD" in render, (
        "the implementer step never receives the block"
    )
