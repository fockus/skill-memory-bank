#!/usr/bin/env python3
"""Verify that a test run actually finished — and that every file you meant to
run produced a log at all (I-147 follow-up).

    python3 tools/check_run_complete.py run.log [more.log ...]
    python3 tools/check_run_complete.py --expect tests/e2e/a.bats:a.log \\
                                        --expect tests/bats/b.bats:b.log

═══════════════════════════════════════════════════════════════════════════════
WHY THIS EXISTS
═══════════════════════════════════════════════════════════════════════════════

Twice in one hour, two people read a partial bats log as a final result:

    ok=29  not ok=0      <- reads as "green" by every habit either of us had
    plan  1..56          <- the run was simply still going

`not ok = 0` is not evidence of success. It is equally consistent with "nothing
failed" and "nothing else has run yet". A killed, crashed, or still-running
suite produces exactly the same shape as a clean one, and the only thing that
distinguishes them is the count TAP already told you to expect.

That is one level of the failure. The other has no snippet at all: a file that
was never run produces no log, and a report assembled per-file cannot notice a
file missing from its own set. One of us checked each file that was run and
never checked that each intended file HAD been run.

Both are the same mistake at different levels — trusting the members without
checking against a declared total. Hence two modes:

    per-log   : ok == plan, no `not ok`, and a plan line that EXISTS
    set-level : every intended file has a log, and every log is complete

═══════════════════════════════════════════════════════════════════════════════
A MISSING PLAN LINE IS THE LOUDEST FAILURE, NOT THE QUIETEST
═══════════════════════════════════════════════════════════════════════════════

A log with no `1..N` is what a run that died at startup looks like — a bad
`load`, a syntax error, a missing interpreter. It also has zero `not ok` lines,
so every naive check calls it green. Treating "no plan" as "nothing to verify"
would rebuild the exact hole this tool closes, so it is a hard error.

═══════════════════════════════════════════════════════════════════════════════
THE SECOND WAY TO MANUFACTURE A FALSE GREEN: A RUN THAT SPANS AN EDIT
═══════════════════════════════════════════════════════════════════════════════

Truncation is detectable after the fact — `ok` is short of `plan`. This one is
not. The run finishes, the plan count matches, every test says `ok`, and yet the
tests did not all run against the same code:

    $ bats ... > run.log &          <- suite running in the background
    $ <edit a script under test>    <- tests before this saw the old file,
    $ wait                             tests after it saw the new one
    plan=384 ok=384 not_ok=0        <- looks exactly like a clean run

Nothing in the log is wrong, so nothing in the log can reveal it. It happened
here: a 384-test suite was reported complete while a script under test had been
edited mid-run.

    python3 tools/check_run_complete.py run.log \
        --since run.stamp --watch scripts/ --watch commands/discuss.md

`--since` is the run START (an epoch, or a file whose mtime is the start — the
ergonomic form is `: > run.stamp` immediately before launching the run).
Any watched file modified at or after that instant fails the run.

The rule is deliberately blunt: an edit landing AFTER the last test also fails.
An mtime says when a file changed, never which tests preceded it, and a log
written after an edit is indistinguishable from one written before it. A guard
that guesses which tests were affected is worse than one that refuses.

Exit 0 only when every log checked is provably complete AND no watched file was
touched during the run. Exit 1 = completeness failure, 3 = the run spans an
edit; when both are true the exit is 1 (the more fundamental) and BOTH are
printed, because neither may hide the other.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import pathlib
import re
import sys

PLAN_RE = re.compile(r"^1\.\.(\d+)\s*$")
OK_RE = re.compile(r"^ok\b")
NOT_OK_RE = re.compile(r"^not ok\b")
# bats prints `# skip` on the ok line; skipped tests still count toward the plan.
SKIP_RE = re.compile(r"^ok\b.*# skip")


class Result:
    def __init__(self, log: pathlib.Path) -> None:
        self.log = log
        self.plan: int | None = None
        self.ok = 0
        self.not_ok = 0
        self.skipped = 0
        self.problems: list[str] = []

    @property
    def complete(self) -> bool:
        return not self.problems

    def summary(self) -> str:
        plan = "MISSING" if self.plan is None else str(self.plan)
        return f"plan={plan} ok={self.ok} not_ok={self.not_ok} skipped={self.skipped}"


def check_log(log: pathlib.Path) -> Result:
    r = Result(log)
    if not log.exists():
        r.problems.append("log does not exist")
        return r

    text = log.read_text(errors="replace")
    for line in text.splitlines():
        m = PLAN_RE.match(line.strip())
        if m:
            # A second plan line means two runs were concatenated into one file,
            # which makes every count below ambiguous.
            if r.plan is not None:
                r.problems.append(
                    f"two plan lines ({r.plan} then {m.group(1)}) — "
                    "logs from separate runs are concatenated"
                )
            r.plan = int(m.group(1))
            continue
        if NOT_OK_RE.match(line):
            r.not_ok += 1
        elif OK_RE.match(line):
            r.ok += 1
            if SKIP_RE.match(line):
                r.skipped += 1

    if r.plan is None:
        r.problems.append(
            "NO PLAN LINE — the run died before reporting one (bad load, syntax "
            "error, missing interpreter). Zero failures here means nothing."
        )
        return r
    if r.plan == 0 and (r.ok or r.not_ok):
        r.problems.append(f"plan is 1..0 but {r.ok + r.not_ok} results present")
    total = r.ok + r.not_ok
    if total < r.plan:
        r.problems.append(
            f"TRUNCATED: {total} of {r.plan} tests reported — the run was "
            "killed, crashed, or is still writing to this file"
        )
    elif total > r.plan:
        r.problems.append(f"OVER-REPORTED: {total} results for a plan of {r.plan}")
    if r.not_ok:
        r.problems.append(f"{r.not_ok} failing test(s)")
    return r


def resolve_since(ref: str) -> float:
    """`--since` is an epoch, or a file whose mtime marks the run start."""
    try:
        return float(ref)
    except ValueError:
        pass
    path = pathlib.Path(ref)
    if not path.exists():
        raise SystemExit(
            f"--since {ref!r} is neither a number nor an existing file; "
            "pass the epoch of the run start, or a stamp file created just "
            "before it (`: > run.stamp`)"
        )
    return path.stat().st_mtime


def expand_watched(paths: list[str]) -> tuple[list[pathlib.Path], list[str]]:
    """Expand directories to the files under them; report what is missing.

    A directory that silently checks nothing would rebuild the hole this guard
    closes, so expansion is explicit and an empty directory is reported.
    """
    files: list[pathlib.Path] = []
    missing: list[str] = []
    for raw in paths:
        path = pathlib.Path(raw)
        if not path.exists():
            missing.append(raw)
            continue
        if path.is_dir():
            found = sorted(q for q in path.rglob("*") if q.is_file())
            if not found:
                missing.append(f"{raw} (directory contains no files)")
            files.extend(found)
        else:
            files.append(path)
    return files, missing


def check_staleness(paths: list[str], since: float) -> list[str]:
    """Every watched file touched at or after `since` invalidates the run."""
    problems: list[str] = []
    files, missing = expand_watched(paths)
    for m in missing:
        problems.append(
            f"WATCHED FILE MISSING: {m} — it cannot be shown unchanged, and a "
            "path that vanished during a run is at least as suspicious as an edit"
        )
    for f in files:
        mtime = f.stat().st_mtime
        if mtime >= since:
            stamp = _dt.datetime.fromtimestamp(mtime).isoformat(timespec="seconds")
            problems.append(
                f"run spans an edit to {f} at {stamp} — tests before and after "
                "that write did not run against the same file"
            )
    return problems


def parse_expect(spec: str) -> tuple[str, pathlib.Path]:
    """`<intended-file>:<log>` — split on the LAST colon so paths may contain one."""
    if ":" not in spec:
        raise SystemExit(f"--expect needs '<test-file>:<log>', got {spec!r}")
    src, _, log = spec.rpartition(":")
    return src, pathlib.Path(log)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Fail unless every test run provably finished.",
    )
    ap.add_argument("logs", nargs="*", help="TAP/bats log files to check")
    ap.add_argument(
        "--expect",
        action="append",
        default=[],
        metavar="FILE:LOG",
        help="a test file you INTENDED to run, and the log it should have produced",
    )
    ap.add_argument(
        "--watch",
        action="append",
        default=[],
        metavar="PATH",
        help="a file or directory the run depended on; fails if touched during "
        "it. Takes ONE path — repeat the flag for several",
    )
    ap.add_argument(
        "--since",
        # NOT "REF": a git ref is the intuitive reading and it is wrong — this
        # is an mtime comparison, so it needs a wall-clock start, not a commit.
        metavar="STAMP|EPOCH",
        help="run start: a file whose mtime is the start (`: > run.stamp` just "
        "before the run), or an epoch. NOT a git ref",
    )
    args = ap.parse_args()

    if not args.logs and not args.expect:
        ap.error("give at least one log, or one --expect FILE:LOG")
    if args.watch and not args.since:
        ap.error(
            "--watch needs --since: without a run start there is nothing to "
            "compare an mtime against, and a check that cannot fail is worse "
            "than no check"
        )

    failures = 0
    entries = 0  # every thing we were asked to account for
    checked: list[Result] = []

    # ── set level: did every intended file even produce a log? ──────────────
    for spec in args.expect:
        entries += 1
        src, log = parse_expect(spec)
        if not pathlib.Path(src).exists():
            print(f"MISSING SOURCE  {src} — intended file does not exist")
            failures += 1
            continue
        if not log.exists():
            print(f"NEVER RAN       {src} — no log at {log}")
            failures += 1
            continue
        r = check_log(log)
        checked.append(r)
        label = "COMPLETE" if r.complete else "INCOMPLETE"
        print(f"{label:<15} {src} [{r.summary()}]")
        for p in r.problems:
            print(f"                  ! {p}")
        failures += 0 if r.complete else 1

    # ── per-log level ──────────────────────────────────────────────────────
    for raw in args.logs:
        entries += 1
        r = check_log(pathlib.Path(raw))
        checked.append(r)
        label = "COMPLETE" if r.complete else "INCOMPLETE"
        print(f"{label:<15} {raw} [{r.summary()}]")
        for p in r.problems:
            print(f"                  ! {p}")
        failures += 0 if r.complete else 1

    # ── staleness level: did the code change under the run? ────────────────
    stale_problems: list[str] = []
    if args.watch:
        stale_problems = check_staleness(args.watch, resolve_since(args.since))
        if stale_problems:
            print()
            for p in stale_problems:
                print(f"STALE RUN       ! {p}")
        else:
            print(
                f"\nUNCHANGED       {len(expand_watched(args.watch)[0])} watched "
                "file(s) predate the run"
            )
    else:
        # Silence must not read as "the staleness check passed".
        print(
            "\nNOT CHECKED     no --watch paths given, so nothing was compared "
            "against the run start; pass --watch to check for mid-run edits"
        )

    total_tests = sum(r.ok + r.not_ok for r in checked if r.plan is not None)
    # Count against everything ASKED FOR, not just what produced a Result — a
    # file that never ran has no Result, and omitting it from the denominator
    # would hide exactly the set-level gap this mode exists to catch.
    print(
        f"\n{entries - failures}/{entries} run(s) provably complete; "
        f"{total_tests} test result(s) accounted for"
    )
    if failures:
        print(
            "REFUSING to call this green: an unfinished run and a clean run are "
            "the same shape until you compare against the plan."
        )
    if stale_problems:
        print(
            "REFUSING to call this green: the code changed while the run was in "
            "flight, so these results describe no single version of the tree."
        )
    # Distinct codes for distinct failures; completeness wins when both apply so
    # a green exit stays reserved for 0 and neither failure can mask the other.
    if failures:
        return 1
    return 3 if stale_problems else 0


if __name__ == "__main__":
    sys.exit(main())
