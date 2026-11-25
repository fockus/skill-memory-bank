"""Local project RAG: atomic generations, incremental refresh and read-only queries."""

from __future__ import annotations

import fcntl
import hashlib
import importlib
import importlib.util
import json
import re
import shutil
import subprocess
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import NamedTuple, Protocol, cast

from mb_project_rag_corpus import inventory
from mb_rag_storage import (
    _INIT,
    _MODULES,
    _existing_state,
    _key,
    _lock,
    _private_dir,
    _read,
    _Selection,
    reap,
    stage,
)
from mb_rag_storage import InvalidSelection as InvalidSelection
from mb_rag_storage import WriterBusy as WriterBusy

from memory_bank_skill._io import atomic_write

_UPDATE = "run `memory-bank rag update`"


class ManualUpdateRequired(RuntimeError):
    """The bounded worker cannot safely update this generation."""


class IndexStale(RuntimeError):
    """The publication is intact but its tracked-source fingerprint has changed."""


class _Provider(Protocol):
    def prepare(self, cache: Path) -> None:
        """Provision the selected model at explicit setup time."""

    def build(self, index: Path, docs: list[tuple[str, str]], cache: Path) -> None:
        """Index snippets using only local weights."""

    def refresh(
        self,
        index: Path,
        docs: list[tuple[str, str]],
        cache: Path,
        old: Path,
        reuse: list[int | None],
        max_new_chunks: int | None = None,
    ) -> bool:
        """Reuse old rows; refuse before embedding if actual token chunks exceed the budget."""

    def search(self, index: Path, query: str, k: int, cache: Path) -> list[str]:
        """Return ranked document IDs from a published generation."""
        raise NotImplementedError


def check_provider(model: str) -> None:
    name = _MODULES[model]
    expected = Path(__file__).resolve().with_name(f"{name}.py")
    spec = importlib.util.find_spec(name)
    if not spec or not spec.origin or Path(spec.origin).resolve() != expected:
        raise RuntimeError(f"Missing installed RAG provider {name}; reinstall Memory Bank")


def _provider(model: str) -> _Provider:
    check_provider(model)
    return cast(_Provider, importlib.import_module(_MODULES[model]))


def check_qmd_paths(root: Path, bank: Path) -> None:
    for name in ("node", "qmd"):
        if exe := shutil.which(name):
            path = Path(exe)
            if not path.is_absolute() or any(
                candidate.is_relative_to(p)
                for p in (root, bank)
                for candidate in (path, path.resolve())
            ):
                raise ValueError(f"Select a system {name} outside the project on PATH")


def _runtime(model: str, root: Path, bank: Path) -> _Provider:
    if model == "qwen3":
        check_qmd_paths(root, bank)
    return _provider(model)


def selected(root: Path, bank: Path) -> str | None:
    """Return the opt-in model, even if the cache/index subsequently disappeared."""
    root, bank = root.resolve(), bank.resolve()
    state = _existing_state(root, bank)
    active = _read(state) if state is not None else None
    return active.model if active else None


def is_current(root: Path, bank: Path, fingerprint: str) -> bool:
    return inventory(root, bank)[0] == fingerprint


class Publication(NamedTuple):
    model: str
    fingerprint: str
    generation: Path
    cache: Path


@contextmanager
def publication(root: Path, bank: Path) -> Iterator[Publication | None]:
    """Pin one published generation; never create a lockfile or initialize a store."""
    state = _existing_state(root, bank)
    if state is None:
        yield None
        return
    with _lock(state, fcntl.LOCK_SH):
        active = _read(state)
        if active is None:
            yield None
            return
        cache = _private_dir(root, bank, "CACHE", ("models", active.model), False)
        projects = _private_dir(root, bank, "CACHE", ("projects", _key(root, bank)), False)
        yield Publication(active.model, active.fingerprint, projects / active.generation, cache)


def setup(root: Path, bank: Path, model: str) -> None:
    if model not in _MODULES:
        raise ValueError("Select model 'qwen3' or 'perplexity'")
    _install(root.resolve(), bank.resolve(), model, None)


def update(root: Path, bank: Path, *, max_new_chunks: int | None = None) -> None:
    _install(root.resolve(), bank.resolve(), None, max_new_chunks)


def _can_reuse(old: Path, provider: _Provider, cache: Path, sample: str) -> bool:
    # A directory can survive the loss of its vector matrix. Exercise the read path
    # before promising the caller that an existing generation is ready.
    try:
        rows = json.loads((old / "rows.json").read_bytes())
        hits = provider.search(old / "index", sample, 1, cache)
        return bool(hits and hits[0].isdecimal() and int(hits[0]) < len(rows))
    except (OSError, RuntimeError, ValueError, TypeError, subprocess.SubprocessError):
        return False


def _install(root: Path, bank: Path, requested: str | None, limit: int | None) -> None:
    key = _key(root, bank)
    state = _private_dir(root, bank, "STATE", (key,), requested is not None)
    if not state.is_dir():
        raise ValueError(f"No project RAG model selected; {_INIT}")
    writer = _private_dir(root, bank, "STATE", (key, "writer"), True)
    with _lock(writer, fcntl.LOCK_EX | fcntl.LOCK_NB):
        _build_generation(root, bank, key, state, requested, limit)


