# Tasks: agreements

> Numbered, checkbox-tracked work items. Each task references the
> REQ-IDs it satisfies via the Covers field. Execute via `/mb work agreements`.
> Order is dependency-driven: 1 → 2 → 3 (parallel with 4) → 4 → 5 → 6 → 7 → 8.

<!-- mb-task:1 -->
## Task 1: Registry core — template, `add`, `list`, lazy init

**Covers:** REQ-001, REQ-003
**Role:** developer

**What to do:**
- Create `templates/agreements.md` (sections: `## Active`, `## Deferred`, `## Open Questions`, `## Archive`) + `templates/locales/ru/` copy.
- Create `scripts/mb-agree.sh`: bank resolution via `_lib.sh::mb_resolve_path`, subcommands `add "<statement>" [--adr NNN] [--source S]` and `list [--all]`.
- Lazy init: `add` on a bank without `agreements.md` copies the template first (REQ-003).
- ID issuance: next `AGR-NNN` = max across ALL sections + 1, zero-padded; entry line per design.md grammar; default source `user-confirmed`; date from `date +%F`.
- Single-line guard: statement containing a newline → exit 2 with usage.

**Testing (TDD — tests BEFORE implementation):**
- New `tests/bats/test_mb_agree.bats`: lazy init creates all 4 sections; `add` writes `- AGR-001 (YYYY-MM-DD, user-confirmed): …` under Active; second `add` issues `AGR-002`; `--adr 12` appends `→ ADR-012`; multiline statement exits 2; `list` prints Active only, `list --all` everything; IDs count Archive entries too (max across sections).

**DoD:**
- [ ] `mb-agree.sh add`/`list` pass all new bats tests on default bash and bash 3.2
- [ ] tests pass
- [ ] lint clean (shellcheck)

<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Lifecycle mutations — `supersede`, `defer`, `reject`

**Covers:** REQ-004, REQ-013
**Role:** developer

**What to do:**
- `add --supersedes N`: in one critical section create the new active entry, rewrite `AGR-N` line with `[superseded by AGR-NEW]`, move it to `## Archive`.
- `defer N` / `reject N`: move an active entry to `## Deferred` / `## Archive` with the status marker.
- Validation: target must exist AND be in `## Active`; otherwise exit 1 with `AGR-N is not active`, zero writes (REQ-013).
- All writes temp-file + `mv` (atomic).

**Testing (TDD — tests BEFORE implementation):**
- Bats: supersede moves old entry to Archive with back-link and new entry is active (scenario 2); supersede of superseded/missing ID exits 1 and leaves the file byte-identical (scenario 3); defer/reject move sections correctly; IDs of archived entries are never reissued.

**DoD:**
- [ ] scenarios 2 and 3 from requirements.md pass as bats tests
- [ ] tests pass
- [ ] lint clean

<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Open Questions — `question`, `resolve`

**Covers:** REQ-016
**Role:** developer

**What to do:**
- `question "<text>"`: append `- Q-NNN: <text>` to `## Open Questions` (own monotonic Q-counter).
- `resolve N`: mark/remove question N (strike-through with date), exit 1 if not found.
- Neither subcommand triggers managed-block sync (Open Questions are not injected).

**Testing (TDD — tests BEFORE implementation):**
- Bats: question appends with next Q-ID; resolve closes it; resolve of missing ID exits 1; CLAUDE.md/AGENTS.md mtime/content unchanged by both subcommands.

**DoD:**
- [ ] question/resolve tests green, block untouched by both
- [ ] tests pass
- [ ] lint clean

<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Managed-block sync engine

**Covers:** REQ-005, REQ-006, REQ-007, REQ-012
**Role:** developer

**What to do:**
- `sync` subcommand + auto-invoke after every mutating subcommand (add/supersede/defer/reject).
- Render block per design.md format (`<!-- mb-agreements:start/end -->`, all Active one-liners, pointer line) into project-root `CLAUDE.md` AND `AGENTS.md` — replace between markers only, byte-preserve the rest (NFR-005).
- Both markers absent → append block at EOF; one marker without the other → exit 1 naming file+marker, no write (scenario 9); neither file exists → create `AGENTS.md` with only the block (REQ-006).
- Active count > 25 → prune warning on stderr, full list still rendered (REQ-007).
- Idempotence: repeated `sync` over unchanged registry → byte-identical outputs (NFR-004).

**Testing (TDD — tests BEFORE implementation):**
- Bats: scenarios 1, 5, 6, 9 from requirements.md; foreign content above/below block byte-preserved; coexistence with an adapters' `<!-- memory-bank:start/end -->` block in the same file; sync rebuilds after a manual registry edit (REQ-012).

