"""svp-adapt-escalation T5 — stub-backlog chain over the shipped S4 writers (design C5, REQ-004)."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
ADAPT = str(ROOT / "scripts" / "mb_work_adapt.py")
STATE = str(ROOT / "scripts" / "mb-backlog-state.sh")
BACKLOG = "# Backlog\n\n## Ideas\n\n## Out of scope\n\n## ADR\n"


def _bank(tmp_path: pathlib.Path, text: str = BACKLOG) -> pathlib.Path:
    (tmp_path / "backlog.md").write_text(text, encoding="utf-8")
    return tmp_path


def _chain(bank, reason="needs a big refresh", *extra):
    return subprocess.run(
        [
            sys.executable,
            ADAPT,
            "stub-backlog",
            "--bank",
            str(bank),
            "--spec-topic",
            "svp-x",
            "--task-id",
            "3",
            "--reason",
            reason,
            "--flag",
            "MB_STUB_X",
            "--capability",
            "bulk refresh, retry",
            *extra,
        ],
        capture_output=True,
        text=True,
    )


def _state(bank, item) -> str:
    out = subprocess.run(["bash", STATE, "list", "--mb", str(bank)], capture_output=True, text=True)
    return re.search(rf"item={item} state=(\S+)", out.stdout).group(1)


def test_stub_backlog_reaches_ready_before_code(tmp_path: pathlib.Path) -> None:
    bank = _bank(tmp_path)
    res = _chain(bank)
    assert res.returncode == 0, res.stderr
    item = res.stdout.strip()
    assert re.fullmatch(r"I-\d+", item) and _state(bank, item) == "READY"
    text = (bank / "backlog.md").read_text(encoding="utf-8")
    assert "[ADAPT] svp-x#3: needs a big refresh" in text
    brief = re.search(r"\*\*Brief:\*\* (.*)", text).group(1)
    assert "shall" in brief and "MB_STUB_X" in brief and "refresh" in brief
    assert "needs a big" not in brief and not re.search(r"\w+\.\w+:\d|/", brief)
    assert "PLANNED" not in text


def test_stub_backlog_repeat_reuses_the_item(tmp_path: pathlib.Path) -> None:
    bank = _bank(tmp_path)
    first = _chain(bank).stdout.strip()
    again = _chain(bank)
    assert again.returncode == 0, again.stderr
    assert again.stdout.strip() == first and _state(bank, first) == "READY"


def test_stub_backlog_resumes_from_an_intermediate_state(tmp_path: pathlib.Path) -> None:
    bank = _bank(tmp_path)
    item = subprocess.run(
        [
            "bash",
            str(ROOT / "scripts" / "mb-idea.sh"),
            "[ADAPT] svp-x#3: half way",
            "HIGH",
            str(bank),
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    for step in ("NEEDS-INFO", "TRIAGED"):
        subprocess.run(
            ["bash", STATE, "transition", item, step, "--mb", str(bank)],
            check=True,
            capture_output=True,
        )
    res = _chain(bank, "half way")
    assert res.returncode == 0, res.stderr
    assert _state(bank, item) == "READY"


def test_stub_backlog_halts_on_wontfix(tmp_path: pathlib.Path) -> None:
    bank = _bank(tmp_path)
    item = _chain(bank, "dropped").stdout.strip()
    for step in ("IN-PROGRESS", "WONTFIX"):
        done = subprocess.run(
            ["bash", STATE, "transition", item, step, "--mb", str(bank), "--reason", "no"],
            capture_output=True,
            text=True,
        )
        assert done.returncode == 0, done.stderr
    res = _chain(bank, "dropped")
    assert res.returncode == 1 and res.stdout.strip() == ""


def test_stub_backlog_halts_on_similar_out_of_scope(tmp_path: pathlib.Path) -> None:
    bank = _bank(
        tmp_path,
        BACKLOG.replace(
            "## Out of scope\n",
            "## Out of scope\n\n### I-020 — svp-x#3 needs a big refresh [MED, WONTFIX, 2026-04-01]\n",
        ),
    )
    res = _chain(bank)
    assert res.returncode == 1 and "similar_out_of_scope" in res.stderr


def test_stub_backlog_usage_and_bad_flag_exit_2(tmp_path: pathlib.Path) -> None:
    bank = _bank(tmp_path)
    assert (
        subprocess.run(
            [sys.executable, ADAPT, "stub-backlog", "--bank", str(bank)],
            capture_output=True,
            text=True,
        ).returncode
        == 2
    )
    bad = subprocess.run(
        [
            sys.executable,
            ADAPT,
            "stub-backlog",
            "--bank",
            str(bank),
            "--spec-topic",
            "t",
            "--task-id",
            "1",
            "--reason",
            "r",
            "--flag",
            "lower",
            "--capability",
            "x",
        ],
        capture_output=True,
        text=True,
    )
    assert bad.returncode == 2
