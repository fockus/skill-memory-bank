#!/usr/bin/env python3
"""Per-unit three-way merge of an OpenSpec change into a bank topic (AGR-105 Q1 B).

For every unit the sidecar baseline, the current OpenSpec text and the current
bank text decide: only OpenSpec moved -> the bank takes the fresh rendering;
only the bank moved -> kept, an export candidate; both moved to the same text
-> converged; both moved differently -> conflict (``take`` may resolve it). A
checkbox is a boolean three-way and never conflicts. Pure: nothing is written.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    from mb_openspec_model import OSChange
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_model import OSChange

from mb_openspec_ids import anchor_safe
from mb_openspec_sync import SIDECAR_FORMAT, UNKNOWN, Triple, bank_units, os_units, unit_hash

TAKE_CHOICES = ("openspec", "bank")


@dataclass
class Conflict:
    key: str
    openspec: str | None
    bank: str | None


@dataclass
class SyncPlan:
    """What a sync would do; ``sidecar`` is the new baseline when applied."""

    take: list[str] = field(default_factory=list)  # bank <- rendering (replace/insert/delete)
    candidates: list[str] = field(default_factory=list)  # bank ahead: run export
    conflicts: list[Conflict] = field(default_factory=list)
    checks: dict[str, bool] = field(default_factory=dict)  # task key -> new bank checkbox
    renamed_from: dict[str, str] = field(default_factory=dict)  # new req key -> old req key
    sidecar: dict = field(default_factory=dict)


def _hash(units: dict[str, dict], key: str) -> str | None:
    return unit_hash(units[key]["mb"]) if key in units else None


def is_prose(key: str, base: dict, os_side: dict, ours: dict) -> bool:
    """A plain bullet the bank added to a task group: prose, never a unit."""
    return (
        key.startswith("task:")
        and key not in base
        and key not in os_side
        and key in ours
        and "mb_checked" not in ours[key]
    )


def _decide(s: dict, os_now, mb_now, r_now, take: str | None) -> str:
    os_moved, mb_moved = os_now != s.get("os"), mb_now != s.get("mb")
    if not os_moved and not mb_moved:
        return "same"
    if os_moved and not mb_moved:
        return "take" if r_now != mb_now else "converged"
    if mb_moved and not os_moved:
        return "ours"
    if mb_now == r_now:
        return "converged"
    return {"openspec": "take", "bank": "ours-over"}.get(take or "", "conflict")


def _check(
    s: dict, entry: dict, oc: bool | None, mc: bool | None, key: str, plan: SyncPlan
) -> None:
    """Three-way on the checkbox against the old baseline ``s``; sets the new baselines.

    A bank tick the OpenSpec side did not match keeps its old ``mb_checked``
    baseline, so it stays an export candidate.
    """
    if oc is None or mc is None:
        return
    base_oc, base_mc = s.get("os_checked"), s.get("mb_checked")
    if oc != base_oc and mc == base_mc and mc != oc:
        plan.checks[key] = oc
    entry["os_checked"] = oc
    final = plan.checks.get(key, mc)
    entry["mb_checked"] = base_mc if oc == base_oc and base_mc is not None else final


def _box(checked: bool) -> str:
    return f"[{'x' if checked else ' '}] (checkbox)"


def _unknown_tick(s: dict, os_entry: dict, bank_entry: dict) -> tuple[bool, bool] | None:
    """``(openspec, bank)`` checkbox values that differ with no reliable baseline: an
    unknown one, or none at all (the same task added on both sides)."""
    oc, mc = os_entry.get("os_checked"), bank_entry.get("mb_checked")
    if s.get("os_checked", UNKNOWN) != UNKNOWN or oc is None or mc is None or oc == mc:
        return None
    return oc, mc


def _fresh_entry(key: str, os_side: dict, mb_hash: str | None) -> dict | None:
    if key not in os_side and mb_hash is None:
        return None
    entry = {k: v for k, v in os_side.get(key, {}).items() if k != "os"}
    entry["os"] = unit_hash(os_side[key]["os"]) if key in os_side else None
    entry["mb"] = mb_hash
    return entry


def plan_sync(
    sidecar: dict, ch: OSChange, bank: Triple, rendered: Triple, *, take: str | None = None
) -> SyncPlan:
    """Decide every unit. ``rendered`` is ``convert(ch, prior_triple=bank)``."""
    base: dict = sidecar.get("units", {})
    os_side, ours, theirs = os_units(ch), bank_units(bank), bank_units(rendered)
    plan = SyncPlan()
    units: dict[str, dict] = {}
    for key in sorted(set(base) | set(os_side) | set(ours)):
        if is_prose(key, base, os_side, ours):
            continue
        s = base.get(key, {})
        os_now = unit_hash(os_side[key]["os"]) if key in os_side else None
        mb_now, r_now = _hash(ours, key), _hash(theirs, key)
        pending = key in theirs and key not in ours and key in base and s.get("mb") is None
        if pending and os_side.get(key, {}).get("kind") == "renamed":
            decision = "take"
        else:
            decision = _decide(s, os_now, mb_now, r_now, take)
        if decision == "conflict":
            text = theirs.get(key, {}).get("mb")
            plan.conflicts.append(Conflict(key, text, ours.get(key, {}).get("mb")))
            continue
        tick = _unknown_tick(s, os_side.get(key, {}), ours.get(key, {}))
        if tick is not None and take is None:
            plan.conflicts.append(Conflict(key, _box(tick[0]), _box(tick[1])))
            continue
        if decision in ("same", "ours"):
            entry = dict(s) if key in base else None
        elif decision == "ours-over":
            entry = _fresh_entry(key, os_side, r_now) if os_now is not None else None
        else:
            entry = _fresh_entry(key, os_side, r_now if decision == "take" else mb_now)
        if decision == "take":
            plan.take.append(key)
            source = os_side.get(key, {})
            if source.get("kind") == "renamed" and source.get("from"):
                plan.renamed_from[key] = f"req:{anchor_safe(source['from'])}"
        elif decision in ("ours", "ours-over"):
            plan.candidates.append(key)
        if entry is not None:
            meta = os_side.get(key, {})  # where the unit lives now (cap/kind/name/from)
            entry.update({k: v for k, v in meta.items() if k not in ("os", "os_checked")})
            if key in ours and key in os_side:
                oc, mc = os_side[key].get("os_checked"), ours[key].get("mb_checked")
                if tick is not None and take == "openspec":
                    plan.checks[key] = tick[0]
                _check(s, entry, oc, mc, key, plan)
                if tick is not None:  # a resolved unknown tick: bank side stays a candidate
                    entry["mb_checked"] = oc if take == "bank" else plan.checks.get(key, mc)
            elif decision == "take" and key in theirs and "mb_checked" in theirs[key]:
                entry["mb_checked"] = theirs[key]["mb_checked"]
            units[key] = entry
    plan.sidecar = {
        "format": SIDECAR_FORMAT,
        "change_id": ch.change_id,
        "openspec_hash": ch.source_hash,
        "units": units,
    }
    return plan


def bank_changes(sidecar: dict, bank: Triple) -> dict[str, str]:
    """``key -> add|edit|delete|check`` for every unit the bank changed since the last sync."""
    base: dict = sidecar.get("units", {})
    ours = bank_units(bank)
    out: dict[str, str] = {}
    for key in sorted(set(base) | set(ours)):
        s = base.get(key, {})
        if key not in base:
            if not is_prose(key, base, {}, ours):
                out[key] = "add"
        elif key not in ours:
            if s.get("mb") is not None:
                out[key] = "delete"
        elif unit_hash(ours[key]["mb"]) != s.get("mb"):
            out[key] = "edit"
        elif ours[key].get("mb_checked", s.get("mb_checked")) != s.get("mb_checked"):
            out[key] = "check"
    return out
