"""Scaffold compatibility (C7) + v2 template contract (svp-sdd-core Task 6).

Two concerns:
  1. `scripts/mb-sdd.sh` stays a byte-identical scaffold-only writer, and
     `/mb sdd --scaffold-only` is documented as the alias that selects it — the
     generation pipeline must NOT call the writer before the D-35 gate.
  2. `references/templates.md` carries the v2 task block (anchored `**Eval:**`,
     `**Scope:**`, `**Budget:**`, bare `**Role:**`), the C9 seam block, a
     structural-Eval sample, and the waiver form (non-gated only).

`references/templates.md` is owned by Track A (Track C ships the block for the
orchestrator to land), so `test_templates_carry_v2_block` — the Eval anchor —
stays RED until that block lands.
"""

from __future__ import annotations

import pathlib
import subprocess

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SDD = (REPO_ROOT / "commands" / "sdd.md").read_text(encoding="utf-8")
MB_SDD = REPO_ROOT / "scripts" / "mb-sdd.sh"
TEMPLATES = (REPO_ROOT / "references" / "templates.md").read_text(encoding="utf-8")


def _scaffold(bank: pathlib.Path, force: bool = False) -> dict[str, str]:
    args = ["bash", str(MB_SDD)]
    if force:
        args.append("--force")
    args += ["demo", str(bank)]
    subprocess.run(args, check=True, capture_output=True, text=True)
    spec = bank / "specs" / "demo"
    return {p.name: p.read_text(encoding="utf-8") for p in sorted(spec.glob("*.md"))}


def test_scaffold_writer_creates_triple(tmp_path: pathlib.Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    files = _scaffold(bank)
    assert set(files) == {"requirements.md", "design.md", "tasks.md"}


def test_scaffold_writer_byte_identical_across_runs(tmp_path: pathlib.Path) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    first = _scaffold(bank)
    second = _scaffold(bank, force=True)
    assert first == second, "scaffold writer must be deterministic / byte-identical"


def test_scaffold_only_alias_documented() -> None:
    # /mb sdd --scaffold-only selects the same raw writer (C7 boundary).
    assert "--scaffold-only" in SDD
    assert "scaffold" in SDD.lower() and "mb-sdd.sh" in SDD


def test_pipeline_defers_scaffold_writer_until_d35() -> None:
    low = SDD.lower()
    assert "does not call the scaffold writer before" in low or (
        "scaffold" in low and "before the d-35 gate" in low
    )


def test_templates_carry_v2_block() -> None:
    # v2 task block: anchored Eval + Scope + Budget + bare Role guidance.
    assert "**Eval:**" in TEMPLATES
    assert "output~:" in TEMPLATES or "exit:" in TEMPLATES
    assert "**Scope:**" in TEMPLATES
    assert "**Budget:**" in TEMPLATES
    assert "bare" in TEMPLATES.lower() and "role" in TEMPLATES.lower()
    # C9 seam block.
    assert "**Seams:**" in TEMPLATES
    assert "**Seam rationale:**" in TEMPLATES
    # structural-Eval sample for a docs/config task.
    assert "structural" in TEMPLATES.lower()
    # waiver form, marked non-gated only.
    assert "waiver:" in TEMPLATES
    assert "non-gated" in TEMPLATES.lower()
