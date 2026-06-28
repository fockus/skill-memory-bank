#!/usr/bin/env python3
"""Memory Bank statusline — shows how much of the context window is filled.

Claude Code pipes a JSON status payload on stdin; this prints one line to be
rendered under the input box, e.g.:

    Opus 4.8 (1M context) | ⎇ main | 📁 skill-memory-bank ██░░░░░░░░ 7% (70k/1M)

Modes:
    (stdin JSON)     render the statusline   (how Claude Code calls it)
    --install        wire it into ~/.claude/settings.json (backup, no clobber)
    --selfcheck      run the built-in assertions

Pure stdlib — no jq, no deps. ponytail: reads the transcript tail, not the
whole file; bump TAIL_BYTES if a single turn ever exceeds it.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

TAIL_BYTES = 512 * 1024  # last chunk of transcript scanned for the latest usage
DEFAULT_LIMIT = 200_000
LONG_LIMIT = 1_000_000  # "[1m]" / 1M-context model variants


def context_limit(model: dict) -> int:
    """1M for [1m] model variants, else the standard 200k window."""
    blob = f"{model.get('id', '')} {model.get('display_name', '')}".lower()
    return LONG_LIMIT if ("[1m]" in blob or "1m context" in blob) else DEFAULT_LIMIT


def used_tokens(transcript_path: str | None) -> int:
    """Tokens in the current context = the most recent MAIN-chain assistant
    usage (input + cache_creation + cache_read). Sidechain (subagent) entries
    are skipped so their usage never pollutes the main-window count."""
    if not transcript_path:
        return 0
    p = Path(transcript_path)
    if not p.is_file():
        return 0
    size = p.stat().st_size
    with p.open("rb") as fh:
        if size > TAIL_BYTES:
            fh.seek(size - TAIL_BYTES)
            fh.readline()  # drop the partial first line after the seek
        lines = fh.read().decode("utf-8", "replace").splitlines()
    for line in reversed(lines):
        line = line.strip()
        if not line or '"usage"' not in line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("isSidechain"):
            continue
        usage = (rec.get("message") or {}).get("usage")
        if not isinstance(usage, dict):
            continue
        return (
            usage.get("input_tokens", 0)
            + usage.get("cache_creation_input_tokens", 0)
            + usage.get("cache_read_input_tokens", 0)
        )
    return 0


def _human(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M".replace(".0M", "M")
    if n >= 1_000:
        return f"{n // 1000}k"
    return str(n)


def render(payload: dict) -> str:
    model = payload.get("model") or {}
    workspace = payload.get("workspace") or {}

    limit = context_limit(model)
    used = used_tokens(payload.get("transcript_path"))
    pct = min(100, round(used * 100 / limit)) if limit else 0

    filled = round(pct / 10)
    bar = "█" * filled + "░" * (10 - filled)
    # green < 60, yellow 60-85, red > 85 — peripheral "time to compact" signal
    color = "32" if pct < 60 else ("33" if pct <= 85 else "31")
    meter = f"{bar} \x1b[{color}m{pct}%\x1b[0m ({_human(used)}/{_human(limit)})"

    model_name = model.get("display_name") or model.get("id") or "model"
    proj_dir = (
        workspace.get("project_dir") or workspace.get("current_dir") or payload.get("cwd") or "."
    )
    project = os.path.basename(os.path.normpath(proj_dir)) or proj_dir

    parts = [model_name]
    branch = _git_branch(proj_dir)
    if branch:
        parts.append(f"⎇ {branch}")
    parts.append(f"📁 {project} {meter}")
    return " | ".join(parts)


def _git_branch(repo_dir: str) -> str | None:
    """Read .git/HEAD directly — no subprocess. None when not a repo."""
    head = Path(repo_dir) / ".git" / "HEAD"
    try:
        ref = head.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if ref.startswith("ref: refs/heads/"):
        return ref[len("ref: refs/heads/") :]
    return ref[:7] if ref else None  # detached HEAD → short sha


def install(force: bool = False) -> int:
    cfg_dir = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    settings = Path(cfg_dir) / "settings.json"
    command = f"python3 {Path(__file__).resolve()}"

    data: dict = {}
    if settings.is_file():
        try:
            data = json.loads(settings.read_text(encoding="utf-8"))
        except ValueError:
            print(f"⚠️  {settings} is not valid JSON — fix it first.", file=sys.stderr)
            return 1
        existing = data.get("statusLine", {})
        if existing and existing.get("command") != command and not force:
            print(
                f"⚠️  A statusLine is already set in {settings}:\n"
                f"      {existing.get('command', existing)}\n"
                "    Refusing to overwrite. Re-run with --force, or add manually:\n"
                f'      "statusLine": {{ "type": "command", "command": "{command}" }}',
                file=sys.stderr,
            )
            return 1
        settings.with_suffix(".json.bak").write_text(json.dumps(data, indent=2), encoding="utf-8")

    settings.parent.mkdir(parents=True, exist_ok=True)
    data["statusLine"] = {"type": "command", "command": command}
    settings.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"✅ Memory Bank statusline installed → {settings}")
    print("   Open a new prompt to see context % under the input box.")
    return 0


def selfcheck() -> int:
    import tempfile

    assert context_limit({"id": "claude-opus-4-8[1m]"}) == LONG_LIMIT
    assert context_limit({"display_name": "Opus 4.8 (1M context)"}) == LONG_LIMIT
    assert context_limit({"id": "claude-opus-4-8"}) == DEFAULT_LIMIT

    with tempfile.TemporaryDirectory() as d:
        tp = Path(d) / "t.jsonl"
        tp.write_text(
            json.dumps(
                {"isSidechain": True, "message": {"usage": {"cache_read_input_tokens": 999_999}}}
            )
            + "\n"
            + json.dumps(
                {
                    "message": {
                        "usage": {
                            "input_tokens": 1000,
                            "cache_creation_input_tokens": 4000,
                            "cache_read_input_tokens": 65000,
                        }
                    }
                }
            )
            + "\n",
            encoding="utf-8",
        )
        assert used_tokens(str(tp)) == 70_000, "sidechain leaked or sum wrong"
        line = render(
            {
                "model": {"display_name": "Opus 4.8 (1M context)", "id": "x[1m]"},
                "workspace": {"project_dir": "/x/skill-memory-bank"},
                "transcript_path": str(tp),
            }
        )
        assert "7%" in line and "(70k/1M)" in line and "skill-memory-bank" in line, line

    assert used_tokens(None) == 0 and used_tokens("/no/such/file") == 0
    print("selfcheck OK")
    return 0


def main(argv: list[str]) -> int:
    if "--selfcheck" in argv:
        return selfcheck()
    if "--install" in argv:
        return install(force="--force" in argv)
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except ValueError:
        payload = {}
    print(render(payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
