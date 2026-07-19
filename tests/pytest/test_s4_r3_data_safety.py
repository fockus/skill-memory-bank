"""S4 round-3 regressions: the sync must never destroy hand-written bytes.

Every finding in this round is the same failure shape — a code path that was
allowed to guess which bytes were generated and which were the user's, and got
it wrong. So every assertion here is BYTE-EXACT on the surviving content; a
substring check would have passed against each of these bugs.

Covered: R3-001 inline fence markers · R3-002 prefix-sharing group slug ·
R3-005 CRLF outside the fence · R3-006 rstrip of the user's prefix ·
R3-007 group header at EOF · R3-008 mode narrowing on stat failure ·
R3-010 over-eager path detector.
"""

from __future__ import annotations

import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
SYNC = SCRIPTS / "mb-roadmap-sync.sh"
sys.path.insert(0, str(SCRIPTS))

from mb_backlog_validate import validate_brief  # noqa: E402
from mb_fs_atomic import atomic_write  # noqa: E402
from mb_roadmap_render import (  # noqa: E402
    FenceError,
    append_block,
    find_fence,
    strip_bootstrap_groups,
)

FENCE_OPEN = "<!-- mb-roadmap-auto -->"
FENCE_CLOSE = "<!-- /mb-roadmap-auto -->"


def _bank(tmp_path: Path, roadmap: str) -> Path:
    mb = tmp_path / ".memory-bank"
    for sub in ("plans", "specs", "context"):
        (mb / sub).mkdir(parents=True)
    with (mb / "roadmap.md").open("w", encoding="utf-8", newline="") as fh:
        fh.write(roadmap)
    return mb


def _run(mb: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SYNC), str(mb), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _read(path: Path) -> str:
    with path.open(encoding="utf-8", newline="") as fh:
        return fh.read()


# ── R3-001: an inline marker pair is prose, not a fence ───────────────────────


def test_inline_fence_markers_are_refused_not_treated_as_a_pair() -> None:
    """`Example: <!-- open --> generated <!-- close -->` is documentation.

    Accepting it as a fence made the next sync overwrite the user's sentence
    with the generated block.
    """
    with pytest.raises(FenceError, match="alone on its line"):
        find_fence("x " + FENCE_OPEN + " gen " + FENCE_CLOSE + " y\n")


def test_sync_refuses_an_inline_fence_and_leaves_the_file_byte_identical(
    tmp_path: Path,
) -> None:
    original = f"# Roadmap\n\nExample: {FENCE_OPEN} generated {FENCE_CLOSE} — see docs.\n"
    mb = _bank(tmp_path, original)

    result = _run(mb)

    assert result.returncode != 0
    assert "malformed_fence" in result.stderr
    assert _read(mb / "roadmap.md") == original


@pytest.mark.parametrize(
    "text",
    [
        f"a\n{FENCE_OPEN}\nG\n{FENCE_CLOSE}\nb\n",
        f"{FENCE_OPEN}\n{FENCE_CLOSE}\n",
        f"a\r\n{FENCE_OPEN}\r\nG\r\n{FENCE_CLOSE}\r\nb\r\n",
    ],
)
def test_well_formed_fences_still_parse(text: str) -> None:
    span = find_fence(text)
    assert span is not None
    start, end = span
    assert text[start:].startswith(FENCE_OPEN)
    assert text[:end].rstrip("\r\n").endswith(FENCE_CLOSE)


# ── R3-002 / R3-007: group-block removal must hit exactly the right slug ──────


def test_discovered_slug_does_not_delete_a_prefix_sharing_group() -> None:
    """`foo` must not consume the NON-discovered `foo.bar` block."""
    text = f"{FENCE_OPEN}\nGEN\n{FENCE_CLOSE}\n## Group: foo.bar\nKEEP NON-DISCOVERED\n"
    assert strip_bootstrap_groups(text, {"foo"}) == text


@pytest.mark.parametrize("other", ["foo.bar", "foo-bar", "foobar", "foo:1"])
def test_prefix_sharing_slugs_survive_byte_exact(other: str) -> None:
    text = f"{FENCE_OPEN}\nGEN\n{FENCE_CLOSE}\n## Group: {other}\nUSER PROSE\n"
    assert strip_bootstrap_groups(text, {"foo"}) == text


