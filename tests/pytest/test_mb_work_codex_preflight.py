"""I-093 Stage 8 — `scripts/mb-work-codex-preflight.sh` fail-safe codex CLI
availability/auth health-check, run before a cross-model review wave (`/mb
work` step 5d). Must never block a session: always exit 0, `--json` schema
is `{"available": bool, "reason": str}`.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-codex-preflight.sh"

# A minimal, real-codex-free PATH: enough for bash/sleep/kill/head builtin
# tooling to run, but no chance of hitting an actually-installed `codex`
# (e.g. Homebrew's) on the machine running the suite.
SAFE_PATH = "/usr/bin:/bin"


def _stub_codex(tmp_path: Path, body: str) -> Path:
    """Write an executable `codex` stub into a fresh temp bin dir; return that dir."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    stub = bin_dir / "codex"
    stub.write_text(body)
    stub.chmod(0o755)
    return bin_dir


def _run(
    *args: str,
    path: str,
    extra_env: dict[str, str] | None = None,
    timeout: float = 15,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PATH"] = path
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        env=env,
        timeout=timeout,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_preflight_available_when_codex_ok(tmp_path: Path) -> None:
    bin_dir = _stub_codex(
        tmp_path,
        "#!/bin/bash\n"
        'if [ "$1" = "login" ] && [ "$2" = "status" ]; then\n'
        '  echo "Logged in as dev@example.com"\n'
        "  exit 0\n"
        "fi\n"
        "exit 1\n",
    )
    r = _run("--json", path=f"{bin_dir}:{SAFE_PATH}")
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload["available"] is True


def test_preflight_unavailable_when_codex_missing(tmp_path: Path) -> None:
    r = _run("--json", path=SAFE_PATH)
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload["available"] is False
    assert "not found" in payload["reason"].lower()


def test_preflight_unavailable_on_auth_403(tmp_path: Path) -> None:
    bin_dir = _stub_codex(
        tmp_path,
        "#!/bin/bash\n"
        'if [ "$1" = "login" ] && [ "$2" = "status" ]; then\n'
        '  echo "Error: request failed with status 403 Forbidden"\n'
        "  exit 1\n"
        "fi\n"
        "exit 1\n",
    )
    r = _run("--json", path=f"{bin_dir}:{SAFE_PATH}")
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload["available"] is False
    assert "403" in payload["reason"]


def test_preflight_is_fail_safe(tmp_path: Path) -> None:
    """A hanging/misbehaving codex must never wedge or fail the preflight."""
    bin_dir = _stub_codex(
        tmp_path,
        "#!/bin/bash\n"
        'if [ "$1" = "login" ] && [ "$2" = "status" ]; then\n'
        "  sleep 30\n"
        "  exit 1\n"
        "fi\n"
        "exit 1\n",
    )
    r = _run(
        "--json",
        path=f"{bin_dir}:{SAFE_PATH}",
        extra_env={"MB_CODEX_PREFLIGHT_TIMEOUT_SECS": "1"},
        timeout=10,
    )
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload["available"] is False
