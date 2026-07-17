---
topic: svp-brief
group: sdd-vision-pipeline
ice: {impact: 8, confidence: 8, ease: 7}
ice_confirmed: false
blocked_by: [svp-interview-upgrade]
covers_umbrella: [REQ-045, REQ-046]
status: ready
---

# Requirements: svp-brief

> Spec triple — see also: design.md, tasks.md.
> Слайс S7 группы `sdd-vision-pipeline` (ICE 448, self-interview). Контекст: `context/svp-brief.md`;
> транскрипты: `context/svp-brief-interview.md` + родительский `context/sdd-vision-pipeline-interview.md`.
> Ревизия 3 (2026-07-17): REQ-010 переписан под MVP-контракт «abort, никакого override» (SVP-BRIEF-001),
> сценарии 3–5 выровнены на `brief=blocked reason=…` и манифест `mb-brief.sh context` (R2-001),
> добавлен сценарий 7 (`--auto` + `assumptions_note`, SVP-BRIEF-003/006).
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous: `THE SYSTEM SHALL` · Event: `WHEN … THE SYSTEM SHALL` · State: `WHILE … THE SYSTEM SHALL` · Optional: `WHERE … THE SYSTEM SHALL` · Unwanted: `IF … THEN THE SYSTEM SHALL`

## Requirements (EARS)

### Requirement 1: Одностраничник из любого входа

**User Story:** As a user with a raw request and a pile of documents, I want `/mb brief` to produce a validated one-pager stored with its sources, so that the work enters the pipeline formalized.

#### Acceptance Criteria

- **REQ-001** (event-driven): When `/mb brief <topic>` runs, the system shall create `briefs/<topic>/` containing `brief.md` and an `inputs/` folder with copies of the attached source documents. <!-- S7-A-01 -->
- **REQ-002** (ubiquitous): The generated `brief.md` shall contain the sections Essence, Goal & Impact, References, Solution (JTBD), Scenarios, Constraints, UX, Done Criteria and Attachments. <!-- S7-A-02 -->
- **REQ-007** (ubiquitous): The system shall validate the brief structure — required sections present — by script. <!-- NFR-002 -->
- **REQ-008** (event-driven): When source documents are attached, the system shall list them in the Attachments section with relative links into `inputs/`. <!-- S7-A-01 -->

### Requirement 2: Лёгкие уточнения — не интервью

**User Story:** As a user, I want clarifying questions only when my intent is genuinely unclear, so that briefing stays fast and the deep interview remains discuss's job.

#### Acceptance Criteria

- **REQ-003** (unwanted): If the essence or the goal of the request remains unclear after analyzing the inputs and `--auto` is not selected, then the system shall ask up to five light clarifying questions before generating the brief. <!-- S7-A-03 -->
- **REQ-004** (state-driven): While the intent is clear from the request and inputs, or `--auto` is selected, the system shall generate the brief without asking questions; when `--auto` bypasses an otherwise-unclear intent, the brief shall carry a non-empty `assumptions_note`. <!-- S7-A-03 -->

### Requirement 3: Хендоф в discuss

**User Story:** As a user, I want the brief to flow into `/mb discuss` automatically, so that the next stage starts from the formalized request.

#### Acceptance Criteria

- **REQ-005** (event-driven): When the brief is written, the system shall offer to proceed to `/mb discuss` seeded by the brief. <!-- umbrella REQ-046 -->
- **REQ-006** (event-driven): When `/mb discuss` runs for a topic with an existing brief, the system shall read `brief.md` and its inputs during Phase 0. <!-- S7-A-04 -->

### Requirement 4: Секрет не должен попасть в git через `inputs/`

**User Story:** As a user attaching real project documents, I want any credential in those documents to block the copy — not silently land in `briefs/<topic>/inputs/` and from there in git — so that briefing never becomes a leak vector.

#### Acceptance Criteria

