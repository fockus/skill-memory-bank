"""Profile field `key_rules` + resolver (key-rules-onboarding Stage 2)."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from memory_bank_skill import key_rules, rules_profile

REPO_ROOT = Path(__file__).resolve().parents[2]
PROFILE_CMD = REPO_ROOT / "scripts" / "mb-profile.sh"
CATALOG = key_rules.load_catalog()
# No plain catalog rule is off by default any more (coverage is a profile setting): flip one.
CATALOG = {**CATALOG, "rules": [{**r, "default": False} if r["id"] == "comments-why-only" else r
                                for r in CATALOG["rules"]]}
DEFAULT_OFF = "comments-why-only"
# Rows with a `source` always reach the settings step, which decides (key_rules.apply_settings).
DEFAULT_ON = [r["id"] for r in CATALOG["rules"] if r["default"] or "source" in r]
# Principles are toggled through quality.principles, not key_rules buckets.
OPTIONAL_ON = next(r["id"] for r in CATALOG["rules"]
                   if r["default"] and not r["locked"] and r["group"] != "principles" and "source" not in r)
LOCKED = next(r["id"] for r in CATALOG["rules"] if r["locked"])


def _ids(resolved: dict) -> list[str]:
    return [r["id"] for r in resolved["rules"]]


def _profile(**key_rules_field) -> dict:
    return {"schema_version": 1, "scope": "user", "role": "backend", "stack": "generic",
            "key_rules": key_rules_field}


def _run(*args: str, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(PROFILE_CMD), *args], cwd=cwd,
                          capture_output=True, text=True, check=False)


def test_resolve_key_rules_empty_profiles_returns_catalog_defaults() -> None:
    resolved = key_rules.resolve_key_rules(None, None, CATALOG)
    assert _ids(resolved) == DEFAULT_ON
    assert resolved["custom"] == []


def test_resolve_key_rules_user_disabled_rule_absent() -> None:
    resolved = key_rules.resolve_key_rules({"disabled": [OPTIONAL_ON]}, None, CATALOG)
    assert OPTIONAL_ON not in _ids(resolved)


def test_resolve_key_rules_project_reenables_user_disabled_rule() -> None:
    resolved = key_rules.resolve_key_rules({"disabled": [OPTIONAL_ON]}, {"enabled": [OPTIONAL_ON]}, CATALOG)
    assert _ids(resolved) == DEFAULT_ON


def test_resolve_key_rules_enabled_default_off_rule_keeps_catalog_order() -> None:
    resolved = key_rules.resolve_key_rules({"enabled": [DEFAULT_OFF]}, None, CATALOG)
    expected = [r["id"] for r in CATALOG["rules"] if r["id"] in DEFAULT_ON or r["id"] == DEFAULT_OFF]
    assert _ids(resolved) == expected


def test_resolve_key_rules_project_disables_user_enabled_rule() -> None:
    resolved = key_rules.resolve_key_rules({"enabled": [DEFAULT_OFF]}, {"disabled": [DEFAULT_OFF]}, CATALOG)
    assert DEFAULT_OFF not in _ids(resolved)


def test_resolve_key_rules_custom_ordered_user_then_project() -> None:
    resolved = key_rules.resolve_key_rules({"custom": ["u1", "u2"]}, {"custom": ["p1"]}, CATALOG)
    assert resolved["custom"] == ["u1", "u2", "p1"]


def test_validate_profile_disabling_locked_rule_reports_reason_code() -> None:
    errors = rules_profile.validate_profile(_profile(disabled=[LOCKED]))
    assert [(e.field, e.message.split(":")[0]) for e in errors] == [(f"key_rules.disabled.{LOCKED}", "locked_rule")]


@pytest.mark.parametrize("bucket", ["enabled", "disabled"])
def test_validate_profile_unknown_rule_id_named_in_error(bucket: str) -> None:
    errors = rules_profile.validate_profile(_profile(**{bucket: ["no-such-rule"]}))
    assert len(errors) == 1
    assert errors[0].message.startswith("unknown_rule:") and "no-such-rule" in errors[0].message


@pytest.mark.parametrize(
    ("value", "code"),
    [
        ({"custom": ["x" * 201]}, "custom_invalid"),
        ({"custom": ["two\nlines"]}, "custom_invalid"),
        ({"surprise": []}, "unknown_key"),
        ({"enabled": "solid"}, "not_a_list"),
        ([], "not_an_object"),
    ],
)
def test_validate_key_rules_malformed_field_rejected(value, code: str) -> None:
    errors = key_rules.validate_key_rules(value, CATALOG)
    assert errors and errors[0].message.startswith(f"{code}:")


def test_validate_profile_valid_key_rules_accepted() -> None:
    profile = _profile(enabled=[DEFAULT_OFF], disabled=[OPTIONAL_ON], custom=["x" * 200])
    assert rules_profile.validate_profile(profile) == []


def test_cli_validate_rejects_disabled_locked_rule(tmp_path: Path) -> None:
    path = tmp_path / "rules-profile.json"
    path.write_text(json.dumps(_profile(disabled=[LOCKED])), encoding="utf-8")
    proc = _run("validate", str(path), cwd=tmp_path)
    assert proc.returncode == 2
    assert "locked_rule" in proc.stderr and LOCKED in proc.stderr


def test_cli_key_rules_merges_user_and_project_scopes(tmp_path: Path) -> None:
    home, bank = tmp_path / "home", tmp_path / "proj" / ".memory-bank"
    user_dir = home / ".claude" / "memory-bank"
    user_dir.mkdir(parents=True)
    bank.mkdir(parents=True)
    (user_dir / "rules-profile.json").write_text(
        json.dumps({"key_rules": {"disabled": [OPTIONAL_ON], "custom": ["mine"]}}), encoding="utf-8")
    (bank / "rules-profile.json").write_text(
        json.dumps({"key_rules": {"enabled": [DEFAULT_OFF], "custom": ["ours"]}}), encoding="utf-8")
    proc = subprocess.run(["bash", str(PROFILE_CMD), "key-rules", f"--mb={bank}", "--json"],
                          cwd=tmp_path, env={"HOME": str(home), "PATH": "/usr/bin:/bin:/opt/homebrew/bin"},
                          capture_output=True, text=True, check=False)
    assert proc.returncode == 0, proc.stderr
    resolved = json.loads(proc.stdout)
    assert OPTIONAL_ON not in _ids(resolved) and DEFAULT_OFF in _ids(resolved)
    assert resolved["custom"] == ["mine", "ours"]


def test_cli_key_rules_invalid_profile_exits_2_naming_id(tmp_path: Path) -> None:
    user = tmp_path / "user.json"
    user.write_text(json.dumps({"key_rules": {"enabled": ["bogus-id"]}}), encoding="utf-8")
    proc = _run("key-rules", f"--user={user}", cwd=tmp_path)
    assert proc.returncode == 2
    assert "bogus-id" in proc.stderr
