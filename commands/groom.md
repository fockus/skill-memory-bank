---
description: Critical grooming session for any task or idea — challenge necessity and approach, cover white spots, record decisions into the existing bank structures. No spec required.
allowed-tools: [Bash, Read, Write, AskUserQuestion]
---

# /mb groom <topic>

Groom a task with the agent **before** (or during, or after) implementation. Unlike `/mb discuss`, the goal is NOT to produce a spec — it is to cover the white spots: the agent approaches the requirements critically, challenges the user on whether the thing should be done at all and how exactly, proposes its own solutions, gives advice, and asks follow-up questions.

Usable at **any stage**: a raw idea, a task that already has a spec, a decision worth revisiting, or any open question. The resulting context and decisions then feed spec planning (`/mb sdd`) or change already-accepted decisions.

## Difference from /mb discuss

| | `/mb discuss` | `/mb groom` |
|---|---|---|
| Goal | EARS-validated requirements → `context/<topic>.md`, `status: ready` for `/mb sdd`/`/mb plan` | Cover white spots, challenge the task, record decisions |
| Output | Requirements document | Dialogue summary + decisions routed into agreements/backlog |
| EARS enforcement | Yes | No |
| Fixed phases | 5 phases + size triage + transcript contracts | Free-form, driven by white spots |

Alias note: `/mb ask_me` is an alias for `/mb discuss`, not for groom.

## Workflow

### Pre-flight

1. Resolve `MB_PATH = .memory-bank/`. Refuse if missing (suggest `/mb init`).
2. `GROOM_FILE = $MB_PATH/context/<topic>-groom.md` (same folder as `/mb discuss` output).
3. **Read existing artifacts first** — groom against reality, not from scratch: `context/<topic>.md`, `specs/<topic>/`, matching `plans/*.md`, `agreements.md`, `backlog.md` entries mentioning the topic (best-effort, skip missing).

### Research (before the first question)

Same evidence discipline as `/mb discuss` Phase 0, lighter: codebase recon (code graph / `mb-semantic-search.py` / grep, cite `file:line`), prior decisions (`/mb recall <topic>`, `agreements.md`, `notes/`). Recommendations must cite evidence; a recommendation without a citation is a guess — say so.

### Grooming dialogue

Reuse the **grilling rules** from `commands/discuss.md` (recommend-first, one question per turn, concrete scenarios, surface contradictions with code, decision ledger), plus the grooming-specific stance:

- **Challenge necessity.** "Do we need this at all?" — when evidence supports it, propose do-nothing or a radically simpler alternative before discussing how.
- **Challenge the approach.** Offer your own solution options with trade-offs; disagree with the user's proposal when the code or prior decisions argue against it.
- **Advise.** Risks, sequencing, cheaper paths, what to defer.
- **No fixed phases, no EARS.** Follow the white spots by dependency until none remain or the user stops.

### Finalize

1. Write the summary to `context/<topic>-groom.md` — frontmatter (`type: groom`, date, `related:` links to spec/context if any) + sections: **Context & goal / Discussion summary / Decisions / Rejected alternatives / Open questions / Next steps**. Re-grooming the same topic later appends a new dated section (append, never rewrite old ones).
2. **Route accepted decisions into the existing bank structures** (only explicitly confirmed ones):
   - project/architecture decision confirmed by the user → `bash scripts/mb-agree.sh add "<statement>"` → announce `→ AGR-NNN записано`; a changed prior decision → `add "<new>" --supersedes N`;
   - architecture decision that needs recorded rationale → `bash scripts/mb-adr.sh "<title>"` (backlog `## ADR` section);
   - new ideas that surfaced → `bash scripts/mb-idea.sh "<title>" [HIGH|MED|LOW]` (backlog `## Ideas`);
   - unconfirmed hypotheses → `bash scripts/mb-agree.sh question "<text>"` — never recorded as decisions.
3. **Propose next steps** and let the user pick: create a spec (`/mb sdd <topic>` or `/mb discuss` first), create a plan (`/mb plan`), amend an existing spec/plan, or stop here — the groom file is now planning context.

## Out of scope

- Does not create a spec or plan; does not edit `roadmap.md`/`status.md` directly.
- Does not require or validate EARS.

## Exit conditions

- Success: `context/<topic>-groom.md` written, confirmed decisions routed (AGR/ADR/I-NNN), next steps proposed.
- Cancel mid-dialogue: write what was covered so far with `status: draft` in frontmatter; a later `/mb groom <topic>` resumes by appending.
