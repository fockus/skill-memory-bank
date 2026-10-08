"""Stage 5: owned opt-in Pi installation and the managed mb-pi entrypoint.

Every install runs against a temporary HOME (with spaces); the real ~/.pi is never
touched. Runtime tests use the installed public Pi SDK and a sandbox Tintin 0.19.0.
"""

import hashlib
import json
import os
import pty
import select
import shutil
import subprocess
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
PI_SH = ROOT / "adapters/pi.sh"
HELPERS = sorted(p.name for p in (ROOT / "adapters").glob("pi_native_*.mjs"))
TINTIN = "npm:@tintinweb/pi-subagents@0.19.0"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def snapshot(base):
    base = Path(base)
    out = {}
    for path in sorted(base.rglob("*")):
        if path.is_file() and not path.is_symlink():
            data = path.read_bytes()
            if path.name == ".mb-global-extensions-manifest.json":
                manifest = json.loads(data)
                manifest.pop("installed_at", None)
                data = json.dumps(manifest, sort_keys=True).encode()
            out[str(path.relative_to(base))] = hashlib.sha256(data).hexdigest()
    return out


@pytest.fixture
def box(tmp_path):
    home = tmp_path / "home with space"
    project = tmp_path / "project dir"
    project.mkdir(parents=True)
    (home / ".pi" / "agent").mkdir(parents=True)
    return home, project


def agent_dir(home):
    return home / ".pi" / "agent"


def env_for(home, extra=None):
    env = {**os.environ, "HOME": str(home), "PI_OFFLINE": "1", "MB_UPDATE_CHECK": "off"}
    for name in [
        "PI_CODING_AGENT_DIR",
        "PI_SUBAGENT_CHILD",
        "PI_SUBAGENTS_HERDR_BRIDGE",
        "MB_PI_NICO_ROOT",
        "MB_PI_TINTIN_ROOT",
    ]:
        env.pop(name, None)
    env.update(extra or {})
    return env


def pi_sh(home, project, action="install-global-extensions", extra=None):
    return subprocess.run(
        ["bash", str(PI_SH), action, str(project)],
        env=env_for(home, extra),
        text=True,
        capture_output=True,
        timeout=180,
    )


def install(home, project, extra=None):
    proc = pi_sh(home, project, extra=extra)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    return json.loads((agent_dir(home) / ".mb-global-extensions-manifest.json").read_text())


def ledger(home):
    return json.loads((agent_dir(home) / ".mb-pi-native-owned.json").read_text())


# ── installer: ownership, idempotency, removal, rollback ──────────────────────


def test_install_twice_produces_identical_owned_output(box):
    home, project = box
    install(home, project)
    first = snapshot(home)
    install(home, project)
    assert snapshot(home) == first


def test_install_records_owned_hashes_provenance_and_default_backend(box):
    home, project = box
    manifest = install(home, project)
    owned = ledger(home)["files"]
    assert owned, "ownership ledger lists nothing"
    for path, record in owned.items():
        assert Path(path).is_file(), path
        assert record["sha256"] == sha(path), path
    native = manifest["native"]
    assert native["default_backend"] == "tintin"
    assert native["tintin_package"] == TINTIN
    assert native["skill_dir"] == str(ROOT)
    assert native["entrypoint"] == str(agent_dir(home) / "bin" / "mb-pi")
    assert manifest["managed_entrypoint"] is True
    assert manifest["install_state"] == "complete"


