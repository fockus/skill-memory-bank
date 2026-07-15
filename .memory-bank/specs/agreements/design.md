# Design: agreements

> Architecture, interfaces, and decisions backing requirements.md.
> Interview source: `context/agreements.md` (8 confirmed decisions, 2026-07-15).

## Architecture

```
model notices an explicitly confirmed decision (rules trigger)
        │
        ▼
scripts/mb-agree.sh  ──[_lock_acquire <bank>/.agreements.lock]──┐
        │                                                        │
        ▼                                                        │
<bank>/agreements.md            (single source of truth)        │
  ## Active / ## Deferred / ## Open Questions / ## Archive      │
        │                                                        │
        ▼  (auto-sync after every mutation; also `sync` cmd)     │
managed block in project-root CLAUDE.md + AGENTS.md  ◄──────────┘
  <!-- mb-agreements:start --> … <!-- mb-agreements:end -->
        │
        ▼
every agent session auto-loads the active list (zero extra tooling)

/mb verify (plan-verifier) reads agreements.md → agreement compliance check
```

Components (all inside this repo — the skill bundle):

| Component | File | Responsibility |
|---|---|---|
| CLI | `scripts/mb-agree.sh` (new) | all mutations, ID issuance, lock, block sync |
| Template | `templates/agreements.md` (new) + `templates/locales/ru/…` | lazy-created registry skeleton |
| Rules trigger | `rules/CLAUDE-GLOBAL.md`, `rules/RULES.md` (edit) | when the model must call `/mb agree` |
| Protocol reference | `references/agreements.md` (new) | full maintenance protocol (what is/isn't an agreement, statuses, subagent rules) |
| Router | `commands/mb.md` (edit) + `commands/agree.md` (new) | `/mb agree <subcommand>` dispatch |
| Verifier | `agents/plan-verifier.md` (edit) | agreement compliance step in `/mb verify` |
| Tests | `tests/bats/test_mb_agree.bats` (new) | TDD-first coverage of REQ-001…008, 012–014, 016 |

Dependency direction: CLI depends only on `scripts/_lib.sh` (bank resolution, lock, atomic write). Rules/docs depend on the CLI contract. The verifier depends on the file format, not on the CLI.

## Interfaces

### CLI contract — `mb-agree.sh <subcommand> [args] [mb_path]`

| Subcommand | Args | Effect | Exit |
|---|---|---|---|
| `add "<statement>"` | `[--supersedes N] [--adr NNN] [--source S]` | new active entry (default source `user-confirmed`); with `--supersedes` atomically archives AGR-N | 0; 2 usage; 1 invalid target / damaged file |
| `defer N` / `reject N` | — | move active AGR-N to Deferred / Archive with status | 0; 1 not-active |
| `question "<text>"` | — | append to Open Questions (no block sync) | 0 |
| `resolve N` | — | close open question N | 0; 1 not found |
| `list` | `[--all]` | print Active (default) or the whole registry | 0 |
| `sync` | — | rebuild managed block from file (reconcile hand edits) | 0; 1 damaged block/file |

Global behavior: statements are single-line (embedded newline → exit 2); every mutating subcommand takes the lock, writes via temp-file + `mv`, then re-syncs the managed block; `MB_AGREEMENTS=off` (env or `.mb-config` line) → explained no-op, exit 0, zero writes.

### Registry line grammar (`agreements.md`)

```
- AGR-NNN (YYYY-MM-DD, <source>): <statement> [supersedes AGR-X] [→ ADR-YYY]
- AGR-NNN (YYYY-MM-DD, <source>): <statement> [superseded by AGR-Y]   # Archive
```

Sections: `## Active`, `## Deferred`, `## Open Questions` (`- Q-NNN: <text>`), `## Archive`. Status is derived from section + trailing marker (superseded/rejected). Next ID = max across ALL sections + 1 (never reused).

### Managed block format (CLAUDE.md / AGENTS.md)

```markdown
<!-- mb-agreements:start -->
## Active Agreements
- AGR-001: <statement>
- AGR-002: <statement>

История, superseded и правила ведения → .memory-bank/agreements.md (`/mb agree`)
<!-- mb-agreements:end -->
```

Distinct markers from the adapters' `<!-- memory-bank:start/end -->` — the two blocks coexist and are owned by different writers. Sync rules: replace between markers only, byte-preserve everything else; both markers absent → append fresh block at EOF; start without end (or vice versa) → loud error, no write; neither file exists → create `AGENTS.md` with only the block.

### Locking & atomicity

Reuse `scripts/_lib.sh` idioms already used by `mb-work-progress-append.sh`: owner-token `mkdir` lock at `<bank>/.agreements.lock` (`_lock_acquire`/`_lock_release`, timeout → loud skip with non-zero exit), temp-file + `mv` for every write. ID issuance happens under the lock (read max → write entry in one critical section) — REQ-014.

### Verifier integration (`agents/plan-verifier.md`)

New step after DoD audit: if `<bank>/agreements.md` exists, read `## Active`, classify each entry against the diff/plan as `satisfied | violated | not-applicable`, render an `## Agreement Compliance` section. Any `violated` → overall verdict FAIL with the fix-or-supersede choice (REQ-010/011). No agreements file → step silently skipped (lazy contract).

## Decisions

ADR-style, from the confirmed interview (details in `context/agreements.md`):

1. **v1 scope = core + compliance check** — no YAML mirror, no conflict registry, no scoped subsets. *Why:* token-economical design contract; extensions only if the core proves itself.
2. **Writes only via script, not model edits** — parallel sessions are real in this repo (COORDINATION.md); script guarantees monotonic IDs, valid format, atomic supersede.
3. **Explicit decision → immediate write + visible announce** (`→ AGR-NNN записано`) — no re-asking on explicit decisions, no silent writes; hypotheses go to Open Questions.
4. **Inject ALL active one-liners into CLAUDE.md and AGENTS.md** + pointer to the bank — the whole point is a fresh session seeing the full canon; >25 warns, never truncates.
5. **4 statuses** (active/deferred/superseded/rejected) — proposed/confirmed unnecessary (only confirmed decisions are written); deprecated/invalidated are rare shades of the kept two.
6. **Violated = FAIL in verify, escapable only by explicit user choice** (fix code or supersede) — never silent, never a dead end. Per-stage `/mb work` gate deliberately NOT in v1 (cost).
7. **Agreements = single entry point for decisions** — big architectural ones additionally get an ADR, referenced via `→ ADR-NNN`; rationale lives in the ADR, registry stays compact.
8. **Lazy activation** — rules trigger ships with the skill, but files/blocks appear on first `/mb agree`; kill-switch `MB_AGREEMENTS=off`.

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Model over-records (ideas become AGRs) | M | M | REQ-009 rules text with explicit anti-examples; visible announce makes every write reviewable; `reject`/`supersede` are one command |
| Model under-records (forgets to call agree) | M | M | trigger lines in CLAUDE-GLOBAL (always-on rules layer); `/mb done` checklist reminder to review session decisions |
| Managed block clobbers user content in CLAUDE.md | L | H | replace-between-markers only + byte-preservation test (NFR-005); damaged markers → loud error, no write |
| Registry grows unbounded → token bloat in every session | M | M | >25 prune warning (REQ-007); Archive not injected; rationale offloaded to ADRs |
| Marker collision with adapters' `memory-bank:start` block | L | M | distinct `mb-agreements:*` markers; bats test that both blocks coexist |
| bash 3.2 / BSD vs GNU divergence (date, sed -i) | M | M | reuse `_lib.sh` portable helpers; CI matrix already covers bash 3.2 + Linux |
| Verify cost on large registries | L | L | verifier reads Active only; not-applicable classification is cheap; per-stage gate deferred |
