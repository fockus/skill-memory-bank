#!/usr/bin/env python3
"""``--normalize`` LLM slot-fill layer (T6) — REQ-007, REQ-008, REQ-010.

Design (D-03/D-04): ``convert()`` always renders the deterministic skeleton
(headers, ``- **REQ-NNN**``, anchors, ``<!-- mb-task:N -->``, section order);
``--normalize`` only swaps specific TEXT SLOTS inside that skeleton for LLM
output — a strict-EARS rewrite of the requirement text, a generated
``#### Scenario`` for a requirement that has none, and proposed ``Covers``
links. This module owns exactly three things:

1. The injectable LLM seam (:func:`normalize_requirement`, with the real
   dispatcher :func:`default_llm_dispatch` as its default — swappable for a
   mock in tests, never hardwired plumbing inside the converter).
2. The on-disk cache, keyed by the source-requirement hash so an unchanged
   requirement never regenerates and re-import stays stable (D-04, REQ-008).
3. Fail-open behaviour: an unavailable/erroring ``llm`` callable falls back
   to the exact same deterministic values ``convert(normalize=False)``
   already produces, plus a stderr warning — the import always still
   succeeds (REQ-010).

Structure/format decisions (headers, anchors, task markers) never live here —
that stays 100% in ``mb_openspec_convert.py``.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

try:
    from mb_openspec_model import OSRequirement, OSScenario
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_model import OSRequirement, OSScenario

# One slot dict per source requirement: {"text": str, "scenario": dict|None,
# "covers": list[str]}. "scenario" is a plain {"name": str, "steps": [[kw,
# text], ...]} shape (not an OSScenario instance) so it round-trips through
# JSON in the on-disk cache without a custom encoder/decoder.
LlmDispatch = Callable[[dict[str, Any]], dict[str, Any]]


def requirement_source_hash(req: OSRequirement) -> str:
    """Stable hash of everything that can change the normalize slots (REQ-008).

    Keyed on the requirement name, its full body text, and its scenario
    steps — any of those changing invalidates the cache entry; anything else
    in the source file (formatting elsewhere, other requirements) does not.
    """
    parts = [req.name, req.text]
    for scenario in req.scenarios:
        parts.append(scenario.name)
        for keyword, text in scenario.steps:
            parts.append(f"{keyword}:{text}")
    payload = "\x1f".join(parts).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


class NormalizeCache:
    """Per-requirement slot cache keyed by :func:`requirement_source_hash`.

    Persisted as a single small JSON index under
    ``<mb_path>/.index/openspec/normalize-cache.json`` — one entry per
    source-requirement hash, e.g. ``{"<hash>": {"text": ..., "scenario":
    ...|None, "covers": [...]}}``. A single index (rather than one file per
    hash) keeps "was this hash already normalized" a single dict lookup, and
    the whole cache for one spec import is tiny (one entry per requirement).

    When ``mb_path`` is ``None`` (``convert()`` called without a bank, as
    several pre-T6 unit tests do) the cache is purely in-process/volatile —
    never touches disk, and nothing persists across calls. That is a
    deliberate degrade, not a bug: no bank path means nowhere writable to
    park the cache under, and the deterministic core must still work without
    one.
    """

    def __init__(self, mb_path: str | Path | None) -> None:
        self._mb_path: Path | None = Path(mb_path) if mb_path is not None else None
        self._path: Path | None = None
        if self._mb_path is not None:
            self._path = self._mb_path / ".index" / "openspec" / "normalize-cache.json"
        self._data: dict[str, dict[str, Any]] = {}
        self._dirty = False
        if self._path is not None and self._path.is_file():
            try:
                loaded = json.loads(self._path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                loaded = {}
            if isinstance(loaded, dict):
                self._data = loaded

    def get(self, key: str) -> dict[str, Any] | None:
        return self._data.get(key)

    def set(self, key: str, value: dict[str, Any]) -> None:
        self._data[key] = value
        self._dirty = True

    def delete(self, key: str) -> None:
        """Drop a (corrupted) cache entry so the next lookup is a genuine
        miss (F6, REQ-008/REQ-010)."""
        if key in self._data:
            del self._data[key]
            self._dirty = True

    def flush(self) -> None:
        """Persist the cache to disk (no-op for a path-less/unchanged cache).

        Best-effort: a write failure (e.g. read-only filesystem) is warned to
        stderr, never raised — the cache is an optimization, not something
        that should be able to fail an import (REQ-010's fail-open spirit
        extends to the cache's own I/O, not just the LLM call).

        Routed through the same bank-safe guard as the spec-triple writer
        (F2, NFR-002): if ``<mb_path>/.index/openspec`` resolves outside
        ``mb_path`` (e.g. a symlink escape), the write is refused — never
        silently follows the symlink out of the bank.

        R4 (Codex round-2 residual): the initial guard below catches
        ``OSError``/``RuntimeError`` too (not just ``ValueError``) — a
        ``resolve()`` can itself raise ``OSError`` (e.g. a filesystem loop, a
        permission error walking a parent), and that must degrade to the
        same fail-open warn-and-return as an actual escape, never propagate
        out of ``flush()``. A second, narrower guard immediately precedes the
        write/replace to shrink (not eliminate — see the ``ponytail`` note
        below) the TOCTOU window between the first resolve and the actual
        write.
        """
        if self._path is None or not self._dirty:
            return
        assert self._mb_path is not None
        try:
            base_r = self._mb_path.resolve()
            target_r = self._path.resolve()
            target_r.relative_to(base_r)
        except (ValueError, OSError, RuntimeError):
            print(
                f"[warn] --normalize: refusing to persist cache outside {self._mb_path} "
                "(or the bank/cache path could not be resolved)",
                file=sys.stderr,
            )
            return

        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            print(f"[warn] --normalize: could not persist cache ({exc})", file=sys.stderr)
            return

        # ponytail: re-check IMMEDIATELY before the write to shrink the
        # TOCTOU window opened by the first resolve()+mkdir() above -- if
        # the cache path or its parent was swapped for a symlink in between,
        # refuse rather than write/replace through it. This is NOT a fully
        # race-free openat-style guard (that would need O_NOFOLLOW-style
        # syscalls this stdlib-only module doesn't reach for) -- beyond a
        # single-user CLI's threat model. The goal here is fail-open safety
        # and no escape on the NORMAL (non-adversarial-concurrent) path.
        try:
            if self._path.is_symlink() or self._path.parent.is_symlink():
                raise RuntimeError("cache path or its parent is a symlink")
            self._path.resolve().relative_to(base_r)
        except (ValueError, OSError, RuntimeError):
            print(
                f"[warn] --normalize: refusing to persist cache outside {self._mb_path} "
                "(symlink escape detected immediately before write)",
                file=sys.stderr,
            )
            return

        try:
            tmp = self._path.with_suffix(".json.tmp")
            tmp.write_text(
                json.dumps(self._data, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )
            tmp.replace(self._path)
        except OSError as exc:
            print(f"[warn] --normalize: could not persist cache ({exc})", file=sys.stderr)
        else:
            self._dirty = False


def _deterministic_slots(req: OSRequirement) -> dict[str, Any]:
    """The exact fallback values ``convert(normalize=False)`` already emits.

    ``text``: the flattened prose body (``_flatten`` in the converter uses
    the same rule). ``scenario``: ``None`` — meaning "no generated scenario",
    so the caller keeps using its own deterministic empty-scenario stub.
    ``covers``: empty — no links proposed, so no ``**Covers:**`` line is
    added to the requirement bullet.
    """
    text = " ".join(req.text.split())
    return {"text": text or "(no requirement text provided)", "scenario": None, "covers": []}


def _valid_steps(steps: Any) -> bool:
    """A `scenario_from_slot`-safe ``steps`` shape (F5): a non-empty list of
    2-item sequences, both elements nonblank strings. Anything else (a bare
    string, a list of non-pairs, blank text) must never reach
    :func:`scenario_from_slot`'s ``for kw, text in slot["steps"]`` unpack,
    which raises on anything that isn't actually pairs."""
    if not isinstance(steps, list) or not steps:
        return False
    for step in steps:
        if not isinstance(step, (list, tuple)) or len(step) != 2:
            return False
        keyword, text = step
        if not isinstance(keyword, str) or not keyword.strip():
            return False
        if not isinstance(text, str) or not text.strip():
            return False
    return True


def _validate_slots(raw: dict[str, Any], req: OSRequirement) -> dict[str, Any]:
    """Defensively coerce a (possibly malformed) llm response into the slot shape.

    A missing/blank ``text`` falls back to the deterministic text (never let
    a malformed LLM response blank out the requirement body); ``scenario``
    and ``covers`` degrade to "no slot filled" rather than raising. A
    ``scenario`` whose ``steps`` is not a list of 2-item nonblank-string
    pairs (F5) is dropped to ``None`` rather than being allowed through to
    crash :func:`scenario_from_slot` downstream.
    """
    fallback = _deterministic_slots(req)
    text = raw.get("text") if isinstance(raw, dict) else None
    if not isinstance(text, str) or not text.strip():
        text = fallback["text"]

    scenario = raw.get("scenario") if isinstance(raw, dict) else None
    if scenario is not None and (
        not isinstance(scenario, dict)
        or not isinstance(scenario.get("name"), str)
        or not scenario.get("name", "").strip()
        or not _valid_steps(scenario.get("steps"))
    ):
        scenario = None

    covers = raw.get("covers") if isinstance(raw, dict) else None
    if not isinstance(covers, list) or not all(isinstance(c, str) for c in covers):
        covers = []

    return {"text": text, "scenario": scenario, "covers": covers}


def normalize_requirement(
    req: OSRequirement,
    *,
    cache: NormalizeCache,
    llm: LlmDispatch | None = None,
) -> dict[str, Any]:
    """Fill (or reuse from cache) the normalize slots for one requirement.

    Cache hit (unchanged source, REQ-008): returns the cached slot dict, the
    ``llm`` callable is never invoked — UNLESS the cached entry is itself
    malformed (F6: a hand-edited/corrupted cache file), in which case it is
    dropped and treated as a genuine miss so a re-fetch can heal it, rather
    than crashing conversion or permanently freezing a bad entry in place.
    Cache miss: calls ``llm`` with a small structured payload; on success
    the (validated) result is cached and returned. On failure (``llm``
    raises, or is left ``None`` and no real dispatcher is configured) the
    deterministic slots are returned instead, a warning is emitted to
    stderr, and — deliberately — nothing is cached, so a transient LLM
    outage does not permanently downgrade a requirement that could
    normalize successfully on the next run (REQ-010).
    """
    dispatch: LlmDispatch = llm if llm is not None else default_llm_dispatch
    key = requirement_source_hash(req)
    cached = cache.get(key)
    if cached is not None:
        validated = _validate_slots(cached, req)
        if validated == cached:
            return cached
        print(
            f"[warn] --normalize: corrupted cache entry for requirement '{req.name}' "
            "(invalid shape); dropping and re-generating",
            file=sys.stderr,
        )
        cache.delete(key)

    payload = {
        "name": req.name,
        "text": req.text,
        "needs_scenario": not req.scenarios,
    }
    try:
        raw = dispatch(payload)
    except Exception as exc:  # noqa: BLE001 - any llm failure is fail-open (REQ-010)
        print(
            f"[warn] --normalize: llm unavailable for requirement '{req.name}' "
            f"({exc}); using deterministic fallback",
            file=sys.stderr,
        )
        return _deterministic_slots(req)

    slots = _validate_slots(raw, req)
    cache.set(key, slots)
    return slots


def scenario_from_slot(slot: dict[str, Any]) -> OSScenario:
    """Rebuild an :class:`OSScenario` from a cached/validated scenario slot dict."""
    steps = [(str(kw), str(text)) for kw, text in slot["steps"]]
    return OSScenario(name=str(slot["name"]), steps=steps)


# ---------------------------------------------------------------------------
# Real dispatcher — a seam, not the plumbing the tests exercise (they inject
# their own `llm` callable). Kept simple by design: T6's DoD is the
# slot-fill/cache/fail-open contract, not model-quality or prompt tuning.
# ---------------------------------------------------------------------------


def _build_prompt(payload: dict[str, Any]) -> str:
    lines = [
        "Rewrite the following OpenSpec requirement's prose into a single",
        "strict EARS-pattern sentence (ubiquitous/event-driven/state-driven/",
        "optional/unwanted). Reply with exactly these lines and nothing else:",
        "TEXT: <the rewritten sentence>",
    ]
    if payload.get("needs_scenario"):
        lines.append("SCENARIO: <name> | WHEN <trigger> | THEN <outcome>")
    lines.append("COVERS: <comma-separated REQ-NNN ids this relates to, or NONE>")
    lines.append("")
    lines.append(f"Requirement name: {payload['name']}")
    lines.append(f"Requirement text: {payload['text']}")
    return "\n".join(lines)


def _parse_llm_response(raw_text: str) -> dict[str, Any]:
    """Parse the flat ``KEY: value`` reply contract from :func:`_build_prompt`."""
    text: str | None = None
    scenario: dict[str, Any] | None = None
    covers: list[str] = []
    for line in raw_text.splitlines():
        stripped = line.strip()
        if stripped.upper().startswith("TEXT:"):
            text = stripped.split(":", 1)[1].strip()
        elif stripped.upper().startswith("SCENARIO:"):
            body = stripped.split(":", 1)[1].strip()
            segments = [s.strip() for s in body.split("|")]
            name = segments[0] if segments else ""
            steps: list[list[str]] = []
            for segment in segments[1:]:
                parts = segment.split(None, 1)
                if len(parts) == 2:
                    steps.append([parts[0].upper(), parts[1]])
            if name and steps:
                scenario = {"name": name, "steps": steps}
        elif stripped.upper().startswith("COVERS:"):
            body = stripped.split(":", 1)[1].strip()
            if body.upper() != "NONE":
                covers = [c.strip() for c in body.split(",") if c.strip()]
    return {"text": text, "scenario": scenario, "covers": covers}


def default_llm_dispatch(payload: dict[str, Any]) -> dict[str, Any]:
    """Real LLM seam default.

    Shells out to the project's own subagent-dispatch resolver
    (``mb-subinvoke-resolve.sh``) and reuses the same env-prompt contract
    ``mb-fanout.sh`` already uses for every other dispatch path: the prompt
    flows exclusively through the ``MB_FANOUT_PROMPT`` env var, never
    interpolated into shell text. This lets ``--normalize`` piggyback on the
    existing per-agent (claude-code/codex/pi/opencode) sub-invoke table
    instead of inventing a second one.

    ponytail: this is one blocking, one-shot, non-streaming subprocess call
    with no retry and no session/context beyond a flat text prompt — the
    ceiling here is a real subagent-invoke integration (structured
    request/response, retries, per-role prompt templates) the way
    ``mb-fanout.sh``/``adapters/*_subagent_dispatch_core.mjs`` do for other
    dispatch paths. That deeper integration is out of scope for T6, whose
    DoD is the slot-fill/cache/fail-open contract (fully exercised via a
    mocked ``llm``), not model-quality or prompt engineering.
    """
    script = Path(__file__).with_name("mb-subinvoke-resolve.sh")
    if not script.is_file():
        raise RuntimeError(f"subinvoke resolver not found: {script}")
    resolved = subprocess.run(
        ["bash", str(script)],
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )
    if resolved.returncode != 0 or not resolved.stdout.strip():
        raise RuntimeError(
            f"no sub-invoke command resolvable: {resolved.stderr.strip() or 'unknown error'}"
        )
    cmd = resolved.stdout.strip()

    env = dict(os.environ)
    env["MB_FANOUT_PROMPT"] = _build_prompt(payload)
    proc = subprocess.run(
        ["bash", "-c", cmd],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=180,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"llm dispatch failed (exit {proc.returncode}): {proc.stderr.strip()[:200]}"
        )
    return _parse_llm_response(proc.stdout)
