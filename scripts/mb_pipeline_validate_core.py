"""Pipeline config validation core for mb-pipeline-validate.sh.

Extracted verbatim from the shell heredoc so every file stays <=400 lines
(S2 review [25]). Behaviour is unchanged: reads MB_PIPELINE_PATH, accumulates
errors, prints them and exits 1 when any were found.
"""

import os
import sys

# As a heredoc this ran with sys.path[0] == cwd, which is how the top-level
# `memory_bank_skill` package resolved. Running as a file makes sys.path[0] the
# scripts/ dir, so both the cwd and the skill root are restored explicitly.
sys.path.insert(0, os.getcwd())
sys.path.insert(1, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None

path = os.environ["MB_PIPELINE_PATH"]
errors = []


def err(msg: str) -> None:
    errors.append(msg)


# The PyYAML-optional textual loader lives in a sibling module (review [25]).
from mb_pipeline_minimal_yaml import (  # noqa: E402
    minimal_pipeline_load,
    strip_comment,
)

with open(path, encoding="utf-8") as fh:
    text = fh.read()

if not text.strip():
    err("empty file")

if yaml is None:
    cfg = minimal_pipeline_load(text) if text.strip() else None
else:
    try:
        from memory_bank_skill.pipeline_yaml import (
            PipelineYamlError,
        )
        from memory_bank_skill.pipeline_yaml import (
            load_text as _pipeline_load_text,
        )

        cfg = _pipeline_load_text(text) if text.strip() else None
    except PipelineYamlError as exc:
        err(str(exc))
        cfg = None
    except Exception as exc:
        err(f"YAML parse error: {exc}")
        cfg = None

if cfg is None:
    for e in errors:
        sys.stderr.write(f"[validate] {e}\n")
    sys.exit(1)

if not isinstance(cfg, dict):
    sys.stderr.write("[validate] top-level must be a mapping\n")
    sys.exit(1)

REQUIRED = (
    "version",
    "roles",
    "stage_pipeline",
    "budget",
    "protected_paths",
    "sprint_context_guard",
    "review_rubric",
    "sdd",
)
for k in REQUIRED:
    if k not in cfg:
        err(f"missing required top-level key: {k}")

if cfg.get("version") not in (1, "1"):
    err(f"version: expected 1 or '1', got {cfg.get('version')!r}")

# ── roles ────────────────────────────────────────────────────────────
roles = cfg.get("roles") or {}
if not isinstance(roles, dict):
    err("roles: must be a mapping")
    roles = {}
for rname, rspec in roles.items():
    if not isinstance(rspec, dict):
        err(f"roles.{rname}: must be a mapping")
        continue
    if "agent" not in rspec or not rspec["agent"]:
        err(f"roles.{rname}: missing 'agent'")

# ── stage_pipeline ──────────────────────────────────────────────────
sp = cfg.get("stage_pipeline")
if not isinstance(sp, list) or not sp:
    err("stage_pipeline: must be a non-empty list")
    sp = []

valid_max_cycles = {"stop_for_human", "continue_with_warning", "judge_decides"}
SEVERITY_KEYS = {"blocker", "major", "minor"}
ALLOWED_ROLE_NAMES = set(roles.keys()) | {"auto"}
step_positions: dict[str, int] = {}

for idx, step in enumerate(sp):
    if not isinstance(step, dict):
        err(f"stage_pipeline[{idx}]: must be a mapping")
        continue
    name = step.get("step", f"<idx{idx}>")
    if isinstance(name, str):
        step_positions.setdefault(name, idx)
    role = step.get("role")
    if role is None:
        err(f"stage_pipeline[{name}]: missing 'role'")
    elif role not in ALLOWED_ROLE_NAMES:
        err(f"stage_pipeline[{name}]: role '{role}' not declared in roles")
    elif role == "auto" and name not in {"implement", "fix"}:
        err(f"stage_pipeline[{name}]: role 'auto' is only permitted for implement/fix")
    if name == "sdd":
        required = step.get("required_artifacts")
        if required is not None and (
            not isinstance(required, list) or not all(isinstance(x, str) and x for x in required)
        ):
            err("stage_pipeline[sdd].required_artifacts: must be a list of non-empty strings")
    if name == "review":
        approval_required = step.get("approval_required")
        if approval_required is not None and not isinstance(approval_required, bool):
            err(
                f"stage_pipeline[review].approval_required: must be boolean (got {approval_required!r})"
            )
        gate = step.get("severity_gate") or {}
        if not isinstance(gate, dict):
            err("stage_pipeline[review].severity_gate: must be a mapping")
            gate = {}
        unknown = set(gate.keys()) - SEVERITY_KEYS
        if unknown:
            err(
                f"stage_pipeline[review].severity_gate: unknown keys {sorted(unknown)}; allowed {sorted(SEVERITY_KEYS)}"
            )
        for sev_k, sev_v in gate.items():
            if not isinstance(sev_v, int) or isinstance(sev_v, bool) or sev_v < 0:
                err(f"stage_pipeline[review].severity_gate.{sev_k}: must be int >= 0")
        mc = step.get("max_cycles")
        if not isinstance(mc, int) or isinstance(mc, bool) or mc < 1:
            err(f"stage_pipeline[review].max_cycles: must be int >= 1 (got {mc!r})")
        omc = step.get("on_max_cycles")
        if omc not in valid_max_cycles:
            err(f"stage_pipeline[review].on_max_cycles: '{omc}' not in {sorted(valid_max_cycles)}")
    if name == "fix":
        returns_to = step.get("returns_to")
        if returns_to != "verify":
            err(f"stage_pipeline[fix].returns_to: expected 'verify' (got {returns_to!r})")
    if name == "done":
        require_review_approval = step.get("require_review_approval")
        if require_review_approval is not None and not isinstance(require_review_approval, bool):
            err(
                f"stage_pipeline[done].require_review_approval: must be boolean (got {require_review_approval!r})"
            )

for required_step in ("implement", "verify"):
    if required_step not in step_positions:
        err(f"stage_pipeline: missing required step '{required_step}'")
# stage_pipeline runs implement → review → verify (review before verify); the
# governed workflows.<name> blocks carry their own verify→review→judge ordering.
if "fix" in step_positions and "verify" not in step_positions:
    err("stage_pipeline: fix step requires verify step")

# ── workflow / workflows (optional named /mb work modes) ─────────────
workflow_cfg = cfg.get("workflow") or {}
workflows_cfg = cfg.get("workflows") or {}
ALLOWED_WORKFLOW_STEPS = {
    "discuss",
    "sdd",
    "plan",
    "implement",
    "verify",
    "review",
    "judge",
    "fix",
    "done",
}
VALID_UNTIL = {"reviewer_approved", "severity_gate_pass", "verification_pass", "judge_go", "manual"}
VALID_ENTRYPOINTS = {"freeform_or_topic", "plan_or_spec", "plan_or_spec_or_diff", "diff", "topic"}

if workflow_cfg is not None and not isinstance(workflow_cfg, dict):
    err("workflow: must be a mapping")
    workflow_cfg = {}
if workflows_cfg is not None and not isinstance(workflows_cfg, dict):
    err("workflows: must be a mapping")
    workflows_cfg = {}

if workflows_cfg:
    default_workflow = (
        workflow_cfg.get("default", "execution") if isinstance(workflow_cfg, dict) else "execution"
    )
    aliases = workflow_cfg.get("aliases", {}) if isinstance(workflow_cfg, dict) else {}
    if aliases is not None and not isinstance(aliases, dict):
        err("workflow.aliases: must be a mapping")
        aliases = {}
    for alias_name, target_name in aliases.items():
        if not isinstance(alias_name, str) or not alias_name:
            err("workflow.aliases: alias names must be non-empty strings")
        if not isinstance(target_name, str) or not target_name:
            err(f"workflow.aliases.{alias_name}: target must be a non-empty string")
        elif target_name not in workflows_cfg:
            err(f"workflow.aliases.{alias_name}: target workflow '{target_name}' is not declared")
    resolved_default = (
        aliases.get(default_workflow, default_workflow)
        if isinstance(aliases, dict)
        else default_workflow
    )
    if not isinstance(default_workflow, str) or not default_workflow:
        err("workflow.default: must be a non-empty string")
    elif resolved_default not in workflows_cfg:
        err(f"workflow.default: workflow '{default_workflow}' is not declared")

    for wname, wspec in workflows_cfg.items():
        if not isinstance(wname, str) or not wname:
            err("workflows: workflow names must be non-empty strings")
            continue
        if not isinstance(wspec, dict):
            err(f"workflows.{wname}: must be a mapping")
            continue
        steps = wspec.get("steps")
        if not isinstance(steps, list) or not steps:
            err(f"workflows.{wname}.steps: must be a non-empty list")
            steps = []
        else:
            for i, step_name in enumerate(steps):
                if not isinstance(step_name, str) or not step_name:
                    err(f"workflows.{wname}.steps[{i}]: must be a non-empty string")
                elif step_name not in ALLOWED_WORKFLOW_STEPS:
                    err(f"workflows.{wname}.steps[{i}]: unknown step '{step_name}'")
        entrypoint = wspec.get("entrypoint")
        if entrypoint is not None and entrypoint not in VALID_ENTRYPOINTS:
            err(f"workflows.{wname}.entrypoint: '{entrypoint}' not in {sorted(VALID_ENTRYPOINTS)}")
        interactive = wspec.get("interactive")
        if interactive is not None and not isinstance(interactive, bool):
            err(f"workflows.{wname}.interactive: must be boolean")
        loop = wspec.get("loop")
        if loop is not None:
            if not isinstance(loop, dict):
                err(f"workflows.{wname}.loop: must be a mapping")
                loop = {}
            after = loop.get("after")
            if after is not None and after not in steps:
                err(f"workflows.{wname}.loop.after: step '{after}' is not in workflow steps")
            until = loop.get("until")
            if until is not None and until not in VALID_UNTIL:
                err(f"workflows.{wname}.loop.until: '{until}' not in {sorted(VALID_UNTIL)}")
            returns_to = loop.get("returns_to")
            if returns_to is not None and returns_to not in steps:
                err(
                    f"workflows.{wname}.loop.returns_to: step '{returns_to}' is not in workflow steps"
                )
            max_cycles = loop.get("max_cycles")
            if max_cycles is not None and (
                not isinstance(max_cycles, int)
                or isinstance(max_cycles, bool)
                or max_cycles < 1
            ):
                err(f"workflows.{wname}.loop.max_cycles: must be int >= 1")
            on_max_cycles = loop.get("on_max_cycles")
            if on_max_cycles is not None and on_max_cycles not in valid_max_cycles:
                err(
                    f"workflows.{wname}.loop.on_max_cycles: '{on_max_cycles}' not in {sorted(valid_max_cycles)}"
                )
            approval_required = loop.get("approval_required")
            if approval_required is not None and not isinstance(approval_required, bool):
                err(f"workflows.{wname}.loop.approval_required: must be boolean")
            workflow_gate = loop.get("severity_gate")
            if workflow_gate is not None:
                if not isinstance(workflow_gate, dict):
                    err(f"workflows.{wname}.loop.severity_gate: must be a mapping")
                else:
                    unknown = set(workflow_gate.keys()) - SEVERITY_KEYS
                    if unknown:
                        err(
                            f"workflows.{wname}.loop.severity_gate: unknown keys {sorted(unknown)}; allowed {sorted(SEVERITY_KEYS)}"
                        )
                    for sev_k, sev_v in workflow_gate.items():
                        if not isinstance(sev_v, int) or isinstance(sev_v, bool) or sev_v < 0:
                            err(f"workflows.{wname}.loop.severity_gate.{sev_k}: must be int >= 0")
        if "fix" in steps:
            if "review" not in steps and "judge" not in steps:
                err(f"workflows.{wname}: fix step requires review or judge step")
            if "verify" not in steps:
                err(f"workflows.{wname}: fix step requires verify step")
        if "judge" in steps and "verify" not in steps:
            err(f"workflows.{wname}: judge step requires verify step")
        if "judge" in steps and "review" not in steps:
            err(f"workflows.{wname}: judge step requires review step")

# Per-block validators live in a sibling module (S2 review [25]); the shared
# context is passed explicitly so neither file depends on the other's globals.
import mb_pipeline_validate_blocks as _blocks  # noqa: E402

_blocks.run(cfg, err, strip_comment, valid_max_cycles, yaml, text, SEVERITY_KEYS)

# ── final ─────────────────────────────────────────────────────────
if errors:
    for e in errors:
        sys.stderr.write(f"[validate] {e}\n")
    sys.exit(1)
sys.exit(0)
