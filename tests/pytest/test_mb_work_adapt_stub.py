"""svp-adapt-escalation T4 — verify-stub gate (design C4, REQ-009)."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys

import pytest
from _inproc import load_adapt, run_main

ADAPT = str(pathlib.Path(__file__).resolve().parents[2] / "scripts" / "mb_work_adapt.py")
MARKER = "# MB-ADAPT-STUB backlog=I-007 flag=MB_STUB_X eval=drv.sh"
GOOD_DRIVER = (
    '#!/usr/bin/env bash\nif [ -n "${MB_STUB_X:-}" ]; then echo "MB-ADAPT-STUB-PATH: staged";'
    ' else echo "MB-ADAPT-STUB-PATH: baseline"; fi\n'
)
STUB_SRC = f'"""Stub.\n{MARKER}\n"""\nimport os\nON = os.environ.get("MB_STUB_X")\n'


def _repo(tmp_path, src=STUB_SRC, driver=GOOD_DRIVER, backlog="### I-007 — x [HIGH, READY, d]\n"):
    (tmp_path / "mod.py").write_text(src, encoding="utf-8")
    if driver is not None:
        drv = tmp_path / "drv.sh"
        drv.write_text(driver, encoding="utf-8")
        drv.chmod(0o755)
    (tmp_path / "backlog.md").write_text("## Ideas\n\n" + backlog, encoding="utf-8")
    (tmp_path / "diff.txt").write_text("mod.py\n", encoding="utf-8")
    return tmp_path


def _verify(repo, files="mod.py\n", env=None):
    (repo / "diff.txt").write_text(files, encoding="utf-8")
    res = run_main(
        load_adapt().main,
        [
            "verify-stub",
            "--repo",
            str(repo),
            "--diff-file",
            str(repo / "diff.txt"),
            "--backlog",
            str(repo / "backlog.md"),
        ],
        env={**os.environ, **(env or {})},
    )
    return res, (json.loads(res.stdout) if res.stdout.strip() else {})


def _reasons(out):
    return [v["reason"] for v in out["violations"]]


def test_verify_stub_clean_stub_passes_and_is_listed(tmp_path) -> None:
    res, out = _verify(_repo(tmp_path))
    assert res.returncode == 0, res.stderr
    assert out["violations"] == []
    assert out["stubs"] == [
        {"file": "mod.py", "backlog_id": "I-007", "flag": "MB_STUB_X", "eval": "drv.sh"}
    ]


def test_verify_stub_default_on_flag_fails(tmp_path) -> None:
    driver = '#!/usr/bin/env bash\necho "MB-ADAPT-STUB-PATH: staged"\n'
    res, out = _verify(_repo(tmp_path, driver=driver))
    assert res.returncode == 1 and _reasons(out) == ["flag_default_on"]


def test_verify_stub_flag_that_does_not_gate_fails(tmp_path) -> None:
    driver = '#!/usr/bin/env bash\necho "MB-ADAPT-STUB-PATH: baseline"\n'
    res, out = _verify(_repo(tmp_path, driver=driver))
    assert res.returncode == 1 and _reasons(out) == ["flag_does_not_gate_stub"]


def test_verify_stub_marker_without_eval_fails(tmp_path) -> None:
    src = STUB_SRC.replace(" eval=drv.sh", "")
    res, out = _verify(_repo(tmp_path, src=src))
    assert res.returncode == 1 and _reasons(out) == ["missing_stub_eval"]


def test_verify_stub_unknown_backlog_id_fails(tmp_path) -> None:
    res, out = _verify(_repo(tmp_path, backlog="### I-001 — y [LOW, NEW, d]\n"))
    assert res.returncode == 1 and "unknown_backlog_id" in _reasons(out)


def test_verify_stub_marker_outside_a_comment_fails(tmp_path) -> None:
    src = f'x = "{MARKER[2:]}"\nimport os\nON = os.environ.get("MB_STUB_X")\n'
    res, out = _verify(_repo(tmp_path, src=src))
    assert res.returncode == 1 and "marker_not_in_docstring" in _reasons(out)


def test_verify_stub_flag_only_on_the_marker_line_fails(tmp_path) -> None:
    res, out = _verify(_repo(tmp_path, src=f'"""Stub.\n{MARKER}\n"""\n'))
    assert res.returncode == 1 and "flag_token_unused" in _reasons(out)


@pytest.mark.parametrize(
    "body", ["raise NotImplementedError\n", "# TODO later\n", "def f():\n    ...\n"]
)
def test_verify_stub_bare_placeholder_without_marker_fails(tmp_path, body) -> None:
    res, out = _verify(_repo(tmp_path, src=body))
    assert res.returncode == 1 and _reasons(out) == ["bare_placeholder"]
    assert out["violations"][0]["line"] >= 1


def test_verify_stub_failing_driver_fails(tmp_path) -> None:
    res, out = _verify(_repo(tmp_path, driver="#!/usr/bin/env bash\nexit 3\n"))
    assert res.returncode == 1 and _reasons(out) == ["stub_eval_failed"]


def test_verify_stub_hanging_driver_times_out(tmp_path) -> None:
    res, out = _verify(
        _repo(tmp_path, driver="#!/usr/bin/env bash\nsleep 30\n"),
        env={"MB_ADAPT_STUB_TIMEOUT": "1"},
    )
    assert res.returncode == 1 and _reasons(out) == ["stub_eval_timeout"]


def test_verify_stub_missing_or_unrunnable_driver_is_a_tooling_error(tmp_path) -> None:
    assert _verify(_repo(tmp_path, driver=None))[0].returncode == 2
    drv = tmp_path / "drv.sh"
    drv.write_text(GOOD_DRIVER, encoding="utf-8")
    drv.chmod(0o644)
    assert _verify(tmp_path)[0].returncode == 2


def test_verify_stub_lists_two_valid_stubs(tmp_path) -> None:
    repo = _repo(tmp_path)
    (repo / "other.py").write_text(
        STUB_SRC.replace("I-007", "I-008").replace("MB_STUB_X", "MB_STUB_Y"), encoding="utf-8"
    )
    (repo / "backlog.md").write_text(
        "### I-007 — a [HIGH, READY, d]\n### I-008 — b [HIGH, READY, d]\n"
    )
    drv2 = GOOD_DRIVER.replace("MB_STUB_X", "MB_STUB_Y")
    (repo / "drv2.sh").write_text(drv2, encoding="utf-8")
    (repo / "drv2.sh").chmod(0o755)
    (repo / "other.py").write_text(
        (repo / "other.py").read_text(encoding="utf-8").replace("eval=drv.sh", "eval=drv2.sh"),
        encoding="utf-8",
    )
    res, out = _verify(repo, files="mod.py\nother.py\n")
    assert res.returncode == 0, res.stdout
    assert [s["backlog_id"] for s in out["stubs"]] == ["I-007", "I-008"]


def test_verify_stub_usage_error_exits_2(tmp_path) -> None:
    res = subprocess.run(
        [sys.executable, ADAPT, "verify-stub", "--repo", str(tmp_path)],
        capture_output=True,
        text=True,
    )
    assert res.returncode == 2
