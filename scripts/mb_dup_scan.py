"""Cross-track duplication candidates for `/mb team collect` (language-agnostic, stdlib only).

Each track's verifier and reviewer see only that track's diff, so the same mechanism written by two tracks
passes both. At wave end `collect` scans the lines every finished track added since the team baseline:
lines are normalised (identifiers → `i` except a small keyword set, strings → `S`, numbers → `0`), comment
and trivial lines are dropped, and every window of WINDOW consecutive meaningful lines is hashed. A window
found in files of two different tracks is a candidate pair; consecutive windows merge into one pair.
Candidates, not verdicts: the orchestrator reads both places and decides (extract, or accept).
"""

from __future__ import annotations

import re
from pathlib import Path

import mb_team_state as st

WINDOW = 5
MAX_FILE_BYTES = 1_000_000
KEYWORDS = frozenset(
    ["func", "def", "fn", "function", "class", "struct", "interface", "type", "return", "if", "else", "elif", "for", "while", "switch", "case", "default", "break", "continue", "go", "defer", "select", "map", "chan", "var", "let", "const", "new", "try", "catch", "except", "finally", "raise", "throw", "import", "from", "package", "async", "await", "yield", "in", "not", "and", "or", "is", "nil", "null", "None", "true", "false", "True", "False", "self", "this"]
)
STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`[^`]*`')
NUMBER_RE = re.compile(r"\b\d+(?:\.\d+)?\b")
IDENT_RE = re.compile(r"[A-Za-z_]\w*")
COMMENT_PREFIXES = ("//", "#", "/*", "*", "--", ";")
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def normalize(line: str) -> str | None:
    """Normalised form of a meaningful line; None for blank, comment or trivial lines."""
    s = line.strip()
    if not s or s.startswith(COMMENT_PREFIXES):
        return None
    s = NUMBER_RE.sub("0", STRING_RE.sub("S", s))
    tokens = 0

    def ident(m: re.Match) -> str:
        nonlocal tokens
        tokens += 1
        return m.group(0) if m.group(0) in KEYWORDS else "i"

    s = IDENT_RE.sub(ident, s)
    return "".join(s.split()) if tokens >= 2 else None


def added_lines(diff: str) -> dict[str, list[tuple[int, str]]]:
    """Added lines per new path from a unified diff, with their line numbers in the new file."""
    out: dict[str, list[tuple[int, str]]] = {}
    path, no = None, 0
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif m := HUNK_RE.match(line):
            no = int(m.group(1))
        elif path and line.startswith("+"):
            out.setdefault(path, []).append((no, line[1:]))
            no += 1
        elif path and line.startswith(" "):
            no += 1
    return out


def scan(by_track: dict[str, dict[str, list[tuple[int, str]]]]) -> list[dict]:
    windows: dict[tuple, list[tuple[str, str, int]]] = {}
    meaningful: dict[tuple[str, str], list[int]] = {}
    for tid, files in by_track.items():
        for path, lines in files.items():
            kept = [(no, n) for no, text in lines if (n := normalize(text))]
            meaningful[(tid, path)] = [no for no, _ in kept]
            for i in range(len(kept) - WINDOW + 1):
                windows.setdefault(tuple(n for _, n in kept[i : i + WINDOW]), []).append(
                    (tid, path, i)
                )
    starts: dict[tuple, list[tuple[int, int]]] = {}
    for hits in windows.values():
        for x, (ta, pa, ia) in enumerate(hits):
            for tb, pb, ib in hits[x + 1 :]:
                if ta == tb:
                    continue
                key, pos = (
                    ((ta, pa, tb, pb), (ia, ib))
                    if (ta, pa) < (tb, pb)
                    else ((tb, pb, ta, pa), (ib, ia))
                )
                starts.setdefault(key, []).append(pos)
    pairs = []
    for (ta, pa, tb, pb), pos in sorted(starts.items()):
        pos.sort()
        run_start, run_len = pos[0], 1
        for prev, cur in zip(pos, [*pos[1:], None], strict=True):
            if cur == (prev[0] + 1, prev[1] + 1):
                run_len += 1
                continue
            pairs.append(
                {
                    "a": {"track": ta, "path": pa, "line": meaningful[(ta, pa)][run_start[0]]},
                    "b": {"track": tb, "path": pb, "line": meaningful[(tb, pb)][run_start[1]]},
                    "lines": run_len + WINDOW - 1,
                }
            )
            run_start, run_len = cur, 1
    return pairs


def wave_duplicates(
    team: dict, tree: str, diff: str, untracked: list[str], finished: set[str]
) -> list[dict]:
    """Candidate pairs across the finished tracks' changes since the baseline (diff + untracked files)."""
    added = added_lines(diff)
    for rel in untracked:
        f = Path(tree) / rel
        if f.is_file() and f.stat().st_size <= MAX_FILE_BYTES:
            text = f.read_text(encoding="utf-8", errors="ignore")
            if "\0" not in text:
                added[rel] = list(enumerate(text.splitlines(), 1))
    by_track: dict[str, dict] = {}
    for path, lines in added.items():
        owner = next(
            (t["id"] for t in team["tracks"] if t["id"] in finished and st.owns(t, path)), None
        )
        if owner:
            by_track.setdefault(owner, {})[path] = lines
    return scan(by_track) if len(by_track) >= 2 else []
