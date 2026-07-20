#!/usr/bin/env python3
"""Prove that each assertion in a bats file can actually FAIL its test (I-148).

    python3 tools/prove_assertions.py tests/bats/test_foo.bats [more.bats...]
    python3 tools/prove_assertions.py --list tests/bats/test_foo.bats

═══════════════════════════════════════════════════════════════════════════════
READ THIS FIRST: THE POLARITY IS INVERTED
═══════════════════════════════════════════════════════════════════════════════

Every other check in this repo reports green = good. THIS ONE DOES NOT.

The tool rewrites one assertion at a time to demand the OPPOSITE of what it
claims, then runs the enclosing test and requires it to go RED.

    RED   = the assertion is ALIVE and participates in the test's verdict.  GOOD.
    GREEN = the assertion is DEAD. Its failure does not fail the test.      BAD.

A green line in this tool's output is a defect report, not a pass. Someone will
misread this; the output labels every line to make it hard.

═══════════════════════════════════════════════════════════════════════════════
WHY INVERSION, AND WHY IT IS THE EXACT TEST
═══════════════════════════════════════════════════════════════════════════════

The defect class (I-147) is precisely: *this line's failure does not fail the
test*. Inverting the assertion makes the line's condition false on purpose. If
the test still passes, the line's failure demonstrably does not fail the test --
which IS the defect, by definition. Inversion is not a proxy for hollowness, it
is its inverse-test.

TWO MECHANISMS PRODUCE A DEAD ASSERTION, AND ONLY ONE HAS A STATIC LINT:

1. SYNTACTIC -- the `!` trap. Bats runs test bodies under `set -e`, but `! cmd`
   is exempt: POSIX treats a negated command as a tested condition, so its
   failure is swallowed unless it is the LAST command in the body.

       @test "x" { ! grep -q PRESENT f ; true }   -> PASSES though it is false

   `tests/pytest/test_bats_assertion_contract.py` kills this class statically,
   in milliseconds, on every commit. It is fully handled; you do not need this
   tool for it.

2. SEMANTIC -- the dead guard. THIS is why this tool exists.

       @test "uninstall removes our git hooks" {
         run_adapter install "$PROJECT"
         run_adapter uninstall "$PROJECT"
         if [ -f "$PROJECT/.git/hooks/post-commit" ]; then
           refute_grep -q "memory-bank" "$PROJECT/.git/hooks/post-commit"
         fi
       }

   Read it: correct. Run it: green. Lint it: clean -- the negation was already
   converted to a helper. But the fixture starts with NO post-commit hook, so
   install creates ours and uninstall deletes it outright; the guard is false
   and the body never executes. The test asserts nothing about git hooks at
   all, which is the one thing its name promises.

   No static analysis can distinguish that from a legitimate conditional --
   whether the guard holds depends on runtime state. Only running it can tell
   you, and only inversion makes a dead line announce itself.

   Six assertions of this exact shape survived the I-147 conversion in
   kilo/pi/git-hooks/cursor and were caught only by this technique. Without it
   we would have closed I-147 with dead assertions in "converted" files.

═══════════════════════════════════════════════════════════════════════════════
WORKED EXAMPLE -- the same defect seen by all three checks
═══════════════════════════════════════════════════════════════════════════════

Reproduced by re-inserting the pre-I-147 guard into `test_kilo_adapter.bats`
(`kilo: uninstall removes rules file and git hooks`), then asking each check:

    $ bats tests/bats/test_kilo_adapter.bats
      failing tests: 0                                    <- suite says FINE

    $ python3 -m pytest tests/pytest/test_bats_assertion_contract.py
      5 passed                                            <- lint says FINE
      (correctly: the negation IS inside a helper; the trap here is the guard)

    $ python3 tools/prove_assertions.py tests/bats/test_kilo_adapter.bats
      ALIVE :51   kilo: install creates .kilocode/rules/memory-bank.md
      ...
      DEAD  :113  kilo: uninstall removes rules file and git hooks
              ^ inverted to: assert_grep -q "memory-bank: managed hook" ...
              ^ the test still PASSED, so this line's failure
                does not fail the test. It asserts nothing.
      alive=8  dead=1  skipped(no inversion rule)=0
      $ echo $?  ->  1

The green suite and the green lint are both telling the truth about what they
measure. Neither measures whether the line runs.

THE FIX IS NOT TO DELETE THE LINE. Assert the end state the fixture actually
produces (here: `refute_file "$PROJECT/.git/hooks/post-commit"`, because
uninstall removes the hook it created), and add a SEPARATE test with a fixture
that reaches the guarded branch (here: seed a pre-existing user hook, then
assert uninstall restores it without our marker). Both then prove ALIVE.

═══════════════════════════════════════════════════════════════════════════════
SAFETY: THE FILE UNDER TEST IS NEVER WRITTEN TO
═══════════════════════════════════════════════════════════════════════════════

The mutated copy goes to a sibling `<name>.prove-tmp` and bats runs THAT. The
real file is opened read-only for the whole run.

This is the second design. The first rewrote the file in place and restored it
in a `try/finally`, which I reported as "cannot leave a mutated file behind"
WITHOUT ever interrupting a run to check. It was wrong: SIGTERM terminates the
interpreter without unwinding the stack, so `finally` never executes -- and
SIGTERM is exactly what a CI or harness timeout sends. A killed run left an
assertion silently inverted (`refute_grep` -> `assert_grep`): the file still
parsed, the suite could stay green, and the line read as deliberate. The tool
for proving tests honest was able to make them dishonest, and the claim that it
could not was itself an untested assertion -- the very defect this tool exists
to catch.

Running the copy REMOVES the window instead of narrowing it. There is no
instant at which the real file differs from HEAD, so SIGTERM, SIGINT, an
uncaught exception and even `kill -9` cannot corrupt it; the worst case is a
stray sidecar, which the next run sweeps. Signal handlers and the exit hook now
only tidy up, and `verify_untouched` asserts the property at the end of every
file rather than trusting it.

═══════════════════════════════════════════════════════════════════════════════
COST, AND WHY THIS IS A TOOL AND NOT A GATE
═══════════════════════════════════════════════════════════════════════════════

One bats run per assertion. On the adapter/e2e suites that is seconds to
minutes each, so as a per-commit gate it multiplies CI time by the assertion
count -- not survivable, and a gate people disable is worse than no gate. Run
it deliberately:

  * on a file you are converting or substantially editing;
  * as the completion criterion for an I-147 ledger entry, rather than trusting
    a green suite.

═══════════════════════════════════════════════════════════════════════════════
COVERAGE IS PARTIAL, ON PURPOSE, AND REPORTED
═══════════════════════════════════════════════════════════════════════════════

Only the forms in INVERSIONS below can be mechanically inverted. Anything else
in a test body is reported as SKIPPED and counted separately. A tool for this
defect class must never imply coverage it does not have -- silent gaps are the
disease, not the cure.
"""

