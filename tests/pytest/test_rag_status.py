"""Public RAG status and project identity, exercised from an unrelated Git checkout."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
MODEL = "Qwen3-Embedding-0.6B-Q8_0.gguf"


@pytest.fixture(name="project")
def git_project_fixture(tmp_path, monkeypatch):
    repo = tmp_path / "sample"
    subprocess.run(["git", "init", "-q", repo], check=True)
    (repo / "src").mkdir()
    (repo / "src" / "orders.py").write_text("def calculate_discount(): return 42\n")
    subprocess.run(["git", "-C", repo, "add", "src"], check=True)
    for name, path in {
        "HOME": tmp_path / "home",
        "MB_SKILL_BUNDLE": ROOT,
        "XDG_STATE_HOME": tmp_path / "state",
        "XDG_CACHE_HOME": tmp_path / "cache",
        "PYTHONPATH": ROOT,
    }.items():
        monkeypatch.setenv(name, str(path))
    monkeypatch.setenv("PYTHONDONTWRITEBYTECODE", "1")
    monkeypatch.delenv("MB_PATH", raising=False)
    monkeypatch.delenv("MB_AGENT", raising=False)
    return repo


def cli(cwd, *args):
    result = subprocess.run(
        [sys.executable, "-m", "memory_bank_skill", "rag", *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def status(cwd, *args):
    return json.loads(cli(cwd, "status", "--json", *args))


def snapshot(tree):
    return {p.relative_to(tree): p.stat().st_mtime_ns for p in tree.rglob("*")}


def test_new_project_offers_both_models_without_writes(tmp_path, project):
    before = snapshot(tmp_path)
    result = status(project / "src")
    assert result["status"] == "unconfigured"
    assert result["action"] == "memory-bank rag init"
    assert status(project, "--auto-refresh") == result
    human = cli(tmp_path, "status", "--project-root", str(project))
    assert all(word in human for word in ("qwen3", "perplexity", "memory-bank rag init"))
    assert snapshot(tmp_path) == before


@pytest.mark.parametrize("git", [True, False])
def test_no_git_or_no_tracked_source_has_no_offer(tmp_path, git):
    if git:
        subprocess.run(["git", "init", "-q", tmp_path], check=True)
        (tmp_path / "README.md").write_text("Not source")
        subprocess.run(["git", "-C", tmp_path, "add", "README.md"], check=True)
    (tmp_path / "untracked.py").write_text("not enrolled")
    before = snapshot(tmp_path)
    with pytest.MonkeyPatch.context() as env:
        env.setenv("PYTHONPATH", str(ROOT))
        env.setenv("MB_SKILL_BUNDLE", str(ROOT))
        result = status(tmp_path)
    assert result["status"] == "not_applicable" and not result.get("action")
    assert snapshot(tmp_path) == before


@pytest.fixture(name="offline_qmd")
def offline_qmd_fixture(tmp_path, project, monkeypatch):
    # Same magic as the pinned GGUF; scale its length and digest down for offline tests.
    scripts = tmp_path / "bundle" / "scripts"
    scripts.mkdir(parents=True)
    (scripts.parent / "install.sh").touch()
    for name in ("mb-rag.py", "_lib.sh", "_mb_skill_python.py", "mb_project_rag.py",
                 "mb_project_rag_corpus.py", "mb_rag_qmd.py", "mb_rag_refresh.py", "mb_rag_storage.py",
                 "mb_rag_diagnosis.py"):
        shutil.copy(ROOT / "scripts" / name, scripts)
    weights = b"GGUFoffline fixture"
    shim = scripts / "mb_rag_qmd.py"
    with shim.open("a") as overrides:
        overrides.write(f"\n_SHA256 = {hashlib.sha256(weights).hexdigest()!r}\n")
        overrides.write(f"_MODEL_BYTES = {len(weights)}\n")
    qmd = tmp_path / "qmd"
    bin_dir = qmd / "bin"
    bin_dir.mkdir(parents=True)
    (qmd / "package.json").write_text('{"name":"@tobilu/qmd","version":"2.8.3"}')
    (bin_dir / "qmd").touch(mode=0o700)
    node = bin_dir / "node"
    node.write_text(
        f"#!{sys.executable}\n"
        "import json, sqlite3, sys\n"
        "_, _, _, action, db, _ = sys.argv\n"
        f"with open({str(tmp_path / 'provider-calls')!r}, 'a') as log: print(action, file=log)\n"
        "data = json.load(sys.stdin)\n"
        "with sqlite3.connect(db) as conn:\n"
        "    if action == 'build':\n"
        "        conn.execute('create table docs (id, text)')\n"
        "        conn.executemany('insert into docs values (?,?)', data)\n"
        "    elif action == 'refresh':\n"
        "        conn.execute('delete from docs')\n"
        "        conn.executemany('insert into docs values (?,?)', data['docs'])\n"
        "        print('true')\n"
        "    else:\n"
        "        rows = conn.execute('select id from docs where instr(text,?) limit ?', "
        "(data['query'],data['k']))\n"
        "        print(json.dumps([r[0] for r in rows]))\n"
    )
    node.chmod(0o700)
    cache = Path(os.environ["XDG_CACHE_HOME"]) / "qmd/models"
    cache.mkdir(parents=True)
    (cache / ("hf_Qwen_" + MODEL)).write_bytes(weights)
    monkeypatch.setenv("MB_SKILL_BUNDLE", str(scripts.parent))
    monkeypatch.setenv("PATH", str(bin_dir) + os.pathsep + os.environ["PATH"])
    return scripts


@pytest.mark.parametrize("bank_mode", ["local", "MB_PATH", "relative_env", "registry"])
def test_subdir_init_update_status_and_actual_lookup_share_a_key(
    tmp_path, project, offline_qmd, monkeypatch, bank_mode
):
    bank = tmp_path / "external bank" if bank_mode != "local" else project / ".memory-bank"
    if bank_mode == "MB_PATH":
        monkeypatch.setenv("MB_PATH", str(bank))
    elif bank_mode == "relative_env":
        monkeypatch.setenv("MB_PATH", "../external bank")
    elif bank_mode == "registry":
        monkeypatch.setenv("MB_AGENT", "pi")
        registry = Path.home() / ".pi/agent/memory-bank/registry.json"
        registry.parent.mkdir(parents=True)
        registry.write_text(json.dumps({"projects": {str(project): {"bank_path": str(bank)}}}))
    cli(project / "src", "init", "--model", "qwen3")
    before = snapshot(tmp_path)
    result = status(tmp_path, "--project-root", str(project), "--mb-path", str(bank))
    assert result["status"] == "ready" and result["model"] == "qwen3"
    assert status(project, "--auto-refresh") == result
    assert snapshot(tmp_path) == before

    lookup = subprocess.run(
        [
            sys.executable,
            "-c",
            "from mb_project_rag import candidates; import json; "
            "from pathlib import Path; import sys; "
            "print(json.dumps(candidates(Path.cwd(), Path(sys.argv[1]), 'calculate_discount')))",
            str(bank),
        ],
        cwd=project,
        env={**os.environ, "PYTHONPATH": os.pathsep.join(map(str, (offline_qmd, ROOT)))},
        text=True,
        capture_output=True,
        check=True,
    )
    assert json.loads(lookup.stdout) == [{"file": "src/orders.py", "line": 1, "end_line": 1}]
    (project / "src/orders.py").write_text("def reduce_price(): return 21\n")
    stale = status(project / "src")
    assert stale["status"] == "stale" and stale["action"] == "memory-bank rag update"
    cli(project / "src", "update")
    assert status(project)["status"] == "ready"
    assert not bank.exists() and not (project / ".memory-bank").exists()


@pytest.mark.parametrize(
    ("asset", "action"),
    [
        ("code.sqlite", "memory-bank rag update"),
        ("rows.json", "memory-bank rag update"),
        (MODEL, "memory-bank rag init --model qwen3"),
        ("current.json", "memory-bank rag init"),
    ],
)
def test_damaged_publication_names_the_repair_without_performing_it(
    tmp_path, project, offline_qmd, asset, action
):
    cli(project, "init", "--model", "qwen3")
    (path,) = tmp_path.rglob(asset)
    if asset == "current.json":
        path.write_bytes(b"[broken")
    else:
        path.unlink()
    before = snapshot(tmp_path)
    result = status(project)
    assert result["status"] == "broken" and result["action"] == action
    assert status(project, "--auto-refresh") == result
    assert snapshot(tmp_path) == before


def test_unsafe_store_does_not_suggest_rebuilding(project, offline_qmd):
    cli(project, "init", "--model", "qwen3")
    state = Path(os.environ["XDG_STATE_HOME"]) / "memory-bank-project-rag"
    state.chmod(0o755)
    result = status(project)
    assert result["status"] == "broken" and not result.get("action")


@pytest.mark.parametrize("damage", ["one_byte", "truncated_after_magic", "wrong_magic"])
def test_damaged_qwen3_weights_require_init_without_writes(project, offline_qmd, tmp_path, damage):
    cli(project, "init", "--model", "qwen3")
    assert status(project)["status"] == "ready"
    (path,) = tmp_path.rglob(MODEL)
    with path.open("r+b") as weights:
        if damage == "wrong_magic":
            weights.write(b"NOPE")  # Keep the pinned length.
        else:
            weights.truncate(1 if damage == "one_byte" else 4)
    before = snapshot(tmp_path)
    result = status(project)
    assert result["status"] == "broken" and result["action"] == "memory-bank rag init --model qwen3"
    assert snapshot(tmp_path) == before


def test_truncated_row_map_requires_update(project, offline_qmd, tmp_path):
    cli(project, "init", "--model", "qwen3")
    (rows,) = tmp_path.rglob("rows.json")
    rows.write_bytes(b'[["truncated')
    result = status(project)
    assert result["status"] == "broken" and result["action"] == "memory-bank rag update"


def test_invalid_system_qmd_is_not_reported_as_a_rebuild(project, offline_qmd, tmp_path):
    cli(project, "init", "--model", "qwen3")
    (tmp_path / "qmd/package.json").write_text("[]")
    result = status(project)
    assert result["status"] == "broken" and not result.get("action")


def test_missing_bundled_provider_cannot_be_replaced_by_another_checkout(
    project, offline_qmd, monkeypatch
):
    cli(project, "init", "--model", "qwen3")
    (offline_qmd / "mb_rag_qmd.py").unlink()
    monkeypatch.setenv("PYTHONPATH", os.pathsep.join(map(str, (ROOT, ROOT / "scripts"))))
    result = status(project)
    assert result["status"] == "broken" and not result.get("action")


@pytest.fixture(name="offline_pplx")
def offline_pplx_fixture(project: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.syspath_prepend(str(ROOT / "scripts"))
    import mb_project_rag as rag
    import mb_rag_pplx as pplx

    def prepare(cache: Path):
        for relative in (
            *[f"{pplx._MODEL}/{name}" for name in pplx._FILES],
            "pplx-venv/pyvenv.cfg",
            "pplx-venv/bin/python",
        ):
            file = cache / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b"offline")
        (cache / "pplx-venv/bin/python").chmod(0o700)

    def build(index: Path, docs: list[tuple[str, str]], cache: Path):
        (index / "pplx-ids.json").write_text(json.dumps([key for key, _ in docs]))
        (index / "pplx.npy").write_bytes(b"\x93NUMPY" + b"fixture")

    monkeypatch.setattr(pplx, "prepare", prepare)
    monkeypatch.setattr(pplx, "build", build)
    rag.setup(project, project / ".memory-bank", "perplexity")
    return build


@pytest.mark.parametrize(("remove", "action"), [
    ("pplx.npy", "memory-bank rag update"), ("pplx-ids.json", "memory-bank rag update"),
    ("model_q4.onnx_data", "memory-bank rag init --model perplexity"),
    ("pyvenv.cfg", "memory-bank rag init --model perplexity"),
])
def test_perplexity_status_checks_selected_generation_and_private_runtime(
    tmp_path: Path, project: Path, offline_pplx, remove: str, action: str
):
    assert status(project)["status"] == "ready"
    (path,) = tmp_path.rglob(remove)
    path.unlink()
    before = snapshot(tmp_path)
    result = status(project)
    assert result["status"] == "broken" and result["action"] == action
    assert snapshot(tmp_path) == before
