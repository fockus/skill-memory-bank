"""Project quality settings: profile fields `quality`, `architecture` (list/custom), `discipline`
and their resolver (project-quality-settings Stage 1, proportional-effort Sprint 2 Stage 3b)."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from memory_bank_skill import key_rules, quality, rules_profile

REPO_ROOT = Path(__file__).resolve().parents[2]
PROFILE_CMD = REPO_ROOT / "scripts" / "mb-profile.sh"
CATALOG = key_rules.load_catalog()
OPENCODE_POINTER = "Details: `~/.config/opencode/skills/memory-bank/rules/RULES.md`."


def _codes(errors) -> list[str]:
    return [e.message.split(":")[0] for e in errors]


def _ids(resolved: dict) -> list[str]:
    return [r["id"] for r in resolved["rules"]]


def test_resolve_quality_no_profiles_returns_defaults() -> None:
    resolved = quality.resolve_quality(None, None)
    assert resolved["quality"] == {
        "tdd": "small+",
        "testing_trophy": "on",
        "coverage": {"enabled": False, "overall": 85, "core": 95, "infra": 70},
        "principles": {"solid": "on", "dry": "on", "kiss": "on", "yagni": "on"},
    }
    # Same three lines the catalog rendered by default before AGR-076 (defaults never shrink silently).
    assert resolved["architecture"] == {"names": ["clean", "fsd", "ddd"], "custom": None}
    assert resolved["discipline"] == "auto"
    assert set(resolved["sources"].values()) == {"default"}


def test_resolve_quality_project_overrides_user_per_key() -> None:
    user = {"quality": {"tdd": "on", "coverage": {"enabled": True, "overall": 80}, "principles": {"kiss": "off"}},
            "architecture": "hexagonal", "discipline": "strict"}
    project = {"quality": {"tdd": "off", "coverage": {"core": 90}, "principles": {"dry": "off"}},
               "architecture": ["modular-monolith", {"custom": "ports for every adapter"}]}
    resolved = quality.resolve_quality(user, project)
    q, src = resolved["quality"], resolved["sources"]
    assert q["tdd"] == "off" and src["quality.tdd"] == "project"
    assert q["coverage"] == {"enabled": True, "overall": 80, "core": 90, "infra": 70}
    assert src["quality.coverage.enabled"] == "user" and src["quality.coverage.core"] == "project"
    assert src["quality.coverage.infra"] == "default"
    assert q["principles"] == {"solid": "on", "dry": "off", "kiss": "off", "yagni": "on"}
    assert q["testing_trophy"] == "on" and src["quality.testing_trophy"] == "default"
    assert resolved["architecture"] == {"names": ["modular-monolith"], "custom": "ports for every adapter"}
    assert src["architecture"] == "project"
    assert resolved["discipline"] == "strict" and src["discipline"] == "user"


@pytest.mark.parametrize(
    ("value", "code"),
    [
        ({"tdd": "sometimes"}, "invalid_value"),
        ({"testing_trophy": True}, "invalid_value"),
        ({"principles": {"kiss": "maybe"}}, "invalid_value"),
        ({"principles": {"grasp": "on"}}, "unknown_key"),
        ({"surprise": 1}, "unknown_key"),
        ({"coverage": {"overall": 101}}, "coverage_out_of_range"),
        ({"coverage": {"infra": -1}}, "coverage_out_of_range"),
        ({"coverage": {"core": "95"}}, "invalid_value"),
        ({"coverage": {"enabled": "yes"}}, "invalid_value"),
        ([], "not_an_object"),
    ],
)
def test_validate_quality_invalid_value_reports_code(value, code: str) -> None:
    assert code in _codes(quality.validate_quality(value))


@pytest.mark.parametrize(
    ("value", "code"),
    [
        ("serverless-mesh", "unknown_architecture"),
        (["clean", "nope"], "unknown_architecture"),
        ([], "unknown_architecture"),
        ("custom", "custom_invalid"),
        ([{"custom": ""}], "custom_invalid"),
        ([{"custom": "two\nlines"}], "custom_invalid"),
    ],
)
def test_validate_architecture_invalid_reports_code(value, code: str) -> None:
    assert code in _codes(quality.validate_architecture(value))


@pytest.mark.parametrize("value", ["fsd", ["clean", "ddd"], ["hexagonal", {"custom": "CQRS on writes"}]])
def test_validate_architecture_list_and_custom_text_accepted(value) -> None:
    assert quality.validate_architecture(value) == []


def test_validate_profile_rejects_invalid_quality_architecture_discipline() -> None:
    profile = {"schema_version": 1, "scope": "project", "role": "backend", "stack": "generic",
               "architecture": "custom", "quality": {"coverage": {"overall": 150}}, "discipline": "loud"}
    codes = _codes(rules_profile.validate_profile(profile))
    assert {"custom_invalid", "coverage_out_of_range", "invalid_value"} <= set(codes)


def test_validate_profile_principle_in_key_rules_bucket_rejected() -> None:
    # Single source: the four principles are switched only through quality.principles.
    profile = {"key_rules": {"disabled": ["kiss"]}}
    assert _codes(key_rules.validate_key_rules(profile["key_rules"], CATALOG)) == ["principle_in_quality"]


def test_key_rules_principle_off_absent_from_resolved_block() -> None:
    user = key_rules.profile_layer({"quality": {"principles": {"kiss": "off", "yagni": "off"}}})
    project = key_rules.profile_layer({"quality": {"principles": {"yagni": "on"}}})
    ids = _ids(key_rules.resolve_key_rules(user, project, CATALOG))
    assert "kiss" not in ids and "yagni" in ids and "solid" in ids


def test_key_rules_locked_rule_still_refused() -> None:
    errors = key_rules.validate_key_rules({"disabled": ["fail-fast"]}, CATALOG)
    assert _codes(errors) == ["locked_rule"]


def test_render_block_strict_discipline_adds_iron_law_within_budget() -> None:
    defaults = key_rules.resolve_key_rules(None, None, CATALOG)
    calm = key_rules.render_block({**defaults, "discipline": "auto"}, OPENCODE_POINTER)
    strict = key_rules.render_block({**defaults, "discipline": "strict"}, OPENCODE_POINTER)
    for line in CATALOG["strict_lines"]:
        assert f"- {line}" in strict and line not in calm
    assert len(strict.encode("utf-8")) <= 3072


def _run(*args: str, cwd: Path, home: Path) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(PROFILE_CMD), *args], cwd=cwd, capture_output=True, text=True,
                          check=False, env={"HOME": str(home), "PATH": "/usr/bin:/bin:/opt/homebrew/bin"})


def test_cli_quality_json_merges_user_and_project(tmp_path: Path) -> None:
    home, bank = tmp_path / "home", tmp_path / "proj" / ".memory-bank"
    (home / ".claude" / "memory-bank").mkdir(parents=True)
    bank.mkdir(parents=True)
    (home / ".claude" / "memory-bank" / "rules-profile.json").write_text(
        json.dumps({"quality": {"tdd": "on"}}), encoding="utf-8")
    (bank / "rules-profile.json").write_text(
        json.dumps({"quality": {"coverage": {"enabled": True}}}), encoding="utf-8")
    proc = _run("quality", f"--mb={bank}", "--json", cwd=tmp_path, home=home)
    assert proc.returncode == 0, proc.stderr
    resolved = json.loads(proc.stdout)
    assert resolved["quality"]["tdd"] == "on" and resolved["quality"]["coverage"]["enabled"] is True
    text = _run("quality", f"--mb={bank}", cwd=tmp_path, home=home)
    assert "quality.tdd = on (user)" in text.stdout
    assert "quality.coverage.enabled = true (project)" in text.stdout


def test_cli_quality_invalid_profile_exits_2(tmp_path: Path) -> None:
    user = tmp_path / "user.json"
    user.write_text(json.dumps({"quality": {"coverage": {"overall": 200}}}), encoding="utf-8")
    proc = _run("quality", f"--user={user}", cwd=tmp_path, home=tmp_path)
    assert proc.returncode == 2
    assert "coverage_out_of_range" in proc.stderr


def test_cli_validate_catches_invalid_quality(tmp_path: Path) -> None:
    path = tmp_path / "rules-profile.json"
    path.write_text(json.dumps({"schema_version": 1, "scope": "user", "role": "backend", "stack": "generic",
                                "quality": {"tdd": "always"}}), encoding="utf-8")
    proc = _run("validate", str(path), cwd=tmp_path, home=tmp_path)
    assert proc.returncode == 2
    assert "invalid_value" in proc.stderr


@pytest.mark.parametrize("rule_id", ["tdd", "testing-trophy", "coverage", "architecture",
                                     "clean-architecture", "fsd", "mobile-udf"])
def test_validate_key_rules_profile_setting_ids_rejected(rule_id: str) -> None:
    # One place per setting: architecture/TDD/Trophy/coverage live in the profile, not key_rules.
    assert _codes(key_rules.validate_key_rules({"enabled": [rule_id]}, CATALOG)) == ["profile_setting"]


def test_dry_kiss_yagni_not_immutable() -> None:
    # AGR-077: on by default, switchable per principle.
    assert "dry-kiss-yagni" not in rules_profile.IMMUTABLE_RULES
    profile = {"schema_version": 1, "scope": "user", "role": "backend", "stack": "generic",
               "baseline": {"dry-kiss-yagni": False}}
    assert rules_profile.validate_profile(profile) == []


def test_render_project_rules_lists_settings_and_preset_rules() -> None:
    resolved = quality.resolve_quality(None, {"architecture": ["modular-monolith", {"custom": "ports"}],
                                              "quality": {"principles": {"kiss": "off"}}})
    block = quality.render_project_rules(resolved)
    assert block.startswith("<!-- mb-project-rules:start -->\n")
    assert block.endswith("<!-- mb-project-rules:end -->\n")
    assert "[block] explicit-module-boundaries" in block and "ports" in block
    assert "KISS: off" in block and "TDD: small+" in block and "Coverage: off" in block


def test_first_save_keeps_default_architecture_list(tmp_path: Path) -> None:
    # A new profile created by a non-architecture change must not shrink the default
    # architecture (clean, fsd, ddd) to the legacy single-name default.
    from memory_bank_skill import key_rules_edit

    path = tmp_path / "rules-profile.json"
    sel = key_rules_edit.Selection(key_rules.load_catalog(), {}, None)
    sel.quality = {"tdd": "off"}
    key_rules_edit.save(str(path), "user", sel)

    saved = json.loads(path.read_text(encoding="utf-8"))
    assert saved["architecture"] == quality.DEFAULT_ARCHITECTURE
    assert saved["quality"] == {"tdd": "off"}
