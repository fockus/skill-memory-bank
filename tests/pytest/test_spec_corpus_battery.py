"""BL-1: run the spec battery over the REAL corpus, not over a fixture.

Four review rounds and a validator suite of 77 bats cases never noticed that
10 of 10 program specs failed `mb-spec-validate.sh`, because every one of those
cases builds a triple designed to pass and then mutates one thing. That proves
the checker RUNS. Only the corpus proves it DISCRIMINATES — and the first time
anyone pointed it at `.memory-bank/specs/*`, it found 64 violations in the
umbrella alone.

The ledger below is the whole point of the file:

* every failing spec is listed EXPLICITLY, with the reason it fails;
* a spec that is not listed must pass, so a new or newly-broken spec is red;
* a listed spec that starts passing is ALSO red, because a dead entry silently
  re-covers the spec the day it breaks again (the `PENDING_CONVERSION` rule from
  `test_bats_assertion_contract.py`, for the same reason);
* nothing here counts violations: the number changes every time somebody fixes
  a line, and a test pinned to it would be noise.
"""

from __future__ import annotations

import concurrent.futures
import pathlib
import subprocess

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SPECS_DIR = REPO_ROOT / ".memory-bank" / "specs"
VALIDATE = REPO_ROOT / "scripts" / "mb-spec-validate.sh"

# Not a spec: an archive of retired specs, each in its own subdirectory. It has
# no triple of its own, so the battery has nothing to say about it.
NOT_A_SPEC = {"superseded"}

# spec -> why it is allowed to fail TODAY. Every entry is a debt, not a policy.
# Keep the reason concrete enough that a reader can tell when it is discharged.
KNOWN_FAILING = {
    "cursor-extension": "pre-EARS spec: REQ-319 and REQ-322 do not match any EARS pattern",
    "mb-research-tooling-core": "design.md only — requirements.md and tasks.md were never written",
    "parallel-team-execution": "REQ-PTE-070/071/072 are orphans: no task Covers them",
    "sdd-vision-pipeline": "umbrella: 53 gated REQs have no covering Eval, 10 CPR-D drifts, no Seams block",
    "svp-adapt-escalation": "5 CPR-D drifts, no Seams block, and 2 tasks whose Eval tests are not written yet",
    "svp-brief": "no Seams block; task 3's Eval test drives scripts/mb-brief.sh, so it is not structural",
    "svp-contract-test-loop": "8 CPR-D drifts and no Seams block",
    "svp-docs-wiki": "7 CPR-D drifts, no Seams block, task 5's Eval test is not written yet",
    "svp-interview-upgrade": "6 CPR-D drifts and no Seams block",
    "svp-parallel-engine": "10 CPR-D drifts and no Seams block",
    "svp-roadmap-backlog-db": "9 CPR-D drifts, no Seams block, task 5's Eval test is not written yet",
    "svp-spec-review-loop": "REQ-014..017 orphans, 4 gated REQs without Eval, 5 CPR-D drifts, no Seams block",
}


def _spec_dirs() -> list[str]:
    return sorted(
        p.name
        for p in SPECS_DIR.iterdir()
        if p.is_dir() and p.name not in NOT_A_SPEC and not p.name.startswith(".")
    )


def _validate(topic: str) -> tuple[str, int, str]:
    proc = subprocess.run(
        ["bash", str(VALIDATE), topic],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )
    return topic, proc.returncode, (proc.stdout + proc.stderr).strip()


def _verdicts() -> dict[str, tuple[int, str]]:
    topics = _spec_dirs()
    out: dict[str, tuple[int, str]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for topic, rc, log in pool.map(_validate, topics):
            out[topic] = (rc, log)
    return out


def test_the_corpus_is_actually_there() -> None:
    """A green run must not be the sound of an empty loop.

    If the glob or the path ever breaks, every assertion below passes
    vacuously — so the corpus size and the runner are asserted first.
    """
    topics = _spec_dirs()
    assert len(topics) >= 20, f"only {len(topics)} spec dirs found under {SPECS_DIR}"
    assert VALIDATE.is_file(), f"{VALIDATE} is missing"
    for name in KNOWN_FAILING:
        assert (SPECS_DIR / name).is_dir(), f"allowlist names a spec that does not exist: {name}"


def test_every_allowlist_entry_carries_a_reason() -> None:
    empty = [k for k, v in KNOWN_FAILING.items() if not (v or "").strip()]
    assert not empty, f"allowlisted without a reason: {empty}"


def test_no_unlisted_spec_fails_the_battery() -> None:
    verdicts = _verdicts()
    offenders = []
    for topic, (rc, log) in sorted(verdicts.items()):
        if rc != 0 and topic not in KNOWN_FAILING:
            tail = "\n      ".join(log.splitlines()[-6:])
            offenders.append(f"{topic} (exit {rc}):\n      {tail}")
    assert not offenders, (
        "spec(s) fail `mb-spec-validate.sh` and are not in KNOWN_FAILING.\n"
        "Fix the spec, or add it with the concrete reason it may fail:\n\n" + "\n\n".join(offenders)
    )


def test_the_allowlist_has_no_stale_entries() -> None:
    """A fixed spec must leave the ledger the same day it is fixed."""
    verdicts = _verdicts()
    fixed = [t for t in sorted(KNOWN_FAILING) if verdicts.get(t, (1, ""))[0] == 0]
    assert not fixed, (
        "these specs now PASS the battery — delete them from KNOWN_FAILING, "
        "otherwise the entry silently covers them again the next time they break:\n  "
        + "\n  ".join(fixed)
    )


def test_an_unlisted_broken_spec_is_caught(tmp_path) -> None:
    """The mechanism itself, on a spec the corpus does not contain.

    `.memory-bank/specs/**` belongs to other tracks, so a deliberately broken
    spec cannot be planted there to prove the gate bites. It is proven here on
    the same runner instead: a triple with no requirements.md must come back
    non-zero, which is exactly the signal `test_no_unlisted_spec_fails_the_battery`
    reads.
    """
    broken = tmp_path / "specs" / "broken-demo"
    broken.mkdir(parents=True)
    (broken / "tasks.md").write_text(
        "<!-- mb-task:1 -->\n## Task 1: demo\n\n**Covers:** REQ-001\n<!-- /mb-task:1 -->\n",
        encoding="utf-8",
    )
    proc = subprocess.run(
        ["bash", str(VALIDATE), str(broken)],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )
    assert proc.returncode != 0, proc.stdout + proc.stderr
    assert "requirements.md" in (proc.stdout + proc.stderr)
