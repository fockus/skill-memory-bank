"""mb-team Stage 6 (T-ENGINE, AGR-097): acceptance of a `light` work-mode track.

A light track agent walks the stages of its source itself; before the
orchestrator spends verifier and review on it, `mb_work_light.py accept`
checks the report against the source: STATUS line, every pending stage done,
no stage whose Eval gate only the orchestrated engine can prove.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb_work_light.py"


def _source(tmp_path: Path, stages: int = 2, extra: dict[int, str] | None = None,
            done: tuple[int, ...] = ()) -> Path:
    body = ""
    for n in range(1, stages + 1):
        box = "[x]" if n in done else "[ ]"
        body += (f"<!-- mb-stage:{n} -->\n### Stage {n}: step {n}\n\n{(extra or {}).get(n, '')}"
                 f"**DoD:**\n- {box} bit {n}\n\n")
    path = tmp_path / "track.prompt.md"
    path.write_text("---\ntype: feature\ntopic: t\n---\n# Track\n\n" + body, encoding="utf-8")
    return path


def _report(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "A.md"
    path.write_text(text, encoding="utf-8")
    return path


def _accept(source: Path, report: Path) -> tuple[int, dict]:
    r = subprocess.run([sys.executable, str(SCRIPT), "accept", "--source", str(source),
                        "--report", str(report), "--json"],
                       capture_output=True, text=True, check=False)
    return r.returncode, (json.loads(r.stdout) if r.stdout.strip() else {"stderr": r.stderr})


DONE_BOTH = "STATUS: DONE\n\nwork summary\n\n## Stages\n- 1: done — bats green\n- 2: done\n"


def test_accept_all_stages_done_is_accepted(tmp_path: Path) -> None:
    rc, out = _accept(_source(tmp_path), _report(tmp_path, DONE_BOTH))
    assert rc == 0, out
    assert out["accepted"] is True
    assert out["status"] == "DONE"
    assert out["items"] == [1, 2]


def test_accept_done_with_concerns_is_accepted(tmp_path: Path) -> None:
    rc, out = _accept(_source(tmp_path),
                      _report(tmp_path, DONE_BOTH.replace("STATUS: DONE", "STATUS: DONE_WITH_CONCERNS")))
    assert rc == 0, out
    assert out["status"] == "DONE_WITH_CONCERNS"


def test_accept_missing_stage_is_rejected_naming_it(tmp_path: Path) -> None:
    rc, out = _accept(_source(tmp_path), _report(tmp_path, "STATUS: DONE\n\n## Stages\n- 1: done\n"))
    assert rc == 1
    assert out["accepted"] is False
    assert out["pending"] == [2]
    assert any("2" in e for e in out["errors"])


def test_accept_blocked_stage_is_rejected(tmp_path: Path) -> None:
    rc, out = _accept(_source(tmp_path),
                      _report(tmp_path, "STATUS: DONE\n\n## Stages\n- 1: done\n- 2: blocked — no disk\n"))
    assert rc == 1
    assert out["pending"] == [2]


def test_accept_blocked_status_is_rejected(tmp_path: Path) -> None:
    rc, out = _accept(_source(tmp_path), _report(tmp_path, DONE_BOTH.replace("DONE\n\nwork", "BLOCKED\n\nwork")))
    assert rc == 1
    assert out["status"] == "BLOCKED"


def test_accept_report_without_status_line_is_rejected(tmp_path: Path) -> None:
    rc, out = _accept(_source(tmp_path), _report(tmp_path, DONE_BOTH.replace("STATUS: DONE\n", "")))
    assert rc == 1
    assert any("STATUS" in e for e in out["errors"])


def test_accept_unknown_stage_in_report_is_rejected(tmp_path: Path) -> None:
    rc, out = _accept(_source(tmp_path), _report(tmp_path, DONE_BOTH + "- 7: done\n"))
    assert rc == 1
    assert any("7" in e for e in out["errors"])


def test_accept_stage_with_eval_gate_needs_orchestrated(tmp_path: Path) -> None:
    src = _source(tmp_path, extra={2: "**Eval:** bats t.bats — red: fails\n\n"})
    rc, out = _accept(src, _report(tmp_path, DONE_BOTH))
    assert rc == 1
    assert any("orchestrated" in e for e in out["errors"])


def test_accept_waived_eval_is_fine(tmp_path: Path) -> None:
    src = _source(tmp_path, extra={2: "**Eval:** none — waiver: docs only\n\n"})
    rc, out = _accept(src, _report(tmp_path, DONE_BOTH))
    assert rc == 0, out


def test_accept_stage_already_done_in_source_need_not_be_reported(tmp_path: Path) -> None:
    rc, out = _accept(_source(tmp_path, done=(1,)), _report(tmp_path, "STATUS: DONE\n\n## Stages\n- 2: done\n"))
    assert rc == 0, out
    assert out["items"] == [2]


def test_accept_missing_report_exits_2(tmp_path: Path) -> None:
    rc, _ = _accept(_source(tmp_path), tmp_path / "absent.md")
    assert rc == 2