def test_the_actually_discovered_group_is_still_removed() -> None:
    text = f"{FENCE_OPEN}\nGEN\n{FENCE_CLOSE}\n## Group: foo\nBODY\n## Other\nKEEP\n"
    expected = f"{FENCE_OPEN}\nGEN\n{FENCE_CLOSE}\n## Other\nKEEP\n"
    assert strip_bootstrap_groups(text, {"foo"}) == expected


def test_group_header_on_the_last_line_without_newline_is_removed() -> None:
    """A file whose final byte ends the header still gets the block stripped."""
    text = f"{FENCE_OPEN}\nGEN\n{FENCE_CLOSE}\n## Group: foo"
    assert strip_bootstrap_groups(text, {"foo"}) == f"{FENCE_OPEN}\nGEN\n{FENCE_CLOSE}\n"


def test_group_header_at_eof_with_a_body_and_no_trailing_newline() -> None:
    text = f"{FENCE_OPEN}\nGEN\n{FENCE_CLOSE}\n## Group: foo\nBODY WITHOUT NEWLINE"
    assert strip_bootstrap_groups(text, {"foo"}) == f"{FENCE_OPEN}\nGEN\n{FENCE_CLOSE}\n"


# ── R3-005: CRLF outside the fence survives a sync ───────────────────────────


def test_crlf_outside_the_fence_is_preserved_byte_exact(tmp_path: Path) -> None:
    original = (
        "# Roadmap\r\n\r\nBEFORE MANUAL\r\n\r\n"
        f"{FENCE_OPEN}\r\nOLD\r\n{FENCE_CLOSE}\r\n"
        "\r\nAFTER MANUAL\r\n"
    )
    mb = _bank(tmp_path, original)

    assert _run(mb).returncode == 0

    now = _read(mb / "roadmap.md")

    # The expected boundaries are HARD-CODED, not computed with find_fence
    # (R4-009). Deriving them from the production parser made it its own oracle:
    # if find_fence started swallowing every CRLF after the closing marker, the
    # sync would eat the user's blank line and this test would still pass,
    # because both sides of the comparison would shift together.
    expected_head = "# Roadmap\r\n\r\nBEFORE MANUAL\r\n\r\n"
    expected_tail = "\r\nAFTER MANUAL\r\n"

    assert now.startswith(expected_head), repr(now[:60])
    assert now.endswith(expected_tail), repr(now[-60:])
    # Exactly ONE line ending after the closing marker, then the user's blank
    # line: `...-->\r\n` + `\r\n` + `AFTER MANUAL\r\n`.
    assert now.count(FENCE_CLOSE) == 1
    close_at = now.index(FENCE_CLOSE) + len(FENCE_CLOSE)
    assert now[close_at:] == "\r\n" + expected_tail
    # And the whole file stays CRLF -- no mixed endings introduced.
    assert now.count("\n") == now.count("\r\n")


def test_crlf_roadmap_sync_is_idempotent(tmp_path: Path) -> None:
    original = f"# Roadmap\r\n\r\nKEEP\r\n\r\n{FENCE_OPEN}\r\nOLD\r\n{FENCE_CLOSE}\r\n"
    mb = _bank(tmp_path, original)

    assert _run(mb).returncode == 0
    first = _read(mb / "roadmap.md")
    assert _run(mb).returncode == 0
    assert _read(mb / "roadmap.md") == first
    assert _run(mb, "--check").returncode == 0


# ── R3-006: the user's prefix is never rstripped ─────────────────────────────


def test_fence_injection_without_h1_preserves_trailing_whitespace(
    tmp_path: Path,
) -> None:
    original = "MANUAL WITHOUT H1   \n\n\n"
    mb = _bank(tmp_path, original)

    assert _run(mb).returncode == 0

    now = _read(mb / "roadmap.md")
    assert now.startswith(original), f"user prefix was rewritten: {now[:40]!r}"


@pytest.mark.parametrize(
    ("text", "expected_prefix"),
    [
        ("A   \n\n\n", "A   \n\n\n"),
        ("A\n", "A\n\n"),
        ("A", "A\n\n"),
        ("A\n\n", "A\n\n"),
    ],
)
def test_append_block_adds_only_the_missing_separator(text: str, expected_prefix: str) -> None:
    out = append_block(text, "BLOCK")
    assert out == expected_prefix + "BLOCK"
    assert out.startswith(text)