def _old_ids(old: Path) -> dict[str, int] | None:
    try:
        stored = json.loads((old / "hashes.json").read_bytes())
        if not isinstance(stored, list) or not all(
            isinstance(h, str) and re.fullmatch("[0-9a-f]{64}", h) for h in stored
        ):
            return None
        return {h: i for i, h in enumerate(stored)}
    except (FileNotFoundError, ValueError):
        return None


def _build_generation(
    root: Path, bank: Path, key: str, state: Path, requested: str | None, limit: int | None
) -> None:
    previous = _read(state, repair=requested is not None)
    if requested is None and previous is None:
        raise ValueError(f"No project RAG model selected; {_INIT}")
    model = requested if requested is not None else cast(_Selection, previous).model
    cache = _private_dir(root, bank, "CACHE", ("models", model), requested is not None)
    projects = _private_dir(root, bank, "CACHE", ("projects", key), True)
    reap(state, projects, previous)
    if not cache.is_dir():
        raise RuntimeError(f"Missing {model} model cache; {_INIT}")
    old = projects / previous.generation if previous and previous.model == model else None
    ids = _old_ids(old) if old is not None else None
    if limit is not None and ids is None:
        raise ManualUpdateRequired(f"Generation lacks incremental metadata; {_UPDATE}")
    fingerprint, docs, rows = inventory(root, bank, read=True)
    if not docs and requested is not None:
        raise ValueError("No tracked, non-empty UTF-8 source files to index")
    hashes = [hashlib.sha256(text.encode()).hexdigest() for _, text in docs]
    reuse = [ids.get(h) for h in hashes] if ids is not None else None
    if limit is not None and reuse is not None and (count := reuse.count(None)) > limit:
        raise ManualUpdateRequired(f"{count} new chunks exceed the limit of {limit}; {_UPDATE}")
    provider = _runtime(model, root, bank)
    if requested is not None:
        with _lock(cache, fcntl.LOCK_EX):
            provider.prepare(cache)
        if previous and old and reuse is not None and previous.fingerprint == fingerprint:
            if _can_reuse(old, provider, cache, docs[0][1][:120]):
                return
            reuse = None  # Explicit setup repairs a generation that failed its read-path check.
    active = _Selection(model, uuid.uuid4().hex, fingerprint)
    with stage(state, projects, previous, active) as index:
        if (
            old is None
            or reuse is None
            or not provider.refresh(index, docs, cache, old / "index", reuse, limit)
        ):
            if limit is not None:
                raise ManualUpdateRequired(
                    f"Cannot refresh incrementally within {limit} new vector chunks; {_UPDATE}"
                )
            # A rejected incremental copy may already contain a partial provider database.
            if any(index.iterdir()):
                shutil.rmtree(index)
                index.mkdir(mode=0o700)
            provider.build(index, docs, cache)
        (index.parent / "rows.json").write_text(json.dumps(rows), encoding="utf-8")
        (index.parent / "hashes.json").write_text(json.dumps(hashes), encoding="utf-8")
        with _lock(state, fcntl.LOCK_EX):
            if _read(state, repair=requested is not None) != previous:
                raise RuntimeError("Another RAG build was published; retry this command")
            if not is_current(root, bank, fingerprint):
                raise RuntimeError(f"Source changed during indexing; {_UPDATE}")
            # QMD registers absolute paths: publish a pointer, never rename the directory.
            atomic_write(state / "current.json", json.dumps(active._asdict()))


def candidates(root: Path, bank: Path, query: str, k: int = 10) -> list[dict]:
    root, bank = root.resolve(), bank.resolve()
    with publication(root, bank) as active:
        if active is None or k <= 0:
            return []
        cache = active.cache
        if not cache.is_dir():
            raise RuntimeError(f"Missing {active.model} model cache; {_INIT}")
        generation = active.generation
        index = generation / "index"
        if not index.is_dir():
            raise RuntimeError(f"Missing project RAG index; {_UPDATE}")
        try:
            if not is_current(root, bank, active.fingerprint):
                raise IndexStale(f"Project RAG index is stale; {_UPDATE}")
            rows = json.loads((generation / "rows.json").read_bytes())
            if rows == []:
                return []
            ids = _runtime(active.model, root, bank).search(index, query, k, cache)
            result = []
            for doc in ids[:k]:
                if not isinstance(doc, str) or not re.fullmatch("[0-9]+", doc):
                    raise ValueError("invalid document ID")
                file, line, end = rows[int(doc)]
                result.append({"file": file, "line": line, "end_line": end})
            return result
        except (
            OSError,
            ValueError,
            KeyError,
            IndexError,
            TypeError,
            ImportError,
            subprocess.SubprocessError,
        ) as exc:
            raise RuntimeError(
                f"Project RAG model or index unavailable ({exc}); {_INIT} or {_UPDATE}"
            ) from exc
