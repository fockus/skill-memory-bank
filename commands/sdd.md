---
description: Generate a Kiro-style spec triple — specs/<topic>/{requirements,design,tasks}.md
allowed-tools: [Bash, Read, Write, Task]
---

# /mb sdd <topic>

Generate a Kiro/Kilo-compatible spec triple under `.memory-bank/specs/<topic>/`. Each file has a single concern: **requirements** (Kiro User Stories + EARS acceptance criteria — hybrid format), **design** (architecture + interfaces + decisions + Eval declarations), **tasks** (numbered `<!-- mb-task:N -->` work items with `**Eval:**` / `**Scope:**` / `**Budget:**`).

`/mb sdd` is a **generation pipeline**, not a blank scaffolder: it reads the discuss/self-interview transcript, generates full content, gates the size, publishes the triple as **draft**, and runs the deterministic C8 self-check battery before anything is called ready. The raw scaffold writer still exists for direct use (see *Scaffold boundary*).

## Hybrid requirements format

`requirements.md` pairs the two industry conventions instead of choosing one:

- **Kiro User Story** per requirement — `### Requirement N` + `**User Story:** As a <role>, I want <feature>, so that <benefit>.` (the "who / why").
- **EARS acceptance criteria** under each — a `#### Acceptance Criteria` heading with `- **REQ-NNN**: WHEN ... THE SYSTEM SHALL ...` bullets in the 5 EARS patterns, uppercase keywords (the testable "what"). `mb-ears-validate.sh` is case-insensitive and validates only these bullets; User-Story lines are ignored, so the two layers coexist with zero tooling conflict.

REQ-IDs stay unique and traceable; `mb-traceability-gen.sh` and `**Covers:** REQ-NNN` in `tasks.md` are unaffected by the grouping.

## Why split into three?

- Parallel work — requirements / design / tasks evolve at different speeds.
- `requirements.md` stays self-contained and exportable to Kiro.
- `tasks.md` is checkbox-compatible with downstream tools.
- `mb-traceability-gen.sh` automatically picks up REQ-IDs from `specs/*/requirements.md` for the REQ → Plan → Test matrix.

## When to use

After `/mb discuss <topic>` (or a self-interview) produced a transcript and an EARS-validated `context/<topic>.md`, when the work is large enough to need a dedicated spec triple. For small fixes, `/mb plan` alone is enough.

## Arguments

- `<topic>` — short slug (kebab-case). Becomes the directory name `specs/<topic>/`.
- `--force` — overwrite an existing spec triple (refuses without it).
- `--scaffold-only` — bypass the generation pipeline and emit blank scaffolds only (the C7 alias for the raw writer; see *Scaffold boundary*).

## Generation pipeline

The pipeline runs the following steps **in order**. Each step is a hard gate: a
failure stops the pipeline, leaves any accepted `specs/<topic>/tasks.md`
byte-identical, and reports `sdd_status=blocked` (escalation) or
`sdd_status=invalid` (malformed input). The final report lists the three paths
plus one `eval.<task-id>=<eval_status>` line per task from the C8 battery.

### Step 0 — Context gate: run the interview when it is missing

When there is no discuss/self-interview transcript or EARS-valid `context/<topic>.md`, the pipeline **runs the interview itself before generating** (REQ-001): interactively it runs the `/mb discuss <topic>` interview (plan → size gate → triage); in `--auto` it runs a **self-interview and records the assumptions**. It does NOT stop and defer to a separate command — generation only proceeds once a transcript exists. The pipeline never invents requirements without a source.

### Step 1 — Read the transcript

Reading the transcript is **mandatory**. A missing transcript file is a **loud error** (`sdd_status=invalid`), never a silent skip — the generator must consume the real interview output, not guess from memory.

### Step 2 — Generate requirements → staging

Generate `requirements.md` into the staging dir `<bank>/tmp/sdd/<topic>/requirements.md` (NOT `specs/`): Kiro User Stories + EARS acceptance criteria, REQ-IDs from `mb-req-next-id.sh --spec <topic>`. Add GIVEN/WHEN/THEN `<!-- mb-scenario:N -->` blocks for gated SHALL/MUST requirements; scenario names must be ASCII/English slugs.

### Step 3 — Generate design → staging (§Contract + seams + Eval declarations)

