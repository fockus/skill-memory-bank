"""Memory Bank for Hermes: pick each session's bank, then let the skill's own scripts do the work.

Bank per session (first match wins):
  folder   the nearest ``.memory-bank/`` at or above the session's cwd (shared with other agents)
  project  ``$HERMES_HOME/projects/<slug>/.memory-bank`` for a Hermes project folder without its own bank
  general  ``$HERMES_HOME/.memory-bank``: one bank per profile (bot) for every other session
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import sys
import threading
from pathlib import Path

logger = logging.getLogger(__name__)

SKILL_ROOT = Path(__file__).resolve().parents[2]
_SLUG = re.compile(r"[a-z0-9][a-z0-9_-]{0,63}")
_banks: dict[
    str, Path
] = {}  # ponytail: one entry per session for the gateway's lifetime; prune on finalize
_init_lock = threading.Lock()
SECTION_CAP = 6000
_SHARED = {
    "folder": "this project folder's own bank, shared by every session and agent working in it",
    "project": "this Hermes project's bank, shared by every session of the project",
    "general": "this bot's general bank, shared by all of its sessions outside projects",
}


def _hermes_home() -> Path:
    try:
        from hermes_constants import get_hermes_home

        return Path(get_hermes_home()).expanduser().resolve()
    except ImportError:
        return Path(os.environ.get("HERMES_HOME") or Path.home() / ".hermes").expanduser().resolve()


def _project_slug(cwd: Path) -> str | None:
    """The slug of the Hermes project owning *cwd* (core's own resolver), else None."""
    try:
        from hermes_cli import projects_db

        with projects_db.connect_closing() as conn:
            project = projects_db.project_for_path(conn, str(cwd))
    except Exception:  # an unreadable projects.db names no project, as in core
        logger.debug("memory-bank: project lookup failed", exc_info=True)
        return None
    return project.slug if project else None


def _trusted(*paths: Path) -> bool:
    """A folder bank feeds the system prompt and receives writes: accept it only when this user owns it
    and nobody else can write to it or its folder (e.g. a planted /tmp/.memory-bank is refused)."""
    try:
        stats = [path.stat() for path in paths]
    except OSError:
        return False
    uid = os.getuid() if hasattr(os, "getuid") else None
    return all((uid is None or st.st_uid == uid) and not st.st_mode & 0o002 for st in stats)


def resolve_bank(cwd: str) -> tuple[Path, str]:
    home = _hermes_home()
    if cwd and Path(cwd).is_absolute() and Path(cwd).is_dir():
        start = Path(cwd).resolve()
        stop = {Path.home().resolve(), Path(start.anchor)}
        for folder in (start, *start.parents):
            if folder in stop:
                break
            if (folder / ".memory-bank").is_dir() and _trusted(folder, folder / ".memory-bank"):
                return folder / ".memory-bank", "folder"
        slug = _project_slug(start)
        if slug and _SLUG.fullmatch(slug):
            return home / "projects" / slug / ".memory-bank", "project"
    return home / ".memory-bank", "general"


def _script(*args: str, env: dict | None = None, stdin: str = "", timeout: int = 15) -> str:
    result = subprocess.run(
        ["bash", str(SKILL_ROOT / args[0]), *args[1:]],
        input=stdin,
        capture_output=True,
        text=True,
        timeout=timeout,
        # The skill's scripts spawn python several times; a pyenv shim costs ~0.5 s per call.
        env={**os.environ, "MB_PYTHON": sys.executable, **(env or {})},
        check=False,
    )
    if result.returncode:
        logger.warning("memory-bank: %s exited %s", args[0], result.returncode)
    return result.stdout


def _ensure(bank: Path, kind: str) -> None:
    """Scaffold a Hermes-owned bank on first use; a folder's own bank is never created here."""
    if kind == "folder" or bank.is_dir():
        return
    with _init_lock:
        if not bank.is_dir():
            bank.parent.mkdir(parents=True, exist_ok=True)
            _script("scripts/mb-init-bank.sh", f"--project-root={bank.parent}")


def _section(info) -> str:
    cwd = str(info.get("cwd") or "")
    try:
        bank, kind = resolve_bank(cwd)
        _ensure(bank, kind)
        if info.get("session_id"):
            _banks[str(info["session_id"])] = bank
        raw = _script(
            "hooks/mb-session-start-context.sh",
            env={"MB_PATH": str(bank)},
            stdin=json.dumps({"workspace_roots": [cwd or str(bank.parent)]}),
        )
        # The skill builds this for Cursor with literal "\\n" escapes.
        context = json.loads(raw or "{}").get("additional_context", "").replace("\\n", "\n")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        logger.warning("memory-bank: context unavailable: %s", type(error).__name__)
        return ""
    head = (
        f"Memory Bank ({kind}): {bank}, {_SHARED[kind]}.\n"
        "It holds plans, status, decisions and progress; curated knowledge belongs to LLM Wiki. "
        "Keep it current with the memory-bank skill; /mb <command> runs its commands, and terminal commands get "
        "MB_PATH and MB_SKILLS_ROOT. Search it with /mb recall <query> (BM25 plus local semantic vectors over "
        "notes, progress and sessions); for a project's code use "
        'bash "$MB_SKILLS_ROOT/scripts/mb-graph.sh" search "<query>" (or who-calls / impact / tests <symbol>).\n\n'
    )
    # Hermes caps all plugin prompt sections at 8000 chars together; keep room for llm-wiki.
    return (head + context)[:SECTION_CAP]


def _session_env(session_id: str, ctx) -> dict:
    bank = _banks.get(session_id) or resolve_bank(ctx.session_cwd())[0]
    return {"MB_PATH": str(bank), "MB_SKILLS_ROOT": str(SKILL_ROOT)}


def _handoff(session_id: str, *, forget: bool = False) -> None:
    bank = _banks.pop(session_id, None) if forget else _banks.get(session_id)
    if bank is None or not bank.is_dir():
        return
    try:
        _script(
            "scripts/mb-handoff.sh",
            "--actualize",
            str(bank),
            "pre_compact",
            env={"MB_SESSION_ID": session_id},
        )
    except (OSError, subprocess.SubprocessError) as error:
        logger.warning("memory-bank: handoff unavailable: %s", type(error).__name__)
    _reindex(bank)


def _reindex(bank: Path) -> None:
    """Refresh the bank's semantic index in the background, as the skill's Claude Code hooks do."""
    python = os.environ.get("MB_SEMANTIC_PY") or next(
        (
            str(p)
            for p in (
                SKILL_ROOT / "hooks/.venv/bin/python",
                Path.home() / ".claude/hooks/.venv/bin/python",
            )
            if p.is_file()
        ),
        "",
    )
    if not python:
        return
    try:
        subprocess.Popen(
            [python, str(SKILL_ROOT / "hooks/mb-semantic.py"), "reindex"],
            env={**os.environ, "MB_ROOT": str(bank)},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as error:
        logger.warning("memory-bank: reindex unavailable: %s", type(error).__name__)


def _after_compaction(*, session_id="", old_session_id="", **kwargs):
    if old_session_id in _banks:
        _banks.setdefault(session_id, _banks[old_session_id])
    _handoff(session_id)


def _on_finalize(*, session_id="", **kwargs):
    _handoff(session_id, forget=True)


_COMMENT = re.compile(r"<!--.*?-->\n?", re.DOTALL)


_RULES_START, _RULES_END = "<!-- mb-rules:start -->", "<!-- mb-rules:end -->"
_LANGUAGE_LINE = re.compile(r"^.*\*\*Language\*\*.*\n?", re.MULTILINE)


def _rules_block() -> str:
    """Key rules + Memory Bank engineering rules, rendered from the skill (single source with Claude Code).
    The language line is dropped: Hermes answers in the user's language (USER.md, SOUL.md)."""
    key = _script("scripts/mb-rules.sh", "render", "--target=global")
    engineering = (SKILL_ROOT / "rules" / "CLAUDE-GLOBAL.md").read_text(encoding="utf-8")
    body = _LANGUAGE_LINE.sub("", _COMMENT.sub("", key + "\n\n" + engineering)).strip()
    return f"{_RULES_START}\n{body}\n{_RULES_END}"


def _sync_soul_rules() -> None:
    """Keep the rules block in SOUL.md current. SOUL has no plugin-section size cap and is read at session start."""
    soul = _hermes_home() / "SOUL.md"
    if not soul.is_file():
        return  # no SOUL.md: Hermes uses its built-in identity, which a rules-only file would replace
    try:
        block = _rules_block()
        text = soul.read_text(encoding="utf-8")
    except (OSError, subprocess.SubprocessError) as error:
        logger.warning("memory-bank: rules sync skipped: %s", type(error).__name__)
        return
    if _RULES_START in text and _RULES_END in text:
        before, rest = text.split(_RULES_START, 1)
        updated = before + block + rest.split(_RULES_END, 1)[1]
    else:
        paragraphs = text.split("\n\n")
        at = next(
            (
                i + 1
                for i, para in enumerate(paragraphs)
                if para.startswith("Priority when instructions conflict")
            ),
            len(paragraphs),
        )
        updated = "\n\n".join(paragraphs[:at] + [block] + paragraphs[at:])
    if updated != text:
        try:
            soul.write_text(updated, encoding="utf-8")
        except OSError as error:
            logger.warning("memory-bank: rules sync failed: %s", type(error).__name__)


def register(ctx):
    _sync_soul_rules()
    ctx.register_system_prompt_section("memory-bank", _section)
    ctx.register_session_env(
        ["MB_PATH", "MB_SKILLS_ROOT"], lambda session_id: _session_env(session_id, ctx)
    )
    ctx.register_hook("post_compaction", _after_compaction)
    ctx.register_hook("on_session_finalize", _on_finalize)
