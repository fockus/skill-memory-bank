"""Escalation journal for ADaPT (svp-adapt-escalation design C3, REQ-007/008/010).

`<bank>/tmp/escalations.jsonl` holds three closed record schemas (opened / resolved / clean).
Every read -> validate -> append runs under the shared `mb_lock_acquire` from scripts/_lib.sh,
held by a bash holder subprocess for the whole critical section: the lock records the holder's
shell PID and reclaims by owner liveness, so a Python writer cannot be the owner itself.

CLI (dispatched from mb_work_adapt.py): esc-open | esc-resolve | esc-clean | esc-summary.
Exit: 0 ok · 1 invalid journal line / lock timeout · 2 usage or forbidden combination.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime
import json
import pathlib
import re
import subprocess
import sys

LIB = pathlib.Path(__file__).resolve().parent / "_lib.sh"
COMMANDS = ("esc-open", "esc-resolve", "esc-clean", "esc-summary")
MODES = ("autonomous", "hitl")
DECISIONS = ("auto_split", "stub_continue", "fork_user", "stop_run")
RESOLUTIONS = ("continue", "simplify", "decompose", "skip", "stub_continue")
ALLOWED = {
    "auto_split": ("decompose",),
    "stub_continue": ("stub_continue",),
    "fork_user": ("continue", "simplify", "decompose", "skip"),
}
NEEDS_BACKLOG = ("stub_continue", "skip")
_ID = re.compile(r"I-\d+\Z")
# A waiter can see the lock path vanish or be re-created between mkdir and its -d check (the lib
# then reports a spurious lock_corrupt): retry a fast failure, give up once the 30 s budget is spent.
_HOLDER = (
    'source "$1"; SECONDS=0; '
    'while ! tok=$(mb_lock_acquire "$2" 30 30); do [ "$SECONDS" -lt 25 ] || exit 1; sleep 0.2; done; '
    'printf "%s\\n" "$tok"; read -r _ || true; mb_lock_release "$2" "$tok"'
)


class JournalError(Exception):
    """Invalid journal content or lock failure (exit 1)."""


class UsageError(Exception):
    """Forbidden combination (exit 2)."""


def _is_int(v, low: int) -> bool:
    return isinstance(v, int) and not isinstance(v, bool) and v >= low


def _is_str(v) -> bool:
    return isinstance(v, str) and bool(v)


def _str_list(v, nonempty: bool) -> bool:
    return isinstance(v, list) and all(_is_str(x) for x in v) and (bool(v) or not nonempty)


_COMMON = {"ts": _is_str, "run_id": _is_str, "item_id": _is_str, "cycle": lambda v: _is_int(v, 0)}
_ESC = {
    "escalation_id": _is_str,
    "seq": lambda v: _is_int(v, 1),
    "mode": lambda v: v in MODES,
}
SCHEMAS = {
    "opened": {
        **_COMMON,
        **_ESC,
        "event": lambda v: v == "opened",
        "decision": lambda v: v in DECISIONS,
        "triggers": lambda v: _str_list(v, True),
        "degraded_guards": lambda v: _str_list(v, False),
        "consecutive": lambda v: _is_int(v, 1),
    },
    "resolved": {
        **_COMMON,
        **_ESC,
        "event": lambda v: v == "resolved",
        "resolution": lambda v: v in RESOLUTIONS,
        "backlog_id": lambda v: v is None or (isinstance(v, str) and bool(_ID.match(v))),
        "resolved_by": lambda v: v in ("user", "orchestrator"),
    },
    "clean": {**_COMMON, "event": lambda v: v == "clean"},
}


def _valid(rec) -> bool:
    schema = SCHEMAS.get(rec.get("event")) if isinstance(rec, dict) else None
    return (
        schema is not None and set(rec) == set(schema) and all(f(rec[k]) for k, f in schema.items())
    )


@contextlib.contextmanager
def _locked(bank: pathlib.Path):
    (bank / "tmp").mkdir(parents=True, exist_ok=True)
    holder = subprocess.Popen(
        ["bash", "-c", _HOLDER, "holder", str(LIB), str(bank / "tmp" / ".escalations.lock")],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        if not (holder.stdout.readline() or "").strip():
            raise JournalError("code=lock_timeout " + holder.stderr.read().strip())
        yield
    finally:
        with contextlib.suppress(OSError):
            holder.stdin.close()
        holder.wait(timeout=30)
        holder.stdout.close()
        holder.stderr.close()


def _read(path: pathlib.Path) -> list[dict]:
    if not path.exists():
        return []
    recs = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            rec = None
        if not _valid(rec):
            raise JournalError(f"code=invalid_log_line line={n}")
        recs.append(rec)
    return recs


def _append(path: pathlib.Path, rec: dict) -> None:
    ts = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    rec = {"ts": ts, **rec}
    schema = SCHEMAS[rec["event"]]
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps({k: rec[k] for k in schema}, ensure_ascii=False) + "\n")


def _consecutive(recs: list[dict], run: str) -> int:
    n = 0
    for r in recs:
        if r["run_id"] == run:
            n = 0 if r["event"] == "clean" else n + (r["event"] == "opened")
    return n


def _find_opened(recs: list[dict], esc_id: str) -> dict:
    for r in reversed(recs):
        if r["event"] == "opened" and r["escalation_id"] == esc_id:
            return r
    raise UsageError(f"unknown escalation id {esc_id!r}")


def esc_open(path, recs, a, cascade_stop: int) -> dict:
    triggers = list(dict.fromkeys(t for t in a.triggers.split(",") if t))
    if not triggers or not a.run_id or not a.item_id:
        raise UsageError("esc-open needs --run-id, --item-id and --triggers")
    if a.split_refused and a.mode != "autonomous":
        raise UsageError("--split-refused is for autonomous mode only")
    consecutive = _consecutive(recs, a.run_id) + 1
    if consecutive >= cascade_stop:
        decision = "stop_run"
    elif a.split_refused:
        decision = "stub_continue"
    else:
        decision = "fork_user" if a.mode == "hitl" else "auto_split"
    seq = 1 + sum(
        r["event"] == "opened"
        and (r["run_id"], r["item_id"], r["cycle"]) == (a.run_id, a.item_id, a.cycle)
        for r in recs
    )
    esc_id = f"{a.run_id}:{a.item_id}:{a.cycle}:{seq}"
    _append(
        path,
        {
            "event": "opened",
            "escalation_id": esc_id,
            "seq": seq,
            "run_id": a.run_id,
            "item_id": a.item_id,
            "cycle": a.cycle,
            "mode": a.mode,
            "decision": decision,
            "triggers": triggers,
            "degraded_guards": [d for d in a.degraded.split(",") if d],
            "consecutive": consecutive,
        },
    )
    return {
        "escalation_id": esc_id,
        "decision": decision,
        "triggers": triggers,
        "consecutive": consecutive,
    }


def esc_resolve(path, recs, a) -> None:
    opened = _find_opened(recs, a.id)
    allowed = ALLOWED.get(opened["decision"], ())
    if a.resolution not in allowed:
        raise UsageError(
            f"resolution {a.resolution!r} not allowed after {opened['decision']} {allowed}"
        )
    backlog = a.backlog_id or None
    if (a.resolution in NEEDS_BACKLOG) != (backlog is not None) or (
        backlog and not _ID.match(backlog)
    ):
        raise UsageError(
            "--backlog-id I-NNN is required for stub_continue/skip and forbidden otherwise"
        )
    prior = [r for r in recs if r["event"] == "resolved" and r["escalation_id"] == a.id]
    if prior and (prior[-1]["resolution"], prior[-1]["backlog_id"]) == (a.resolution, backlog):
        return
    keep = ("escalation_id", "seq", "run_id", "item_id", "cycle", "mode")
    _append(
        path,
        {
            "event": "resolved",
            **{k: opened[k] for k in keep},
            "resolution": a.resolution,
            "backlog_id": backlog,
            "resolved_by": "user" if opened["decision"] == "fork_user" else "orchestrator",
        },
    )


def _tag(rec: dict) -> str:
    return rec["resolution"] + (f" backlog={rec['backlog_id']}" if rec["backlog_id"] else "")


def summary(recs: list[dict], run: str) -> list[str]:
    lines = []
    for op in (r for r in recs if r["event"] == "opened" and r["run_id"] == run):
        eid = op["escalation_id"]
        res = [r for r in recs if r["event"] == "resolved" and r["escalation_id"] == eid]
        state = "stopped" if op["decision"] == "stop_run" else (_tag(res[-1]) if res else "open")
        lines.append(
            f"escalation {eid} item={op['item_id']} decision={op['decision']} "
            f"triggers={','.join(op['triggers'])} resolution={state}"
        )
        lines += [
            f"  correction: {_tag(o)} -> {_tag(n)}" for o, n in zip(res, res[1:], strict=False)
        ]
    return lines or ["no escalations in this run"]


def cli(argv: list[str], load_config) -> int:
    ap = argparse.ArgumentParser(prog="mb_work_adapt.py")
    ap.add_argument("cmd", choices=COMMANDS)
    ap.add_argument("--bank", required=True)
    for flag in (
        "pipeline",
        "run-id",
        "item-id",
        "triggers",
        "degraded",
        "id",
        "resolution",
        "backlog-id",
    ):
        ap.add_argument(f"--{flag}", default="")
    ap.add_argument("--cycle", type=int, default=0)
    ap.add_argument("--mode", choices=MODES, default="hitl")
    ap.add_argument("--split-refused", action="store_true")
    a = ap.parse_args(argv)
    bank = pathlib.Path(a.bank)
    path = bank / "tmp" / "escalations.jsonl"
    cascade_stop = load_config(a.pipeline)["cascade_stop"] if a.cmd == "esc-open" else 0
    try:
        with _locked(bank):
            recs = _read(path)
            if a.cmd == "esc-open":
                print(json.dumps(esc_open(path, recs, a, cascade_stop)))
            elif a.cmd == "esc-resolve":
                esc_resolve(path, recs, a)
            elif a.cmd == "esc-clean":
                if not a.run_id or not a.item_id:
                    raise UsageError("esc-clean needs --run-id and --item-id")
                _append(
                    path,
                    {"event": "clean", "run_id": a.run_id, "item_id": a.item_id, "cycle": a.cycle},
                )
            else:
                if not a.run_id:
                    raise UsageError("esc-summary needs --run-id")
                print("\n".join(summary(recs, a.run_id)))
    except JournalError as exc:
        print(f"[adapt] {exc}", file=sys.stderr)
        return 1
    except UsageError as exc:
        print(f"[adapt] {a.cmd}: {exc}", file=sys.stderr)
        return 2
    return 0