Generate `design.md` into the staging dir `<bank>/tmp/sdd/<topic>/design.md`: architecture, interfaces, decisions, risks. The §Contract section carries the machine-readable C9 seam block and **you must confirm the seams with the user** before continuing:

```markdown
**Seams:**
- <the single, highest seam>
**Seam rationale:** <why more than one> ← required ONLY when ≥2 seams
```

Default is exactly one seam (existing seams > new; pick the highest). More than one requires a brief `**Seam rationale:**`. `design.md` also carries a §Eval declarations block whose `**Eval:**` lines are byte-identical to the same-named task's `**Eval:**` line in `tasks.md` (the CPR-D byte-identity gate).

### Step 4 — Generate candidate tasks.md (v2) → staging

Generate the tasks as a **candidate**, written to `<bank>/tmp/sdd/<topic>/tasks.candidate.md` — NOT to `specs/`. Each task block carries `**Covers:**`, bare `**Role:**`, `**Stage:**`, `**Scope:**` (restricted glob), `**Budget:**` (integer), and a `**Eval:**` line carrying an `exit:` / `output~:` red anchor (or `none — waiver: <reason>` for a non-gated task). Copy the block shape from `references/templates.md`; do not write formats from memory.

### Step 5 — Budget gate (C3) on the candidate

Run the size gate on the candidate — exactly the generated file, never a stale final. Keep the stdout verdict for the promotion step:

```bash
bash scripts/mb-estimate-check.sh --tasks-file <bank>/tmp/sdd/<topic>/tasks.candidate.md
```

`spec=over`, `task_over`, or `stage_over` triggers the **Escalation menu (D-35)** below. `spec=near` is advisory. The estimator is a pure checker — it never writes or moves the candidate.

### Step 6 — DAG self-check on the candidate

Resolve the candidate's `Blocked-by` graph and confirm it is acyclic and that every dependency resolves. A cycle or an unresolved dependency stops the pipeline (`sdd_status=blocked`) and the candidate is discarded.

### Step 7 — C8 self-check battery on the STAGED draft (before touching `specs/`)

Assemble the staged draft triple in `<bank>/tmp/sdd/<topic>/` (the generated `requirements.md`, `design.md`, and the candidate as `tasks.md`) and run the deterministic battery on it — **the accepted `specs/<topic>/tasks.md` is not touched yet**. The pipeline **calls** the helper; it does not reproduce the preflight by prompt judgement. Pass `--mb <bank>` so the check honours the selected storage (local OR global):

```bash
bash scripts/mb-sdd-self-check.sh --spec <bank>/tmp/sdd/<topic> --mb <bank>
```

The helper prints `self_check=ready|invalid`, then one `eval.<task-id>=ready|pending_materialization|invalid` line per task, and owns the exit code. A non-zero exit (any `invalid`, cycle, structural failure) **stops the pipeline before promotion**, discards the candidate, and leaves the previously accepted `specs/<topic>/tasks.md` **byte-identical**. `pending_materialization` is not a failure.

A **structural failure short-circuits** the battery: the violations are printed on stderr, `self_check=invalid` is the only stdout line, and **no Eval command is executed** — a spec already known to be malformed does not get code run on its behalf, and the missing `eval.*` lines mean "the behavioural half never ran", never "this spec has no tasks". Fix the structural violations and re-run.

### Step 8 — Optional spec review (C5) on the draft

