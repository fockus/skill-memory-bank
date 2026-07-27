"""I-147: a bats assertion that cannot fail is not an assertion.

THE TRAP. Bats runs a test body under ``set -e``, but ``! cmd`` is explicitly
EXEMPT from it -- POSIX treats a negated command as a tested condition, so its
non-zero status is swallowed. A negated assertion therefore only fails its test
when it is the LAST command in the body::

    @test "x" { ! grep -q PRESENT f ; true }   -> PASSES though it is false
    @test "y" { ! grep -q PRESENT f }          -> fails correctly

79 such assertions were decorative across 40 files. They were not merely weak:
they were indistinguishable from correct ones by reading, by running the suite,
and even by mutation testing, because a mutation they should have caught was
usually caught by some OTHER sound assertion in the same test.

THE SECOND TRAP. ``[ "$before" = "$(cat f)" ]`` cannot see a lost trailing
newline: command substitution strips trailing newlines from both sides. Use
``snapshot`` + ``assert_unchanged`` (byte-exact ``cmp``) from
``tests/bats/lib/assert.bash``.

This contract makes both unwritable in any file that has been converted. Files
still awaiting conversion are listed in ``PENDING_CONVERSION`` and are checked
in the opposite direction (see ``test_pending_list_is_honest``) so the list can
only shrink.

SCOPE -- WHAT THIS CANNOT SEE (I-148). This check is STATIC, so it only catches
the syntactic half of the class. An assertion can also be dead because it sits
inside a guard that is false in its fixture::

    if [ -f "$PROJECT/.git/hooks/post-commit" ]; then   # never true here
      refute_grep -q "memory-bank" "$PROJECT/.git/hooks/post-commit"
    fi

That is clean by this contract (the negation IS a helper) and green in the
suite, while asserting nothing. Six such assertions survived the I-147
conversion. Whether a guard holds is a runtime property, so no static rule can
decide it -- use ``tools/prove_assertions.py``, which inverts each assertion and
requires the test to go red. Run it when you convert or substantially edit a
bats file; it is a tool, not a gate, because it costs one bats run per
assertion.
"""

from __future__ import annotations

import pathlib
import re

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TESTS = REPO_ROOT / "tests"

# A `!` that OPENS a statement. A `!` on a backslash-continued line is an
# argument (find's `! -name x`), not a negated command, and `if ! cmd` /
# `[ ! -f x ]` do not start with `!` at all.
_NEGATION = re.compile(r"^\s*!\s")

# `[ "$x" = "$(cat f)" ]` and friends -- byte-blind file comparisons.
_CAT_COMPARE = re.compile(
    r'"\$\(cat\b[^)]*\)"\s*(?:=|!=)\s*"\$\(cat\b'
    r'|"\$\{?\w+\}?"\s*(?:=|!=)\s*"\$\(cat\b'
)

# Files not yet converted (I-147 group B + zones frozen for a parallel session).
# This list is a debt ledger, not an exemption: `test_pending_list_is_honest`
# fails if an entry no longer has a violation, so a converted file MUST be
# removed from here.
#
# Three entries were removed when the `|| fail` false positive was fixed:
# test_discuss_transcript, test_mb_interview_artifact_write and
# test_mb_pre_compact route every negation's failure through `||`, so they were
# never violations and never needed conversion. The ledger's honesty test is
# what surfaced that -- it refused to keep carrying files that had become clean.
#
# test_mb_glossary was converted in r5 review [9]: its two `! echo "$stderr" |
# grep -q 'Traceback'` lines were hollow, and a product mutation that leaked a
# real traceback on the glossary-read path kept the test named "not a traceback"
# green. They are `refute_substring` now, so the file leaves the ledger.
PENDING_CONVERSION = frozenset(
    {
        "tests/bats/test_extensions_offer.bats",
        "tests/bats/test_mb_flow_sync.bats",
    }
)


def _test_blocks(lines: list[str]):
    """Yield (start, end) line indices of each `@test ... { ... }` body."""
    i = 0
    while i < len(lines):
        if lines[i].startswith("@test "):
            depth = 0
            j = i
            while j < len(lines):
                depth += lines[j].count("{") - lines[j].count("}")
                if depth == 0 and j > i:
                    break
                j += 1
            yield i, j
            i = j
        i += 1


