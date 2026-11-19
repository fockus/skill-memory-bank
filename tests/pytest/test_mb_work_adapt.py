"""adapt-lite Stage 2 — `adapt:` block in pipeline.yaml (default + validator).

Both validator branches (PyYAML and the stdlib fallback) must see the block,
or a bad threshold passes silently in one of them.
"""

from __future__ import annotations

import json
import os
import pathlib
import subprocess

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
VALIDATE = REPO_ROOT / "scripts" / "mb-pipeline-validate.sh"
BASE = (REPO_ROOT / "references" / "pipeline.default.yaml").read_text(encoding="utf-8")
DEFAULT_LINE = (
    "adapt: {enabled: true, verify_fail_cycles: 3, item_token_budget: null, max_depth: 2, "
    "review_cycles: 3, judge_cycles: 2, cascade_stop: 3}"
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
        ("{review_cycles: 0}", "adapt.review_cycles"),
        ("{judge_cycles: -1}", "adapt.judge_cycles"),
        ("{cascade_stop: true}", "adapt.cascade_stop"),
        ("{cascade_stop: three}", "adapt.cascade_stop"),
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


ADAPT = str(REPO_ROOT / "scripts" / "mb_work_adapt.py")


def _state(tmp_path: pathlib.Path, steps: list[str], max_cycles: int = 2) -> str:
    path = tmp_path / "state.json"
    path.write_text(
        json.dumps({"item_no": "4", "steps": steps, "max_cycles": max_cycles}), encoding="utf-8"
    )
    return str(path)


def _check(state: str, *extra: str, stdin: str | None = None) -> dict:
    res = subprocess.run(
        ["python3", ADAPT, "adapt-check", "--state", state, *extra],
        capture_output=True,
        text=True,
        input=stdin,
    )
    assert res.returncode == 0, res.stderr
    return json.loads(res.stdout)


def test_adapt_check_scope_violation_triggers(tmp_path: pathlib.Path) -> None:
    state = _state(tmp_path, [])
    declared = "scripts/a.py, tests/**, docs/*.md, README.md"
    ok = _check(
        state,
        "--declared",
        declared,
        "--changed",
        "-",
        stdin="scripts/a.py\ntests/x/y.py\ndocs/g.md\nREADME.md\n",
    )
    assert ok["trigger"] is False and ok["degraded_guards"] == []
    bad = _check(
        state,
        "--declared",
        declared,
        "--changed",
        "-",
        stdin="scripts/a.py\ndocs/deep/g.md\nscripts/b.py\n",
    )
    assert bad["trigger"] is True and bad["reasons"] == ["scope_violation"]
    assert bad["out_of_scope"] == ["docs/deep/g.md", "scripts/b.py"]


def test_adapt_check_scope_guard_degrades_without_inputs(tmp_path: pathlib.Path) -> None:
    state = _state(tmp_path, [])
    res = _check(state)
    assert res["trigger"] is False and res["degraded_guards"] == ["scope"]
    res = _check(state, "--declared", "a.py")
    assert res["trigger"] is False and res["degraded_guards"] == ["scope"]


@pytest.mark.parametrize(
    ("step", "count", "fires", "reason"),
    [
        ("review_cycle", 2, False, "review_cycles"),
        ("review_cycle", 3, True, "review_cycles"),
        ("judge_cycle", 1, False, "judge_cycles"),
        ("judge_cycle", 2, True, "judge_cycles"),
        ("eval_fail", 1, False, "eval_not_green"),
        ("eval_fail", 2, True, "eval_not_green"),
    ],
)
def test_adapt_check_loop_thresholds(
    tmp_path: pathlib.Path, step: str, count: int, fires: bool, reason: str
) -> None:
    res = _check(_state(tmp_path, [step] * count))
    assert (reason in res["reasons"]) is fires


def test_adapt_check_loop_counters_use_the_sub_item_suffix(tmp_path: pathlib.Path) -> None:
    state = _state(tmp_path, ["review_cycle@4.1"] * 3)
    assert _check(state, "4.1")["reasons"] == ["review_cycles"]
    assert _check(state)["reasons"] == []


def test_adapt_config_new_keys_default_and_override(tmp_path: pathlib.Path) -> None:
    def cfg(pipeline: str) -> dict:
        out = subprocess.run(
            ["python3", ADAPT, "config", "--pipeline", pipeline],
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(out.stdout)

    base = cfg(str(REPO_ROOT / "references" / "pipeline.default.yaml"))
    assert (
        base["verify_fail_cycles"],
        base["review_cycles"],
        base["judge_cycles"],
        base["cascade_stop"],
    ) == (3, 3, 2, 3)
    mine = tmp_path / "p.yaml"
    mine.write_text("adapt: {cascade_stop: 5}\n", encoding="utf-8")
    assert cfg(str(mine))["cascade_stop"] == 5


STAGE18_FILES = (
    "`.memory-bank/specs/svp-adapt-escalation/{requirements,design,tasks}.md`, "
    "`references/adapt.md`, `scripts/mb_work_adapt.py`, `commands/work.md`, "
    "Eval test files of the rebased tasks"
)


def test_adapt_check_scope_guard_ignores_free_text_entries(tmp_path: pathlib.Path) -> None:
    res = _check(
        _state(tmp_path, []),
        "--declared",
        STAGE18_FILES,
        "--changed",
        "-",
        stdin=".memory-bank/specs/svp-adapt-escalation/design.md\nscripts/other.py\n",
    )
    assert res["trigger"] is False and res["degraded_guards"] == ["scope"]


def test_adapt_check_scope_guard_expands_brace_groups(tmp_path: pathlib.Path) -> None:
    declared = "`specs/x/{requirements,design,tasks}.md`, scripts/a.py"
    state = _state(tmp_path, [])
    ok = _check(state, "--declared", declared, "--changed", "-", stdin="specs/x/design.md\n")
    assert ok["trigger"] is False and ok["degraded_guards"] == []
    bad = _check(
        state,
        "--declared",
        declared,
        "--changed",
        "-",
        stdin="specs/x/design.md\nspecs/x/other.md\n",
    )
    assert bad["reasons"] == ["scope_violation"] and bad["out_of_scope"] == ["specs/x/other.md"]
