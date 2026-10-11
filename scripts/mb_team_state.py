#!/usr/bin/env python3
"""team.json (contract C1) store: the single writer, track status machine, globs, render hooks.

Writes go through `locked()`: an exclusive lock on reports/<topic>/.team.lock, then a temp file
and os.replace, so concurrent callers never lose an update and readers never see a partial file.
Track statuses: planned -> dispatched -> returned -> verifying -> reviewing -> done | done_with_concerns;
any open state -> blocked | needs_context | cancelled; reviewing | done* -> fixing -> returned. Track globs
match paths relative to the tree root (`**` crosses directories, `*` does not).
The CLI lives in mb_team_tracks.py, mb_team_status.py and mb_team_ops.py (routed by mb-team.sh).
"""

from __future__ import annotations

import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import mb_team_pipeline as pipeline_mod  # noqa: E402
import mb_team_render as render  # noqa: E402
from mb_team_config import ConfigError, load_configs  # noqa: E402

ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,15}$")
TOPIC_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
FINISHED = ("done", "done_with_concerns")
TERMINAL = (*FINISHED, "cancelled")
HALTED = ("blocked", "needs_context", "cancelled")
MOVES = {"planned": {"dispatched"}, "dispatched": {"returned"},
         "returned": {"verifying", "reviewing", "fixing", *FINISHED},
         "verifying": {"reviewing", "fixing", *FINISHED}, "reviewing": {"fixing", *FINISHED},
         "fixing": {"returned"}, "blocked": {"planned", "dispatched"}, "needs_context": {"planned", "dispatched"}}


class TeamError(Exception):
    def __init__(self, msg: str, code: int = 2):
        super().__init__(msg)
        self.code = code


def can_move(old: str, new: str) -> bool:
    if old in TERMINAL:
        return old in FINISHED and new == "fixing"  # a team-review fix reopens a finished track
    return new in HALTED or new in MOVES.get(old, set())


def _glob_re(glob: str) -> re.Pattern:
    out, i = "", 0
    while i < len(glob):
        if glob.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif glob.startswith("**", i):
            out, i = out + ".*", i + 2
        else:
            out += {"*": "[^/]*", "?": "[^/]"}.get(glob[i], re.escape(glob[i]))
            i += 1
    return re.compile(out + r"\Z")


def glob_match(glob: str, path: str) -> bool:
    return bool(_glob_re(glob).match(path))


def globs_overlap(a: str, b: str) -> bool:
    wild = re.compile(r"[*?\[]")
    wa, wb = bool(wild.search(a)), bool(wild.search(b))
    if not (wa and wb):
        return glob_match(b, a) if wb else glob_match(a, b) if wa else a == b
    # ponytail: literal-prefix test, conservative (src/*.py vs src/*.go count as overlapping)
    pa, pb = wild.split(a, 1)[0], wild.split(b, 1)[0]
    return pa.startswith(pb) or pb.startswith(pa)


def owns(track: dict, path: str) -> bool:
    return any(glob_match(g, path) for g in track.get("files") or [])


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=False, **kw)


def script(name: str) -> str:
    return str(HERE / name)


def now() -> str:
    return dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def team_file(bank: str, topic: str) -> Path:
    return Path(bank) / "reports" / topic / "team.json"


def find_topic(bank: str, topic: str = "") -> str:
    if topic:
        if not team_file(bank, topic).is_file():
            raise TeamError(f"no team '{topic}' in {bank}/reports")
        return topic
    open_teams = [p.parent.name for p in sorted((Path(bank) / "reports").glob("*/team.json"))
                  if not json.loads(p.read_text(encoding="utf-8")).get("closed")]
    if len(open_teams) != 1:
        raise TeamError(f"pass --topic: open teams {open_teams or 'none'}")
    return open_teams[0]


def load(bank: str, topic: str) -> dict:
    return json.loads(team_file(bank, topic).read_text(encoding="utf-8"))


def _write(path: Path, data: dict) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".team.json.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


@contextlib.contextmanager
def locked(bank: str, topic: str, create: dict | None = None):
    """Yield team.json under an exclusive lock; written back atomically unless the body raises."""
    path = team_file(bank, topic)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.with_name(".team.lock"), "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if create is not None:
            if path.exists():
                raise TeamError(f"team '{topic}' already exists: {path}")
            data = create
        else:
            data = json.loads(path.read_text(encoding="utf-8"))
        yield data
        _write(path, data)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else ""


def configs(bank: str) -> tuple[dict, dict, dict]:
    try:
        return load_configs("", bank)
    except ConfigError as exc:
        raise TeamError("; ".join(exc.errors)) from exc


def refresh_brief(bank: str, team: dict, force: bool = False) -> None:
    """Re-render the brief while nobody edited it since the last render."""
    path = Path(bank) / team["brief"]
    if not force and path.exists() and _sha(path) != team.get("brief_sha256"):
        print(f"note: the brief was edited by hand, tracks table not refreshed: {path}", file=sys.stderr)
        return
    try:
        path.write_text(render.render_brief(team, bank, str(HERE.parent), configs(bank)[2]), encoding="utf-8")
    except render.RenderError as exc:
        raise TeamError(str(exc)) from exc
    team["brief_sha256"] = _sha(path)


def render_prompt(bank: str, team: dict, tid: str) -> Path:
    track = next(t for t in team["tracks"] if t["id"] == tid)
    path = Path(bank) / track["prompt"]
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.write_text(render.render_track(team, tid, bank, str(HERE.parent)), encoding="utf-8")
    except render.RenderError as exc:
        raise TeamError(str(exc)) from exc
    return path


def pipeline_attrs(args) -> list[str]:
    attrs = [f"{k}={getattr(args, k)}" for k in ("size", "mode", "tdd", "verifier", "review", "effort")
             if getattr(args, k)]
    return attrs + [f"models.{m}" for m in args.model]


def resolve_track(bank: str, team: dict, track: dict) -> None:
    project, bundled, cfg = configs(bank)
    errors: list[str] = []
    layers = {name: pipeline_mod.parse_kv(track["layers"].get(name, []) if name != "team" else team["team_attrs"],
                                          name, errors.append) for name in ("team", "track", "prompt")}
    source = os.path.join(bank, track["source"]) if track.get("source") else ""
    try:
        if errors:
            raise ConfigError(errors)
        out = pipeline_mod.resolve(cfg, project, bundled, layers, host=team.get("host") or "claude-code",
                                   role=track["role"], source=source)
    except ConfigError as exc:
        raise TeamError(f"track {track['id']}: " + "; ".join(exc.errors)) from exc
    for warning in out["warnings"]:
        print(f"warning: track {track['id']}: {warning}", file=sys.stderr)
    track.update(size=out["pipeline"]["size"], pipeline=out["pipeline"], provenance=out["provenance"])