_QUOTED = re.compile(r"""'[^']*'|"[^"]*\"""")


def _logical_line(lines: list[str], start: int) -> str:
    """Join backslash-continued physical lines into one logical statement."""
    out = [lines[start]]
    k = start
    while k < len(lines) - 1 and lines[k].rstrip().endswith("\\"):
        k += 1
        out.append(lines[k])
    return " ".join(s.rstrip().rstrip("\\") for s in out)


def _failure_is_handled(statement: str) -> bool:
    """True when the negation's failure is routed somewhere, e.g. `|| fail ...`.

    `! cmd || fail "msg"` is SAFE at any position: if `cmd` succeeds, `! cmd` is
    false and `|| fail` fires. Reported by S2 as a false positive, because the
    continuation exemption only ever inspected the PREVIOUS physical line, so
    this shape was flagged:

        ! grep -q 'X' f \\
          || fail "X must be absent"

    `||` inside quotes is not an operator, so quoted spans are removed first.
    """
    return "||" in _QUOTED.sub("", statement)


def scan(path: pathlib.Path) -> tuple[list[str], list[str], list[str]]:
    """Return (hollow_negations, last_position_negations, cat_comparisons)."""
    lines = path.read_text(errors="replace").split("\n")
    hollow: list[str] = []
    last_position: list[str] = []
    cat_compares: list[str] = []

    for start, end in _test_blocks(lines):
        body = [
            (k, lines[k])
            for k in range(start + 1, end)
            if lines[k].strip() and not lines[k].strip().startswith("#")
        ]
        last_idx = body[-1][0] if body else None
        for pos, (k, line) in enumerate(body):
            if not _NEGATION.match(line):
                continue
            if pos > 0 and body[pos - 1][1].rstrip().endswith("\\"):
                continue  # continuation line: the `!` is an argument
            if _failure_is_handled(_logical_line(lines, k)):
                continue  # `! cmd || fail ...` -- the failure IS routed
            entry = f"{path.relative_to(REPO_ROOT)}:{k + 1}: {line.strip()[:90]}"
            (last_position if k == last_idx else hollow).append(entry)

    for k, line in enumerate(lines, 1):
        if _CAT_COMPARE.search(line):
            cat_compares.append(f"{path.relative_to(REPO_ROOT)}:{k}: {line.strip()[:90]}")
    return hollow, last_position, cat_compares


def _bats_files() -> list[pathlib.Path]:
    return sorted(TESTS.rglob("*.bats"))


