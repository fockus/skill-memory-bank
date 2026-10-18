#!/usr/bin/env python3
"""Contained manifest I/O: exit 1 for policy refusal, 2 for bad JSON, 3 for I/O failure."""

from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
import tempfile
from pathlib import Path


def lexical(value: str) -> str:
    return "/" + os.path.normpath(value).lstrip("/")


def absolute(value: str) -> Path:
    if not os.path.isabs(value) or ".." in Path(value).parts or any(c in value for c in "\n\r\0"):
        raise ValueError("nonabsolute, traversing or delimited path")
    path = Path(lexical(value))
    # macOS mktemp emits /var paths through the immutable system /private alias.
    if sys.platform == "darwin":
        for alias in ("/var", "/tmp"):
            if path.is_relative_to(alias) and os.path.realpath(alias) == f"/private{alias}":
                return Path("/private") / path.relative_to("/")
    return path


def directories(path: Path) -> None:
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            continue
        if not stat.S_ISDIR(mode):
            raise ValueError(f"unsafe directory ancestor: {current}")


def checked(value: str) -> Path:
    path = absolute(value)
    directories(path.parent)
    return path


def existing(path: Path) -> os.stat_result | None:
    try:
        return path.lstat()
    except FileNotFoundError:
        return None


def contained(file: str, root: str) -> Path:
    path, base = checked(file), absolute(root)
    directories(base)
    if path == base or not path.is_relative_to(base) or not path.parent.resolve().is_relative_to(base.resolve()):
        raise ValueError(f"outside managed root: {base}")
    return path


def fingerprint(path: Path, *, alias: bool = False) -> str:
    identity = path.lstat()
    if alias:
        if not stat.S_ISLNK(identity.st_mode):
            raise ValueError("not the installed alias")
        value = f"{identity.st_dev}:{identity.st_ino}:".encode() + os.fsencode(os.readlink(path))
        return "symlink:" + hashlib.sha256(value).hexdigest()
    if not stat.S_ISREG(identity.st_mode):
        raise ValueError("not a regular managed file")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError("not a regular managed file")
        return hashlib.file_digest(source, "sha256").hexdigest()


def manifest(file: str) -> dict:
    path = absolute(file)
    directories(path.parent)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return {}
    with os.fdopen(fd, "r") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError("not a regular manifest")
        data = json.load(source)
    if not isinstance(data, dict):
        raise ValueError("invalid manifest")
    if not isinstance(data.get("files", []), list) or not all(isinstance(p, str) for p in data.get("files", [])):
        raise ValueError("invalid manifest file list")
    if not isinstance(data.get("file_sha256") or {}, dict):
        raise ValueError("invalid manifest content hashes")
    backups = data.get("backups", [])
    if not isinstance(backups, list) or not all(isinstance(b, str) and b.count("|") == 1 for b in backups):
        raise ValueError("invalid manifest backup mappings")
    return data


def owned(file: str, record: str, root: str, *, alias: bool = False, directory: bool = False) -> bool:
    path = contained(file, root)
    if file != lexical(file):
        raise ValueError("noncanonical ownership key")
    data = manifest(record)
    if (alias or directory or "home" in data) and data.get("home") != os.environ.get("HOME"):
        return False
    expected = (data.get("file_sha256") or {}).get(file)
    if file not in data.get("files", []) or not expected:
        return False
    return expected == (backup_hash(path) if directory else fingerprint(path, alias=alias))


def backup_hash(path: Path) -> str:
    """Identity and contents of the quarantined original skill, without following links."""
    if not stat.S_ISDIR(path.lstat().st_mode):
        raise ValueError("not a regular skill backup directory")
    digest = hashlib.sha256()
    def failed(exc: OSError) -> None:
        raise exc

    for current, folders, files in os.walk(path, followlinks=False, onerror=failed):
        folders.sort()
        for item in [Path(current), *(Path(current) / name for name in sorted([*folders, *files]))]:
            info = item.lstat()
            if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
                raise ValueError(f"unsafe backup member: {item}")
            digest.update(json.dumps([str(item.relative_to(path)), info.st_dev, info.st_ino, info.st_mode]).encode())
            if stat.S_ISREG(info.st_mode):
                digest.update(fingerprint(item).encode())
    return "backup:" + digest.hexdigest()


def protected(path: Path, base: Path) -> bool:
    if path.is_relative_to(base):
        return True
    info = existing(path)
    # Resolving a final link can only exclude a protected target, never authorize I/O.
    return info is not None and stat.S_ISLNK(info.st_mode) and path.resolve().is_relative_to(base)


def file_identity(path: Path) -> list | None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    digest = backup_hash(path) if stat.S_ISDIR(info.st_mode) else fingerprint(path, alias=stat.S_ISLNK(info.st_mode))
    return [info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid, info.st_mtime_ns, digest]


def private_directory(value: str) -> Path:
    path = checked(value)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("recovery directory must be private, owned and not a link")
    return path


