"""Cross-track duplication candidates at `team collect` (each track's reviewer sees only its own diff)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import mb_dup_scan as dup  # noqa: E402
from test_mb_team_state import _bank, _cli  # noqa: E402

MAPPER_A = """func mapError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		writeJSON(w, 404, map[string]string{"error": "not found"})
	case errors.Is(err, ErrForbidden):
		writeJSON(w, 403, map[string]string{"error": "forbidden"})
	default:
		writeJSON(w, 500, map[string]string{"error": "internal"})
	}
}
"""
# The same mechanism written again by another track, renamed and re-worded.
MAPPER_B = """func toHTTP(rw http.ResponseWriter, e error) {
	switch {
	case errors.Is(e, ErrMissing):
		respond(rw, 404, map[string]string{"message": "missing"})
	case errors.Is(e, ErrDenied):
		respond(rw, 403, map[string]string{"message": "denied"})
	default:
		respond(rw, 500, map[string]string{"message": "oops"})
	}
}
"""


def _lines(text: str) -> list[tuple[int, str]]:
    return list(enumerate(text.splitlines(), 1))


def test_same_mechanism_in_two_tracks_is_one_candidate_pair():
    pairs = dup.scan(
        {"A": {"a/errors.go": _lines(MAPPER_A)}, "B": {"b/http.go": _lines("// b\n" + MAPPER_B)}}
    )
    assert len(pairs) == 1
    p = pairs[0]
    assert (p["a"]["track"], p["a"]["path"], p["a"]["line"]) == ("A", "a/errors.go", 1)
    assert (p["b"]["track"], p["b"]["path"], p["b"]["line"]) == ("B", "b/http.go", 2)
    assert p["lines"] >= dup.WINDOW


def test_copies_inside_one_track_are_not_reported():
    assert (
        dup.scan(
            {"A": {"a/x.go": _lines(MAPPER_A), "a/y.go": _lines(MAPPER_B)}, "B": {"b/z.go": []}}
        )
        == []
    )


def test_unrelated_code_is_not_reported():
    other = "def add(a, b):\n    total = a + b\n    log.info('sum %s', total)\n    return total\n"
    assert dup.scan({"A": {"a/x.go": _lines(MAPPER_A)}, "B": {"b/y.py": _lines(other * 3)}}) == []


def test_added_lines_follow_hunk_headers():
    diff = (
        "diff --git a/x.go b/x.go\n--- a/x.go\n+++ b/x.go\n@@ -1,2 +1,3 @@\n keep\n+new one\n keep2\n"
        "@@ -10,0 +11,2 @@\n+n11\n+n12\n"
    )
    assert dup.added_lines(diff) == {"x.go": [(2, "new one"), (11, "n11"), (12, "n12")]}


def test_collect_reports_cross_track_duplicates(tmp_path):
    bank = _bank(tmp_path)
    tree = bank.parent
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(tree)).returncode == 0
    for tid in ("A", "B"):
        assert (
            _cli(
                bank,
                "track",
                "add",
                tid,
                "--task",
                f"t {tid}",
                "--dod",
                "d",
                "--files",
                f"{tid.lower()}/**",
                "--size",
                "small",
            ).returncode
            == 0
        )
        for s in ("dispatched", "returned"):
            assert _cli(bank, "track", "set", tid, "--status", s).returncode == 0
        (bank / "reports" / "demo" / f"{tid}.md").write_text("STATUS: DONE\n", encoding="utf-8")
    (tree / "a").mkdir()
    (tree / "b").mkdir()
    (tree / "a" / "errors.go").write_text(MAPPER_A, encoding="utf-8")
    (tree / "b" / "http.go").write_text(MAPPER_B, encoding="utf-8")
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "mb_team_ops.py"), "collect", "--json", "--mb", str(bank)],
        capture_output=True,
        text=True,
        cwd=tree,
    )
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["collected"] == ["A", "B"]
    assert [(d["a"]["path"], d["b"]["path"]) for d in out["duplicates"]] == [
        ("a/errors.go", "b/http.go")
    ]
