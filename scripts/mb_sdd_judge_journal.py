#!/usr/bin/env python3
"""Judge / override / status half of the spec-review journal — S9 contract C2.

Driven by `scripts/mb-sdd-review-result.sh`, which owns the CLI and the exit
codes; this module owns the reading, the validation and the single append. The
S2 half (`record` kind=review, `check`, `decide`) stays in the shell script,
untouched: this file is additive.

    record-judge     --bank B --topic T --pipeline P --judge-model M
                     --decision GO|GO_WITH_BACKLOG|NO_GO [--items ...] [--confirmed ...]
    record-override  --bank B --topic T
    check-judge      --bank B --topic T --pipeline P [--judge-model M] [--reviewer-model R]
    status           --bank B --topic T

exit 0 GO | valid GO_WITH_BACKLOG | override | clean check | status
     1 NO_GO | GO_WITH_BACKLOG whose surviving findings carry no backlog ids
     2 same_model | model_not_in_roster | malformed | no_verdict_to_judge | path_escape
     5 the journal EXISTS but cannot be read or classified (AMEND-S9-1)

FOUR THINGS HERE ARE DELIBERATE, EACH AGAINST A SPECIFIC FAILURE
════════════════════════════════════════════════════════════════

**A model outside the roster is UNWRITABLE, not discouraged (AGR-034 [8]).**
`--judge-model` is mandatory and must equal `sdd.spec_judge.model` in the
resolved pipeline. A journal line naming a model that never ran is a fabricated
provenance record, and this journal is exactly where such a line would land —
so the check sits before every write path, and a mismatch produces no bytes at
all. The flag is mandatory rather than defaulted from the config on purpose: a
model read out of the roster would always match it, leaving a gate that cannot
fire. A PLACEHOLDER roster (`inherit`, empty, non-string) authorises nothing —
it names no model, so it cannot back a claim about which model judged.

**`confirmed` must cover every finding of the judged verdict (AMEND-S9-2).**
The finding ids are DERIVED here from the verdict under judgement —
`R<attempt>-<NNN>`, positional over its `issues` array — because the S2 verdict
schema has no id field and inventing one would mean changing the S2 half. A
judge that cannot enumerate the findings cannot have read the spec text for
them, which is the whole point of ADR-S9-6.

**Append-only is enforced by construction.** One writer, one mode: `open(...,
"a")`. There is no code path that truncates, seeks or rewrites, and the
containment check (no symlinked directory, no symlinked file, realpath inside
the bank) is re-done on every append rather than trusted from the caller — the
S2 half learned that one the hard way (blocker #9, review [5]).

**"Cannot tell" never degrades to "nothing there".** An ABSENT journal is a
known state and reports `none`; a journal that exists but does not parse exits
5 (AMEND-S9-1). The S2 rule "the last VALID line is the current state" is kept
for SELECTION among known kinds — it is not a licence to skip a line nobody can
classify, because that is how a corrupt journal reads as a clean one.

ONE DEVIATION FROM THE LETTER OF C2, FLAGGED FOR REVIEW
═══════════════════════════════════════════════════════
C2 defines `status` as "the last valid line of EACH kind", resolved
independently. Taken literally that produces a stale pass: judge GO over
attempt 1, then a fix pass and a fresh review recording CHANGES_REQUESTED at
attempt 2, and `status` still answers `judge=GO` — so the C5 gate, whose rule
is "CHANGES_REQUESTED without a judge GO ⇒ blocked" (REQ-009), lets work
proceed on a verdict nobody judged. A judge line therefore counts only while
its `attempt` still matches the effective verdict; an older one is history.
This is narrower than the literal rule and never wider: it can only report
`judge=none` where the recorded decision does not pertain to the current
verdict. REQ-009 asks whether THIS verdict has a judge GO, so the requirement
is what is implemented and the design sentence is the thing that needs the
amendment.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_pipeline_minimal_yaml as minimal_yaml  # noqa: E402

DECISIONS = ("GO", "GO_WITH_BACKLOG", "NO_GO")
VERDICTS = ("APPROVED", "CHANGES_REQUESTED")
# C7 decision (svp-sdd-core C5). `basis` is not free text: each value asserts
# something about the verdict that was actually recorded, and is checked against it.
C7_DECISIONS = ("accept", "reject")
C7_BASES = ("skipped", "dismissed_issues")
C7_KEYS = frozenset({"kind", "decision", "basis", "rationale", "decided_by"})
ITEM_RE = re.compile(r"^I-[0-9]+$")


class Refusal(Exception):
    """Observable token on stderr + the exit code that owns it."""

    def __init__(self, token: str, code: int, detail: str = "") -> None:
        super().__init__(token)
        self.token = token
        self.code = code
        self.detail = detail


def warn(line: str) -> None:
    sys.stderr.write(line + "\n")


def utc_now() -> str:
    return datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


# ── journal ─────────────────────────────────────────────────────────────────


def journal_file(bank: str, topic: str) -> str:
    return os.path.join(bank, "tmp", "spec-review", topic + ".jsonl")


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def classify(obj) -> str | None:
    """Which known record kind this line is, or None (== unclassifiable)."""
    if not isinstance(obj, dict):
        return None
    kind = obj.get("kind")
    if kind == "judge":
        if (
            obj.get("decision") in DECISIONS
            and _is_int(obj.get("attempt"))
            and isinstance(obj.get("confirmed"), dict)
        ):
            return "judge"
        return None
    if kind == "override":
        return "override" if isinstance(obj.get("ts"), str) else None
    if kind == "decision":
        # C7 human/orchestrator decision (svp-sdd-core C5). It is its OWN kind:
        # it never answers for the verdict, and the verdict never answers for it.
        if (
            obj.get("decision") in C7_DECISIONS
            and obj.get("basis") in C7_BASES
            and _is_int(obj.get("attempt"))
        ):
            return "decided"
        return None
    # The S2 half writes its verdict line WITH NO DISCRIMINATOR, so a review is
    # recognised by shape and an absent `kind` — matching on `kind == "review"`
    # would see no verdict at all against today's writer, while both halves'
    # own suites stayed green. `"review"` is accepted too, so a discriminator
    # landing on that line later does not break this reader.
    # Any OTHER value is a record kind this reader has never heard of: it is
    # refused here rather than falling through to the shape check, because a
    # future kind that happens to carry a `status` field would otherwise be
    # answered as a verdict (AMEND-S9-1: "cannot tell" must be loud).
    if kind not in (None, "review"):
        return None
    if obj.get("status") in ("reviewed", "skipped"):
        if not isinstance(obj.get("reviewer"), dict) or not _is_int(obj.get("attempt")):
            return None
        if obj["status"] == "skipped" and obj.get("verdict") is None:
            return "review"
        if obj["status"] == "reviewed" and obj.get("verdict") in VERDICTS:
            return "review"
    return None


def read_journal(path: str, token: str):
    """[(kind, obj)] — or None when the journal is ABSENT (a known state).

    Every other failure raises: a journal that exists and cannot be read, or
    carries a line no known kind explains, is not an empty history.
    """
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        raise Refusal(token, 5, "cannot read %s (%s)" % (path, exc.__class__.__name__))
    out = []
    for number, line in enumerate(raw.splitlines(), 1):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            raise Refusal(token, 5, "line %d is not JSON" % number)
        kind = classify(obj)
        if kind is None:
            raise Refusal(token, 5, "line %d matches no known record kind" % number)
        out.append((kind, obj))
    return out


def last_of(records, kind: str):
    for found, obj in reversed(records or []):
        if found == kind:
            return obj
    return None


def finding_ids(verdict) -> list:
    """Canonical ids of the findings of the verdict under judgement."""
    issues = verdict.get("issues") or []
    return ["R%d-%03d" % (verdict["attempt"], i) for i in range(1, len(issues) + 1)]


def append(bank: str, topic: str, record: dict) -> None:
    outdir = pathlib.Path(bank, "tmp", "spec-review")
    real_bank = os.path.realpath(bank)
    if outdir.is_symlink():
        raise Refusal("path_escape", 2, "tmp/spec-review is a symlink")
    outdir.mkdir(parents=True, exist_ok=True)
    target = outdir / (topic + ".jsonl")
    if target.is_symlink():
        raise Refusal("path_escape", 2, "%s is a symlink" % target)
    real_target = os.path.realpath(target)
    # ONE containment rule: the resolved write path must be the exact path
    # inside the resolved bank. A second, weaker "is it under the bank" check
    # used to sit here; no input can distinguish it from this one, and a check
    # nothing can kill is not defence in depth, it is a line that reads like
    # protection while contributing none.
    expected = os.path.join(real_bank, "tmp", "spec-review", topic + ".jsonl")
    if real_target != expected:
        raise Refusal("path_escape", 2, "%s resolves outside the bank" % target)
    with open(real_target, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, separators=(",", ":"), ensure_ascii=False) + "\n")


# ── the two model sources ───────────────────────────────────────────────────


def roster_model(pipeline: str, block: str):
    """`sdd.<block>.model` from the resolved pipeline, or None when it names no
    model. Parsed with the SAME inline-map reader the validator uses, so the
    roster the record is checked against cannot drift from the roster the
    config was validated as."""
    if not pipeline or not os.path.isfile(pipeline):
        return None
    try:
        with open(pipeline, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    line, _top_level = minimal_yaml.find_sdd_inline_map(text, block, minimal_yaml.strip_comment)
    if line is None or not (line.startswith("{") and line.endswith("}")):
        return None
    model = minimal_yaml.parse_inline_map(line).get("model")
    if not isinstance(model, str):
        return None
    model = model.strip()
    # Shared vocabulary, not a local copy: the config validator refuses the same
    # placeholders under `enabled: true`, and two definitions would drift.
    return None if model.lower() in minimal_yaml.PLACEHOLDER_MODELS else model


def generated_by(bank: str, topic: str):
    """`generated_by` from the spec frontmatter, or None when the key is absent."""
    path = os.path.join(bank, "specs", topic, "requirements.md")
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        key, sep, value = line.partition(":")
        if sep and key.strip() == "generated_by":
            value = value.strip().strip('"').strip("'")
            return value or None
    return None


# ── arguments of a judge decision ───────────────────────────────────────────


def parse_confirmed(raw: str, ids: list) -> dict:
    got = {}
    for part in [p.strip() for p in (raw or "").split(",") if p.strip()]:
        key, sep, value = part.partition("=")
        key, value = key.strip(), value.strip().lower()
        if not sep or value not in ("true", "false"):
            raise Refusal("malformed", 2, "--confirmed takes <finding-id>=true|false pairs")
        if key in got:
            raise Refusal("malformed", 2, "duplicate confirmation for %s" % key)
        got[key] = value == "true"
    if sorted(got) != sorted(ids):
        raise Refusal(
            "malformed",
            2,
            "--confirmed must cover exactly the findings of the verdict under "
            "judgement: %s" % (", ".join(ids) or "(none)"),
        )
    return {i: got[i] for i in ids}


def parse_items(raw: str) -> list:
    items = [p.strip() for p in (raw or "").split(",") if p.strip()]
    for item in items:
        if not ITEM_RE.match(item):
            raise Refusal("malformed", 2, "backlog id %r is not I-<n>" % item)
    if len(set(items)) != len(items):
        raise Refusal("malformed", 2, "duplicate backlog id in --items")
    return items


# ── subcommands ─────────────────────────────────────────────────────────────


def cmd_record_judge(args) -> int:
    if args.decision not in DECISIONS:
        raise Refusal("malformed", 2, "--decision must be one of %s" % "|".join(DECISIONS))
    judge_model = (args.judge_model or "").strip()
    roster = roster_model(args.pipeline, "spec_judge")
    if not judge_model or roster != judge_model:
        raise Refusal(
            "model_not_in_roster",
            2,
            "sdd.spec_judge.model in %s authorises %r, not %r — a verdict naming "
            "a model the config never sanctioned is not recorded at all"
            % (args.pipeline or "(no pipeline)", roster, judge_model),
        )

    records = read_journal(journal_file(args.bank, args.topic), "journal_unreadable")
    verdict = last_of(records, "review")
    if verdict is None:
        raise Refusal(
            "no_verdict_to_judge", 2, "no spec_review verdict recorded for topic %s" % args.topic
        )

    if (verdict.get("reviewer") or {}).get("model") == judge_model:
        raise Refusal("same_model", 2, "the judge is the reviewer of the verdict under judgement")
    generator = generated_by(args.bank, args.topic)
    if generator is None:
        warn("generator_model_unknown")
        generator_check = "skipped"
    elif generator == judge_model:
        raise Refusal("same_model", 2, "the judge is the model that generated the spec")
    else:
        generator_check = "performed"

    ids = finding_ids(verdict)
    confirmed = parse_confirmed(args.confirmed, ids)
    items = parse_items(args.items)
    if items and args.decision != "GO_WITH_BACKLOG":
        raise Refusal("malformed", 2, "--items is only valid with GO_WITH_BACKLOG")
    survivors = [i for i in ids if confirmed[i]]
    if args.decision == "GO_WITH_BACKLOG" and survivors and not items:
        # Refused WITHOUT a write: an acceptance-with-backlog whose backlog does
        # not exist reads, forever after, as an acceptance (REQ-006).
        raise Refusal(
            "items_required",
            1,
            "GO_WITH_BACKLOG needs --items for the surviving findings: %s" % ", ".join(survivors),
        )

    record = {
        "ts": utc_now(),
        "attempt": verdict["attempt"],
        "kind": "judge",
        "decision": args.decision,
    }
    if items:
        record["items"] = items
    record["confirmed"] = confirmed
    record["generator_check"] = generator_check
    record["judge_model"] = judge_model
    # Same honesty rule as the S2 half: the caller asserts which model ran, and
    # the roster check proves only that the config sanctions that name.
    record["judge_model_provenance"] = "claimed"
    append(args.bank, args.topic, record)
    sys.stdout.write("spec_judge=%s attempt=%d\n" % (args.decision, verdict["attempt"]))
    return 1 if args.decision == "NO_GO" else 0


def cmd_record_override(args) -> int:
    read_journal(journal_file(args.bank, args.topic), "journal_unreadable")
    append(args.bank, args.topic, {"ts": utc_now(), "kind": "override"})
    # Silent on stdout on purpose: the C5 work-gate calls this inside a run
    # whose stdout is itself a contract ("prints nothing" is one of its states).
    return 0


def cmd_record_decision(args) -> int:
    """C7 decision (svp-sdd-core C5, round-4 findings [2][3][4]).

    Lives here rather than in the shell heredoc for one reason: `append()` above
    is the containment check, and round 4 found exactly what happens when the
    rule is held by only one of two writers — `record` refused a symlink while
    `decide` followed it out of the bank. A second implementation of the same
    rule is the drift; there is now one.
    """
    try:
        payload = json.loads(sys.stdin.read())
    except ValueError:
        raise Refusal("malformed", 2, "the decision payload is not JSON")
    # Closed schema, validated BEFORE the journal is consulted, so a malformed
    # payload is still reported as malformed rather than as `no_review`.
    if not isinstance(payload, dict) or set(payload) != C7_KEYS:
        raise Refusal("malformed", 2, "keys must be exactly %s" % ", ".join(sorted(C7_KEYS)))
    if payload["kind"] != "decision":
        raise Refusal("malformed", 2, 'kind must be "decision"')
    if payload["decision"] not in C7_DECISIONS:
        raise Refusal("malformed", 2, "decision must be accept|reject")
    if payload["basis"] not in C7_BASES:
        raise Refusal("malformed", 2, "basis must be skipped|dismissed_issues")
    for key in ("rationale", "decided_by"):
        if not isinstance(payload[key], str) or not payload[key].strip():
            raise Refusal("malformed", 2, "%s must be a non-empty string" % key)
    try:
        attempt = int(args.attempt)
    except (TypeError, ValueError):
        raise Refusal("malformed", 2, "--attempt must be an integer")

    # A decision is a statement ABOUT a review. With no verdict in the journal
    # there is nothing it can be about, and "accept, because the review was
    # skipped" becomes a gate bypass wearing an audit trail's clothes.
    verdict = last_of(
        read_journal(journal_file(args.bank, args.topic), "journal_unreadable"), "review"
    )
    if verdict is None:
        raise Refusal("no_review", 2, "no verdict recorded for topic %s" % args.topic)
    basis = payload["basis"]
    if basis == "skipped" and verdict["status"] != "skipped":
        raise Refusal(
            "basis_mismatch",
            2,
            "basis=skipped, but the recorded verdict is %s" % verdict.get("verdict"),
        )
    if basis == "dismissed_issues" and verdict.get("verdict") != "CHANGES_REQUESTED":
        raise Refusal(
            "basis_mismatch",
            2,
            "basis=dismissed_issues needs a CHANGES_REQUESTED verdict to dismiss, "
            "the recorded one is %s" % (verdict.get("verdict") or verdict["status"]),
        )

    record = {
        "ts": utc_now(),
        "attempt": attempt,
        "kind": "decision",
        "decision": payload["decision"],
        "basis": basis,
        "rationale": payload["rationale"],
        "decided_by": payload["decided_by"],
        # Same honesty rule as `reviewer_provenance`: the actor is asserted
        # by the caller, so no consumer may read it as verified.
        "decided_by_provenance": "claimed",
    }
    append(args.bank, args.topic, record)
    sys.stdout.write(
        "spec_decision=%s basis=%s attempt=%d\n" % (payload["decision"], basis, attempt)
    )
    return 0 if payload["decision"] == "accept" else 1


def cmd_check_judge(args) -> int:
    judge_model = (args.judge_model or "").strip() or roster_model(args.pipeline, "spec_judge")
    if not judge_model:
        raise Refusal(
            "judge_model_unknown",
            2,
            "no judge model on the command line and none in sdd.spec_judge.model",
        )
    records = read_journal(journal_file(args.bank, args.topic), "journal_unreadable")
    verdict = last_of(records, "review")
    reviewer_model = (args.reviewer_model or "").strip()
    if not reviewer_model and verdict is not None:
        reviewer_model = (verdict.get("reviewer") or {}).get("model") or ""
    if not reviewer_model:
        reviewer_model = roster_model(args.pipeline, "spec_review") or ""
    if not reviewer_model:
        raise Refusal(
            "reviewer_model_unknown",
            2,
            "cannot resolve the review model, so independence is unprovable",
        )
    if reviewer_model == judge_model:
        raise Refusal("same_model", 2, "the judge is the reviewer")
    generator = generated_by(args.bank, args.topic)
    if generator is None:
        warn("generator_model_unknown")
    elif generator == judge_model:
        raise Refusal("same_model", 2, "the judge is the model that generated the spec")
    return 0


def cmd_status(args) -> int:
    records = read_journal(journal_file(args.bank, args.topic), "status_unreadable")
    review = last_of(records, "review")
    judge = last_of(records, "judge")
    override = last_of(records, "override")
    if review is None:
        spec_review = "none"
    elif review["status"] == "skipped":
        spec_review = "SKIPPED"
    else:
        spec_review = review["verdict"]
    # A judge decision belongs to the verdict it judged. After a fix pass and a
    # fresh independent review (ADR-S9-2) the newest verdict carries a higher
    # `attempt` and has not been judged at all, so the previous decision is
    # history, not state: reporting it would answer REQ-009's question ("is
    # there a judge GO over THIS verdict?") with a decision about another one,
    # and hand the C5 gate a pass nobody issued.
    if judge is not None and review is not None and judge["attempt"] < review["attempt"]:
        judge = None
    sys.stdout.write(
        "spec_review=%s judge=%s override=%s\n"
        % (spec_review, judge["decision"] if judge else "none", "yes" if override else "no")
    )
    return 0


def cmd_check_roster(args) -> int:
    """Is `<model>` the one `sdd.<block>.model` sanctions? (AGR-034 [8], judge B4)

    Called before the OTHER writer of this journal appends a verdict. The rule
    was implemented once, on the judge path, and that was the defect: two
    writers append to one journal, one was gated and one was not, so a verdict
    could still name a model that never ran. The reader lives here, in the
    module that already owns the roster for the judge — a second copy is the
    same drift round-4 [4] found in containment.
    """
    model = (args.model or "").strip()
    block = args.block or "spec_review"
    roster = roster_model(args.pipeline, block)
    if not model or roster != model:
        raise Refusal(
            "model_not_in_roster",
            2,
            "sdd.%s.model in %s authorises %r, not %r — a verdict naming a model "
            "the config never sanctioned is not recorded at all"
            % (block, args.pipeline or "(no pipeline)", roster, model),
        )
    return 0


HANDLERS = {
    "record-judge": cmd_record_judge,
    "record-override": cmd_record_override,
    "record-decision": cmd_record_decision,
    "check-judge": cmd_check_judge,
    "check-roster": cmd_check_roster,
    "status": cmd_status,
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("action", choices=sorted(HANDLERS))
    # Not `required=True`: `check-roster` answers a question about the config
    # alone and touches no journal, so demanding a bank/topic from it would be
    # asking for arguments it must then ignore.
    parser.add_argument("--bank", default="")
    parser.add_argument("--topic", default="")
    parser.add_argument("--block", default="")
    parser.add_argument("--model", default="")
    parser.add_argument("--pipeline", default="")
    parser.add_argument("--judge-model", dest="judge_model", default="")
    parser.add_argument("--reviewer-model", dest="reviewer_model", default="")
    parser.add_argument("--decision", default="")
    parser.add_argument("--items", default="")
    parser.add_argument("--confirmed", default="")
    parser.add_argument("--attempt", default="")
    return parser


def main(argv) -> int:
    try:
        args = build_parser().parse_args(argv)
    except SystemExit:
        sys.stderr.write("error=usage\n")
        return 2
    if args.action != "check-roster" and not (args.bank and args.topic):
        sys.stderr.write("error=usage\n")
        return 2
    try:
        return HANDLERS[args.action](args)
    except Refusal as refusal:
        sys.stderr.write(refusal.token + "\n")
        if refusal.detail:
            sys.stderr.write(refusal.detail + "\n")
        return refusal.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
