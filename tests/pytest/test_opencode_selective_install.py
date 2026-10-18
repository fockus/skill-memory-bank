"""Public selective lifecycle contract, using real files and private host roots."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def inventory(root):
    result = {".": (stat.S_IMODE(root.lstat().st_mode), "directory")}
    for path in sorted(root.rglob("*")):
        info = path.lstat()
        value = os.readlink(path) if path.is_symlink() else (
            hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "directory"
        )
        result[str(path.relative_to(root))] = (stat.S_IMODE(info.st_mode), value)
    return result


@pytest.fixture
def lab(tmp_path):
    bundle = tmp_path / "bundle"
    bundle.mkdir()
    for name in ("adapters", "agents", "commands", "hooks", "scripts", "rules", "references",
                 "templates", "flow-templates", "settings", "memory_bank_skill"):
        shutil.copytree(ROOT / name, bundle / name, ignore=shutil.ignore_patterns("__pycache__"))
    for name in ("install.sh", "uninstall.sh", "VERSION", "SKILL.md"):
        shutil.copy2(ROOT / name, bundle / name)
    # Representative real payloads keep lifecycle contracts proportional;
    # candidate-wide artifact membership and full payload QA belong to Stage 3.
    for path in (bundle / "commands").glob("*.md"):
        if path.stem not in {"mb", "adr"}:
            path.unlink()
    for path in (bundle / "agents").glob("*.md"):
        if path.stem not in {"mb-developer", "mb-qa"} and "partial: true" not in path.read_text()[:300]:
            path.unlink()
    home, project, temporary = (tmp_path / name for name in ("home", "project", "tmp"))
    for folder in (home, project, temporary):
        folder.mkdir(mode=0o700)
    env = {"PATH": f"{Path(sys.executable).parent}:{os.environ['PATH']}", "HOME": str(home), "TMPDIR": str(temporary),
           "PYTHONPATH": str(bundle), "PYTHONDONTWRITEBYTECODE": "1", "MB_SKIP_DEPS_CHECK": "1",
           "MB_SKILL_BUNDLE": str(bundle),
           "MB_USER_RULES_AUTO_PROMPT": "off", "MB_PYTHON": sys.executable,
           "CODEX_HOME": str(home / ".codex")}
    for suffix in ("CONFIG", "DATA", "CACHE", "STATE", "RUNTIME"):
        env[f"XDG_{suffix}_HOME" if suffix != "RUNTIME" else "XDG_RUNTIME_DIR"] = str(home / suffix.lower())
    # Public pipeline is read-only input; no inherited personal model assignments.
    (project / ".memory-bank").mkdir()
    shutil.copy2(bundle / "references/pipeline.default.yaml", project / ".memory-bank/pipeline.yaml")
    for name in (".claude", ".codex", ".cursor", ".pi/agent", ".config/opencode", "config/memory-bank"):
        folder = home / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "user-canary").write_text("Independent host data\n")
        (folder / "user-canary").chmod(0o640)
        (folder / "alias").symlink_to(bundle, target_is_directory=True)
        (folder / ("CLAUDE.md" if name == ".claude" else "AGENTS.md")).write_text("Independent instructions\n")
        (folder / "settings.json").write_text('{ "keep": true }\n')
        (folder / "pipeline.yaml").write_text("roles:\n  developer: {model: other/host}\n")
        (folder / "skills").mkdir()
        (folder / "skills/memory-bank").symlink_to(bundle, target_is_directory=True)
    oc = home / "config/opencode"
    oc.mkdir(parents=True)
    (oc / "AGENTS.md").write_text("User global instructions\n")
    (oc / "opencode.json").write_text('{ "theme": "user", "agent": {} }\n')
    (project / "AGENTS.md").write_text("User project instructions\n")
    (project / "opencode.json").write_text('{ "plugins": ["unrelated"] }\n')
    return bundle, home, project, env


def invoke(lab, entry="shell", action="install", *args, scoped=True, extra=None):
    bundle, _, project, env = lab
    command = ([sys.executable, "-m", "memory_bank_skill", action] if entry == "cli" else
               ["bash", str(bundle / f"{action}.sh")])
    command += ["--non-interactive"]
    if scoped:
        command += ["--only", "opencode"]
    if action == "install":
        command += ["--project-root", str(project)]
    command += list(args)
    result = subprocess.run(command, cwd=project, env=env | (extra or {}), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    return result


def preserved(lab):
    _, home, project, _ = lab
    paths = [home / name for name in (".claude", ".codex", ".cursor", ".pi", ".config", "config/memory-bank")]
    result = {str(p): inventory(p) for p in paths}
    files = {str(p): (p.read_bytes(), p.stat().st_mode) for p in (
        project / "opencode.json", home / "config/opencode/opencode.json",
        project / ".memory-bank/pipeline.yaml")}
    return result, files


@pytest.mark.parametrize("entry", ["shell", "cli"])
@pytest.mark.parametrize("extended", [False, True])
def test_fresh_opt_in(lab, entry, extended):
    bundle, home, project, _ = lab
    before = preserved(lab)
    result = invoke(lab, entry, "install", *(["--with-extensions=opencode"] if extended else []))
    assert result.returncode == 0, result.stdout
    assert preserved(lab) == before
    oc = home / "config/opencode"
    assert (oc / "skills/memory-bank").resolve() == bundle
    assert (oc / "commands/mb.md").read_bytes() == (bundle / "commands/mb.md").read_bytes()
    assert f"extended: {str(extended).lower()}" in (project / ".opencode/plugins/memory-bank.js").read_text()
    assert (oc / "agent/mb-developer.md").exists() == extended
    assert "User global instructions" in (oc / "AGENTS.md").read_text()
    assert "User project instructions" in (project / "AGENTS.md").read_text()


@pytest.mark.parametrize("entry", ["shell", "cli"])
@pytest.mark.parametrize("args", [("--only", "bad"), ("--only",),
                                  ("--only", "opencode", "--clients", "claude-code"),
                                  ("--only", "opencode", "--with-extensions=pi")])
def test_invalid_selectors(lab, entry, args):
    _, home, project, env = lab
    env["MB_MANIFEST_PATH"] = str(home / "not-created/record.json")
    before = inventory(home), inventory(project)
    result = invoke(lab, entry, "install", *args, scoped=False)
    assert result.returncode != 0
    assert (inventory(home), inventory(project)) == before, result.stdout


@pytest.mark.parametrize("entry", ["shell", "cli"])
def test_owned_repeat_update(lab, entry):
    bundle, home, project, _ = lab
    before = preserved(lab)
    result = invoke(lab, entry, "install", "--with-extensions=opencode")
    assert result.returncode == 0, result.stdout
    alias = home / "config/opencode/skills/memory-bank"
    through_alias = alias, home, project, lab[3] | {"PYTHONPATH": str(alias), "MB_SKILL_BUNDLE": str(alias)}
    result = invoke(through_alias, entry)
    assert result.returncode == 0, result.stdout
    assert alias.resolve() == bundle
    successor = bundle.with_name("successor")
    shutil.copytree(bundle, successor)
    with (successor / "commands/mb.md").open("a") as out:
        out.write("\nSuccessor command\n")
    lab = successor, home, project, lab[3] | {"PYTHONPATH": str(successor), "MB_SKILL_BUNDLE": str(successor)}
    # Plain reinstall, as printed by existing upgrade guidance, retains recorded scope.
    for _ in range(2):
        result = invoke(lab, entry, scoped=False)
        assert result.returncode == 0, result.stdout
    assert preserved(lab) == before
    assert (home / "config/opencode/skills/memory-bank").resolve() == successor
    assert "Successor command" in (project / ".opencode/commands/mb.md").read_text()
    assert "extended: true" in (project / ".opencode/plugins/memory-bank.js").read_text()


@pytest.mark.parametrize("entry", ["shell", "cli"])
@pytest.mark.parametrize("kind", ["hashless", "edited"])
def test_protected_resources(lab, entry, kind):
    bundle, home, project, _ = lab
    if kind == "edited":
        result = invoke(lab, entry, "install", "--with-extensions=opencode")
        assert result.returncode == 0, result.stdout
        target = project / ".opencode/agent/mb-qa.md"
    else:
        target = home / "config/opencode/commands/mb.md"
        target.parent.mkdir(parents=True)
    target.write_text("Managed-looking but unauthorized bytes\n" if kind == "edited" else
                      (bundle / "commands/mb.md").read_text())
    before = inventory(home), inventory(project)
    result = invoke(lab, entry, "install", "--with-extensions=opencode")
    assert result.returncode != 0
    assert str(target) in result.stdout
    assert (inventory(home), inventory(project)) == before, result.stdout
    result = invoke(lab, entry, "uninstall", "--project-root", str(project))
    assert result.returncode != 0
    assert "restore" in result.stdout.lower(), result.stdout
    assert "rm ~/.claude" not in result.stdout
    assert (inventory(home), inventory(project)) == before, result.stdout


@pytest.mark.parametrize("entry", ["shell", "cli"])
@pytest.mark.parametrize("layout", ["canonical", "native-home", "native-xdg"])
@pytest.mark.parametrize("record_kind", ["native", "mixed"])
def test_owned_hashes_survive_alias_checkpoints_and_reinstall(lab, entry, layout, record_kind):
    bundle, original_home, project, original_env = lab
    env = {k: v for k, v in original_env.items() if not k.startswith("XDG_") and k != "CODEX_HOME"}
    home = original_home.with_name("canonical-home")
    home.mkdir(mode=0o700)
    native = None
    if layout != "canonical":
        if sys.platform != "darwin":
            pytest.skip("Requires Darwin's native /var to /private/var system alias")
        created = subprocess.run(["/usr/bin/mktemp", "-d"], cwd=project,
                                 env={k: v for k, v in env.items() if k != "TMPDIR"},
                                 text=True, capture_output=True, check=True, timeout=10)
        native = Path(created.stdout.strip())
    try:
        if native is not None:
            assert str(native).startswith("/var/") and str(native.resolve()).startswith("/private/var/")
            if layout == "native-home":
                home = native
            else:
                env["XDG_CONFIG_HOME"] = str(native / "config")
        env["HOME"] = str(home)
        oc = Path(env.get("XDG_CONFIG_HOME", str(home / ".config"))) / "opencode"
        foreign = home / ".codex"
        foreign.mkdir()
        (foreign / "user-data").write_text("Independent host data\n")
        (foreign / "alias").symlink_to(bundle, target_is_directory=True)
        before = inventory(foreign)
        record = oc / ".mb-install-manifest.json"
        metadata = {"home": str(home), "project_root": str(project), "clients": ["codex"],
                    "adapters_failed": ["pi"], "extensions_installed": ["pi"],
                    "files": [str(foreign / "user-data")],
                    "file_sha256": {str(foreign / "user-data"): "foreign-proof-unchanged"}}
        if record_kind == "mixed":
            record = home / "mixed.json"
            record.write_text(json.dumps(metadata))
            env["MB_MANIFEST_PATH"] = str(record)
        case = bundle, home, project, env
        first = invoke(case, entry, "install", "--with-extensions=opencode")
        assert first.returncode == 0, first.stdout
        saved = json.loads(record.read_text())
        targets = (oc / "commands", oc / "agent", project / ".opencode")
        payload = {str(p): inventory(p) for p in targets}
        # Project manifest timestamps are not installed payload.
        payload[str(project / ".opencode")].pop(".mb-manifest.json", None)
        second = invoke(case, entry, scoped=False)
        expected = [oc / "AGENTS.md", oc / "skills/memory-bank",
                    *(oc / "commands" / p.name for p in (bundle / "commands").glob("*.md"))]
        missing = [str(p) for p in expected if not saved["file_sha256"].get(str(p))]
        assert not missing, f"Missing first-install authority: {missing}; reinstall={second.returncode}\n{second.stdout}"
        for path in expected:
            assert str(path) in saved["files"]
            if not path.is_symlink():
                assert saved["file_sha256"][str(path)] == hashlib.sha256(path.read_bytes()).hexdigest()
        assert second.returncode == 0, second.stdout
        after = {str(p): inventory(p) for p in targets}
        after[str(project / ".opencode")].pop(".mb-manifest.json", None)
        assert after == payload
        assert inventory(foreign) == before
        retained = json.loads(record.read_text())
        assert retained["home"] == str(home)
        assert "opencode" in retained["extensions_installed"]
        assert "extended: true" in (project / ".opencode/plugins/memory-bank.js").read_text()
        assert (oc / "skills/memory-bank").resolve() == bundle
        if record_kind == "mixed":
            for key in ("clients", "adapters_failed", "extensions_installed", "files"):
                assert set(metadata[key]) <= set(retained[key])
            assert retained["file_sha256"][str(foreign / "user-data")] == "foreign-proof-unchanged"
    finally:
        if native is not None:
            shutil.rmtree(native)


@pytest.mark.parametrize("entry", ["shell", "cli"])
def test_user_home_symlink_refuses_without_target_writes(lab, entry):
    bundle, home, project, env = lab
    alias = home.with_name("home-alias")
    alias.symlink_to(home, target_is_directory=True)
    env = {k: v for k, v in env.items() if not k.startswith("XDG_") and k != "CODEX_HOME"}
    env["HOME"] = str(alias)
    before = inventory(home), inventory(project)
    result = invoke((bundle, alias, project, env), entry)
    assert result.returncode != 0 and "unsafe directory ancestor" in result.stdout, result.stdout
    assert (inventory(home), inventory(project)) == before


@pytest.mark.parametrize("entry", ["shell", "cli"])
@pytest.mark.parametrize("layout", ["legacy-inside-current", "current-inside-legacy", "disjoint"])
def test_legacy_quarantine_preserves_authority_with_overlapping_roots(lab, entry, layout):
    if sys.platform != "darwin":
        pytest.skip("Requires Darwin's native /var to /private/var system alias")
    bundle, _, project, original_env = lab
    env = {k: v for k, v in original_env.items() if not k.startswith("XDG_") and k != "CODEX_HOME"}
    created = subprocess.run(["/usr/bin/mktemp", "-d"], cwd=project,
                             env={k: v for k, v in env.items() if k != "TMPDIR"},
                             text=True, capture_output=True, check=True, timeout=10)
    native = Path(created.stdout.strip())
    try:
        assert str(native).startswith("/var/") and str(native.resolve()).startswith("/private/var/")
        home = native / ("owned/opencode/home" if layout == "legacy-inside-current" else "home")
        home.mkdir(parents=True)
        xdg = (home.resolve() / ".opencode/config" if layout == "current-inside-legacy" else
               native.resolve() / "owned")
        oc, legacy = xdg / "opencode", home / ".opencode"
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(xdg), MB_MANIFEST_PATH=str(home / "record.json"))
        old = legacy / "plugins/memory-bank.js"
        old.parent.mkdir(parents=True)
        old.write_text("// Memory Bank — OpenCode plugin\n"
                       "// memory-bank: managed plugin (do not remove marker line)\n"
                       "export default { id: 'memory-bank', async setup() {} };\n")
        old.chmod(0o640)
        digest = hashlib.sha256(old.read_bytes()).hexdigest()
        foreign = home / "foreign-data"
        foreign.mkdir()
        canary = foreign / "user-data"
        canary.write_text("Independent host data\n")
        before = inventory(foreign)
        record = home / "record.json"
        metadata = {"home": str(home), "project_root": str(project), "clients": ["codex"],
                    "adapters_failed": ["pi"], "backups": [], "files": [str(old)],
                    "file_sha256": {str(old): digest}}
        record.write_text(json.dumps(metadata))
        # Legacy migration belongs to the original --clients path, not --only.
        result = invoke((bundle, home, project, env), entry, "install", "--clients", "opencode", scoped=False)
        assert result.returncode == 0, result.stdout
        destinations = list((legacy / ".memory-bank-backups/plugins").glob("memory-bank.js.pre-mb-backup.*"))
        assert len(destinations) == 1 and not old.exists(), result.stdout
        dest = destinations[0]
        assert hashlib.sha256(dest.read_bytes()).hexdigest() == digest
        assert stat.S_IMODE(dest.stat().st_mode) == 0o640
        saved = json.loads(record.read_text())
        actual = {"destination_listed": str(dest) in saved["files"],
                  "destination_hash": saved["file_sha256"].get(str(dest)),
                  "old_listed": str(old) in saved["files"],
                  "old_hash": saved["file_sha256"].get(str(old))}
        assert actual == {"destination_listed": True, "destination_hash": digest,
                          "old_listed": False, "old_hash": None}, actual
        for name in ("commands/adr.md", "commands/mb.md", "AGENTS.md"):
            path = oc / name
            assert str(path) in saved["files"]
            assert saved["file_sha256"][str(path)] == hashlib.sha256(path.read_bytes()).hexdigest()
        assert inventory(foreign) == before
        assert saved["home"] == str(home)
        for key in ("clients", "adapters_failed"):
            assert set(metadata[key]) <= set(saved[key])
    finally:
        shutil.rmtree(native)


@pytest.mark.parametrize("entry", ["shell", "cli"])
@pytest.mark.parametrize("field,host", [("clients", "codex"), ("adapters_failed", "pi"),
                                       ("clients", "opencode")])
def test_recorded_project_switch_refuses_without_target_writes(lab, entry, field, host):
    _, home, project, env = lab
    prior = project.with_name("project-a")
    shutil.copytree(project, prior)
    (prior / "host-link").symlink_to(home / ".codex/user-canary")
    (prior / "AGENTS.md").chmod(0o640)
    record = home / "record.json"
    env["MB_MANIFEST_PATH"] = str(record)
    record.write_text(json.dumps({"home": str(home), "project_root": str(prior), field: [host]}))
    record.chmod(0o600)
    before = inventory(home), inventory(prior), inventory(project)
    result = invoke(lab, entry)
    after = inventory(home), inventory(prior), inventory(project)
    assert result.returncode != 0, f"{result.stdout}\nRecord after install: {record.read_text()}"
    assert after == before, result.stdout
    assert "project" in result.stdout.lower(), result.stdout
    if host != "opencode":
        assert "same project" in result.stdout.lower() and "separate" in result.stdout.lower(), result.stdout


@pytest.mark.parametrize("entry", ["shell", "cli"])
def test_empty_record_can_change_project(lab, entry):
    _, home, project, env = lab
    record = home / "record.json"
    env["MB_MANIFEST_PATH"] = str(record)
    record.write_text(json.dumps({"home": str(home), "project_root": str(project.with_name("old-project")),
                                  "clients": [], "adapters_failed": []}))
    before = preserved(lab)
    result = invoke(lab, entry)
    assert result.returncode == 0, result.stdout
    saved = json.loads(record.read_text())
    assert saved["project_root"] == str(project) and saved["clients"] == ["opencode"]
    assert (project / ".opencode/plugins/memory-bank.js").is_file()
    assert preserved(lab) == before


@pytest.mark.parametrize("entry", ["shell", "cli"])
def test_unreadable_record_refuses_without_target_writes(lab, entry):
    _, home, project, env = lab
    record = home / "record.json"
    env["MB_MANIFEST_PATH"] = str(record)
    record.write_text(json.dumps({"home": str(home), "project_root": str(project), "clients": ["codex"]}))
    before = inventory(home), inventory(project)
    record.chmod(0o000)
    try:
        result = invoke(lab, entry)
        assert stat.S_IMODE(record.stat().st_mode) == 0
    finally:
        record.chmod(before[0]["record.json"][0])
    assert result.returncode != 0, result.stdout
    assert (inventory(home), inventory(project)) == before, result.stdout


@pytest.mark.parametrize("entry", ["shell", "cli"])
def test_scoped_uninstall(lab, entry):
    _, home, project, env = lab
    record = home / "mixed-manifest.json"
    env["MB_MANIFEST_PATH"] = str(record)
    foreign = home / ".codex/user-canary"
    metadata = {"home": str(home), "project_root": str(project), "clients": ["codex"], "adapters_failed": ["pi"],
                "clients_requested": "codex", "extensions_installed": ["pi"], "language": "en",
                "files": [str(foreign)], "file_sha256": {str(foreign): "unchanged-foreign-record"},
                "backups": [f"{foreign}|{home}/.codex/absent-backup"],
                "platform_limited": ["other-host-limit"], "other_host_options": {"retain": True}}
    record.write_text(json.dumps(metadata))
    before = preserved(lab)
    result = invoke(lab, entry, "install", "--with-extensions=opencode")
    assert result.returncode == 0, result.stdout
    alias = home / "config/opencode/skills/memory-bank"
    through_alias = alias, home, project, env | {"PYTHONPATH": str(alias), "MB_SKILL_BUNDLE": str(alias)}
    result = invoke(through_alias, entry, "uninstall", "--project-root", str(project))
    assert result.returncode == 0, result.stdout
    remaining = json.loads(record.read_text())
    for key in ("clients", "adapters_failed", "clients_requested", "extensions_installed", "files", "file_sha256",
                "backups", "platform_limited", "other_host_options"):
        assert remaining[key] == metadata[key], key
    assert preserved(lab) == before
    assert not (home / "config/opencode/skills/memory-bank").is_symlink()
    assert not (project / ".opencode/plugins/memory-bank.js").exists()
    assert "User global instructions" in (home / "config/opencode/AGENTS.md").read_text()


@pytest.mark.parametrize("behavior", ["restore", "changed"])
def test_io_failure_recovery(lab, behavior):
    bundle, home, _, env = lab
    record = home / "record.json"
    env["MB_MANIFEST_PATH"] = str(record)
    result = invoke(lab)
    assert result.returncode == 0, result.stdout
    target = home / "config/opencode/commands/adr.md"
    before = target.read_bytes()
    with (bundle / "commands/adr.md").open("a") as out:
        out.write("\nNew revision\n")
    fault = home / "fault"
    fault.mkdir()
    # Reuse the existing RST10 real-permission fault fixture; no ownership mocks.
    source = (ROOT / "tests/bats/test_opencode_install_durability.bats").read_text()
    payload = source.split('cat > "$T/fault/sitecustomize.py" <<\'PY\'\n', 1)[1].split("\nPY\n", 1)[0]
    (fault / "sitecustomize.py").write_text(payload)
    result = invoke(lab, extra={"PYTHONPATH": f"{fault}:{bundle}", "FAULT_RECORD": str(record),
                               "FAULT_TARGET": str(target), "FAULT_FIRED": str(fault / "fired"),
                               "FAULT_ORIGINAL": hashlib.sha256(before).hexdigest(),
                               "FAULT_CHANGE": "1" if behavior == "changed" else ""})
    home.chmod(0o700)
    assert (fault / "fired").exists(), result.stdout
    assert result.returncode != 0
    assert "Manifest saved" not in result.stdout
    if behavior == "restore":
        assert target.read_bytes() == before
    else:
        assert "User changed this postimage" in target.read_text()
        recovery = Path(result.stdout.rsplit("recovery: ", 1)[1].splitlines()[0])
        assert (recovery / "pending.json").exists(), result.stdout


@pytest.mark.parametrize("override", [True, False])
def test_upgrade_scoped_options_reach_existing_installer(lab, override):
    bundle, home, project, env = lab
    before = preserved(lab)
    (bundle / ".git").mkdir()
    binary = home / "bin"
    binary.mkdir()
    # Git is the external process boundary; no fetch/network or repository mutation.
    git = binary / "git"
    git.write_text('#!/bin/sh\ncase "$*" in\n'
                   '  "rev-list --count HEAD.."*) echo 1;;\n'
                   '  "rev-list --count"*) echo 0;;\n'
                   '  "rev-parse --abbrev-ref HEAD") echo main;;\n'
                   '  "rev-parse"*) echo fixture;;\nesac\nexit 0\n')
    git.chmod(0o700)
    result = subprocess.run(["bash", str(bundle / "scripts/mb-upgrade.sh"), "--force",
                             "--only", "opencode", "--with-extensions=opencode", "--project-root", str(project)],
                            cwd=project, env=env | ({"MB_SKILL_DIR": str(bundle)} if override else {})
                            | {"PATH": f"{binary}:{env['PATH']}"},
                            text=True, capture_output=True, timeout=180)
    assert result.returncode == 0, result.stdout + result.stderr
    assert preserved(lab) == before
    assert "extended: true" in (project / ".opencode/plugins/memory-bank.js").read_text()


def test_legacy_corrupt_manifest_force_remains_explicit(lab):
    _, home, _, env = lab
    record = home / "record.json"
    record.write_text("invalid JSON\n")
    env["MB_MANIFEST_PATH"] = str(record)
    result = invoke(lab, "shell", "uninstall", scoped=False)
    assert result.returncode != 0
    assert record.read_text() == "invalid JSON\n"
    result = invoke(lab, "shell", "uninstall", "--force", scoped=False)
    assert result.returncode == 0, result.stdout
    assert not record.exists()


@pytest.mark.parametrize("conflict", ["model", "owners"])
def test_known_configuration_conflict_refuses_before_writes(lab, conflict):
    _, home, project, _ = lab
    if conflict == "model":
        (project / ".memory-bank/pipeline.yaml").write_text(
            "roles:\n  developer: {agent: mb-developer, model: unsupported-alias}\n")
    else:
        (project / ".mb-agents-owners.json").write_text('{"owners":"not-an-array"}\n')
    before = inventory(home), inventory(project)
    result = invoke(lab, "cli", "install", "--with-extensions=opencode")
    assert result.returncode != 0
    assert ("provider/model" if conflict == "model" else "owners") in result.stdout
    assert (inventory(home), inventory(project)) == before