- **REQ-009** (unwanted): If a secret-scan finds a credential in a source before it is copied into `inputs/`, then the system shall refuse to copy that source and report the finding instead, until the secret is removed or redacted in the source itself or the offending line carries an explicit `<!-- mb-secret-ok -->` pragma. <!-- BRIEF-001 -->
- **REQ-010** (unwanted): If a source cannot be scanned because it is unreadable, binary, or of an unsupported type, then the system shall abort before any destination mutation, print `brief=blocked reason=scan_unsupported` on stdout, name every unscannable source with its reason on stderr, and require a fresh invocation after that source is removed, converted, or excluded — an unsupported source shall never be copied in MVP and no override flag shall exist. <!-- BRIEF-001, SVP-BRIEF-001 -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Brief from a prompt plus a scannable input
**Covers:** REQ-001, REQ-002, REQ-004, REQ-008

- GIVEN a user runs `/mb brief checkout-v2` with a paragraph of text and an attached `PRD.md` (a readable UTF-8 text file) that scans clean
- WHEN the intent is clear from the request and the attached input
- THEN `briefs/checkout-v2/{brief.md, inputs/PRD.md}` is published in one step from the complete candidate — nothing exists under `briefs/checkout-v2/` before that step — all 9 sections are filled, Attachments links to `inputs/PRD.md`, stdout is `brief=created path=briefs/checkout-v2/brief.md`, and no clarifying questions are asked
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Unclear goal triggers light questions
**Covers:** REQ-003

- GIVEN a request "make it like the competitors" with no attached documents
- WHEN the essence and goal cannot be extracted from the request alone
- THEN up to 5 clarifying questions are asked (what exactly, what impact), and the brief is generated only after they are answered
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Secret in an attachment blocks the copy
**Covers:** REQ-001, REQ-009

- GIVEN an attached `.env`-like file containing an API key, including one line wrapped in `<private>...</private>`
- WHEN `/mb brief` scans sources before copying them into `inputs/`
- THEN stdout is `brief=blocked reason=secret`, the scanner finding is forwarded on stderr, nothing is copied into `inputs/`, `briefs/<topic>/` does not exist afterwards, and `<private>` does not unblock the copy — only removing/redacting the secret in the source or marking the finding line with `<!-- mb-secret-ok -->` does
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Unscannable attachment aborts the brief instead of copying silently
**Covers:** REQ-001, REQ-010

- GIVEN an attached file the scanner cannot read (a corrupted binary or an unsupported format)
- WHEN `/mb brief` scans it before copying anything into `inputs/`
- THEN the command aborts before any destination mutation, prints `brief=blocked reason=scan_unsupported` on stdout, names the file and its reason on stderr, leaves `briefs/<topic>/` non-existent, and offers no override — the only continuations are removing, converting or excluding the source and invoking the command again
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Brief handoff seeds discuss Phase 0
**Covers:** REQ-005, REQ-006

- GIVEN a completed `ready` brief with one input file at `briefs/checkout-v2/{brief.md, inputs/PRD.md}`
- WHEN `/mb brief` finishes and the user then runs `/mb discuss checkout-v2`
- THEN `/mb brief` offers the exact command `/mb discuss checkout-v2` as its final line, and the discuss Phase 0 research digest takes its first sources from the `brief_path`/`input_path` manifest printed by `scripts/mb-brief.sh context`
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Validator rejects a brief missing a required section
**Covers:** REQ-007

- GIVEN a `brief.md` with all required sections except `## UX`
- WHEN `scripts/mb-brief-validate.sh` runs against it
- THEN it exits 1, prints `brief=invalid` on stdout and `error=missing_section section=UX` on stderr
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Auto mode skips the question gate and records its assumptions
**Covers:** REQ-004

- GIVEN a vague request run as `/mb brief checkout-v2 --auto` with no attached documents
- WHEN the essence and the goal cannot be extracted from the request alone
- THEN no clarifying questions are asked and the published brief carries a non-empty `assumptions_note` in its frontmatter, while a candidate generated under `--auto` without that key is refused with `brief=blocked reason=invalid` before anything is published
<!-- /mb-scenario:7 -->
