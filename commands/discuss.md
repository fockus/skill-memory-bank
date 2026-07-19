---
description: 5-phase requirements-elicitation interview that produces an EARS-validated context/<topic>.md
allowed-tools: [Bash, Read, Write, AskUserQuestion, Task]
---

# /mb discuss <topic>

Run a structured 5-phase interview that turns a fuzzy idea into an EARS-validated `context/<topic>.md`. The output feeds `mb-traceability-gen.sh` REQ → Plan → Test matrix and is read by `/mb plan` to link stages to requirements.

## When to use

Before creating a non-trivial plan (`/mb plan feature/refactor/...`). Skip for trivial fixes — the overhead isn't justified.

## Arguments

- `<topic>` — short slug (kebab-case). Becomes the filename: `.memory-bank/context/<topic>.md`.

## Workflow

### Pre-flight

1. Resolve `MB_PATH = .memory-bank/`. Refuse if missing (suggest `/mb init`).
2. Compute `CONTEXT_FILE = $MB_PATH/context/<topic>.md`.
3. If `CONTEXT_FILE` exists → ask `AskUserQuestion`: continue editing / overwrite / cancel.

### Phase 0 — Research (before the first question)

Recommendations must be grounded in evidence, not guesses. Gather it up front:

1. **Core context** (best-effort, skip if missing): `roadmap.md`, `research.md`, `backlog.md`, `codebase/STACK.md`, `codebase/ARCHITECTURE.md`.
2. **Codebase recon** — map the topic's touchpoints: code graph (`jq` over `codebase/graph.json`) or `mb-semantic-search.py "<topic>"` for concepts, `grep`/`Glob` fallback. Record exact `file:line` for every place the feature will touch.
3. **Prior decisions** — `/mb recall <topic>` over `session/` + `notes/`; check `plans/` and `specs/` for earlier attempts at the same topic.
4. **External research** (only when the topic involves an external library, protocol, standard, or ecosystem prior art): dispatch the `mb-researcher` subagent (WebSearch/WebFetch) and demand source URLs. Skip for purely internal topics — don't research what the repo already answers.

Compress findings into a **Research digest** — ≤20 lines, each line one fact + citation (`file:line` or URL). Show it to the user before Phase 1; every recommendation in the interview cites the digest or the code. A recommendation without a citation is a guess — say so explicitly.

### Interview plan

Before the first question, write an interview plan to `<bank>/tmp/interview-plan-<topic>.md` — the white-spot ledger that keeps the interview honest. It lists the topics to close and the inherited decisions not to re-ask; generation is gated on closing every topic (grilling rule 11).

Structure (contract C2, validated by `scripts/mb-interview-artifact-check.sh plan`, installed by `scripts/mb-interview-artifact-write.sh install-plan`):

- `## Inherited decisions (do not re-ask)` — decisions carried from `parent_context` (JIT slice interviews); empty for a root topic.
- `## Topics` — one `- [ ]` line per planned theme; flip to `- [x]` once the theme is closed.
- `## Discovered mid-interview` — append `- [ ]` lines for themes that surface while grilling.

Do not hand-write the file: build a candidate and install it through the deterministic writer (`mb-interview-artifact-write.sh install-plan`), so the atomic write and structural validity are script-proven, not prompt-judged. The full template lives in `references/templates.md` (`## Interview plan template`).

### 5 phases — one question at a time

After each phase, restate what was captured and ask the user to confirm before moving on.

#### Grilling rules — apply to every question

