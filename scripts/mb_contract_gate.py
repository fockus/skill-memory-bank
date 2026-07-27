"""Runner for the Contract-checkers registry — svp-contract-test-loop C3a.

    mb_contract_gate.py red|verify --spec SPEC_DIR --mb BANK [--json]

Driven by `scripts/mb-contract-gate.sh`; see that file for the CLI contract.

WHAT THE TWO PHASES ARE ACTUALLY FOR
────────────────────────────────────
`red` answers "were the checkers failing before the code existed?" — and the
answer has to survive two ways of being wrong:

  fake_red         the checker exits 0 before anything was implemented. It
                   observes nothing, and its later green means nothing.
  foreign_failure  the checker exits non-zero for some other reason. A missing
                   file, a typo in a path, an import error — `bats <missing>`
                   exits 1 exactly like a genuine failure. Requiring the
                   declared `output_ere` to match the real output is what
                   separates "failed as predicted" from "failed somehow".

`verify` answers "does it pass now?", but only for a command whose red was
actually witnessed. Hence the precondition: every checker needs a stored
red-evidence whose `cmd`/`cmd_sha256` is byte-identical to the registry's
current argv. Edit the registry after the red run and verify refuses to start —
verifying against a command nobody ever saw fail proves nothing at all.

Evidence is published with a temp file plus `os.replace` into the same
directory, so a consumer never observes a half-written object; the phases write
separate files and `verify` never overwrites the red run's evidence.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mb_contract_registry as registry  # noqa: E402
import mb_work_items  # noqa: E402

EVIDENCE_KEYS = (
    "version",
    "topic",
    "checker_id",
    "phase",
    "cmd",
    "cmd_sha256",
    "exit",
    "output_match",
    "verdict",
)

USAGE, FAILURE, OK = 2, 1, 0


class GateError(Exception):
    """Refusal before any checker runs; carries the process exit code."""

    def __init__(self, code: int, *messages: str):
        super().__init__("; ".join(messages))
        self.code = code
        self.messages = list(messages)


# ── locating the registry ───────────────────────────────────────────────────


def contract_task(spec_dir: Path) -> dict:
    tasks_path = spec_dir / "tasks.md"
    if not tasks_path.is_file():
        raise GateError(USAGE, "tasks.md not found in %s" % spec_dir)
    try:
        items = mb_work_items.parse_work_items(tasks_path)
    except (ValueError, OSError) as exc:
        raise GateError(USAGE, "tasks.md is unparseable: %s" % exc) from exc
    found = [i for i in items if registry.layer_of(i.body) == "contract"]
    if len(found) != 1:
        raise GateError(
            USAGE,
            "expected exactly one `**Layer:** contract` task in %s, found %d"
            % (tasks_path, len(found)),
        )
    return {"item_no": found[0].item_no, "body": found[0].body}


def check_paths(checkers: list, repo_root: Path) -> None:
    """`path` must name the file `argv` runs, and that file must exist.

    It was validated only as a non-empty string: never compared with argv,
    never checked against the disk, read by no consumer. A field that can say
    anything without consequence documents nothing — and here it is the only
    human-readable statement of WHICH file implements a checker, so a stale one
    sends a reader to the wrong place while the gate reports success.
    """
    problems = []
    for checker in checkers:
        path, argv = checker["path"], checker["argv"]
        if not any(path == arg or arg.endswith("/" + path) for arg in argv):
            problems.append(
                "checker `%s`: path `%s` is not among the argv that runs it (%s)"
                % (checker["id"], path, " ".join(argv))
            )
        elif not (repo_root / path).is_file():
            problems.append(
                "checker `%s`: path `%s` does not exist under %s" % (checker["id"], path, repo_root)
            )
    if problems:
        raise GateError(USAGE, *problems)


def load_checkers(spec_dir: Path, topic: str) -> list:
    task = contract_task(spec_dir)
    text = registry.find_registry(task["body"])
    if text is None:
        raise GateError(
            USAGE,
            "contract task %s carries no ```json Contract-checkers``` block" % task["item_no"],
        )
    checkers, errors = registry.parse_registry(text, topic)
    if errors:
        raise GateError(USAGE, *errors)
    return checkers


# ── evidence paths ──────────────────────────────────────────────────────────


def _escapes(path: Path, root: Path) -> bool:
    """True when `path` resolves outside `root` (symlinks included)."""
    try:
        resolved = path.resolve()
    except OSError:
        return True
    return resolved != root and root not in resolved.parents


def evidence_path(bank: Path, topic: str, checker: dict, phase: str) -> Path:
    """The declared evidence path for one checker, resolved against the bank.

    The schema already refused a leading `/` and any `..`, but both are string
    checks and a symlinked topic directory defeats them: the literal path stays
    inside the bank while the bytes land anywhere. So the parent directory is
    RESOLVED and required to still be inside the bank.

    Resolving the parent is the whole check. An earlier version also resolved
    `<bank>/tmp/contract-gate/<topic>` separately; a mutation proved that check
    can never fire on its own, because resolution follows every component of
    the path — a symlinked topic directory is already visible in the parent.
    Two checks where one decides are not twice as safe, only twice as much to
    keep true.
    """
    full = bank / checker["evidence"].replace("{phase}", phase)
    if _escapes(full.parent, bank):
        raise GateError(USAGE, "evidence path %s resolves outside the bank %s" % (full, bank))
    return full


def write_evidence(path: Path, payload: dict) -> None:
    """Publish atomically: temp file in the destination directory, then rename."""
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=str(path.parent), prefix=".", suffix=".tmp", delete=False
    )
    try:
        with handle as fh:
            json.dump(payload, fh, ensure_ascii=False, sort_keys=True)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(handle.name, path)
    except BaseException:
        # A partial temp file is debris; a partial evidence file is a lie.
        try:
            os.unlink(handle.name)
        except OSError:
            pass
        raise


# ── the red-evidence precondition (CPR-A) ───────────────────────────────────


def _self_consistent(data: dict) -> bool:
    """Does the record's verdict follow from its own `exit`/`output_match`?

    Re-derives the verdict with the SAME rule `run_checker` applies, so the
    two can never drift: one function decides what a verdict means, and the
    reader checks against it rather than trusting the label.
    """
    if data.get("version") != 1:
        return False
    code, matched = data.get("exit"), data.get("output_match")
    if not isinstance(code, int) or not isinstance(matched, bool):
        return False
    if data["phase"] == "red":
        expected = "fake_red" if code == 0 else ("pass" if matched else "foreign_failure")
    else:
        expected = "pass" if code == 0 else "red_checker"
    return data.get("verdict") == expected


def require_red_evidence(bank: Path, topic: str, checkers: list) -> None:
    problems: list = []
    for checker in checkers:
        path = evidence_path(bank, topic, checker, "red")
        cmd = registry.canonical_cmd(checker["argv"])
        label = checker["id"]
        if not path.is_file():
            problems.append("checker `%s`: no red evidence at %s" % (label, path))
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError) as exc:
            problems.append("checker `%s`: red evidence is unreadable — %s" % (label, exc))
            continue
        if not isinstance(data, dict) or set(data) != set(EVIDENCE_KEYS):
            problems.append("checker `%s`: red evidence does not match the CPR-A schema" % label)
            continue
        if data.get("verdict") != "pass" or data.get("phase") != "red":
            problems.append(
                "checker `%s`: red evidence is `%s`, not a passing red run"
                % (label, data.get("verdict"))
            )
            continue
        if data.get("checker_id") != label or data.get("topic") != topic:
            problems.append("checker `%s`: red evidence belongs to another checker" % label)
            continue
        if not _self_consistent(data):
            # The record's own fields have to agree with its verdict. Reading
            # `verdict` alone made `version`, `exit` and `output_match`
            # decorative: an object saying phase=red, verdict=pass, exit=0,
            # output_match=false unlocked verify, though this runner could
            # only ever have written `fake_red` for that combination. Evidence
            # that cannot be checked against itself is a claim.
            problems.append(
                "checker `%s`: red evidence is self-inconsistent — verdict `%s` with "
                "exit %r and output_match %r"
                % (label, data.get("verdict"), data.get("exit"), data.get("output_match"))
            )
            continue
        if data.get("cmd") != cmd or data.get("cmd_sha256") != registry.cmd_digest(cmd):
            problems.append(
                "checker `%s`: the registry command changed after the red run "
                "(evidence %s, registry %s)" % (label, data.get("cmd"), cmd)
            )
    if problems:
        raise GateError(USAGE, *problems)


# ── running ─────────────────────────────────────────────────────────────────


def run_checker(checker: dict, repo_root: Path, phase: str) -> dict:
    """Execute one checker shell=false from the repo root and judge the result."""
    argv = list(checker["argv"])
    try:
        proc = subprocess.run(
            argv,
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            errors="replace",
        )
        code, output = proc.returncode, (proc.stdout or "") + (proc.stderr or "")
    except OSError as exc:
        # Could not even start: a non-zero exit that is emphatically NOT the
        # declared failure, which is precisely foreign_failure.
        code, output = 127, "could not execute %s: %s" % (argv, exc)

    matched = registry.ere_match(checker["output_ere"], output)
    if phase == "red":
        if code == 0:
            verdict = "fake_red"
        elif matched:
            verdict = "pass"
        else:
            verdict = "foreign_failure"
    else:
        verdict = "pass" if code == 0 else "red_checker"
    return {"id": checker["id"], "exit": code, "match": matched, "verdict": verdict}


def gate(phase: str, spec_dir: Path, bank: Path) -> tuple:
    topic = spec_dir.name
    repo_root = bank.parent
    checkers = load_checkers(spec_dir, topic)
    check_paths(checkers, repo_root)
    paths = [evidence_path(bank, topic, c, phase) for c in checkers]
    if phase == "verify":
        require_red_evidence(bank, topic, checkers)

    results = []
    for checker, path in zip(checkers, paths):
        result = run_checker(checker, repo_root, phase)
        cmd = registry.canonical_cmd(checker["argv"])
        write_evidence(
            path,
            {
                "version": 1,
                "topic": topic,
                "checker_id": checker["id"],
                "phase": phase,
                "cmd": cmd,
                "cmd_sha256": registry.cmd_digest(cmd),
                "exit": result["exit"],
                "output_match": result["match"],
                "verdict": result["verdict"],
            },
        )
        results.append(result)

    failed = [r for r in results if r["verdict"] != "pass"]
    verdict = failed[0]["verdict"] if failed else "pass"
    return {"phase": phase, "checkers": results, "verdict": verdict}, (FAILURE if failed else OK)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="mb-contract-gate", add_help=False)
    parser.add_argument("phase", choices=registry.PHASES)
    parser.add_argument("--spec", required=True)
    parser.add_argument("--mb", required=True)
    parser.add_argument("--json", action="store_true")
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return USAGE

    def diagnose(*messages: str) -> None:
        if args.json:
            return
        for message in messages:
            sys.stderr.write("[contract-gate] %s\n" % message)

    spec_dir = Path(args.spec)
    bank = Path(args.mb)
    if not spec_dir.is_dir():
        diagnose("spec directory not found: %s" % spec_dir)
        return USAGE
    if not bank.is_dir():
        diagnose("memory bank not found: %s" % bank)
        return USAGE

    try:
        report, code = gate(args.phase, spec_dir.resolve(), bank.resolve())
    except GateError as exc:
        diagnose(*exc.messages)
        return exc.code

    sys.stdout.write(json.dumps(report, ensure_ascii=False, separators=(",", ":")) + "\n")
    if code != OK:
        diagnose(
            "%s failed: %s"
            % (args.phase, ", ".join("%s=%s" % (r["id"], r["verdict"]) for r in report["checkers"]))
        )
    return code


if __name__ == "__main__":
    sys.exit(main())
