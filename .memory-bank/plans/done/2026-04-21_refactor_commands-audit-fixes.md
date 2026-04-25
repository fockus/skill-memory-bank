# Plan: refactor — commands-audit-fixes

## Context

**Problem:** `commands/` audit surfaced 7 systemic issues (broken frontmatter in 10/18 files, duplicates `/plan`↔`/mb plan` etc., stack-hardcoding, missing safety gates, `codebase/` integration gap, weak $ARGUMENTS handling, path conflict in `/adr`) and per-command issues. User decision: non-`/mb` commands become primary, `/mb plan`/`/mb start`/`/mb done` become aliases that dispatch to them. Rest of review items: execute all actionable P0/P1/P2.

**Expected result:**
- All 17 command files (except `mb.md` which has custom router) have valid YAML frontmatter.
- `/plan`, `/start`, `/done` are the primary commands. `/mb plan|start|done` become thin aliases.
- `/adr` writes to `backlog.md` per RULES.md, not to `plans/`. Monotonic `ADR-NNN` numbering.
- Stack-specific commands detect stack via `mb-metrics.sh` with explicit `stack=unknown` fallback.
- Safety gates: `/commit` runs `mb-drift.sh` + `git diff --check`; `/pr` checks branch != main + preview; `/db-migration` explicit destructive-op confirm.
- Empty `$ARGUMENTS` handled in `/refactor`, `/contract`, `/adr`, `/api-contract`, `/db-migration`.
- `/catchup`, `/start`, `/review`, `/pr` read `.memory-bank/codebase/*.md` summaries.
- `doc.md`'s `agent:` + `context:` keys verified or removed.
- `references/command-template.md` documents canonical format.
- CHANGELOG entry + `mb-drift.sh` green.

**Related files:**
- 17 command files in `commands/`
- `references/command-template.md` (NEW)
- `CHANGELOG.md`

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Create `references/command-template.md`

**What to do:**
- Write canonical command file structure: YAML frontmatter keys (`description`, `allowed-tools`, `argument-hint`), body structure, memory-bank integration snippet.
- Include 2 examples: minimal (≤20 lines) and complex (with `mb-metrics.sh` stack detection).

**Testing:**
- File exists; `wc -l` < 200 (KISS).
- `grep -c '^---$'` ≥ 4 (2 examples × 2 fences each).

**DoD:**
- [ ] `references/command-template.md` exists with frontmatter spec + 2 examples
- [ ] No `TODO`/`FIXME`
- [ ] Referenced from `SKILL.md` References section

**Code rules:** KISS, YAGNI.

---

<!-- mb-stage:2 -->
### Stage 2: Fix frontmatter in 10 files

**Files:** `adr.md`, `catchup.md`, `changelog.md`, `commit.md`, `contract.md`, `done.md`, `roadmap.md`, `refactor.md`, `start.md`, `test.md`.

**What to do:**
- Replace broken `# commentary` + `---` + `## description:` pattern with canonical YAML frontmatter.
- `start.md` has no frontmatter — add one.
- `doc.md` with non-standard keys → deferred to Stage 9.

**Testing:**
- `grep -c '^---$'` on each of the 10 files == 2.
- `head -1` starts with `---` on all 10.

**DoD:**
- [ ] All 10 files begin with `^---$` on line 1
- [ ] Each has exactly 2 `---` fences
- [ ] No `# ~/.claude/commands/...` artifact at file top
- [ ] Body content preserved (diff = frontmatter-only)
- [ ] `argument-hint` added where command takes `$ARGUMENTS`

**Code rules:** DRY — same frontmatter shape.

---

<!-- mb-stage:3 -->
### Stage 3: Alias resolution — `/plan`, `/start`, `/done` primary

**What to do:**
- **`commands/roadmap.md`** — absorb logic from `### plan` of `mb.md`: `mb-plan.sh` scaffold + `<!-- mb-stage:N -->` markers + `mb-plan-sync.sh` after fill.
- **`commands/start.md`** — absorb logic from `### start` / `### context` of `mb.md`: `mb-context.sh` + STATUS/plan/checklist/RESEARCH read + active plan in full + `codebase/` bootstrap suggestion if empty.
- **`commands/done.md`** — absorb logic from `### done` of `mb.md`: MB Manager subagent invocation with `action: actualize + action: note` + `.session-lock` touch.
- **`commands/mb.md`** — replace body of `### plan` / `### start` / `### done` / `### context` sections with one-liner pointers to primary commands. Keep router table entries working.

