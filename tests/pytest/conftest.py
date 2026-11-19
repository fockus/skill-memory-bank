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
import json
import os
import shutil
import subprocess
import sys
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
    # The shared git dir too: from a worktree `.git` is a file, so `.git/hooks`
    # sees nothing, yet a test under a leaked GIT_DIR writes the common hooks and
    # core.* (`git init` there sets core.bare=true for every checkout).
    common = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "rev-parse", "--path-format=absolute", "--git-common-dir"],
        text=True, capture_output=True, check=False,
    ).stdout.strip()
    tops = [REPO_ROOT / top for top in _GUARDED]
    if common:
        tops.append(Path(common) / "hooks")
        core = subprocess.run(
            ["git", "config", "--file", f"{common}/config", "--get-regexp", r"^core\."],
            text=True, capture_output=True, check=False,
        ).stdout
        out.append(("git-config core.*", 0, core))
    for top in tops:
        paths = [top]
        if paths[0].is_dir():
            paths = []
            for d, dirs, names in os.walk(top):
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

    Same order as adapters/pi_managed_entrypoint.mjs: the managed install
    (Pi >= 1.1: ~/.pi/agent/install/current-version names the release), else
    the package behind `pi` on PATH. Not `npm root -g`: the first `npm` on PATH
    can belong to another Node (a shim in ~/.local/bin) than the one Pi lives in.
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
    pi = shutil.which("pi")
    if not pi:
        return None
    for folder in Path(pi).resolve().parents:
        manifest = folder / "package.json"
        try:
            if json.loads(manifest.read_text()).get("name") == "@earendil-works/pi-coding-agent":
                return str(folder)
        except (OSError, ValueError):
            continue
    return None


# Run from a git hook (a linked worktree's pre-commit exports an absolute
# GIT_DIR), every `git -C <tmp>` in a test would act on the committing repo.
for _var in subprocess.run(
    ["git", "rev-parse", "--local-env-vars"], text=True, capture_output=True, check=False
).stdout.split():
    os.environ.pop(_var, None)
# Tests sandbox HOME; XDG base dirs must follow it. CI runners export
# XDG_CONFIG_HOME=/home/runner/.config, so installs shared one real directory.
for _var in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"):
    os.environ.pop(_var, None)
# CI runners have no git identity; product code that commits (mb_vcs.sh) needs one.
for _var, _value in (("GIT_AUTHOR_NAME", "mb-test"), ("GIT_COMMITTER_NAME", "mb-test"),
                     ("GIT_AUTHOR_EMAIL", "mb-test@example.invalid"),
                     ("GIT_COMMITTER_EMAIL", "mb-test@example.invalid")):
    os.environ.setdefault(_var, _value)

# Subprocesses that call `python3` get this interpreter directly: a pyenv shim
# costs ~0.6 s per start and an adapter install spawns hundreds of them.
os.environ["PATH"] = os.pathsep.join((os.path.dirname(sys.executable), os.environ.get("PATH", "")))

# Every Pi harness (fixtures read PI_PACKAGE_ROOT / PI_SDK_ROOT, mb-pi reads
# MB_PI_SDK_ROOT) gets the same explicit SDK instead of guessing under a sandbox HOME.
_PI_SDK = os.environ.get("MB_PI_SDK_ROOT") or _installed_pi_sdk()
if _PI_SDK:
    for _name in ("MB_PI_SDK_ROOT", "PI_PACKAGE_ROOT", "PI_SDK_ROOT"):
        os.environ.setdefault(_name, _PI_SDK)


# ~95% of the run (measured: 68 of 72 min) is in these modules — real installers and
# host runtimes. `-m "not slow"` is the quick local loop; CI and pre-merge run everything.
_SLOW_MODULES = frozenset({
    "test_audit_install_roundtrip", "test_cli", "test_codex_native_install",
    "test_global_prompt_guard", "test_opencode_acceptance_native",
    "test_opencode_memory_acceptance_native", "test_opencode_resources",
    "test_opencode_selective_install", "test_opencode_v2_native", "test_opencode_workflow_native",
    "test_pi_native_backends", "test_pi_native_install", "test_pi_native_work",
    "test_runtime_contract", "test_wheel_ships_templates",
})


# Modules that load the real Pi SDK (its jiti) through a node host fixture.
_PI_HOST_MODULES = frozenset({
    "test_pi_native_backends", "test_pi_native_commands", "test_pi_native_embeddings",
    "test_pi_native_graph", "test_pi_native_hooks", "test_pi_native_host",
    "test_pi_native_session", "test_pi_native_work",
})
_NO_PI_SDK = pytest.mark.skip(reason="needs the Pi SDK: npm i -g @earendil-works/pi-coding-agent, or MB_PI_SDK_ROOT")


def pytest_configure(config):
    config.addinivalue_line("markers", "slow: real installers/host runtimes; deselect with -m 'not slow'")


def pytest_collection_modifyitems(items):
    for item in items:
        module = item.module.__name__.rpartition(".")[2]
        if module in _SLOW_MODULES:
            item.add_marker(pytest.mark.slow)
        if not _PI_SDK and module in _PI_HOST_MODULES:
            item.add_marker(_NO_PI_SDK)
