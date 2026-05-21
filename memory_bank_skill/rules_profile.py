"""Rules profile parser, validator, and resolver.

Stdlib-only implementation — no external dependencies.

Public API (imported by tests):
    parse_profile(path) -> Profile
    parse_profile_safe(path) -> Profile | None
    validate_profile(data) -> list[ValidationError]
    resolve_profile(user_profile, project_profile, task_override) -> ResolvedProfile
"""

from __future__ import annotations

import json
import warnings
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants / allowed values
# ---------------------------------------------------------------------------

ALLOWED_ROLES = ("backend", "frontend", "mobile")
ALLOWED_STACKS = ("go", "python", "javascript", "typescript", "java", "generic")
ALLOWED_ARCHITECTURES = (
    "clean",
    "hexagonal",
    "modular-monolith",
    "microservices",
    "ddd",
    "fsd",
    "mobile-udf",
    "event-driven",
    "custom",
)
ALLOWED_DELIVERY = (
    "tdd",
    "contract-first",
    "api-first",
    "sdd",
    "legacy-safe",
    "exploratory",
)
ALLOWED_STRICTNESS = ("advisory", "warn", "block")

IMMUTABLE_RULES: tuple[str, ...] = (
    "no-placeholders",
    "protected-files",
    "destructive-confirm",
    "fail-fast",
    "dry-kiss-yagni",
    "verification-before-completion",
    "explicit-storage-choice",
)

SCHEMA_VERSION = 1

# Canonical top-level keys (excluding extras and baseline which are allowed)
_CANONICAL_KEYS = frozenset(
    {
        "schema_version",
        "scope",
        "role",
        "stack",
        "architecture",
        "delivery",
        "strictness",
        "extras",
        "baseline",
    }
)

_STRICTNESS_RANK = {"advisory": 0, "warn": 1, "block": 2}

# Built-in defaults (lowest precedence, tagged "baseline")
_DEFAULTS = {
    "role": "backend",
    "stack": "generic",
    "architecture": "clean",
    "delivery": "tdd",
    "strictness": "warn",
}


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Profile:
    schema_version: int
    scope: str  # "user" | "project"
    role: str
    stack: str
    architecture: str
    delivery: str
    strictness: str  # default "warn"
    extras: dict = field(default_factory=dict)


@dataclass(frozen=True)
class ResolvedProfile:
    role: str
    stack: str
    architecture: str
    delivery: str
    strictness: str
    sources: dict  # e.g. {"role": "user", "architecture": "project"}
    immutable_rules: tuple[str, ...]
    prompt_summary: str


@dataclass(frozen=True)
class ValidationError:
    field: str  # dotted path (e.g. "baseline.no-placeholders")
    message: str  # human-readable error


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


