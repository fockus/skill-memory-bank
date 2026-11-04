#!/usr/bin/env python3
"""Records written before content hashes existed: the listing proves provenance, not integrity."""

from __future__ import annotations

import os

from opencode_files import claim, contained, existing, identity


def legacy_owned(file: str, record: str, root: str, *, alias: bool = False, directory: bool = False) -> bool:
    listed = claim(file, record, root, alias=alias, directory=directory)
    if listed is None or listed[1] is not None:
        return False
    # Refuses the wrong kind (a link where a file was installed, a file where a link was) without following it.
    identity(listed[0], alias=alias, directory=directory)
    return True


def quarantine(file: str, record: str, root: str, backup: str, *, alias: bool = False) -> None:
    """Move a legacy-owned path aside so its replacement never discards user edits."""
    if not legacy_owned(file, record, root, alias=alias):
        raise ValueError("not listed by a pre-hash record; inspect it before retrying")
    saved = contained(backup, root)
    if existing(saved) is not None:
        raise ValueError(f"quarantine destination exists: {saved}")
    os.rename(contained(file, root), saved)


def main(action: str, file: str, record: str, root: str, extra: list[str]) -> int:
    if action in {"quarantine", "quarantine-alias"}:
        quarantine(file, record, root, extra[0], alias=action == "quarantine-alias")
        return 0
    if action not in {"legacy-owned", "legacy-owned-alias", "legacy-owned-directory"}:
        raise ValueError("unknown file operation")
    kind = {"alias": action.endswith("-alias"), "directory": action.endswith("-directory")}
    return 0 if legacy_owned(file, record, root, **kind) else 1
