"""Rules gate of `/mb team commit`: the project's lint-on-new-code command, mb-rules-check.sh, the track contract.

`team.rules_gate` (pipeline.yaml) is a shell command run once in the tree, e.g. `make lint-new`, with a timeout.
A non-zero exit fails only the selected tracks whose changed files its output names (path match on
boundaries); output that names none of them refuses the commit without sending any track back — the breach
is elsewhere (another track's files, a red baseline). `mb-rules-check.sh` then runs per track on the files
that still exist, with `--base <team baseline>` only when the baseline commit is reachable in a git tree
(otherwise a pre-existing large file would look newly pushed over the threshold); any CRITICAL fails the
track, and so does any failing item of the track's contract, or a contract that is not frozen. A failed track
goes back to `fixing` (the caller re-dispatches it with the findings).
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

import mb_contract as contract
import mb_team_state as st

OUTPUT_TAIL = 40
# Reported, never a send-back: the checker pairs a source with a test by file stem, and package-level tests
# (Go, Kotlin) or a separate test track break that pairing. TDD evidence is plan-verifier's job.
ADVISORY_RULES = ("tdd/delta",)
GENERATED_RE = re.compile(r"Code generated|DO NOT EDIT|@generated")
GATE_TIMEOUT = 1800
CONTRACT_TIMEOUT = 600


def _base(team: dict) -> tuple[str | None, list[str]]:
    """(--base value or None, warnings)."""
    kind = st.run(["bash", st.script("mb_vcs.sh"), "kind", "--tree", team["tree"]]).stdout.strip()
    ok = (
        kind == "git"
        and st.run(
            ["git", "-C", team["tree"], "cat-file", "-e", f"{team['baseline']}^{{commit}}"]
        ).returncode
        == 0
    )
    if ok:
        return team["baseline"], []
    return None, [
        f"baseline {team['baseline'][:12]} is not a reachable git commit ({kind or 'no vcs'}): "
        "the SRP check ran without --base, so a large file is a WARNING, never CRITICAL"
    ]


def _rules_check(team: dict, bank: str, files: list[str], base: str | None) -> tuple[list[str], list[str]]:
    """(blocking CRITICAL findings, advisory findings) of mb-rules-check.sh."""
    csv = ",".join(files)
    cmd = [
        "bash",
        st.script("mb-rules-check.sh"),
        "--files",
        csv,
        "--diff-files",
        csv,
        "--out",
        "json",
    ]
    cmd += ["--base", base] if base else []
    profile = os.path.join(bank, "rules-profile.json")
    if os.path.isfile(profile):
        cmd += ["--profile", profile]
    r = st.run(cmd, cwd=team["tree"])
    try:
        violations = json.loads(r.stdout.strip().splitlines()[-1])["violations"]
    except (ValueError, KeyError, IndexError):
        return [f"mb-rules-check.sh: unreadable output (exit {r.returncode}): {r.stderr.strip()[:200]}"], []
    found = [(v["rule"], f"{v['rule']} {v['file']}:{v['line']} — {v['rationale']}") for v in violations
             if v.get("severity") == "CRITICAL"]
    return [t for rule, t in found if rule not in ADVISORY_RULES], [t for rule, t in found if rule in ADVISORY_RULES]


def _checked(tree: str, files: list[str]) -> list[str]:
    """Files that still exist and are not generated (a generated file's size is not the author's choice)."""
    out = []
    for f in files:
        path = Path(tree) / f
        if path.is_file():
            with path.open(encoding="utf-8", errors="ignore") as fh:
                head = "".join(fh.readline() for _ in range(5))
            if GENERATED_RE.search(head):
                continue
        if path.exists():
            out.append(f)
    return out


def _contract_check(path: Path, tree: str) -> list[str]:
    try:
        result = contract.run(path, tree, CONTRACT_TIMEOUT)
    except (contract.ContractError, OSError, ValueError) as exc:
        return [f"contract {path}: {exc}"]
    found = [
        f"contract {r['section']} {r['id']}: {r['reason']}"
        for r in result["items"]
        if r["status"] == "fail"
    ]
    if result["frozen"] == "no":
        found.append(f"contract {path}: not frozen (no lock) — freeze it before the commit")
    return found


def _names(line: str, path: str) -> bool:
    return re.search(rf"(?:^|[^\w./-]|\./){re.escape(path)}(?![\w/-]|\.\w)", line) is not None


def _gate(
    team: dict, bank: str, owned: dict[str, list[str]]
) -> tuple[dict[str, list[str]], list[str]]:
    """(per-track gate findings, refusal lines when the output names no selected track's file)."""
    gate = st.configs(bank)[2].get("rules_gate")
    if not gate:
        return {}, []
    code, out, err = contract.run_shell(gate, team["tree"], GATE_TIMEOUT)
    if code is None:
        return {}, [f"rules gate `{gate}` timed out after {GATE_TIMEOUT}s"]
    if code == 0:
        return {}, []
    lines = (out + err).strip().splitlines()
    head = f"rules gate `{gate}` exit {code}:"
    hits = {
        tid: [ln for ln in lines if any(_names(ln, f) for f in files)]
        for tid, files in owned.items()
    }
    hits = {tid: found for tid, found in hits.items() if found}
    if not hits:
        return {}, [
            f"{head} its output names no file of the selected tracks; fix the reported files or the "
            "baseline, then commit again:",
            *(f"  {ln}" for ln in lines[-OUTPUT_TAIL:]),
        ]
    return {
        tid: [head, *(f"  {ln}" for ln in found[-OUTPUT_TAIL:])] for tid, found in hits.items()
    }, []


def check(
    team: dict, bank: str, owned: dict[str, list[str]]
) -> tuple[dict[str, list[str]], list[str], list[str]]:
    """(failures per selected track, refusal lines not owned by any track, warnings).

    `owned` maps each selected track id to its changed files (deleted ones included).
    """
    failures, refusal = _gate(team, bank, owned)
    base, warnings = _base(team)
    by_id = {t["id"]: t for t in team["tracks"]}
    for tid, files in owned.items():
        present = _checked(team["tree"], files)
        found, advisory = _rules_check(team, bank, present, base) if present else ([], [])
        warnings += [f"{tid}: {a} (advisory, for the verifier)" for a in advisory]
        if by_id[tid].get("contract"):
            found += _contract_check(Path(bank) / by_id[tid]["contract"], team["tree"])
        if found:
            failures.setdefault(tid, []).extend(found)
    return failures, refusal, warnings


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