def validate_profile(data: dict) -> list[ValidationError]:
    """Validate a profile dict. Returns a list of errors (empty = valid)."""
    errors: list[ValidationError] = []

    # schema_version
    sv = data.get("schema_version")
    if sv != SCHEMA_VERSION:
        errors.append(
            ValidationError(
                field="schema_version",
                message=f"schema_version must be {SCHEMA_VERSION}, got {sv!r}",
            )
        )

    # role
    role = data.get("role", "")
    if role not in ALLOWED_ROLES:
        errors.append(
            ValidationError(
                field="role",
                message=f"role {role!r} not in allowed values: {ALLOWED_ROLES}",
            )
        )

    # stack
    stack = data.get("stack", "")
    if stack not in ALLOWED_STACKS:
        errors.append(
            ValidationError(
                field="stack",
                message=f"stack {stack!r} not in allowed values: {ALLOWED_STACKS}",
            )
        )

    # architecture (optional — defaults applied at resolve time)
    arch = data.get("architecture", "")
    if arch and arch not in ALLOWED_ARCHITECTURES:
        errors.append(
            ValidationError(
                field="architecture",
                message=f"architecture {arch!r} not in allowed values: {ALLOWED_ARCHITECTURES}",
            )
        )

    # delivery
    delivery = data.get("delivery", "")
    if delivery and delivery not in ALLOWED_DELIVERY:
        errors.append(
            ValidationError(
                field="delivery",
                message=f"delivery {delivery!r} not in allowed values: {ALLOWED_DELIVERY}",
            )
        )

    # strictness
    strictness = data.get("strictness", "warn")
    if strictness not in ALLOWED_STRICTNESS:
        errors.append(
            ValidationError(
                field="strictness",
                message=f"strictness {strictness!r} not in allowed values: {ALLOWED_STRICTNESS}",
            )
        )

    # Unknown top-level keys
    for key in data:
        if key not in _CANONICAL_KEYS:
            errors.append(
                ValidationError(
                    field=key,
                    message=f"unknown top-level key {key!r} is not allowed",
                )
            )

    # Baseline block: attempts to disable immutable rules
    baseline = data.get("baseline")
    if isinstance(baseline, dict):
        for rule, value in baseline.items():
            if rule in IMMUTABLE_RULES and value is False:
                errors.append(
                    ValidationError(
                        field=f"baseline.{rule}",
                        message=f"immutable rule {rule!r} cannot be disabled",
                    )
                )

    return errors


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------


def parse_profile(path: Path | str) -> Profile:
    """Parse a JSON profile file. Raises ValueError on validation errors."""
    path = Path(path)
    data = json.loads(path.read_text(encoding="utf-8"))
    errors = validate_profile(data)
    if errors:
        field_names = ", ".join(e.field for e in errors)
        raise ValueError(
            f"Profile {path} has validation errors: {field_names}"
        )
    return Profile(
        schema_version=data["schema_version"],
        scope=data.get("scope", "user"),
        role=data["role"],
        stack=data["stack"],
        architecture=data.get("architecture", _DEFAULTS["architecture"]),
        delivery=data.get("delivery", _DEFAULTS["delivery"]),
        strictness=data.get("strictness", _DEFAULTS["strictness"]),
        extras=dict(data.get("extras") or {}),
    )


def parse_profile_safe(path: Path | str) -> Profile | None:
    """Like parse_profile but returns None on JSON error and emits warnings.warn(...)."""
    path = Path(path)
    try:
        raw = path.read_text(encoding="utf-8")
        json.loads(raw)
    except Exception as exc:
        warnings.warn(
            f"Failed to parse profile {path}: {exc}",
            UserWarning,
            stacklevel=2,
        )
        return None
    try:
        return parse_profile(path)
    except ValueError as exc:
        warnings.warn(
            f"Invalid profile {path}: {exc}",
            UserWarning,
            stacklevel=2,
        )
        return None


# ---------------------------------------------------------------------------
# Resolver
# ---------------------------------------------------------------------------