from __future__ import annotations

import argparse
import atexit
import os
import pathlib
import re
import signal
import subprocess
import sys
import time

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]

# (pattern, replacement) applied to the ONE assertion line under test.
# Each flips the line's claim to its opposite; a live assertion then fails.
INVERSIONS: list[tuple[re.Pattern[str], str]] = [
    # helper assertions (tests/bats/lib/assert.bash)
    (re.compile(r"^(\s*)refute_grep\b"), r"\1assert_grep"),
    (re.compile(r"^(\s*)assert_grep\b"), r"\1refute_grep"),
    (re.compile(r"^(\s*)refute_substring\b"), r"\1assert_substring"),
    (re.compile(r"^(\s*)assert_substring\b"), r"\1refute_substring"),
    # "must not exist" -> "must exist"
    (re.compile(r"^(\s*)refute_file\s+(.*)$"), r"\1[ -e \2 ]"),
    # "must be unchanged" -> "must differ"
    (re.compile(r"^(\s*)assert_unchanged\s+(.*)$"), r"\1refute_cmd cmp -s \2"),
    # "must fail" -> "must succeed" (drop the refutation wrapper)
    (re.compile(r"^(\s*)refute_cmd\s+(.*)$"), r"\1\2"),
    # bare command-position grep used as a positive assertion
    (re.compile(r"^(\s*)grep\s+(.*)$"), r"\1refute_grep \2"),
]

_TEST_HEADER = re.compile(r'^@test\s+"(.*)"\s*\{')

# Lines that are assertions we can invert.
_ASSERTION_START = re.compile(
    r"^\s*(refute_grep|assert_grep|refute_substring|assert_substring"
    r"|refute_file|assert_unchanged|refute_cmd|grep)\b"
)


def enclosing_test(lines: list[str], idx: int) -> str | None:
    for k in range(idx, -1, -1):
        m = _TEST_HEADER.match(lines[k])
        if m:
            return m.group(1)
    return None


def invert(line: str) -> str | None:
    for pattern, repl in INVERSIONS:
        if pattern.search(line):
            return pattern.sub(repl, line, count=1)
    return None


