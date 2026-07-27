"""The `layers` block of a spec — svp-contract-test-loop C1.

    read_spec_layers(requirements_path, pipeline_path) -> SpecLayers

    python3 -m memory_bank_skill.spec_layers --requirements PATH
                                             --pipeline PATH --json

The canonical owner of the block is the frontmatter of `requirements.md`, and
only that file: a triple has three files, so "the spec's frontmatter" would be
ambiguous. A `layers` key found in `design.md` or `tasks.md` is rejected before
anything else is resolved.

THREE DECISIONS WORTH KNOWING, each with a wrong-direction failure mode:

* **No block at all means LEGACY** — all three layers off, `source="legacy"`,
  and the new gates do not apply. The obvious default ("no block = everything
  on") would make every spec written before S8 invalid under S8's own gates,
  including S8's own spec, which has gated requirements and no block.
* **A layer switched off in an EXPLICIT block must say why.** `false` without a
  non-empty `<layer>_reason` is an error, so speed stays a recorded decision
  rather than a silently missing task. A layer that is off because the pipeline
  default says so owes nothing: the spec never made that decision.
* **A malformed pipeline default is loud, never silently enabled.** Quietly
  defaulting a broken config to "on" would hand the gates a layer set nobody
  chose — the failure shape where a check runs against nothing and reports
  success.

Reading NEVER writes. The parser normalises nothing on disk (NFR-002).
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

LAYER_KEYS = ("contract_first", "integration_tests", "e2e_tests")
SIBLINGS = ("design.md", "tasks.md")


class SpecLayersError(Exception):
    """code in {missing_reason, malformed_block, unknown_key, noncanonical_owner}."""

    def __init__(self, code: str, field: str = ""):
        super().__init__("%s:%s" % (code, field) if field else code)
        self.code = code
        self.field = field


@dataclass(frozen=True)
class SpecLayers:
    contract_first: bool
    integration_tests: bool
    e2e_tests: bool
    reasons: dict[str, str | None] = field(default_factory=dict)
    source: str = "legacy"

    def as_dict(self) -> dict:
        return {
            "contract_first": self.contract_first,
            "integration_tests": self.integration_tests,
            "e2e_tests": self.e2e_tests,
            "reasons": dict(self.reasons),
            "source": self.source,
        }


# ── frontmatter ─────────────────────────────────────────────────────────────


def _frontmatter_lines(text: str) -> list:
    """Lines between the opening `---` and the closing one; [] when there is none.

    "No frontmatter" and "frontmatter that never closes" are DIFFERENT answers
    and must not share one. Returning [] for both made a truncated or
    mis-edited block read as legacy — every layer gate switched off on a spec
    whose author was in the middle of declaring them, which is precisely the
    fail-open this module's docstring forbids. An unterminated block raises.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return []
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i]
    raise SpecLayersError("malformed_block", "frontmatter is opened but never closed")


def _scalar(raw: str):
    """`true`/`false` to bool, quoted text to str, anything else to raw str."""
    value = raw.strip()
    if value in ("true", "True"):
        return True
    if value in ("false", "False"):
        return False
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def _layers_block(front: list):
    """The `layers:` mapping from frontmatter lines, or None when absent.

    A hand parser rather than a YAML load, on purpose: the grammar is tiny and
    fixed, and this is the one reader whose answer decides whether the gates
    apply at all. Two YAML paths (PyYAML present / absent) that could disagree
    about that is the exact divergence C1 measured for the pipeline side.
    """
    start = None
    for i, line in enumerate(front):
        if line.strip() and not line[:1].isspace() and line.split(":", 1)[0].strip() == "layers":
            start = i
            break
    if start is None:
        return None

    block = {}
    for line in front[start + 1 :]:
        if not line.strip():
            continue
        if not line[:1].isspace():
            break
        key, sep, raw = line.strip().partition(":")
        if not sep:
            raise SpecLayersError("malformed_block", line.strip())
        block[key.strip()] = _scalar(raw)
    return block