def resolve_profile(
    user_profile: Profile | None = None,
    project_profile: Profile | None = None,
    task_override: dict | None = None,
) -> ResolvedProfile:
    """Resolve a layered profile. Precedence (ascending): baseline → user → project → task.

    Task can only tighten strictness; it cannot weaken immutable rules.
    """
    dimensions = ("role", "stack", "architecture", "delivery", "strictness")
    result: dict[str, str] = dict(_DEFAULTS)
    sources: dict[str, str] = {dim: "baseline" for dim in dimensions}

    # User profile
    if user_profile is not None:
        for dim in dimensions:
            val = getattr(user_profile, dim, None)
            default = _DEFAULTS.get(dim, "")
            if val and val != default:
                result[dim] = val
                sources[dim] = "user"
            elif val:
                result[dim] = val
                # Only mark "user" if different from baseline; keep "baseline" if same
                # Actually always mark source correctly — user explicitly set it
                sources[dim] = "user"

    # Project profile overrides user
    if project_profile is not None:
        for dim in dimensions:
            val = getattr(project_profile, dim, None)
            if val:
                result[dim] = val
                sources[dim] = "project"

    # Task override (only tightens — for strictness, only higher rank applies)
    if task_override:
        task_strictness = task_override.get("strictness")
        if task_strictness and task_strictness in ALLOWED_STRICTNESS:
            current_rank = _STRICTNESS_RANK.get(result.get("strictness", "warn"), 1)
            task_rank = _STRICTNESS_RANK.get(task_strictness, 1)
            if task_rank > current_rank:
                result["strictness"] = task_strictness
                sources["strictness"] = "task"
        # Other dimensions from task (non-strictness, non-baseline)
        for dim in ("role", "stack", "architecture", "delivery"):
            val = task_override.get(dim)
            if val:
                result[dim] = val
                sources[dim] = "task"
        # Ignore baseline attempts to disable immutable rules (silently)

    # Immutable rules always present regardless of any override
    immutable = IMMUTABLE_RULES

    prompt_summary = _build_prompt_summary(result, sources, immutable)

    return ResolvedProfile(
        role=result["role"],
        stack=result["stack"],
        architecture=result["architecture"],
        delivery=result["delivery"],
        strictness=result["strictness"],
        sources=dict(sources),
        immutable_rules=immutable,
        prompt_summary=prompt_summary,
    )


