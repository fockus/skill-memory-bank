"""Tests for memory_bank_skill.cli.

Covers: argparse, version, platform gate, bundle resolution, shell wrapper paths.
Windows paths mocked; shell invocations use bundled install.sh --help (safe, no-op).
"""

from __future__ import annotations

import io
import os
import platform
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import __version__  # noqa: E402
from memory_bank_skill import cli  # noqa: E402
from memory_bank_skill._bundle import find_bundle_root  # noqa: E402


# ═══════════════════════════════════════════════════════════════
# Version + basic argparse
# ═══════════════════════════════════════════════════════════════

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
    # argparse with required=True exits 2 and writes to stderr
    assert exc.value.code == 2


def test_unknown_subcommand_errors(capsys):
    with pytest.raises(SystemExit):
        cli.main(["bogus"])


# ═══════════════════════════════════════════════════════════════
# Self-update + doctor
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


def test_doctor_reports_bundle_and_platform(capsys):
    rc = cli.main(["doctor"])
    assert rc == 0
    out = capsys.readouterr().out
    assert __version__ in out
    assert "Bundle root:" in out
    assert "install.sh:" in out


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
    # Patch dev-layout candidate to also be invalid
    with patch("memory_bank_skill._bundle.__file__", str(tmp_path / "x.py")):
        with pytest.raises(FileNotFoundError):
            find_bundle_root()


# ═══════════════════════════════════════════════════════════════
# Platform gate
# ═══════════════════════════════════════════════════════════════

def test_is_windows_detects():
    with patch.object(platform, "system", return_value="Windows"):
        assert cli.is_windows() is True


def test_install_on_windows_exits_with_wsl_hint(capsys):
    with patch.object(platform, "system", return_value="Windows"):
        with pytest.raises(SystemExit) as exc:
            cli.main(["install"])
        assert exc.value.code == 2
    err = capsys.readouterr().err
    assert "WSL" in err or "Windows" in err


def test_uninstall_on_windows_exits(capsys):
    with patch.object(platform, "system", return_value="Windows"):
        with pytest.raises(SystemExit):
            cli.main(["uninstall"])


# ═══════════════════════════════════════════════════════════════
# Shell invocation plumbing
# ═══════════════════════════════════════════════════════════════

def test_run_shell_invokes_install_help_via_bundle(monkeypatch):
    """install.sh --help prints usage and exits 0 (smoke test for shell wrapper)."""
    rc = cli.run_shell("install.sh", "--help")
    assert rc == 0


def test_run_shell_missing_script(monkeypatch, capsys):
    rc = cli.run_shell("does-not-exist.sh")
    assert rc == 3
    err = capsys.readouterr().err
    assert "missing bundled script" in err


def test_install_cmd_passes_clients_flag(tmp_path, monkeypatch):
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Darwin")
    rc = cli.main(["install", "--clients", "cursor", "--project-root", str(tmp_path)])
    assert rc == 0
    assert "install.sh" in captured["cmd"][1]
    assert "--clients" in captured["cmd"]
    assert "cursor" in captured["cmd"]
    assert "--project-root" in captured["cmd"]


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


def test_uninstall_cmd_calls_uninstall_sh(monkeypatch):
    captured: dict = {}

    def fake_run(cmd, check, **kw):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(subprocess, "run", fake_run)
    monkeypatch.setattr(platform, "system", lambda: "Darwin")
    rc = cli.main(["uninstall"])
    assert rc == 0
    assert "uninstall.sh" in captured["cmd"][1]
