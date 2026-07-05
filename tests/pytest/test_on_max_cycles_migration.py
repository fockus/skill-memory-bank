"""work-loop-v2 Task 4 (REQ-113) — `on_max_cycles` fail-fast default migration.

design.md §6 "Fail-fast default": the v5 shipped default flips
`on_max_cycles` from `continue_with_warning` to `stop_for_human`. Two
guarantees must hold simultaneously:

1. A project `pipeline.yaml` with NO `on_max_cycles` entry resolves to the
   NEW default (`stop_for_human`) — `scripts/mb-workflow.sh`'s legacy
   `stage_pipeline`-derived branch already does this
   (`review.get("on_max_cycles", "stop_for_human")`).
2. A project `pipeline.yaml` that explicitly set `on_max_cycles:
   continue_with_warning` keeps that value — the new default must never
   override an explicit setting (migration is opt-in-by-silence).
3. Install/upgrade never rewrites an existing `<bank>/pipeline.yaml`, so an
   explicit `continue_with_warning` project config survives an install
   re-run untouched — `scripts/mb-pipeline.sh init` already refuses to
   overwrite an existing file unless `--force` is passed, and neither
   `install.sh` nor `scripts/mb-init-bank.sh` ever calls `init` (or otherwise
   touches `<bank>/pipeline.yaml`) on their own.
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = REPO_ROOT / "scripts" / "mb-workflow.sh"
PIPELINE = REPO_ROOT / "scripts" / "mb-pipeline.sh"
DEFAULT_YAML = REPO_ROOT / "references" / "pipeline.default.yaml"


def _run(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(script), *args],
        capture_output=True,
        text=True,
        check=False,
    )


# A legacy (pre-`workflows:`) `stage_pipeline`-style config — this is the
# schema shape `mb-workflow.sh`'s "backward compatibility: derive from
# stage_pipeline" branch reads `on_max_cycles` from (the code path proving
# G3 is already shipped).
def _legacy_pipeline(on_max_cycles: str | None) -> dict:
    review_step: dict = {
        "step": "review",
        "role": "reviewer",
        "max_cycles": 3,
    }
    if on_max_cycles is not None:
        review_step["on_max_cycles"] = on_max_cycles
    return {
        "version": 1,
        "roles": {
            "developer": {"agent": "mb-developer"},
            "reviewer": {"agent": "mb-reviewer"},
            "verifier": {"agent": "plan-verifier"},
        },
        "stage_pipeline": [
            {"step": "implement", "role": "developer", "tdd": True},
            {"step": "verify", "role": "verifier"},
            review_step,
            {"step": "fix", "returns_to": "verify"},
            {"step": "done", "role": "verifier"},
        ],
    }


def _write_bank(tmp_path: Path, cfg: dict) -> Path:
    bank = tmp_path / ".memory-bank"
    bank.mkdir(parents=True, exist_ok=True)
    (bank / "pipeline.yaml").write_text(yaml.safe_dump(cfg, sort_keys=False), encoding="utf-8")
    return bank


def _resolve_loop(bank: Path) -> dict:
    proc = _run(WORKFLOW, "--mb", str(bank), "--loop")
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


# ── 1 & 2. Resolver: absent key -> new default; explicit key -> preserved ──


def test_absent_on_max_cycles_resolves_to_new_default_stop_for_human(tmp_path: Path) -> None:
    bank = _write_bank(tmp_path, _legacy_pipeline(on_max_cycles=None))
    loop = _resolve_loop(bank)
    assert loop["on_max_cycles"] == "stop_for_human"


def test_explicit_continue_with_warning_is_not_overridden(tmp_path: Path) -> None:
    bank = _write_bank(tmp_path, _legacy_pipeline(on_max_cycles="continue_with_warning"))
    loop = _resolve_loop(bank)
    assert loop["on_max_cycles"] == "continue_with_warning"


def test_explicit_stop_for_human_is_preserved_too(tmp_path: Path) -> None:
    """Explicit stop_for_human (matches the new default) is not special-cased."""
    bank = _write_bank(tmp_path, _legacy_pipeline(on_max_cycles="stop_for_human"))
    loop = _resolve_loop(bank)
    assert loop["on_max_cycles"] == "stop_for_human"


# ── 3. The shipped default itself must document/ship the new default value ──


def test_shipped_default_yaml_uses_stop_for_human() -> None:
    cfg = yaml.safe_load(DEFAULT_YAML.read_text(encoding="utf-8"))
    assert cfg["review"]["on_max_cycles"] == "stop_for_human", (
        "references/pipeline.default.yaml review.on_max_cycles must be the v5 "
        "fail-fast default (stop_for_human), not the legacy continue_with_warning"
    )


# ── 4. Install-safety: an existing project pipeline.yaml is never rewritten ──


def test_pipeline_init_refuses_to_overwrite_existing_file(tmp_path: Path) -> None:
    """`mb-pipeline.sh init` (the only writer of `<bank>/pipeline.yaml`) is
    copy-if-absent: a project that already has a pipeline.yaml — e.g. one
    that explicitly opted back into the old `continue_with_warning` policy —
    keeps it byte-for-byte across a second `init` (what an install/upgrade
    re-run would trigger if it ever called this), unless `--force` is passed.
    """
    bank = tmp_path / ".memory-bank"
    bank.mkdir()

    first = _run(PIPELINE, "init", str(bank))
    assert first.returncode == 0, first.stderr
    target = bank / "pipeline.yaml"
    assert target.is_file()

    # Simulate a v4 project that explicitly kept the old soft policy.
    custom = target.read_text(encoding="utf-8") + "\n# project override\ncustom_marker: true\n"
    target.write_text(custom, encoding="utf-8")

    second = _run(PIPELINE, "init", str(bank))
    assert second.returncode != 0, "init must refuse to clobber an existing pipeline.yaml"
    assert "already exists" in second.stderr

    assert target.read_text(encoding="utf-8") == custom, (
        "an existing pipeline.yaml must survive a non-forced init/install/upgrade untouched"
    )


def test_pipeline_init_force_is_the_only_way_to_overwrite(tmp_path: Path) -> None:
    """Contrast case: `--force` is the explicit, human-driven escape hatch —
    never something install/upgrade invokes on its own (grepped for below)."""
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    _run(PIPELINE, "init", str(bank))
    target = bank / "pipeline.yaml"
    target.write_text("custom: true\n", encoding="utf-8")

    forced = _run(PIPELINE, "init", "--force", str(bank))
    assert forced.returncode == 0, forced.stderr
    assert target.read_text(encoding="utf-8") != "custom: true\n"


def test_install_and_init_bank_never_touch_project_pipeline_yaml() -> None:
    """Neither `install.sh` (global skill install/upgrade) nor
    `scripts/mb-init-bank.sh` (`/mb init`) ever creates/overwrites a
    project's `<bank>/pipeline.yaml` directly — the only writer is the
    explicit, overwrite-guarded `mb-pipeline.sh init` (exercised above).
    `install.sh`/`mb-init-bank.sh` may still *mention* `pipeline.yaml` in
    doc/comment strings (e.g. describing how `/mb work` reads it), so this
    guards specifically against write-shaped patterns: invoking
    `mb-pipeline.sh` at all, or a `cp`/redirect whose destination path ends
    in `pipeline.yaml`.
    """
    write_dest_re = re.compile(r'(cp\s+\S+\s+\S*|[>]{1,2}\s*")\S*pipeline\.yaml')
    for script in (REPO_ROOT / "install.sh", REPO_ROOT / "scripts" / "mb-init-bank.sh"):
        text = script.read_text(encoding="utf-8")
        assert "mb-pipeline.sh" not in text, (
            f"{script.name} must not invoke mb-pipeline.sh — that would bypass/"
            "duplicate its own overwrite guard for <bank>/pipeline.yaml"
        )
        match = write_dest_re.search(text)
        assert match is None, (
            f"{script.name}: possible direct write to pipeline.yaml: {match.group(0)!r}"
        )
