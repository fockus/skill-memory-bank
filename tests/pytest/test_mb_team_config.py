"""`team:` block of pipeline.yaml: schema, stdlib/PyYAML parity, resource JSON (C3).

Fixture `tests/fixtures/team/pipeline-team.yaml` is the golden team block of
specs/mb-team/examples.md section 1.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
CONFIG = SCRIPTS / "mb_team_config.py"
VALIDATE = SCRIPTS / "mb-pipeline-validate.sh"
FIXTURE = REPO_ROOT / "tests" / "fixtures" / "team" / "pipeline-team.yaml"
DEFAULT = (REPO_ROOT / "references" / "pipeline.default.yaml").read_text(encoding="utf-8")

sys.path.insert(0, str(SCRIPTS))


def _env(tmp_path: Path, *, hide_yaml: bool = False) -> dict[str, str]:
    env = dict(os.environ)
    env["MB_LOCK_DIR"] = "/tmp/mb-locks-test"
    if hide_yaml:
        stub = tmp_path / "noyaml"
        stub.mkdir(exist_ok=True)
        (stub / "yaml.py").write_text("raise ImportError('no pyyaml')\n", encoding="utf-8")
        env["PYTHONPATH"] = str(stub) + os.pathsep + env.get("PYTHONPATH", "")
    return env


def _config(tmp_path: Path, *args: str, pipeline: Path = FIXTURE, hide_yaml: bool = False):
    return subprocess.run(
        [sys.executable, str(CONFIG), *args, "--pipeline", str(pipeline),
         "--mb", str(tmp_path / ".memory-bank"), "--json"],
        capture_output=True, text=True, env=_env(tmp_path, hide_yaml=hide_yaml),
    )


def _team_text(body: str) -> str:
    return "team:\n" + body


def _write(tmp_path: Path, text: str, name: str = "pipeline.yaml") -> Path:
    path = tmp_path / name
    path.write_text(text, encoding="utf-8")
    return path


def _default_without_team() -> str:
    head, sep, _tail = DEFAULT.partition("\nteam:\n")
    assert sep, "bundled default has no top-level team: block"
    return head + "\n"


# ── C3 resource JSON ─────────────────────────────────────────────────────────


def test_resource_build_on_examples_matches_c3_json(tmp_path: Path) -> None:
    r = _config(tmp_path, "resource", "build")
    assert r.returncode == 0, r.stderr
    got = json.loads(r.stdout)
    assert got.pop("path") == "/tmp/mb-locks-test/build"
    assert got == {
        "name": "build", "kind": "mutex", "scope": "host",
        "preconditions": {"free_disk_gb": 25, "disk_path": "/System/Volumes/Data", "check": "test -x ./ya"},
        "stop_threshold": {"free_disk_gb": 12, "check": None}, "maintenance": "./ya gc cache",
        "watch_interval_s": 30, "poll_s": 5,
    }


def test_resource_bank_scope_lives_under_bank_locks(tmp_path: Path) -> None:
    r = _config(tmp_path, "resource", "full-tests")
    assert r.returncode == 0, r.stderr
    got = json.loads(r.stdout)
    assert got["path"] == str(tmp_path / ".memory-bank" / ".locks" / "res" / "full-tests")
    assert got["preconditions"] == {"free_disk_gb": None, "disk_path": None, "check": None}
    assert got["maintenance"] is None


def test_resource_unknown_name_exits_3(tmp_path: Path) -> None:
    r = _config(tmp_path, "resource", "gpu")
    assert r.returncode == 3
    assert "gpu" in r.stderr


def test_resource_without_yaml_is_identical(tmp_path: Path) -> None:
    with_yaml = _config(tmp_path, "resource", "build")
    without = _config(tmp_path, "resource", "build", hide_yaml=True)
    assert without.returncode == 0, without.stderr
    assert json.loads(without.stdout) == json.loads(with_yaml.stdout)


# ── schema errors name the field, exit 2 ─────────────────────────────────────

BAD_TEAMS = [
    ("  colour: red\n", "team.colour"),
    ("  default_size: huge\n", "team.default_size"),
    ("  presets:\n    small:\n      mode: fast\n", "team.presets.small.mode"),
    ("  presets:\n    small:\n      sparkle: true\n", "team.presets.small.sparkle"),
    ("  overrides:\n    work: heavy\n", "team.overrides.work"),
    ("  review:\n    lenses: [logic, vibes]\n", "team.review.lenses"),
    ("  presets:\n    large:\n      lenses: [perf]\n", "team.presets.large.lenses"),
    ("  review:\n    clean_when: {blocker: 0, critical: 0}\n", "team.review.clean_when"),
    ("  resources:\n    build:\n      kind: semaphore\n", "team.resources.build.kind"),
    ("  resources:\n    build:\n      scope: galaxy\n", "team.resources.build.scope"),
    ("  resources:\n    ../x:\n      kind: mutex\n", "team.resources: invalid name '../x'"),
    ("  resources:\n    build:\n      preconditions: {free_disk_gb: lots}\n",
     "team.resources.build.preconditions.free_disk_gb"),
    ("  presets:\n    small:\n      models: {executor: {slot: mid}}\n", "team.presets.small.models"),
    ("  max_parallel: 0\n", "team.max_parallel"),
]


@pytest.mark.parametrize(("body", "field"), BAD_TEAMS)
def test_invalid_team_exits_2_naming_field(tmp_path: Path, body: str, field: str) -> None:
    path = _write(tmp_path, _team_text(body))
    r = _config(tmp_path, "show", pipeline=path)
    assert r.returncode == 2, r.stdout
    assert field in r.stderr


@pytest.mark.parametrize(("body", "field"), BAD_TEAMS)
def test_invalid_team_errors_identical_without_yaml(tmp_path: Path, body: str, field: str) -> None:
    path = _write(tmp_path, _team_text(body))
    with_yaml = _config(tmp_path, "show", pipeline=path)
    without = _config(tmp_path, "show", pipeline=path, hide_yaml=True)
    assert without.returncode == 2 and field in without.stderr
    assert (without.returncode, without.stderr) == (with_yaml.returncode, with_yaml.stderr)


def test_effective_team_identical_with_and_without_yaml(tmp_path: Path) -> None:
    with_yaml = _config(tmp_path, "show")
    without = _config(tmp_path, "show", hide_yaml=True)
    assert with_yaml.returncode == 0, with_yaml.stderr
    assert json.loads(without.stdout) == json.loads(with_yaml.stdout)
    team = json.loads(with_yaml.stdout)
    assert team["rules"][0] == "Go code: gofmt and go vet clean before you report."
    assert team["presets"]["standard"]["verifier"] == "none"  # project replaces the bundled value
    assert team["presets"]["extra"]["review"] == "lenses"  # omitted size falls back to bundled


def test_bundled_team_block_is_valid_and_has_no_resources(tmp_path: Path) -> None:
    r = _config(tmp_path, "show", pipeline=REPO_ROOT / "references" / "pipeline.default.yaml")
    assert r.returncode == 0, r.stderr
    team = json.loads(r.stdout)
    assert team["resources"] == {}
    assert team["review"]["enabled"] is False
    assert team["review"]["clean_when"] == {"blocker": 0, "major": 0, "medium": 0}


# ── whole-file validator integration ─────────────────────────────────────────


def test_validator_accepts_examples_team_block(tmp_path: Path) -> None:
    path = _write(tmp_path, _default_without_team() + FIXTURE.read_text(encoding="utf-8"))
    for hide in (False, True):
        r = subprocess.run(["bash", str(VALIDATE), str(path)], capture_output=True, text=True,
                           env=_env(tmp_path, hide_yaml=hide))
        assert r.returncode == 0, r.stderr


def test_validator_rejects_bad_team_naming_field(tmp_path: Path) -> None:
    path = _write(tmp_path, _default_without_team() + _team_text("  presets:\n    small:\n      tdd: maybe\n"))
    for hide in (False, True):
        r = subprocess.run(["bash", str(VALIDATE), str(path)], capture_output=True, text=True,
                           env=_env(tmp_path, hide_yaml=hide))
        assert r.returncode == 1
        assert "team.presets.small.tdd" in r.stderr


def test_validator_rejects_nested_inline_map_in_team(tmp_path: Path) -> None:
    body = "  presets:\n    small:\n      models: {lens: {security: premium}}\n"
    path = _write(tmp_path, _default_without_team() + _team_text(body))
    for hide in (False, True):
        r = subprocess.run(["bash", str(VALIDATE), str(path)], capture_output=True, text=True,
                           env=_env(tmp_path, hide_yaml=hide))
        assert r.returncode == 1
        assert "team.presets.small.models" in r.stderr
        assert "nested inline" in r.stderr
