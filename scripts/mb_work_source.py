"""Shared declaration-source resolution for work-state initialization and Eval."""

from __future__ import annotations

import os
from pathlib import Path


def declaration_candidates(
    bank: Path, source_path: str, source_topic: str, legacy: str
) -> list[Path]:
    """Resolve explicit file first; otherwise use the existing topic/legacy locations."""
    if source_path.strip():
        path = Path(source_path.strip())
        return [path if path.suffix == ".md" else path / "tasks.md"]
    if source_topic.strip():
        topic = source_topic.strip()
        return [bank / "specs" / topic / "tasks.md", Path(topic) / "tasks.md"]
    legacy = legacy.strip()
    if legacy and legacy not in {"spec", "plan", "drive"}:
        path = Path(legacy)
        first = path if path.suffix == ".md" else bank / "specs" / legacy / "tasks.md"
        return [first, path / "tasks.md"]
    return []


def canonical_init_source(bank: Path, source_path: str, source_topic: str, legacy: str) -> str:
    """Bind a unique source to its canonical path; unknown ad-hoc sources stay unbound.

    An explicit locator is canonicalized even before its file exists, so it cannot
    change identity with cwd. Ambiguous legacy locators require an explicit path.
    """
    candidates = declaration_candidates(bank, source_path, source_topic, legacy)
    if source_path.strip():
        return str(candidates[0].resolve())
    resolved = {path.resolve() for path in candidates if path.is_file()}
    if len(resolved) > 1:
        raise ValueError("ambiguous source; pass --source-path to bind one declaration")
    return str(next(iter(resolved))) if resolved else ""


def resolve_spec_source(bank: Path, topic: str, source_path: str) -> str | None:
    """Accept only a safe topic's tasks.md contained under the resolved specs root."""
    topic = topic.strip()
    source_path = source_path.strip()
    if (
        not topic
        or "/" in topic
        or "\\" in topic
        or topic.startswith(".")
        or topic in (".", "..")
        or not all(c.isalnum() or c in "._-" for c in topic)
    ):
        return None
    try:
        bank_real = Path(os.path.realpath(bank))
        specs_real = Path(os.path.realpath(bank_real / "specs"))
        canonical = bank_real / "specs" / topic / "tasks.md"
        if not canonical.is_file():
            return None
        real = Path(os.path.realpath(canonical))
        if not (real == specs_real or specs_real in real.parents):
            return None
        if source_path and Path(os.path.realpath(source_path)) != real:
            return None
        return str(canonical)
    except (OSError, ValueError):
        return None


def init_spec_locator(bank: Path, topic: str, source_path: str) -> str | None:
    """Bind a topic or bare path to the same contained spec locator as init."""
    if not topic and source_path:
        # Resolving a lexical dot parent would accept a previously refused locator.
        topic = os.path.basename(os.path.dirname(source_path.rstrip("/")))
    canonical = resolve_spec_source(bank, topic, source_path)
    return f"{topic}\x1f{canonical}" if canonical is not None else None
