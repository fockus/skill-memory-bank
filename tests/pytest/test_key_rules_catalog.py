"""Contract tests for rules/key-rules.json — the key-rules catalog (key-rules-onboarding Stage 1)."""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
from _skill_guide_checks import _headings, github_slug

from memory_bank_skill.key_rules import render_block, resolve_effective
from memory_bank_skill.quality import ARCHITECTURES, load_architecture_preset

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG = REPO_ROOT / "rules" / "key-rules.json"
RULES_MD = REPO_ROOT / "rules" / "RULES.md"

REQUIRED_GROUPS = ("principles", "minimal-code", "architecture", "tests", "process")
KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
DEFAULT_BUDGET_BYTES = 3072


@pytest.fixture(scope="module")
def catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def test_catalog_schema_valid(catalog: dict) -> None:
    assert catalog["schema_version"] == 1
    assert set(catalog) == {"schema_version", "groups", "rules", "strict_lines"}
    assert 3 <= len(catalog["strict_lines"]) <= 5
    group_ids = [g["id"] for g in catalog["groups"]]
    assert all(set(g) == {"id", "title"} and g["title"] for g in catalog["groups"])
    for rule in catalog["rules"]:
        assert {"id", "group", "text", "default", "locked", "ref"} <= set(rule), rule
        assert set(rule) <= {"id", "group", "text", "default", "locked", "ref", "source", "variants"}, rule
        assert rule["group"] in group_ids, rule["id"]
        assert isinstance(rule["default"], bool) and isinstance(rule["locked"], bool)
        assert rule["ref"] is None or isinstance(rule["ref"], str)


def test_catalog_ids_unique_kebab_case(catalog: dict) -> None:
    ids = [r["id"] for r in catalog["rules"]]
    assert len(ids) == len(set(ids))
    assert [i for i in ids if not KEBAB.match(i)] == []


def test_catalog_text_single_line_within_160(catalog: dict) -> None:
    bad = [r["id"] for r in catalog["rules"]
           if not r["text"].strip() or "\n" in r["text"] or len(r["text"]) > 160]
    assert bad == []


def test_catalog_refs_resolve_to_rules_md_headings(catalog: dict) -> None:
    slugs = {github_slug(h) for h in _headings(RULES_MD.read_text(encoding="utf-8"))}
    dangling = [(r["id"], r["ref"]) for r in catalog["rules"] if r["ref"] and r["ref"] not in slugs]
    assert dangling == []


def test_catalog_required_groups_present_and_populated(catalog: dict) -> None:
    used = {r["group"] for r in catalog["rules"]}
    assert set(REQUIRED_GROUPS) <= {g["id"] for g in catalog["groups"]}
    assert set(REQUIRED_GROUPS) <= used


def test_catalog_principles_on_and_locked_set(catalog: dict) -> None:
    # AGR-077: SOLID/DRY/KISS/YAGNI are on by default but switchable (via quality.principles).
    principles = [r for r in catalog["rules"] if r["group"] == "principles"]
    assert principles and all(r["default"] for r in principles)
    locked = {r["id"] for r in catalog["rules"] if r["locked"]}
    assert locked == {"fail-fast", "no-placeholders", "root-cause", "effort-tiers"}


def test_catalog_proportional_effort_rules_present(catalog: dict) -> None:
    # AGR-067/070/071: tiered effort, behaviour tests, minimal docs, targeted checks.
    rules = {r["id"]: r for r in catalog["rules"]}
    for rid, group in {"effort-tiers": "process", "targeted-verification": "process",
                       "docs-minimal": "process", "test-behavior": "tests"}.items():
        assert rules[rid]["group"] == group and rules[rid]["default"], rid
    assert rules["effort-tiers"]["locked"]
    assert "evidence" in rules["targeted-verification"]["text"].lower()
    assert "mock" in rules["test-behavior"]["text"].lower()
    # Absorbed: an unconditional plan, evidence and naming rule would contradict the tiers.
    assert not {"plan-first", "evidence-before-done", "test-naming-aaa"} & set(rules)


def test_catalog_architecture_and_quality_lines_come_from_the_profile(catalog: dict) -> None:
    # AGR-076: one place per setting — no independent architecture/TDD/Trophy/coverage toggles.
    sources = {r["id"]: r.get("source") for r in catalog["rules"]}
    assert [r["id"] for r in catalog["rules"] if r["group"] == "architecture"] == ["architecture"]
    assert sources["architecture"] == "architecture"
    assert sources["tdd"] == "quality.tdd"
    assert sources["testing-trophy"] == "quality.testing_trophy"
    assert sources["coverage"] == "quality.coverage"
    assert not {"clean-architecture", "fsd", "ddd-folders", "mobile-udf", "backend-macro"} & set(sources)


def test_catalog_coverage_off_by_default() -> None:
    ids = [r["id"] for r in resolve_effective(None, None)["rules"]]
    assert "coverage" not in ids and "tdd" in ids and "testing-trophy" in ids


def test_catalog_has_comments_and_ponytail_ladder_rules(catalog: dict) -> None:
    texts = [r["text"].lower() for r in catalog["rules"] if r["group"] == "minimal-code"]
    assert any("comment" in t and "why" in t for t in texts)
    assert any("stdlib" in t and "already" in t and "one line" in t for t in texts)
    assert any("ponytail:" in t for t in texts)


@pytest.mark.parametrize("discipline", ["auto", "strict"])
def test_catalog_default_render_within_budget(discipline: str) -> None:
    # Whole managed block, markers and the longest host pointer included — not just the rule lines.
    resolved = resolve_effective(None, {"discipline": discipline})
    pointer = "Details: `~/.config/opencode/skills/memory-bank/rules/RULES.md`."
    rendered = render_block(resolved, pointer)
    assert len(rendered.encode("utf-8")) <= DEFAULT_BUDGET_BYTES


def test_catalog_widest_architecture_render_within_budget() -> None:
    # Three longest one-liners (the default has three) + coverage on + strict: inside the budget.
    names = sorted(ARCHITECTURES, key=lambda n: -len(load_architecture_preset(n)["one_liner"].encode()))[:3]
    project = {"architecture": names, "discipline": "strict",
               "quality": {"tdd": "small+", "coverage": {"enabled": True}}}
    rendered = render_block(resolve_effective(None, project),
                            "Details: `~/.config/opencode/skills/memory-bank/rules/RULES.md`.")
    assert len(rendered.encode("utf-8")) <= DEFAULT_BUDGET_BYTES


def test_architecture_presets_have_one_liner_for_key_rules() -> None:
    for name in ARCHITECTURES:
        line = load_architecture_preset(name)["one_liner"]
        assert line.strip() and "\n" not in line and len(line) <= 110, name


def test_default_architecture_lines_keep_clean_fsd_ddd_folders() -> None:
    texts = [r["text"] for r in resolve_effective(None, None)["rules"] if r["id"] == "architecture"]
    assert [t.split(":", 1)[0] for t in texts] == ["Clean Architecture", "FSD (frontend)", "DDD folders"]
    assert "bounded context in every layer" in texts[2] and "single-file folders" in texts[2]
