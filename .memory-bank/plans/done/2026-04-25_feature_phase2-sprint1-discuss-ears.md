---
type: feature
topic: phase2-sprint1-discuss-ears
status: done
sprint: 1
phase_of: skill-v2-phase-2
parallel_safe: false
covers_requirements: []
linked_specs: [specs/mb-skill-v2/]
created: 2026-04-25
---

# Feature: Phase 2 Sprint 1 — `/mb discuss` + EARS validator + `context/<topic>.md`

## Context

Sprint 2 (Phase 1) построил **output-side** traceability pipeline (mb-traceability-gen.sh заполняет matrix REQ → Plan → Test). Но **input-side** пуст: нет команды для создания requirements в EARS-формате, нет `context/<topic>.md` template'а, нет валидатора. Поэтому traceability.md всегда печатает "No specs yet".

Phase 2 Sprint 1 закрывает input-side: `/mb discuss` собирает структурированное интервью, EARS validator проверяет 5 паттернов, `context/<topic>.md` становится источником REQ-IDs для traceability.

## Spec references

- `specs/mb-skill-v2/design.md` §5 — `/mb discuss` workflow
- §6 — `/mb plan` SDD-lite enhancement (откладываем на Sprint 2 Phase 2)
- §10 — traceability storage details

## EARS — 5 patterns (formal grammar)

| Pattern | Template | Example |
|---|---|---|
| Ubiquitous | `The <system> shall <response>` | `The system shall log every transaction` |
| Event-driven | `When <trigger>, the <system> shall <response>` | `When the user logs in, the system shall record the timestamp` |
| State-driven | `While <state>, the <system> shall <response>` | `While the door is open, the alarm shall stay active` |
| Optional feature | `Where <feature>, the <system> shall <response>` | `Where biometric auth is enabled, the system shall require a fingerprint` |
| Unwanted | `If <trigger>, then the <system> shall <response>` | `If the connection times out, then the system shall retry up to 3 times` |

Validator regex (final form):
```
^[[:space:]]*-[[:space:]]+\*\*REQ-[0-9]{3,}\*\*.*\b(The|When|While|Where|If)\b.*\bshall\b
```

(`If` requires implicit `then` — semantic check via LLM, not regex.)

## REQ-NNN cross-spec ID generator

`scripts/mb-req-next-id.sh` сканирует:
- `.memory-bank/specs/*/requirements.md`
- `.memory-bank/context/*.md`
- `.memory-bank/specs/*/design.md` (на случай прямых REQ ссылок)

Возвращает `printf 'REQ-%03d\n' $((max + 1))`. При отсутствии любых REQ → `REQ-001`.

## Definition of Done (SMART)

- ✅ pytest 293+ → 293+ N (новые tests добавлены, ничего не регрессирует)
- ✅ `scripts/mb-ears-validate.sh` принимает `[file]` (или stdin при отсутствии), exit 0 если все REQ-* строки в формате, exit 1 если есть нарушения, exit 2 на ошибки usage
- ✅ `scripts/mb-req-next-id.sh` возвращает следующий REQ-NNN сквозной по проекту
- ✅ `references/templates.md` содержит `context/<topic>.md` template
- ✅ `commands/discuss.md` — slash-command для `/mb discuss <topic>`
- ✅ `commands/mb.md` router добавляет `discuss` row + section
- ✅ shellcheck + ruff clean
- ✅ Backlog обновлён, plan переехал в done/, CHANGELOG `[Unreleased]`

## Stages

<!-- mb-stage:1 -->
## Stage 1: RED — failing tests for EARS validator + REQ-ID generator

**TDD:** написать pytest тесты против ещё не существующих скриптов.

1. `tests/pytest/test_ears_validate.py`:
   - 5 valid patterns (по одному на каждый EARS-тип) — exit 0, 0 stdout violations.
   - 4 invalid: REQ без `shall`, REQ без trigger keyword, plain text (no REQ marker), broken format.
   - Empty input → exit 0 (vacuously valid).
   - Multiple REQs: 3 valid + 1 invalid → exit 1, only the invalid line in violations.
   - Non-EARS lines (free text) — ignored, only `REQ-NNN` lines validated.
2. `tests/pytest/test_req_next_id.py`:
   - Empty bank → REQ-001.
   - Single requirements.md with REQ-001/REQ-002 → REQ-003.
   - Cross-spec: spec_a has REQ-001..REQ-005, spec_b has REQ-006..REQ-008 → REQ-009.
   - Context-only: context/foo.md with REQ-001..REQ-003 → REQ-004.
   - Mixed: specs + context → max+1 across all sources.
   - Non-monotonic gaps: REQ-001, REQ-005 → REQ-006 (max+1, не fill gap).

**DoD:**
- ✅ pytest `test_ears_validate.py` 11+ failing (RED)
- ✅ pytest `test_req_next_id.py` 6 failing (RED)
- ✅ Old 293 tests green