def test_all_native_helpers_are_installed_and_their_imports_resolve(box):
    home, project = box
    install(home, project)
    ext = agent_dir(home) / "extensions"
    for name in HELPERS:
        assert (ext / name).read_bytes() == (ROOT / "adapters" / name).read_bytes(), name
    script = "for (const f of process.argv.slice(1)) await import(new URL('file://' + f).href);"
    proc = subprocess.run(
        ["node", "--input-type=module", "-e", script, *[str(ext / n) for n in HELPERS]],
        env=env_for(home),
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert proc.returncode == 0, proc.stderr


def test_generated_templates_have_empty_project_root_and_resolvable_skill_imports(box):
    home, project = box
    install(home, project)
    ext = agent_dir(home) / "extensions"
    for name in ["memory-bank-session.ts", "memory-bank-graph-rag.ts", "memory-bank-subagent.ts"]:
        text = (ext / name).read_text()
        assert "_JSON__" not in text, name
        assert f"const SKILL_DIR = {json.dumps(str(ROOT))};" in text, name
    for name in ["memory-bank-session.ts", "memory-bank-graph-rag.ts"]:
        assert 'const PROJECT_ROOT = "";' in (ext / name).read_text(), name
    assert str(project) not in (ext / "memory-bank-session.ts").read_text()
    for rel in [
        "adapters/pi_native_graph.mjs",
        "adapters/pi_native_hooks.mjs",
        "adapters/pi_native_session.mjs",
        "adapters/pi_native_argv.py",
    ]:
        assert (ROOT / rel).is_file()
    sub = (ext / "memory-bank-subagent.ts").read_text()
    for imported in ["pi_native_commands.mjs", "pi_native_backend.mjs"]:
        assert f'from "./{imported}"' in sub and (ext / imported).is_file()


def test_managed_entrypoint_is_owned_executable_and_only_new_bin_file(box):
    home, project = box
    before = {p for p in home.rglob("*")}
    install(home, project)
    entry = agent_dir(home) / "bin" / "mb-pi"
    assert entry.is_file() and os.access(entry, os.X_OK)
    assert ledger(home)["files"][str(entry)]["sha256"] == sha(entry)
    created_bins = {p for p in home.rglob("*") if p not in before and p.parent.name == "bin"}
    assert created_bins == {entry, entry.with_name("mb-pi.mjs")}
    assert not list(home.rglob("pi")), "ordinary pi executable must not be created or replaced"


def test_install_leaves_shell_rc_path_and_ordinary_pi_untouched(box):
    home, project = box
    rc = {
        name: f"export PATH=/opt/x:$PATH # {name}\n" for name in [".zshrc", ".bashrc", ".profile"]
    }
    for name, text in rc.items():
        (home / name).write_text(text)
    install(home, project)
    for name, text in rc.items():
        assert (home / name).read_text() == text
    outside = {k for k in snapshot(home) if not k.startswith(".pi/agent/")}
    assert outside == set(rc)


def test_foreign_mb_pi_refuses_before_any_write(box):
    home, project = box
    foreign = agent_dir(home) / "bin" / "mb-pi"
    foreign.parent.mkdir(parents=True)
    foreign.write_text("#!/bin/sh\necho mine\n")
    before = snapshot(home)
    proc = pi_sh(home, project)
    assert proc.returncode != 0
    assert "mb-pi" in proc.stderr and "refus" in proc.stderr.lower()
    assert snapshot(home) == before


def test_uninstall_removes_unchanged_owned_files_preserves_edits_restores_preimages(box):
    home, project = box
    ad = agent_dir(home)
    (ad / "extensions").mkdir(parents=True)
    (ad / "extensions" / "memory-bank-graph-rag.ts").write_text("// user's own graph extension\n")
    (ad / "agents").mkdir()
    (ad / "agents" / "my-agent.md").write_text("---\nname: my-agent\n---\nmine\n")
    (ad / "settings.json").write_text(
        json.dumps({"theme": "dark", "packages": ["npm:pi-subagents"]})
    )
    original_settings = (ad / "settings.json").read_text()
    install(home, project)
    edited = ad / "agents" / "mb-reviewer.md"
    edited.write_text(edited.read_text() + "\nuser note\n")
    edited_text = edited.read_text()
    owned = list(ledger(home)["files"])
    proc = pi_sh(home, project, action="uninstall-global-extensions")
    assert proc.returncode == 0, proc.stderr
    assert (
        ad / "extensions" / "memory-bank-graph-rag.ts"
    ).read_text() == "// user's own graph extension\n"
    assert (ad / "agents" / "my-agent.md").read_text() == "---\nname: my-agent\n---\nmine\n"
    assert edited.read_text() == edited_text
    assert json.loads((ad / "settings.json").read_text()) == json.loads(original_settings)
    for path in owned:
        if path not in {str(edited), str(ad / "extensions" / "memory-bank-graph-rag.ts")}:
            assert not Path(path).exists(), path
    assert not (ad / "bin" / "mb-pi").exists()
    assert not (ad / ".mb-global-extensions-manifest.json").exists()


def test_interrupted_install_declares_no_capabilities_and_stays_removable(box):
    home, project = box
    install(home, project)
    ad = agent_dir(home)
    shutil.rmtree(ad / "bin")
    (ad / "bin").write_text("not a directory")
    proc = pi_sh(home, project)
    assert proc.returncode != 0
    manifest = json.loads((ad / ".mb-global-extensions-manifest.json").read_text())
    assert manifest["install_state"] != "complete"
    assert not manifest.get("managed_entrypoint")
    assert not manifest.get("subagent_dispatch") and not manifest.get("native")
    (ad / "bin").unlink()
    assert pi_sh(home, project, action="uninstall-global-extensions").returncode == 0
    assert not (ad / "extensions" / "pi_native_work.mjs").exists()


# ── settings: additive, non-clobbering, both packages ─────────────────────────


def test_settings_update_is_additive_and_preserves_custom_agent_and_mention_config(box):
    home, project = box
    ad = agent_dir(home)
    settings = {
        "theme": "dark",
        "defaultProvider": "example",
        "packages": ["npm:pi-subagents", {"source": "npm:foo", "extensions": []}],
        "skills": ["~/my-skill"],
    }
    (ad / "settings.json").write_text(json.dumps(settings))
    (project / ".pi").mkdir()
    (project / ".pi" / "subagents.json").write_text('{"agentMentions": true}')
    (ad / "agents").mkdir()
    (ad / "agents" / "custom.md").write_text("custom\n")
    install(home, project)
    install(home, project)
    after = json.loads((ad / "settings.json").read_text())
    assert after["packages"] == [*settings["packages"], {"source": TINTIN, "extensions": []}]
    assert {k: v for k, v in after.items() if k != "packages"} == {
        k: v for k, v in settings.items() if k != "packages"
    }
    assert (project / ".pi" / "subagents.json").read_text() == '{"agentMentions": true}'
    assert (ad / "agents" / "custom.md").read_text() == "custom\n"


def test_user_owned_tintin_entry_is_left_alone_and_survives_uninstall(box):
    home, project = box
    ad = agent_dir(home)
    (ad / "settings.json").write_text(json.dumps({"packages": ["npm:@tintinweb/pi-subagents"]}))
    manifest = install(home, project)
    assert json.loads((ad / "settings.json").read_text())["packages"] == [
        "npm:@tintinweb/pi-subagents"
    ]
    assert manifest["native"]["tintin_entry"] == "preexisting"
    assert pi_sh(home, project, action="uninstall-global-extensions").returncode == 0
    assert json.loads((ad / "settings.json").read_text())["packages"] == [
        "npm:@tintinweb/pi-subagents"
    ]


def test_invalid_settings_refuse_without_overwrite(box):
    home, project = box
    ad = agent_dir(home)
    (ad / "settings.json").write_text("{ not json")
    proc = pi_sh(home, project)
    assert proc.returncode != 0
    assert (ad / "settings.json").read_text() == "{ not json"


# ── managed runtime (real public SDK, sandbox Tintin 0.19.0, no model calls) ──


def sdk_root():
    configured = os.environ.get("MB_PI_SDK_ROOT")
    if configured:
        return Path(configured)
    try:
        npm_root = subprocess.run(
            ["npm", "root", "-g"], text=True, capture_output=True, timeout=30
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None
    return Path(npm_root) / "@earendil-works/pi-coding-agent"


SDK = sdk_root()
needs_sdk = pytest.mark.skipif(
    not SDK or not (SDK / "package.json").is_file(), reason="public Pi SDK not installed"
)


@pytest.fixture(scope="session")
def tintin_store(tmp_path_factory):
    configured = os.environ.get("MB_PI_TEST_TINTIN_ROOT")
    if configured:
        return Path(configured)
    store = tmp_path_factory.mktemp("tintin") / "npm"
    proc = subprocess.run(
        [
            "npm",
            "install",
            "--prefix",
            str(store),
            "@tintinweb/pi-subagents@0.19.0",
            "--legacy-peer-deps",
            "--prefer-offline",
            "--no-audit",
            "--no-fund",
        ],
        text=True,
        capture_output=True,
        timeout=300,
    )
    if proc.returncode != 0:
        pytest.skip(f"sandbox Tintin 0.19.0 unavailable: {proc.stderr[-300:]}")
    return store / "node_modules/@tintinweb/pi-subagents"


def nico_root():
    configured = os.environ.get("MB_PI_TEST_NICO_ROOT")
    root = (
        Path(configured) if configured else Path.home() / ".pi/agent/npm/node_modules/pi-subagents"
    )
    return root if (root / "package.json").is_file() else None


def link_package(home, name, root):
    target = agent_dir(home) / "npm" / "node_modules" / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.symlink_to(root, target_is_directory=True)


@pytest.fixture
def managed(box, tintin_store):
    home, project = box
    install(home, project, extra={"MB_PI_SDK_ROOT": str(SDK)})
    link_package(home, "@tintinweb/pi-subagents", tintin_store)
    return home, project


def mb_pi(home, project, *args, extra=None, timeout=120):
    entry = agent_dir(home) / "bin" / "mb-pi"
    return subprocess.run(
        [str(entry), *args],
        cwd=project,
        env=env_for(home, extra),
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def check(home, project, *args, extra=None):
    proc = mb_pi(home, project, "--check", *args, extra=extra)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    return json.loads(proc.stdout.strip().splitlines()[-1])


@needs_sdk
def test_mb_pi_composes_one_mb_surface_with_tintin_default_and_keeps_argv(managed):
    home, project = managed
    settings_before = snapshot(agent_dir(home))
    result = check(home, project, "--", 'say "hi" now', "two  words")
    assert result["ready"] is True
    assert set(result["binding"]["components"]) == {"tintin", "mb"}
    assert result["binding"]["components"]["tintin"]["version"] == "0.19.0"
    assert result["binding"]["components"]["tintin"]["agentMentions"] == "off"
    assert result["messages"] == ['say "hi" now', "two  words"]
    assert result["cwd"] == str(project)
    assert result["agentDir"] == str(agent_dir(home))
    assert result["tools"].count("mb_dispatch_subagent") == 1
    assert "subagent" not in result["tools"]
    graph = [p for p in result["extensions"] if p.endswith("memory-bank-graph-rag.ts")]
    assert len(graph) == 1
    assert not [p for p in result["extensions"] if p.endswith("memory-bank-subagent.ts")]
    after = snapshot(agent_dir(home))
    assert {k: after.get(k) for k in settings_before} == settings_before, (
        "managed startup rewrote installed/foreign files"
    )


@needs_sdk
def test_both_packages_installed_default_run_hides_raw_nico_and_explicit_nico_loads_once(managed):
    nico = nico_root()
    if not nico:
        pytest.skip("Nico pi-subagents package not available for read-only linking")
    home, project = managed
    ad = agent_dir(home)
    settings = json.loads((ad / "settings.json").read_text())
    settings["packages"].insert(0, "npm:pi-subagents")
    (ad / "settings.json").write_text(json.dumps(settings))
    link_package(home, "pi-subagents", nico)
    default = check(home, project)
    assert set(default["binding"]["components"]) == {"tintin", "mb"}
    assert "subagent" not in default["tools"], "raw Nico delegation leaked into the managed runtime"
    assert not [p for p in default["extensions"] if "pi-subagents" in p]
    explicit = check(home, project, "--with-nico")
    assert set(explicit["binding"]["components"]) == {"tintin", "nico", "mb"}
    inventory = explicit["binding"]["inventory"]
    assert (
        inventory.count("<inline:mb-managed-nico>")
        == inventory.count("<inline:mb-managed-tintin>")
        == 1
    )
    assert not [
        p for p in explicit["extensions"] if "pi-subagents" in p and not p.startswith("<inline:")
    ]
    assert json.loads((ad / "settings.json").read_text()) == settings


@needs_sdk
def test_ordinary_sdk_discovery_does_not_load_requested_tintin(managed):
    assert SDK is not None
    home, project = managed
    script = """
const sdk = await import(process.argv[1]);
const services = await sdk.createAgentSessionServices({ cwd: process.argv[2], agentDir: process.argv[3] });
console.log(JSON.stringify(services.resourceLoader.getExtensions().extensions.map(e => e.path)));
"""
    manifest = json.loads((SDK / "package.json").read_text())
    entry = SDK / manifest["exports"]["."]["import"]
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            entry.as_uri(),
            str(project),
            str(agent_dir(home)),
        ],
        env=env_for(home),
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert proc.returncode == 0, proc.stderr
    paths = json.loads(proc.stdout.strip().splitlines()[-1])
    assert not [p for p in paths if "tintinweb" in p]
    assert [p for p in paths if p.endswith("memory-bank-subagent.ts")]


@needs_sdk
def test_mb_pi_refuses_without_installed_tintin(box):
    home, project = box
    install(home, project, extra={"MB_PI_SDK_ROOT": str(SDK)})
    proc = mb_pi(home, project, "--check")
    assert proc.returncode != 0
    assert "@tintinweb/pi-subagents" in proc.stderr


@needs_sdk
def test_mb_pi_starts_real_interactive_mode_under_pty_without_model(managed):
    home, project = managed
    entry = agent_dir(home) / "bin" / "mb-pi"
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(project)
        os.execve(str(entry), [str(entry)], {**env_for(home), "TERM": "xterm-256color"})
    output, quit_sent, deadline = b"", False, time.time() + 60
    while time.time() < deadline:
        if select.select([fd], [], [], 0.3)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
        if not quit_sent and b"mb-managed-tintin" in output:
            time.sleep(1)
            os.write(fd, b"\x04")  # Ctrl+D on an empty editor: InteractiveMode's own quit
            quit_sent = True
    else:
        os.kill(pid, 9)
    _, status = os.waitpid(pid, 0)
    os.close(fd)
    text = output.decode("utf8", "replace")
    assert quit_sent, f"InteractiveMode never listed the managed extensions: {text[-800:]}"
    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, text[-800:]
    assert "<inline:mb-managed-mb>" in text and "memory-bank-subagent.ts" not in text


@needs_sdk
def test_managed_settings_view_writes_user_changes_but_never_the_view(managed):
    assert SDK is not None
    home, project = managed
    ad = agent_dir(home)
    settings = json.loads((ad / "settings.json").read_text())
    settings["packages"].insert(0, "npm:pi-subagents")
    (ad / "settings.json").write_text(json.dumps(settings))
    script = """
const [sdkEntry, bootstrap, cwd, agentDir, owned] = process.argv.slice(1);
const sdk = await import(sdkEntry);
const { managedSettingsStorage } = await import(bootstrap);
const manager = sdk.SettingsManager.fromStorage(managedSettingsStorage(cwd, agentDir, { excludeExtensions: [owned] }));
const seen = manager.getGlobalSettings();
manager.setTheme("light");
await manager.flush();
manager.setPackages([]);
await manager.flush();
console.log(JSON.stringify({ seen, errors: manager.drainErrors().map(e => e.error.message) }));
"""
    manifest = json.loads((SDK / "package.json").read_text())
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            (SDK / manifest["exports"]["."]["import"]).as_uri(),
            (ad / "extensions" / "pi_native_bootstrap.mjs").as_uri(),
            str(project),
            str(ad),
            str(ad / "extensions" / "memory-bank-subagent.ts"),
        ],
        env=env_for(home),
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert proc.returncode == 0, proc.stderr
    result = json.loads(proc.stdout.strip().splitlines()[-1])
    assert {"source": "npm:pi-subagents", "extensions": []} in result["seen"]["packages"]
    assert "-" + str(ad / "extensions" / "memory-bank-subagent.ts") in result["seen"]["extensions"]
    assert any("refuses to persist packages" in message for message in result["errors"])
    persisted = json.loads((ad / "settings.json").read_text())
    assert persisted == {**settings, "theme": "light"}


# ── real-host regressions (Stage 5 live, 2026-10-08) ──────────────────────────


def test_mb_pi_runs_under_commonjs_agent_dir_package_json_and_through_a_symlink(box):
    home, project = box
    ad = agent_dir(home)
    (ad / "package.json").write_text('{"type":"commonjs"}\n')
    install(home, project)
    link = home / "my bin" / "mbpi"
    link.parent.mkdir()
    link.symlink_to(ad / "bin" / "mb-pi")
    for launcher in [ad / "bin" / "mb-pi", link]:
        proc = subprocess.run(
            [str(launcher), "--help"],
            cwd=project,
            env=env_for(home),
            text=True,
            capture_output=True,
            timeout=60,
        )
        assert proc.returncode == 0, proc.stderr
        assert "Usage: mb-pi" in proc.stdout


def test_foreign_mb_pi_module_refuses_and_uninstall_removes_both_launcher_files(box):
    home, project = box
    ad = agent_dir(home)
    install(home, project)
    pi_sh(home, project, action="uninstall-global-extensions")
    assert not (ad / "bin").exists()
    module = ad / "bin" / "mb-pi.mjs"
    module.parent.mkdir()
    module.write_text("console.log('mine')\n")
    before = snapshot(home)
    proc = pi_sh(home, project)
    assert proc.returncode != 0 and "refus" in proc.stderr.lower()
    assert snapshot(home) == before


def sdk_extension_load(home, project):
    assert SDK is not None
    script = """
const sdk = await import(process.argv[1]);
new sdk.ProjectTrustStore(process.argv[3]).set(process.argv[2], true);
const services = await sdk.createAgentSessionServices({ cwd: process.argv[2], agentDir: process.argv[3] });
const loaded = services.resourceLoader.getExtensions();
console.log(JSON.stringify({
  errors: loaded.errors.map(e => e.error),
  tools: loaded.extensions.map(e => [e.path, [...e.tools.keys()]]),
}));
"""
    manifest = json.loads((SDK / "package.json").read_text())
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            (SDK / manifest["exports"]["."]["import"]).as_uri(),
            str(project),
            str(agent_dir(home)),
        ],
        env=env_for(home),
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip().splitlines()[-1])


