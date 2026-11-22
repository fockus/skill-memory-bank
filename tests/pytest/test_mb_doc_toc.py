"""mb-doc-toc.py: a line-range contents block for long command files, kept honest by --check."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOC = ROOT / "scripts" / "mb-doc-toc.py"
TEAM_MD = ROOT / "commands" / "team.md"
DOC = "# Title\n\nintro\n\n<!-- toc:start -->\n<!-- toc:end -->\n\n## One\na\nb\n\n## Two\nc\n"


def _run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(TOC), *args], capture_output=True, text=True)


def test_toc_write_lists_each_section_with_its_line_range(tmp_path):
    doc = tmp_path / "d.md"
    doc.write_text(DOC, encoding="utf-8")
    assert _run(str(doc)).returncode == 0
    lines = doc.read_text(encoding="utf-8").splitlines()
    one, two = lines.index("## One") + 1, lines.index("## Two") + 1
    assert f"- L{one}–L{two - 1} · One" in lines
    assert f"- L{two}–L{len(lines)} · Two" in lines
    assert any(f"{len(lines)} lines" in ln for ln in lines)
    assert _run("--check", str(doc)).returncode == 0


def test_toc_check_fails_when_the_ranges_drift(tmp_path):
    doc = tmp_path / "d.md"
    doc.write_text(DOC, encoding="utf-8")
    _run(str(doc))
    doc.write_text(
        doc.read_text(encoding="utf-8").replace("\na\n", "\na\nadded\n"), encoding="utf-8"
    )
    r = _run("--check", str(doc))
    assert r.returncode == 1 and "mb-doc-toc.py" in r.stderr


def test_team_command_starts_with_the_key_rules_and_a_current_toc():
    head = TEAM_MD.read_text(encoding="utf-8").splitlines()[:45]
    text = "\n".join(head)
    assert "Read this file whole" in text and "<!-- toc:start -->" in text
    for rule in ("never edit code", "--followup", "team commit", "mb-team-track", "track set"):
        assert rule in text, rule
    assert _run("--check", str(TEAM_MD)).returncode == 0
