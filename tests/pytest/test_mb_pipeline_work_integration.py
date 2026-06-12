"""Named pipelines — end-to-end threading into /mb work consumers (Stage 5).

Consumers resolve their config via `mb-pipeline.sh path "$MB_ARG"`, which now
honors $MB_PIPELINE and host binding. This proves a *real* consumer
(mb-work-protected-check.sh) reads protected_paths from the SELECTED named
pipeline, not the legacy <bank>/pipeline.yaml — with no change to the consumer.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PROTECTED = REPO_ROOT / "scripts" / "mb-work-protected-check.sh"

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


def _bank(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "pipelines").mkdir(parents=True)
    # legacy default — guards secret-legacy/**
    (mb / "pipeline.yaml").write_text(
        'protected_paths:\n  - "secret-legacy/**"\n', encoding="utf-8"
    )
    # named "alt" — guards secret-alt/**, unbound to any host, not default
    (mb / "pipelines" / "alt.yaml").write_text(
        "pipeline_name: alt\n"
        "default: false\n"
        'protected_paths:\n  - "secret-alt/**"\n',
        encoding="utf-8",
    )
    return mb


def _check(file: str, mb: Path, env: dict[str, str]) -> int:
    return subprocess.run(
        ["bash", str(PROTECTED), file, "--mb", str(mb)],
        capture_output=True, text=True, check=False, env=env,
    ).returncode


def test_mb_pipeline_env_selects_named_protected_paths(tmp_path: Path) -> None:
    mb = _bank(tmp_path)
    env = _clean_env()
    env["MB_PIPELINE"] = "alt"
    # alt guards secret-alt/** → protected (exit 1)
    assert _check("secret-alt/x.txt", mb, env) == 1
    # alt does NOT guard secret-legacy → clean (exit 0)
    assert _check("secret-legacy/y.txt", mb, env) == 0


def test_default_selection_uses_legacy_protected_paths(tmp_path: Path) -> None:
    mb = _bank(tmp_path)
    env = _clean_env()  # no MB_PIPELINE, no host → falls back to legacy pipeline.yaml
    # legacy guards secret-legacy/** → protected
    assert _check("secret-legacy/y.txt", mb, env) == 1
    # legacy does NOT guard secret-alt → clean
    assert _check("secret-alt/x.txt", mb, env) == 0
