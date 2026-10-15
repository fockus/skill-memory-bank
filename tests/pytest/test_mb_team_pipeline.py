"""Layered track pipeline resolver (C2) and the closed prompt vocabulary.

Layers, later wins: preset(size) -> team.overrides -> team attrs (init) ->
track attrs -> prompt. Every resolved key records the layer that set it.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
RESOLVER = SCRIPTS / "mb_team_pipeline.py"
BUNDLED = REPO_ROOT / "references" / "pipeline.default.yaml"


def _run(*args: str):
    return subprocess.run([sys.executable, str(RESOLVER), *args], capture_output=True, text=True)


def _resolve(pipeline: Path, *args: str):
    return _run("resolve", "--pipeline", str(pipeline), "--json", *args)


def _ok(pipeline: Path, *args: str) -> dict:
    r = _resolve(pipeline, *args)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def _yaml_fields(flat: dict, indent: int) -> str:
    """Render flat keys (`models.lens.security`) as nested block YAML."""
    tree: dict = {}
    for key, value in flat.items():
        node = tree
        parts = key.split(".")
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value

    def emit(node: dict, depth: int) -> str:
        out = ""
        for k, v in node.items():
            pad = " " * depth
            if isinstance(v, dict):
                out += f"{pad}{k}:\n" + emit(v, depth + 2)
            elif isinstance(v, list):
                out += f"{pad}{k}: [{', '.join(v)}]\n"
            else:
                out += f"{pad}{k}: {v}\n"
        return out

    return emit(tree, indent)


# Base preset with every step on, so every model key is part of the output.
BASE = {"mode": "work", "tdd": "required", "verifier": "plan-verifier", "review": "lenses",
        "lenses": ["logic", "security"], "effort": "medium", "models.executor": "sonnet"}

LAYERS = ("preset:large", "override", "team", "track", "prompt")
FLAG = {"team": "--team", "track": "--attr", "prompt": "--prompt"}

# Two alternating values per key; layer i gets VALUES[key][i % 2].
VALUES = {
    "tdd": ("optional", "required"),
    "verifier": ("none", "plan-verifier"),
    "review": ("single", "lenses"),
    "lenses": (["tests"], ["logic", "scalability"]),
    "effort": ("high", "low"),
    "models.executor": ("opus", "claude-sonnet-x"),
    "models.verifier": ("opus", "claude-sonnet-x"),
    "models.reviewer": ("opus", "claude-sonnet-x"),
    "models.lead": ("opus", "claude-sonnet-x"),
    "models.lenses": ("opus", "claude-sonnet-x"),
    "models.lens.security": ("opus", "claude-sonnet-x"),
}


def _cli_value(value) -> str:
    return ",".join(value) if isinstance(value, list) else value


def _matrix_pipeline(tmp_path: Path, key: str, upto: int) -> tuple[Path, list[str]]:
    preset = dict(BASE)
    if key == "models.reviewer":
        preset["review"] = "single"
    preset[key] = VALUES[key][0]
    text = "team:\n  presets:\n    large:\n" + _yaml_fields(preset, 6)
    if upto >= 1:
        text += "  overrides:\n" + _yaml_fields({key: VALUES[key][1]}, 4)
    path = tmp_path / "pipeline.yaml"
    path.write_text(text, encoding="utf-8")
    args = ["--size", "large", "--source", "plans/x.md"]
    for i in range(2, upto + 1):
        args += [FLAG[LAYERS[i]], f"{key}={_cli_value(VALUES[key][i % 2])}"]
    return path, args


def _lookup(pipeline: dict, key: str):
    node = pipeline
    for part in key.split("."):
        node = node[part]
    return node


@pytest.mark.parametrize("upto", range(len(LAYERS)), ids=LAYERS)
@pytest.mark.parametrize("key", sorted(VALUES))
def test_layer_matrix_later_layer_wins_with_provenance(tmp_path: Path, key: str, upto: int) -> None:
    path, args = _matrix_pipeline(tmp_path, key, upto)
    out = _ok(path, *args)
    expected = VALUES[key][upto % 2]
    assert _lookup(out["pipeline"], key) == expected
    assert out["provenance"][key] == LAYERS[upto]


def test_every_resolved_key_has_provenance(tmp_path: Path) -> None:
    out = _ok(BUNDLED, "--size", "extra", "--source", "plans/x.md")
    keys = {"size", "mode", "work", "tdd", "verifier", "review", "lenses", "effort",
            "models.executor", "models.verifier", "models.lead", "models.lenses"}
    assert keys <= set(out["provenance"])
    assert out["provenance"]["size"] == "track"
    assert out["provenance"]["models.verifier"] == "preset:extra"
    small = _ok(BUNDLED, "--size", "small", "--prompt", "review=single")
    assert small["provenance"]["models.reviewer"] == "default"  # no layer set it: host profile
    assert small["pipeline"]["models"]["reviewer"] == "opus"


def test_size_layers_default_team_track_prompt(tmp_path: Path) -> None:
    path = tmp_path / "pipeline.yaml"
    path.write_text("team:\n  default_size: small\n", encoding="utf-8")
    assert _ok(path)["provenance"]["size"] == "default"
    out = _ok(path, "--team", "size=standard")
    assert (out["pipeline"]["size"], out["provenance"]["size"]) == ("standard", "team")
    out = _ok(path, "--team", "size=standard", "--size", "small")
    assert (out["pipeline"]["size"], out["provenance"]["size"]) == ("small", "track")
    out = _ok(path, "--size", "small", "--prompt", "size=standard")
    assert (out["pipeline"]["size"], out["provenance"]["mode"]) == ("standard", "preset:standard")


@pytest.mark.parametrize(
    ("size", "mode", "verifier", "review"),
    [("small", "work", "none", "none"),
     ("standard", "work", "plan-verifier", "none"),
     ("large", "work", "plan-verifier", "lenses"),
     ("extra", "work", "plan-verifier", "lenses")],
)
def test_bundled_presets_follow_agr_097(size: str, mode: str, verifier: str, review: str) -> None:
    p = _ok(BUNDLED, "--size", size, "--source", "plans/x.md")["pipeline"]
    assert (p["mode"], p["tdd"], p["verifier"], p["review"]) == (mode, "required", verifier, review)


def test_review_lenses_shorthand_and_quality_alias() -> None:
    out = _ok(BUNDLED, "--size", "standard", "--prompt", "review=lenses:logic,quality")
    assert out["pipeline"]["review"] == "lenses"
    assert out["pipeline"]["lenses"] == ["logic", "code_rules"]
    assert out["provenance"]["lenses"] == out["provenance"]["review"] == "prompt"


def test_work_mode_needs_no_source_and_defaults_to_orchestrated() -> None:
    out = _ok(BUNDLED, "--size", "standard")
    assert (out["pipeline"]["mode"], out["pipeline"]["work"], out["provenance"]["work"]) == (
        "work", "orchestrated", "preset:standard")


@pytest.mark.parametrize(
    ("arg", "named"),
    [("colour=red", "colour"), ("tdd=maybe", "tdd"), ("review=lenses:logic,vibes", "vibes"),
     ("work=heavy", "work"), ("models.janitor=opus", "models.janitor"), ("effort", "effort")],
)
def test_bad_attribute_exits_2_naming_it(arg: str, named: str) -> None:
    r = _resolve(BUNDLED, "--size", "standard", "--attr", arg)
    assert r.returncode == 2
    assert named in r.stderr


def test_slots_resolve_to_host_models() -> None:
    out = _ok(BUNDLED, "--size", "standard", "--host", "codex", "--prompt", "models.executor=premium")
    assert out["pipeline"]["models"]["executor"] == "gpt-6-astra"
    out = _ok(BUNDLED, "--size", "standard", "--host", "claude-code")
    assert out["pipeline"]["models"] == {"executor": "sonnet", "verifier": "sonnet"}
    out = _ok(BUNDLED, "--size", "standard", "--prompt", "models.executor=claude-opus-5-5")
    assert out["pipeline"]["models"]["executor"] == "claude-opus-5-5"


def test_prompt_lowering_below_preset_is_accepted_with_warning() -> None:
    out = _ok(BUNDLED, "--size", "standard", "--prompt", "verifier=none")
    assert out["pipeline"]["verifier"] == "none"
    assert any("verifier" in w and "preset" in w for w in out["warnings"])


# ── prompt vocabulary ─────────────────────────────────────────────────────────


def _parse(text: str):
    r = _run("parse-prompt", "--text", text, "--json")
    return r.returncode, json.loads(r.stdout)


def test_prompt_example_maps_to_closed_keys() -> None:
    code, out = _parse("трек A крупный, ревью одним ревьюером на opus, исполнитель opus")
    assert code == 0
    assert out == {"set": {"size": "large", "review": "single", "models.reviewer": "opus",
                           "models.executor": "opus"}, "questions": []}


@pytest.mark.parametrize(
    ("text", "expected"),
    [("через /mb work, оркестратор ведёт", {"mode": "work", "work": "orchestrated"}),
     ("без TDD, без верификатора", {"tdd": "optional", "verifier": "none"}),
     ("линзами [logic, security], effort high", {"review": "lenses", "lenses": "logic,security",
                                                "effort": "high"}),
     ("без ревью, думай глубже", {"review": "none", "effort": "high"})],
)
def test_prompt_phrases(text: str, expected: dict) -> None:
    code, out = _parse(text)
    assert (code, out["set"], out["questions"]) == (0, expected, [])


@pytest.mark.parametrize(
    "text",
    ["ревью построже", "без ревью, линзами", "модель получше", "линзами [logic, vibes]",
     "на opus или sonnet", "облегчённо", "напрямую"],
)
def test_ambiguous_prompt_returns_question_not_guess(text: str) -> None:
    code, out = _parse(text)
    assert code == 3
    assert out["questions"]
