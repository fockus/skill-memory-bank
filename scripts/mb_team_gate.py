"""Rules gate of `/mb team commit`: the project's lint-on-new-code command plus mb-rules-check.sh.

`team.rules_gate` (pipeline.yaml) is a shell command run once in the tree, e.g. `make lint-new`; a non-zero
exit fails every selected track whose owned file the output names (all of them when it names none).
`mb-rules-check.sh --base <team baseline>` then runs per track on its owned files; any CRITICAL — a file this
change pushed over the SRP threshold, a domain→infrastructure import, a source without a test — fails the
track, and so does any failing item of the track's frozen contract (mb_contract.py). A failed track goes
back to `fixing` (the caller re-dispatches it with the findings).
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import mb_contract as contract
import mb_team_state as st

OUTPUT_TAIL = 40


def _rules_check(team: dict, bank: str, files: list[str]) -> list[str]:
    cmd = [
        "bash",
        st.script("mb-rules-check.sh"),
        "--files",
        ",".join(files),
        "--diff-files",
        ",".join(files),
        "--base",
        team["baseline"],
        "--out",
        "json",
    ]
    profile = os.path.join(bank, "rules-profile.json")
    if os.path.isfile(profile):
        cmd += ["--profile", profile]
    r = st.run(cmd, cwd=team["tree"])
    try:
        violations = json.loads(r.stdout.strip().splitlines()[-1])["violations"]
    except (ValueError, KeyError, IndexError):
        return [
            f"mb-rules-check.sh: unreadable output (exit {r.returncode}): {r.stderr.strip()[:200]}"
        ]
    return [
        f"{v['rule']} {v['file']}:{v['line']} — {v['rationale']}"
        for v in violations
        if v.get("severity") == "CRITICAL"
    ]


def _contract_check(path: Path, tree: str) -> list[str]:
    try:
        result = contract.run(path, tree, 600)
    except (contract.ContractError, OSError) as exc:
        return [f"contract {path}: {exc}"]
    return [f"contract {r['section']} {r['id']}: {r['reason']}" for r in result["items"] if r["status"] == "fail"]


def check(team: dict, bank: str, owned: dict[str, list[str]]) -> dict[str, list[str]]:
    """{track id: findings} for the selected tracks that fail; `owned` maps track id → its changed files."""
    failures: dict[str, list[str]] = {}
    gate = st.configs(bank)[2].get("rules_gate")
    if gate:
        r = st.run(["bash", "-c", gate], cwd=team["tree"])
        if r.returncode != 0:
            out = (r.stdout + r.stderr).strip().splitlines()[-OUTPUT_TAIL:]
            named = [
                tid for tid, files in owned.items() if any(f in line for f in files for line in out)
            ]
            for tid in named or list(owned):
                failures[tid] = [
                    f"rules gate `{gate}` exit {r.returncode}:",
                    *(f"  {ln}" for ln in out),
                ]
    by_id = {t["id"]: t for t in team["tracks"]}
    for tid, files in owned.items():
        found = _rules_check(team, bank, files) if files else []
        if by_id[tid].get("contract"):
            found += _contract_check(Path(bank) / by_id[tid]["contract"], team["tree"])
        if found:
            failures.setdefault(tid, []).extend(found)
    return failures


def send_back(bank: str, topic: str, ids: list[str]) -> None:
    """Failed tracks → `fixing` (counts a fix cycle; the return is collected again)."""
    with st.locked(bank, topic) as team:
        for t in team["tracks"]:
            if t["id"] in ids and st.can_move(t["status"], "fixing"):
                t["status"], t["fix_cycle"], t["collected"] = (
                    "fixing",
                    t.get("fix_cycle", 0) + 1,
                    False,
                )
