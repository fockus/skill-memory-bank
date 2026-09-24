"""scripts/mb-language.py — per-project language override as a managed block in AGENTS.md + CLAUDE.md."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-language.py"
START = "<!-- mb-language:start -->"


def _run(project: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SCRIPT), *args, "--project", str(project)],
                          capture_output=True, text=True, check=False)


def test_set_writes_the_block_at_the_top_of_both_instruction_files(tmp_path: Path) -> None:
    (tmp_path / "AGENTS.md").write_text("# Project\n\nUser rules.\n", encoding="utf-8")

    r = _run(tmp_path, "set", "ru", "--comments", "en")

    assert r.returncode == 0, r.stderr
    agents = (tmp_path / "AGENTS.md").read_text(encoding="utf-8")
    claude = (tmp_path / "CLAUDE.md").read_text(encoding="utf-8")
    assert agents.startswith(START)
    assert "respond in Russian; write code comments in English" in agents
    assert "overrides the global Memory Bank language rule" in agents
    assert agents.endswith("# Project\n\nUser rules.\n")
    assert claude.startswith(START) and "respond in Russian" in claude


def test_set_twice_replaces_the_block_instead_of_stacking(tmp_path: Path) -> None:
    (tmp_path / "AGENTS.md").write_text("# Project\n", encoding="utf-8")
    _run(tmp_path, "set", "ru")
    _run(tmp_path, "set", "zh")

    agents = (tmp_path / "AGENTS.md").read_text(encoding="utf-8")
    assert agents.count(START) == 1
    assert "Chinese (Simplified)" in agents and "Russian" not in agents
    assert agents.endswith("# Project\n")


def test_symlinked_claude_md_gets_one_block(tmp_path: Path) -> None:
    (tmp_path / "AGENTS.md").write_text("# Project\n", encoding="utf-8")
    (tmp_path / "CLAUDE.md").symlink_to("AGENTS.md")

    _run(tmp_path, "set", "es")

    assert (tmp_path / "CLAUDE.md").is_symlink()
    assert (tmp_path / "AGENTS.md").read_text(encoding="utf-8").count(START) == 1


def test_clear_restores_user_content_and_removes_files_it_created(tmp_path: Path) -> None:
    original = "# Project\n\nUser rules.\n"
    (tmp_path / "AGENTS.md").write_text(original, encoding="utf-8")
    _run(tmp_path, "set", "pt")

    r = _run(tmp_path, "clear")

    assert r.returncode == 0, r.stderr
    assert (tmp_path / "AGENTS.md").read_text(encoding="utf-8") == original
    assert not (tmp_path / "CLAUDE.md").exists()


def test_show_reports_the_override_or_the_global_default(tmp_path: Path) -> None:
    assert "global" in _run(tmp_path, "show").stdout
    _run(tmp_path, "set", "ru")
    assert "respond in Russian" in _run(tmp_path, "show").stdout


@pytest.mark.parametrize("bad", ["de", "EN", ""])
def test_set_rejects_an_unsupported_language(tmp_path: Path, bad: str) -> None:
    r = _run(tmp_path, "set", bad)
    assert r.returncode != 0
    assert not (tmp_path / "AGENTS.md").exists()


def test_global_localization_leaves_the_project_block_alone() -> None:
    from memory_bank_skill._texttools import localize_language_text, resolve_language_strings

    sys.path.insert(0, str(SCRIPT.parent))
    import importlib.util

    spec = importlib.util.spec_from_file_location("mb_language", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    project_block = mod.block("ru")
    en = resolve_language_strings("en")
    out = localize_language_text(project_block, rule_full=en.rule_full, rule_short=en.rule_short,
                                 comments_language=en.comments_language)
    assert out == project_block
