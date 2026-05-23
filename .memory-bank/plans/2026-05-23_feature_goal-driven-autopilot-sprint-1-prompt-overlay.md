---
type: feature
topic: goal-driven-autopilot-sprint-1-prompt-overlay
status: active
created: 2026-05-23
level: sprint
phase_plan: 2026-05-23_feature_goal-driven-autopilot-phase.md
linked_spec: specs/goal-driven-autopilot
tasks: 1-5
baseline_commit: HEAD
---

# Plan: feature — goal-driven-autopilot — Sprint 1: Prompt overlay + addons

## Context

**Problem:** Role-agent prompts (`agents/mb-*.md`) ship as flat files. Users who want to enforce defensive behaviours (no fabrication, scope lock, read-before-write) have to fork the skill. Plus the overall spec depends on a defensive prompting infrastructure — mb-debugger (Sprint 2) and autopilot (Sprint 7) all benefit from preamble addons.

**Expected result:** A 3-level prompt resolver (user-global ◀ project ◀ skill-base) + a catalogue of opt-in preamble addons that prepend to base prompts. Default config produces byte-identical dispatches; addons activate per-project via `pipeline.yaml`.

**Related files:**
- Spec: `.memory-bank/specs/goal-driven-autopilot/{design,requirements,tasks}.md` (tasks 1-5)
- Design contract: `references/design-principles.md`
- Existing agents: `agents/mb-*.md` (9 files — not touched in this sprint)
- Existing config: `references/pipeline.default.yaml`

**Sprint scope:** spec tasks 1-5. This plan is a thin wrapper; per-task DoD lives in `tasks.md`. Stages below correspond 1:1 to spec tasks for `/mb work` execution.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Build `scripts/mb-agent-resolve.sh`

Mirrors spec Task 1.

**What to do:**
- New bash script `scripts/mb-agent-resolve.sh <role>` — resolves prompt file by precedence: user-global → project → skill-base.
- User-global root: `$HOME/.<host>/memory-bank/agents/mb-<role>.md` (host detected from `$MB_AGENT` or default `claude-code`).
- Project root: `<bank>/agents/mb-<role>.md`.
- Skill-base: `<skill-bundle>/agents/mb-<role>.md`.
- Honour `MB_AGENT_OVERLAY_ROOT` env override for testing.
- Print resolved path to stdout; exit 1 with stderr error if no match found.
- Follow existing skill conventions: `set -euo pipefail`, source `scripts/_lib.sh`, POSIX-compatible.

**Testing (TDD — tests BEFORE implementation):**
- bats: `tests/bats/test_agent_resolve.bats`
  - Given only skill-base file exists → returns skill-base path.
  - Given project overlay exists → returns project path.
  - Given user-global + project overlays exist → returns user-global path.
  - Given no match for role → exit 1 with descriptive stderr.
  - Given `MB_AGENT_OVERLAY_ROOT` set → returns from override location.

**DoD:**
- [ ] Tests written first; fail on stub `exit 0`.
- [ ] Implementation makes all bats green.
- [ ] `shellcheck scripts/mb-agent-resolve.sh` clean.
- [ ] Manual smoke: `bash scripts/mb-agent-resolve.sh mb-developer` returns shipped path.
- [ ] No new dependencies added.

**Code rules:** SOLID (single responsibility — only resolution, no dispatch), KISS (straight precedence loop), Testing Trophy (5 bats covers precedence + error + override).

---

<!-- mb-stage:2 -->
### Stage 2: Create initial addon set under `agents/addons/`

Mirrors spec Task 2.

**What to do:**
- Create `agents/addons/` directory.
- Author 4 addon files (each ≤ 250 tokens, header `# Addon: <name>`):
  - `defensive.md` — "isolated subagent, no conversation history, do not assume external context".
  - `scope-lock.md` — "may only edit files in DoD/Covers; no new libs/files/refactor outside scope; return blocker if scope wrong".
  - `fail-loudly.md` — "no fabrication, no partial-looking code, no invented paths; return explicit blocker".
  - `read-before-write.md` — "read every file in DoD/Covers BEFORE writing; verify functions/classes exist via Grep/Glob/Read".
- Generate `agents/addons/index.json` catalogue with `{name, path, description, token_estimate}` for each addon.
- Document the addon convention in a short `agents/addons/README.md`.

**Testing (TDD):**
- pytest: `tests/pytest/test_addons.py`
  - All 4 shipped addons exist at expected paths.
  - Each addon under 250 tokens (use `tiktoken` or simple word count proxy; if `tiktoken` unavailable, gate on character count ≤ 1500).
  - No `TODO` / `TBD` / `XXX` markers in addon bodies.
  - `agents/addons/index.json` lists every addon found on disk (bidirectional check — no orphan files, no missing entries).

**DoD:**
- [ ] Tests written first.
- [ ] 4 addons + `index.json` + `README.md` shipped.
- [ ] Pytest green on all assertions.
- [ ] Token estimates within stated cap.

**Code rules:** YAGNI (no extra addons until proven needed), DRY (shared markdown structure across addons).

---

<!-- mb-stage:3 -->
### Stage 3: Extend `pipeline.yaml` schema for `agents.preamble_addons`

Mirrors spec Task 3.

**What to do:**
- Update `references/pipeline.default.yaml` — add commented-out
  ```yaml
  agents:
    preamble_addons: []   # e.g. [defensive, scope-lock, fail-loudly, read-before-write]
  ```