**DoD:**
- [ ] scenarios 1, 5, 6, 9 pass as bats tests; double-sync byte-identity proven
- [ ] tests pass
- [ ] lint clean

<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Lock and kill-switch

**Covers:** REQ-008, REQ-014
**Role:** developer

**What to do:**
- Wrap every mutating subcommand in `_lib.sh::_lock_acquire`/`_lock_release` on `<bank>/.agreements.lock` (owner-token mkdir lock, same idiom as `mb-work-progress-append.sh`); ID read+write inside the critical section.
- Kill-switch: `MB_AGREEMENTS=off` via env or `.mb-config` line → every subcommand prints an explained no-op (with re-enable hint) and exits 0 without writes (REQ-008). Env wins over `.mb-config`.

**Testing (TDD — tests BEFORE implementation):**
- Bats: two backgrounded parallel `add` produce distinct consecutive IDs and both entries survive (scenario 7); stale-lock timeout exits non-zero without corrupting the file; `MB_AGREEMENTS=off` scenario 4 — no writes to any of the three files, informative stdout.

**DoD:**
- [ ] scenarios 4 and 7 pass as bats tests
- [ ] tests pass
- [ ] lint clean

<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: Rules, docs, and router wiring

**Covers:** REQ-002, REQ-009, REQ-015
**Role:** developer

**What to do:**
- `references/agreements.md` (new): full maintenance protocol — what is/isn't an agreement (with anti-examples: proposals, model hypotheses, implicit assumptions), 4 statuses, visible-announce rule, ADR routing (`rationale → ADR, registry stays compact`), subagents propose but never write.
- `rules/CLAUDE-GLOBAL.md` + `rules/RULES.md`: add the compact trigger (≤5 lines): explicit user decision → `mb-agree.sh add` + `→ AGR-NNN записано` announce; hypotheses → `question`; changes → `--supersedes`; pointer to `references/agreements.md`.
- `commands/agree.md` (new) + router row/section in `commands/mb.md`: `/mb agree <subcommand>` dispatch table with the CLI contract.
- `SKILL.md`: short section registering the feature and the lazy-activation contract.

**Testing (TDD — tests BEFORE implementation):**
- Bats (docs invariants, same style as test_agent_report_delivery.bats): trigger present in both rules files; `commands/mb.md` router row exists; `references/agreements.md` contains the announce format and anti-example section; all files pass the repo terminology guard.

**DoD:**
- [ ] docs-invariant bats tests green; `/mb agree` resolvable from the router
- [ ] tests pass
- [ ] lint clean

<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: Verifier integration — agreement compliance check

**Covers:** REQ-010, REQ-011
**Role:** developer

**What to do:**
- `agents/plan-verifier.md`: add the Agreement Compliance step — if `<bank>/agreements.md` exists, classify every `## Active` entry as satisfied / violated / not-applicable against the plan+diff; render an `## Agreement Compliance` report section; any violated → overall FAIL with the explicit fix-or-supersede choice; no file → skip silently.
- `commands/mb.md` `### verify` section: document the new step and the FAIL semantics.

**Testing (TDD — tests BEFORE implementation):**
- Bats (docs invariants): plan-verifier.md contains the three classifications, the FAIL rule, and the fix-or-supersede wording; verify section in commands/mb.md mentions agreements. (LLM-behavior itself is exercised by scenario 8 during `/mb verify` dogfooding of this very spec.)

**DoD:**
- [ ] plan-verifier prompt contains the compliance step; docs-invariant tests green
- [ ] tests pass
- [ ] lint clean

<!-- /mb-task:7 -->

<!-- mb-task:8 -->
## Task 8: Close-out — validation, regression, changelog

**Covers:** REQ-001, REQ-002, REQ-005, REQ-008, REQ-010
**Role:** qa

**What to do:**
- `bash scripts/mb-spec-validate.sh agreements` — spec triple integrity.
- Full bats suite + shellcheck on all touched shell files; bash 3.2 pass for `mb-agree.sh`.
- Dogfood: run `mb-agree.sh add` for the 8 interview decisions of this feature in THIS repo's bank; verify the managed block lands in CLAUDE.md/AGENTS.md and survives `sync` idempotently.
- CHANGELOG.md entry; `.memory-bank` core files actualized (status/checklist via `/mb done` flow).

**Testing (TDD — tests BEFORE implementation):**
- The full existing suite is the test: zero regressions allowed; new suite `test_mb_agree.bats` fully green on Linux CI matrix.

**DoD:**
- [ ] spec-validate exits 0; full bats suite green locally and in CI
- [ ] dogfood registry live in this repo with the 8 decisions injected
- [ ] CHANGELOG updated

<!-- /mb-task:8 -->
