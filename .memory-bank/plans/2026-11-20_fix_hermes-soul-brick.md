---
type: fix
topic: hermes-soul-brick
status: done
depends_on: []
parallel_safe: false
linked_specs: []
qa: off — small tier
created: 2026-11-20
---
# Plan: fix — hermes-soul-brick

**Baseline commit:** ee5cfce4a46b16b8c6cd8d3ef7787472073abd2a

## Context

**Problem:** hermes-plugins roadmap Wave 0 (backlog I-012 there) blocks soul-composer. The Hermes memory-bank plugin (`hermes/memory-bank/__init__.py`) writes its rules block straight into `$HERMES_HOME/SOUL.md` (`_sync_soul_rules`, lines ~214-245), so a composer-built SOUL would get a second writer; its section cap `SECTION_CAP = 6000` (line 28) is above Hermes' 4000-chars-per-plugin-section limit (`agent/system_prompt.py:87`, 8000 total); `hermes` is missing from `KNOWN_AGENTS` in `scripts/mb_pipeline_validate_blocks.py:207`, so a pipeline with `agents: [hermes]` fails validation.

**Expected result:** soul-composer can take the memory-bank rules as a provider brick through `render_soul_brick() -> str`; the plugin never rewrites a SOUL.md that carries the composer header `<!-- soul-composer: build <hash> -->`; the plugin section fits 4000 chars; `hermes` is a known code agent.

**Related files:**
- `hermes/memory-bank/__init__.py`, `tests/pytest/test_hermes_plugin.py`
- `scripts/mb_pipeline_validate_blocks.py` and its existing pipeline-validation tests
- Contract source: `~/Apps/hermes-plugins/.memory-bank/specs/soul-composer/{requirements,design,tasks}.md` (REQ-005, scenario "providers skip their own sync", Task on provider bricks)

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: memory-bank as a soul-composer provider for Hermes

**Files:** `hermes/memory-bank/__init__.py`, `tests/pytest/test_hermes_plugin.py`, `scripts/mb_pipeline_validate_blocks.py`, the existing pytest file that covers pipeline `agents:` validation

**What to do:**
- `render_soul_brick() -> str` (module-level, public): returns the same rules block `_rules_block()` renders, markers included, so the composer gets byte-identical text to what the plugin writes today; `_sync_soul_rules` reuses it (one source).
- `_sync_soul_rules`: if SOUL.md starts with the composer header (`<!-- soul-composer: build ` at the first line), write nothing — the composer is the single writer (REQ-005). Without the header the behaviour stays exactly as today.
- `SECTION_CAP = 4000` (Hermes per-section limit); the section still truncates to it.
- Add `"hermes"` to `KNOWN_AGENTS`.

**Testing (TDD — tests BEFORE implementation):**
- `test_render_soul_brick_returns_rules_block_with_markers`: text starts with `<!-- mb-rules:start -->`, ends with `<!-- mb-rules:end -->`, contains `## Key rules`, has no `**Language**` line, and equals the block `register()` writes into a plain SOUL.md.
- `test_soul_sync_with_composer_header_writes_nothing`: SOUL.md beginning with `<!-- soul-composer: build abc123 -->` keeps bytes and mtime after `register()`.
- `test_memory_bank_section_fits_the_plugin_budget` tightened: `len(text) <= 4000` asserted as a literal, not via `plugin.SECTION_CAP`.
- Pipeline validation: a pipeline with `agents: [hermes]` validates clean; an unknown agent still fails.

**DoD (Definition of Done):**
- [x] `render_soul_brick()` exists and returns the marker-wrapped rules block identical to what the plugin syncs into a header-less SOUL.md
- [x] a SOUL.md with the composer header is never rewritten by the plugin; header-less behaviour unchanged (existing SOUL tests pass)
- [x] plugin section is at most 4000 chars
- [x] `agents: [hermes]` passes pipeline validation, unknown agents still rejected
- [x] `python3 -m pytest -q tests/pytest/test_hermes_plugin.py` and the touched pipeline-validation tests pass
- [x] `ruff check hermes/memory-bank scripts/mb_pipeline_validate_blocks.py tests/pytest/test_hermes_plugin.py` clean

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture
<!-- /mb-stage:1 -->

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Live Hermes profiles lose the rules block | L | Header-less SOUL keeps today's sync; only a composer-built SOUL is skipped, and the composer pulls the same block via `render_soul_brick()` |
| 4000 cap cuts useful section text | M | Section already truncates; test asserts the cap, content order keeps the head first |

## Gate (plan success criterion)

All Stage 1 DoD bullets ticked by `/mb work`, plan-verifier PASS, full pytest of the touched files green.