**Testing:**
- `grep -c 'mb-plan.sh' commands/roadmap.md` ≥ 1
- `grep -c 'mb-context.sh' commands/start.md` ≥ 1
- `grep -c 'MB Manager\|actualize\|session-lock' commands/done.md` ≥ 2
- `mb.md` `### plan` section body size drops by ≥50%.

**DoD:**
- [ ] `roadmap.md` has full planning flow with mb-plan.sh + mb-plan-sync.sh
- [ ] `start.md` has full context-loading + `codebase/` bootstrap
- [ ] `done.md` has MB Manager orchestration + `.session-lock`
- [ ] `mb.md` sections reduced to alias pointers (≤10 lines each)
- [ ] No duplicate logic between `mb.md` and the 3 primaries
- [ ] Aliases explicitly documented in `mb.md`

**Code rules:** DRY, backwards-compatible.

---

<!-- mb-stage:4 -->
### Stage 4: Fix `/adr` path conflict

**What to do:**
- Rewrite `commands/adr.md`: read `.memory-bank/backlog.md`, find next `ADR-NNN` (max+1), prompt user, append to `## Architectural decisions (ADR)` section using RULES.md format.
- Optional cross-link: create a note in `notes/`.
- Empty `$ARGUMENTS` → ask user.

**Testing:**
- `grep -c 'backlog.md' commands/adr.md` ≥ 2
- `grep -c 'plans/' commands/adr.md` == 0
- `grep -c 'ADR-' commands/adr.md` ≥ 2

**DoD:**
- [ ] Writes exclusively to `backlog.md` (no `plans/`)
- [ ] Monotonic `ADR-NNN` numbering documented
- [ ] Empty `$ARGUMENTS` → prompt
- [ ] Format matches `references/templates.md` ADR template

**Code rules:** fixes direct RULES.md violation.

---

<!-- mb-stage:5 -->
### Stage 5: Stack-generic refactor via `mb-metrics.sh`

**Files:** `security-review.md`, `db-migration.md`, `observability.md`, `api-contract.md`, `test.md`.

**What to do:**
- First step: `bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh` → `stack`, `test_cmd`, `lint_cmd`, `src_count`.
- `stack=unknown` → warn + ask user.
- **`security-review.md`**: add Rust (`cargo audit`), Java (`trivy fs`, `dependency-check`), Ruby (`brakeman`, `bundle-audit`); recommend `trufflehog`/`gitleaks` with grep fallback.
- **`db-migration.md`**: add Diesel, Flyway, Liquibase, Sequelize/Knex, SQLx. Non-listed → ask.
- **`observability.md`**: add Rust (`tracing`), Java (`Micrometer`+OTEL), .NET.
- **`api-contract.md`**: broaden handler detection (Express, FastAPI, Spring, ASP.NET, Go). Mention Schemathesis + Pact.
- **`test.md`**: use `test_cmd` from metrics instead of hardcoded list.

**Testing:**
- `grep -c 'mb-metrics.sh' commands/*.md` on 5 files == 5
- Each has `stack=unknown` fallback
- `security-review.md` covers 6 stacks (Go/Python/Node/Rust/Java/Ruby)
- `db-migration.md` ≥ 7 tools
- `observability.md` covers 6 stacks

**DoD:**
- [ ] All 5 commands open with `mb-metrics.sh`
- [ ] Each has unknown-fallback
- [ ] Stack coverage above met

**Code rules:** DRY (single stack-detect source).

---

<!-- mb-stage:6 -->
### Stage 6: Safety gates in `/commit`, `/pr`, `/db-migration`

**What to do:**
- **`commit.md`** pre-step: `mb-drift.sh` + `git diff --check`; final `y/N` confirm before `git commit`.
- **`pr.md`** pre-step: `git rev-parse --abbrev-ref HEAD` (not main); `git rev-list origin/main..HEAD` check; preview + confirm before `gh pr create`.
- **`db-migration.md`**: destructive ops (`DROP TABLE`, `DROP COLUMN`, `TRUNCATE`, `DELETE FROM` w/o WHERE) require `y` confirm before file write.

**Testing:**
- `grep -c 'mb-drift.sh\|git diff --check\|confirm' commands/commit.md` ≥ 3
- `grep -c 'abbrev-ref\|preview\|confirm' commands/pr.md` ≥ 3
- `grep -c 'DROP\|TRUNCATE' commands/db-migration.md` ≥ 2 with confirm

**DoD:**
- [ ] `/commit` has `mb-drift.sh` + `git diff --check` + final confirm
- [ ] `/pr` has branch check + preview + confirm
- [ ] `/db-migration` has explicit destructive-op confirm before write
- [ ] All confirmations default to No

