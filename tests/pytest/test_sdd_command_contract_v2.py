"""Contract tests for the `/mb sdd` generation pipeline (svp-sdd-core Task 4).

These assert the NORMATIVE STRUCTURE of the `commands/sdd.md` prompt file — the
ordered phases 0-10, the mandatory transcript gate, the candidate seam that
precedes any write to `specs/`, the draft publication, and the C8 battery step
that calls the deterministic `mb-sdd-self-check.sh` and owns the draft→ready
transition. This is the honest boundary: pytest checks the prompt CONTRACT, not
LLM behaviour — actual generation is covered by manual scenarios + the C8
battery on a real topic.
"""

from __future__ import annotations

import pathlib
import re

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SDD = REPO_ROOT / "commands" / "sdd.md"


def _text() -> str:
    return SDD.read_text(encoding="utf-8")


def _phase_sequence() -> list[int]:
    """Ordered list of pipeline step numbers as they appear in the document."""
    return [int(m.group(1)) for m in re.finditer(r"(?mi)^#+\s*Step\s+(\d+)\b", _text())]


def test_pipeline_phases_ordered() -> None:
    seq = _phase_sequence()
    assert seq == list(range(0, 11)), f"expected steps 0..10 in order, got {seq}"


def test_no_auto_generate_clause_removed() -> None:
    # The scaffold-only disclaimer must be gone — the command now generates.
    assert "does not auto-generate" not in _text().lower()
    assert "auto-generate `design.md`" not in _text()


def test_transcript_input_mandatory() -> None:
    t = _text().lower()
    assert "transcript" in t
    # missing transcript must be a loud failure, not a silent skip.
    assert re.search(
        r"transcript[^\n]*\b(missing|absent|not found|loud|error|fail)", t
    ) or re.search(r"\b(missing|absent|no)\b[^\n]*transcript", t), (
        "transcript gate must treat a missing transcript as a loud error"
    )


def test_candidate_seam_path_present() -> None:
    # candidate is written under <bank>/tmp/sdd/<topic>/tasks.candidate.md
    assert re.search(r"tmp/sdd/[^\s`]*tasks\.candidate\.md", _text())


def test_candidate_estimate_runs_on_tasks_file() -> None:
    # budget gate C3 runs on the candidate via --tasks-file (not the final file).
    assert re.search(r"mb-estimate-check\.sh[^\n]*--tasks-file", _text())


def test_candidate_seam_precedes_specs_write() -> None:
    """The candidate write + estimate must appear BEFORE the publish/specs write."""
    text = _text()
    cand = re.search(r"tasks\.candidate\.md", text)
    publish = re.search(r"mb-sdd-candidate\.sh\s+publish", text)
    assert cand and publish, "both candidate seam and publish step must be present"
    assert cand.start() < publish.start(), "candidate seam must precede the publish step"


def test_specs_tasks_not_written_before_publish() -> None:
    # The prompt must state specs/<topic>/tasks.md is not created/modified before publish.
    t = _text().lower()
    assert re.search(
        r"specs/[^\n]*tasks\.md[^\n]*(not (created|written|modified|touched)|until (publish|step\s*7|this step))",
        t,
    ) or re.search(r"not (created|written|modified|touched)[^\n]*specs/[^\n]*tasks\.md", t)


def test_step0_runs_interview_not_defer(*_a) -> None:
    """REQ-001 (blocker #1): the pipeline RUNS the interview when context is
    missing — it must not stop and defer to a separate `/mb discuss`."""
    text = _text()
    low = text.lower()
    # runs discuss/self-interview itself before generating
    assert re.search(r"(?i)run(s)?[^\n]*interview[^\n]*before generat", text) or re.search(
        r"(?i)pipeline[^\n]*run(s)?[^\n]*(interview|discuss)", text
    ), "Step 0 must RUN the interview, not defer it"
    assert "self-interview" in low
    # the contradicting out-of-scope disclaimer must be gone.
    assert "does not run `/mb discuss`" not in low
    assert not re.search(r"(?i)stop and run\s+`?/mb discuss", text)


def test_promotion_publishes_draft_via_helper() -> None:
    text = _text()
    assert re.search(r"mb-sdd-candidate\.sh\s+publish", text), (
        "promotion must go through the helper"
    )
    # promoted as draft, explicitly NOT accepted/ready at promotion time.
    assert (
        re.search(r"(?i)publish[^\n]*draft", text)
        or re.search(r"(?i)draft[^\n]*promotion", text)
        or re.search(r"(?i)lands as[^\n]*draft", text)
    )


