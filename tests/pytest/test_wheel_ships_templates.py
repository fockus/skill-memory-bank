"""Contract: the built wheel + sdist must ship the template bundles.

Regression guard (C-1): `pyproject.toml` shared-data listed adapters/agents/...
but NOT `templates/` nor `flow-templates/`. On pipx/pip installs the bundle tree
therefore had no `templates/locales/<lang>/.memory-bank/`, and `mb-init-bank.sh`
aborted with exit 3 ("missing template bundle"). These tests inspect the actual
packaged artifacts (not the repo tree), so the class of "works from git, broken
from wheel" bugs is caught.
"""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tarfile
import textwrap
import venv
import zipfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

# Path prefix hatch uses for shared-data files inside a wheel.
WHEEL_DATA_PREFIX = "share/memory-bank-skill"


@pytest.fixture(scope="module")
def built_dists(tmp_path_factory: pytest.TempPathFactory) -> tuple[Path, Path]:
    """Build wheel + sdist once and return (wheel_path, sdist_path)."""
    if importlib.util.find_spec("hatchling") is None:
        pytest.fail("Offline hatchling backend required; supply existing backend dependencies without downloading")
    outdir = tmp_path_factory.mktemp("dist")
    result = subprocess.run(
        [sys.executable, "-c", "import sys; import hatchling.build as b; "
         "print(b.build_wheel(sys.argv[1])); print(b.build_sdist(sys.argv[1]))", str(outdir)],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    (outdir / "build.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    assert result.returncode == 0, result.stdout + result.stderr
    wheels = list(outdir.glob("*.whl"))
    sdists = list(outdir.glob("*.tar.gz"))
    assert wheels, "wheel not produced"
    assert sdists, "sdist not produced"
    return wheels[0], sdists[0]


def _wheel_names(wheel: Path) -> list[str]:
    with zipfile.ZipFile(wheel) as zf:
        return zf.namelist()


def _sdist_names(sdist: Path) -> list[str]:
    with tarfile.open(sdist, "r:gz") as tf:
        return tf.getnames()


def test_wheel_ships_templates_locales(built_dists: tuple[Path, Path]) -> None:
    wheel, _ = built_dists
    names = _wheel_names(wheel)
    # Every supported locale must carry its .memory-bank/status.md into the wheel.
    for lang in ("en", "ru", "es", "pt", "zh"):
        needle = f"{WHEEL_DATA_PREFIX}/templates/locales/{lang}/.memory-bank/status.md"
        assert any(n.endswith(needle) for n in names), (
            f"wheel is missing {needle}; templates not packaged as shared-data"
        )


def test_wheel_ships_flow_templates(built_dists: tuple[Path, Path]) -> None:
    wheel, _ = built_dists
    names = _wheel_names(wheel)
    patterns_needle = f"{WHEEL_DATA_PREFIX}/flow-templates/patterns/"
    assert any(patterns_needle in n for n in names), (
        "wheel is missing flow-templates/patterns/; flow-routing templates absent on pipx"
    )
    route_needle = f"{WHEEL_DATA_PREFIX}/flow-templates/code-change.md"
    assert any(n.endswith(route_needle) for n in names), (
        "wheel is missing flow-templates route templates"
    )


def test_sdist_ships_templates(built_dists: tuple[Path, Path]) -> None:
    _, sdist = built_dists
    names = _sdist_names(sdist)
    assert any(n.endswith("templates/locales/en/.memory-bank/status.md") for n in names), (
        "sdist is missing templates/"
    )
    assert any(n.endswith("flow-templates/patterns/tournament.md") for n in names), (
        "sdist is missing flow-templates/"
    )


def test_installed_rules_assets(built_dists: tuple[Path, Path], tmp_path: Path) -> None:
    wheel, _ = built_dists
    prefix, cwd, home = (tmp_path / name for name in ("prefix", "empty", "home"))
    cwd.mkdir()
    home.mkdir()
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("MB_", "XDG_", "PYTHON")) and k != "CODEX_HOME"}
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / "config"),
               XDG_DATA_HOME=str(home / "data"), XDG_CACHE_HOME=str(home / "cache"),
               XDG_STATE_HOME=str(home / "state"), PYTHONDONTWRITEBYTECODE="1",
               PIP_NO_INDEX="1", PIP_DISABLE_PIP_VERSION_CHECK="1")

    def run(*args: str) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True,
                                timeout=120, check=False)
        log = tmp_path / f"command-{len(list(tmp_path.glob('command-*.json')))}.json"
        log.write_text(json.dumps({"argv": args, "exit": result.returncode,
                                   "stdout": result.stdout, "stderr": result.stderr}), encoding="utf-8")
        assert result.returncode == 0, result.stdout + result.stderr
        return result

    run(sys.executable, "-m", "venv", "--without-pip", str(prefix))
    python = prefix / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    run(sys.executable, "-m", "pip", "--python", str(python), "install", "--no-deps", "--no-index",
        "--no-cache-dir", "--no-compile", str(wheel))
    bundle = prefix / WHEEL_DATA_PREFIX
    origins = run(str(python), "-I", "-c", textwrap.dedent("""\
        import json, sys
        from pathlib import Path
        from memory_bank_skill import key_rules, quality
        from memory_bank_skill._bundle import find_bundle_root
        prefix, checkout = map(Path, sys.argv[1:])
        assert Path(sys.prefix) == prefix
        assert find_bundle_root() == prefix / "share/memory-bank-skill"
        assert all(Path(m.__file__).is_relative_to(prefix) for m in (key_rules, quality))
        assert str(checkout) not in sys.path
        print(json.dumps({"key_rules": key_rules.__file__, "quality": quality.__file__,
                          "bundle": str(find_bundle_root()), "sys_path": sys.path}))
        """), str(prefix), str(REPO_ROOT))
    assert json.loads(origins.stdout)["bundle"] == str(bundle)
    resolved = json.loads(run(str(python), "-I", "-m", "memory_bank_skill.key_rules", "resolve", "--json").stdout)
    architecture = [r["text"].split(":", 1)[0] for r in resolved["rules"] if r["id"] == "architecture"]
    assert architecture == ["Clean Architecture", "FSD (frontend)", "DDD folders"]
    assert any(r["locked"] for r in resolved["rules"])
    env["MB_PYTHON"] = str(python)
    block = run("bash", str(bundle / "scripts/mb-rules.sh"), "render", "--target=global", "--host=opencode").stdout
    assert block.startswith("<!-- mb-key-rules:start -->\n")
    assert "Clean Architecture:" in block and "DDD folders:" in block
    assert f"Details: `{home}/config/opencode/skills/memory-bank/rules/RULES.md`." in block
    assert block.endswith("<!-- mb-key-rules:end -->\n")
    assert list(cwd.iterdir()) == []


