"""S2 review [24]/[25]/[26]: svp-sdd-core zone files stay within 400 lines.

Scope note, deliberately narrow: 400 is NOT a documented repo-wide rule. It
appears nowhere in `rules/RULES.md`, `AGENTS.md`, or `scripts/mb-rules-check.sh`,
and 25 first-party files currently exceed it (`commands/mb.md` at 1658,
`rules/RULES.md` itself at 816). The limit comes from the `svp-sdd-core`
design and from the executor brief, so this test binds ONLY the files of that
zone. Do not widen it to the repository without first codifying the rule —
a green test must not imply a policy the repo never adopted.

These three files were 572 / 856 / 832 lines while their spec was marked
complete, so the contract is locked down here rather than left to review.
"""

from __future__ import annotations

import pathlib

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
LIMIT = 400

ZONE_FILES = [
    "scripts/mb-spec-validate.sh",
    "scripts/mb_spec_validate_v2.py",
    "scripts/mb_spec_validate_graph.py",
    "scripts/mb_spec_validate_structural.py",
    "scripts/mb_spec_validate_tasks.py",
    "scripts/mb-pipeline-validate.sh",
    "scripts/mb_pipeline_validate_core.py",
    "scripts/mb_pipeline_validate_blocks.py",
    "scripts/mb_pipeline_minimal_yaml.py",
    "scripts/mb-work-state.sh",
    "scripts/mb-work-state-eval.sh",
    "scripts/mb-work-state-lib.sh",
    "scripts/mb-sdd-candidate.sh",
    "scripts/mb-sdd-review-result.sh",
    "scripts/mb-sdd-self-check.sh",
    "commands/work.md",
    "commands/sdd.md",
]


def _lines(rel: str) -> int:
    return len((REPO_ROOT / rel).read_text(encoding="utf-8").splitlines())


def test_s2_zone_files_within_line_limit() -> None:
    offenders = {rel: n for rel in ZONE_FILES if (n := _lines(rel)) > LIMIT}
    assert offenders == {}, f"files over the {LIMIT}-line limit: {offenders}"


def test_every_zone_file_exists() -> None:
    """A file renamed away must fail loudly, not silently drop its size check."""
    missing = [rel for rel in ZONE_FILES if not (REPO_ROOT / rel).is_file()]
    assert missing == [], f"zone files missing: {missing}"
