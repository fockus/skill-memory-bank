"""The `## Quality DoD` block — one renderer, three receivers (C6/C5).

    python3 scripts/mb_quality_dod.py --rules-json PATH

Rendered from the canonical JSON of `scripts/mb-rules-resolve.sh`: the resolved
rule sources by PATH (never their text), the `review_rubric` bullets, and the
command of the existing rules checker.

WHY THIS IS A MODULE
────────────────────
Two callers need these exact bytes. `mb-sdd-layers-render.py` (C8) puts the
block into a spec's design.md at generation time; `mb-review.sh` (C6) hands it
to the reviewer at review time, and `commands/work.md` gives the same file to
the implementer and the judge. The entire contract is that all of them hold the
SAME sha256 — so a second renderer would not be duplication, it would be the
defect itself.

THE BLOCK IS STATIC ON PURPOSE
──────────────────────────────
`<touched-files-csv>` stays a literal parameter of the documented command
rather than being substituted per item. The moment per-item data enters the
block, the three copies stop matching and the byte-identity that makes the
criterion shared is gone. Per-item evidence travels separately, in the
payload's `## Prior evidence` section.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

RULES_KEYS = {"sources", "review_rubric", "fallback_used", "checker"}
SOURCE_KEYS = {"kind", "path"}


def load_rules(path: Path) -> dict:
    """The canonical JSON from `mb-rules-resolve.sh`, schema-checked."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("rules JSON must be an object")
    unknown = sorted(set(data) - RULES_KEYS)
    if unknown:
        raise ValueError("unknown key(s) in rules JSON: %s" % ", ".join(unknown))
    missing = sorted(RULES_KEYS - set(data))
    if missing:
        raise ValueError("missing key(s) in rules JSON: %s" % ", ".join(missing))
    if not isinstance(data["sources"], list) or not data["sources"]:
        raise ValueError("rules JSON `sources` must be a non-empty array")
    for entry in data["sources"]:
        if not isinstance(entry, dict) or set(entry) != SOURCE_KEYS:
            raise ValueError("each rules source needs exactly {kind, path}")
    if not isinstance(data["review_rubric"], list):
        raise ValueError("rules JSON `review_rubric` must be an array")
    if not isinstance(data["checker"], str) or not data["checker"]:
        raise ValueError("rules JSON `checker` must be a non-empty string")
    return data


def render_quality_dod(rules: dict) -> str:
    """Exactly one `## Quality DoD` section in the C5 format.

    Paths only, never the rules' text (REQ-015), and the sources sorted by path
    so the same resolve renders byte-identically (NFR-003) — that byte-identity
    is what lets implementer, reviewer and judge be given the same block.
    """
    lines = [
        "## Quality DoD",
        "",
        "Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):",
    ]
    for entry in sorted(rules["sources"], key=lambda e: e["path"]):
        lines.append("- [%s] %s" % (entry["kind"], entry["path"]))
    lines += ["", "Review rubric (from `pipeline.yaml:review_rubric`):"]
    lines += ["- %s" % bullet for bullet in rules["review_rubric"]]
    lines += [
        "",
        "Checker: `bash %s --files <touched-files-csv> --out json` — no violations"
        % rules["checker"],
        "on this item's touched files.",
        "",
    ]
    return "\n".join(lines)


def main(argv=None) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="mb-quality-dod", add_help=True)
    parser.add_argument("--rules-json", required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2
    try:
        rules = load_rules(Path(args.rules_json))
    except (ValueError, OSError) as exc:
        # Nothing on stdout: a caller that reads only stdout must not mistake a
        # refusal for an empty-but-valid block.
        sys.stderr.write("[quality-dod] %s\n" % exc)
        return 1
    sys.stdout.write(render_quality_dod(rules))
    return 0


if __name__ == "__main__":
    sys.exit(main())
