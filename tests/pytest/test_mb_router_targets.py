"""Every router row in commands/mb.md must name an existing references/mb/<sub>.md."""
from __future__ import annotations

import re

from mb_corpus import MB_MD, MB_REFS, ROOT

LIMIT_BYTES = 16384


def _router_rows() -> list[str]:
    rows, in_table = [], False
    for line in MB_MD.read_text(encoding="utf-8").splitlines():
        if line.startswith("| Subcommand"):
            in_table = True
            continue
        if in_table:
            if not line.startswith("|"):
                break
            if not line.startswith("| ---"):
                rows.append(line)
    return rows


def test_router_has_rows():
    assert len(_router_rows()) >= 50


def test_every_router_row_points_at_an_existing_reference():
    for row in _router_rows():
        m = re.search(r"`(references/mb/[\w\-]+\.md)`\s*\|$", row)
        assert m, f"router row has no references/mb target: {row[:80]}"
        assert (ROOT / m.group(1)).is_file(), f"missing {m.group(1)}"


def test_no_orphan_reference_files():
    text = MB_MD.read_text(encoding="utf-8")
    for p in MB_REFS.glob("*.md"):
        assert f"references/mb/{p.name}" in text, f"{p.name} is not routed"


def test_mb_md_stays_within_byte_budget():
    assert len(MB_MD.read_bytes()) <= LIMIT_BYTES


def test_help_route_resolves_subcommand_reference():
    assert "/mb help <subcommand>" in MB_MD.read_text(encoding="utf-8")
    assert "references/mb/<subcommand>.md" in (MB_REFS / "help.md").read_text(encoding="utf-8")


_CELL_SPLIT = re.compile(r"(?<!\\)\|")


def test_every_router_row_has_a_command_an_action_and_a_reference():
    for row in _router_rows():
        cells = [c.strip() for c in _CELL_SPLIT.split(row)[1:-1]]
        assert len(cells) == 3 and all(cells), f"router row needs 3 non-empty cells: {row[:80]}"


def test_help_algorithm_prints_the_reference_for_every_router_command():
    import os
    import subprocess
    import sys

    block = re.search(r"<<'PY'\n(.*?)\nPY\n", (MB_REFS / "help.md").read_text(encoding="utf-8"), re.S)
    assert block, "help.md lost its algorithm block"
    words = {"context", "ask_me", "grooming"}
    for row in _router_rows():
        cell = _CELL_SPLIT.split(row)[1]
        words |= {tok.split()[0] for tok in re.findall(r"`([^`]+)`", cell) if tok.split()}
    for word in sorted(words):
        env = dict(os.environ, SKILL_MD=str(MB_MD), SUB=word)
        done = subprocess.run([sys.executable, "-c", block.group(1)], env=env, capture_output=True, text=True)
        assert done.returncode == 0, f"/mb help {word}: {done.stderr}"
        assert done.stdout.startswith("# /mb "), word