If `sdd.spec_review.enabled` is true: first call `mb-sdd-review-result.sh check --generator-model <exact> --reviewer-model <exact>` — equal models return `same_model` (exit 2) and dispatch is forbidden. Otherwise dispatch the review model with the transcript + staged spec (the prompt owns the dispatch and passes the *actually resolved* model IDs; the dispatch is a `Task` call — which is why `Task` is in this command's `allowed-tools`, without it this step is unexecutable on any host that honours the allowlist), then record the verdict through `mb-sdd-review-result.sh record --topic <topic> --attempt <n> --generator-model <exact> --reviewer-model <exact> --reviewer-agent <exact> --thinking <low|medium|high> --input <path|-> --mb <bank>` (pass the same resolved `<bank>` as Step 7, so provenance for a global bank is recorded in it; all identity flags are **mandatory**; the helper owns validation, the append-only JSONL, and the exit code: 0 APPROVED / 1 CHANGES_REQUESTED / 2 unavailable|malformed). Unavailability is reported loudly as SKIPPED (its own JSONL line), never a silent pass.

### Step 9 — Atomic promotion (ONLY after C8 pass + review resolution)

Only now — after C8 passed and review resolved — promote the staged draft into `specs/`. The tasks.md promotion is an atomic same-filesystem rename through the deterministic lifecycle helper, which re-parses the C3 verdict and keeps the accepted target byte-identical on any refusal:

```bash
bash scripts/mb-sdd-candidate.sh publish --topic <topic> \
     --candidate <bank>/tmp/sdd/<topic>/tasks.candidate.md \
     --estimate-file <estimate-stdout> --mb <bank> [--override user] [--force]
```

**`--force` is the existing-spec gate, re-checked inside the helper.** When `specs/<topic>/tasks.md` already exists, publish refuses with `candidate=blocked reason=spec_exists` (exit 1) and leaves the accepted triple byte-identical. Pass `--force` only when the user invoked `/mb sdd <topic> --force`; the helper enforces this itself so the guarantee cannot be lost by a caller that skips the prompt-level check (review [14]).

The triple lands as **status: draft** — promotion is not acceptance. `specs/<topic>/tasks.md` is never created or modified until this step, and only when every earlier gate passed; the staged `requirements.md`/`design.md` are moved into place alongside it. Any block/malformed verdict, or any earlier gate failure, leaves the existing accepted triple **byte-identical**.

### Step 10 — Status transition draft → ready

Apply the C7 status state machine (below) to decide `draft → ready`, then print the final report (`sdd_status`, three paths, and the `eval.<task-id>=…` lines).

## Escalation menu (D-35)

When Step 5 reports an overflow, present the four-option menu and act on the choice — never silently accept an oversized spec:

1. **Split now** — decompose into smaller tasks/stages and regenerate the candidate.
2. **MVP-trim → registry** — cut scope to an MVP and defer the rest as child specs, registered via `mb-idea.sh "[SPEC:<group>] <child-topic>"` (the orchestrator is the sole registry writer).
3. **Umbrella + JIT** — keep an umbrella spec and slice releases just-in-time.
4. **`budget_override: user`** — accept a `spec=over` spec by adding `budget_override: user` to `requirements.md` frontmatter. This lifts **only** `spec=over` and **only** when `task_over=none ∧ stage_over=none`. The hard D-13 caps (task ≤120000, stage ≤400000) are never overridable — a `task_over`/`stage_over` candidate is always blocked and discarded.

An `auto` choice generates self-interview slices and records an **assumption**. Escalation that the user cancels calls `mb-sdd-candidate.sh discard` and reports `sdd_status=blocked` — the candidate is removed and `specs/<topic>/tasks.md` stays byte-identical.

Decomposition rules:

- Each child spec created by option 2 receives `group: <group>` and `parent_context: context/<umbrella>.md` in its `requirements.md` frontmatter.
- The registry has a single writer until S4 — the orchestrator, via `mb-idea.sh "[SPEC:<group>] <child-topic>"`. Child agents return only structured proposals.
- On a **partial failure** after some children are created, the created children stay registered as `status: draft` and the unwritten ones are named in a **loud report** — never silently dropped.
- An **orphaned** `tasks.candidate.md` left by a previous run is overwritten by Step 4 regeneration and is never published as-is.

## Status state machine (C7, draft → ready)

Publication in `specs/` ≠ acceptance. Neither the helper nor the orchestrator calls a draft "accepted" until it has passed C8 and cleared review.

- Every new/regenerated triple is published with `requirements.md: status: draft`.
- `status` becomes `ready` **only** after `mb-sdd-self-check.sh` exit 0 (C8=pass) **and** one of: review disabled (`sdd.spec_review.enabled=false`); review returned **APPROVED** (`mb-sdd-review-result.sh record` exit 0); or an explicit human/orchestrator decision to accept on **SKIPPED** or on dismissed issues, recorded through the same single writer as its own JSONL line:

```bash
bash scripts/mb-sdd-review-result.sh decide --topic <topic> --attempt <n> --input - --mb <bank> <<'IN'
{"kind":"decision","decision":"accept","basis":"skipped","rationale":"<why this is acceptable>","decided_by":"<who>"}
IN
```

  `decision` is `accept`|`reject`, `basis` is `skipped`|`dismissed_issues`, and both `rationale` and `decided_by` must be non-empty — an unexplained accept is exactly what the audit trail exists to prevent. Exit 0 = accepted, 1 = rejected, 2 = malformed / `no_review` / basis-versus-verdict mismatch / `path_escape`. Never hand-append this line, and never fake an `APPROVED` review to express a human decision: those are different facts and the log is append-only, so the lie is permanent. Like `record`, the actor is CLAIMED, not verified.

  **`kind: "decision"`, never `status: "decided"`.** The journal holds more than one kind of record, and it has exactly one discrimination rule: **a record with no `kind` key is a review verdict; every non-review record carries `kind`** (`decision` here, `judge` and `override` from `/mb work`'s spec gate). "The last valid line" is therefore only a definition once the kind is named — the current verdict is the last valid line **without** `kind`, the current decision the last with `kind: "decision"`, and a record of one kind never answers for the state of another.

  **A decision needs a review to be about.** `basis: "skipped"` is only valid when the current verdict is `status: "skipped"`, and `basis: "dismissed_issues"` only when it is `CHANGES_REQUESTED` (an APPROVED review has nothing to dismiss). With no verdict in the journal at all the helper refuses — stderr `no_review`, exit 2, nothing written: "accept, because the review was skipped" over an empty journal is a gate bypass wearing an audit trail's clothes, not a decision.
- A C8 failure (`mb-sdd-self-check.sh` exit ≠ 0) **or** **CHANGES_REQUESTED** (record exit 1) keeps `status: draft`. A plain **SKIPPED** without an explicit decision is also draft — nothing becomes ready silently.
- Fixes after CHANGES_REQUESTED run the whole cycle again, in the Step 7-9 order: new candidate → C3 gate → staged C8 on `<bank>/tmp/sdd/<topic>/` → review → atomic promotion. Promotion is the LAST step: an accepted `specs/<topic>/tasks.md` is never replaced by a re-generated candidate that has not yet passed C8 and review (REQ-053 byte-identity). No partial edits to an accepted file.

## Scaffold boundary (C7)

The raw writer stays byte-identical and scaffold-only for direct calls:

```bash
bash scripts/mb-sdd.sh <topic> [--force] [mb_path]
```

`--scaffold-only` on `/mb sdd` is an alias that selects this same writer (its stdout and exit codes do not change). `/mb sdd` without `--scaffold-only` does NOT call the scaffold writer before the D-35 gate is cleared.

## tasks.md format — executable task blocks

Generated `tasks.md` uses `<!-- mb-task:N -->` markers so `mb_work_items.py` (and `/mb work <topic>`) parse tasks as structured work items. Copy the exact v2 block shape (with `**Eval:**` anchor, `**Scope:**`, `**Budget:**`) from `references/templates.md`.

## Validate & migrate

After editing `tasks.md`, validate the triple:

```bash
bash scripts/mb-spec-validate.sh <topic>
# stricter, when the spec carries gated SHALL/MUST requirements:
bash scripts/mb-spec-validate.sh --require-scenarios <topic>
```

To upgrade a legacy `tasks.md` (old `## N. ...` headings without markers):

```bash
bash scripts/mb-spec-tasks-migrate.sh <topic>            # dry-run
bash scripts/mb-spec-tasks-migrate.sh <topic> --apply    # writes a backup, idempotent
```

## Out of scope

- Does not decide REQ→task coverage completeness — that's `/mb verify`'s job (or the `/mb work` review-loop).
- Does not accept a spec on the strength of a `specs/` file alone — acceptance requires the C8 battery and the status state machine above.

## Related

- `/mb discuss <topic>` — produces the EARS-validated transcript/context that feeds `requirements.md`.
- `/mb plan <type> <topic> --sdd` — strict mode, refuses without an EARS-valid context.
- `/mb traceability-gen` — regenerate `traceability.md` after edits to `specs/*/requirements.md`.
- `bash scripts/mb-req-next-id.sh --spec <topic>` — emit the next per-spec-local REQ-NNN.
- `bash scripts/mb-ears-validate.sh <file>|-` — verify REQ lines.