- Extend `scripts/mb-pipeline-validate.sh`:
  - Accept `agents.preamble_addons` as list of strings.
  - Validate each entry against `agents/addons/index.json` known names.
  - Unknown name → emit `[validate] agents.preamble_addons: unknown 'X'` and exit 1.
  - Empty list (default) → exit 0.
- Update `commands/config.md` docs section if needed.

**Testing (TDD):**
- bats: `tests/bats/test_pipeline_validate_preamble_addons.bats`
  - Valid empty list → exit 0.
  - Valid list of all 4 known addons → exit 0.
  - Single unknown addon → exit 1 with descriptive message.
  - Non-array value (string instead of list) → exit 1.
  - Mixed valid + invalid → exit 1, lists all invalid names.

**DoD:**
- [ ] Tests written first.
- [ ] Validator handles all 5 scenarios.
- [ ] `pipeline.default.yaml` annotated with addon example.
- [ ] `mb-pipeline-validate.sh references/pipeline.default.yaml` exit 0.

**Code rules:** Validator is single-responsibility (no behaviour beyond validation), fail-fast (clear messages, non-zero exit).

---

<!-- mb-stage:4 -->
### Stage 4: Wire `/mb work` dispatch through resolver + addons

Mirrors spec Task 4. **Highest integration risk in this sprint** — touches the existing dispatch step.

**What to do:**
- Update `commands/work.md` step 3a:
  - Replace direct read of `agents/<agent>.md` with:
    ```
    addon_content = "\n\n".join(read(addon) for addon in pipeline.agents.preamble_addons)
    base_prompt = read($(bash scripts/mb-agent-resolve.sh <role>))
    final_prompt = addon_content + "\n\n---\n\n" + base_prompt + "\n\n" + stage_context
    ```
- When `preamble_addons` is empty AND no overlay exists, `final_prompt` must equal current behaviour byte-for-byte (no leading `\n\n---\n\n`).
- Document the new template in `commands/work.md` near step 3a description.

**Testing (TDD):**
- pytest golden-snapshot: `tests/pytest/test_dispatch_prompt_baseline.py`
  - Record current prompt for representative role (mb-developer) + dummy stage → snapshot.
  - With empty config, regenerate prompt → must match snapshot exactly.
  - With `preamble_addons: [defensive]` → snapshot includes addon at the top with separator.
  - With project overlay file present → snapshot uses overlay path.
- pytest integration: `tests/pytest/test_dispatch_with_addons.py`
  - Mock Task dispatcher; verify prompt assembly order: addons → separator → base → context.

**DoD:**
- [ ] Tests written first (snapshot frozen with empty-config behaviour).
- [ ] Implementation makes all assertions green.
- [ ] Manual smoke: `/mb work --dry-run` on the phase plan prints expected prompts.
- [ ] No regression in existing `/mb work` tests.

**Code rules:** Backward compatibility paramount; SRP (separate "resolve" and "compose prompt" steps); test before refactor.

---

<!-- mb-stage:5 -->
### Stage 5: Documentation — `docs/concepts/overlay-system.md`

Mirrors spec Task 5.

**What to do:**
- Write `docs/concepts/overlay-system.md`:
  - Overview of resolution precedence with ASCII diagram.
  - Catalogue of 4 shipped addons with one-line summaries (mirrors `index.json`).
  - Configuration snippet (copy-pasteable into `pipeline.yaml`).
  - Project / user-global overlay pattern with example file layout.
  - "When to write a custom addon" recipe (rare; usually existing 4 suffice).
- Update `docs/README.md` — replace the placeholder for "Overlay system *(coming)*" with the live link.
- Add a one-line reference to overlay-system from `docs/concepts/overview.md` (it already mentions overlays at the architecture level — link it).

**Testing (TDD):**
- pytest doc-quality: `tests/pytest/test_docs_overlay.py`
  - File exists and is ≤ 300 lines.
  - Contains required sections (Overview, Resolution order, Addons, Config, Custom addons).
  - No `(coming)` / `TBD` / `TODO` markers.
  - Code blocks parse as valid YAML where they look like YAML.

**DoD:**
- [ ] Doc shipped at expected path.
- [ ] `docs/README.md` link updated.
- [ ] All doc-quality assertions green.

**Code rules:** YAGNI on doc scope (no exhaustive theory; just enough to use the feature).

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Stage 4 breaks existing `/mb work` flow | M | Golden snapshot frozen BEFORE implementation; backward-compat path tested |
| Addon token estimates inflate over time | L | Pytest gate on character count; PR review |
| Overlay path resolution differs across hosts | M | `MB_AGENT_OVERLAY_ROOT` env override + per-host test cases |
| User adds malicious addon path | L | Validator restricts to known names from `index.json`; no arbitrary path injection |

## Gate (sprint success criterion)

Sprint 1 is complete when:

1. All 5 stages PASS through `/mb work` review-loop + verify.
2. `scripts/mb-agent-resolve.sh`, `agents/addons/`, `agents/addons/index.json` shipped.
3. `pipeline.yaml` validator accepts new field; default behaviour byte-identical to pre-sprint baseline (golden snapshot green).
4. `docs/concepts/overlay-system.md` published; `docs/README.md` link live.
5. CHANGELOG entry added under "Unreleased" referencing the overlay system.
6. All existing `mb-drift.sh` checks green; no breakage in pre-existing tests.