def _sibling_owns_layers(spec_dir: Path) -> str | None:
    for name in SIBLINGS:
        path = spec_dir / name
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue  # an absent sibling is simply ignored
        try:
            block = _layers_block(_frontmatter_lines(text))
        except SpecLayersError:
            # A sibling with a broken frontmatter owns no `layers` block, so it
            # is not a canonical-owner violation. Letting its error escape here
            # would report requirements.md as malformed because design.md is —
            # a true refusal pointing at the wrong file.
            continue
        if block is not None:
            return name
    return None


# ── pipeline defaults ───────────────────────────────────────────────────────


def _pipeline_layers(pipeline_path: Path) -> dict:
    """`sdd.layers` from the pipeline config; {} when unset (REQ-012: all on)."""
    try:
        text = Path(pipeline_path).read_text(encoding="utf-8")
    except OSError:
        return {}
    cfg = None
    try:
        import yaml

        cfg = yaml.safe_load(text)
    except ImportError:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
        from mb_pipeline_minimal_yaml import minimal_pipeline_load

        cfg = minimal_pipeline_load(text)
    except Exception as exc:
        raise SpecLayersError("malformed_block", "pipeline") from exc

    layers = ((cfg or {}).get("sdd") or {}).get("layers")
    if layers is None:
        return {}
    if not isinstance(layers, dict):
        raise SpecLayersError("malformed_block", "sdd.layers")
    for key, value in layers.items():
        if key not in LAYER_KEYS:
            raise SpecLayersError("unknown_key", key)
        if not isinstance(value, bool):
            raise SpecLayersError("malformed_block", "sdd.%s" % key)
    return layers


# ── the resolver ────────────────────────────────────────────────────────────


def read_spec_layers(requirements_path, pipeline_path) -> SpecLayers:
    requirements_path = Path(requirements_path)
    spec_dir = requirements_path.parent

    # The canonical owner is checked FIRST — before defaults and before the
    # block's own validation — so a misplaced block is never masked by a second
    # error found in the legitimate one.
    intruder = _sibling_owns_layers(spec_dir)
    if intruder:
        raise SpecLayersError("noncanonical_owner", "%s:layers" % intruder)

    front = _frontmatter_lines(requirements_path.read_text(encoding="utf-8"))
    block = _layers_block(front)

    if block is None:
        # Legacy: never consults the pipeline, never demands a reason, and the
        # new gates do not apply to it.
        return SpecLayers(False, False, False, {key: None for key in LAYER_KEYS}, "legacy")

    for key in block:
        base = key[: -len("_reason")] if key.endswith("_reason") else key
        if base not in LAYER_KEYS:
            raise SpecLayersError("unknown_key", key)

    defaults = _pipeline_layers(Path(pipeline_path))

    values, reasons = {}, {}
    explicit = 0
    for key in LAYER_KEYS:
        if key in block:
            explicit += 1
            value = block[key]
            if not isinstance(value, bool):
                raise SpecLayersError("malformed_block", key)
            reason = block.get("%s_reason" % key)
            if value is False:
                # Owed only by the spec that made the decision.
                if not isinstance(reason, str) or not reason.strip():
                    raise SpecLayersError("missing_reason", key)
            values[key] = value
            reasons[key] = reason if isinstance(reason, str) and reason.strip() else None
        else:
            values[key] = bool(defaults.get(key, True))
            reasons[key] = None

    source = "spec" if explicit == len(LAYER_KEYS) else "pipeline"
    return SpecLayers(
        values["contract_first"], values["integration_tests"], values["e2e_tests"], reasons, source
    )


# ── CLI ─────────────────────────────────────────────────────────────────────


def main(argv=None) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="mb-spec-layers")
    parser.add_argument("--requirements", required=True)
    parser.add_argument("--pipeline", required=True)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    try:
        layers = read_spec_layers(Path(args.requirements), Path(args.pipeline))
    except SpecLayersError as exc:
        # Nothing on stdout: a caller that only reads stdout must not be able to
        # mistake a refusal for an empty-but-valid answer.
        sys.stderr.write("spec_layers_error=%s field=%s\n" % (exc.code, exc.field))
        return 1
    except OSError as exc:
        sys.stderr.write("spec_layers_error=malformed_block field=%s\n" % exc)
        return 2
    sys.stdout.write(json.dumps(layers.as_dict(), ensure_ascii=False, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
