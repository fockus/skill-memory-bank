"""Shared foundations across /mb team tracks: registry, foundation detection, EXTRACT handovers.

A wave of parallel tracks that each need the same mechanism writes one copy per track unless the
plan names the foundation first (registry rows injected into prompts, a blocking readiness warning
for signals ≥2 tracks share, and `extract` actions for tracks that hit another track's zone).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import mb_team_shared as shared  # noqa: E402
import mb_team_status as status_mod  # noqa: E402
from test_mb_team_state import _bank, _cli, facts, team, track  # noqa: E402

REGISTRY = """# Shared mechanisms

| Mechanism | Home | Status | Keywords |
|---|---|---|---|
| http-error-mapper | internal/platform/httperr | exists | error mapper, request-id |
| idempotency-store | internal/platform/idem | being-extracted | idempotency |
"""


def _t(tid, task, files=None, deps=None, status="planned"):
    t = track(tid, status, files=files, deps=deps)
    t["task"] = task
    return t


def test_registry_parses_rows_and_ignores_header_and_separator(tmp_path):
    (tmp_path / "shared-mechanisms.md").write_text(REGISTRY, encoding="utf-8")
    rows = shared.load_registry(str(tmp_path))
    assert [(r["mechanism"], r["home"], r["status"]) for r in rows] == [
        ("http-error-mapper", "internal/platform/httperr", "exists"),
        ("idempotency-store", "internal/platform/idem", "being-extracted"),
    ]
    assert rows[0]["keywords"] == ["error mapper", "request-id"]


def test_registry_absent_is_empty(tmp_path):
    assert shared.load_registry(str(tmp_path)) == []


def test_relevant_rows_match_keyword_in_task_or_home_under_track_globs(tmp_path):
    (tmp_path / "shared-mechanisms.md").write_text(REGISTRY, encoding="utf-8")
    rows = shared.load_registry(str(tmp_path))
    by_text = _t(
        "A", "Map service errors to HTTP with the Error Mapper", files=["internal/admin/**"]
    )
    by_glob = _t("B", "Write the store", files=["internal/platform/idem/**"])
    other = _t("C", "Render the users page", files=["web/**"])
    assert [r["mechanism"] for r in shared.relevant(rows, by_text)] == ["http-error-mapper"]
    assert [r["mechanism"] for r in shared.relevant(rows, by_glob)] == ["idempotency-store"]
    assert shared.relevant(rows, other) == []


def test_signals_cover_shared_paths_phrases_and_registry_hits():
    rows = [
        {
            "mechanism": "http-error-mapper",
            "home": "x",
            "status": "exists",
            "keywords": ["error mapper"],
        }
    ]
    t = _t(
        "A",
        "Add an admin kit and reuse the error mapper from pkg/shared/errs",
        files=["internal/platform/httperr/**", "internal/admin/**"],
    )
    assert shared.signals(t, rows) == {
        "path:internal/platform",
        "path:pkg/shared",
        "word:admin-kit",
        "mech:http-error-mapper",
    }


def test_foundation_group_blocks_until_dependency_registry_or_accept():
    a = _t("A", "users section", files=["internal/admin/users/**", "internal/platform/**"])
    b = _t("B", "roles section", files=["internal/admin/roles/**", "internal/platform/**"])
    c = _t("C", "web page", files=["web/**"])
    groups = shared.foundation_groups(team(a, b, c), [])
    assert [(g["signal"], g["tracks"]) for g in groups] == [("path:internal/platform", ["A", "B"])]
    assert "foundation track" in groups[0]["suggest"]
    b_dep = _t(
        "B", "roles section", files=["internal/admin/roles/**", "internal/platform/**"], deps=["A"]
    )
    assert shared.foundation_groups(team(a, b_dep), []) == []
    accepted = team(a, b)
    accepted["accepted_shared"] = ["path:internal/platform"]
    assert shared.foundation_groups(accepted, []) == []


def test_registry_exists_resolves_but_being_extracted_needs_a_dependency():
    rows = [
        {"mechanism": "errmap", "home": "p/e", "status": "exists", "keywords": []},
        {"mechanism": "idem", "home": "p/i", "status": "being-extracted", "keywords": []},
    ]
    a, b = (
        _t("A", "use errmap and idem", files=["a/**"]),
        _t("B", "use errmap and idem", files=["b/**"]),
    )
    assert [g["signal"] for g in shared.foundation_groups(team(a, b), rows)] == ["mech:idem"]


def test_blocking_only_while_a_track_of_the_group_is_planned():
    a = _t("A", "x", files=["internal/platform/**"], status="dispatched")
    b = _t("B", "y", files=["internal/platform/**"], status="dispatched")
    assert shared.blocking(team(a, b), []) == []
    b2 = _t("B", "y", files=["internal/platform/**"])
    assert shared.blocking(team(a, b2), []) == ["path:internal/platform"]


def test_next_stops_on_a_shared_foundation_signal():
    t = team(_t("A", "x"), _t("B", "y"))
    out = status_mod.decide(t, facts(shared_foundation=["path:internal/platform"]))
    assert out == ["stop_human shared-foundation:path:internal/platform"]


def test_next_prints_extract_for_each_open_extract_handover():
    board = {
        "tracks": {},
        "open_blocked": [],
        "open_handover": [
            {"track": "A", "date": "2026-11-17", "title": "extract:errmap"},
            {"track": "B", "date": "2026-11-17", "title": "contract change"},
        ],
    }
    t = team(_t("A", "x", status="dispatched"), _t("B", "y", status="dispatched"))
    assert status_mod.decide(t, facts(board=board)) == ["extract A errmap"]


# ── through the CLI ───────────────────────────────────────────────────────────


def _plan(bank: Path, *extra: str) -> dict:
    r = _cli(bank, "plan", "--json", *extra)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def test_plan_reports_shared_foundation_and_accept_clears_it(tmp_path):
    bank = _bank(tmp_path)
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    for tid in ("A", "B"):
        r = _cli(
            bank,
            "track",
            "add",
            tid,
            "--task",
            f"section {tid}",
            "--dod",
            "tested",
            "--files",
            f"internal/{tid.lower()}/**,internal/platform/**",
            "--size",
            "small",
        )
        assert r.returncode == 0, r.stderr
    ready = _plan(bank)["ready"]
    assert [g["signal"] for g in ready["shared_foundation"]] == ["path:internal/platform"]
    assert (
        _plan(bank, "--accept-shared", "path:internal/platform")["ready"]["shared_foundation"] == []
    )
    assert _plan(bank)["ready"]["shared_foundation"] == []


def test_track_prompt_injects_relevant_registry_rows(tmp_path):
    bank = _bank(tmp_path)
    (bank / "shared-mechanisms.md").write_text(REGISTRY, encoding="utf-8")
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    r = _cli(
        bank,
        "track",
        "add",
        "A",
        "--task",
        "Admin users: map errors with the error mapper",
        "--dod",
        "tested",
        "--files",
        "internal/admin/**",
        "--size",
        "small",
    )
    assert r.returncode == 0, r.stderr
    text = Path(r.stdout.strip()).read_text(encoding="utf-8")
    assert "## Shared mechanisms" in text
    assert "`http-error-mapper` from `internal/platform/httperr`" in text and "do not copy" in text
    assert "idempotency-store" not in text


def test_brief_tells_tracks_to_post_an_extract_handover(tmp_path):
    bank = _bank(tmp_path)
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    brief = (bank / "reports" / "demo" / "brief.md").read_text(encoding="utf-8")
    assert "HANDOVER · extract:<mechanism>" in brief


def test_reviewer_rubrics_make_a_second_registry_copy_a_blocker():
    for name in ("mb-reviewer.md", "mb-reviewer-quality.md"):
        lines = (REPO_ROOT / "agents" / name).read_text(encoding="utf-8").splitlines()
        at = next(i for i, ln in enumerate(lines) if "shared-mechanisms.md" in ln)
        assert "blocker" in " ".join(lines[at - 1:at + 3]), name
    rubric = (REPO_ROOT / "references" / "pipeline.default.yaml").read_text(encoding="utf-8")
    assert "shared-mechanisms.md mechanism outside its home is a blocker" in rubric


# ── review fixes (b728474): false positives and the documented resolution ────

def test_prepositions_before_client_are_not_a_shared_phrase():
    a = _t("A", "Return 404 to client when the card is missing")
    b = _t("B", "Send validation errors to client")
    assert shared.foundation_groups(team(a, b), []) == []


def test_registry_keywords_match_whole_words_only():
    rows = [{"mechanism": "request-id", "home": "p/r", "status": "exists", "keywords": ["id", "log"]}]
    assert shared.relevant(rows, _t("A", "Validate the catalog form")) == []
    assert shared.relevant(rows, _t("B", "Propagate the request id to the log")) == rows


def test_a_foundation_track_all_members_depend_on_resolves_the_group():
    f = _t("F", "Wrap the http client for outbound calls", files=["internal/outbound/**"])
    a = _t("A", "Call the bank over an http client", files=["a/**"], deps=["F"])
    b = _t("B", "Use the http client for retries", files=["b/**"], deps=["F"])
    assert shared.foundation_groups(team(f, a, b), []) == []
    a_nodep = _t("A", "Call the bank over an http client", files=["a/**"])
    assert [g["signal"] for g in shared.foundation_groups(team(f, a_nodep, b), [])] == ["word:http-client"]


def test_signal_ids_have_no_spaces():
    t = _t("A", "Build the HTTP Client and the admin kit")
    assert all(" " not in s for s in shared.signals(t, []))


def test_registry_prompt_line_names_the_full_handover_command():
    rows = [{"mechanism": "idem", "home": "p/i", "status": "being-extracted", "keywords": []}]
    text = shared.prompt_section(rows)
    assert "--type HANDOVER --track <id> --title extract:idem" in text


def test_next_cli_stops_on_the_signal_and_accept_releases_it(tmp_path):
    bank = _bank(tmp_path)
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    for tid in ("A", "B"):
        assert _cli(bank, "track", "add", tid, "--task", f"s {tid}", "--dod", "d",
                    "--files", f"internal/{tid.lower()}/**,internal/platform/**", "--size", "small").returncode == 0
    nxt = [sys.executable, str(SCRIPTS / "mb_team_status.py"), "next", "--mb", str(bank)]
    before = subprocess.run(nxt, capture_output=True, text=True, cwd=bank.parent).stdout
    assert "stop_human shared-foundation:path:internal/platform" in before
    assert _cli(bank, "plan", "--accept-shared", "path:internal/platform").returncode == 0
    after = subprocess.run(nxt, capture_output=True, text=True, cwd=bank.parent).stdout
    assert "shared-foundation" not in after


def test_an_unrelated_shared_dependency_does_not_resolve_the_group():
    setup = _t("S", "Create the DB schema migrations", files=["migrations/**"])
    a = _t("A", "Build the payments client calls", files=["a/**"], deps=["S"])
    b = _t("B", "Retry through the payments client", files=["b/**"], deps=["S"])
    assert [g["signal"] for g in shared.foundation_groups(team(setup, a, b), [])] == ["word:payments-client"]