**Code rules:** Fail-safe defaults.

---

<!-- mb-stage:7 -->
### Stage 7: Empty `$ARGUMENTS` guards

**Files:** `refactor.md`, `contract.md`, `adr.md`, `api-contract.md`, `db-migration.md`.

**What to do:**
- Add first step: «if `$ARGUMENTS` empty, stop and ask user».

**Testing:**
- `grep -c 'ARGUMENTS.*empty\|ARGUMENTS.*ask\|if.*ARGUMENTS' commands/{refactor,contract,adr,api-contract,db-migration}.md` ≥ 1 per file

**DoD:**
- [ ] All 5 check empty upfront
- [ ] Explicit user-facing prompt text

**Code rules:** Fail-Fast per RULES.md.

---

<!-- mb-stage:8 -->
### Stage 8: `codebase/` integration in context-reading commands

**Files:** `catchup.md`, `review.md`, `pr.md` (`start.md` already via Stage 3).

**What to do:**
- Read `.memory-bank/codebase/*.md` — one-line summary per doc via `mb-context.sh` or `cat`.
- `review.md` uses `ARCHITECTURE.md` + `CONCERNS.md` for architectural findings.
- `pr.md` appends codebase summary to PR body for reviewer context.

**Testing:**
- `grep -c 'codebase/' commands/{catchup,review,pr}.md` ≥ 1 per file

**DoD:**
- [ ] `catchup.md` reads codebase summaries
- [ ] `review.md` uses ARCHITECTURE + CONCERNS
- [ ] `pr.md` includes codebase context in body

**Code rules:** Uses existing `mb-context.sh` integration.

---

<!-- mb-stage:9 -->
### Stage 9: `doc.md` non-standard keys audit

**What to do:**
- Check whether `agent:` and `context:` are valid Claude Code frontmatter keys (grep ecosystem commands, CC docs).
- If valid → document in `references/command-template.md`, keep with fixed surrounding YAML.
- If unknown → remove, replace with body instruction.

**Testing:**
- If kept: template documents the keys
- If removed: `grep 'agent:\|context:' commands/doc.md` == 0

**DoD:**
- [ ] Decision documented
- [ ] No broken frontmatter

**Code rules:** YAGNI.

---

<!-- mb-stage:10 -->
### Stage 10: Verification + CHANGELOG

**What to do:**
- `bash scripts/mb-drift.sh .` → `drift_warnings=0`
- Frontmatter loop: `for f in commands/*.md; do head -1 "$f" | grep -q '^---' || echo "BROKEN: $f"; done` — 0 BROKEN (except maybe `mb.md` which has custom structure)
- Append CHANGELOG entry under `## [Unreleased]` listing all changes.

**Testing:**
- `mb-drift.sh` → 0 warnings
- Frontmatter loop → 0 BROKEN
- CHANGELOG has entry

**DoD:**
- [ ] `mb-drift.sh` green
- [ ] All command files (except `mb.md`) start with `---`
- [ ] CHANGELOG entry added

**Code rules:** Verification-first.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Alias resolution breaks `/mb plan\|start\|done` for existing users | M | `mb.md` keeps sections as pointers; mental walkthrough each alias = same outcome as primary |
| Frontmatter fix introduces YAML parsing error | L | Validate each: `head -1` + fence count; manual scan |
| `mb-metrics.sh` returns `stack=unknown` too often → friction | M | Every stack-generic command has `unknown` branch; fallback = ask, not crash |
| `/adr` migration orphans existing ADR files in `plans/` | L | Document in CHANGELOG; old files remain; new ones go to `backlog.md` |
| `doc.md` `agent: explorer` is actually functional CC feature | M | Stage 9 researches first; remove only if non-functional |
| Scope creep: 10 stages, many files | H | Strict stage-at-a-time with TaskList; skip new-command P3 items this pass |

## Gate

All 17 command files (except `mb.md`) have valid YAML frontmatter. `/plan`, `/start`, `/done` are primary with sophisticated logic; `/mb plan|start|done` are explicit aliases. `/adr` writes to `backlog.md`. 5 commands use `mb-metrics.sh` with unknown-fallback. `/commit`, `/pr`, `/db-migration` have safety gates. 5 commands validate empty `$ARGUMENTS`. 4 commands read `codebase/*.md`. `doc.md` frontmatter valid, dead keys documented or removed. `references/command-template.md` exists. `CHANGELOG.md` entry added. `mb-drift.sh` green. `/mb plan` still works end-to-end.
