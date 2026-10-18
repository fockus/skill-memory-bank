"""Public Pi entrypoint preflight: required I/O cannot grant write permission."""

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from test_pi_native_install import ROOT, agent_dir, env_for, ledger, sha, snapshot
from test_pi_native_install import box as box


def _inventory(root: Path) -> dict:
    result = {}
    for path in sorted(root.rglob("*")):
        info = path.lstat()
        payload = None
        if path.is_symlink():
            payload = os.readlink(path)
        elif path.is_file():
            try:
                payload = hashlib.sha256(path.read_bytes()).hexdigest()
            except PermissionError:
                payload = "unreadable"
        result[str(path.relative_to(root))] = (
            info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid, info.st_mtime_ns, payload,
        )
    return result


def _limit_file_size() -> None:
    import resource

    resource.setrlimit(resource.RLIMIT_FSIZE, (0, 0))


def _run(home: Path, project: Path, temp: Path, bundle: Path = ROOT,
         limited: bool = False) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["bash", str(bundle / "adapters/pi.sh"), "install-global-extensions", str(project)],
        cwd=project.parent, env=env_for(home, {"TMPDIR": str(temp)}), capture_output=True, text=True,
        timeout=180, check=False, preexec_fn=_limit_file_size if limited else None,
    )
    log = project.parent / f"adapter-{len(list(project.parent.glob('adapter-*.json')))}.json"
    log.write_text(json.dumps({"argv": result.args, "exit": result.returncode,
                               "stdout": result.stdout, "stderr": result.stderr,
                               "cwd": str(project.parent), "TMPDIR": str(temp)}), encoding="utf-8")
    return result


def _healthy(home: Path, project: Path, temp: Path) -> None:
    result = _run(home, project, temp)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (agent_dir(home) / ".mb-global-extensions-manifest.json").is_file()


@pytest.mark.skipif(sys.platform != "darwin", reason="Native Darwin temp selection")
def test_native_darwin_adapter_uses_explicit_private_temp(box: tuple[Path, Path], tmp_path: Path) -> None:
    home, project = box
    temp = tmp_path / "private temp"
    temp.mkdir()
    result = _run(home, project, temp)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stderr == ""
    assert json.loads((agent_dir(home) / ".mb-global-extensions-manifest.json").read_text())["install_state"] == "complete"
    assert list(temp.iterdir()) == []


def test_missing_temp_directory_refuses_before_owned_state_changes(box: tuple[Path, Path], tmp_path: Path) -> None:
    home, project = box
    temp = tmp_path / "temp"
    temp.mkdir()
    _healthy(home, project, temp)
    before = _inventory(home), _inventory(project)
    result = _run(home, project, tmp_path / "absent" / "temp")
    assert result.returncode != 0
    assert "preflight" in result.stderr.lower()
    assert (_inventory(home), _inventory(project)) == before
    assert list(temp.iterdir()) == []


def test_missing_required_module_hash_preserves_owned_install(box: tuple[Path, Path], tmp_path: Path) -> None:
    home, project = box
    temp = tmp_path / "temp"
    temp.mkdir()
    _healthy(home, project, temp)
    bundle = tmp_path / "incomplete bundle"
    shutil.copytree(ROOT, bundle)
    (bundle / "adapters/pi_managed_entrypoint.mjs").unlink()
    before = _inventory(home), _inventory(project)
    result = _run(home, project, temp, bundle)
    assert result.returncode != 0
    assert (_inventory(home), _inventory(project)) == before
    assert "preflight" in result.stderr.lower()
    assert list(temp.iterdir()) == []


@pytest.mark.skipif(os.name == "nt", reason="POSIX required-render I/O limit")
def test_launcher_render_io_failure_is_not_a_safe_preflight(box: tuple[Path, Path], tmp_path: Path) -> None:
    home, project = box
    temp = tmp_path / "temp"
    temp.mkdir()
    (agent_dir(home) / "settings.json").write_text('{"theme":"user"}\n', encoding="utf-8")
    before = _inventory(home), _inventory(project)
    result = _run(home, project, temp, limited=True)
    assert result.returncode != 0
    assert (_inventory(home), _inventory(project)) == before
    assert "preflight" in result.stderr.lower()
    assert list(temp.iterdir()) == []


@pytest.mark.skipif(os.name == "nt" or os.geteuid() == 0, reason="Real non-root file permissions")
def test_unreadable_existing_launcher_is_an_error_not_permission(box: tuple[Path, Path], tmp_path: Path) -> None:
    home, project = box
    temp = tmp_path / "temp"
    temp.mkdir()
    _healthy(home, project, temp)
    entry = agent_dir(home) / "bin/mb-pi"
    mode = entry.stat().st_mode & 0o777
    with entry.open("rb") as original:
        data = original.read()
        entry.chmod(0)
        try:
            before = _inventory(home), _inventory(project)
            result = _run(home, project, temp)
            assert result.returncode != 0
            assert "preflight" in result.stderr.lower()
            assert (_inventory(home), _inventory(project)) == before
            original.seek(0)
            assert original.read() == data
        finally:
            entry.chmod(mode)
    assert list(temp.iterdir()) == []


def test_healthy_owned_retry_keeps_hash_authority_and_cleans_temp(box: tuple[Path, Path], tmp_path: Path) -> None:
    home, project = box
    temp = tmp_path / "temp"
    temp.mkdir()
    first = _run(home, project, temp)
    assert first.returncode == 0 and first.stderr == "", first.stdout + first.stderr
    before = snapshot(home)
    second = _run(home, project, temp)
    assert second.returncode == 0 and second.stderr == "", second.stdout + second.stderr
    assert snapshot(home) == before
    assert all(item["sha256"] == sha(path) for path, item in ledger(home)["files"].items())
    assert list(temp.iterdir()) == []


@pytest.mark.parametrize("name", ["mb-pi", "mb-pi.mjs"])
def test_foreign_entrypoint_refuses_without_adoption(name: str, box: tuple[Path, Path], tmp_path: Path) -> None:
    home, project = box
    temp = tmp_path / "temp"
    temp.mkdir()
    entry = agent_dir(home) / "bin" / name
    entry.parent.mkdir()
    entry.write_text("User-owned entrypoint\n", encoding="utf-8")
    before = _inventory(home), _inventory(project)
    result = _run(home, project, temp)
    assert result.returncode != 0
    assert "not owned" in result.stderr
    assert (_inventory(home), _inventory(project)) == before
    assert list(temp.iterdir()) == []