> **Source & attribution.** The grilling rules below (the `grill-me` / `grill-with-docs` interview patterns, the recommend-don't-ask discipline, and the concrete-scenario stress-tests) are adapted from [mattpocock/skills](https://github.com/mattpocock/skills), used under the MIT license.

The 5 phases below are the **coverage checklist**, not a rigid script. While walking them, grill the design:

1. **Recommend, don't just ask.** Every question carries your recommended answer + a one-line rationale. The user confirms or corrects — never fills a blank. (Inspired by `grill-me`.)
2. **Code answers beat guesses.** If a question is answerable from the codebase, resolve it via the MB code graph / graphify / grep **before** asking, and cite `file:line`. Only ask the user what the code genuinely can't tell you: intent, priorities, trade-offs.
3. **Follow the dependency tree.** When an answer unblocks a downstream decision, chase that branch to resolution before returning to the next phase — order questions by dependency, not strictly by phase number.
4. **Stress-test with concrete scenarios.** Don't ask "any edge cases?" in the abstract — invent specific scenarios ("the feed has the product but `price` is null") and force a precise answer on the boundary. (From `grill-with-docs`.)
5. **Surface contradictions with code.** When stated intent conflicts with what the code actually does, call it out: "the code does X, but you said Y — which is right?" Resolve the contradiction before recording the requirement.
6. **One question per turn, recommendation first.** Never bundle questions — one decision, wait for the answer, then the next. When using `AskUserQuestion`, put your recommended option first with "(Recommended)" in its label and the rationale in its description.
7. **Relentless until shared understanding.** Phase coverage is the floor, not the finish line. If an answer opens a new ambiguity, chase it — even outside the 5 phases. Stop interviewing only when no decision remains that could change the requirements.
8. **Final confirmation gate.** Before writing `context/<topic>.md`, present a numbered summary of every decision taken and get an explicit confirmation. Corrections reopen the affected branch; do not write the file until the summary is confirmed. (Grilling's "do not act until shared understanding is confirmed".)
9. **Decision ledger.** Maintain a running numbered ledger throughout the interview: every decision taken (`D-NN`: decision + rationale + alternatives rejected) and every open question discovered. An answer that spawns new questions puts them on the ledger before you continue — nothing gets dropped because a branch ran long. The ledger is what rule 8 presents for confirmation, and it lands in the file as `## Decision Log` + `## Open Questions`.
10. **Depth floor, no question cap.** A phase is done when questioning stops producing new information — not when it "feels covered". Heuristic: if the last two answers changed nothing on the ledger, move on; while answers keep changing requirements, keep asking. Never cut the interview short to save turns.
11. **No generation with open topics.** Do not generate any artifact while the interview plan still has open `- [ ]` topics — return to each open theme and ask the missing questions before generating (REQ-002). Cancelling mid-interview keeps `status: draft` and preserves the plan file for resume (REQ-019).
12. **Final "anything to add?" gate.** Once the interview plan has no open topics, ask the user a final "anything to add?" question before generation (REQ-003). A non-empty answer reopens the discussion iteration and records the new material on the decision ledger (REQ-004); only an explicit "no" lets generation proceed. Separate from rule 8 (the decision-summary confirmation) — this gate does not replace it.
13. **Glossary.** When a term is resolved during the interview, record it immediately in `.memory-bank/glossary.md` through `mb-glossary.sh upsert` (never a raw prompt write); the file is created lazily on the first term, one line per entry as «term — definition». If a later statement conflicts with an existing glossary term, challenge the conflict before recording the requirement (REQ-018).
14. **Fast-to-code bypass.** At any point the user may explicitly choose fast-to-code mode to skip the remaining interview and decomposition steps; record the choice and its quality trade-off in the context frontmatter (REQ-020). Quality mode stays the default for every interview.

#### Phase 1 — Purpose & Users

- Who uses this?
- What problem does it solve for them?
- How will we know it's a success (qualitatively)?

#### Size triage

After Phase 1 closes, estimate the topic size and record it before going deeper. Estimate every touched surface with the fixed rubric, then write the `estimated_tokens` block (a `total` plus a six-key `breakdown`) into the context frontmatter and validate it with `scripts/mb-estimate-check.sh` (contract C1). The six rubric categories are exactly the `breakdown` keys:

| Category (`breakdown.*`) | ~Tokens / unit |
|---|---|
| `shell_scripts` (new script) | 15 000 |
| `prompt_changes` (command / prompt edit) | 8 000 |
| `python_modules` (new Python module) | 25 000 |
| `test_files` (test file) | 10 000 |
| `docs_pages` (docs page) | 5 000 |
| `external_integrations` (external API integration) | 30 000 |

When the estimate exceeds the ~1M-token spec budget, recommend splitting the topic into **named** grouped specs — and state that each accepted child receives its own follow-up interview (REQ-009). The recommendation is advisory: the user may decline the recommendation and keep the topic whole. On acceptance, register the deferred specs with `mb-idea.sh` under a `[SPEC:<group>]` title prefix (contract C7) and continue the interview on the selected spec (REQ-010).

If a discussion branch itself grows to spec size, offer two choices before continuing — defer it as its own child spec, or simplify it to an MVP inside the current topic (REQ-021).

#### Phase 2 — Functional Requirements (EARS-enforced)

For each requirement, pick one of the 5 patterns and assign the next ID via `bash $SKILL_DIR/scripts/mb-req-next-id.sh --spec <topic> "$MB_PATH"` (per-spec-local: the topic owns its REQ namespace, so a brand-new topic starts at `REQ-001` regardless of other specs):

| Pattern | Template |
|---|---|
| Ubiquitous | `The <system> shall <response>` |
| Event-driven | `When <trigger>, the <system> shall <response>` |
| State-driven | `While <state>, the <system> shall <response>` |
| Optional | `Where <feature>, the <system> shall <response>` |
| Unwanted | `If <trigger>, then the <system> shall <response>` |

After all REQs are drafted, run the validator on the in-memory draft:

```bash
echo "$DRAFT_REQ_BLOCK" | bash $SKILL_DIR/scripts/mb-ears-validate.sh -
```

If exit ≠ 0, surface every violation back to the user and re-prompt for that specific REQ.

#### Phase 3 — Non-Functional Requirements

Performance, security, scale, observability. Capture as `**NFR-NNN**: <description>` (free-form, no EARS enforcement).

#### Phase 4 — Constraints + Out-of-Scope

- Hard constraints (regulatory, technical, organizational).
- Explicit exclusions — prevents scope creep at planning time.

#### Phase 5 — Edge Cases & Failure Modes

What breaks at boundaries? What happens when dependencies fail? What's the worst-case input? Apply grilling rule 4 — probe each with a **concrete scenario**, not an abstract category.

### Batch mode

`/mb discuss <topic> --batch` trades the one-question-at-a-time cadence for frontier rounds. `--batch` overrides grilling rule 6 (one question per turn) and only that rule — every other grilling rule still holds.

- **Frontier round.** Ask the whole current frontier of unblocked questions in one numbered round, with a recommendation on each question (REQ-015).
- **Tool limit.** On hosts with `AskUserQuestion`, batch up to 4 questions per call and issue several calls in one round when the frontier exceeds four.
- **Degradation.** On a host without an interactive question tool, the round degrades to a numbered plain-text list — it is never skipped (REQ-016).
- **Partial answers.** When a round is only partially answered, answered themes close `- [x]` while every unanswered question stays `- [ ]` in the interview plan and returns in the next frontier (REQ-022).
- **Fact-finding, parallel.** Before asking the round, fact-find every unblocked frontier question from the same sources as Phase 0 (code graph / semantic-search / grep; `mb-researcher` only for external topics); on a host that provides subagent dispatch, run the fact-finding in parallel subagents, one per frontier question (REQ-055).
- **Fact-finding, citation.** Each per-question recommendation must cite the found fact (`file:line` or URL), never a guess (REQ-015).
- **Fact-finding, honest degradation.** On a host whose manifest lists `platform_limited: subagents`, run the same fact-finding sequentially in the main agent — never skipped — and report the degradation to the user in one line (REQ-056, AGR-013).
- **Default off.** Without `--batch` the default is unchanged: one question per turn, with no parallel subagent dispatch (D-18).

### Self-interview

`/mb discuss <topic> --self "<brief>" [--auto]` runs the interview against the brief instead of asking the user. Quality mode (live interview) stays the default when no flag is given.

- **Self-answers.** With `--self "<brief>"` the agent answers the interview questions itself from the brief, citing it like any other evidence.
- **Assumptions block.** Every self-answered decision is recorded in a `## Assumptions (self-answered)` block in the context file, so nothing assumed on the user's behalf is hidden.
- **Interactive confirmation.** In interactive self-interview (without `--auto`), present the assumptions batch for confirmation before generation (REQ-013).
- **Auto mode.** With `--auto` the run does not block on assumptions and offers their review after completion (REQ-014).
- **`--auto` needs `--self`.** `--auto` without `--self` is a usage error raised before writing any files.
- **Non-empty brief.** An empty or whitespace-only brief is a usage error raised before writing any files.
- **Batch is orthogonal.** `--batch` is compatible with `--self` and changes only the frontier size, not the answer mode.
- **Draft resume.** An existing `draft` context resumes the saved interview plan rather than starting over.
- **Ready context.** An existing `ready` context keeps the current edit / overwrite / cancel choice unchanged.

### Write & finalize

1. Render `context/<topic>.md` using the template in `references/templates.md` (`## Context (context/<topic>.md)` section). Write it thoroughly: include the **Research digest** (with its citations), the **Decision Log** (decision → rationale → alternatives rejected, from the ledger), and **Open Questions** (anything deferred, so `/mb plan` addresses or explicitly parks each). Every REQ must trace back to a ledger decision — no requirement appears out of thin air.
2. Run `bash scripts/mb-ears-validate.sh "$CONTEXT_FILE"`. If it fails, fix in place and retry — do not commit invalid state.
3. Run `bash scripts/mb-traceability-gen.sh "$MB_PATH"` so the matrix picks up new REQs.
4. Update frontmatter `status: ready`.

#### Transcript

When the interview completes, save a curated transcript to `context/<topic>-interview.md` (contract C4, grammar validated by `mb-interview-artifact-check.sh transcript`). It preserves the user's answers near-verbatim, including rejected alternatives (REQ-005), so the planner and spec-reviewer see the real discussion.

- **Candidate first.** Write the candidate to `<bank>/tmp/interview-transcript-<topic>.candidate.md` before any git-tracked path.
- **Scan gate.** Run `mb-secret-scan.sh --policy transcript` on the candidate before publication.
- **Private is not a bypass.** The scan reads the raw text including content inside `<private>` — a `<private>` marker never unblocks a git write (R3-001).
- **Block on finding.** On a finding the git target is not created, and the user is offered removal or irreversible redaction of the credential (REQ-007).
- **Publish through the writer.** `mb-interview-artifact-write.sh publish-transcript` atomically installs `context/<topic>-interview.md` only after the scan and the C8 grammar check both pass, and the context frontmatter records `interview_transcript: context/<topic>-interview.md`.

### Out of scope for this command

- Does not create a plan (`/mb plan` does that, optionally reading `context/<topic>.md`).
- Does not edit `roadmap.md` / `status.md` directly — those flip at `/mb plan` and `/mb done` time.

## Exit conditions

- Success: `context/<topic>.md` exists, EARS-valid, traceability regenerated.
- Cancel mid-interview: leave `status: draft` so `/mb discuss` can resume later.
- Validation failure that user can't fix: keep the file as `status: draft` and surface the violation list.

## Related

- `/mb plan <type> <topic>` — read `context/<topic>.md` to link stages to REQs.
- `/mb traceability-gen` — regenerate `traceability.md` after edits.
- `bash scripts/mb-req-next-id.sh --spec <topic>` — next per-spec-local REQ-NNN for this topic (omit `--spec` for a project-wide max+1).
- `bash scripts/mb-ears-validate.sh <file>|-` — validate REQ lines against the 5 EARS patterns.
