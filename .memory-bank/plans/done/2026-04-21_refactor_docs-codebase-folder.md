# Plan: refactor — docs-codebase-folder

## Context

**Problem:** The `.memory-bank/codebase/` directory (populated by `/mb map` and `/mb graph`, consumed by `mb-context.sh`) is not documented in the user-facing structure and workflow references. As a result:
- `rules/CLAUDE-GLOBAL.md` (installed as `~/.claude/CLAUDE.md` managed block) and `rules/RULES.md` (installed as `~/.claude/RULES.md`) do not list `codebase/` in the `.memory-bank/` structure table.
- `references/structure.md` has no section at all for `codebase/`.
- `references/workflow.md` has no trigger that tells the agent when to run `/mb map` or how to handle an empty `codebase/` directory at session start.
- `references/claude-md-template.md` — the template used by `/mb init --full` to generate the per-project `CLAUDE.md` — also omits `codebase/`.
- `commands/mb.md` `### init` creates the empty directory but never prompts the user to populate it via `mb-codebase-mapper` subagent.

**Expected result:**
- Every structural / workflow reference mentions `codebase/` with the same consistent description.
- The global install (`~/.claude/CLAUDE.md` + `~/.claude/RULES.md`) after the next upgrade / fresh install includes `codebase/` in its structure tables.
- A new project initialized via `/mb init --full` gets a generated `CLAUDE.md` that documents `codebase/`, and the init flow proactively offers to run `mb-codebase-mapper` so the folder is populated from day one.
- Session start (`/mb start`) explicitly checks whether `codebase/` is empty and, if it is, suggests `/mb map`.

**Related files:**
- `rules/CLAUDE-GLOBAL.md`
- `rules/RULES.md`
- `references/structure.md`
- `references/workflow.md`
- `references/templates.md`
- `references/claude-md-template.md`
- `commands/mb.md` (`### init` section)
- `CHANGELOG.md`
- `scripts/mb-context.sh` — read-only reference (already integrated, informs wording)
- `agents/mb-codebase-mapper.md` — read-only reference (templates/focus values)

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Update reference documents (source of truth)