def test_step7_calls_self_check_helper_with_mb() -> None:
    text = _text()
    assert "mb-sdd-self-check.sh" in text, "battery C8 must call the deterministic helper"
    # blocker #13: the self-check call carries --mb so it honours global storage.
    assert re.search(r"(?i)mb-sdd-self-check\.sh[^\n]*--spec[^\n]*--mb", text), (
        "self-check call must pass --mb <bank>"
    )


def test_self_check_precedes_promotion(*_a) -> None:
    """Blocker #5: C8 must run BEFORE the accepted tasks.md is replaced —
    self-check must appear before the publish/promotion in the document."""
    text = _text()
    sc = re.search(r"mb-sdd-self-check\.sh", text)
    pub = re.search(r"mb-sdd-candidate\.sh\s+publish", text)
    assert sc and pub, "both self-check and publish must be present"
    assert sc.start() < pub.start(), "C8 self-check must precede the promotion/publish"


def test_accepted_byte_identical_on_failure() -> None:
    """Blocker #5: any gate failure must leave the accepted triple byte-identical."""
    t = _text().lower()
    assert "byte-identical" in t
    assert re.search(r"(?i)(fail|refus|block|non-zero)[^\n]*byte-identical", _text()) or re.search(
        r"(?i)byte-identical[^\n]*(fail|refus|block|non-zero|gate)", _text()
    )


def test_ready_gated_by_self_check_exit_code() -> None:
    t = _text().lower()
    # draft→ready decided by the helper exit / C8=pass, not the file's mere presence.
    assert "self_check" in t or "self-check" in t
    assert re.search(r"draft\s*(?:→|-?->|to)\s*ready", t), (
        "the draft→ready transition must be documented"
    )


def test_status_state_machine_transitions() -> None:
    text = _text()
    # C7 transitions: disabled/APPROVED → ready; CHANGES_REQUESTED / SKIPPED-without-decision → draft.
    assert re.search(r"(?i)approved", text)
    assert re.search(r"(?i)changes_requested|changes requested", text)
    assert re.search(r"(?i)skipped", text)


def test_seam_block_and_user_confirmation() -> None:
    text = _text()
    assert "**Seams:**" in text, "the C9 seam block must be part of the design contract"
    assert re.search(r"(?i)seam[^\n]*rationale", text)
    assert re.search(r"(?i)confirm[^\n]*(user|with the user)|user[^\n]*confirm", text)


def test_escalation_menu_d35_present() -> None:
    t = _text().lower()
    # D-35 four-option overflow menu is referenced.
    assert "d-35" in t or "escalation" in t
    assert "budget_override" in t


def test_no_normative_sequence_publishes_before_c8() -> None:
    """Review [17]: the fix-cycle must not promote into `specs/` before C8.

    Steps 7-9 already read staged-C8 -> review -> atomic promotion. Any arrow
    sequence that names a publish/promotion BEFORE C8 contradicts them and
    would replace an accepted tasks.md with a draft that never passed the
    battery, breaking the byte-identity guarantee of REQ-053.
    """
    offenders = []
    for line in _text().splitlines():
        if "→" not in line:
            continue
        seq = [s.strip().lower() for s in line.split("→")]
        pub = next((i for i, s in enumerate(seq) if "publish" in s or "promot" in s), None)
        c8 = next((i for i, s in enumerate(seq) if "c8" in s), None)
        if pub is not None and c8 is not None and pub < c8:
            offenders.append(line.strip())
    assert not offenders, "publish/promotion precedes C8 in:\n  " + "\n  ".join(offenders)


def test_review_record_call_passes_resolved_bank() -> None:
    """Review [18]: record must be told the resolved bank, like every other call.

    Without --mb the helper resolves the active bank itself, but the prompt is
    normative for global storage: the same <bank> selected in Step 7 has to be
    threaded through, otherwise provenance for a global bank can land elsewhere.
    """
    text = _text()
    idx = text.find("mb-sdd-review-result.sh record")
    assert idx != -1, "record call not found in commands/sdd.md"
    call = text[idx : idx + 500]
    assert "--mb" in call, f"record call does not pass --mb:\n{call[:300]}"