def test_append_block_on_empty_text_is_just_the_block() -> None:
    assert append_block("", "BLOCK") == "BLOCK"


# ── R3-008: a stat failure must not silently narrow the mode ─────────────────


def test_stat_failure_preserves_bytes_and_mode(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    target = tmp_path / "bank.md"
    target.write_text("ORIGINAL\n", encoding="utf-8")
    os.chmod(target, 0o664)

    real_stat = os.stat

    def flaky(path, *a, **k):  # type: ignore[no-untyped-def]
        if str(path) == str(target):
            raise OSError(5, "transient EIO")
        return real_stat(path, *a, **k)

    monkeypatch.setattr(os, "stat", flaky)

    with pytest.raises(OSError):
        atomic_write(target, "NEW\n")

    monkeypatch.setattr(os, "stat", real_stat)
    assert target.read_text(encoding="utf-8") == "ORIGINAL\n"
    assert stat.S_IMODE(os.stat(target).st_mode) == 0o664
    assert not list(tmp_path.glob(".mb-atomic.*.tmp"))


def test_existing_mode_is_preserved_on_a_normal_write(tmp_path: Path) -> None:
    target = tmp_path / "bank.md"
    target.write_text("ORIGINAL\n", encoding="utf-8")
    os.chmod(target, 0o640)

    atomic_write(target, "NEW\n")

    assert target.read_text(encoding="utf-8") == "NEW\n"
    assert stat.S_IMODE(os.stat(target).st_mode) == 0o640


# ── R3-010: `input/output` is behaviour, not a file path ─────────────────────


@pytest.mark.parametrize(
    "brief",
    [
        "the serializer must preserve input/output semantics",
        "the reader must support read/write modes",
        "the client must handle request/response pairs correctly",
        "the router must map the on/off toggle when the flag is set",
    ],
)
def test_conceptual_slash_briefs_are_accepted(brief: str) -> None:
    ok, why = validate_brief(brief)
    assert ok, f"legitimate behavioural brief rejected: {why}"


@pytest.mark.parametrize(
    "brief",
    [
        "the agent must edit scripts/runner",
        "the agent must edit README.md",
        "should update scripts/mb-x.sh handler",
        "the agent must read /etc/passwd",
        "the agent must edit ./x",
        "the agent must edit ../x",
        "the agent must edit ~/.config/app.conf",
        r"the agent must edit C:\Users\dev\notes.txt",
        "must update src/main.py before the run",
        "must walk a/b/c when resolving",
    ],
)
def test_real_paths_are_still_refused(brief: str) -> None:
    ok, why = validate_brief(brief)
    assert not ok, f"path brief slipped through: {brief}"
    assert why == "contains file path"


# ── R4-002: line numbers in prose, and extensionless relative paths ──────────


@pytest.mark.parametrize(
    "brief",
    [
        "the parser must retry at line 42 when input fails",
        "the parser must retry at Line 42 when input fails",
        "the job must retry on строка 42 failure",
        "must handle the retry at :42 when it fails",
        "the fix must land at #L42 in the handler",
        "must handle lines 10 when parsing",
    ],
)
def test_prose_line_numbers_are_refused(brief: str) -> None:
    ok, why = validate_brief(brief)
    assert not ok, f"line number slipped through: {brief}"
    assert why == "contains line number"


@pytest.mark.parametrize(
    "brief",
    [
        "the agent must edit custom/runner",
        "the agent must edit widget/handler",
        "the agent must open foo/bar",
    ],
)
def test_extensionless_relative_paths_are_refused(brief: str) -> None:
    ok, why = validate_brief(brief)
    assert not ok, f"relative path slipped through: {brief}"
    assert why == "contains file path"


@pytest.mark.parametrize(
    "brief",
    [
        "the serializer must preserve input/output semantics",
        "the reader must support read/write modes",
        "the client must handle request/response pairs correctly",
        "the router must map the on/off toggle when the flag is set",
        "the queue must keep producer/consumer ordering stable",
    ],
)
def test_conceptual_pairs_survive_the_narrower_rule(brief: str) -> None:
    ok, why = validate_brief(brief)
    assert ok, f"legitimate behavioural brief rejected: {why}"