<!-- mb-stage:2 -->
## Stage 2: GREEN — `scripts/mb-ears-validate.sh`

**Implementation:**
- Parse arg: file path или `-` для stdin.
- For each line matching `^[[:space:]]*-[[:space:]]+\*\*REQ-[0-9]{3,}\*\*`:
  - Apply regex `\b(The|When|While|Where|If)\b.*\bshall\b`.
  - On miss: print `[ears] line N: REQ-NNN does not match any EARS pattern` to stderr, set exit=1.
- Final exit: 0 если 0 violations, 1 если есть violations, 2 если usage error.
- Header comment с EARS table.

**Test gate:**
- `test_ears_validate.py` всё PASSED.
- `shellcheck -x mb-ears-validate.sh` clean.

**DoD:**
- ✅ pytest 304+ passed
- ✅ shellcheck clean

<!-- mb-stage:3 -->
## Stage 3: GREEN — `scripts/mb-req-next-id.sh`

**Implementation:**
- Resolve `MB_PATH` через `mb_resolve_path`.
- Глобально grep'нуть `REQ-[0-9]{3,}` через `find` + `grep -hoE` по `specs/**/*.md` + `context/*.md`.
- `sort -u | sed 's/REQ-//' | sort -n | tail -1` → max.
- При отсутствии — start = 0.
- Output: `printf 'REQ-%03d\n' $((max + 1))`.
- Exit: 0 OK, 1 missing `.memory-bank/`.

**Test gate:**
- `test_req_next_id.py` PASSED.
- `shellcheck -x mb-req-next-id.sh` clean.

**DoD:**
- ✅ pytest всё green
- ✅ shellcheck clean

<!-- mb-stage:4 -->
## Stage 4: `context/<topic>.md` template + `commands/discuss.md` + router registration

**Files:**

1. `references/templates.md` (новая секция):
   ```markdown
   ## context/<topic>.md template

   ---
   topic: <topic>
   created: YYYY-MM-DD
   status: draft | ready
   ---

   # Context: <topic>

   ## Purpose & Users
   ...

   ## Functional Requirements (EARS)
   - **REQ-NNN** (ubiquitous): The system shall ...
   - **REQ-NNN** (event-driven): When ..., the system shall ...

   ## Non-Functional Requirements
   - **NFR-001**: ...

   ## Constraints
   ...

   ## Edge Cases & Failure Modes
   ...

   ## Out of Scope
   ...
   ```

2. `commands/discuss.md`:
   - Frontmatter: `description`, `allowed-tools`.
   - 5-phase interview workflow (Purpose & Users / Functional EARS / Non-Functional / Constraints / Edge Cases).
   - After phase 2: run `bash scripts/mb-ears-validate.sh` against draft, surface violations.
   - REQ-IDs assigned via `bash scripts/mb-req-next-id.sh`.
   - Final write: `.memory-bank/context/<topic>.md` with frontmatter status=ready.
   - Trigger `mb-traceability-gen.sh` after write.

3. `commands/mb.md`:
   - Add row to router table:
     `| `discuss <topic>`                                       | Run 5-phase requirements-elicitation interview, write context/<topic>.md (EARS-validated)  |`
   - Add `### discuss <topic>` section with full description (mirroring `commands/discuss.md`).

**Tests (where deterministic):**
- `tests/pytest/test_context_template.py`:
  - Verify the template appears in `references/templates.md` (substring presence).
  - Verify required sections (Purpose & Users / Functional Requirements (EARS) / Non-Functional / Constraints / Edge Cases / Out of Scope).
- `tests/pytest/test_discuss_command_registration.py`:
  - `commands/discuss.md` exists with frontmatter `description` + `allowed-tools`.
  - `commands/mb.md` router table contains `| \`discuss` row.
  - `commands/mb.md` has `### discuss` section.

**DoD:**
- ✅ All template + registration tests PASSED
- ✅ All 4 sections in template
- ✅ Router table updated

<!-- mb-stage:5 -->
## Stage 5: Final regression + bank close-out + commit/push

1. Full pytest, shellcheck, ruff — green.
2. Bats sanity (subset, не все 526 — interactive tests тут new).
3. Update bank artifacts:
   - `backlog.md`: nothing closed (no I-NNN involved); just inventory check.
   - `checklist.md`: Phase 2 Sprint 1 block → ✅.
   - `status.md`: pointer на Phase 2 Sprint 2 (`/mb sdd` + specs/<topic>/).
   - `roadmap.md`: Recently completed entry, Next pivots to Sprint 2.
   - `CHANGELOG.md` `[Unreleased]` Added entry.
4. Plan `.memory-bank/plans/2026-04-25_feature_phase2-sprint1-discuss-ears.md` → `plans/done/`, status=done.
5. `progress.md` append.
6. Bulk commit + push.

**DoD:**
- ✅ pytest всё green
- ✅ shellcheck зелёный
- ✅ ruff зелёный
- ✅ Bank актуален
- ✅ Origin pushed
