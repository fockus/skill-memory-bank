#!/usr/bin/env python3
"""Read-only native work preflight; the shared helpers remain the workflow engine."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

from opencode_models import ROOT, assignments, model_reference

from memory_bank_skill.pipeline_yaml import load_file

WORKFLOW_VALUES = {"--workflow", "--verify", "--tier", "--stages", "--lenses"}
WORKFLOW_SWITCHES = {f"--{prefix}{name}" for prefix in ("", "no-")
                     for name in ("review", "judge", "fix", "brainstorm", "sdd", "plan")}
WORKFLOW_SWITCHES |= {"--no-adapt", "--qa"}
PLAN_VALUES = {"--range", "--cost", "--model", "--step-model", "--target"}
DRIVER_VALUES = {"--budget", "--loop", "--max-cycles", "--run-id"}
DRIVER_SWITCHES = {"--auto", "--dry-run", "--allow-protected"}


def selected_steps(cfg: dict, default: dict, workflow: dict) -> dict[str, str]:
    steps = {role: step for step, role in (("verify", "verifier"), ("judge", "judge"), ("plan", "planner"))
             if step in workflow["steps"]}
    if "review" not in workflow["steps"]:
        return steps
    spec = {**default.get("workflows", {}), **cfg.get("workflows", {})}.get(workflow["name"], {})
    if spec.get("review_profile") != "ensemble":
        return {**steps, "reviewer": "review"}
    ensemble = cfg.get("review_ensemble") or default.get("review_ensemble") or {}
    lenses = workflow.get("review_lenses")
    reviewers = [r["role"] for r in ensemble.get("reviewers", []) if lenses is None or r.get("focus") in lenses]
    lead = ensemble.get("lead_role")
    if not reviewers or not isinstance(lead, str) or not lead:
        raise ValueError("selected review ensemble needs reviewers and a lead_role")
    return {**steps, **dict.fromkeys([*reviewers, lead], "review")}


def prepare(text: str, bank: str, execution_source: str = "", resolve_execution: bool = False, current: dict | None = None) -> dict:
    tokens = shlex.split(text)
    workflow_args: list[str] = []
    plan_args: list[str] = []
    overrides: dict[str, str] = {}
    driver: list[str] = []
    env = {**os.environ, "MB_AGENT": "opencode", "MB_PIPELINE_HOST": "opencode", "MB_PATH": bank}
    cost = ""
    while tokens:
        token = tokens.pop(0)
        flag, equal, value = token.partition("=")
        if flag in WORKFLOW_VALUES | PLAN_VALUES | DRIVER_VALUES | {"--host"}:
            if not equal:
                if not tokens:
                    raise ValueError(f"{flag} needs a value")
                value = tokens.pop(0)
            if flag in WORKFLOW_VALUES:
                workflow_args += [flag, value]
            elif flag in PLAN_VALUES:
                plan_args += [flag, value]
                if flag == "--model":
                    overrides["implementer"] = value
                if flag == "--step-model":
                    role, separator, selector = value.partition("=")
                    if not separator or role not in ("verifier", "reviewer", "judge") or not selector:
                        raise ValueError("--step-model needs verifier|reviewer|judge=<model>")
                    overrides[role] = selector
                if flag == "--cost":
                    cost = value
            elif flag == "--host":
                if value != "opencode":
                    raise ValueError("native OpenCode work requires --host opencode")
            else:
                driver += [flag, value]
        elif token in WORKFLOW_SWITCHES:
            workflow_args.append(token)
        elif token in DRIVER_SWITCHES:
            driver.append(token)
        elif token.startswith("-"):
            raise ValueError(f"unsupported native work argument {token!r}")
        else:
            plan_args += ["--target", token]

    def run(script: str, args: list[str]) -> str:
        result = subprocess.run(["bash", str(ROOT / "scripts" / script), *args],
                                env=env, capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise ValueError(result.stderr.strip() or f"{script} exited {result.returncode}")
        return result.stdout.strip()

    # Resolve strictly FIRST: downstream helpers intentionally have fail-open legacy paths.
    pipeline = Path(run("mb-pipeline.sh", ["path", bank]))
    cfg = load_file(str(pipeline))
    default = load_file(str(ROOT / "references/pipeline.default.yaml"))
    workflow = json.loads(run("mb-workflow.sh", ["--mb", bank, "--host", "opencode", *workflow_args, "--json"]))
    deferred = (workflow.get("entrypoint") == "freeform_or_topic"
                and bool(set(workflow["steps"]) & {"discuss", "sdd", "plan"}) and not execution_source and not resolve_execution)
    items = []
    existing = []
    if deferred:
        targets = [value for flag, value in zip(plan_args[::2], plan_args[1::2], strict=True) if flag == "--target"] or [""]
        for target in targets:
            candidate = subprocess.run(["bash", str(ROOT / "scripts/mb-work-resolve.sh"), *([target] if target else []), "--mb", bank],
                                       env=env, capture_output=True, text=True, timeout=15)
            if candidate.returncode == 0:
                resolved = run("mb-work-plan.sh", ["--target", candidate.stdout.strip(), "--mb", bank,
                                                  "--host", "opencode", "--workflow", workflow["name"]])
                existing.extend(json.loads(line)["source_path"] for line in resolved.splitlines() if line)
            elif candidate.returncode == 2:
                raise ValueError(candidate.stderr.strip())
    if execution_source:
        plan_args = [part for flag, value in zip(plan_args[::2], plan_args[1::2], strict=True)
                     if flag != "--target" for part in (flag, value)] + ["--target", execution_source]
    if not deferred and set(workflow["steps"]) & {"implement", "verify", "review", "fix", "done"}:
        raw = run("mb-work-plan.sh", ["--mb", bank, "--host", "opencode", *plan_args,
                                    "--verify", workflow["verify_cadence"],
                                    "--workflow", workflow["name"], *( ["--qa"] if workflow.get("qa") else [])])
        items = [json.loads(line) for line in raw.splitlines() if line]
    steps = selected_steps(cfg, default, workflow)
    for role, step in steps.items():
        if step == "review" and "reviewer" in overrides:
            overrides[role] = overrides["reviewer"]
    settings = assignments(pipeline, cost, overrides, set(steps))
    for role, spec in settings.items():
        spec["step"] = steps[role]
    for index, item in enumerate(items):
        active = bool(set(workflow["steps"]) & {"implement", "fix"}) and (item["status"] != "done" or
                  current == {"source_path": item["source_path"], "item_no": item["item_no"]})
        item["native_model"] = model_reference(item["model"], "" if item["model_source"] == "cli" else item["thinking"]) if active else ""
        # Work-plan already resolved item aliases, fallback agents and --model for every item role.
        if active:
            settings[f"item:{index}"] = {"agent": item["agent"], "model": item["model"], "native": item["native_model"],
                                        "source_path": item["source_path"], "item_no": item["item_no"], "step": "implement"}
    return {"pipeline": str(pipeline), "workflow": workflow, "items": items, "roles": settings, "driver": driver,
            "execution_deferred": deferred, "existing_sources": existing}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bank")
    parser.add_argument("--execution-source", default="")
    parser.add_argument("--resolve-execution", action="store_true")
    parser.add_argument("--current-item", type=json.loads)
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(sys.stdin.read(), args.bank, args.execution_source, args.resolve_execution, args.current_item)))
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({"error": str(exc)}))
        print(f"opencode-work: {exc}", file=sys.stderr)
        raise SystemExit(1) from None
