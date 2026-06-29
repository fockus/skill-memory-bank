"""Tests for memory_bank_skill.cli.

Covers: argparse, version, bundle resolution, bash discovery, shell wrapper.
Platform behavior mocked; shell invocations use bundled install.sh --help.
"""

from __future__ import annotations

import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import __version__, cli  # noqa: E402
from memory_bank_skill._bundle import find_bundle_root  # noqa: E402


@pytest.fixture(autouse=True)
def _protect_repo_install_manifest():
    """Back up & restore `REPO_ROOT/.installed-manifest.json`.

    `install.sh:17` hard-codes the manifest path to `$SOURCE_SKILL_DIR/...`,
    so every install-related test in this module overwrites the repo's own
    manifest regardless of `$HOME` sandboxing. Without this fixture, tests
    that call `_run_install_sh`/`_run_uninstall_sh` leak state into the
    repo (and therefore into all subsequent tests in the same session).
    Root cause of the audit-time flake on `test_cli_install_uninstall_smoke_with_cursor_global`
    + `test_uninstall_non_interactive_flag_works_without_stdin`.
    """
    manifest = REPO_ROOT / ".installed-manifest.json"
    original = manifest.read_bytes() if manifest.exists() else None
    try:
        yield
    finally:
        if original is None:
            if manifest.exists():
                manifest.unlink()
        else:
            manifest.write_bytes(original)


# ═══════════════════════════════════════════════════════════════
# Version + basic argparse
# ═══════════════════════════════════════════════════════════════


def test_python_version_matches_bundle_version():
    assert __version__ == (REPO_ROOT / "VERSION").read_text().strip()


def test_version_subcommand(capsys):
    rc = cli.main(["version"])
    assert rc == 0
    out = capsys.readouterr().out
    assert __version__ in out
    assert "memory-bank-skill" in out


def test_top_level_version_flag(capsys):
    with pytest.raises(SystemExit) as exc:
        cli.main(["--version"])
    assert exc.value.code == 0
    out = capsys.readouterr().out
    assert __version__ in out


def test_no_subcommand_shows_help_and_exits_nonzero(capsys):
    with pytest.raises(SystemExit) as exc:
        cli.main([])
    # argparse with required=True exits 2
    assert exc.value.code == 2


def test_unknown_subcommand_errors(capsys):
    with pytest.raises(SystemExit):
        cli.main(["bogus"])


# ═══════════════════════════════════════════════════════════════
# Self-update + init + doctor
# ═══════════════════════════════════════════════════════════════


