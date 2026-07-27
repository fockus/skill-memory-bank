"""svp-contract-test-loop C1 — the `layers` block parser (Task 2).

The canonical owner of the block is the frontmatter of `requirements.md` and
only that file. Three things this pins, all of which have a wrong-direction
failure mode:

* **No block at all means LEGACY**, not "all layers on". The earlier default
  made every pre-existing spec invalid under the new gates — including S8's own
  spec, which has gated requirements and no block, and would therefore have
  failed the contract gate it introduces (R3-001).
* **A layer switched off must say why.** `false` without `<layer>_reason` is an
  error, so "we skipped it for speed" stays a recorded decision instead of a
  silently missing task (REQ-011).
* **Reading never writes.** A parser that normalised the file on read would
  rewrite specs behind the user's back (NFR-002).
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))


# Imported lazily, INSIDE the tests, on purpose. With a module-level import the
# red run this eval declares — `FAILED ...::test_missing_block_is_legacy` — is
# unobservable: an absent module makes pytest abort at COLLECTION with exit 2
# and "no tests collected", which carries no per-test FAILED line to match. A
# declared red that cannot be observed is the same defect class as a gate that
# runs after the thing it guards.
def _layers():
    from memory_bank_skill import spec_layers
    return spec_layers


def read_spec_layers(*args, **kwargs):
    return _layers().read_spec_layers(*args, **kwargs)


def spec_layers_error():
    return _layers().SpecLayersError

PIPELINE_DEFAULT = REPO_ROOT / "references" / "pipeline.default.yaml"


def write_spec(tmp_path: Path, frontmatter: str, *, siblings: dict | None = None) -> Path:
    """A spec dir whose requirements.md carries `frontmatter` between --- fences."""
    spec = tmp_path / "spec"
    spec.mkdir(exist_ok=True)
    req = spec / "requirements.md"
    req.write_text(
        "---\ntopic: demo\n%s---\n\n# Requirements: demo\n\n- **REQ-001** …\n"
        % (frontmatter and frontmatter + "\n" or ""),
        encoding="utf-8",
    )
    for name, text in (siblings or {}).items():
        (spec / name).write_text(text, encoding="utf-8")
    return req


def pipeline_with(tmp_path: Path, sdd_layers: str | None) -> Path:
    p = tmp_path / "pipeline.yaml"
    body = "version: 1\nsdd:\n  enabled: false\n"
    if sdd_layers is not None:
        body += "  layers: %s\n" % sdd_layers
    p.write_text(body, encoding="utf-8")
    return p


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ── legacy ──────────────────────────────────────────────────────────────────


def test_missing_block_is_legacy(tmp_path):
    req = write_spec(tmp_path, "")
    layers = read_spec_layers(req, PIPELINE_DEFAULT)
    assert layers.source == "legacy"
    assert layers.contract_first is False
    assert layers.integration_tests is False
    assert layers.e2e_tests is False


def test_missing_block_is_legacy_even_when_pipeline_enables_everything(tmp_path):
    # The pipeline default must NOT reach a spec that never opted in — that is
    # exactly what made every legacy spec invalid under the first design.
    req = write_spec(tmp_path, "")
    pipeline = pipeline_with(
        tmp_path, "{contract_first: true, integration_tests: true, e2e_tests: true}"
    )
    layers = read_spec_layers(req, pipeline)
    assert layers.source == "legacy"
    assert (layers.contract_first, layers.integration_tests, layers.e2e_tests) == (
        False,
        False,
        False,
    )


def test_missing_block_is_legacy_needs_no_reasons(tmp_path):
    # `_reason` is required for a layer switched off in an EXPLICIT block; a
    # legacy spec never declared anything, so it owes no explanation.
    req = write_spec(tmp_path, "")
    layers = read_spec_layers(req, PIPELINE_DEFAULT)
    assert layers.source == "legacy"
    assert all(v is None for v in layers.reasons.values())


def test_real_s8_spec_is_grandfathered(tmp_path):
    # The regression that motivated legacy mode: S8's own spec has gated
    # requirements, no `layers` block, and `Layer:` only on its last two tasks.
    req = REPO_ROOT / ".memory-bank" / "specs" / "svp-contract-test-loop" / "requirements.md"
    layers = read_spec_layers(req, PIPELINE_DEFAULT)
    assert layers.source == "legacy"
    assert layers.contract_first is False


# ── explicit block + pipeline defaults ──────────────────────────────────────


def test_present_block_inherits_pipeline_default(tmp_path):
    req = write_spec(tmp_path, "layers:\n  contract_first: true\n")
    pipeline = pipeline_with(
        tmp_path, "{contract_first: false, integration_tests: true, e2e_tests: true}"
    )
    layers = read_spec_layers(req, pipeline)
    assert layers.source == "pipeline"
    assert layers.contract_first is True  # spec said so
    assert layers.integration_tests is True  # inherited
    assert layers.e2e_tests is True  # inherited


def test_spec_value_beats_pipeline_default(tmp_path):
    req = write_spec(
        tmp_path,
        'layers:\n  contract_first: false\n  contract_first_reason: "library, no gate"\n'
        "  integration_tests: true\n  e2e_tests: true\n",
    )
    pipeline = pipeline_with(
        tmp_path, "{contract_first: true, integration_tests: true, e2e_tests: true}"
    )
    layers = read_spec_layers(req, pipeline)
    assert layers.source == "spec"
    assert layers.contract_first is False
    assert layers.reasons["contract_first"] == "library, no gate"


def test_absent_pipeline_layers_defaults_to_enabled(tmp_path):
    # REQ-012: "all enabled when unset" — an absent default is not an excuse to
    # hand the gates an empty layer set.
    req = write_spec(tmp_path, "layers:\n  contract_first: true\n")
    pipeline = pipeline_with(tmp_path, None)
    layers = read_spec_layers(req, pipeline)
    assert (layers.integration_tests, layers.e2e_tests) == (True, True)


# ── reasons ─────────────────────────────────────────────────────────────────


def test_false_without_reason_raises(tmp_path):
    req = write_spec(tmp_path, "layers:\n  e2e_tests: false\n")
    with pytest.raises(spec_layers_error()) as exc:
        read_spec_layers(req, PIPELINE_DEFAULT)
    assert exc.value.code == "missing_reason"
    assert exc.value.field == "e2e_tests"


def test_false_with_empty_reason_raises(tmp_path):
    # An empty string is not a reason; accepting it would turn the requirement
    # into a formality anyone can satisfy with `""`.
    req = write_spec(tmp_path, 'layers:\n  e2e_tests: false\n  e2e_tests_reason: ""\n')
    with pytest.raises(spec_layers_error()) as exc:
        read_spec_layers(req, PIPELINE_DEFAULT)
    assert exc.value.code == "missing_reason"


def test_false_inherited_from_pipeline_needs_no_reason(tmp_path):
    # The reason is owed by whoever made the decision. A spec that never
    # mentioned the layer did not decide anything; the pipeline did.
    req = write_spec(tmp_path, "layers:\n  contract_first: true\n")
    pipeline = pipeline_with(
        tmp_path, "{contract_first: true, integration_tests: true, e2e_tests: false}"
    )
    layers = read_spec_layers(req, pipeline)
    assert layers.e2e_tests is False
    assert layers.reasons["e2e_tests"] is None


# ── canonical owner ─────────────────────────────────────────────────────────


@pytest.mark.parametrize("sibling", ["design.md", "tasks.md"])
def test_layers_block_outside_requirements_rejected(tmp_path, sibling):
    req = write_spec(
        tmp_path,
        "layers:\n  contract_first: true\n  integration_tests: true\n  e2e_tests: true\n",
        siblings={sibling: "---\nlayers:\n  contract_first: false\n---\n\n# doc\n"},
    )
    with pytest.raises(spec_layers_error()) as exc:
        read_spec_layers(req, PIPELINE_DEFAULT)
    assert exc.value.code == "noncanonical_owner"
    assert exc.value.field == "%s:layers" % sibling


def test_noncanonical_owner_detected_before_defaults(tmp_path):
    # "BEFORE default resolution" (C1): a sibling block must be reported even
    # when the spec's own block is itself invalid, so the owner error is not
    # masked by a second one.
    req = write_spec(
        tmp_path,
        "layers:\n  e2e_tests: false\n",  # would otherwise raise missing_reason
        siblings={"design.md": "---\nlayers:\n  contract_first: false\n---\n"},
    )
    with pytest.raises(spec_layers_error()) as exc:
        read_spec_layers(req, PIPELINE_DEFAULT)
    assert exc.value.code == "noncanonical_owner"


def test_missing_sibling_is_ignored(tmp_path):
    req = write_spec(
        tmp_path, "layers:\n  contract_first: true\n  integration_tests: true\n  e2e_tests: true\n"
    )
    layers = read_spec_layers(req, PIPELINE_DEFAULT)  # no design.md/tasks.md at all
    assert layers.source == "spec"


def test_sibling_without_layers_key_is_fine(tmp_path):
    req = write_spec(
        tmp_path,
        "layers:\n  contract_first: true\n  integration_tests: true\n  e2e_tests: true\n",
        siblings={"design.md": "---\ntopic: demo\n---\n\n# Design\n\nlayers: mentioned in prose\n"},
    )
    layers = read_spec_layers(req, PIPELINE_DEFAULT)
    assert layers.source == "spec"


# ── malformed ───────────────────────────────────────────────────────────────


def test_unknown_key_in_block_raises(tmp_path):
    req = write_spec(tmp_path, "layers:\n  contract_first: true\n  smoke_tests: true\n")
    with pytest.raises(spec_layers_error()) as exc:
        read_spec_layers(req, PIPELINE_DEFAULT)
    assert exc.value.code == "unknown_key"
    assert exc.value.field == "smoke_tests"


def test_non_boolean_layer_value_raises(tmp_path):
    req = write_spec(tmp_path, "layers:\n  contract_first: maybe\n")
    with pytest.raises(spec_layers_error()) as exc:
        read_spec_layers(req, PIPELINE_DEFAULT)
    assert exc.value.code == "malformed_block"


def test_malformed_pipeline_default_is_loud_not_silently_enabled(tmp_path):
    # The third failure shape: not "the gate did not run" and not "the gate
    # could not fail", but "the gate ran against nothing and reported success".
    # A non-boolean pipeline default must not quietly become True.
    req = write_spec(tmp_path, "layers:\n  contract_first: true\n")
    pipeline = pipeline_with(tmp_path, "{integration_tests: sometimes}")
    with pytest.raises(spec_layers_error()) as exc:
        read_spec_layers(req, pipeline)
    assert exc.value.code in ("malformed_block", "unknown_key")


def test_unknown_key_in_pipeline_default_is_loud(tmp_path):
    req = write_spec(tmp_path, "layers:\n  contract_first: true\n")
    pipeline = pipeline_with(tmp_path, "{smoke_tests: true}")
    with pytest.raises(spec_layers_error()) as exc:
        read_spec_layers(req, pipeline)
    assert exc.value.code == "unknown_key"


# ── purity ──────────────────────────────────────────────────────────────────


def test_read_does_not_mutate_file(tmp_path):
    req = write_spec(
        tmp_path, "layers:\n  contract_first: true\n  integration_tests: true\n  e2e_tests: true\n"
    )
    before = sha(req)
    read_spec_layers(req, PIPELINE_DEFAULT)
    assert sha(req) == before


def test_read_does_not_mutate_legacy_file(tmp_path):
    req = write_spec(tmp_path, "")
    before = sha(req)
    read_spec_layers(req, PIPELINE_DEFAULT)
    assert sha(req) == before


def test_read_does_not_create_a_layers_block(tmp_path):
    req = write_spec(tmp_path, "")
    read_spec_layers(req, PIPELINE_DEFAULT)
    assert "layers" not in req.read_text(encoding="utf-8")


# ── CLI ─────────────────────────────────────────────────────────────────────


def run_cli(req: Path, pipeline: Path):
    return subprocess.run(
        [
            sys.executable,
            "-m",
            "memory_bank_skill.spec_layers",
            "--requirements",
            str(req),
            "--pipeline",
            str(pipeline),
            "--json",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )


def test_cli_emits_json(tmp_path):
    req = write_spec(
        tmp_path, "layers:\n  contract_first: true\n  integration_tests: true\n  e2e_tests: true\n"
    )
    proc = run_cli(req, PIPELINE_DEFAULT)
    assert proc.returncode == 0, proc.stderr
    payload = json.loads(proc.stdout)
    assert payload["source"] == "spec"
    assert payload["contract_first"] is True


def test_cli_legacy_spec_reports_legacy(tmp_path):
    req = write_spec(tmp_path, "")
    proc = run_cli(req, PIPELINE_DEFAULT)
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout)["source"] == "legacy"


def test_cli_noncanonical_owner_exits_1(tmp_path):
    req = write_spec(
        tmp_path,
        "layers:\n  contract_first: true\n  integration_tests: true\n  e2e_tests: true\n",
        siblings={"design.md": "---\nlayers:\n  contract_first: false\n---\n"},
    )
    proc = run_cli(req, PIPELINE_DEFAULT)
    assert proc.returncode == 1
    assert proc.stdout == ""
    assert "spec_layers_error=noncanonical_owner field=design.md:layers" in proc.stderr


def test_cli_missing_reason_exits_1(tmp_path):
    req = write_spec(tmp_path, "layers:\n  e2e_tests: false\n")
    proc = run_cli(req, PIPELINE_DEFAULT)
    assert proc.returncode == 1
    assert proc.stdout == ""
    assert "spec_layers_error=missing_reason field=e2e_tests" in proc.stderr


def test_cli_usage_error_exits_2(tmp_path):
    proc = subprocess.run(
        [sys.executable, "-m", "memory_bank_skill.spec_layers", "--requirements"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 2
    assert proc.stdout == ""
