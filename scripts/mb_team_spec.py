"""Wave-end whole-spec verification for /mb team.

Track verifiers check the track prompt (or one task) only, so a REQ no task carries through is never
checked. When every track is finished and collected, `next` asks for `spec_verify <spec>` per spec the team
implements (`init --plan` or a track `--source` under `specs/<topic>/`): the orchestrator runs plan-verifier
in spec mode over the whole spec (`mb_spec_coverage.py` is its floor) and records the result with
`team spec-check <spec> --gaps N --report F`. A record goes stale when the set of collected returns changes
(a new track, a fix cycle); recorded gaps → `stop_human spec-gaps:<spec>` until next-wave tracks or backlog
items take them and a fresh check records 0.
"""

from __future__ import annotations

import re

SPEC_RE = re.compile(r"^(specs/[^/]+)/")  # bank-relative only: `api/specs/v1/openapi.yaml` is not a bank spec
ANY_SPEC_RE = re.compile(r"(?:^|/)(specs/[^/]+)(?:/|$)")


def normalize(arg: str) -> str | None:
    """`specs/<topic>` from what a user types: absolute, `.memory-bank/specs/x/`, `specs/x/tasks.md`."""
    m = ANY_SPEC_RE.search(arg.rstrip("/"))
    return m.group(1) if m else None


def team_specs(team: dict) -> list[str]:
    paths = [team.get("plan"), *(t.get("source") for t in team["tracks"])]
    return sorted({m.group(1) for p in paths if p and (m := SPEC_RE.search(p))})


def wave_key(team: dict) -> str:
    """Identity of the collected returns: changes with every new collect, including a fix cycle."""
    return ",".join(
        f"{t['id']}:{t.get('fix_cycle', 0)}" for t in team["tracks"] if t.get("collected")
    )


def actions(team: dict) -> list[str]:
    """`spec_verify` for unchecked or stale specs, else `stop_human spec-gaps` for recorded gaps; [] when clear."""
    checks, key = team.get("spec_checks") or {}, wave_key(team)
    todo = [s for s in team_specs(team) if (checks.get(s) or {}).get("wave") != key]
    if todo:
        return [f"spec_verify {s}" for s in todo]
    return [f"stop_human spec-gaps:{s}" for s in team_specs(team) if checks[s]["gaps"] > 0]