def test_self_update_prints_pipx_command(capsys):
    rc = cli.main(["self-update"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "pipx upgrade" in out
    assert "memory-bank-skill" in out


def test_init_prints_claude_code_hint(capsys):
    rc = cli.main(["init"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "/mb init" in out


def test_init_hint_documents_local_and_global_storage_modes(capsys):
    rc = cli.main(["init"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "--storage" in out, "init hint must surface --storage flag"
    assert "local" in out and "global" in out, (
        "init hint must mention both local and global storage modes"
    )


def test_doctor_reports_bundle_platform_and_bash(capsys):
    cli.main(["doctor"])
    # rc == 0 on systems with bash (macOS/Linux CI); rc==1 on Windows w/o bash
    out = capsys.readouterr().out
    assert __version__ in out
    assert "Bundle root:" in out
    assert "install.sh:" in out
    assert "bash:" in out


# ═══════════════════════════════════════════════════════════════
# Bundle resolution
# ═══════════════════════════════════════════════════════════════


def test_find_bundle_root_resolves_dev_layout():
    root = find_bundle_root()
    assert (root / "install.sh").is_file()
    assert (root / "adapters").is_dir()


def test_bundle_override_env(tmp_path, monkeypatch):
    fake_bundle = tmp_path / "fake"
    fake_bundle.mkdir()
    (fake_bundle / "install.sh").write_text("#!/bin/sh\nexit 0\n")
    monkeypatch.setenv("MB_SKILL_BUNDLE", str(fake_bundle))
    assert find_bundle_root() == fake_bundle


def test_bundle_not_found_raises(monkeypatch, tmp_path):
    monkeypatch.setenv("MB_SKILL_BUNDLE", str(tmp_path / "does-not-exist"))
    monkeypatch.setattr("sys.prefix", str(tmp_path / "nowhere"))
    with (
        patch("memory_bank_skill._bundle.__file__", str(tmp_path / "x.py")),
        pytest.raises(FileNotFoundError),
    ):
        find_bundle_root()


# ═══════════════════════════════════════════════════════════════
# Platform + bash discovery
# ═══════════════════════════════════════════════════════════════


def test_is_windows_detects():
    with patch.object(platform, "system", return_value="Windows"):
        assert cli.is_windows() is True


def test_is_windows_false_on_posix():
    with patch.object(platform, "system", return_value="Darwin"):
        assert cli.is_windows() is False


def test_find_bash_posix_returns_which_result(monkeypatch):
    monkeypatch.setattr(platform, "system", lambda: "Linux")
    monkeypatch.delenv("MB_BASH", raising=False)
    monkeypatch.setattr(shutil, "which", lambda name: "/usr/bin/bash" if name == "bash" else None)
    assert cli.find_bash() == "/usr/bin/bash"


def test_find_bash_env_override_wins(monkeypatch, tmp_path):
    fake_bash = tmp_path / "custom-bash"
    fake_bash.write_text("")
    monkeypatch.setenv("MB_BASH", str(fake_bash))
    # Even on POSIX with PATH bash — override takes priority.
    monkeypatch.setattr(shutil, "which", lambda name: "/should/not/be/used")
    assert cli.find_bash() == str(fake_bash)


def test_find_bash_env_override_ignored_if_missing(monkeypatch):
    monkeypatch.setenv("MB_BASH", "/does/not/exist/bash")
    monkeypatch.setattr(platform, "system", lambda: "Linux")
    monkeypatch.setattr(shutil, "which", lambda name: "/usr/bin/bash" if name == "bash" else None)
    # Non-existent override falls back to PATH discovery.
    assert cli.find_bash() == "/usr/bin/bash"


def test_find_bash_windows_path_discovery(monkeypatch):
    monkeypatch.setattr(platform, "system", lambda: "Windows")
    monkeypatch.delenv("MB_BASH", raising=False)
    monkeypatch.setattr(
        shutil,
        "which",
        lambda name: r"C:\Program Files\Git\bin\bash.exe" if name == "bash.exe" else None,
    )
    assert cli.find_bash() == r"C:\Program Files\Git\bin\bash.exe"


def test_find_bash_windows_skips_system32(monkeypatch):
    """shutil.which may return C:\\Windows\\System32\\bash.exe (WSL launcher shim).

    That invocation form doesn't handle script forwarding reliably, so the
    discoverer must skip it and prefer Git Bash / explicit WSL."""
    monkeypatch.setattr(platform, "system", lambda: "Windows")
    monkeypatch.delenv("MB_BASH", raising=False)
    # system32 match from `which` ...
    monkeypatch.setattr(
        shutil,
        "which",
        lambda name: r"C:\Windows\System32\bash.exe" if name == "bash.exe" else None,
    )
    # ... and no Git Bash anywhere on disk ...
    monkeypatch.setattr(Path, "exists", lambda self: False)
    # ... falls through to None (or wsl if available — but we killed Path.exists).
    result = cli.find_bash()
    assert result != r"C:\Windows\System32\bash.exe"


def test_find_bash_windows_wsl_fallback(monkeypatch):
    monkeypatch.setattr(platform, "system", lambda: "Windows")
    monkeypatch.delenv("MB_BASH", raising=False)

    def fake_which(name):
        if name in ("bash.exe", "bash"):
            return None
        if name in ("wsl.exe", "wsl"):
            return r"C:\Windows\System32\wsl.exe"
        return None

    monkeypatch.setattr(shutil, "which", fake_which)
    monkeypatch.setattr(Path, "exists", lambda self: False)
    assert cli.find_bash() == r"C:\Windows\System32\wsl.exe"


def test_find_bash_windows_no_bash_returns_none(monkeypatch):
    monkeypatch.setattr(platform, "system", lambda: "Windows")
    monkeypatch.delenv("MB_BASH", raising=False)
    monkeypatch.setattr(shutil, "which", lambda name: None)
    monkeypatch.setattr(Path, "exists", lambda self: False)
    assert cli.find_bash() is None


def test_require_bash_exits_with_hint_on_windows(monkeypatch, capsys):
    monkeypatch.setattr(platform, "system", lambda: "Windows")
    monkeypatch.setattr(cli, "find_bash", lambda: None)
    with pytest.raises(SystemExit) as exc:
        cli.require_bash()
    assert exc.value.code == 2
    err = capsys.readouterr().err
    assert "Git for Windows" in err or "WSL" in err


def test_require_bash_exits_on_posix_without_bash(monkeypatch, capsys):
    monkeypatch.setattr(platform, "system", lambda: "Linux")
    monkeypatch.setattr(cli, "find_bash", lambda: None)
    with pytest.raises(SystemExit):
        cli.require_bash()
    err = capsys.readouterr().err
    assert "bash" in err.lower()


# ═══════════════════════════════════════════════════════════════
# Shell invocation plumbing
# ═══════════════════════════════════════════════════════════════


def test_run_shell_invokes_install_help_via_bundle():
    """install.sh --help prints usage and exits 0 (real subprocess smoke test)."""
    rc = cli.run_shell("install.sh", "--help")
    assert rc == 0


def test_run_shell_missing_script(capsys):
    rc = cli.run_shell("does-not-exist.sh")
    assert rc == 3
    err = capsys.readouterr().err
    assert "missing bundled script" in err


def test_run_shell_passes_interpreter_via_env(monkeypatch):
    """run_shell must hand the bundled script the interpreter that owns the
    package (``sys.executable``) through ``MB_PYTHON``.

    Regression for the pipx/pip/brew install bug: install.sh shells out to
    ``python3 -m memory_bank_skill._texttools``; when the package lives in a
    pipx/venv and only the CLI's own interpreter can import it, a bare system
    ``python3`` raises ModuleNotFoundError and (under ``set -euo pipefail``)
    aborts the whole install. Propagating ``sys.executable`` lets the script
    use the right interpreter, while leaving the env's PATH untouched.
    """
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["env"] = kw.get("env")
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    rc = cli.run_shell("install.sh", "--help")
    assert rc == 0
    assert captured["env"] is not None, "run_shell must pass an explicit env"
    assert captured["env"].get("MB_PYTHON") == sys.executable
    # The rest of the environment must be preserved (PATH, HOME, …).
    assert "PATH" in captured["env"]


def test_install_cmd_passes_clients_flag(tmp_path, monkeypatch):
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Darwin")
    rc = cli.main(["install", "--clients", "cursor", "--project-root", str(tmp_path)])
    assert rc == 0
    # cmd = [bash_path, install_sh_path, --clients, cursor, --project-root, <path>]
    assert any("install.sh" in part for part in captured["cmd"])
    assert "--clients" in captured["cmd"]
    assert "cursor" in captured["cmd"]
    assert "--project-root" in captured["cmd"]


def test_install_cmd_passes_language_flag(monkeypatch):
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Darwin")
    rc = cli.main(["install", "--language", "ru"])
    assert rc == 0
    assert "--language" in captured["cmd"]
    assert "ru" in captured["cmd"]


def test_install_cmd_no_args_calls_install_sh(monkeypatch):
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Linux")
    rc = cli.main(["install"])
    assert rc == 0
    assert "--clients" not in captured["cmd"]


def test_install_cmd_forwards_non_interactive(monkeypatch):
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Darwin")
    rc = cli.main(["install", "--non-interactive"])
    assert rc == 0
    assert "--non-interactive" in captured["cmd"]


def test_install_cmd_rejects_invalid_clients_before_shell(monkeypatch, capsys):
    called = {"run_shell": False}

    def fake_run_shell(*args, **kwargs):
        called["run_shell"] = True
        return 0

    monkeypatch.setattr(cli, "run_shell", fake_run_shell)
    rc = cli.main(["install", "--clients", "cursor,bogus-client"])
    assert rc == 2
    assert called["run_shell"] is False
    assert "invalid client" in capsys.readouterr().err.lower()


def test_uninstall_cmd_calls_uninstall_sh(monkeypatch):
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Darwin")
    rc = cli.main(["uninstall"])
    assert rc == 0
    assert any("uninstall.sh" in part for part in captured["cmd"])


def test_uninstall_cmd_forwards_non_interactive(monkeypatch):
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Darwin")
    rc = cli.main(["uninstall", "-y"])
    assert rc == 0
    assert "-y" in captured["cmd"] or "--non-interactive" in captured["cmd"]


def test_run_shell_wsl_wrapper_mode(monkeypatch):
    """When bash path is wsl.exe, run_shell should prepend 'bash' to cmd."""
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Windows")
    monkeypatch.setattr(cli, "require_bash", lambda: r"C:\Windows\System32\wsl.exe")
    rc = cli.run_shell("install.sh", "--help")
    assert rc == 0
    # cmd should be [wsl.exe, bash, <script>, --help]
    assert captured["cmd"][0].lower().endswith("wsl.exe")
    assert captured["cmd"][1] == "bash"
    assert captured["cmd"][-1] == "--help"


def test_run_shell_plain_bash_mode(monkeypatch):
    """When bash is a regular bash binary, no 'bash' prefix is needed."""
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Darwin")
    monkeypatch.setattr(cli, "require_bash", lambda: "/bin/bash")
    rc = cli.run_shell("install.sh", "--help")
    assert rc == 0
    assert captured["cmd"][0] == "/bin/bash"
    assert "install.sh" in captured["cmd"][1]
    assert captured["cmd"][-1] == "--help"


def test_run_shell_returns_bash_not_found_when_subprocess_spawn_fails(monkeypatch, capsys):
    def fake_run(*args, **kwargs):
        raise FileNotFoundError

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(cli, "require_bash", lambda: "/missing/bash")
    rc = cli.run_shell("install.sh", "--help")
    assert rc == cli.EXIT_BASH_NOT_FOUND
    assert "not found" in capsys.readouterr().err.lower()


# ═══════════════════════════════════════════════════════════════
# Cursor global parity — end-to-end install/uninstall smoke test
# ═══════════════════════════════════════════════════════════════


def _run_install_sh(sandbox_home: Path, repo_root: Path) -> subprocess.CompletedProcess:
    """Run the real install.sh against a sandboxed $HOME."""
    env = {
        "HOME": str(sandbox_home),
        "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    }
    return subprocess.run(
        ["bash", str(repo_root / "install.sh"), "--non-interactive"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _run_uninstall_sh(
    sandbox_home: Path,
    repo_root: Path,
    *extra_args: str,
    input_text: str | None = "y\n",
) -> subprocess.CompletedProcess:
    env = {
        "HOME": str(sandbox_home),
        "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    }
    return subprocess.run(
        ["bash", str(repo_root / "uninstall.sh"), *extra_args],
        env=env,
        input=input_text,
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash required")
@pytest.mark.skipif(shutil.which("jq") is None, reason="jq required for Cursor hooks.json merge")
def test_cli_install_uninstall_smoke_with_cursor_global(tmp_path):
    """Smoke test: memory-bank install/uninstall don't crash with Cursor global steps."""
    sandbox = tmp_path / "home"
    sandbox.mkdir()

    install_result = _run_install_sh(sandbox, REPO_ROOT)
    assert install_result.returncode == 0, (
        f"install.sh failed (rc={install_result.returncode})\n"
        f"stdout:\n{install_result.stdout}\n"
        f"stderr:\n{install_result.stderr}"
    )

    assert (sandbox / ".cursor" / "skills" / "memory-bank").is_symlink()
    assert (sandbox / ".cursor" / "hooks.json").is_file()
    assert (sandbox / ".cursor" / "AGENTS.md").is_file()
    assert (sandbox / ".cursor" / "memory-bank-user-rules.md").is_file()
    assert (sandbox / ".cursor" / "commands" / "mb.md").is_file()

    agents_content = (sandbox / ".cursor" / "AGENTS.md").read_text()
    assert "memory-bank-cursor:start" in agents_content
    assert "memory-bank-cursor:end" in agents_content

    uninstall_result = _run_uninstall_sh(sandbox, REPO_ROOT)
    assert uninstall_result.returncode == 0, (
        f"uninstall.sh failed (rc={uninstall_result.returncode})\n"
        f"stdout:\n{uninstall_result.stdout}\n"
        f"stderr:\n{uninstall_result.stderr}"
    )

    assert not (sandbox / ".cursor" / "skills" / "memory-bank").exists()
    assert not (sandbox / ".cursor" / "memory-bank-user-rules.md").exists()
    assert not (sandbox / ".cursor" / "commands" / "mb.md").exists()


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash required")
def test_install_sh_routes_python_through_mb_python(tmp_path):
    """install.sh must run Python through ``$MB_PYTHON`` (the interpreter the
    CLI hands it), not a bare system ``python3``.

    Deterministic regression for the pipx/pip/brew bug: when the package lives
    only in a venv, the bundled installer must use that venv's interpreter. We
    point ``MB_PYTHON`` at a sentinel wrapper that records its use and then
    delegates to a real python3; if install.sh ignored ``MB_PYTHON`` the marker
    would never appear.
    """
    sandbox = tmp_path / "home"
    sandbox.mkdir()
    marker = tmp_path / "mb_python_was_used"
    fake_py = tmp_path / "mb-python.sh"
    fake_py.write_text(f'#!/usr/bin/env bash\ntouch "{marker}"\nexec python3 "$@"\n')
    fake_py.chmod(0o755)

    env = {
        "HOME": str(sandbox),
        "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "MB_PYTHON": str(fake_py),
    }
    result = subprocess.run(
        ["bash", str(REPO_ROOT / "install.sh"), "--non-interactive"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, (
        f"install.sh failed under MB_PYTHON (rc={result.returncode})\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert marker.exists(), (
        "install.sh did not route Python through MB_PYTHON — a bare system "
        "python3 would break pipx/pip/brew installs"
    )


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash required")
def test_cross_agent_adapters_route_python_through_mb_python(tmp_path):
    """Cross-agent adapters (e.g. cursor.sh ``run_texttool``) must run Python
    through ``$MB_PYTHON``, not a bare ``python3``.

    Regression for the pipx/pyenv break: ``memory_bank_skill`` lives only in the
    interpreter the CLI hands the installer via ``MB_PYTHON``. A bare ``python3``
    resolves to whatever is first on PATH (under pyenv: a shim without the
    package), so ``python3 -m memory_bank_skill._texttools`` raises
    ``ModuleNotFoundError``. cursor.sh swallows that error (``|| true``), so the
    install still returns 0 but silently skips AGENTS.md localization. We poison
    the bare ``python3`` so any package import through it fails loudly, and
    assert the install never falls back to it.
    """
    sandbox = tmp_path / "home"
    sandbox.mkdir()
    project = tmp_path / "project"
    project.mkdir()

    # MB_PYTHON: the real interpreter that owns the package (this test's python),
    # with the repo on PYTHONPATH so `-m memory_bank_skill...` resolves.
    real_py = tmp_path / "mb-python.sh"
    real_py.write_text(
        f'#!/usr/bin/env bash\n'
        f'exec env PYTHONPATH="{REPO_ROOT}${{PYTHONPATH:+:$PYTHONPATH}}" '
        f'"{sys.executable}" "$@"\n'
    )
    real_py.chmod(0o755)

    # Poisoned bare python3: fails on any memory_bank_skill import, else delegates.
    poison_dir = tmp_path / "poison"
    poison_dir.mkdir()
    bare_py = poison_dir / "python3"
    bare_py.write_text(
        '#!/usr/bin/env bash\n'
        'case " $* " in\n'
        '  *memory_bank_skill*) echo "bare python3 used for memory_bank_skill" >&2; exit 1 ;;\n'
        'esac\n'
        f'exec "{sys.executable}" "$@"\n'
    )
    bare_py.chmod(0o755)

    env = {
        "HOME": str(sandbox),
        "PATH": f"{poison_dir}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "MB_PYTHON": str(real_py),
    }
    result = subprocess.run(
        [
            "bash",
            str(REPO_ROOT / "install.sh"),
            "--non-interactive",
            "--clients",
            "claude-code,cursor",
            "--project-root",
            str(project),
        ],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, (
        f"install.sh failed (rc={result.returncode})\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    combined = result.stdout + result.stderr
    assert "No module named 'memory_bank_skill'" not in combined, (
        "a cross-agent adapter imported memory_bank_skill through a bare "
        f"python3 instead of MB_PYTHON\n{combined}"
    )
    assert "bare python3 used for memory_bank_skill" not in combined, (
        "a cross-agent adapter ran `python3 -m memory_bank_skill` through the "
        f"bare PATH interpreter instead of MB_PYTHON\n{combined}"
    )


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash required")
def test_uninstall_non_interactive_flag_works_without_stdin(tmp_path):
    sandbox = tmp_path / "home"
    sandbox.mkdir()

    install_result = _run_install_sh(sandbox, REPO_ROOT)
    assert install_result.returncode == 0

    uninstall_result = _run_uninstall_sh(sandbox, REPO_ROOT, "-y", input_text=None)
    assert uninstall_result.returncode == 0, uninstall_result.stderr


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash required")
def test_install_manifest_has_schema_version_and_stable_file_order(tmp_path):
    sandbox = tmp_path / "home"
    sandbox.mkdir()

    manifest_path = REPO_ROOT / ".installed-manifest.json"
    original_manifest = (
        manifest_path.read_text(encoding="utf-8") if manifest_path.exists() else None
    )

    try:
        first = _run_install_sh(sandbox, REPO_ROOT)
        assert first.returncode == 0, first.stderr
        manifest_1 = json.loads(manifest_path.read_text(encoding="utf-8"))

        second = _run_install_sh(sandbox, REPO_ROOT)
        assert second.returncode == 0, second.stderr
        manifest_2 = json.loads(manifest_path.read_text(encoding="utf-8"))

        assert manifest_1["schema_version"] == 1
        assert manifest_2["schema_version"] == 1
        assert manifest_1["files"] == manifest_2["files"]
        assert manifest_1["backups"] == manifest_2["backups"]
    finally:
        if original_manifest is None:
            manifest_path.unlink(missing_ok=True)
        else:
            manifest_path.write_text(original_manifest, encoding="utf-8")
