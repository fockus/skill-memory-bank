"""Key-rules checklist and the interactive onboarding prompt (`mb-rules.sh list`, `init --interactive`):
checklist, own rules, then the Quality step (architecture, TDD, Trophy, coverage)."""

from __future__ import annotations

import copy
import re
from collections.abc import Callable
from typing import TextIO

from memory_bank_skill.key_rules import SelectionError
from memory_bank_skill.key_rules_edit import Selection, _layer
from memory_bank_skill.quality import ARCHITECTURES, resolve_quality, validate_settings


def checklist(sel: Selection, scope: str) -> str:
    """Numbered checklist by group: [x] on, [ ] off, [*] locked; own rules below."""
    rows, lines = sel.resolved()["rules"], []
    active = {r["id"] for r in rows}
    texts = {r["id"]: " / ".join(x["text"] for x in rows if x["id"] == r["id"]) for r in rows}
    number = {rule_id: n for n, rule_id in sel.numbers.items()}
    for group in sel.catalog["groups"]:
        lines.append(group["title"])
        for r in (r for r in sel.catalog["rules"] if r["group"] == group["id"]):
            mark = "*" if r["locked"] else "x" if r["id"] in active else " "
            lines.append(f"  [{mark}] {number[r['id']]:2d}. {r['id']} — {texts.get(r['id'], r['text'])}")
    base_custom = _layer(sel.base or {})["custom"]
    if base_custom:
        lines.append("Your rules (user scope; change with --scope=user)")
        lines += [f"  - {c}" for c in base_custom]
    lines.append(f"Your rules ({scope} scope)")
    lines += [f"  {i}. {c}" for i, c in enumerate(sel.layer["custom"], 1)] or ["  (none)"]
    return "\n".join(lines) + "\n"


def prompt(sel: Selection, scope: str, inp: TextIO, out: TextIO) -> None:
    """Interactive onboarding: numbers toggle rules, Enter accepts; then own rules, one per line."""
    out.write("\nKey rules — injected at the top of CLAUDE.md / AGENTS.md; [*] = always on.\n")
    while True:
        out.write(checklist(sel, scope) + 'Type numbers to toggle (e.g. "9 25"), Enter to accept.\n> ')
        out.flush()
        line = inp.readline()
        if not line.strip():
            break
        for token in line.replace(",", " ").split():
            try:
                sel.toggle(sel.numbers[int(token)])
            except (ValueError, KeyError):
                out.write(f"  ? {token}: not a rule number\n")
            except SelectionError as exc:
                out.write(f"  ! {exc}\n")
    out.write("\nYour own rules (architecture, process, anything) — one per line, empty line to finish.\n")
    while True:
        out.write("> ")
        out.flush()
        line = inp.readline()
        if not line.strip():
            break
        try:
            sel.add(line)
        except SelectionError as exc:
            out.write(f"  ! {exc}\n")
    quality_prompt(sel, scope, inp, out)
    out.write("\n")


def _ask(question: str, apply: Callable[[str], None], inp: TextIO, out: TextIO) -> None:
    """Enter (or EOF) keeps the current value; an invalid answer is asked again once."""
    for _ in range(2):
        out.write(question + "\n> ")
        out.flush()
        line = inp.readline().strip()
        if not line:
            return
        try:
            return apply(line)
        except SelectionError as exc:
            out.write(f"  ! {exc}\n")
    out.write("  keeping the current value\n")


def _setter(sel: Selection, key: str, value: Callable[[str], str] = str) -> Callable[[str], None]:
    """`sel.set(key, value(line))`, rolled back unless the result validates."""
    def apply(line: str) -> None:
        saved = copy.deepcopy((sel.quality, sel.architecture))
        sel.set(key, [value(line)])
        data = {"quality": sel.quality} | ({} if sel.architecture is None else {"architecture": sel.architecture})
        errors = validate_settings(data)
        if errors:
            sel.quality, sel.architecture = saved
            raise SelectionError(errors[0].message)
    return apply


def _architecture_value(line: str) -> str:
    """`2,3` / `2 3` / `1 c <text>` / `c <text>` → the `set architecture` value."""
    match = re.fullmatch(r"([\d,\s]*?)\s*(?:\bc\s+(.+))?", line)
    if not match:
        raise SelectionError(f"numbers 1-{len(ARCHITECTURES)}, or c <text> for a custom rule")
    numbers, custom = match.group(1).replace(",", " ").split(), match.group(2)
    if any(not 1 <= int(n) <= len(ARCHITECTURES) for n in numbers):
        raise SelectionError(f"numbers 1-{len(ARCHITECTURES)}, or c <text> for a custom rule")
    items = [ARCHITECTURES[int(n) - 1] for n in dict.fromkeys(numbers)]
    return ",".join(items + ([f"custom:{custom}"] if custom else []))


def quality_prompt(sel: Selection, scope: str, inp: TextIO, out: TextIO) -> None:
    """Quality step: architecture, TDD, Testing Trophy, coverage; Enter keeps the current value."""
    own = sel._own()
    current = resolve_quality(sel.base, own) if scope == "project" else resolve_quality(own, None)
    q, arch = current["quality"], current["architecture"]
    names = arch["names"] + ([f"custom: {arch['custom']}"] if arch["custom"] else [])
    cov = q["coverage"]
    coverage = f"{cov['overall']}/{cov['core']}/{cov['infra']}" if cov["enabled"] else "off"
    out.write("\nQuality settings — Enter keeps the current value.\nArchitecture:\n")
    out.writelines(f"  [{'x' if a in arch['names'] else ' '}] {i}. {a}\n" for i, a in enumerate(ARCHITECTURES, 1))
    _ask(f'Numbers (e.g. "2,3"), c <text> for a custom rule (current: {", ".join(names)})',
         _setter(sel, "architecture", _architecture_value), inp, out)
    _ask(f"TDD — on / off / small+ (current: {q['tdd']})", _setter(sel, "tdd"), inp, out)
    _ask(f"Testing Trophy — on / off (current: {q['testing_trophy']})", _setter(sel, "trophy"), inp, out)
    _ask(f"Coverage — off or <overall>/<core>/<infra>, e.g. 85/95/70 (current: {coverage})",
         _setter(sel, "coverage"), inp, out)
