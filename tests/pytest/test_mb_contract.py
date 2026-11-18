"""Executable stage contracts (contract-first): `mb_contract.py run|freeze`.

A contract is written from the plan stage / spec task before implementation, frozen with a red dry run of
its spec items, and run by the verifier and the team commit gate; it carries the spec REQ checks, the rules
checks and the DoD checks, each a command with an Eval-style anchor or a `manual:` reason.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
TOOL = SCRIPTS / "mb_contract.py"
sys.path.insert(0, str(SCRIPTS))

from test_mb_team_state import _bank, _cli, _team  # noqa: E402

CONTRACT = """# Contract: access-task-1

**Covers:** REQ-001, REQ-002

## spec
- REQ-001 a verified user gets a card — `test -f card.txt` — exit: 0
- REQ-002 recovery only through an operator — `cat recovery.txt` — output~: operator-only

## rules
- no debug prints — `grep -rn "print(" src || true` — output-empty

## dod
- README names the endpoint — manual: reviewer reads README
"""


def _write(tree: Path, text: str = CONTRACT) -> Path:
    path = tree / ".memory-bank" / "contracts" / "access-task-1.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    (tree / "src").mkdir(exist_ok=True)
    return path


def _run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True)


def _items(r: subprocess.CompletedProcess) -> dict:
    return {(i["section"], i["id"]): i for i in json.loads(r.stdout)["items"]}


def _implement(tree: Path) -> None:
    (tree / "card.txt").write_text("card\n", encoding="utf-8")
    (tree / "recovery.txt").write_text("mode: operator-only\n", encoding="utf-8")


def test_run_reports_each_item_and_fails_on_red(tmp_path):
    contract = _write(tmp_path)
    r = _run("run", str(contract), "--tree", str(tmp_path), "--json")
    assert r.returncode == 1
    items = _items(r)
    assert items[("spec", "REQ-001")]["status"] == "fail"
    assert items[("rules", "no debug prints")]["status"] == "pass"
    assert items[("dod", "README names the endpoint")]["status"] == "manual"
    _implement(tmp_path)
    r = _run("run", str(contract), "--tree", str(tmp_path), "--json")
    assert r.returncode == 0, r.stdout
    assert json.loads(r.stdout)["summary"] == {"pass": 3, "fail": 0, "manual": 1}


def test_output_empty_anchor_fails_on_output(tmp_path):
    contract = _write(tmp_path)
    (tmp_path / "src" / "x.py").write_text('print("debug")\n', encoding="utf-8")
    _implement(tmp_path)
    r = _run("run", str(contract), "--tree", str(tmp_path), "--json")
    assert r.returncode == 1
    assert _items(r)[("rules", "no debug prints")]["status"] == "fail"


def test_a_covered_req_without_a_spec_item_is_a_failure(tmp_path):
    contract = _write(
        tmp_path,
        CONTRACT.replace("**Covers:** REQ-001, REQ-002", "**Covers:** REQ-001, REQ-002, REQ-028"),
    )
    _implement(tmp_path)
    r = _run("run", str(contract), "--tree", str(tmp_path), "--json")
    assert r.returncode == 1
    assert "no contract item" in _items(r)[("spec", "REQ-028")]["reason"]


def test_manual_spec_item_satisfies_coverage(tmp_path):
    text = (
        CONTRACT.replace("**Covers:** REQ-001, REQ-002", "**Covers:** REQ-001, REQ-002, REQ-028")
        + "\n## spec\n- REQ-028 SMS to the operator — manual: needs the live SMS gateway\n"
    )
    contract = _write(tmp_path, text)
    _implement(tmp_path)
    r = _run("run", str(contract), "--tree", str(tmp_path), "--json")
    assert r.returncode == 0, r.stdout
    assert _items(r)[("spec", "REQ-028")]["status"] == "manual"


def test_malformed_contract_is_refused(tmp_path):
    for bad in (
        "# c\n\n## spec\n- no req id here — `true`\n",
        "# c\n\n## extras\n- x — `true`\n",
        "# c\n\n## dod\n- empty manual — manual:\n",
        "# c\n\n## dod\n- no command at all\n",
    ):
        r = _run("run", str(_write(tmp_path, bad)), "--tree", str(tmp_path))
        assert r.returncode == 2, bad


def test_freeze_needs_red_spec_items_and_records_evidence(tmp_path):
    contract = _write(tmp_path)
    r = _run("freeze", str(contract), "--tree", str(tmp_path))
    assert r.returncode == 0, r.stderr
    lock = json.loads(Path(f"{contract}.lock.json").read_text(encoding="utf-8"))
    assert [e["id"] for e in lock["red"]] == ["REQ-001", "REQ-002"] and lock["sha256"]
    green = tmp_path / "green"
    green.mkdir()
    _implement(green)
    contract2 = _write(green)
    r = _run("freeze", str(contract2), "--tree", str(green))
    assert r.returncode == 1 and "REQ-001" in r.stderr
    assert not Path(f"{contract2}.lock.json").exists()


def test_change_after_freeze_fails_run_until_amended(tmp_path):
    contract = _write(tmp_path)
    assert _run("freeze", str(contract), "--tree", str(tmp_path)).returncode == 0
    contract.write_text(CONTRACT.replace("exit: 0", "exit: 1"), encoding="utf-8")
    _implement(tmp_path)
    r = _run("run", str(contract), "--tree", str(tmp_path), "--json")
    assert r.returncode == 1 and json.loads(r.stdout)["frozen"] == "drifted"
    assert _run("freeze", str(contract), "--tree", str(tmp_path)).returncode == 1
    assert (
        _run(
            "freeze", str(contract), "--tree", str(tmp_path), "--amend", "--reason", "fix anchor"
        ).returncode
        == 0
    )
    lock = json.loads(Path(f"{contract}.lock.json").read_text(encoding="utf-8"))
    assert lock["amendments"][0]["reason"] == "fix anchor"
    assert (
        json.loads(_run("run", str(contract), "--tree", str(tmp_path), "--json").stdout)["frozen"]
        == "yes"
    )


# ── /mb team: contract per track ─────────────────────────────────────────────


def _team_with_contract(tmp_path: Path) -> tuple[Path, Path]:
    bank = _bank(tmp_path)
    tree = bank.parent
    contract = bank / "contracts" / "A.md"
    contract.parent.mkdir()
    contract.write_text(
        "# Contract: A\n\n## dod\n- a file exists — `test -f a/done.txt` — exit: 0\n",
        encoding="utf-8",
    )
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(tree)).returncode == 0
    r = _cli(
        bank,
        "track",
        "add",
        "A",
        "--task",
        "t",
        "--dod",
        "d",
        "--files",
        "a/**",
        "--size",
        "small",
        "--contract",
        "contracts/A.md",
    )
    assert r.returncode == 0, r.stderr
    return bank, contract


def test_dispatch_refuses_an_unfrozen_contract(tmp_path):
    bank, contract = _team_with_contract(tmp_path)
    r = _cli(bank, "track", "set", "A", "--status", "dispatched")
    assert r.returncode == 2 and "freeze" in r.stderr
    assert _run("freeze", str(contract), "--tree", str(bank.parent)).returncode == 0
    assert _cli(bank, "track", "set", "A", "--status", "dispatched").returncode == 0
    prompt = (bank / _team(bank)["tracks"][0]["prompt"]).read_text(encoding="utf-8")
    assert str(contract) in prompt


def test_commit_gate_runs_the_track_contract(tmp_path):
    bank, contract = _team_with_contract(tmp_path)
    tree = bank.parent
    assert _run("freeze", str(contract), "--tree", str(tree)).returncode == 0
    for s in ("dispatched", "returned", "done"):
        assert _cli(bank, "track", "set", "A", "--status", s).returncode == 0
    (tree / "a").mkdir()
    (tree / "a" / "other.txt").write_text("x\n", encoding="utf-8")
    commit = [
        sys.executable,
        str(SCRIPTS / "mb_team_ops.py"),
        "commit",
        "--tracks",
        "A",
        "-m",
        "a",
        "--yes",
        "--mb",
        str(bank),
    ]
    r = subprocess.run(commit, capture_output=True, text=True, cwd=tree)
    assert r.returncode == 1 and "contract" in r.stderr and "a file exists" in r.stderr
    assert _team(bank)["tracks"][0]["status"] == "fixing"


def test_plan_warns_about_standard_tracks_without_a_contract(tmp_path):
    bank = _bank(tmp_path)
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    assert (
        _cli(
            bank, "track", "add", "A", "--task", "t", "--dod", "d", "--size", "standard"
        ).returncode
        == 0
    )
    p = json.loads(_cli(bank, "plan", "--json").stdout)
    assert any("A" in w and "contract" in w for w in p["warnings"])


def test_plan_verifier_runs_the_contract_first_and_can_write_one():
    text = (REPO_ROOT / "agents" / "plan-verifier.md").read_text(encoding="utf-8")
    assert "mb_contract.py\" run <contract>" in text and "Mode: contract" in text
    assert text.index("Step 1.5: Run the contract first") < text.index("Step 2: Inspect code changes")


# ── review fixes (b728474) ───────────────────────────────────────────────────

def test_timeout_kills_the_whole_process_group(tmp_path):
    marker = tmp_path / "late"
    text = f"# c\n\n## dod\n- slow — `(sleep 3; touch {marker}) & wait` — exit: 0\n"
    r = _run("run", str(_write(tmp_path, text)), "--tree", str(tmp_path), "--json", "--timeout", "1")
    assert r.returncode == 1 and "timeout" in r.stdout
    import time
    time.sleep(4)
    assert not marker.exists()


def test_a_corrupted_lock_is_a_failure_not_a_traceback(tmp_path):
    contract = _write(tmp_path)
    Path(f"{contract}.lock.json").write_text("{not json", encoding="utf-8")
    _implement(tmp_path)
    r = _run("run", str(contract), "--tree", str(tmp_path), "--json")
    assert r.returncode == 1 and "Traceback" not in r.stderr
    assert json.loads(r.stdout)["frozen"] == "corrupt"


def test_freeze_warns_about_spec_items_with_an_exit_only_anchor(tmp_path):
    r = _run("freeze", str(_write(tmp_path)), "--tree", str(tmp_path))
    assert r.returncode == 0
    assert "REQ-001" in r.stderr and "exit-only" in r.stderr and "REQ-002" not in r.stderr


def test_commit_gate_fails_when_the_lock_is_gone(tmp_path):
    bank, contract = _team_with_contract(tmp_path)
    tree = bank.parent
    assert _run("freeze", str(contract), "--tree", str(tree)).returncode == 0
    for s in ("dispatched", "returned", "done"):
        assert _cli(bank, "track", "set", "A", "--status", s).returncode == 0
    (tree / "a").mkdir()
    (tree / "a" / "done.txt").write_text("x\n", encoding="utf-8")
    Path(f"{contract}.lock.json").unlink()
    commit = [sys.executable, str(SCRIPTS / "mb_team_ops.py"), "commit", "--tracks", "A", "-m", "a", "--yes",
              "--mb", str(bank)]
    r = subprocess.run(commit, capture_output=True, text=True, cwd=tree)
    assert r.returncode == 1 and "not frozen" in r.stderr


def test_track_set_attaches_a_contract_to_an_existing_track(tmp_path):
    bank = _bank(tmp_path)
    contract = bank / "contracts" / "A.md"
    contract.parent.mkdir()
    contract.write_text("# c\n\n## dod\n- x — `true` — exit: 0\n", encoding="utf-8")
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    assert _cli(bank, "track", "add", "A", "--task", "t", "--dod", "d", "--size", "standard").returncode == 0
    r = _cli(bank, "track", "set", "A", "--contract", "contracts/A.md")
    assert r.returncode == 0, r.stderr
    t = _team(bank)["tracks"][0]
    assert t["contract"] == "contracts/A.md"
    assert str(contract) in (bank / t["prompt"]).read_text(encoding="utf-8")


def test_run_reports_amendments_and_freeze_warns_without_red_evidence(tmp_path):
    contract = _write(tmp_path, "# c\n\n## dod\n- a file — `test -f x` — exit: 0\n")
    r = _run("freeze", str(contract), "--tree", str(tmp_path))
    assert r.returncode == 0 and "no executable spec item" in r.stderr
    contract.write_text("# c\n\n## dod\n- a file — `true` — exit: 0\n", encoding="utf-8")
    assert _run("freeze", str(contract), "--tree", str(tmp_path), "--amend", "--reason", "relax").returncode == 0
    out = json.loads(_run("run", str(contract), "--tree", str(tmp_path), "--json").stdout)
    assert out["amendments"] == [{"reason": "relax", "at": out["amendments"][0]["at"]}]


def test_contract_attached_with_dispatch_in_one_call_must_be_frozen(tmp_path):
    bank = _bank(tmp_path)
    contract = bank / "contracts" / "A.md"
    contract.parent.mkdir()
    contract.write_text("# c\n\n## dod\n- x — `test -f nope` — exit: 0\n", encoding="utf-8")
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    assert _cli(bank, "track", "add", "A", "--task", "t", "--dod", "d", "--size", "small").returncode == 0
    r = _cli(bank, "track", "set", "A", "--status", "dispatched", "--contract", "contracts/A.md")
    assert r.returncode == 2 and "freeze" in r.stderr
    assert _team(bank)["tracks"][0]["status"] == "planned"


def test_a_dispatched_track_cannot_swap_its_contract(tmp_path):
    bank, contract = _team_with_contract(tmp_path)
    assert _run("freeze", str(contract), "--tree", str(bank.parent)).returncode == 0
    assert _cli(bank, "track", "set", "A", "--status", "dispatched").returncode == 0
    other = contract.with_name("B.md")
    other.write_text("# c\n\n## dod\n- x — `true` — exit: 0\n", encoding="utf-8")
    r = _cli(bank, "track", "set", "A", "--contract", "contracts/B.md")
    assert r.returncode == 2 and "amend" in r.stderr
    assert _team(bank)["tracks"][0]["contract"] == "contracts/A.md"
