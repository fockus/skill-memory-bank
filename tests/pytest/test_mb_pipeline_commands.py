"""Named pipelines — `/mb pipeline` management subcommands (Stage 3).

Covers mb-pipeline.sh: `new`, `use`, `list`.
(`show` / `path` / `validate --pipeline` resolution is covered in test_mb_pipeline_named.py.)
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-pipeline.sh"

_HOST_VARS = (
    "MB_PIPELINE", "MB_PIPELINE_HOST", "MB_AGENT",
    "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT",
    "OPENCODE", "OPENCODE_BIN", "CODEX_SANDBOX", "CODEX_HOME",
    "CURSOR_TRACE_ID", "CURSOR_AGENT", "WINDSURF_AGENT", "PI_AGENT",
)


def _clean_env() -> dict[str, str]:
    env = os.environ.copy()
    for var in _HOST_VARS:
        env.pop(var, None)
    return env


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    return mb


def _run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True, text=True, check=False,
        env=env if env is not None else _clean_env(),
    )


def _meta(path: Path, field: str):
    import yaml
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return data.get(field)


# ── new ─────────────────────────────────────────────────────────────────────


def test_new_creates_named_pipeline_from_default(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("new", "claude-fast", "--agent", "claude-code", str(mb))
    assert r.returncode == 0, r.stderr
    f = mb / "pipelines" / "claude-fast.yaml"
    assert f.is_file()
    assert _meta(f, "pipeline_name") == "claude-fast"
    assert _meta(f, "default") is False
    assert _meta(f, "agents") == ["claude-code"]
    # body inherited from the bundled default
    assert "stage_pipeline" in f.read_text(encoding="utf-8")


def test_new_default_flag_sets_default_true(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("new", "solo", "--default", str(mb))
    assert r.returncode == 0, r.stderr
    f = mb / "pipelines" / "solo.yaml"
    assert _meta(f, "default") is True


def test_new_multiple_agents(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("new", "pi-gov", "--agent", "pi,opencode", str(mb))
    assert r.returncode == 0, r.stderr
    f = mb / "pipelines" / "pi-gov.yaml"
    assert _meta(f, "agents") == ["pi", "opencode"]


def test_new_refuses_existing_without_force(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "solo", str(mb)).returncode == 0
    r = _run("new", "solo", str(mb))
    assert r.returncode != 0
    assert "exists" in (r.stderr + r.stdout).lower()


def test_new_force_overwrites(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "solo", str(mb)).returncode == 0
    r = _run("new", "solo", "--default", "--force", str(mb))
    assert r.returncode == 0, r.stderr
    assert _meta(mb / "pipelines" / "solo.yaml", "default") is True


def test_new_from_named_has_no_duplicate_metadata(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "base", "--agent", "pi", "--default", str(mb)).returncode == 0
    r = _run("new", "derived", "--from", "base", "--agent", "claude-code", str(mb))
    assert r.returncode == 0, r.stderr
    f = mb / "pipelines" / "derived.yaml"
    # fresh metadata wins; no duplicate keys (yaml.safe_load would otherwise collapse them)
    assert _meta(f, "pipeline_name") == "derived"
    assert _meta(f, "agents") == ["claude-code"]
    assert _meta(f, "default") is False
    text = f.read_text(encoding="utf-8")
    assert text.count("pipeline_name:") == 1
    assert text.count("\nagents:") + text.startswith("agents:") == 1


def test_new_created_pipeline_validates(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "claude-fast", "--agent", "claude-code", str(mb)).returncode == 0
    r = _run("validate", "--pipeline", "claude-fast", str(mb))
    assert r.returncode == 0, r.stderr


def test_new_rejects_unsafe_name(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("new", "../escape", str(mb))
    assert r.returncode != 0


# ── use ─────────────────────────────────────────────────────────────────────


def test_use_sets_mbconfig_pointer(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "solo", str(mb)).returncode == 0
    r = _run("use", "solo", str(mb))
    assert r.returncode == 0, r.stderr
    cfg = (mb / ".mb-config").read_text(encoding="utf-8")
    assert "pipeline=solo" in cfg
    # and path resolves to it
    p = _run("path", str(mb))
    assert p.stdout.strip() == str((mb / "pipelines" / "solo.yaml").resolve())


def test_use_missing_pipeline_errors(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("use", "ghost", str(mb))
    assert r.returncode != 0


def test_use_replaces_previous_pointer(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "a", str(mb)).returncode == 0
    assert _run("new", "b", str(mb)).returncode == 0
    assert _run("use", "a", str(mb)).returncode == 0
    assert _run("use", "b", str(mb)).returncode == 0
    cfg = (mb / ".mb-config").read_text(encoding="utf-8")
    assert "pipeline=b" in cfg
    assert "pipeline=a" not in cfg


# ── list ────────────────────────────────────────────────────────────────────


def test_list_shows_pipelines_and_default(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "solo", "--default", str(mb)).returncode == 0
    assert _run("new", "pi-gov", "--agent", "pi", str(mb)).returncode == 0
    r = _run("list", str(mb))
    assert r.returncode == 0, r.stderr
    assert "solo" in r.stdout
    assert "pi-gov" in r.stdout
    assert "pi" in r.stdout  # agents column


def test_list_graceful_when_no_pipelines(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("list", str(mb))
    assert r.returncode == 0, r.stderr
    assert "no named pipelines" in r.stdout.lower()


# ── validate --all (cross-file conflicts) — Stage 4 ─────────────────────────


def test_validate_all_clean_passes(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "solo", "--default", str(mb)).returncode == 0
    assert _run("new", "pi-gov", "--agent", "pi", str(mb)).returncode == 0
    r = _run("validate", "--all", str(mb))
    assert r.returncode == 0, r.stderr + r.stdout


def test_validate_all_detects_two_defaults(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "a", "--default", str(mb)).returncode == 0
    assert _run("new", "b", "--default", str(mb)).returncode == 0
    r = _run("validate", "--all", str(mb))
    assert r.returncode != 0
    assert "default" in (r.stderr + r.stdout).lower()


def test_validate_all_detects_agent_bound_twice(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "a", "--agent", "claude-code", str(mb)).returncode == 0
    assert _run("new", "b", "--agent", "claude-code", str(mb)).returncode == 0
    r = _run("validate", "--all", str(mb))
    assert r.returncode != 0
    assert "claude-code" in (r.stderr + r.stdout)


def test_validate_all_propagates_schema_error(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("new", "ok", str(mb)).returncode == 0
    bad = mb / "pipelines" / "bad.yaml"
    bad.write_text("pipeline_name: bad\nversion: 1\n", encoding="utf-8")  # missing required keys
    r = _run("validate", "--all", str(mb))
    assert r.returncode != 0
    assert "bad" in (r.stderr + r.stdout)
