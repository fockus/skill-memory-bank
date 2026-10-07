"""Stage 4 (AGR-073) — `mb-work-plan.sh` emits a parallel `wave` per item."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-plan.sh"

# Key order of the pre-wave emitter; `wave` is appended after `final_verify`.
LEGACY_KEYS = [
    "plan",
    "stage_no",
    "item_no",
    "heading",
    "role",
    "agent",
    "model",
    "thinking",
    "status",
    "dod_lines",
    "source",
    "source_topic",
    "source_path",
    "kind",
    "covers",
    "discipline",
    "model_source",
    "cost",
    "host",
    "step_models",
    "verify",
    "final_verify",
]
# Model-routing fields depend on pipeline.default.yaml, not on this stage.
ROUTING_KEYS = {"model", "thinking", "discipline", "model_source", "cost", "step_models"}


def _bank(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "plans" / "done").mkdir(parents=True)
    (mb / "specs").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n", encoding="utf-8"
    )
    return mb


def _plan(mb: Path, files: list[str | None]) -> Path:
    parts = ["---\ntype: feature\ntopic: foo\nstatus: in-progress\n---\n\n# Plan\n\n"]
    for no, line in enumerate(files, 1):
        label = "ABC"[no - 1] if no <= 3 else str(no)
        files_line = f"**Files:** {line}\n\n" if line is not None else ""
        parts.append(
            f"<!-- mb-stage:{no} -->\n## Stage {no}: do {label}\n\n{files_line}- [ ] DoD {label}\n\n"
        )
    plan = mb / "plans" / "p.md"
    plan.write_text("".join(parts), encoding="utf-8")
    return plan


def _items(mb: Path, target: Path) -> list[dict]:
    r = subprocess.run(
        ["bash", str(SCRIPT), "--target", str(target), "--mb", str(mb), "--host", "claude-code"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert r.returncode == 0, r.stderr
    return [json.loads(line) for line in r.stdout.splitlines() if line.startswith("{")]


@pytest.mark.parametrize(
    ("files", "waves"),
    [
        (["`scripts/a.sh`, docs/a.md", "scripts/b.sh", "tests/c.py"], [1, 1, 1]),
        (["scripts/a.sh, docs/a.md", "scripts/b.sh", "scripts/a.sh"], [1, 1, 2]),
        ([None, None, None], [1, 2, 3]),
        (["scripts/a.sh", None, "scripts/b.sh"], [1, 2, 3]),
        (["<!-- files this stage edits -->", "scripts/b.sh", "scripts/c.sh"], [1, 2, 2]),
        (["scripts/", "scripts/b.sh", "tests/*.py"], [1, 2, 2]),
    ],
    ids=["disjoint", "intersect", "no-files", "gap", "scaffold-comment", "dir-and-glob"],
)
def test_wave_from_files_lines(tmp_path: Path, files: list, waves: list[int]) -> None:
    mb = _bank(tmp_path)
    objs = _items(mb, _plan(mb, files))
    assert [o["wave"] for o in objs] == waves


def test_wave_explicit_blocked_by_splits_disjoint_stages(tmp_path: Path) -> None:
    mb = _bank(tmp_path)
    plan = _plan(mb, ["scripts/a.sh", "scripts/b.sh\n**Blocked-by:** 1"])
    assert [o["wave"] for o in _items(mb, plan)] == [1, 2]


def test_wave_json_otherwise_identical_and_final_verify_last(tmp_path: Path) -> None:
    mb = _bank(tmp_path)
    plan = _plan(mb, ["`scripts/a.sh`, docs/a.md", "scripts/b.sh", "scripts/a.sh"])
    objs = _items(mb, plan)
    # Golden captured from the pre-wave emitter on this fixture.
    golden = [
        {
            "plan": "p.md",
            "stage_no": n,
            "item_no": n,
            "heading": f"Stage {n}: do {c}",
            "role": "developer",
            "agent": "mb-developer",
            "status": "pending",
            "dod_lines": 1,
            "source": "plan",
            "source_topic": "p",
            "source_path": str(plan.resolve()),
            "kind": "stage",
            "covers": [],
            "host": "claude-code",
            "verify": n == 3,
            "final_verify": n == 3,
        }
        for n, c in ((1, "A"), (2, "B"), (3, "C"))
    ]
    for obj, gold in zip(objs, golden, strict=True):
        assert list(obj) == [*LEGACY_KEYS, "wave"]
        assert {k: v for k, v in obj.items() if k not in ROUTING_KEYS | {"wave"}} == gold


def test_wave_spec_tasks_use_scope_and_blocked_by(tmp_path: Path) -> None:
    mb = _bank(tmp_path)
    spec = mb / "specs" / "t"
    spec.mkdir()
    tasks = spec / "tasks.md"
    tasks.write_text(
        "# Tasks\n\n"
        "<!-- mb-task:1 -->\n## Task 1: a\n\n**Scope:** scripts/a.sh\n\n- [ ] a\n\n"
        "<!-- mb-task:2 -->\n## Task 2: b\n\n**Blocked-by:** none\n**Scope:** scripts/b.sh\n\n- [ ] b\n\n"
        "<!-- mb-task:3 -->\n## Task 3: c\n\n**Scope:** scripts/c.sh\n\n- [ ] c\n\n"
        "<!-- mb-task:4 -->\n## Task 4: d\n\n**Blocked-by:** none\n\n- [ ] d\n",
        encoding="utf-8",
    )
    # Task 3 implicitly depends on task 2 (C1 default); task 4 has no Scope.
    assert [o["wave"] for o in _items(mb, tasks)] == [1, 1, 2, 3]
