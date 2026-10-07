#!/usr/bin/env python3
"""Render the installed form of an agent file for one host.

An agent whose frontmatter declares `compose: <partial> [<partial> ...]` is installed with
those partials' bodies (frontmatter stripped, declared order) above its own body. That makes
a dispatch by name carry the shared discipline in the agent's system prompt, so the
orchestrator never re-types partial files into each prompt.

Frontmatter per host (`--host`, default claude):
  claude    as written, minus `compose:`
  opencode  drops `effort` and `model`: OpenCode forwards unknown keys to the provider as model
            options, and its `model` is `provider/id`, not a Claude alias
  pi        `effort` becomes `thinking` (pi-subagents and the Memory Bank dispatcher read it),
            `tools` become pi built-in names, `model` is dropped
  cursor    keeps only `name` and `description`: Cursor subagents (cursor.com/docs/agent/subagents)
            document name/description/model/readonly/is_background, and a Claude alias is not a
            Cursor model id, so `model` is omitted (= inherit the parent model) unless
            `--pipeline` resolves a Cursor id for the role (below)
  codex     a TOML role for `~/.codex/agents/` (name, description, developer_instructions,
            model_reasoning_effort, and sandbox_mode = "read-only" for agents without Write/Edit)

Role model (`--pipeline PATH [--cost TIER]`, hosts opencode/cursor/codex only): the agent's
role is looked up in the pipeline's `roles.<role>.agent` and its model resolved by
mb_work_models.resolve_model (role model ▸ model_profiles[host][cost tier] ▸ inherit) — the
same resolution /mb work uses. A resolved id is written as `model: <id>` (Cursor, OpenCode —
OpenCode only a `provider/id`) or `model = "<id>"` (Codex). `inherit`, no role, no profile or
no PyYAML → no model key, output identical to a render without `--pipeline`.

Usage: mb-agent-render.py SRC --skill-dir DIR [--host claude|opencode|pi|cursor|codex]
                          [--pipeline PATH [--cost premium|optimal|economy]]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HOSTS = ("claude", "opencode", "pi", "cursor", "codex")
DROPPED_KEYS = {"opencode": {"effort", "model"}, "pi": {"model"}}
# Pi's --tools allowlist is an exact match on its built-in names; Glob maps to find, the rest
# (WebSearch, WebFetch, SendMessage) have no pi built-in and are dropped.
PI_TOOL_NAMES = {"bash": "bash", "read": "read", "write": "write", "edit": "edit",
                 "grep": "grep", "glob": "find", "find": "find", "ls": "ls"}
WRITE_TOOLS = {"write", "edit"}
CURSOR_KEYS = {"name", "description"}
MODEL_HOSTS = ("opencode", "cursor", "codex")  # pipeline host key == renderer host name


def role_model(agent: str, host: str, pipeline: Path, cost: str = "") -> str:
    """Tier model for the agent's role on `host`, or "" (= inherit, key omitted)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mb_work_models as models

    try:
        import yaml  # type: ignore

        cfg = yaml.safe_load(pipeline.read_text(encoding="utf-8")) or {}
    except Exception:  # no PyYAML / unreadable pipeline: fail open to inherit
        return ""
    default_cfg = models.load_default()
    roles = cfg.get("roles") or default_cfg.get("roles") or {}
    role = next((r for r, spec in roles.items() if isinstance(spec, dict) and spec.get("agent") == agent), "")
    if not role:
        return ""
    # Same call as mb-work-plan.sh / config show: item roles fall back to roles.developer.model.
    item_role = role != "planner" and models.role_class(role) not in models.STEP_ROLES
    model, _ = models.resolve_model(role, cfg, default_cfg, host,
                                    models.resolve_cost(cfg, default_cfg, host, cost),
                                    legacy_developer=item_role)
    if model == "inherit" or (host == "opencode" and "/" not in model):
        return ""
    return model


def split_frontmatter(text: str) -> tuple[list[str], str] | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        return None
    return text[4:end].splitlines(), text[end + 5:]


def _key(line: str) -> str:
    return line.split(":", 1)[0].strip()


