"""pipeline-presets-cost-tiers Stage 3 — cost tiers + per-role model resolution (AGR-074).

Resolution per role: CLI `--model` (item role only) ▸ `roles.<role>.model` ▸
`model_profiles[host][cost_tiers[cost][class]]` ▸ `inherit`. Cost: `--cost` ▸
`hosts.<host>.cost` ▸ `cost` ▸ `optimal`.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

REPO_ROOT = Path(__file__).resolve().parents[2]
WORK_PLAN = REPO_ROOT / "scripts" / "mb-work-plan.sh"
WORKFLOW = REPO_ROOT / "scripts" / "mb-workflow.sh"
VALIDATE = REPO_ROOT / "scripts" / "mb-pipeline-validate.sh"
DEFAULT = REPO_ROOT / "references" / "pipeline.default.yaml"


def _bank(tmp_path: Path, extra: str = "", stages: tuple[str, ...] = ("do A",)) -> tuple[Path, Path]:
    mb = tmp_path / ".memory-bank"
    (mb / "plans" / "done").mkdir(parents=True)
    (mb / "specs").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n", encoding="utf-8")
    (mb / "pipeline.yaml").write_text(DEFAULT.read_text(encoding="utf-8") + extra, encoding="utf-8")
    body = "".join(
        f"<!-- mb-stage:{n} -->\n## Stage {n}: {h}\n\n- ⬜ DoD bit\n\n"
        for n, h in enumerate(stages, 1))
    plan = mb / "plans" / "p.md"
    plan.write_text(
        "---\ntype: feature\ntopic: foo\nstatus: in-progress\n---\n\n# Plan\n\n" + body,
        encoding="utf-8")
    return mb, plan


def _items(mb: Path, plan: Path, *args: str, env: dict | None = None) -> list[dict]:
    r = subprocess.run(
        ["bash", str(WORK_PLAN), "--target", str(plan), "--mb", str(mb), *args],
        capture_output=True, text=True, check=False, env={**os.environ, **(env or {})})
    assert r.returncode == 0, r.stderr
    return [json.loads(x) for x in r.stdout.splitlines() if x.startswith("{")]


def _models(mb: Path, plan: Path, *args: str) -> dict[str, str]:
    """role → model for the item role plus the verifier/reviewer/judge steps."""
    item = _items(mb, plan, *args)[0]
    return {item["role"]: item["model"], **item["step_models"]}


# Stage headings that route to a role (mb-work-plan.sh ROLE_RULES).
ARCH = "architecture of the domain model"


def test_optimal_on_claude_code_puts_cheap_hands_and_expensive_eyes(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    item = _items(mb, plan, "--host", "claude-code")[0]
    assert (item["role"], item["model"], item["model_source"]) == ("developer", "sonnet", "profile")
    assert (item["cost"], item["host"]) == ("optimal", "claude-code")
    assert item["step_models"] == {"verifier": "sonnet", "reviewer": "opus", "judge": "opus"}
    arch = _items(*_bank(tmp_path / "a", stages=(ARCH,)), "--host", "claude-code")[0]
    assert (arch["role"], arch["model"]) == ("architect", "opus")


def test_premium_is_opus_everywhere(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    assert set(_models(mb, plan, "--host", "claude-code", "--cost", "premium").values()) == {"opus"}


def test_economy_is_sonnet_everywhere(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    assert set(_models(mb, plan, "--host", "claude-code", "--cost=economy").values()) == {"sonnet"}


def test_explicit_role_model_beats_the_profile(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    p = mb / "pipeline.yaml"
    p.write_text(p.read_text(encoding="utf-8").replace(
        "developer: { agent: mb-developer }", "developer: { agent: mb-developer, model: opus }"),
        encoding="utf-8")
    item = _items(mb, plan, "--host", "claude-code", "--cost", "economy")[0]
    assert (item["model"], item["model_source"]) == ("opus", "role")


def test_cli_model_beats_role_model_for_the_item(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    item = _items(mb, plan, "--host", "claude-code", "--model", "fable")[0]
    assert (item["model"], item["model_source"]) == ("fable", "cli")
    assert item["step_models"]["judge"] == "opus"


def test_cost_precedence_cli_over_host_over_top_level(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path, "cost: economy\nhosts:\n  claude-code: {cost: premium}\n")
    assert _items(mb, plan, "--host", "claude-code")[0]["cost"] == "premium"
    assert _items(mb, plan, "--host", "claude-code", "--cost", "optimal")[0]["cost"] == "optimal"
    assert _items(mb, plan, "--host", "codex")[0]["cost"] == "economy"


def test_unknown_host_without_profile_inherits(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    item = _items(mb, plan, "--host", "windsurf")[0]
    assert (item["model"], item["model_source"], item["discipline"]) == ("inherit", "inherit", "calm")
    assert item["step_models"]["judge"] == "inherit"


def test_host_is_auto_detected_from_mb_agent(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    env = {"MB_PIPELINE_HOST": "", "MB_AGENT": "claude-code"}
    assert _items(mb, plan, env=env)[0]["host"] == "claude-code"


def test_profile_missing_a_slot_inherits_with_a_warning(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path, "")
    p = mb / "pipeline.yaml"
    p.write_text(p.read_text(encoding="utf-8").replace(
        "  claude-code: {premium: opus, mid: sonnet}",
        "  claude-code: {premium: opus, mid: sonnet}\n  pi: {premium: openai/gpt-6-astra}"),
        encoding="utf-8")
    r = subprocess.run(["bash", str(WORK_PLAN), "--target", str(plan), "--mb", str(mb),
                        "--host", "pi"], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stderr
    item = json.loads(r.stdout.splitlines()[0])
    assert (item["model"], item["model_source"]) == ("inherit", "inherit")
    assert item["step_models"]["judge"] == "openai/gpt-6-astra"
    assert "model_profiles.pi.mid" in r.stderr


def test_resolved_haiku_role_override_is_strict(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    p = mb / "pipeline.yaml"
    p.write_text(p.read_text(encoding="utf-8").replace(
        "developer: { agent: mb-developer }", "developer: { agent: mb-developer, model: haiku }"),
        encoding="utf-8")
    item = _items(mb, plan, "--host", "claude-code")[0]
    assert (item["model"], item["discipline"]) == ("haiku", "strict")


def test_this_repo_keeps_its_explicit_models(tmp_path: Path) -> None:
    """Explicit role models win; roles without one keep the legacy developer fallback."""
    bank = REPO_ROOT / ".memory-bank"
    mb, plan = _bank(tmp_path, stages=("do A", ARCH, "research the option matrix"))
    (mb / "pipeline.yaml").write_text((bank / "pipeline.yaml").read_text(encoding="utf-8"),
                                      encoding="utf-8")
    items = _items(mb, plan, "--host", "claude-code")
    assert [(i["role"], i["model"], i["model_source"]) for i in items] == [
        ("developer", "opus", "role"), ("architect", "opus", "role"), ("researcher", "opus", "role")]
    assert items[0]["step_models"]["reviewer"] == "gpt-5.6-sol"
    assert items[0]["step_models"]["judge"] == "opus"


def test_host_preset_and_verify_apply_to_the_workflow(tmp_path: Path) -> None:
    mb, _plan = _bank(tmp_path, "hosts:\n  codex: {preset: governed, verify: stage}\n")
    r = subprocess.run(["bash", str(WORKFLOW), "--mb", str(mb), "--host", "codex", "--json"],
                       capture_output=True, text=True, check=False)
    out = json.loads(r.stdout)
    assert (out["name"], out["verify_cadence"]) == ("governed", "stage")
    r = subprocess.run(["bash", str(WORKFLOW), "--mb", str(mb), "--host", "claude-code", "--json"],
                       capture_output=True, text=True, check=False)
    assert json.loads(r.stdout)["name"] == "medium"


@pytest.mark.parametrize(
    ("extra", "needle"),
    [
        ("cost: luxury\n", "cost"),
        ("hosts:\n  codex: {cost: luxury}\n", "hosts.codex.cost"),
        ("hosts:\n  codex: {verify: weekly}\n", "hosts.codex.verify"),
        ("hosts:\n  codex: {preset: nonesuch}\n", "hosts.codex.preset"),
        ("hosts:\n  codex: {colour: red}\n", "hosts.codex"),
    ],
)
def test_validate_rejects_bad_cost_and_host_settings(tmp_path: Path, extra: str, needle: str) -> None:
    mb, _ = _bank(tmp_path, extra)
    r = subprocess.run(["bash", str(VALIDATE), str(mb / "pipeline.yaml")],
                       capture_output=True, text=True, check=False)
    assert r.returncode == 1
    assert needle in r.stderr


@pytest.mark.parametrize(
    ("old", "new", "needle"),
    [
        ("  economy:", "  luxury:", "cost_tiers.luxury"),
        ("judge: premium}", "judge: premium, wizard: mid}", "wizard"),
        ("implementer: mid,", "implementer: cheapest,", "cheapest"),
        ("{premium: opus, mid: sonnet}", "{premium: opus}", "model_profiles.claude-code"),
        ("{premium: opus, mid: sonnet}", "{premium: opus, mid: haiku}", "strict_models"),
    ],
)
def test_validate_rejects_bad_tiers_and_profiles(tmp_path: Path, old: str, new: str, needle: str) -> None:
    mb, _ = _bank(tmp_path)
    p = mb / "pipeline.yaml"
    text = p.read_text(encoding="utf-8")
    assert old in text
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    r = subprocess.run(["bash", str(VALIDATE), str(p)], capture_output=True, text=True, check=False)
    assert r.returncode == 1
    assert needle in r.stderr


def test_validate_rejects_pi_aliases(tmp_path: Path) -> None:
    """On Pi `opus`/`sonnet` collapse to the parent model (AGR-056): profiles need provider/id."""
    mb, _ = _bank(tmp_path)
    p = mb / "pipeline.yaml"
    p.write_text(p.read_text(encoding="utf-8").replace(
        "  claude-code: {premium: opus, mid: sonnet}",
        "  claude-code: {premium: opus, mid: sonnet}\n  pi: {premium: opus, mid: sonnet}"),
        encoding="utf-8")
    r = subprocess.run(["bash", str(VALIDATE), str(p)], capture_output=True, text=True, check=False)
    assert r.returncode == 1
    assert "provider/id" in r.stderr


def test_validate_without_pyyaml_still_sees_the_cost_blocks(tmp_path: Path) -> None:
    mb, _ = _bank(tmp_path, "hosts:\n  codex: {cost: luxury}\n")
    code = (
        "import builtins, runpy, sys\n"
        "real = builtins.__import__\n"
        "def fake(name, *a, **k):\n"
        "    if name == 'yaml': raise ImportError\n"
        "    return real(name, *a, **k)\n"
        "builtins.__import__ = fake\n"
        f"sys.path.insert(0, {str(REPO_ROOT / 'scripts')!r})\n"
        f"runpy.run_path({str(REPO_ROOT / 'scripts' / 'mb_pipeline_validate_core.py')!r})\n"
    )
    r = subprocess.run(["python3", "-c", code], capture_output=True, text=True, check=False,
                       env={**os.environ, "MB_PIPELINE_PATH": str(mb / "pipeline.yaml")})
    assert r.returncode == 1
    assert "hosts.codex.cost" in r.stderr
