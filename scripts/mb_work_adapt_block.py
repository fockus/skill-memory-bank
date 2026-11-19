"""Input parsing for mb_work_adapt.py: the ``complexity_escalation`` block of an implementer
report (a normalized block out, ValueError when invalid) and the scope-guard path matching.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from mb_pipeline_minimal_yaml import parse_nested_block  # noqa: E402

_KEY_RE = re.compile(r"^(\s*)complexity_escalation:\s*$")


def _files(value) -> list[str]:
    parts = value.split(",") if isinstance(value, str) else value if isinstance(value, list) else []
    return [str(p).strip().strip("`").strip() for p in parts if str(p).strip().strip("`").strip()]


def normalize_subitems(raw) -> list[dict]:
    """2-5 sub-items, each with a title and a non-empty Files list; ValueError otherwise."""
    if not isinstance(raw, list) or not 2 <= len(raw) <= 5:
        n = len(raw) if isinstance(raw, list) else 0
        raise ValueError(f"proposed_subitems must hold 2-5 sub-items (got {n})")
    out = []
    for idx, item in enumerate(raw, 1):
        if not isinstance(item, dict) or not str(item.get("title") or "").strip():
            raise ValueError(f"sub-item {idx} needs a non-empty title")
        files = _files(item.get("Files", item.get("files")))
        if not files:
            raise ValueError(f"sub-item {idx} needs a non-empty Files list")
        out.append({"title": str(item["title"]).strip(), "files": files})
    return out


def _yaml_block(text: str):
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = _KEY_RE.match(line)
        if not m:
            continue
        base = len(m.group(1))
        body = []
        for nxt in lines[i + 1 :]:
            if nxt.strip().startswith("```") or (
                nxt.strip() and len(nxt) - len(nxt.lstrip()) <= base
            ):
                break
            body.append(nxt[base:])
        src = "\n".join(["complexity_escalation:", *body])
        try:
            import yaml  # type: ignore

            return (yaml.safe_load(src) or {}).get("complexity_escalation")
        except ImportError:
            return parse_nested_block(src.splitlines(), "complexity_escalation")
    return None


def _json_block(text: str):
    decoder = json.JSONDecoder()
    for m in re.finditer(r"\{", text):
        try:
            obj, _ = decoder.raw_decode(text, m.start())
        except ValueError:
            continue
        if isinstance(obj, dict) and "complexity_escalation" in obj:
            return obj["complexity_escalation"]
    return None


def parse_escalation(text: str):
    """Return the normalized block, None when the report carries none; ValueError if invalid."""
    block = (
        _yaml_block(text)
        if any(_KEY_RE.match(ln) for ln in text.splitlines())
        else _json_block(text)
    )
    if block is None:
        return None
    if not isinstance(block, dict):
        raise ValueError("complexity_escalation must be a mapping")
    for key in ("reason", "estimate"):
        if not str(block.get(key) or "").strip():
            raise ValueError(f"complexity_escalation.{key} is required")
    return {
        "reason": str(block["reason"]).strip(),
        "estimate": str(block["estimate"]).strip(),
        "proposed_subitems": normalize_subitems(block.get("proposed_subitems")),
    }


def _scope_re(entry: str):
    """Declared Files entry → regex: exact path, `dir/**`, or `*` inside one segment."""
    entry = entry.strip().strip("`").strip()
    if entry.endswith("/"):
        entry += "**"
    head, deep = (entry[:-3], True) if entry.endswith("/**") else (entry, False)
    rx = "[^/]*".join(re.escape(part) for part in head.split("*"))
    return re.compile(rx + ("/.+" if deep else "") + r"\Z")


def _split_top(csv: str) -> list[str]:
    parts, depth, cur = [], 0, ""
    for ch in csv:
        depth += (ch == "{") - (ch == "}")
        if ch == "," and depth <= 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    return [*parts, cur]


def _braces(entry: str) -> list[str]:
    m = re.search(r"\{([^{}]*)\}", entry)
    if not m:
        return [entry]
    return [
        x
        for alt in m.group(1).split(",")
        for x in _braces(entry[: m.start()] + alt + entry[m.end() :])
    ]


def parse_declared(csv: str) -> list[str] | None:
    """Files csv -> path/glob entries (brace groups expanded); None when an entry is free text."""
    out = []
    for raw in _split_top(csv):
        entry = raw.strip().strip("`").strip()
        if not entry:
            continue
        if re.search(r"\s", entry):
            return None
        out += _braces(entry)
    return out or None


def scope_violations(declared: list[str], changed: list[str]) -> list[str]:
    pats = [_scope_re(d) for d in declared if d.strip()]
    return sorted({c for c in changed if c and not any(p.match(c) for p in pats)})


def read_changed(spec: str) -> list[str]:
    text = sys.stdin.read() if spec == "-" else pathlib.Path(spec).read_text(encoding="utf-8")
    return [ln.strip() for ln in text.splitlines() if ln.strip()]


def parse_cli(file: str) -> int:
    """`parse` subcommand body: 0 = block printed, 1 = no block, 3 = invalid block."""
    text = pathlib.Path(file).read_text(encoding="utf-8") if file else sys.stdin.read()
    try:
        block = parse_escalation(text)
    except ValueError as exc:
        print(f"[adapt] invalid complexity_escalation: {exc}", file=sys.stderr)
        return 3
    if block is None:
        print("[adapt] no complexity_escalation block", file=sys.stderr)
        return 1
    print(json.dumps(block, ensure_ascii=False))
    return 0