@pytest.mark.parametrize("selected", ["override", "prefix", "checkout"])
def test_rules_assets_follow_bundle_precedence_without_mixing(
    selected: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from memory_bank_skill import _bundle, key_rules, quality

    roots = {"override": tmp_path / "override", "prefix": tmp_path / WHEEL_DATA_PREFIX,
             "checkout": tmp_path / "checkout"}
    monkeypatch.setattr(sys, "prefix", str(tmp_path))
    monkeypatch.setattr(_bundle, "__file__", str(roots["checkout"] / "memory_bank_skill/_bundle.py"))
    monkeypatch.setenv("MB_SKILL_BUNDLE", str(roots["override"]))
    for name, root in roots.items():
        root.mkdir(parents=True)
        (root / "install.sh").touch()
        for asset in ("rules/key-rules.json", "references/rules-presets/architecture/clean.json"):
            path = root / asset
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({"selected": name}), encoding="utf-8")
    for name in roots:
        if name == selected:
            break
        (roots[name] / "install.sh").unlink()
    assert key_rules.load_catalog() == {"selected": selected}
    assert quality.load_architecture_preset("clean") == {"selected": selected}
    for asset, load in (("rules/key-rules.json", key_rules.load_catalog),
                        ("references/rules-presets/architecture/clean.json",
                         lambda: quality.load_architecture_preset("clean"))):
        path = roots[selected] / asset
        path.unlink()
        with pytest.raises(FileNotFoundError) as exc:
            load()
        assert exc.value.filename == str(path)