def _value(line: str) -> str:
    return line.split(":", 1)[1].strip().strip("\"'")


def _tools(line: str) -> list[str]:
    return [t.strip() for t in _value(line).split(",") if t.strip()]


def _pi_line(line: str) -> str | None:
    key = _key(line)
    if key == "effort":
        return f"thinking: {_value(line)}"
    if key == "tools":
        names = dict.fromkeys(PI_TOOL_NAMES[t.lower()] for t in _tools(line) if t.lower() in PI_TOOL_NAMES)
        return f"tools: {', '.join(names)}" if names else None
    return line


def _compose_body(src: Path, skill_dir: Path, names: list[str], body: str) -> str:
    blocks: list[str] = []
    for name in names:
        partial = skill_dir / "agents" / f"{name}.md"
        if not partial.is_file():
            raise FileNotFoundError(f"{src.name}: compose partial not found: {name} ({partial})")
        text = partial.read_text(encoding="utf-8")
        split = split_frontmatter(text)
        blocks.append((split[1] if split else text).strip("\n"))
    blocks.append(body.strip("\n"))
    return "\n\n".join(blocks) + "\n"


def _codex_toml(src: Path, fields: dict[str, str], tools: list[str], body: str, model: str = "") -> str:
    missing = [k for k in ("name", "description") if not fields.get(k)]
    if missing:
        raise ValueError(f"{src.name}: codex role needs frontmatter {', '.join(missing)}")
    # A JSON string is a valid TOML basic string (same escapes), so json.dumps quotes safely.
    out = [f"name = {json.dumps(fields['name'], ensure_ascii=False)}",
           f"description = {json.dumps(fields['description'], ensure_ascii=False)}"]
    if model:
        out.append(f"model = {json.dumps(model)}")
    if fields.get("effort"):
        out.append(f"model_reasoning_effort = {json.dumps(fields['effort'])}")
    if not WRITE_TOOLS & {t.lower() for t in tools}:
        out.append('sandbox_mode = "read-only"')
    out.append(f"developer_instructions = {json.dumps(body, ensure_ascii=False)}")
    return "\n".join(out) + "\n"


def render(src: Path, skill_dir: Path, host: str = "claude", pipeline: Path | None = None,
           cost: str = "") -> str:
    text = src.read_text(encoding="utf-8")
    parts = split_frontmatter(text)
    if parts is None:
        if host == "codex":
            raise ValueError(f"{src.name}: codex role needs YAML frontmatter")
        return text
    lines, body = parts
    compose: list[str] = []
    fields: dict[str, str] = {}
    tools: list[str] = []
    kept: list[str] = []
    for line in lines:
        key = _key(line)
        if key == "compose":
            compose = _value(line).replace(",", " ").split()
            continue
        if key in ("name", "description", "effort"):
            fields[key] = _value(line)
        if key == "tools":
            tools = _tools(line)
        if key in DROPPED_KEYS.get(host, set()) or (host == "cursor" and key not in CURSOR_KEYS):
            continue
        converted = _pi_line(line) if host == "pi" else line
        if converted is not None:
            kept.append(converted)
    model = role_model(fields.get("name") or src.stem, host, pipeline, cost) \
        if pipeline and host in MODEL_HOSTS else ""
    if host == "codex":
        return _codex_toml(src, fields, tools, _compose_body(src, skill_dir, compose, body).rstrip("\n"), model)
    if model:
        kept.append(f"model: {model}")
    if not compose and kept == lines:
        return text
    return "---\n" + "\n".join(kept) + "\n---\n\n" + _compose_body(src, skill_dir, compose, body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("src", type=Path)
    parser.add_argument("--skill-dir", type=Path, required=True)
    parser.add_argument("--host", choices=HOSTS, default="claude")
    parser.add_argument("--pipeline", type=Path)
    parser.add_argument("--cost", default="", choices=("", "premium", "optimal", "economy"))
    args = parser.parse_args()
    try:
        sys.stdout.write(render(args.src, args.skill_dir, args.host, args.pipeline, args.cost))
    except (FileNotFoundError, ValueError) as exc:
        print(f"mb-agent-render: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