**What to do:**
- `references/structure.md` — add a new subsection `### codebase/ — Codebase map` after the `### reports/` block. List the six artifacts (`STACK.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `CONCERNS.md`, `graph.json`, `god-nodes.md`). Describe the two generators (`/mb map [focus]`, `/mb graph [--apply]`) and the consumer (`scripts/mb-context.sh` → integrated into `/mb context` and `/mb context --deep`). Mention the ≤70-line template rule.
- `references/workflow.md` — in `## Session start`, add a bootstrap rule: «if `.memory-bank/codebase/` is missing or contains no `*.md` files, suggest `/mb map all` (subagent `mb-codebase-mapper`, sonnet) before deep-reading core files». In `### When to update each file`, add a row: «Stack / major dependency changed → re-run `/mb map stack`». In `### When to create files`, add an entry: «`codebase/` — after `/mb init` or whenever architecture / conventions / concerns have drifted».
- `references/templates.md` — in the `## New Memory Bank initialization (/mb init)` tree, add an inline comment next to `codebase/` explaining that it is populated by `mb-codebase-mapper` and consumed by `/mb context`.

**Testing (TDD — tests BEFORE implementation):**
- No runtime code changes — treat review checks as "tests":
  - `grep -c "codebase/" references/structure.md` ≥ 4 (section heading + 4 artifacts listed)
  - `grep -c "codebase/" references/workflow.md` ≥ 3 (session start + when-to-update + when-to-create)
  - `grep -c "codebase" references/templates.md` ≥ 2 (tree comment + explanation)
  - Manual read-through: a new user unfamiliar with `codebase/` should, after reading these three files, know (a) what lives in `codebase/`, (b) who writes it, (c) who reads it, (d) when to re-run it.

**DoD (Definition of Done):**
- [ ] `references/structure.md` has a new `### codebase/` subsection placed after `### reports/`, listing 6 files with purpose + generator + consumer
- [ ] `references/workflow.md` contains an explicit bootstrap rule for empty `codebase/` in `## Session start`
- [ ] `references/workflow.md` mentions `/mb map` as the trigger for stack-change / refactor events
- [ ] `references/templates.md` tree comment for `codebase/` is present
- [ ] All three files still render as valid GitHub-flavored Markdown (no unbalanced code fences)
- [ ] No other sections were reorganized or semantically changed (diff review)

**Code rules:** SOLID, DRY, KISS, YAGNI — wording must be consistent across the three files; do not duplicate the template content inside the references (link to `agents/mb-codebase-mapper.md` instead).

---

<!-- mb-stage:2 -->
### Stage 2: Update `~/.claude/`-bound rules (`rules/CLAUDE-GLOBAL.md`, `rules/RULES.md`)

**What to do:**
- `rules/CLAUDE-GLOBAL.md`:
  - Add a row to the «Detailed records (read on demand)» table for `codebase/` (Purpose: "Codebase map: stack, architecture, conventions, concerns"; When to update: "After `/mb init` or `/mb map`, or when the stack / architecture changes").
  - In the `### Workflow (short)` block, append one sentence to the `**Start:**` line: «If `codebase/` is empty on start, suggest `/mb map` (subagent `mb-codebase-mapper`, sonnet)».
- `rules/RULES.md`:
  - Add the same row to the `.memory-bank/` Structure table (matching `CLAUDE-GLOBAL.md` wording exactly).
  - In `### /mb start — start of session`, add step 5: «If `.memory-bank/codebase/` does not exist or contains no `*.md`, suggest running `/mb map` before continuing».

**Testing (TDD — pre-implementation checks):**
- `grep -n "codebase/" rules/CLAUDE-GLOBAL.md` must hit both the table and the workflow block (≥2 matches)
- `grep -n "codebase/" rules/RULES.md` must hit both the structure table and the session-start section (≥2 matches)
- Cross-consistency check: the row wording for `codebase/` is byte-identical between `CLAUDE-GLOBAL.md` and `RULES.md` (verify with `diff <(grep 'codebase/' rules/CLAUDE-GLOBAL.md) <(grep 'codebase/' rules/RULES.md)`)

**DoD (Definition of Done):**
- [ ] `rules/CLAUDE-GLOBAL.md` contains a new `codebase/` row in the «Detailed records» table
- [ ] `rules/CLAUDE-GLOBAL.md` `### Workflow (short)` references `/mb map` bootstrap
- [ ] `rules/RULES.md` contains the matching row in its `.memory-bank/` Structure table (same wording)
- [ ] `rules/RULES.md` `### /mb start` adds the empty-codebase step
- [ ] Local dry-run: copy `rules/CLAUDE-GLOBAL.md` + `rules/RULES.md` to `/tmp/mb-dryrun/` and confirm `grep codebase/ /tmp/mb-dryrun/*.md` shows the new lines (simulating what `install.sh` will write)
- [ ] No unrelated edits to the rest of the rules (diff-scoped)

**Code rules:** wording must be identical between the two files; both files are installed — drift would confuse users.

---

<!-- mb-stage:3 -->
### Stage 3: Update `/mb init` flow and generated `CLAUDE.md` template

**What to do:**
- `commands/mb.md` `### init [--minimal|--full]`:
  - After Step 1 (create structure), insert an optional Step 1.5: «Offer to populate `codebase/` by running `mb-codebase-mapper` subagent with `focus: all`. Default answer: skip (user can do it later via `/mb map`). Only asked in `--full` mode».
  - In Step 6 (Summary), add one line to the «Suggest the next step» list: «`/mb map` — populate `.memory-bank/codebase/` with STACK / ARCHITECTURE / CONVENTIONS / CONCERNS snapshots».
- `references/claude-md-template.md`:
  - Add a row to the `.memory-bank/` structure table for `codebase/` (Purpose: «Codebase map: stack, architecture, conventions, concerns»; When to update: «After `/mb map`»).

**Testing (TDD — pre-implementation checks):**
- `grep -n "mb-codebase-mapper\|/mb map" commands/mb.md` inside the `### init` section — must have ≥1 match in Step 1.5 and ≥1 match in Step 6 after the edit
- `grep -c "codebase/" references/claude-md-template.md` ≥ 1 after the edit
- Diff review: ensure the Step 1.5 wording does not force the mapper — the default must remain «skip», matching `/mb init` philosophy (no surprises, no heavy operations by default)

**DoD (Definition of Done):**
- [ ] `commands/mb.md` `### init` contains Step 1.5 describing the optional mapper invocation with default=skip
- [ ] `commands/mb.md` Step 6 Summary includes a `/mb map` hint
- [ ] `references/claude-md-template.md` table row for `codebase/` is present
- [ ] The rendered generated `CLAUDE.md` (spot-checked mentally) now documents `codebase/` for every new project
- [ ] No behavioural regression in `--minimal` init (Step 1.5 only fires in `--full` path)

**Code rules:** KISS — Step 1.5 must be one-question prompt, not a multi-step flow. YAGNI — do not add `--skip-map` / `--map-focus` flags; keep the existing `/mb map [focus]` surface.

---

<!-- mb-stage:4 -->
### Stage 4: Verification, CHANGELOG, and cross-file consistency

**What to do:**
- Final read-through of all 7 changed files (or 8 including CHANGELOG) to confirm consistent terminology: «Codebase map», «populated by `/mb map` (subagent `mb-codebase-mapper`)», «consumed by `mb-context.sh` → `/mb context`». No drift between files.
- `grep -rn "codebase/" rules/ references/ commands/mb.md | wc -l` should be ≥ baseline + 10 new references.
- Add a `CHANGELOG.md` entry under the next unreleased / current version bump section describing this doc improvement (no version bump — purely docs).
- Manual smoke test (recorded in the note, not automated): create an empty `/tmp/mb-test/.memory-bank/` directory structure, open `commands/mb.md` and walk through `### init` mentally as the agent would — confirm that (a) the flow now mentions `codebase/`, (b) the mapper option is surfaced.

**Testing (TDD — verification suite):**
- `bash scripts/mb-drift.sh .` — should still return `drift_warnings=0` (docs changes must not break internal consistency checks)
- `grep -l "codebase/" rules/*.md references/*.md | wc -l` ≥ 5 (every key doc touches the term)
- CHANGELOG.md diff inspection — one new bullet under unreleased / pending section; no accidental edits elsewhere

**DoD (Definition of Done):**
- [ ] All 7 primary files modified (2 rules + 3 references + `commands/mb.md` + `claude-md-template.md`)
- [ ] CHANGELOG.md has a bullet under the current unreleased section: «Docs: surface `.memory-bank/codebase/` in structure refs, session workflow, and `/mb init` flow»
- [ ] `bash scripts/mb-drift.sh .` exits 0 (`drift_warnings=0`)
- [ ] `grep -c "codebase/" rules/CLAUDE-GLOBAL.md rules/RULES.md references/structure.md references/workflow.md references/templates.md references/claude-md-template.md commands/mb.md` aggregated increase ≥ 10 lines
- [ ] Terminology is consistent: exactly the same phrase is used to describe `codebase/` across CLAUDE-GLOBAL.md and RULES.md (duplication is intentional — they are the two installed surfaces)

**Code rules:** Verification stage only — no further content changes except CHANGELOG.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Bootstrap prompt («suggest `/mb map` if codebase/ empty») feels spammy / forces mapper on every `/mb start` | M | Make it a one-shot suggestion; the default action is «skip». Do not auto-invoke mapper from session start |
| Wording drift between `CLAUDE-GLOBAL.md` and `RULES.md` (both describe the same row) | M | Stage 2 DoD requires a `diff` check on extracted `codebase/` rows; wording must be byte-identical |
| Users with stale `~/.claude/CLAUDE.md` (managed block not re-applied) will not see the new rows until next `/mb upgrade` | L | Explicitly mention the upgrade requirement in the CHANGELOG entry |
| `/mb init --full` Step 1.5 prompt may be skipped by non-interactive hosts and block init | L | Make it a yes/no question with an explicit «defaults to skip» contract; never block init on mapper failure |
| `/mb map` itself fails (no source files, non-standard layout) | L | `mb-codebase-mapper` already handles `stack=unknown` gracefully — no new failure modes introduced by docs alone |

## Gate (plan success criterion)

A fresh developer running `/mb init --full` on a new project receives a `CLAUDE.md` that documents `codebase/`, and is prompted (default=skip) to run `mb-codebase-mapper`. On a subsequent `/mb start` with an empty `codebase/`, the agent will surface a suggestion to run `/mb map`. Running `grep -rn "codebase/" rules/ references/ commands/mb.md` shows the term in every primary structural / workflow document. `bash scripts/mb-drift.sh .` remains green. No code changes, only documentation.
