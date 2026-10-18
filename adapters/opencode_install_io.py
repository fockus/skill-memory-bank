#!/usr/bin/env python3
"""One handled-I/O operation, not ownership authority, replay or crash recovery."""

from __future__ import annotations

import json
import os
import shutil
import stat
import tempfile
from pathlib import Path

from opencode_files import (
    checked,
    contained,
    main,
    manifest,
)
from opencode_files import (
    file_identity as _fact,
)
from opencode_files import (
    private_directory as _context,
)


def _save(context: Path, data: dict) -> None:
    fd, temporary = tempfile.mkstemp(dir=context)
    with os.fdopen(fd, "w") as output:
        json.dump(data, output)
    os.replace(temporary, context / "pending.json")


def _load(context: Path) -> dict:
    data = manifest(str(context / "pending.json"))
    if not isinstance(data.get("members"), list):
        raise ValueError("missing pending operation; inspect recovery material")
    return data


def _guard(context: Path, data: dict) -> None:
    if _fact(checked(data["record"])) != data["record_before"]:
        raise ValueError("authoritative manifest changed; preserving operation")
    for member in data["members"]:
        if "post" not in member:
            raise ValueError("postimage was not observed; inspection required")
        if _fact(contained(member["path"], data["root"])) != member["post"]:
            raise ValueError(f"live postimage changed: {member['path']}")
        if member["before"] is not None:
            image = Path(member["image"])
            if not image.is_relative_to(context):
                contained(str(image), data["root"])
            if _fact(image) != member["image_fact"]:
                raise ValueError(f"retained preimage changed: {image}")


def _release(context: Path, data: dict) -> None:
    for member in data["members"]:
        if member["image"] and Path(member["image"]).is_relative_to(context):
            Path(member["image"]).unlink(missing_ok=True)
    (context / "rollback-started").unlink(missing_ok=True)
    (context / "pending.json").unlink()


def probe(context: Path, record: str, root: str) -> None:
    main(["uninstall-manifest", record, record, root])
    if any(context.iterdir()):
        raise ValueError("unresolved recovery material; no automatic replay")
    parent = checked(record).parent
    parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=parent, prefix=".mb-ownership-probe.")
    renamed = temporary + ".renamed"
    try:
        with os.fdopen(fd, "w") as output:
            output.write("{}\n")
        os.replace(temporary, renamed)
    finally:
        for path in (temporary, renamed):
            if os.path.lexists(path):
                os.unlink(path)


def prepare(context: Path, record: str, root: str, specification: str) -> None:
    if any(context.iterdir()):
        raise ValueError("one pending operation only; inspect retained recovery")
    main(["uninstall-manifest", record, record, root])
    members = []
    entries = json.loads(specification)
    for index, entry in enumerate(entries):
        path = contained(entry["path"], root)
        before = _fact(path)
        image = None
        material = None
        if before is not None:
            if stat.S_ISDIR(before[2]):
                image = contained(entry["retain"], root)
                if _fact(image) is not None or not any(item["path"] == str(image) for item in entries):
                    raise ValueError("directory retention needs a fresh, declared destination")
                material = before
            else:
                image = context / f"before-{index}"
                if stat.S_ISLNK(before[2]):
                    os.link(path, image, follow_symlinks=False)
                else:
                    shutil.copy2(path, image, follow_symlinks=False)
                    os.chown(image, before[3], before[4])
                    os.chmod(image, stat.S_IMODE(before[2]))
                material = _fact(image)
                if material is None or material[2:] != before[2:]:
                    raise ValueError(f"preimage changed during preparation: {path}")
        member = {"path": str(path), "before": before, "image": str(image) if image else None, "image_fact": material}
        if "expected" in entry:
            member["expected"] = entry["expected"]
        members.append(member)
    data = {"root": root, "record": str(checked(record)), "record_before": _fact(checked(record)), "members": members}
    _save(context, data)
    for member in members:
        if member["before"] and stat.S_ISDIR(member["before"][2]):
            os.rename(member["path"], member["image"])


def mark(context: Path, expectations: str = "") -> dict:
    data = _load(context)
    expected = json.loads(expectations or "{}")
    if all("post" in member for member in data["members"]):
        _guard(context, data)
    else:
        incomplete = False
        for member in data["members"]:
            path = contained(member["path"], data["root"])
            if member["path"] in expected:
                member["expected"] = expected[member["path"]]
            observed = _fact(path)
            if "expected" in member:
                wanted = member["expected"]
                matches = observed is None if wanted is None else observed is not None and observed[-1] == wanted
                if isinstance(wanted, dict) and "link" in wanted:
                    matches = observed is not None and stat.S_ISLNK(observed[2]) and os.readlink(path) == wanted["link"]
                if not matches:
                    if observed != member["before"]:
                        _save(context, data)
                        raise ValueError(f"unexpected postimage; preserving changed target: {path}")
                    incomplete = True
            member["post"] = observed
        _save(context, data)
        if incomplete:
            raise ValueError("mutation did not reach its expected postimage")
    return {member["path"]: member["post"][-1] if member["post"] else None for member in data["members"]}


def checkpoint(context: Path, record: str, candidate: str) -> None:
    context = _context(str(context))
    data = _load(context)
    if str(checked(record)) != data["record"]:
        raise ValueError("checkpoint does not belong to this operation")
    main(["uninstall-manifest", candidate, candidate, data["root"]])
    _guard(context, data)
    os.replace(candidate, record)
    _release(context, data)


def abort(context: Path) -> None:
    if not (context / "pending.json").exists():
        fd = os.open(context / "failed", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)
        return
    data = _load(context)
    fd = os.open(context / "rollback-started", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(fd)
    _guard(context, data)
    consumed = set()
    for index, member in enumerate(data["members"]):
        path = contained(member["path"], data["root"])
        if str(path) in consumed or member["before"] == member["post"]:
            continue
        if member["before"] is None:
            if member["post"] is not None:
                if stat.S_ISDIR(member["post"][2]):
                    path.rmdir()
                else:
                    path.unlink()
        else:
            image = Path(member["image"])
            if stat.S_ISDIR(member["before"][2]) and member["post"] is not None:
                live = context / f"postimage-{index}"
                os.rename(path, live)
                try:
                    os.rename(image, path)
                except OSError:
                    os.rename(live, path)
                    raise
                live.unlink()
            else:
                os.replace(image, path)
            consumed.add(str(image))
    _release(context, data)
    fd = os.open(context / "failed", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(fd)
