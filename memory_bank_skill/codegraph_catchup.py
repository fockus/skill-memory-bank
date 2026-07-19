"""Bounded inline catch-up for the Memory Bank code graph (I-133).

Consumes the ``<codebase>/.graph-dirty`` queue written by lifecycle/git hooks
(and detects git-HEAD drift against the graph's meta row) and reruns the
SHA-cached incremental builder. Discipline mirrors the semantic recall layer
(I-132): a single consumer behind a non-blocking flock, a hard subprocess
budget (nothing runs unbounded — a timed-out child is killed by
``subprocess.run``), a cooldown marker after a failed/timed-out attempt so
query paths never pay the budget repeatedly, and fail-open error handling —
the caller always gets an answer, at worst on the stale graph. A killed
rebuild is harmless: ``graph.json`` is written atomically at the very end,
and the per-file cache keeps whatever was parsed, so the next attempt
resumes further along.

Kill-switch: ``MB_GRAPH_AUTOUPDATE=off``. First build stays manual
(``/mb graph --apply``) — an absent graph is never built behind the user's
back (it is a committable artifact).
"""

from __future__ import annotations

import fcntl
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

try:
    from memory_bank_skill.codegraph_loader import read_meta
except ModuleNotFoundError:  # pragma: no cover - bootstrap when run as a bare script module
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill.codegraph_loader import read_meta

DEFAULT_BUDGET = 30.0  # seconds — incremental rebuild is SHA-cached, usually seconds
DEFAULT_COOLDOWN = 600.0  # seconds — back-off after a timed-out/broken rebuild


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def dirty_path(graph_path: Path) -> Path:
    return Path(graph_path).parent / ".graph-dirty"


def _cooldown_path(graph_path: Path) -> Path:
    return Path(graph_path).parent / ".graph-catchup.cooldown"


def _lock_path(graph_path: Path) -> Path:
    return Path(graph_path).parent / ".graph.lock"


def _head_commit(src_root: Path) -> str | None:
    """Short HEAD of ``src_root``'s repo; fail-open ``None`` (no git / no repo)."""
    try:
        r = subprocess.run(
            ["git", "-C", str(src_root), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return None
    if r.returncode != 0:
        return None
    out = r.stdout.strip()
    return out[:12] if out else None


_KNOWN_FLAGS = ("--cochange", "--docs", "--questions", "--sessions")


def _detect_flags(graph_path: Path) -> list[str]:
    """Opt-in build layers to preserve on catch-up — silently stripping
    ``--docs``/``--cochange``/``--sessions``/``--questions`` data would be
    data loss, not a refresh.

    Deterministic source of truth: the ``flags`` list the builder records in
    the meta row (codex I-133 r1: substring sniffing can both drop a layer —
    a --docs corpus with zero annotated signatures — and spuriously enable
    one). Substring heuristics remain ONLY as a fallback for legacy graphs
    built before the field existed."""
    try:
        meta = read_meta(graph_path) or {}
    except Exception:
        meta = {}
    recorded = meta.get("flags")
    if isinstance(recorded, list):
        return [f for f in recorded if f in _KNOWN_FLAGS]

    flags: list[str] = []
    try:
        text = graph_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return flags
    if '"signature"' in text:
        flags.append("--docs")
    if '"co_change"' in text:
        flags.append("--cochange")
    if '"kind": "session"' in text or '"kind":"session"' in text:
        flags.append("--sessions")
    god = graph_path.parent / "god-nodes.md"
    try:
        if god.is_file() and "## Suggested questions" in god.read_text(
            encoding="utf-8", errors="replace"
        ):
            flags.append("--questions")
    except OSError:
        pass
    return flags


def _builder_path() -> Path | None:
    env = os.environ.get("MB_GRAPH_BUILDER")  # override seam (tests / exotic installs)
    if env:
        p = Path(env)
        return p if p.is_file() else None
    cand = Path(__file__).resolve().parents[1] / "scripts" / "mb-codegraph.py"
    if cand.is_file():
        return cand
    cand = Path("~/.claude/skills/memory-bank/scripts/mb-codegraph.py").expanduser()
    return cand if cand.is_file() else None


def maybe_catchup(
    graph_path: str | Path, src_root: str | Path | None = None, budget: float | None = None
) -> dict[str, Any]:
    """Bring the graph up to date iff something marked it dirty. Never raises.

    Results: ``disabled`` (kill-switch) · ``absent`` (no graph — first build is
    manual) · ``clean`` (nothing to do) · ``cooldown`` (recent failed attempt)
    · ``locked`` (another consumer is rebuilding) · ``refreshed`` ·
    ``timed_out`` (budget hit, old graph kept, cooldown set) · ``error``.
    """
    try:
        if os.environ.get("MB_GRAPH_AUTOUPDATE", "on") == "off":
            return {"result": "disabled"}
        graph_path = Path(graph_path)
        if not graph_path.is_file():
            return {"result": "absent"}

        meta = read_meta(graph_path) or {}
        src = Path(src_root) if src_root else Path(str(meta.get("src_root") or "."))
        dirty = dirty_path(graph_path)
        if not dirty.exists():
            commit = meta.get("commit")
            head = _head_commit(src) if commit else None
            if not (commit and head and head != commit):
                return {"result": "clean"}

        cooldown = _cooldown_path(graph_path)
        cd = _env_float("MB_GRAPH_CATCHUP_COOLDOWN", DEFAULT_COOLDOWN)
        try:
            if cooldown.is_file() and (time.time() - cooldown.stat().st_mtime) < cd:
                return {"result": "cooldown"}
        except OSError:
            pass

        try:
            fh = open(_lock_path(graph_path), "w")
        except OSError:
            return {"result": "locked"}  # unwritable lock path → skip, fail-open
        try:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                return {"result": "locked"}

            builder = _builder_path()
            mb = graph_path.parents[1]
            if builder is None or not mb.is_dir() or not src.is_dir():
                return {"result": "error"}
            budget_s = (
                budget
                if budget is not None
                else _env_float("MB_GRAPH_CATCHUP_BUDGET", DEFAULT_BUDGET)
            )
            flags = _detect_flags(graph_path)
            # Own process GROUP (start_new_session), so the timeout kill reaps
            # the builder's grandchildren too (its internal git subprocesses) —
            # killing only the direct child would orphan them unbounded
            # (codex I-133 r1, same class as the I-132 zombie loaders).
            try:
                proc = subprocess.Popen(
                    [sys.executable, str(builder), "--apply", *flags, str(mb), str(src)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    start_new_session=True,
                )
            except OSError:
                cooldown.touch()
                return {"result": "error"}
            try:
                stdout, _ = proc.communicate(timeout=budget_s)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)  # the whole group, not one pid
                except OSError:
                    proc.kill()
                proc.wait()
                cooldown.touch()
                return {"result": "timed_out", "budget": budget_s}
            if proc.returncode != 0:
                cooldown.touch()
                return {"result": "error"}
            dirty.unlink(missing_ok=True)
            cooldown.unlink(missing_ok=True)
            out: dict[str, Any] = {"result": "refreshed", "flags": flags}
            for line in stdout.splitlines():
                key, sep, value = line.partition("=")
                if sep and key in ("reparsed", "cached", "nodes", "edges"):
                    try:
                        out[key] = int(value)
                    except ValueError:
                        pass
            return out
        finally:
            fh.close()  # close releases the flock
    except Exception:
        return {"result": "error"}