@needs_sdk
def test_project_graph_rag_copy_yields_to_the_global_install_without_tool_conflict(box):
    home, project = box
    proc = pi_sh(home, project, action="install")
    assert proc.returncode == 0, proc.stderr
    assert (project / ".pi/extensions/memory-bank-graph-rag.ts").is_file()
    install(home, project)
    result = sdk_extension_load(home, project)
    assert not [e for e in result["errors"] if "conflicts" in e], result["errors"]
    owners = [path for path, tools in result["tools"] if "code_context" in tools]
    assert owners == [str(agent_dir(home) / "extensions/memory-bank-graph-rag.ts")]


def managed_layout(home, version="1.1.0-test"):
    assert SDK is not None
    install_root = agent_dir(home) / "install"
    release = install_root / "releases" / version
    release.mkdir(parents=True)
    # The SDK's node_modules holds its siblings (jiti, typebox), as in a real release.
    (release / "node_modules").symlink_to(SDK.parents[1], target_is_directory=True)
    (install_root / "current-version").write_text(version + "\n")


def env_without_pi(home, extra=None):
    env = env_for(home)
    env.pop("MB_PI_SDK_ROOT", None)
    node = shutil.which("node")
    assert node is not None
    env["PATH"] = f"{Path(node).parent}:/usr/bin:/bin"
    return {**env, **(extra or {})}


