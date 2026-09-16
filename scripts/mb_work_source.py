"""Shared declaration-source resolution for work-state initialization and Eval."""

from __future__ import annotations

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