def find_assertions(lines: list[str]) -> list[int]:
    """Indices of invertible assertion lines that sit inside a @test body."""
    out: list[int] = []
    for i, line in enumerate(lines):
        if not _ASSERTION_START.match(line):
            continue
        if enclosing_test(lines, i) is None:
            continue  # helper function defined outside any test
        # a continuation of a previous line is an argument, not a statement
        if i > 0 and lines[i - 1].rstrip().endswith("\\"):
            continue
        out.append(i)
    return out


def run_test(path: pathlib.Path, name: str) -> tuple[bool, str]:
    """Run only `name` from `path`. Returns (went_red, output)."""
    proc = subprocess.run(
        ["bats", str(path), "-f", re.escape(name)],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        check=False,
    )
    out = proc.stdout + proc.stderr
    return ("not ok" in out), out


def sidecar_path(path: pathlib.Path) -> pathlib.Path:
    """Where the MUTATED copy is written. The original is never modified.

    Earlier this tool rewrote the test file in place and restored it in a
    `try/finally`. That is not safe: SIGTERM terminates the interpreter WITHOUT
    unwinding the stack, so `finally` never runs -- and SIGTERM is exactly what
    a CI or harness timeout sends. A killed run left an assertion silently
    inverted (`refute_grep` -> `assert_grep`): the file still parsed, the suite
    could stay green, and the line looked deliberate. A tool for proving tests
    honest was able to make them dishonest.

    Running the COPY removes the window rather than narrowing it: there is no
    instant at which the real file differs from HEAD, so no signal, crash or
    `kill -9` can corrupt it. Signals now only need to sweep a stray sidecar.

    The sidecar is a SIBLING because bats tests derive the repo root from
    `dirname "$BATS_TEST_FILENAME"`; a temp directory would break that. The name
    does not end in `.bats`, so no `*.bats` glob (suite runners, the I-147 lint)
    ever collects it.
    """
    return path.with_name(path.name + ".prove-tmp")


# Sidecars currently on disk, so a signal handler can sweep them. Nothing here
# is load-bearing for correctness of the file under test -- that file is never
# written -- this is only tidiness.
_SIDECARS: set[pathlib.Path] = set()


def _sweep_sidecars() -> None:
    for sc in list(_SIDECARS):
        try:
            sc.unlink(missing_ok=True)
        except OSError:  # pragma: no cover
            pass
        _SIDECARS.discard(sc)


def _on_signal(signum, _frame):  # pragma: no cover - exercised via kill(1)
    print(f"\n-- caught signal {signum}; sweeping {len(_SIDECARS)} sidecar(s)", file=sys.stderr)
    _sweep_sidecars()
    # Re-raise with the default disposition so the exit status is honest
    # (128+signum) instead of pretending this was a clean shutdown.
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)


def install_signal_handlers() -> None:
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, _on_signal)
    atexit.register(_sweep_sidecars)


# A sidecar belonging to a LIVE run is rewritten before every single assertion,
# so it is always seconds old. Anything older than this is from a run that died.
# The slowest single assertion in this repo (e2e install/uninstall) is ~30s, so
# 600s is generous in the safe direction.
STALE_AFTER_SECONDS = 600


def sweep_all_stale_sidecars(now: float | None = None) -> int:
    """Remove `*.prove-tmp` under tests/ that are OLD, from any file.

    Global, because the per-file version was useless in exactly the case it
    existed for: a sidecar left by a killed run on file X was only cleaned by a
    later run on X, and a run on any other file walked straight past it. I
    missed that because I tested the sweep on the same file I had killed -- the
    one configuration in which the limitation cannot show.

    A stray sidecar is not inert: `extensions-offer` rsyncs the whole repo, so a
    `.prove-tmp` present during that suite fails someone else's run (I-152).

    AGE-GATED, because global + unconditional is destructive to a CONCURRENT run
    of this tool by another agent -- several of us share this working tree. On
    its first run the global sweep deleted a stray belonging to another agent's
    killed run; had that run been alive, I would have pulled the file out from
    under its bats invocation and handed them a failure that was mine. Deleting
    only old sidecars keeps the I-152 fix without introducing a cross-agent
    race: a live run's sidecar can never be old.
    """
    now = time.time() if now is None else now
    removed = 0
    for sc in sorted((REPO_ROOT / "tests").rglob("*.prove-tmp")):
        try:
            age = now - sc.stat().st_mtime
        except OSError:  # pragma: no cover - vanished under us; nothing to do
            continue
        if age < STALE_AFTER_SECONDS:
            print(
                f"-- leaving {sc.relative_to(REPO_ROOT)} alone ({age:.0f}s old): "
                "another run of this tool may be using it",
                file=sys.stderr,
            )
            continue
        print(
            f"-- removing stale sidecar {sc.relative_to(REPO_ROOT)} "
            f"({age / 60:.0f} min old, from an earlier killed run)",
            file=sys.stderr,
        )
        sc.unlink()
        removed += 1
    return removed


