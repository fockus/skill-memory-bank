"""svp-sdd-core round-2 review — pipeline.yaml validator parity + typing holes.

  [18] the no-PyYAML stdlib fallback never loaded workflows/review/judge/
       review_ensemble/done/dispatch, so closed-enum violations that PyYAML
       rejects sailed through in stdlib-only mode.
  [19] an inline `spec_review` was accepted anywhere in the file — moving it out
       of `sdd:` to the top level validated fine while the runtime, which reads
       `sdd.spec_review`, silently found nothing and left review disabled.
  [20] an enabled `spec_review` accepted non-string identity
       (`agent: false, model: 123`) although C5 requires non-empty strings.

The fallback is exercised the way the code selects it: `mb_pipeline_validate_core`
uses `minimal_pipeline_load` whenever `import yaml` fails, so these tests call
that loader directly and run the validator with PyYAML hidden.
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
VALIDATE = SCRIPTS / "mb-pipeline-validate.sh"

sys.path.insert(0, str(SCRIPTS))

# The shipped default is the only baseline known to validate clean; hand-rolled
# minimal configs trip unrelated required-block errors and make every assertion
# below unattributable.
BASE = (REPO_ROOT / "references" / "pipeline.default.yaml").read_text(encoding="utf-8")


_SR_DEFAULT = (
    "  spec_review: {enabled: false, agent: mb-reviewer, model: inherit, thinking: medium}"
)


def with_spec_review(inline: str) -> str:
    """Replace the default's existing sdd.spec_review line.

    The shipped default ALREADY declares `sdd:`, so appending another one is a
    duplicate-key error that masks whatever the test meant to assert.
    """
    assert _SR_DEFAULT in BASE, "default pipeline no longer has the expected spec_review line"
    return BASE.replace(_SR_DEFAULT, "  spec_review: " + inline)


def without_spec_review() -> str:
    return BASE.replace(_SR_DEFAULT + "\n", "")


def _run_validator(tmp_path: pathlib.Path, text: str, *, hide_yaml: bool):
    """Run the real validator; optionally with PyYAML made unimportable."""
    cfg = tmp_path / "pipeline.yaml"
    cfg.write_text(text, encoding="utf-8")
    # Inherit the real environment: a trimmed PATH silently selects a python3
    # WITHOUT PyYAML, so both branches would run the fallback and the
    # with/without comparison would prove nothing.
    env = dict(os.environ)
    if hide_yaml:
        # A stub package that raises ImportError shadows the real PyYAML.
        stub = tmp_path / "noyaml"
        stub.mkdir(exist_ok=True)
        (stub / "yaml.py").write_text("raise ImportError('no pyyaml')\n", encoding="utf-8")
        env["PYTHONPATH"] = str(stub) + os.pathsep + env.get("PYTHONPATH", "")
    return subprocess.run(
        ["bash", str(VALIDATE), str(cfg)],
        capture_output=True,
        text=True,
        env=env,
    )


# ── [18] fallback must load every validated block ───────────────────────────


def test_fallback_loads_the_blocks_the_validator_checks() -> None:
    from mb_pipeline_minimal_yaml import minimal_pipeline_load

    cfg = minimal_pipeline_load(BASE)
    missing = [k for k in ("workflows", "review", "judge") if not cfg.get(k)]
    assert missing == [], f"stdlib fallback dropped validated blocks: {missing}"


def test_fallback_rejects_a_bad_judge_decision_enum(tmp_path: pathlib.Path) -> None:
    """`SHIP_IT` is not a legal decision; PyYAML rejects it, stdlib must too."""
    bad = BASE.replace("decisions: [GO, GO_WITH_BACKLOG, NO_GO]", "decisions: [GO, SHIP_IT]")
    with_yaml = _run_validator(tmp_path, bad, hide_yaml=False)
    without_yaml = _run_validator(tmp_path, bad, hide_yaml=True)
    assert with_yaml.returncode != 0, "baseline: PyYAML path should reject SHIP_IT"
    assert without_yaml.returncode != 0, (
        "stdlib-only path accepted a decision enum PyYAML rejects\n"
        f"stdout={without_yaml.stdout}\nstderr={without_yaml.stderr}"
    )


# ── [19] spec_review must actually live under sdd ───────────────────────────


def test_spec_review_at_top_level_is_rejected(tmp_path: pathlib.Path) -> None:
    """Runtime reads `sdd.spec_review`; a top-level one is dead config."""
    text = without_spec_review() + (
        "spec_review: {enabled: true, agent: mb-reviewer, model: sonnet, thinking: high}\n"
    )
    res = _run_validator(tmp_path, text, hide_yaml=False)
    assert res.returncode != 0, (
        "top-level spec_review validated clean, but runtime would never find it\n"
        f"stdout={res.stdout}"
    )


def test_spec_review_under_sdd_is_accepted(tmp_path: pathlib.Path) -> None:
    text = with_spec_review("{enabled: true, agent: mb-reviewer, model: sonnet, thinking: high}")
    res = _run_validator(tmp_path, text, hide_yaml=False)
    assert res.returncode == 0, f"valid config rejected\nstdout={res.stdout}"


# ── [20] enabled spec_review requires string identity ───────────────────────


def test_enabled_spec_review_rejects_non_string_identity(tmp_path: pathlib.Path) -> None:
    text = with_spec_review("{enabled: true, agent: false, model: 123, thinking: medium}")
    res = _run_validator(tmp_path, text, hide_yaml=False)
    assert res.returncode != 0, (
        "C5 requires non-empty string agent/model; booleans and numbers passed\n"
        f"stdout={res.stdout}"
    )