def _rel(path: pathlib.Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def test_no_hollow_negations_in_converted_files() -> None:
    """A negated assertion must be the last command in its test, or be a helper.

    Use `refute_grep` / `refute_cmd` / `refute_substring` from
    `tests/bats/lib/assert.bash` instead -- they are plain commands, so `set -e`
    sees their failure wherever they appear.
    """
    offenders: list[str] = []
    for path in _bats_files():
        if _rel(path) in PENDING_CONVERSION:
            continue
        hollow, _, _ = scan(path)
        offenders.extend(hollow)

    assert not offenders, (
        "Hollow negation(s) -- these assertions CANNOT fail their test because "
        "`! cmd` is exempt from `set -e` unless it is the final command.\n"
        "Replace with refute_grep / refute_cmd / refute_substring "
        "(tests/bats/lib/assert.bash):\n  " + "\n  ".join(offenders)
    )


def test_no_byte_blind_file_comparisons_in_converted_files() -> None:
    """`"$(cat a)" = "$(cat b)"` silently ignores trailing-newline differences."""
    offenders: list[str] = []
    for path in _bats_files():
        if _rel(path) in PENDING_CONVERSION:
            continue
        _, _, cats = scan(path)
        offenders.extend(cats)

    assert not offenders, (
        "Command-substitution file comparison(s) -- `$(cat ...)` strips trailing "
        "newlines from BOTH sides, so a write that truncates the final newline "
        "compares equal. Use snapshot + assert_unchanged (cmp -s):\n  " + "\n  ".join(offenders)
    )


def test_pending_list_is_honest() -> None:
    """Every PENDING entry must still exist and still have a violation.

    Without this the allowlist becomes permanent cover: a file could be fixed
    (or deleted, or renamed) and silently keep its exemption, and the next
    hollow assertion added to it would go unnoticed.
    """
    stale: list[str] = []
    for rel in sorted(PENDING_CONVERSION):
        path = REPO_ROOT / rel
        if not path.exists():
            stale.append(f"{rel} (file no longer exists)")
            continue
        hollow, _, cats = scan(path)
        if not hollow and not cats:
            stale.append(f"{rel} (converted -- remove it from PENDING_CONVERSION)")

    assert not stale, (
        "PENDING_CONVERSION is out of date. It is a shrinking debt ledger for "
        "I-147, so a file that no longer violates the contract must be removed "
        "from it:\n  " + "\n  ".join(stale)
    )


def test_legitimately_last_negations_are_not_flagged() -> None:
    """The check must not punish a correct, final-position negation.

    A precision guard: the contract's value depends on it never crying wolf, or
    the next person will add a blanket exemption instead of fixing a real one.
    There are many correct final-position negations in this repo and NONE of
    them may appear in the hollow list.
    """
    total_last = 0
    for path in _bats_files():
        hollow, last_position, _ = scan(path)
        total_last += len(last_position)
        overlap = set(hollow) & set(last_position)
        assert not overlap, f"classified as both hollow and last-position: {overlap}"

    assert total_last > 50, (
        "Expected many legitimately-last negations to still be present and "
        f"NOT flagged; found only {total_last}. If this dropped sharply, the "
        "classifier may have started mislabelling them as hollow."
    )


def test_shared_assert_helper_exists_and_is_loadable() -> None:
    helper = TESTS / "bats" / "lib" / "assert.bash"
    assert helper.is_file(), "tests/bats/lib/assert.bash is the shared helper"
    body = helper.read_text()
    for fn in (
        "refute_grep",
        "assert_grep",
        "refute_cmd",
        "refute_substring",
        "snapshot",
        "assert_unchanged",
    ):
        assert f"{fn}()" in body, f"{fn} missing from the shared helper"
    # refute_grep must reject grep's exit 2 (error), not just exit 0 (match).
    assert '[ "$rc" -eq 1 ]' in body, (
        "refute_grep must require exit 1 exactly, so a mistyped path (grep exit "
        "2) fails the assertion instead of reading as 'absent'"
    )


def test_negation_routed_to_or_fail_is_not_flagged(tmp_path: pathlib.Path) -> None:
    """`! cmd || fail ...` is safe at ANY position and must not be reported.

    Regression for a false positive found by S2: the continuation exemption only
    inspected the previous physical line, so a negation that ended in `\\` and
    routed its failure to `|| fail` on the NEXT line was flagged. Only two
    occurrences existed and both are already converted, so nothing was blocked --
    but a lint that cries wolf gets a blanket exemption added instead of a fix,
    which would cost more than the class it guards.
    """
    probe = tmp_path / "test_probe.bats"
    probe.write_text(
        '@test "safe: continued to || fail" {\n'
        "  ! grep -q 'X' f \\\n"
        '    || fail "X must be absent"\n'
        "  true\n"
        "}\n"
        '@test "safe: same line || fail" {\n'
        "  ! grep -q 'X' f || fail \"X must be absent\"\n"
        "  true\n"
        "}\n"
        '@test "hollow: nothing handles the failure" {\n'
        "  ! grep -q 'X' f\n"
        "  true\n"
        "}\n"
    )
    # scan() reports paths relative to REPO_ROOT, so probe under it.
    target = TESTS / "bats" / "zz_contract_probe.bats"
    target.write_text(probe.read_text())
    try:
        hollow, _, _ = scan(target)
    finally:
        target.unlink()

    assert len(hollow) == 1, f"expected only the genuinely hollow one, got: {hollow}"
    assert "hollow" not in hollow[0] or True
    assert hollow[0].endswith("! grep -q 'X' f"), hollow[0]


def test_quoted_pipe_is_not_mistaken_for_an_or_operator() -> None:
    """`||` inside quotes must not make a hollow negation look handled.

    Under-reporting is the dangerous direction for this contract: a missed
    hollow assertion is exactly the defect it exists to catch.
    """
    assert not _failure_is_handled("! grep -q 'A || B' f")
    assert not _failure_is_handled('! grep -q "A || B" f')
    assert _failure_is_handled('! grep -q X f || fail "msg"')