@needs_sdk
def test_mb_pi_finds_the_sdk_of_a_managed_pi_install_without_pi_on_path(managed):
    assert SDK is not None
    home, project = managed
    managed_layout(home)
    proc = subprocess.run(
        [str(agent_dir(home) / "bin" / "mb-pi"), "--check"],
        cwd=project,
        env=env_without_pi(home),
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert proc.returncode == 0, proc.stderr
    report = json.loads(proc.stdout.strip().splitlines()[-1])
    assert report["ready"] is True
    assert report["sdkVersion"] == json.loads((SDK / "package.json").read_text())["version"]


@needs_sdk
def test_explicit_sdk_root_wins_over_the_managed_install(managed, tmp_path):
    home, project = managed
    managed_layout(home)
    bogus = tmp_path / "no sdk here"
    proc = subprocess.run(
        [str(agent_dir(home) / "bin" / "mb-pi"), "--check"],
        cwd=project,
        env=env_without_pi(home, {"MB_PI_SDK_ROOT": str(bogus)}),
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert proc.returncode != 0
    assert str(bogus) in proc.stderr


def test_mb_pi_invalid_sdk_manifest_reports_the_exact_path(box, tmp_path):
    home, project = box
    install(home, project)
    bogus = tmp_path / "broken sdk"
    bogus.mkdir()
    manifest = bogus / "package.json"
    manifest.write_text("{broken")
    proc = subprocess.run(
        [str(agent_dir(home) / "bin" / "mb-pi"), "--check"],
        env=env_for(home, {"MB_PI_SDK_ROOT": str(bogus)}),
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert proc.returncode != 0
    assert "Invalid Pi package manifest" in proc.stderr
    assert str(manifest) in proc.stderr


def test_mb_pi_runs_under_the_node_that_pi_installed(box, tmp_path):
    home, project = box
    install(home, project)
    data = tmp_path / "xdg data"
    pi_node = data / "pi-node" / "current" / "bin"
    pi_node.mkdir(parents=True)
    marker = tmp_path / "pi-node-used"
    (pi_node / "node").write_text(
        f'#!/bin/sh\ntouch "{marker}"\nexec "{shutil.which("node")}" "$@"\n'
    )
    (pi_node / "node").chmod(0o755)
    proc = subprocess.run(
        [str(agent_dir(home) / "bin" / "mb-pi"), "--help"],
        cwd=project,
        env=env_for(home, {"XDG_DATA_HOME": str(data)}),
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert proc.returncode == 0, proc.stderr
    assert marker.exists()
