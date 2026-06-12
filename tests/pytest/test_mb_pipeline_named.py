"""Named pipelines — resolution ladder in scripts/mb-pipeline.sh (Stage 2).

Ladder (first match wins), implemented by `path` / `show`:
  1. --pipeline NAME / MB_PIPELINE env  → <bank>/pipelines/NAME.yaml (hard error if absent)
  2. host-agent binding                 → pipeline whose `agents:` includes the detected host
  3. .mb-config `pipeline=NAME`          → <bank>/pipelines/NAME.yaml
  4. in-file `default: true`             → that pipeline
  5. legacy <bank>/pipeline.yaml         → back-compat
  6. bundled references/pipeline.default.yaml
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-pipeline.sh"
DEFAULT = REPO_ROOT / "references" / "pipeline.default.yaml"

# Every env var that could make mb_detect_host report a host.
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


def _host_env(host_var: str, value: str = "1") -> dict[str, str]:
    env = _clean_env()
    env[host_var] = value
    return env


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    return mb


def _write_pipeline(mb: Path, name: str, *, default: bool = False,
                    agents: list[str] | None = None) -> Path:
    pdir = mb / "pipelines"
    pdir.mkdir(exist_ok=True)
    body = [f"pipeline_name: {name}", f"default: {'true' if default else 'false'}"]
    if agents is not None:
        body.append("agents: [" + ", ".join(agents) + "]")
    # Minimal but valid-enough body for resolution (validation tested elsewhere).
    body += ['version: "1"', "roles: {}", "stage_pipeline: []"]
    f = pdir / f"{name}.yaml"
    f.write_text("\n".join(body) + "\n", encoding="utf-8")
    return f


def _run_path(mb: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), "path", *args, str(mb)],
        capture_output=True, text=True, check=False,
        env=env if env is not None else _clean_env(),
    )


# ── 1. explicit name ────────────────────────────────────────────────────────


def test_path_explicit_pipeline_flag(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    f = _write_pipeline(mb, "pi-governed", agents=["pi"])
    r = _run_path(mb, "--pipeline", "pi-governed")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(f.resolve())


def test_path_explicit_missing_pipeline_errors(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _write_pipeline(mb, "solo", default=True)
    r = _run_path(mb, "--pipeline", "ghost")
    assert r.returncode != 0
    assert "ghost" in (r.stderr + r.stdout)


def test_mb_pipeline_env_acts_like_flag(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    f = _write_pipeline(mb, "pi-governed", agents=["pi"])
    env = _clean_env()
    env["MB_PIPELINE"] = "pi-governed"
    r = _run_path(mb, env=env)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(f.resolve())


# ── 2. host binding ─────────────────────────────────────────────────────────


def test_path_host_binding_auto_selects(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _write_pipeline(mb, "pi-governed", agents=["pi"])
    f = _write_pipeline(mb, "claude-fast", agents=["claude-code"])
    r = _run_path(mb, env=_host_env("CLAUDECODE"))
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(f.resolve())


def test_path_host_binding_prefers_default_among_matches(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _write_pipeline(mb, "claude-a", agents=["claude-code"])
    f = _write_pipeline(mb, "claude-b", agents=["claude-code"], default=True)
    r = _run_path(mb, env=_host_env("CLAUDECODE"))
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(f.resolve())


def test_explicit_flag_overrides_host_binding(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _write_pipeline(mb, "claude-fast", agents=["claude-code"])
    f = _write_pipeline(mb, "pi-governed", agents=["pi"])
    r = _run_path(mb, "--pipeline", "pi-governed", env=_host_env("CLAUDECODE"))
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(f.resolve())


# ── 3. .mb-config pointer ───────────────────────────────────────────────────


def test_path_mbconfig_pipeline_pointer(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    f = _write_pipeline(mb, "solo")  # not default, no agents
    (mb / ".mb-config").write_text("pipeline=solo\n", encoding="utf-8")
    r = _run_path(mb)  # clean env → no host match
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(f.resolve())


# ── 4. in-file default ──────────────────────────────────────────────────────


def test_path_in_file_default(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _write_pipeline(mb, "other")
    f = _write_pipeline(mb, "solo", default=True)
    r = _run_path(mb)  # clean env, no .mb-config
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(f.resolve())


# ── 5. back-compat ──────────────────────────────────────────────────────────


def test_backcompat_no_pipelines_dir_returns_legacy(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    legacy = mb / "pipeline.yaml"
    legacy.write_text("version: 1\n", encoding="utf-8")
    # Even under a host env, with no pipelines/ dir behavior is unchanged.
    r = _run_path(mb, env=_host_env("CLAUDECODE"))
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(legacy.resolve())


def test_backcompat_no_pipelines_no_legacy_returns_default(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run_path(mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(DEFAULT.resolve())


# ── precedence sanity ───────────────────────────────────────────────────────


def test_precedence_flag_beats_mbconfig_beats_default(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    flag_target = _write_pipeline(mb, "flagged")
    _write_pipeline(mb, "pointed")
    _write_pipeline(mb, "defaulted", default=True)
    (mb / ".mb-config").write_text("pipeline=pointed\n", encoding="utf-8")
    # flag wins
    r = _run_path(mb, "--pipeline", "flagged")
    assert r.stdout.strip() == str(flag_target.resolve())
    # without flag, .mb-config pointer wins over in-file default
    r2 = _run_path(mb)
    assert r2.stdout.strip() == str((mb / "pipelines" / "pointed.yaml").resolve())
