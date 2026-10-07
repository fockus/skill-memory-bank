"""Host templates for `/mb config init --host` and the `/mb config show` matrix (AGR-074).

    init  copy pipeline.default.yaml with workflow.default, cost and one host's
          model profile set as line edits (comments survive), validate, write;
          for a static-model host (opencode, cursor, codex) re-render its installed
          agents with the tier models through the host adapter's `render-agents`.
    show  effective workflow (mb-workflow.sh) + per role agent → model → source →
          discipline (mb_work_models), with host notes.

Called by scripts/mb-pipeline.sh (`init --host …`, `matrix`). Exit codes:
0 ok · 1 refused / invalid result · 2 usage or unresolvable host model.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
import mb_work_models as models  # noqa: E402

SHIPPED = ("claude-code", "codex", "cursor")  # profiles live in pipeline.default.yaml
DETECTED = ("pi", "opencode")  # any provider: filled from the host's current config
HOSTS = SHIPPED + DETECTED
HOST_NOTES = {
    "pi": "Pi: bare aliases (opus/sonnet/haiku/inherit) collapse to the parent model and "
          "models must be provider/id of the parent's provider (AGR-056).",
    "opencode": "OpenCode: the subagent model is static. `config init --host opencode` writes the "
                "role's model (`model: provider/id`) into the installed project agents "
                "(.opencode/agent/*.md); adapter install reads .memory-bank/pipeline.yaml too.",
    "cursor": "Cursor: the subagent model is static frontmatter. `config init --host cursor` writes it "
              "into the installed global ~/.cursor/agents/mb-*.md from this pipeline (the last init "
              "wins); a plain install-global uses the shipped default profile and MB_COST.",
    "codex": "Codex: `config init --host codex` writes `model` into the installed "
             "~/.codex/agents/*.toml; a reinstall renders them without it until the next init.",
}
# Hosts whose subagent model lives in the installed agent file → adapter re-render entry.
STATIC_HOSTS = {"opencode": "opencode.sh", "cursor": "cursor.sh", "codex": "codex.sh"}
ADAPTERS_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "adapters")
_PLAIN = re.compile(r"^[A-Za-z0-9._/-]+$")


def _mapping(value) -> dict:
    return value if isinstance(value, dict) else {}


class UsageError(Exception):
    pass


def _json(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def pi_current(root: str) -> str:
    home = os.path.expanduser("~")
    settings = {**_json(os.path.join(home, ".pi", "agent", "settings.json")),
                **_json(os.path.join(root, ".pi", "settings.json"))}
    provider, model = settings.get("defaultProvider"), settings.get("defaultModel")
    if not model:
        return ""
    return f"{provider}/{model}" if provider and not str(model).startswith(f"{provider}/") else str(model)


def opencode_current(root: str) -> str:
    """OpenCode `model` by its precedence; `small_model` is the cheap slot and never read."""
    cfg_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    layers = [_json(os.path.join(cfg_home, "opencode", "opencode.json")),
              _json(os.environ["OPENCODE_CONFIG"]) if os.environ.get("OPENCODE_CONFIG") else {},
              _json(os.path.join(root, "opencode.json"))]
    with contextlib.suppress(ValueError):
        layers.append(json.loads(os.environ.get("OPENCODE_CONFIG_CONTENT") or "{}"))
    model = ""
    for layer in layers:
        if isinstance(layer, dict) and layer.get("model"):
            model = str(layer["model"])
    return model


def host_profile(host: str, default_cfg: dict, root: str, premium: str, mid: str) -> dict:
    if host in SHIPPED:
        shipped = _mapping(_mapping(default_cfg.get("model_profiles")).get(host))
        profile = {"premium": premium or shipped.get("premium"), "mid": mid or shipped.get("mid")}
        if not all(profile.values()):
            raise UsageError(f"no shipped {host} profile; pass --model-premium and --model-mid")
        return profile
    where = ("~/.pi/agent/settings.json or .pi/settings.json (defaultProvider + defaultModel)"
             if host == "pi" else "opencode.json `model` (global, $OPENCODE_CONFIG, project)")
    premium = premium or (pi_current(root) if host == "pi" else opencode_current(root))
    if not premium:
        raise UsageError(f"cannot detect the current {host} model in {where}; "
                         "pass --model-premium <provider/id>")
    if not mid:
        raise UsageError(f"{host} needs --model-mid <provider/id>: the host's mid model "
                         "(never its cheapest / small_model)")
    for slot, value in (("premium", premium), ("mid", mid)):
        if "/" not in value:
            raise UsageError(f"{host} --model-{slot} '{value}' needs provider/id")
    if host == "pi" and premium.split("/", 1)[0] != mid.split("/", 1)[0]:
        raise UsageError(f"pi mid '{mid}' must use the premium model's provider "
                         f"'{premium.split('/', 1)[0]}' (AGR-056: same provider as the parent)")
    return {"premium": premium, "mid": mid}


def _scalar(value: str) -> str:
    return value if _PLAIN.match(value) else json.dumps(value)


def profile_line(host: str, profile: dict) -> str:
    return f"  {host}: {{premium: {_scalar(profile['premium'])}, mid: {_scalar(profile['mid'])}}}"


def apply_edits(text: str, preset: str, cost: str, host: str, profile) -> str:
    if preset:
        text, n = re.subn(r"(?m)^(workflow:\n(?:[ \t]*#.*\n)*  default:)[^\n]*", rf"\g<1> {preset}", text)
        if n != 1:
            raise RuntimeError("workflow.default not found in the template")
    if cost:
        text, n = re.subn(r"(?m)^cost:[^\n]*", f"cost: {cost}", text)
        if n != 1:
            raise RuntimeError("top-level cost not found in the template")
    if profile:
        lines = text.split("\n")
        start = lines.index("model_profiles:")
        end = start + 1
        while end < len(lines) and lines[end].startswith("  "):
            end += 1
        new = profile_line(host, profile)
        hit = [i for i in range(start + 1, end) if lines[i].startswith(f"  {host}:")]
        if hit:
            lines[hit[0]] = new
        else:
            lines.insert(end, new)
        text = "\n".join(lines)
    return text


def cmd_init(a) -> int:
    default_cfg = models.load_default()
    if not default_cfg:
        sys.stderr.write("[pipeline] PyYAML is required for host templates (pip install pyyaml)\n")
        return 1
    if a.cost and a.cost not in models.TIERS:
        raise UsageError(f"--cost '{a.cost}' not in {list(models.TIERS)}")
    if a.host and a.host not in HOSTS:
        raise UsageError(f"--host '{a.host}' not in {list(HOSTS)}")
    if (a.model_premium or a.model_mid) and not a.host:
        raise UsageError("--model-premium / --model-mid need --host")
    names = set(_mapping(default_cfg.get("workflows"))) | set(
        _mapping(_mapping(default_cfg.get("workflow")).get("aliases")))
    if a.preset and names and a.preset not in names:
        raise UsageError(f"--preset '{a.preset}' is not a workflow or alias in the default")
    profile = host_profile(a.host, default_cfg, a.root, a.model_premium, a.model_mid) if a.host else None

    if os.path.exists(a.target) and not a.force:
        keys = ([f"workflow.default: {a.preset}"] if a.preset else []) + \
               ([f"cost: {a.cost}"] if a.cost else []) + \
               (["model_profiles:", profile_line(a.host, profile)] if profile else [])
        sys.stderr.write(f"[pipeline] {a.target} already exists; your edits are kept. Add these keys by "
                         "hand, or re-run with --force to rewrite it from the template (edits lost):\n")
        sys.stderr.write("".join(f"  {k}\n" for k in keys))
        return 1

    with open(a.default, encoding="utf-8") as fh:
        text = apply_edits(fh.read(), a.preset, a.cost, a.host, profile)
    tmp = a.target + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    check = subprocess.run(["bash", os.path.join(SCRIPT_DIR, "mb-pipeline-validate.sh"), tmp])
    if check.returncode != 0:
        os.remove(tmp)
        sys.stderr.write("[pipeline] the rendered template failed validation; nothing written\n")
        return 1
    os.replace(tmp, a.target)
    print(f"[pipeline] created {a.target}" + (f" (host {a.host})" if a.host else ""))
    if a.host in HOST_NOTES:
        print(f"note: {HOST_NOTES[a.host]}")
    return render_installed_agents(a.host, a.root, a.target) if a.host in STATIC_HOSTS else 0


def render_installed_agents(host: str, root: str, pipeline: str) -> int:
    """Re-render the host's installed agents with this pipeline's tier models (the adapter writes)."""
    cmd = ["bash", os.path.join(ADAPTERS_DIR, STATIC_HOSTS[host]), "render-agents"]
    cmd += [pipeline] if host == "cursor" else [root, pipeline]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.stderr.write(out.stdout + out.stderr)
        sys.stderr.write(f"[pipeline] {host} agents were not re-rendered\n")
        return 1
    print(f"applied: static (installed agents) — {out.stdout.strip()}")
    return 0


def _run(cmd: list) -> str:
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.stderr.write(out.stderr)
        raise SystemExit(out.returncode)
    return out.stdout.strip()


def cmd_show(a) -> int:
    if a.cost and a.cost not in models.TIERS:
        raise UsageError(f"--cost '{a.cost}' not in {list(models.TIERS)}")
    path = _run(["bash", os.path.join(SCRIPT_DIR, "mb-pipeline.sh"), "path"] + ([a.mb] if a.mb else []))
    wf_cmd = ["bash", os.path.join(SCRIPT_DIR, "mb-workflow.sh"), "--json"]
    for flag, value in (("--mb", a.mb), ("--workflow", a.preset), ("--verify", a.verify), ("--host", a.host)):
        if value:
            wf_cmd += [flag, value]
    wf = json.loads(_run(wf_cmd))
    try:
        import yaml  # type: ignore

        with open(path, encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh) or {}
    except Exception:
        cfg = {}
    default_cfg = models.load_default()
    host = wf.get("host") or ""
    cost = models.resolve_cost(cfg, default_cfg, host, a.cost)
    strict = models.strict_models(cfg, default_cfg)

    print(f"pipeline: {path}")
    print(f"host: {host or '(not detected; pass --host)'} · preset: {wf['name']} · "
          f"cost: {cost} · verify: {wf.get('verify_cadence')}")
    print("steps: " + " → ".join(wf.get("steps", [])) + ("  (self-verify)" if wf.get("self_verify") else ""))
    print()
    rows = [("ROLE", "AGENT", "MODEL", "SOURCE", "DISCIPLINE")]
    aliases = []
    for role, spec in _mapping(cfg.get("roles")).items():
        # Same call as mb-work-plan.sh: item roles fall back to roles.developer.model.
        item_role = role != "planner" and models.role_class(role) not in models.STEP_ROLES
        model, source = models.resolve_model(role, cfg, default_cfg, host, cost, legacy_developer=item_role)
        rows.append((role, str(_mapping(spec).get("agent", "")), model, source,
                     models.discipline_for(model, strict)))
        if model != "inherit" and "/" not in model:
            aliases.append(role)
    widths = [max(len(r[i]) for r in rows) for i in range(5)]
    for r in rows:
        print("  ".join(c.ljust(widths[i]) for i, c in enumerate(r)).rstrip())
    if host:
        print("\napplied: " + ("static (installed agents)" if host in STATIC_HOSTS else "per-dispatch"))
    if host in HOST_NOTES:
        print(f"note: {HOST_NOTES[host]}")
    if host == "pi" and aliases:
        print(f"warning: on Pi these roles have no provider/ prefix and run on the parent model: {', '.join(aliases)}")
    print_quality(a.mb)
    return 0


def print_quality(mb: str) -> None:
    """Project quality settings with their source (AGR-076) — `mb-profile.sh quality` verbatim."""
    out = subprocess.run(["bash", os.path.join(SCRIPT_DIR, "mb-profile.sh"), "quality"]
                         + ([f"--mb={mb}"] if mb else []), capture_output=True, text=True)
    detail = "; ".join(out.stderr.split("\n")).strip("; ")
    lines = out.stdout.splitlines() if out.returncode == 0 else [f"quality: invalid profile ({detail})"]
    print("\nquality:\n" + "\n".join("  " + line for line in lines))


def main(argv) -> int:
    p = argparse.ArgumentParser(prog="mb_config_hosts.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("init")
    i.add_argument("--default", required=True)
    i.add_argument("--target", required=True)
    i.add_argument("--root", default=os.getcwd())
    s = sub.add_parser("show")
    s.add_argument("--verify", default="")
    s.add_argument("mb", nargs="?", default="")
    for sp in (i, s):
        sp.add_argument("--host", default="")
        sp.add_argument("--preset", default="")
        sp.add_argument("--cost", default="")
    i.add_argument("--model-premium", default="")
    i.add_argument("--model-mid", default="")
    i.add_argument("--force", action="store_true")
    a = p.parse_args(argv)
    try:
        return cmd_init(a) if a.cmd == "init" else cmd_show(a)
    except UsageError as exc:
        sys.stderr.write(f"[pipeline] {exc}\n")
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