def _build_prompt_summary(
    result: dict[str, str],
    sources: dict[str, str],
    immutable: tuple[str, ...],
) -> str:
    """Build a compact multi-line prompt summary under 4 KB."""
    lines = [
        "# Active Rule Profile",
        f"role={result['role']}  stack={result['stack']}  architecture={result['architecture']}",
        f"delivery={result['delivery']}  strictness={result['strictness']}",
        "",
        "## Sources",
    ]
    for dim, src in sources.items():
        lines.append(f"  {dim}: {src}")
    lines += [
        "",
        "## Immutable Baseline (non-overridable)",
    ]
    for rule in immutable:
        lines.append(f"  - {rule}: always ON")
    lines += [
        "",
        "## Guidance",
        f"Follow {result['architecture']} architecture with {result['delivery']} delivery.",
        f"Strictness: {result['strictness']} — findings reported at this level.",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI entry point (invoked by mb-profile.sh via python3 -m memory_bank_skill.rules_profile)
# ---------------------------------------------------------------------------


def _cli_main() -> None:
    """Minimal CLI for shell integration. Called as __main__ block."""
    import sys

    args = sys.argv[1:]
    if not args:
        print("Usage: rules_profile.py <subcommand> [args...]", file=sys.stderr)
        sys.exit(1)

    subcommand = args[0]
    rest = args[1:]

    if subcommand == "validate":
        if not rest:
            print("validate requires a file path", file=sys.stderr)
            sys.exit(1)
        path = Path(rest[0])
        if not path.is_file():
            print(f"File not found: {path}", file=sys.stderr)
            sys.exit(1)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"JSON parse error: {exc}", file=sys.stderr)
            sys.exit(2)
        errors = validate_profile(data)
        if errors:
            for err in errors:
                print(f"ERROR [{err.field}]: {err.message}", file=sys.stderr)
            sys.exit(2)
        print("OK")

    elif subcommand == "parse":
        if not rest:
            print("parse requires a file path", file=sys.stderr)
            sys.exit(1)
        try:
            profile = parse_profile(rest[0])
            print(
                json.dumps(
                    {
                        "schema_version": profile.schema_version,
                        "scope": profile.scope,
                        "role": profile.role,
                        "stack": profile.stack,
                        "architecture": profile.architecture,
                        "delivery": profile.delivery,
                        "strictness": profile.strictness,
                        "extras": profile.extras,
                    },
                    indent=2,
                )
            )
        except (ValueError, FileNotFoundError, json.JSONDecodeError) as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(2)

    elif subcommand == "resolve":
        # resolve [--user=<path>] [--project=<path>] [--task-strictness=<level>]
        user_path: str | None = None
        project_path: str | None = None
        task_dict: dict = {}
        for arg in rest:
            if arg.startswith("--user="):
                user_path = arg[len("--user="):]
            elif arg.startswith("--project="):
                project_path = arg[len("--project="):]
            elif arg.startswith("--task-strictness="):
                task_dict["strictness"] = arg[len("--task-strictness="):]

        user_profile: Profile | None = None
        project_profile: Profile | None = None

        if user_path:
            user_profile = parse_profile_safe(user_path)
        if project_path:
            project_profile = parse_profile_safe(project_path)

        resolved = resolve_profile(
            user_profile=user_profile,
            project_profile=project_profile,
            task_override=task_dict or None,
        )
        print(
            json.dumps(
                {
                    "role": resolved.role,
                    "stack": resolved.stack,
                    "architecture": resolved.architecture,
                    "delivery": resolved.delivery,
                    "strictness": resolved.strictness,
                    "sources": resolved.sources,
                    "immutable_rules": list(resolved.immutable_rules),
                    "prompt_summary": resolved.prompt_summary,
                },
                indent=2,
            )
        )

    elif subcommand == "init":
        # init --scope=<user|project> --role=<role> --stack=<stack>
        #      --architecture=<arch> --delivery=<delivery> [--strictness=<s>]
        #      --output=<path>
        params: dict = {}
        output_path: str | None = None
        for arg in rest:
            if "=" in arg:
                k, v = arg.lstrip("-").split("=", 1)
                k = k.lstrip("-")
                if k == "output":
                    output_path = v
                else:
                    params[k] = v
        scope = params.get("scope", "user")
        role = params.get("role", _DEFAULTS["role"])
        stack = params.get("stack", _DEFAULTS["stack"])
        architecture = params.get("architecture", _DEFAULTS["architecture"])
        delivery = params.get("delivery", _DEFAULTS["delivery"])
        strictness = params.get("strictness", _DEFAULTS["strictness"])

        profile_data = {
            "schema_version": SCHEMA_VERSION,
            "scope": scope,
            "role": role,
            "stack": stack,
            "architecture": architecture,
            "delivery": delivery,
            "strictness": strictness,
        }
        errors = validate_profile(profile_data)
        if errors:
            for err in errors:
                print(f"ERROR [{err.field}]: {err.message}", file=sys.stderr)
            sys.exit(2)

        output = json.dumps(profile_data, indent=2) + "\n"
        if output_path:
            out = Path(output_path)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(output, encoding="utf-8")
            print(f"Profile written to {output_path}")
        else:
            print(output)

    elif subcommand == "set":
        # set --scope=<user|project> --file=<path> key=value
        file_path: str | None = None
        kv_pairs: dict = {}
        for arg in rest:
            if arg.startswith("--file="):
                file_path = arg[len("--file="):]
            elif "=" in arg and not arg.startswith("--"):
                k, v = arg.split("=", 1)
                kv_pairs[k] = v
        if not file_path:
            print("set requires --file=<path>", file=sys.stderr)
            sys.exit(1)
        fp = Path(file_path)
        if not fp.is_file():
            print(f"File not found: {file_path}", file=sys.stderr)
            sys.exit(1)
        data = json.loads(fp.read_text(encoding="utf-8"))
        for k, v in kv_pairs.items():
            # Reject attempts to disable immutable rules
            if k == "baseline" or k.startswith("baseline."):
                print("ERROR: cannot modify baseline via set", file=sys.stderr)
                sys.exit(2)
            data[k] = v
        errors = validate_profile(data)
        if errors:
            for err in errors:
                print(f"ERROR [{err.field}]: {err.message}", file=sys.stderr)
            sys.exit(2)
        fp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print(f"Updated {file_path}")

    else:
        print(f"Unknown subcommand: {subcommand}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    _cli_main()
