"""Shared pytest guards.

Keeps the suite hermetic against the one step that reaches outside the process:
``mb-codegraph.py --apply`` spawns a detached embedding builder when a semantic
venv exists (``~/.claude/hooks/.venv``). Left alone, every apply-mode test on a
developer machine would fork a real fastembed child — and on a cold machine each
one would try to download the model. Tests that want the builder set
``MB_SEMANTIC_PY`` themselves.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
# What install.sh writes into the skill dir (manifest) or the default project
# root ($PWD) — mirrors tests/bats/lib/repo_guard.bash. The checkout is the
# owner's live skill, so none of it may change during a test run.
_GUARDED = (
    ".installed-manifest.json", ".mb-agents-owners.json", ".mb-pi-manifest.json",
    ".mb-cline-manifest.json", ".codex", ".cursor", ".pi", ".windsurf", ".clinerules",
    ".kilocode", ".opencode", "opencode.json", ".git/hooks",
)


def _repo_fingerprint() -> list[tuple[str, int, str]]:
    out = []
    for top in _GUARDED:
        paths = [REPO_ROOT / top]
        if paths[0].is_dir():
            paths = []
            for d, dirs, names in os.walk(REPO_ROOT / top):
                dirs[:] = sorted(x for x in dirs if x != "node_modules")
                paths += [Path(d) / n for n in sorted(names)]
        for p in paths:
            if p.is_file():
                out.append((str(p), p.stat().st_mtime_ns, hashlib.sha256(p.read_bytes()).hexdigest()))
    return out


@pytest.fixture(scope="session", autouse=True)
def _repo_checkout_untouched(tmp_path_factory):
    # Without MB_MANIFEST_PATH install.sh writes its manifest next to itself —
    # the owner's install manifest in this checkout. Default it to a temp path
    # (as tests/bats/lib/repo_guard.bash does); a test that exercises the
    # resolver's own default unsets it with monkeypatch, which restores it after.
    saved = os.environ.get("MB_MANIFEST_PATH")
    os.environ["MB_MANIFEST_PATH"] = str(tmp_path_factory.mktemp("guard") / "installed-manifest.json")
    before = _repo_fingerprint()
    yield
    if saved is None:
        os.environ.pop("MB_MANIFEST_PATH", None)
    else:
        os.environ["MB_MANIFEST_PATH"] = saved
    changed = sorted(set(before) ^ set(_repo_fingerprint()))
    assert not changed, f"the test run wrote into the repo checkout: {changed}"


@pytest.fixture(autouse=True)
def _no_background_embedder(monkeypatch, tmp_path_factory):
    monkeypatch.setenv("MB_SEMANTIC_PY", str(tmp_path_factory.getbasetemp() / "absent-python"))


def _installed_pi_sdk() -> str | None:
    """The real Pi SDK, resolved once with the real HOME (tests then swap HOME).

    Managed install (Pi >= 1.1): ~/.pi/agent/install/current-version names the
    release; older global npm installs live under `npm root -g`.
    """
    agent = Path(os.environ.get("PI_CODING_AGENT_DIR") or Path.home() / ".pi" / "agent")
    try:
        version = (agent / "install" / "current-version").read_text().strip()
        release = agent / "install" / "releases" / version / "node_modules"
        managed = release / "@earendil-works" / "pi-coding-agent"
        if version and "/" not in version and (managed / "package.json").is_file():
            return str(managed)
    except OSError:
        pass
    try:
        npm = subprocess.run(["npm", "root", "-g"], text=True, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    legacy = Path(npm.stdout.strip()) / "@earendil-works" / "pi-coding-agent"
    return str(legacy) if (legacy / "package.json").is_file() else None


# Every Pi harness (fixtures read PI_PACKAGE_ROOT / PI_SDK_ROOT, mb-pi reads
# MB_PI_SDK_ROOT) gets the same explicit SDK instead of guessing under a sandbox HOME.
_PI_SDK = os.environ.get("MB_PI_SDK_ROOT") or _installed_pi_sdk()
if _PI_SDK:
    for _name in ("MB_PI_SDK_ROOT", "PI_PACKAGE_ROOT", "PI_SDK_ROOT"):
        os.environ.setdefault(_name, _PI_SDK)