def verify_untouched(path: pathlib.Path, pristine: str) -> bool:
    """Belt-and-braces: the file under test must be byte-identical to entry.

    The safety property is now structural (we never write to it), but a property
    that has never been checked is exactly what this whole round was about, so
    it is asserted rather than assumed.
    """
    if path.read_text() == pristine:
        return True
    print(
        f"\n!!!! {path} CHANGED during the run -- this must be impossible.\n"
        "!!!! Do not trust these results; inspect `git diff` before committing.",
        file=sys.stderr,
    )
    return False


def prove_file(path: pathlib.Path, verbose: bool = False) -> tuple[int, int, int]:
    """Returns (alive, dead, skipped)."""
    original = path.read_text()
    lines = original.split("\n")
    targets = find_assertions(lines)
    alive = dead = skipped = 0
    sidecar = sidecar_path(path)

    print(f"\n=== {path.relative_to(REPO_ROOT)}  ({len(targets)} invertible assertions)")
    _SIDECARS.add(sidecar)
    try:
        for i in targets:
            name = enclosing_test(lines, i)
            mutated = invert(lines[i])
            if mutated is None or name is None:
                skipped += 1
                print(f"  SKIP  :{i + 1}  (no inversion rule) {lines[i].strip()[:70]}")
                continue
            patched = list(lines)
            patched[i] = mutated
            sidecar.write_text("\n".join(patched))
            went_red, output = run_test(sidecar, name)

            if went_red:
                alive += 1
                print(f"  ALIVE :{i + 1}  {name[:66]}")
            else:
                dead += 1
                print(f"  DEAD  :{i + 1}  {name[:66]}")
                print(f"          ^ inverted to: {mutated.strip()[:76]}")
                print("          ^ the test still PASSED, so this line's failure")
                print("            does not fail the test. It asserts nothing.")
                if verbose:
                    print("          " + output.replace("\n", "\n          ")[:600])
    finally:
        sidecar.unlink(missing_ok=True)
        _SIDECARS.discard(sidecar)
        verify_untouched(path, original)
    return alive, dead, skipped


def list_assertions(path: pathlib.Path) -> None:
    lines = path.read_text().split("\n")
    for i in find_assertions(lines):
        print(f"{path.relative_to(REPO_ROOT)}:{i + 1}: {lines[i].strip()[:100]}")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Prove each bats assertion can fail (I-148). "
        "RED under inversion = alive = good; GREEN = dead = defect.",
    )
    ap.add_argument("files", nargs="+", help="bats files to prove")
    ap.add_argument("--list", action="store_true", help="list assertions, run nothing")
    ap.add_argument("-v", "--verbose", action="store_true", help="show bats output for dead lines")
    args = ap.parse_args()

    paths = [
        pathlib.Path(f) if pathlib.Path(f).is_absolute() else REPO_ROOT / f for f in args.files
    ]
    for p in paths:
        if not p.is_file():
            print(f"no such file: {p}", file=sys.stderr)
            return 2

    install_signal_handlers()
    # A previous run may have been SIGKILLed (uncatchable) mid-mutation. Sweep
    # before doing anything else so a stale inversion cannot be mistaken for
    # the file's real content -- or worse, used as this run's baseline.
    sweep_all_stale_sidecars()

    if args.list:
        for p in paths:
            list_assertions(p)
        return 0

    total_alive = total_dead = total_skipped = 0
    for p in paths:
        a, d, s = prove_file(p, args.verbose)
        total_alive += a
        total_dead += d
        total_skipped += s

    print(
        f"\n{'=' * 70}\n"
        f"alive={total_alive}  dead={total_dead}  skipped(no inversion rule)={total_skipped}\n"
        f"{'=' * 70}"
    )
    if total_dead:
        print(
            f"{total_dead} assertion(s) DEAD: the test passed while demanding the\n"
            "opposite of what the assertion claims. Each one asserts nothing.\n"
            "Usual cause is a guard (`if [ -f X ]`) that is false in this fixture,\n"
            "so the body never runs -- fix by asserting the end state the fixture\n"
            "actually produces, and add a separate test for the guarded scenario.\n"
            "Do NOT delete the assertion to make this tool quiet."
        )
    return 1 if total_dead else 0


if __name__ == "__main__":
    raise SystemExit(main())