def legacy_paths(data: dict, root: str, *, backups: bool = False) -> list[str]:
    entries = data.get("backups" if backups else "files", [])
    base = absolute(root)
    safe = []
    for entry in entries:
        try:
            paths = [checked(value) for value in (entry.split("|") if backups else [entry])]
            if any(protected(path, base) for path in paths):
                # OpenCode paths never enter the permissive other-host cleanup, in any spelling.
                if not paths[0].is_relative_to(base):
                    print(f"[opencode] preserved cross-root link/mapping: {entry}", file=sys.stderr)
                continue
        except ValueError as exc:
            print(f"[opencode] preserved {entry}: {exc}", file=sys.stderr)
            continue
        safe.append(entry)
    return safe


def write(source: str, file: str, record: str, root: str) -> None:
    path = contained(file, root)
    info = existing(path)
    if info is not None and not owned(file, record, root):
        raise ValueError("modified or unmanaged file; inspect it before retrying")
    mode = stat.S_IMODE(info.st_mode) if info is not None else 0o644
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output, open(source, "rb") as incoming:
            while chunk := incoming.read(65536):
                output.write(chunk)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if existing(Path(temporary)) is not None:
            os.unlink(temporary)


def records(record: str, root: str, written: list[str]) -> dict:
    data = manifest(record)
    hashes = dict(data.get("file_sha256") or {})
    for file in written:
        hashes[file] = fingerprint(contained(file, root))
    return {"files": list(dict.fromkeys([*data.get("files", []), *written])), "file_sha256": hashes}


def remove(record: str, root: str, *, global_install: bool = False) -> None:
    data = manifest(record)
    base = absolute(root)
    for file in data.get("files", []):
        try:
            path = checked(file)
            if global_install and (not path.is_relative_to(base) or path in (base, base / "AGENTS.md")):
                continue
            if existing(path) is None:
                continue
            alias = global_install and path == base / "skills/memory-bank"
            authorized = owned(file, record, root, alias=alias)
        except ValueError:
            authorized = False
        if authorized:
            # Required I/O errors must reach the caller; only policy refusals are warnings.
            contained(file, root).unlink()
        else:
            print(f"[opencode] preserved {file} (modified, unmanaged or unsafe)", file=sys.stderr)
    if not global_install:
        return
    for entry in data.get("backups", []):
        original, separator, backup = entry.partition("|")
        try:
            if not separator or not absolute(original).is_relative_to(base) or absolute(original) == base / "AGENTS.md":
                continue
            target, saved = contained(original, root), contained(backup, root)
            hashes = data.get("file_sha256") or {}
            if (original != lexical(original) or backup != lexical(backup)
                    or target != base / "skills/memory-bank" or original not in data.get("files", [])
                    or not str(hashes.get(original, "")).startswith("symlink:")
                    or saved.parent != base / ".memory-bank-backups"
                    or not saved.name.startswith("memory-bank.pre-mb-backup.")):
                raise ValueError("unknown backup origin/authority")
            info = existing(saved)
            if existing(target) is not None or (info is not None and stat.S_ISLNK(info.st_mode)):
                raise ValueError("live destination or changed backup identity")
            if info is None:
                continue
            if hashes.get(backup) != backup_hash(saved):
                raise ValueError("modified or unverified backup")
        except ValueError as exc:
            print(f"[opencode] preserved {original} and backup {backup}: {exc}", file=sys.stderr)
            continue
        os.rename(saved, target)


def main(args: list[str]) -> int:
    action, file, record, root = args[:4]
    if action in {"owned", "owned-alias", "owned-directory"}:
        return 0 if owned(file, record, root, alias=action == "owned-alias", directory=action == "owned-directory") else 1
    if action == "write":
        write(args[4], file, record, root)
    elif action == "records":
        print(json.dumps(records(record, root, [line for line in sys.stdin.read().splitlines() if line])))
    elif action == "path":
        contained(file, root)
    elif action == "symlink":
        os.symlink(args[4], contained(file, root))
    elif action == "regular":
        path = contained(file, root)
        if existing(path) is not None:
            fingerprint(path)
    elif action in {"remove", "global-remove"}:
        remove(record, root, global_install=action == "global-remove")
    elif action == "backup-hash":
        print(backup_hash(contained(file, root)))
    elif action in {"legacy-files", "legacy-backups"}:
        print("\n".join(legacy_paths(manifest(record), root, backups=action == "legacy-backups")))
    elif action in {"manifest", "uninstall-manifest"}:
        data = manifest(record)
        if action == "uninstall-manifest" and "home" in data and data["home"] != os.environ.get("HOME"):
            raise ValueError("manifest HOME does not match current HOME")
    else:
        raise ValueError("unknown file operation")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except json.JSONDecodeError as exc:
        print(f"[opencode] corrupt manifest {sys.argv[3]}: {exc}", file=sys.stderr)
        raise SystemExit(2) from None
    except OSError as exc:
        print(f"[opencode] I/O failed for {sys.argv[2]}: {exc}; restore access and retry", file=sys.stderr)
        raise SystemExit(3) from None
    except ValueError as exc:
        print(f"[opencode] preserved {sys.argv[2]}: {exc}; inspect the path before retrying", file=sys.stderr)
        raise SystemExit(1) from None
