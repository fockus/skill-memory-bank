"""In-process checks for mb_bank_lint.py and mb_backlog_migrate.py.

The full contracts live in tests/bats/test_mb_bank_lint.bats and test_mb_backlog_migrate.bats;
these run the same entry points in-process so CI coverage (pytest-cov 7, no subprocess
measurement) sees the modules.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys

from _inproc import SCRIPTS, run_main

sys.path.insert(0, str(SCRIPTS))
import mb_backlog_migrate  # noqa: E402
import mb_bank_lint  # noqa: E402

ICE = "{impact: 5, confidence: 5, ease: 5}"


def _plan(bank: pathlib.Path, name: str, extra: str = "") -> None:
    (bank / "plans" / f"2026-01-01_feature_{name}.md").write_text(
        f"---\ntype: feature\ntopic: {name}\nstatus: queued\n{extra}"
        "depends_on: []\nparallel_safe: false\nlinked_specs: []\ncreated: 2026-01-01\n---\n# Plan\n",
        encoding="utf-8",
    )


def _bank(tmp_path: pathlib.Path, backlog: str) -> pathlib.Path:
    bank = tmp_path / ".memory-bank"
    (bank / "plans").mkdir(parents=True)
    (bank / "specs" / "alpha").mkdir(parents=True)
    (bank / "specs" / "alpha" / "requirements.md").write_text(
        f"---\ntopic: alpha\ngroup: grp\nice: {ICE}\nice_confirmed: true\nstatus: ready\n---\n# R\n",
        encoding="utf-8",
    )
    (bank / "roadmap.md").write_text(
        "# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n", encoding="utf-8"
    )
    (bank / "backlog.md").write_text(backlog, encoding="utf-8")
    return bank


def _sync(bank: pathlib.Path) -> None:
    subprocess.run(["bash", str(SCRIPTS / "mb-roadmap-sync.sh"), str(bank)], capture_output=True)


CLEAN = "# Backlog\n\n## Ideas\n\n### I-001 — fine [MED, NEW, 2026-04-01]\n\n## Out of scope\n\n## ADR\n"


def test_bank_lint_clean_bank_exits_0_silent(tmp_path: pathlib.Path) -> None:
    bank = _bank(tmp_path, CLEAN)
    _plan(bank, "clean", f"ice: {ICE}\nice_confirmed: true\n")
    _sync(bank)
    res = run_main(mb_bank_lint.main, ["all", str(bank)])
    assert (res.returncode, res.stdout) == (0, "")


def test_bank_lint_broken_bank_reports_errors_and_warnings(tmp_path: pathlib.Path) -> None:
    backlog = (
        "# Backlog\n\n## Ideas\n\n"
        "### I-001 — a [MED, NEW, 2026-04-01]\n\n"
        "### I-001 — dup [MED, NEW, 2026-04-01]\n\n"
        "### I-002 — old [MED, OPEN, 2026-04-02]\n\n"
        "### I-003 — weird [MED, BOGUS, 2026-04-02]\n\n"
        "## Out of scope\n\n## ADR\n"
    )
    bank = _bank(tmp_path, backlog)
    _plan(bank, "no-ice")
    _plan(bank, "unconf", "ice: {impact: 2, confidence: 3, ease: 4}\n")
    _plan(bank, "bad-ice", "ice: {impact: 11, confidence: 5, ease: 5}\n")
    _plan(bank, "bad-conf", f"ice: {ICE}\nice_confirmed: yes\n")
    _plan(bank, "bad-pin", f"ice: {ICE}\nice_confirmed: true\npin: x\n")
    _sync(bank)
    res = run_main(mb_bank_lint.main, ["all", str(bank)])
    assert res.returncode == 1, res.stdout + res.stderr
    for code in (
        "no_ice",
        "ice_unconfirmed",
        "invalid_ice",
        "invalid_ice_confirmed",
        "invalid_pin",
    ):
        assert f"code={code} " in res.stdout, (code, res.stdout)
    assert "code=legacy_state " in res.stdout or "code=duplicate_id " in res.stdout


def test_bank_lint_unknown_scope_exits_2(tmp_path: pathlib.Path) -> None:
    assert run_main(mb_bank_lint.main, ["bogus", str(tmp_path)]).returncode == 2


LEGACY = (
    "# Backlog\n\n## Ideas\n\n"
    "### I-001 — open [MED, OPEN, 2026-04-01]\n\n"
    "### I-002 — planned [HIGH, PLANNED, 2026-04-01]\n\n**Plan:** [plans/x.md](plans/x.md)\n\n"
    "### I-003 — declined [LOW, DECLINED, 2026-04-01]\n\n"
    "### I-004 — resolved [HIGH, RESOLVED 2026-06-14 — abc]\n\n"
    "### I-005 — odd [MED, OBSOLETE, 2026-04-01]\n\n"
    "## ADR\n"
)


def test_backlog_migrate_dry_run_leaves_file_and_apply_is_idempotent(
    tmp_path: pathlib.Path,
) -> None:
    path = tmp_path / "backlog.md"
    path.write_text(LEGACY, encoding="utf-8")
    dry = run_main(mb_backlog_migrate.main, [str(path), "dry-run"])
    assert dry.returncode == 0 and "actions_pending=0" not in dry.stdout
    assert path.read_text(encoding="utf-8") == LEGACY
    assert "unknown_legacy_state=OBSOLETE" in dry.stderr

    applied = run_main(
        mb_backlog_migrate.main, [str(path), "apply", "--backup-dir", str(tmp_path / "bak")]
    )
    assert applied.returncode == 0
    migrated = path.read_text(encoding="utf-8")
    assert "OPEN," not in migrated and "PLANNED," not in migrated
    assert (tmp_path / "bak" / "backlog.md").read_text(encoding="utf-8") == LEGACY
    again = run_main(mb_backlog_migrate.main, [str(path), "apply"])
    assert "actions_pending=0" in again.stdout
    assert path.read_text(encoding="utf-8") == migrated


def test_backlog_migrate_bad_mode_exits_2(tmp_path: pathlib.Path) -> None:
    assert run_main(mb_backlog_migrate.main, [str(tmp_path / "b.md"), "go"]).returncode == 2
