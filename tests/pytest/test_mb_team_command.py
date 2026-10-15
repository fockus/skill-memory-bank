"""`commands/team.md` contract: shape, CLI coverage, runnable bash blocks, router/index rows."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
TEAM_MD = ROOT / "commands" / "team.md"
SCRIPTS = ROOT / "scripts"


def _text() -> str:
    return TEAM_MD.read_text(encoding="utf-8")


def _block(marker: str) -> str:
    tail = _text().split(marker, 1)[1]
    return re.findall(r"```bash\n(.*?)\n```", tail, re.S)[0]


def _cli_flags() -> set[str]:
    """Every long flag the team CLI accepts, read from the argparse sources."""
    flags: set[str] = set()
    for name in ("mb_team_tracks.py", "mb_team_status.py", "mb_team_ops.py", "mb_team_review.py"):
        src = (SCRIPTS / name).read_text(encoding="utf-8")
        flags |= set(re.findall(r'add_argument\("(--[a-z][a-z-]+)"', src))
        for group in re.findall(r"for flag in \(([^)]*)\):", src):
            flags |= {x if x.startswith("--") else f"--{x}" for x in re.findall(r'"([\w-]+)"', group)}
    return flags - {"--team"}  # --team is filled in by mb-team.sh, not by the user


def test_team_command_frontmatter_follows_template_and_size_limit():
    text = _text()
    assert text.startswith("---\n")
    front = yaml.safe_load(text.split("---\n", 2)[1])
    assert "use when" in front["description"].lower()
    assert isinstance(front["allowed-tools"], list) and "Bash" in front["allowed-tools"]
    assert "argument-hint" in front
    assert len(text.splitlines()) < 400


def test_team_command_documents_every_subcommand_and_flag():
    text = _text()
    dispatcher = (SCRIPTS / "mb-team.sh").read_text(encoding="utf-8")
    subcommands = set(re.findall(r"^\s+([a-z-]+(?: \| [a-z-]+)*)\)", dispatcher, re.M))
    names = {n.strip() for group in subcommands for n in group.split("|")}
    assert {"init", "track", "next", "commit", "review"} <= names
    missing = sorted(n for n in names if f"`{n}" not in text and f" {n} " not in text)
    assert missing == []
    for action in ("start", "gate", "external", "ingest"):
        assert f"review {action}" in text
    undocumented = sorted(f for f in _cli_flags() if f not in text)
    assert undocumented == []


def test_team_command_maps_every_vocabulary_value():
    import sys

    sys.path.insert(0, str(SCRIPTS))
    import mb_team_vocab

    text = _text()
    pairs = {f"{k}={v}" for _, assignment in mb_team_vocab.PHRASES for k, v in assignment.items()}
    assert sorted(p for p in pairs if p not in text) == []


def test_team_command_states_safety_rules_and_next_actions():
    text = _text()
    for req in ("REQ-TEAM-090", "REQ-TEAM-091", "REQ-TEAM-092"):
        assert req in text
    for action in ("stop_human", "fix", "verify", "review", "dispatch", "collect", "team_review",
                   "stop_success", "wait"):
        assert f"`{action}" in text
    for host in ("Claude Code", "Codex", "Pi"):
        assert host in text


def _project(tmp_path: Path) -> tuple[Path, Path, dict]:
    project = tmp_path / "project with spaces"
    bank = tmp_path / "personal bank" / ".memory-bank"
    (project / "a").mkdir(parents=True)
    bank.mkdir(parents=True)
    (bank / "COORDINATION.md").write_text("# Coordination board\n")
    (bank / "progress.md").write_text("# Progress\n")
    (project / "a" / "x.txt").write_text("base\n")
    git = ["git", "-C", str(project)]
    subprocess.run([*git, "init", "-q", "."], check=True)
    subprocess.run([*git, "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A"], check=True)
    subprocess.run([*git, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"], check=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    env.update(SKILL_DIR=str(ROOT), MB_PATH=str(bank), MB_LOCK_DIR=str(tmp_path / "locks"), TOPIC="demo")
    return project, bank, env


def test_team_bash_blocks_run_from_project_path_with_spaces(tmp_path):
    project, bank, env = _project(tmp_path)
    script = "\n".join(_block(m) for m in (
        "<!-- mb-team:setup -->", "<!-- mb-team:init -->", "<!-- mb-team:track -->", "<!-- mb-team:loop -->"))
    result = subprocess.run(["bash", "-eu", "-c", script], cwd=project, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "stop_human brief-unfilled" in result.stdout
    team = json.loads((bank / "reports" / "demo" / "team.json").read_text())
    assert [t["id"] for t in team["tracks"]] == ["A"]
    assert team["tree"] == str(project.resolve())
    assert not (project / ".memory-bank").exists()


def test_team_return_block_records_the_track_report(tmp_path):
    project, bank, env = _project(tmp_path)
    script = "\n".join(_block(m) for m in (
        "<!-- mb-team:setup -->", "<!-- mb-team:init -->", "<!-- mb-team:track -->"))
    report = bank / "reports" / "demo" / "A.md"
    setup = f"{script}\nprintf 'STATUS: DONE\\n' > '{report}'\nteam track set A --status dispatched\nID=A\n"
    result = subprocess.run(["bash", "-eu", "-c", setup + _block("<!-- mb-team:return -->")],
                            cwd=project, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    track = json.loads((bank / "reports" / "demo" / "team.json").read_text())["tracks"][0]
    assert track["status"] == "returned"
    assert track["summary"]


def test_router_index_and_counts_list_team():
    router = (ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert re.search(r"^\| `team .*commands/team\.md", router, re.M)
    assert "`/team`" in (ROOT / "SKILL.md").read_text(encoding="utf-8")
    assert re.search(r"^\| `/team` \|", (ROOT / "README.md").read_text(encoding="utf-8"), re.M)
    assert re.search(r"^## team\b", (ROOT / "docs" / "pipeline-yaml.md").read_text(encoding="utf-8"), re.M)


def test_reviewer_lead_previous_issues_carry_an_id():
    lead = (ROOT / "agents" / "mb-reviewer-lead.md").read_text(encoding="utf-8")
    line = next(x for x in lead.splitlines() if '"status":"resolved|unresolved|superseded"' in x)
    assert '"id":' in line


@pytest.mark.parametrize("flag", ["--layer", "--source", "--team-review", "--summary-file"])
def test_team_flag_probe_is_not_vacuous(flag):
    assert flag in _cli_flags()


def test_team_hosts_section_names_four_hosts_and_links_skill_invocation():
    text = _text()
    hosts = text.split("## 9. Hosts", 1)[1].split("## 10.", 1)[0]
    for host in ("Claude Code", "Codex", "OpenCode", "Pi"):
        assert f"| {host} |" in hosts
    assert "SKILL.md" in hosts and "Invocation" in hosts
    invocation = (ROOT / "SKILL.md").read_text(encoding="utf-8").split("### Invocation", 1)[1]
    for host in ("Claude Code", "OpenCode", "Codex", "Pi"):
        assert f"| {host} |" in invocation
