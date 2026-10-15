"""planning-qa-sources Task 5: end-to-end scenarios over the real scripts.

Real scripts run in temp banks; nothing is mocked. Prompt-contract scenarios assert the
load-bearing clauses of the shipped prompt files.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "scripts"
GOLDEN = REPO / "tests" / "bats" / "fixtures" / "qa-golden"
ENV = {**os.environ, "PATH": f"{Path(sys.executable).parent}{os.pathsep}{os.environ['PATH']}"}


def sh(script: str, *args: str, env: dict | None = None, stdin: str | None = None):
    return subprocess.run(["bash", str(SCRIPTS / script), *args], capture_output=True, text=True,
                          env=env or ENV, input=stdin, check=False)


def read(rel: str) -> str:
    return (REPO / rel).read_text(encoding="utf-8")


def section(text: str, heading: str) -> str:
    """Body of the first heading line containing `heading`, up to the next heading of any level."""
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("#") and heading in ln:
            out = []
            for nxt in lines[i + 1:]:
                if nxt.lstrip().startswith("#") and not nxt.lstrip().startswith("# "):
                    break
                out.append(nxt)
            return "\n".join(out)
    raise AssertionError(f"heading {heading!r} not found")


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


@pytest.fixture
def bank(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "plans" / "done").mkdir(parents=True)
    (mb / "qa").mkdir()
    (mb / "qa" / "README.md").write_text("# QA target\n")
    (mb / "checklist.md").write_text("# Checklist\n")
    (mb / "roadmap.md").write_text("# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n")
    shutil.copy(REPO / "references" / "pipeline.default.yaml", mb / "pipeline.yaml")
    subprocess.run("git init -q && git config user.email t@t && git config user.name t "
                   "&& echo i > f && git add f && git commit -q -m i", shell=True, cwd=tmp_path, check=True)
    return mb


def decl(plan: str) -> str:
    return next(ln for ln in Path(plan).read_text().splitlines() if ln.startswith("qa: "))


def make_plan(mb: Path, *flags: str) -> tuple[str, str]:
    r = sh("mb-plan.sh", "feature", "checkout", *flags, str(mb))
    assert r.returncode == 0, r.stderr
    p = r.stdout.strip()
    return decl(p), Path(p).read_text()


def set_qa(mb: Path, enabled: str) -> None:
    (mb / "pipeline.yaml").write_text(f"qa:\n  enabled: {enabled}\n  cadence: plan\n")


def add_spec(mb: Path, topic: str = "demo") -> None:
    d = mb / "specs" / topic
    d.mkdir(parents=True)
    tasks = "# Tasks\n\n" + "".join(
        f"<!-- mb-task:{n} -->\n## Task {n}: t{n}\n\n**Covers:** REQ-001\n**Role:** developer\n"
        f"**Blocked-by:** none\n**Scope:** x\n**Budget:** 1000\n\n**DoD:**\n- [ ] ok\n<!-- /mb-task:{n} -->\n\n"
        for n in (1, 2, 3))
    (d / "tasks.md").write_text(tasks)


def wrapper(mb: Path, name: str = "w1", extra: str = "") -> None:
    (mb / "plans" / f"{name}.md").write_text(
        f"---\ntype: feature\ntopic: demo\nlinked_spec: specs/demo\n{extra}status: in-progress\n---\n\n# Wrapper\n")


def jsonl(out: str) -> list[dict]:
    return [json.loads(ln) for ln in out.splitlines() if ln.startswith("{")]


def test_REQ_001__qa_declaration_follows_tier_opt_outs_and_target(bank: Path) -> None:
    item = "/mb qa run @checkout"
    d, body = make_plan(bank, "--tier", "standard")
    assert d == "qa: on" and item in body
    for flags, want in ((("--tier", "small"), "qa: off — small tier"),
                        (("--tier", "small", "--qa"), "qa: on"),
                        (("--tier", "large", "--no-qa"), "qa: off — disabled")):
        d, body = make_plan(bank, *flags)
        assert d == want, flags
        assert (item in body) == (want == "qa: on"), flags
    set_qa(bank, "false")
    d, body = make_plan(bank, "--tier", "standard", "--qa")
    assert d == "qa: off — disabled" and item not in body
    set_qa(bank, "true")
    assert make_plan(bank, "--tier", "small")[0] == "qa: on"
    assert make_plan(bank, "--tier", "small", "--no-qa")[0] == "qa: off — disabled"
    (bank / "qa" / "README.md").unlink()
    d, body = make_plan(bank, "--tier", "large")
    assert d == "qa: off — no QA target" and item not in body


def test_REQ_005__test_case_authoring_contract() -> None:
    plan = flat(section(read("commands/plan.md"), "3.5. QA test cases"))
    assert re.search(r"dispatch .mb-qa. exactly once.*authoring mode", plan)
    assert re.search(r"only when the plan says .qa: on.", plan)
    assert re.search(r"Task", read("commands/plan.md").split("---")[1])  # allowed-tools frontmatter
    qa = flat(section(read("agents/mb-qa.md"), "Test-case authoring mode"))
    assert re.search(r"writes only under .qa/test_cases/<topic>/.", qa)
    assert re.search(r"frontmatter .id., .tags., .covers., .origin., .proof.", qa)
    assert re.search(r"standard one case per key user path.*large or extra one per externally testable REQ", qa)
    assert re.search(r"marks .status: needs_spec. instead of inventing", qa)


def test_REQ_008__fixed_major_bug_yields_a_regression_case(bank: Path) -> None:
    cases = bank / "qa" / "test_cases" / "checkout"
    cases.mkdir(parents=True)
    (cases / "pay.md").write_text("---\ntags: [checkout, smoke]\ndriver: browser\ncovers: [REQ-002]\n---\n# Pay\n")

    def add(sev: str) -> str:
        r = sh("mb-qa-bug.sh", "--mb", str(bank), "add", sev, f"Bug {sev}",
               stdin="- Scenario: qa/test_cases/checkout/pay.md, step 2\n- Steps: pay\n- Expected: paid\n")
        assert r.returncode == 0, r.stderr
        return r.stdout.strip()

    bug = add("major")
    r = sh("mb-qa-bug.sh", "--mb", str(bank), "set", bug, "fixed")
    assert r.returncode == 0 and "qa/test_cases/checkout/reg-bug-001.md" in r.stdout
    reg = (cases / "reg-bug-001.md").read_text()
    for line in ("id: reg-bug-001", "origin: regression", "proof: both", "covers: [REQ-002]"):
        assert line in reg.splitlines()
    (cases / "reg-bug-001.md").write_text("keep me\n")
    sh("mb-qa-bug.sh", "--mb", str(bank), "set", bug, "fixed")
    assert (cases / "reg-bug-001.md").read_text() == "keep me\n"
    medium = add("medium")
    r = sh("mb-qa-bug.sh", "--mb", str(bank), "set", medium, "fixed")
    assert r.stdout.strip() == "" and not (cases / "reg-bug-002.md").exists()
    run = flat(section(read("commands/qa.md"), "run"))
    assert re.search(r"Drop cases with .status: needs_spec. or .proof: test.*not_run", run)
    assert re.search(r"not run: needs_spec.*not run: proof test.*never as Results rows",
                     flat(read("agents/mb-qa-runner.md")))


def test_REQ_011__spec_gets_a_plan_wrapper(bank: Path) -> None:
    add_spec(bank)
    r = sh("mb-plan.sh", "feature", "demo", "--spec", "demo", "--tier", "large", str(bank))
    assert r.returncode == 0, r.stderr
    wrapper_path = r.stdout.strip()
    text = Path(wrapper_path).read_text()
    assert "linked_spec: specs/demo" in text.splitlines() and decl(wrapper_path).startswith("qa: ")
    w = sh("mb-work-plan.sh", "--target", wrapper_path, "--mb", str(bank), "--dry-run")
    assert w.returncode == 0, w.stderr
    assert sum(1 for i in jsonl(w.stdout) if i.get("kind") == "task") == 3
    assert re.search(r"create it without asking under .--auto. or when QA would be on",
                     flat(section(read("commands/sdd.md"), "Plan wrapper")))


def test_REQ_012__work_items_carry_spec_and_plan_paths(bank: Path) -> None:
    add_spec(bank)
    wrapper(bank)
    spec = str((bank / "specs" / "demo").resolve())
    plan = str((bank / "plans" / "w1.md").resolve())
    for target in ("w1", "demo"):
        r = sh("mb-work-plan.sh", "--mb", str(bank), "--target", target)
        assert r.returncode == 0, r.stderr
        items = jsonl(r.stdout)
        assert items and all(i["spec_path"] == spec and i["plan_path"] == plan for i in items), target
    (bank / "plans" / "w1.md").unlink()
    for n in ("p1",):
        stages = "".join(f"<!-- mb-stage:{s} -->\n## Stage {s}: step {s}\n\n- ⬜ DoD bit\n\n" for s in (1, 2, 3))
        (bank / "plans" / f"{n}.md").write_text(
            f"---\ntype: feature\ntopic: {n}\nstatus: in-progress\n---\n\n# Plan {n}\n\n{stages}")
    tmp = bank.parent
    norm = lambda s: s.replace(str(tmp.resolve()), "@TMP@").replace(str(tmp), "@TMP@")  # noqa: E731
    r = sh("mb-work-plan.sh", "--mb", str(bank), "--host", "claude-code", "--target", "p1")
    assert norm(r.stdout) == (GOLDEN / "plan.jsonl").read_text()
    assert "spec_path" not in r.stdout and "plan_path" not in r.stdout
    wf = sh("mb-workflow.sh", "--mb", str(bank), "--host", "claude-code", "--json")
    assert wf.stdout == (GOLDEN / "workflow.json").read_text()


def test_REQ_013__agents_receive_the_source_bundle(tmp_path: Path) -> None:
    (tmp_path / "spec" / "topic").mkdir(parents=True)
    (tmp_path / "spec" / "topic" / "requirements.md").write_text("- **REQ-001**: spec requirement text\n")
    (tmp_path / "spec" / "topic" / "design.md").write_text("design text must not leak\n")
    (tmp_path / "wrapper.md").write_text("wrapper DoD line\n")
    (tmp_path / "report.md").write_text("QA report body\n")
    case, bank = tmp_path / "case", tmp_path / "bank"
    case.mkdir(), bank.mkdir()

    def payload(*src: Path):
        args = [a for s in src for a in ("--source", str(s))]
        return sh("mb-review.sh", "--emit-payload", "--input", str(case), "--mb", str(bank), *args)

    base = payload().stdout
    assert "## Sources" not in base
    r = payload(tmp_path / "spec" / "topic", tmp_path / "wrapper.md", tmp_path / "report.md")
    assert r.returncode == 0 and r.stdout.startswith(base)
    tail = r.stdout.split("\n## Sources\n", 1)[1]
    assert "spec requirement text" in tail and "wrapper DoD line" in tail and "QA report body" in tail
    assert "design text must not leak" not in tail
    assert payload(tmp_path / "nope.md").returncode == 2
    v = flat(section(read("agents/plan-verifier.md"), "Sources, coverage and divergence"))
    assert re.search(r"### Plan DoD.*### Spec REQ coverage.*separate sections", v)
    assert re.search(r"CRITICAL .plan-spec divergence.*Covers:.*tasks: A-B", v)
    assert re.search(r"Spec:.*Plan wrapper:.*QA cases:.*QA report:.*none", flat(section(read("agents/plan-verifier.md"), "Invocation")))
    assert re.search(r"## Sources.*optional.*last section", flat(section(read("agents/mb-reviewer.md"), "Inputs")))
    assert re.search(r"## Sources. section, the same bytes", flat(section(read("agents/mb-judge.md"), "Inputs")))


def test_REQ_016__verifier_coverage_table_and_nothing_to_verify(bank: Path, tmp_path: Path) -> None:
    # Chain: a fixed major bug writes a regression case; a test names it with `mb:case`.
    cases = bank / "qa" / "test_cases" / "checkout"
    cases.mkdir(parents=True)
    (cases / "pay.md").write_text("---\ntags: [checkout]\ncovers: [REQ-002]\n---\n# Pay\n")
    bug = sh("mb-qa-bug.sh", "--mb", str(bank), "add", "major", "B",
             stdin="- Scenario: qa/test_cases/checkout/pay.md, step 1\n- Steps: s\n- Expected: e\n").stdout.strip()
    sh("mb-qa-bug.sh", "--mb", str(bank), "set", bug, "fixed")
    reg_id = re.search(r"^id: (\S+)$", (cases / "reg-bug-001.md").read_text(), re.M).group(1)
    test = tmp_path / "test_pay.py"
    test.write_text(f"# mb:case {reg_id}\ndef test_pay(): pass\n")
    assert f"mb:case {reg_id}" in test.read_text()
    v = flat(section(read("agents/plan-verifier.md"), "Sources, coverage and divergence"))
    assert re.search(r"### QA coverage.*REQ.*Case.*Origin.*Proof.*Live.*Test", v)
    assert re.search(r"NOTHING TO VERIFY.*no REQ.*no DoD item.*no case", v)
    work = flat(section(read("commands/work.md"), "5c. Verify step"))
    assert re.search(r"NOTHING TO VERIFY.*halts the item", work)


def test_REQ_018__plan_qa_declaration_turns_qa_on_in_work(bank: Path) -> None:
    add_spec(bank)
    wrapper(bank, extra="qa: on\n")
    # The declaration is plain plan frontmatter that work.md reads and maps to --qa.
    assert "qa: on" in (bank / "plans" / "w1.md").read_text().splitlines()
    work = flat(read("commands/work.md"))
    assert re.search(r"plan.s .qa: on. declaration counts as .--qa. for both", work)
    assert re.search(r"@<topic>.*QA from the declaration.*cadence .stage. or .plan.", work)
    on = sh("mb-workflow.sh", "--mb", str(bank), "--host", "claude-code", "--qa", "--json")
    assert json.loads(on.stdout)["qa"]["enabled"] is True
    items = jsonl(sh("mb-work-plan.sh", "--mb", str(bank), "--target", "w1", "--qa").stdout)
    assert items and all("qa" in i for i in items)
    off_wf = sh("mb-workflow.sh", "--mb", str(bank), "--host", "claude-code", "--json")
    assert "qa" not in json.loads(off_wf.stdout)
    off = jsonl(sh("mb-work-plan.sh", "--mb", str(bank), "--target", "w1").stdout)
    assert off and all("qa" not in i for i in off)


def test_REQ_021__pipeline_qa_enabled_auto_is_accepted_and_inert(bank: Path, tmp_path: Path) -> None:
    default = (REPO / "references" / "pipeline.default.yaml").read_text()
    assert re.search(r"^  enabled: auto( |$)", default, re.M)
    shim = tmp_path / "shim"
    shim.mkdir()
    (shim / "yaml.py").write_text("raise ModuleNotFoundError('yaml')\n")
    noyaml = {**ENV, "PYTHONPATH": str(shim)}

    def pipe(top: str, host: str | None = None) -> str:
        text = re.sub(r"(?ms)(^qa:.*?^  enabled: )\S+", rf"\g<1>{top}", default, count=1)
        if host:
            text += f"\nhosts:\n  claude-code:\n    qa:\n      enabled: {host}\n"
        f = tmp_path / f"p-{top}-{host}.yaml"
        f.write_text(text)
        return str(f)

    for env in (ENV, noyaml):
        for v in ("auto", "true", "false"):
            assert sh("mb-pipeline-validate.sh", pipe(v), env=env).returncode == 0, (v, env is noyaml)
            assert sh("mb-pipeline-validate.sh", pipe("auto", v), env=env).returncode == 0, (v, env is noyaml)
        assert sh("mb-pipeline-validate.sh", pipe("maybe"), env=env).returncode == 1
    wf = sh("mb-workflow.sh", "--mb", str(bank), "--host", "claude-code", "--json")
    assert "qa" not in json.loads(wf.stdout)
    assert wf.stdout == (GOLDEN / "workflow.json").read_text()