def test_explicit_catalog_does_not_require_default_bundle(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    from memory_bank_skill import _bundle, key_rules, quality

    monkeypatch.setattr(sys, "prefix", str(tmp_path / "absent-prefix"))
    monkeypatch.setattr(_bundle, "__file__", str(tmp_path / "absent-checkout/memory_bank_skill/_bundle.py"))
    monkeypatch.setenv("MB_SKILL_BUNDLE", str(tmp_path / "absent-override"))
    catalog = tmp_path / "explicit.json"
    catalog.write_text('{"rules": []}', encoding="utf-8")
    assert key_rules.load_catalog(catalog) == {"rules": []}
    assert quality.validate_settings({"architecture": "clean"}) == []
    catalog.write_text("invalid JSON", encoding="utf-8")
    with pytest.raises(json.JSONDecodeError):
        key_rules.load_catalog(catalog)
    with pytest.raises(FileNotFoundError):
        key_rules.load_catalog()


@pytest.mark.parametrize("entry", ["cli", "shell", "checkout"])
def test_opencode_uses_package_interpreter_for_installed_roles(built_dists, tmp_path, entry):
    import yaml

    wheel, _ = built_dists
    prefix, ambient, home, project = (tmp_path / name for name in ("prefix", "ambient", "home", "project"))
    home.mkdir()
    project.mkdir()
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("MB_", "XDG_", "PYTHON")) and k != "CODEX_HOME"}
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / "config"),
               PYTHONDONTWRITEBYTECODE="1", PIP_NO_INDEX="1", PIP_DISABLE_PIP_VERSION_CHECK="1",
               MB_SKIP_DEPS_CHECK="1", MB_USER_RULES_AUTO_PROMPT="off")

    def run(*args):
        result = subprocess.run(args, cwd=project, env=env, capture_output=True, text=True, timeout=300)
        log = tmp_path / f"routing-{len(list(tmp_path.glob('routing-*.json')))}.json"
        log.write_text(json.dumps({"argv": args, "exit": result.returncode,
                                   "stdout": result.stdout, "stderr": result.stderr}))
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout

    for root in (prefix, ambient):
        venv.EnvBuilder(with_pip=False).create(root)
        python = root / "bin/python"
        site = Path(run(str(python), "-c", "import sysconfig; print(sysconfig.get_path('purelib'))").strip())
        # Reuse the test environment's optional parser, without installing or downloading dependencies.
        (site / "yaml").symlink_to(Path(yaml.__file__).parent, target_is_directory=True)
    python = prefix / "bin/python"
    run(sys.executable, "-m", "pip", "--python", str(python), "install", "--no-deps", "--no-index",
        "--no-cache-dir", "--no-compile", str(wheel))
    env["PATH"] = f"{ambient / 'bin'}:{env['PATH']}"
    run("python3", "-c", "import importlib.util, yaml; assert importlib.util.find_spec('memory_bank_skill') is None")
    bundle = prefix / WHEEL_DATA_PREFIX
    assert not (bundle / "memory_bank_skill").exists()
    run(str(python), "-I", "-c", "import memory_bank_skill, sys; "
        "from pathlib import Path; assert Path(memory_bank_skill.__file__).is_relative_to(sys.prefix)")
    if entry == "checkout":
        checkout = tmp_path / "checkout"
        shutil.copytree(bundle, checkout)
        shutil.copytree(REPO_ROOT / "memory_bank_skill", checkout / "memory_bank_skill")
        bundle = checkout
    elif entry == "shell":
        env["MB_PYTHON"] = str(python)
    command = ([str(prefix / "bin/memory-bank"), "install"] if entry == "cli" else
               ["bash", str(bundle / "install.sh")])
    pipeline = project / ".memory-bank/pipeline.yaml"
    pipeline.parent.mkdir()
    pipeline.write_text("roles:\n  developer: {agent: mb-developer, model: test/original}\n")
    run(*command, "--only", "opencode", "--non-interactive", "--with-extensions=opencode",
        "--project-root", str(project))
    role = project / ".opencode/agent/mb-developer.md"
    assert "model: test/original" in role.read_text()
    assert "mode: subagent" in (home / "config/opencode/agent/mb-developer.md").read_text()
    assert "extended: true" in (project / ".opencode/plugins/memory-bank.js").read_text()
    pipeline.write_text("roles:\n  developer: {agent: mb-developer, model: test/updated}\n")
    if entry == "cli":
        env["MB_PYTHON"] = str(python)
    run("bash", str(bundle / "adapters/opencode.sh"), "render-agents", str(project), str(pipeline))
    assert "model: test/updated" in role.read_text()
    uninstall = ([str(prefix / "bin/memory-bank"), "uninstall"] if entry == "cli" else
                 ["bash", str(bundle / "uninstall.sh")])
    run(*uninstall, "--only", "opencode", "--non-interactive", "--project-root", str(project))
    assert not role.exists()
