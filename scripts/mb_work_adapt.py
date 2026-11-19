"""ADaPT-lite for `/mb work` (references/adapt.md): config, escalation block, sub-items, guards.

Siblings: mb_work_adapt_{block,journal,stub} (parsing; esc-*; verify-stub, stub-backlog).

CLI (called by mb-work-state.sh and by the orchestrator directly):
  parse [--file F]                         escalation JSON; exit 1 = no block, 3 = invalid
  config --pipeline P [--no-adapt]         effective adapt config as JSON
  split ITEM --state S --subitems JSON [--pipeline P] [--bank B] [--no-adapt]
  sub-done ITEM --state S
  adapt-check [ITEM] --state S [--pipeline P] [--item-tokens N] [--declared CSV] [--changed F|-]
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
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import mb_work_adapt_journal as journal  # noqa: E402
import mb_work_adapt_stub as stub  # noqa: E402
from mb_pipeline_minimal_yaml import minimal_pipeline_load  # noqa: E402
from mb_work_adapt_block import (  # noqa: E402,F401
    normalize_subitems,
    parse_cli,
    parse_declared,
    parse_escalation,
    read_changed,
    scope_violations,
)
from mb_work_waves import assign_waves  # noqa: E402

DEFAULTS = {
    "enabled": True,
    "verify_fail_cycles": 3,
    "item_token_budget": None,
    "max_depth": 2,
    "review_cycles": 3,
    "judge_cycles": 2,
    "cascade_stop": 3,
}
_INT_KEYS = ("verify_fail_cycles", "max_depth", "review_cycles", "judge_cycles", "cascade_stop")
DEFAULT_PIPELINE = HERE.parent / "references" / "pipeline.default.yaml"


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
    for key in _INT_KEYS:
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


def check(
    state: str,
    cfg: dict,
    item_id: str = "",
    item_tokens=None,
    declared: str = "",
    changed: list[str] | None = None,
) -> dict:
    data = _load(state)
    top = str(data.get("item_no", ""))
    item_id = item_id or top
    suffix = "" if item_id == top else f"@{item_id}"
    steps = list(data.get("steps") or [])
    count = {
        n: steps.count(n + suffix)
        for n in ("verify_fail", "review_cycle", "judge_cycle", "eval_fail")
    }
    reasons, stray = [], []
    decl = parse_declared(declared)
    degraded = [] if decl and changed else ["scope"]
    if cfg["enabled"]:
        budget = cfg["item_token_budget"]
        max_cycles = data.get("max_cycles")
        hits = [
            ("verify_fail_cycles", count["verify_fail"] >= cfg["verify_fail_cycles"]),
            (
                "item_token_budget",
                budget is not None and item_tokens is not None and item_tokens > budget,
            ),
            ("review_cycles", count["review_cycle"] >= cfg["review_cycles"]),
            ("judge_cycles", count["judge_cycle"] >= cfg["judge_cycles"]),
            ("eval_not_green", _is_int(max_cycles) and count["eval_fail"] >= max_cycles),
        ]
        if not degraded:
            stray = scope_violations(decl, changed or [])
            hits.append(("scope_violation", bool(stray)))
        reasons = [name for name, hit in hits if hit]
    out = {
        "enabled": cfg["enabled"],
        "item": item_id,
        "verify_fails": count["verify_fail"],
        "trigger": bool(reasons),
        "reasons": reasons,
        "degraded_guards": degraded,
    }
    if stray and "scope_violation" in reasons:
        out["out_of_scope"] = stray
    return out


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
    if argv and argv[0] in journal.COMMANDS:
        return journal.cli(argv, load_config)
    stubs = {"verify-stub": stub.cli_verify, "stub-backlog": stub.cli_backlog}
    if argv and argv[0] in stubs:
        return stubs[argv[0]](argv[1:])
    ap = argparse.ArgumentParser(prog="mb_work_adapt.py")
    ap.add_argument(
        "cmd", choices=["parse", "config", "split", "sub-done", "adapt-check", "gate", "carry"]
    )
    ap.add_argument("item", nargs="?", default="")
    for flag in ("--file", "--state", "--pipeline", "--bank", "--subitems", "--from", "--to"):
        ap.add_argument(flag, default="")
    ap.add_argument("--declared", default="")
    ap.add_argument("--changed", default="")
    ap.add_argument("--item-tokens", type=int, default=None)
    ap.add_argument("--no-adapt", action="store_true")
    # mb-work-state.sh puts --state/--bank before the item; plain parse_args() drops it before Python 3.12.
    a = ap.parse_intermixed_args(argv)
    cfg = load_config(a.pipeline, a.no_adapt)
    try:
        if a.cmd == "parse":
            rc = parse_cli(a.file)
            if rc:
                return rc
        elif a.cmd == "config":
            print(json.dumps(cfg))
        elif a.cmd == "split":
            children = split(a.state, a.item, json.loads(a.subitems or "null"), cfg)
            ids = ", ".join(c["id"] for c in children)
            _progress(
                a.bank, f"ADaPT: item {a.item} split into {ids} (depth {children[0]['depth']})"
            )
            print(json.dumps(children, ensure_ascii=False))
        elif a.cmd == "sub-done":
            sub_done(a.state, a.item)
        elif a.cmd == "adapt-check":
            changed = read_changed(a.changed) if a.changed else None
            print(json.dumps(check(a.state, cfg, a.item, a.item_tokens, a.declared, changed)))
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
