"""adapt-lite Stage 2 — `adapt:` block in pipeline.yaml (default + validator).

Both validator branches (PyYAML and the stdlib fallback) must see the block,
or a bad threshold passes silently in one of them.
"""

from __future__ import annotations

import os
import pathlib
import subprocess

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
VALIDATE = REPO_ROOT / "scripts" / "mb-pipeline-validate.sh"
BASE = (REPO_ROOT / "references" / "pipeline.default.yaml").read_text(encoding="utf-8")
DEFAULT_LINE = (
    "adapt: {enabled: true, verify_fail_cycles: 3, item_token_budget: null, max_depth: 2}"
)


def _validate(tmp_path: pathlib.Path, text: str, *, hide_yaml: bool) -> subprocess.CompletedProcess:
    cfg = tmp_path / "pipeline.yaml"
    cfg.write_text(text, encoding="utf-8")
    env = dict(os.environ)
    if hide_yaml:
        stub = tmp_path / "noyaml"
        stub.mkdir(exist_ok=True)
        (stub / "yaml.py").write_text("raise ImportError('no pyyaml')\n", encoding="utf-8")
        env["PYTHONPATH"] = str(stub) + os.pathsep + env.get("PYTHONPATH", "")
    return subprocess.run(
        ["bash", str(VALIDATE), str(cfg)], capture_output=True, text=True, env=env
    )


def test_default_pipeline_declares_the_adapt_block() -> None:
    assert DEFAULT_LINE in BASE


@pytest.mark.parametrize("hide_yaml", [False, True])
def test_default_adapt_block_validates_clean(tmp_path: pathlib.Path, hide_yaml: bool) -> None:
    res = _validate(tmp_path, BASE, hide_yaml=hide_yaml)
    assert res.returncode == 0, res.stderr


@pytest.mark.parametrize("hide_yaml", [False, True])
@pytest.mark.parametrize(
    ("inline", "expected"),
    [
        ("{enabled: yes-please}", "adapt.enabled"),
        ("{verify_fail_cycles: 0}", "adapt.verify_fail_cycles"),
        ("{item_token_budget: -5}", "adapt.item_token_budget"),
        ("{max_depth: 0}", "adapt.max_depth"),
        ("{max_dpeth: 2}", "unknown keys"),
    ],
)
def test_bad_adapt_values_are_rejected(
    tmp_path: pathlib.Path, hide_yaml: bool, inline: str, expected: str
) -> None:
    res = _validate(tmp_path, BASE.replace(DEFAULT_LINE, "adapt: " + inline), hide_yaml=hide_yaml)
    assert res.returncode != 0
    assert expected in res.stderr


REPORT = """STATUS: BLOCKED

```yaml
complexity_escalation:
  reason: "needs refresh, see # 12"
  estimate: big
  proposed_subitems:
    - title: "one"
      Files: a.py, `b.py`
    - title: two
      Files: [c.py]
```
"""


@pytest.mark.parametrize("hide_yaml", [False, True])
def test_escalation_block_parses_with_and_without_pyyaml(
    tmp_path: pathlib.Path, hide_yaml: bool
) -> None:
    report = tmp_path / "report.md"
    report.write_text(REPORT, encoding="utf-8")
    env = dict(os.environ)
    if hide_yaml:
        stub = tmp_path / "noyaml"
        stub.mkdir()
        (stub / "yaml.py").write_text("raise ImportError('no pyyaml')\n", encoding="utf-8")
        env["PYTHONPATH"] = str(stub)
    res = subprocess.run(
        [
            "python3",
            str(REPO_ROOT / "scripts" / "mb_work_adapt.py"),
            "parse",
            "--file",
            str(report),
        ],
        capture_output=True,
        text=True,
        env=env,
    )
    assert res.returncode == 0, res.stderr
    assert '"files": ["a.py", "b.py"]' in res.stdout and '"files": ["c.py"]' in res.stdout
    assert "see # 12" in res.stdout
