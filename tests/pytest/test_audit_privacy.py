"""R06/R07/R08: search and index must hide private spans without hiding public text.

Contracts under test are the existing search and index CLIs. Fixtures pair private
markers with visible evidence, including boundaries on the same and different lines.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SEARCH = ROOT / "scripts" / "mb-search.sh"
INDEX = ROOT / "scripts" / "mb-index-json.py"


@pytest.fixture
def bank(tmp_path: Path) -> Path:
    path = tmp_path / "project with spaces" / ".memory-bank"
    (path / "notes").mkdir(parents=True)
    return path


def _note(bank: Path, body: str) -> None:
    (bank / "notes" / "audit.md").write_text(
        "---\ntype: note\ntags: [audit]\n---\n" + body, encoding="utf-8"
    )


def _search(bank: Path, *args: str, reveal_env: bool = False) -> subprocess.CompletedProcess:
    env = {**os.environ, "MB_SHOW_PRIVATE": "1" if reveal_env else "0"}
    return subprocess.run(
        ["bash", str(SEARCH), *args, str(bank)],
        cwd=bank.parent,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _index(bank: Path) -> dict:
    result = subprocess.run(
        [sys.executable, str(INDEX), str(bank)],
        cwd=bank.parent,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return json.loads((bank / "index.json").read_text(encoding="utf-8"))


def test_index_source_bundle_works_with_older_package_on_pythonpath(bank, tmp_path):
    package = tmp_path / "old site-packages" / "memory_bank_skill"
    package.mkdir(parents=True)
    (package / "__init__.py").write_text("")
    shutil.copy2(ROOT / "memory_bank_skill" / "_io.py", package / "_io.py")
    (bank / "lessons.md").write_text("### L-001: Public <private>secret-marker</private>\n")
    result = subprocess.run(
        [sys.executable, str(INDEX), str(bank)], cwd=bank.parent,
        env={**os.environ, "PYTHONPATH": str(package.parent)},
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    index = (bank / "index.json").read_text()
    assert "secret-marker" not in index
    assert "Public" in index


@pytest.mark.parametrize(
    "body, public",
    [
        (
            "Public before <private>Alice <alice@example.invalid> secret-one</private> Public after\n",
            ["Public before", "Public after"],
        ),
        (
            "Public before <private>secret-one</private> Public middle "
            "<private>secret-two</private> Public after <private>secret-three\nsecret-four\n",
            ["Public before", "Public middle", "Public after"],
        ),
        (
            "Public before <private>secret-one\nsecret-two</private> Public middle "
            "<private>secret-three\nsecret-four</private> Public after\n",
            ["Public before", "Public middle", "Public after"],
        ),
        (
            "Public before\n<private>secret-one <b>secret-two</b>\n"
            "secret-three\n</private>\nPublic after\n",
            ["Public before", "Public after"],
        ),
        (
            "Public before <private>secret-one <private>secret-two</private> "
            "secret-three</private> Public after\n",
            ["Public before", "Public after"],
        ),
    ],
    ids=["angle-markup", "closed-then-unclosed", "multiline-boundaries", "multiline", "nested-private"],
)
@pytest.mark.parametrize("mode", ["tag", "freetext"])
def test_search_private_blocks_nested_or_unclosed_keep_public_text(bank, body, public, mode):
    _note(bank, body)

    result = _search(bank, "--tag", "audit") if mode == "tag" else _search(bank, "Public")

    assert result.returncode == 0, result.stderr
    assert "secret-" not in result.stdout
    assert "alice@example.invalid" not in result.stdout
    assert "<private>" not in result.stdout
    assert "</private>" not in result.stdout
    for evidence in public:
        assert evidence in result.stdout


@pytest.mark.parametrize("newline", ["\n", "\r\n", "\r"])
def test_freetext_public_lines_between_closed_and_unclosed_spans_remain_visible(bank, newline):
    body = newline.join(
        [
            "Public before",
            "<private>secret-one</private>",
            "Public middle",
            "<private>",
            "secret-two",
            "</private>",
            "Public after",
            "<private>secret-three",
            "Public hidden within unfinished block",
        ]
    )
    _note(bank, body)

    result = _search(bank, "Public")

    assert result.returncode == 0, result.stderr
    assert "5:Public before" in result.stdout
    assert "7:Public middle" in result.stdout
    assert "11:Public after" in result.stdout
    assert "Public hidden" not in result.stdout
    assert "secret-" not in result.stdout
    assert "13:[REDACTED" in result.stdout


@pytest.mark.parametrize(
    "private_record, suffix",
    [
        (
            "### L-001: Visible title <private>secret-one <a@example.invalid></private>\n",
            [{"id": "L-001", "title": "Visible title"}],
        ),
        ("### L-001: <private>secret-one</private>\n", []),
        ("<private>\n### L-001: secret-one\nsecret-two\n</private>\n", []),
        (
            "<private>\n### L-001: secret-one\n</private>\n"
            "<private>\n### L-002: secret-two\n</private>\n",
            [],
        ),
    ],
    ids=["inline-title", "fully-private-title", "entire-record", "multiple-records"],
)
def test_index_lessons_closed_private_content_excluded_before_extraction(bank, private_record, suffix):
    (bank / "lessons.md").write_text(
        "### L-000: Public before\n" + private_record + "### L-003: Public after\n",
        encoding="utf-8",
    )

    data = _index(bank)

    assert data["lessons"] == [
        {"id": "L-000", "title": "Public before"},
        *suffix,
        {"id": "L-003", "title": "Public after"},
    ]
    assert "secret-" not in json.dumps(data)
    assert "<private>" not in json.dumps(data)


def test_index_lessons_unclosed_block_after_closed_span_hides_only_actual_tail(bank):
    (bank / "lessons.md").write_text(
        "<private>secret-one</private>\n### L-001: Public middle\n"
        "<private>secret-two\n### L-002: secret-three\n",
        encoding="utf-8",
    )

    data = _index(bank)

    assert data["lessons"] == [{"id": "L-001", "title": "Public middle"}]
    assert "secret-" not in json.dumps(data)


@pytest.mark.parametrize("mode", ["tag", "freetext"])
@pytest.mark.parametrize("env_enabled, flag_enabled", [(False, True), (True, False), (True, True)])
def test_search_private_reveal_requires_both_opt_ins(bank, mode, env_enabled, flag_enabled):
    _note(bank, "Public <private>secret-one <a@example.invalid></private>\n")
    args = ["--tag", "audit"] if mode == "tag" else ["Public"]
    if flag_enabled:
        args.insert(0, "--show-private")

    result = _search(bank, *args, reveal_env=env_enabled)

    if flag_enabled and not env_enabled:
        assert result.returncode == 2
        assert "MB_SHOW_PRIVATE=1" in result.stderr
        assert "secret-one" not in result.stdout
    else:
        assert result.returncode == 0, result.stderr
        assert "Public" in result.stdout
        assert ("secret-one" in result.stdout) is (env_enabled and flag_enabled)
