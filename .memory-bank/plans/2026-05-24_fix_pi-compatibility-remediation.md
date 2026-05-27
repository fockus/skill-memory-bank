---
type: fix
scope: pi-compatibility-remediation
created: 2026-05-24
status: queued
priority: HIGH
linked_specs: [specs/pi-extension]
---

# Fix: Pi Compatibility Remediation

Closes the compatibility gap identified in `reports/2026-05-24_pi-compatibility-audit.md`.

## Goal

Achieve first-class Pi parity with Claude Code by shipping the `memory-bank-pipeline`
extension (TypeScript) that provides:
1. **Subagent dispatch** — parallel/chain/single via `pi --mode json` subprocess spawn.
2. **Hook guards** — dangerous-command block, protected-paths block, SessionEnd auto-capture, PreCompact actualize, weekly compact reminder.
3. **Commands** — `/mb`, `/mb-work`, `/mb-run` with native argument parsing.
4. **Model provider registration** — `registerProvider()` for cross-provider judge phases.

## Stages

### Stage 1: Extension skeleton + lib modules

- Task: Extension skeleton (`index.ts`, `package.json`).
- Task: `lib/resolve.ts` — dispatches.json reader + model resolver.
- Task: `lib/spawn.ts` — pi subprocess spawn + JSON output parser.

### Stage 2: Pipeline dispatch tool

- Task: `pipeline.ts` — `mb_dispatch` tool (single + parallel + chain).

### Stage 3: Hook guards

- Task: `hooks.ts` — dangerous-command guard (`tool_call` block).
- Task: `hooks.ts` — protected-paths guard (`tool_call` block).
- Task: `hooks.ts` — SessionEnd auto-capture + PreCompact actualize + compact reminder.

### Stage 4: Commands

- Task: `commands.ts` — `/mb`, `/mb-work`, `/mb-run`.

### Stage 5: Model providers + wiring

- Task: `providers.ts` — optional cross-provider model registration.
- Task: `index.ts` wiring — load all modules, error boundaries.

### Stage 6: Install integration + docs

- Task: `install.sh` integration — extension install step.
- Task: Documentation — `docs/pi-extension.md` + `SKILL.md` update.

## Verification

- `mb-spec-validate pi-extension` — PASS (0 violations).
- `bats tests/bats/test_pi_extension_*.bats` — ≥16 tests, all PASS.
- `pytest tests/pytest/test_pi_extension_*.py` — ≥4 tests, all PASS.
- Manual smoke: Pi extension loads, `/mb work` dispatches subprocess, dangerous command blocked.

## DoD

- [ ] Extension installs via `install.sh --clients pi`.
- [ ] All hook guards active (block-dangerous, protected-paths, auto-capture, compact reminder).
- [ ] Pipeline dispatch supports parallel (max 8 / 4 concurrent) and chain modes.
- [ ] Commands `/mb`, `/mb-work`, `/mb-run` registered and functional.
- [ ] Cross-provider models registerable via env vars.
- [ ] Documentation updated (`docs/pi-extension.md`, `SKILL.md`, `cross-agent-setup.md`).
- [ ] `mb-spec-validate pi-extension` clean.
- [ ] All tests green.
