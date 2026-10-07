"""ADaPT-lite for `/mb work` (references/adapt.md, plan adapt-lite Stage 2).

One module for the three mechanical parts of the fork:

- ``adapt:`` config from pipeline.yaml (defaults, ``--no-adapt``, validator);
- ``complexity_escalation`` block extraction + validation from an implementer report;
- sub-items in the run state: split / sub-done / done gate / guards / resume carry-over.

CLI (called by mb-work-state.sh and by the orchestrator directly):
  parse [--file F]                         escalation JSON; exit 1 = no block, 3 = invalid
  config --pipeline P [--no-adapt]         effective adapt config as JSON
  split ITEM --state S --subitems JSON [--pipeline P] [--bank B] [--no-adapt]
  sub-done ITEM --state S
  adapt-check [ITEM] --state S [--pipeline P] [--item-tokens N] [--no-adapt]
  gate --state S                           exit 6 while sub-items are open
  carry --from OLD --to NEW                keep sub-items when an open item is re-armed
Exit codes: 0 ok · 1 no escalation block · 2 usage / invalid input · 3 invalid block ·
6 ADaPT refusal (disabled, depth past max_depth, open sub-items).
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from mb_pipeline_minimal_yaml import minimal_pipeline_load, parse_nested_block  # noqa: E402
from mb_work_waves import assign_waves  # noqa: E402

DEFAULTS = {"enabled": True, "verify_fail_cycles": 3, "item_token_budget": None, "max_depth": 2}
DEFAULT_PIPELINE = HERE.parent / "references" / "pipeline.default.yaml"
_KEY_RE = re.compile(r"^(\s*)complexity_escalation:\s*$")


class Refusal(Exception):
    """ADaPT refuses the operation (exit 6)."""


# ── config ────────────────────────────────────────────────────────────────
def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def validate(cfg: dict, err) -> None:
    """Validator hook for mb_pipeline_validate_core (absent block = defaults)."""
    block = cfg.get("adapt")
    if block is None:
        return
    if not isinstance(block, dict):
        err("adapt: must be a mapping")
        return
    unknown = sorted(set(block) - set(DEFAULTS))
    if unknown:
        err(f"adapt: unknown keys {unknown}; allowed {sorted(DEFAULTS)}")
    if "enabled" in block and not isinstance(block["enabled"], bool):
        err(f"adapt.enabled: must be boolean (got {block['enabled']!r})")
    for key in ("verify_fail_cycles", "max_depth"):
        if key in block and not (_is_int(block[key]) and block[key] >= 1):
            err(f"adapt.{key}: must be int >= 1 (got {block[key]!r})")
    budget = block.get("item_token_budget")
    if budget is not None and not (_is_int(budget) and budget > 0):
        err(f"adapt.item_token_budget: must be null or int > 0 (got {budget!r})")


def load_config(pipeline: str = "", no_adapt: bool = False) -> dict:
    """Effective adapt config; a missing/unreadable/invalid block degrades to defaults."""
    path = pathlib.Path(pipeline) if pipeline else DEFAULT_PIPELINE
    block = None
    try:
        text = path.read_text(encoding="utf-8")
        try:
            import yaml  # type: ignore

            block = (yaml.safe_load(text) or {}).get("adapt")
        except ImportError:
            block = minimal_pipeline_load(text).get("adapt")
    except Exception:
        block = None
    cfg = dict(DEFAULTS)
    if isinstance(block, dict):
        errors: list[str] = []
        validate({"adapt": block}, errors.append)
        if not errors:
            cfg.update({k: v for k, v in block.items() if k in DEFAULTS})
    if no_adapt:
        cfg["enabled"] = False
    return cfg


# ── escalation block ───────────────────────────────────────────────────────
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


# ── run state ─────────────────────────────────────────────────────────────
def _load(path: str) -> dict:
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


def _save(path: str, data: dict) -> None:
    tmp = f"{path}.adapt.tmp"
    pathlib.Path(tmp).write_text(json.dumps(data) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def _subs(data: dict) -> list[dict]:
    return (data.get("adapt") or {}).get("subitems") or []


def _open_children(data: dict, item_id: str) -> list[str]:
    return [s["id"] for s in _subs(data) if s["parent"] == item_id and s["phase"] == "open"]


def split(state: str, item_id: str, subitems, cfg: dict) -> list[dict]:
    data = _load(state)
    top = str(data.get("item_no", ""))
    if not cfg["enabled"]:
        raise Refusal(
            f"ADaPT disabled (--no-adapt or adapt.enabled: false): halt on item {item_id} as before"
        )
    known = {s["id"]: s for s in _subs(data)}
    if item_id != top and item_id not in known:
        raise ValueError(f"unknown item '{item_id}' (state item {top}, sub-items {sorted(known)})")
    if item_id in known and known[item_id]["phase"] != "open":
        raise ValueError(f"sub-item {item_id} is already done")
    if any(s["parent"] == item_id for s in _subs(data)):
        raise Refusal(f"item {item_id} is already split")
    depth = item_id.count(".") + 1
    if depth > cfg["max_depth"]:
        raise Refusal(
            f"ADaPT refused: splitting {item_id} would reach depth {depth} > max_depth {cfg['max_depth']}; "
            "halt on this item"
        )
    children = [
        {"id": f"{item_id}.{n}", "parent": item_id, "depth": depth, "phase": "open", **sub}
        for n, sub in enumerate(normalize_subitems(subitems), 1)
    ]
    data.setdefault("adapt", {}).setdefault("subitems", []).extend(children)
    _save(state, data)
    waves = assign_waves(
        [{"item_no": c["id"], "body": "**Files:** " + ", ".join(c["files"])} for c in children]
    )
    return [{**c, "wave": w} for c, w in zip(children, waves, strict=True)]


def sub_done(state: str, item_id: str) -> None:
    data = _load(state)
    sub = next((s for s in _subs(data) if s["id"] == item_id), None)
    if sub is None:
        raise ValueError(f"unknown sub-item '{item_id}'")
    still_open = _open_children(data, item_id)
    if still_open:
        raise Refusal(f"sub-item {item_id} has open sub-items: {', '.join(still_open)}")
    sub["phase"] = "done"
    _save(state, data)


def gate(state: str) -> None:
    still_open = [s["id"] for s in _subs(_load(state)) if s["phase"] == "open"]
    if still_open:
        raise Refusal(
            f"done refused: open sub-items: {', '.join(still_open)} — the parent closes after its last sub-item"
        )


def check(state: str, cfg: dict, item_id: str = "", item_tokens=None) -> dict:
    data = _load(state)
    top = str(data.get("item_no", ""))
    item_id = item_id or top
    key = "verify_fail" if item_id == top else f"verify_fail@{item_id}"
    fails = list(data.get("steps") or []).count(key)
    reasons = []
    if cfg["enabled"]:
        if fails >= cfg["verify_fail_cycles"]:
            reasons.append("verify_fail_cycles")
        budget = cfg["item_token_budget"]
        if budget is not None and item_tokens is not None and item_tokens > budget:
            reasons.append("item_token_budget")
    return {
        "enabled": cfg["enabled"],
        "item": item_id,
        "verify_fails": fails,
        "trigger": bool(reasons),
        "reasons": reasons,
    }


def carry(old: str, new: str) -> None:
    """Re-arming `init` on the same still-open item keeps its sub-items (resume)."""
    prev, cur = _load(old), _load(new)
    same = all(prev.get(k) == cur.get(k) for k in ("item_no", "source_path"))
    if same and prev.get("phase") != "done" and prev.get("adapt"):
        cur["adapt"] = prev["adapt"]
        _save(new, cur)


def _progress(bank: str, line: str) -> None:
    if bank:
        subprocess.run(
            ["bash", str(HERE / "mb-work-progress-append.sh"), "--text", line, "--mb", bank],
            check=False,
        )


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="mb_work_adapt.py")
    ap.add_argument(
        "cmd", choices=["parse", "config", "split", "sub-done", "adapt-check", "gate", "carry"]
    )
    ap.add_argument("item", nargs="?", default="")
    for flag in ("--file", "--state", "--pipeline", "--bank", "--subitems", "--from", "--to"):
        ap.add_argument(flag, default="")
    ap.add_argument("--item-tokens", type=int, default=None)
    ap.add_argument("--no-adapt", action="store_true")
    a = ap.parse_args(argv)
    cfg = load_config(a.pipeline, a.no_adapt)
    try:
        if a.cmd == "parse":
            text = pathlib.Path(a.file).read_text(encoding="utf-8") if a.file else sys.stdin.read()
            try:
                block = parse_escalation(text)
            except ValueError as exc:
                print(f"[adapt] invalid complexity_escalation: {exc}", file=sys.stderr)
                return 3
            if block is None:
                print("[adapt] no complexity_escalation block", file=sys.stderr)
                return 1
            print(json.dumps(block, ensure_ascii=False))
        elif a.cmd == "config":
            print(json.dumps(cfg))
        elif a.cmd == "split":
            children = split(a.state, a.item, json.loads(a.subitems or "null"), cfg)
            parent = a.item
            ids = ", ".join(c["id"] for c in children)
            _progress(
                a.bank, f"ADaPT: item {parent} split into {ids} (depth {children[0]['depth']})"
            )
            print(json.dumps(children, ensure_ascii=False))
        elif a.cmd == "sub-done":
            sub_done(a.state, a.item)
        elif a.cmd == "adapt-check":
            print(json.dumps(check(a.state, cfg, a.item, a.item_tokens)))
        elif a.cmd == "gate":
            gate(a.state)
        else:
            carry(getattr(a, "from"), a.to)
    except Refusal as exc:
        print(f"[work-state] {exc}", file=sys.stderr)
        return 6
    except ValueError as exc:  # json.JSONDecodeError included
        print(f"[work-state] {a.cmd}: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
