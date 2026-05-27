---
plan_id: 2026-05-24_feature_opencode-first-adaptation
plan_type: feature
topic: OpenCode-first adaptation — native plugin, host-agnostic dispatch, and hook parity
status: ready
author: AI-architect
created: 2026-05-24
parent_roadmap: harness-upgrade (cross-cutting, blocks W1–W12 on OpenCode)
addresses_gaps: [I-048, I-049, I-050, I-054, I-055, I-056, I-057, I-058, I-059, I-060]
depends_on: []
breaking_changes: no (additive; existing Claude Code path untouched)
---

# OpenCode-first adaptation — Plan

## Executive summary

OpenCode has the richest native plugin API among all 6 supported hosts (JS/TS plugins, auto-discovery, hooks, subtask delegation), yet current plans downgrade it to a bash sequential fallback on par with Codex. This plan elevates OpenCode to a **first-class citizen** by:

1. **Creating a native JS plugin** (`plugins/opencode/memory-bank.js`) that implements guards, hooks, and dispatch.
2. **Introducing a host-agnostic dispatch layer** (`scripts/mb-dispatch.sh`) that abstracts `Task()` / `opencode run` / `codex run` / `pi run`.
3. **Mapping all bash hooks to OpenCode plugin hooks** (`references/opencode-hooks-mapping.md`).
4. **Updating every command file** with OpenCode frontmatter (`agent`, `subtask`).
5. **Making model aliases provider-neutral** so OpenCode (Kimi) gets correct defaults.

This plan is **cross-cutting** — its deliverables are consumed by W1–W12. It can ship in parallel with Wave 0 (CI baseline) because it is purely additive.

---

## 1. Goals & Non-goals

### Goals

- **G1 (I-056)** — OpenCode native plugin: `plugins/opencode/memory-bank.js` implements `onReady`, `onBeforeToolExecute`, `onAfterToolExecute`, `experimental.session.compacting`, `event` (session idle/deleted). Replaces git-hooks-fallback for OpenCode users.
- **G2 (I-054)** — Host-agnostic dispatch: `scripts/mb-dispatch.sh <role> <prompt-file> [--model <alias>]` detects the active host and routes to the correct dispatch primitive (`Task()`, `opencode run`, `codex run`, `pi run`, cursor/kilo sequential fallback).
- **G3 (I-055)** — Hook parity: every bash hook in `hooks/*.sh` has an OpenCode plugin equivalent documented in `references/opencode-hooks-mapping.md`.
- **G4 (I-048, I-049)** — Install & commands: `install.sh --clients opencode` creates `~/.config/opencode/skills/memory-bank/` alias; all `commands/*.md` declare OpenCode `name`, `description`, `agent`, `subtask` frontmatter.
- **G5 (I-057, I-058)** — Model resolver: `mb-pipeline-model-resolve.sh` probes `.opencode/skills/` and `~/.config/opencode/skills/` for `host_supported`; aliases are provider-neutral (`fast`/`balanced`/`powerful` resolve per-host).
- **G6 (I-059)** — Test coverage: bats tests for OpenCode plugin load, hook firing, dispatch routing, and guard blocking.
- **G7** — Documentation: `SKILL.md` gets an "OpenCode" section; `AGENTS.md` mentions auto-discovery and `.opencode/commands/`.

### Non-goals

- Rewriting the entire skill in TypeScript (the plugin is a thin wrapper around existing bash scripts).
- Changing Claude Code behavior (additive only).
- OpenCode-specific agents (agents are host-agnostic markdown; only dispatch mechanism changes).
- Real-time progress bars or UI (backlog).

---

## 2. Architecture overview

```
┌─────────────────────────────────────────────────────────────────┐
│  OpenCode host                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Plugin: .opencode/plugins/memory-bank.js (auto-discovered)│  │
│  │  ┌─────────────┐  ┌──────────────────┐  ┌──────────────┐  │  │
│  │  │ onReady     │  │ onBeforeToolExecute │  │ experimental. │  │  │
│  │  │ → inject    │  │ → dangerous-cmd    │  │ session.      │  │  │
│  │  │   context   │  │   guard            │  │ compacting    │  │  │
│  │  │             │  │ → protected-paths  │  │ → actualize   │  │  │
│  │  │             │  │   guard            │  │   handoff     │  │  │
│  │  └─────────────┘  └──────────────────┘  └──────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  scripts/mb-dispatch.sh <role> <prompt> [--model <alias>] │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  Host detection: $MB_HOST or .memory-bank/.mb-host  │  │  │
│  │  │  ├─ claude-code → Task(subagent_type=role, ...)      │  │  │
│  │  │  ├─ opencode    → opencode run --agent <role> ...     │  │  │
│  │  │  ├─ codex       → codex run --agent <role> ...        │  │  │
│  │  │  ├─ pi          → pi run --agent <role> ...            │  │  │
│  │  │  └─ cursor/kilo → sequential bash fallback              │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Role agents (host-agnostic markdown)                     │  │
│  │  agents/mb-reviewer.md, agents/mb-developer.md, ...       │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Stages

### Stage 1: OpenCode native plugin (G1)

**What to do:**
- Create `plugins/opencode/memory-bank.js` (or `adapters/opencode/plugin.js` if we want to keep everything in `adapters/`):
  - `onReady`: inject session-start context (equivalent to `hooks/mb-session-start-context.sh`).
  - `onBeforeToolExecute`: block dangerous commands + protected paths (equivalent to `hooks/mb-protected-paths-guard.sh` + `hooks/file-change-log.sh`).
  - `onAfterToolExecute`: sync plan after write/edit (equivalent to `hooks/mb-plan-sync-post-write.sh`).
  - `experimental.session.compacting`: actualize handoff before compaction (equivalent to `hooks/mb-pre-compact.sh`).
  - `event` (type `session_idle` / `session_deleted`): session-end autosave (equivalent to `hooks/session-end-autosave.sh`).
- Plugin reads `process.env.MB_PATH` for bank location (same pattern as existing bash scripts).
- Plugin loads `.memory-bank/RULES.md` and injects it into context on ready.

**Testing (TDD):**
- `tests/bats/test_opencode_plugin_load.bats`: plugin file exists, syntax valid (`node --check`), auto-discovered by OpenCode.
- `tests/bats/test_opencode_plugin_onready.bats`: onReady fires, context injected.
- `tests/bats/test_opencode_plugin_guard.bats`: onBeforeToolExecute blocks `rm -rf /` and protected paths.
- `tests/bats/test_opencode_plugin_compact.bats`: experimental.session.compacting triggers handoff actualize.

**DoD:**
- [ ] Plugin file exists and passes `node --check`.
- [ ] All 5 hooks implemented with parity to bash equivalents.
- [ ] 4 bats test files PASS (≥8 tests).
- [ ] Plugin does not break when env `MB_PATH` is unset (graceful fallback to cwd).

**Code rules:** Plugin calls existing bash scripts rather than duplicating logic. DRY — the plugin is a wrapper, not a rewrite.

---

### Stage 2: Host-agnostic dispatch layer (G2)

**What to do:**
- Create `scripts/mb-dispatch.sh`:
  - Args: `<role>` `<prompt-file>` `[--model <alias>]`
  - Detects host: `$MB_HOST` env → `.memory-bank/.mb-host` file → auto-detect from parent process name.
  - Routes:
    - `claude-code`: emits `Task(subagent_type=<role>, model=<resolved>, prompt=<prompt>)`.
    - `opencode`: runs `opencode run --agent <role> --prompt-file <prompt-file> [--model <resolved>]`.
    - `codex`: runs `codex run --agent <role> --prompt-file <prompt-file>`.
    - `pi`: runs `pi run --agent <role> --prompt-file <prompt-file>`.
    - `cursor` / `kilo`: sequential bash fallback (source prompt file and run inline).
  - Returns exit code of the subagent; stdout/stderr forwarded.
- Update `commands/work.md` step 3: replace `Task(...)` with `bash scripts/mb-dispatch.sh <role> <prompt-file>`.
- Update `commands/done.md`, `commands/verify.md`, `commands/review.md` similarly.

**Testing (TDD):**
- `tests/bats/test_mb_dispatch_host_detection.bats`: auto-detect from process name, env override, file override.
- `tests/bats/test_mb_dispatch_routing.bats`: each host route emits correct command (mocked executables).
- `tests/bats/test_mb_dispatch_model_passing.bats`: `--model` forwarded correctly per host.

**DoD:**
- [ ] `mb-dispatch.sh` exists, shellcheck clean.
- [ ] All 5 host routes implemented.
- [ ] 3 bats test files PASS (≥9 tests).
- [ ] At least one real end-to-end: OpenCode `opencode run` successfully dispatches `mb-reviewer`.

**Code rules:** DIP — dispatch layer depends on host abstraction, not concrete agents. Open/Closed — adding a new host = adding a new route function, no changes to callers.

---

### Stage 3: Hook parity & mapping document (G3)

**What to do:**
- Create `references/opencode-hooks-mapping.md`:
  - Table: bash hook file → Claude Code hook → OpenCode plugin hook → implementation status.
  - Document `onBeforeToolExecute` signature: `(input, output)` where `output.args` contains tool args.
  - Document `experimental.session.compacting` signature: `(input, output)` where `output.context[]` can receive new items.
  - Provide copy-paste-ready JS snippets for each mapped hook.
- Update existing bash hooks to be "plugin-friendly":
  - Export `run_guard()` functions so plugin can source and call them.
  - Ensure all hooks respect `MB_PATH` env.

**Testing:**
- `tests/bats/test_opencode_hooks_parity.bats`: for each mapped hook, verify plugin produces same result as bash hook on fixture inputs.

**DoD:**
- [ ] `references/opencode-hooks-mapping.md` exists and covers all 10 hooks.
- [ ] All bash hooks refactored to expose `run_*` functions.
- [ ] Parity bats tests PASS.

---

### Stage 4: Install, commands, and model resolver (G4, G5)

**What to do:**
- Update `install.sh`:
  - Add `--clients opencode` support.
  - Create `~/.config/opencode/skills/memory-bank/` symlink (same pattern as `~/.claude/skills/`).
  - Create `.opencode/commands/` symlinks for all `commands/*.md` (or copy if needed).
- Update all `commands/*.md` (24 files):
  - Add OpenCode frontmatter block at top:
    ```yaml
    ---
    name: /mb work
    description: Execute a work stage
    agent: mb-developer
    subtask: true
    ---
    ```
  - Keep existing Claude Code `allowed-tools` block (backward compat).
- Update `scripts/mb-pipeline-model-resolve.sh`:
  - When active adapter is OpenCode, probe `.opencode/skills/<name>/` and `~/.config/opencode/skills/<name>/` for `host_supported`.
- Update `references/model-aliases.yaml`:
  - Make aliases provider-neutral:
    ```yaml
    aliases:
      fast:
        claude: claude-haiku-4-5-20251001
        opencode: kimi-k2-mini
        codex: gpt-4o-mini
      balanced:
        claude: claude-sonnet-4-6
        opencode: kimi-k2.5
        codex: gpt-4o
      powerful:
        claude: claude-opus-4-7
        opencode: kimi-k2.6
        codex: gpt-4.5
    ```

**Testing:**
- `tests/bats/test_install_opencode_path.bats`: symlink created, commands discoverable.
- `tests/bats/test_commands_opencode_frontmatter.bats`: all 24 files have valid OpenCode frontmatter.
- `tests/bats/test_model_resolver_opencode_probe.bats`: OpenCode skill dirs probed correctly.
- `tests/bats/test_model_aliases_provider_neutral.bats`: aliases resolve per-host.

**DoD:**
- [ ] `install.sh --clients opencode` works idempotently.
- [ ] All 24+ command files have OpenCode frontmatter.
- [ ] Model resolver probes OpenCode paths.
- [ ] All 4 bats test files PASS.

---

### Stage 5: Documentation & e2e smoke (G6, G7)

**What to do:**
- Update `SKILL.md`: add "For OpenCode" section describing auto-discovery, plugin hooks, and `opencode run` dispatch.
- Update `AGENTS.md`: mention `.opencode/commands/` auto-discovery and plugin capabilities.
- Update `docs/cross-agent-setup.md`: add OpenCode column to compatibility matrix.
- Manual e2e smoke:
  - Install skill in an OpenCode project.
  - Run `/mb start` — verify `onReady` injects context.
  - Run `/mb work` on a small plan — verify `mb-dispatch.sh` routes to `opencode run`.
  - Verify `onBeforeToolExecute` blocks a dangerous command.
  - Verify `experimental.session.compacting` actualizes handoff.

**Testing:**
- `tests/bats/test_install_opencode_smoke.bats`: end-to-end on tmp repo with mocked OpenCode CLI.

**DoD:**
- [ ] `SKILL.md` has OpenCode section ≥20 lines.
- [ ] `AGENTS.md` mentions OpenCode plugin system.
- [ ] E2e smoke completed; results recorded in `progress.md`.
- [ ] No regression in existing bats/pytest suites.

---

## 4. File inventory

### New files

| Path | Kind | Purpose |
|------|------|---------|
| `plugins/opencode/memory-bank.js` | JS | Native OpenCode plugin implementing all hooks |
| `scripts/mb-dispatch.sh` | bash | Host-agnostic dispatch abstraction |
| `references/opencode-hooks-mapping.md` | md | Hook parity documentation |
| `tests/bats/test_opencode_plugin_*.bats` | bats | Plugin load, onReady, guard, compact tests |
| `tests/bats/test_mb_dispatch_*.bats` | bats | Host detection, routing, model passing tests |
| `tests/bats/test_opencode_hooks_parity.bats` | bats | Hook parity verification |
| `tests/bats/test_install_opencode_*.bats` | bats | Install path and command frontmatter tests |
| `tests/bats/test_model_resolver_opencode_probe.bats` | bats | OpenCode skill dir probing |
| `tests/bats/test_model_aliases_provider_neutral.bats` | bats | Per-host alias resolution |

### Modified files

| Path | Change |
|------|--------|
| `adapters/opencode.sh` | Install plugin file to `.opencode/plugins/`; no `opencode.json` mutation |
| `install.sh` | Add `--clients opencode` and `~/.config/opencode/skills/` alias |
| `commands/*.md` (24 files) | Add OpenCode frontmatter block (`name`, `description`, `agent`, `subtask`) |
| `scripts/mb-pipeline-model-resolve.sh` | Probe `.opencode/skills/` and `~/.config/opencode/skills/` |
| `references/model-aliases.yaml` | Provider-neutral alias table |
| `SKILL.md` | Add "For OpenCode" section |
| `AGENTS.md` | Mention OpenCode auto-discovery and plugin capabilities |
| `docs/cross-agent-setup.md` | Add OpenCode column to matrix |
| `hooks/*.sh` | Refactor to expose `run_*` functions for plugin reuse |

---

## 5. Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Plugin JS syntax errors break OpenCode startup | M | `node --check` in CI; plugin wrapped in try/catch |
| `opencode run` CLI behavior changes | L | Dispatch layer isolates CLI details; adapter versioned |
| Hook parity drift over time | M | Parity bats tests run in CI; mapping doc auto-checked |
| Command frontmatter bloat | L | Frontmatter is YAML front-matter; ignored by non-OpenCode hosts |
| Model alias table becomes stale | L | Aliases resolve per-host; concrete IDs in one file |
| Host detection false positives | M | `$MB_HOST` env override; `.mb-host` file for explicit config |

---

## 6. Traceability

| REQ | Plan stage | Spec | Test file |
|-----|-----------|------|-----------|
| REQ-OC-001 | S1 | plugins/opencode/memory-bank.js | test_opencode_plugin_load.bats |
| REQ-OC-002 | S1 | onReady hook | test_opencode_plugin_onready.bats |
| REQ-OC-003 | S1 | onBeforeToolExecute guard | test_opencode_plugin_guard.bats |
| REQ-OC-004 | S1 | experimental.session.compacting | test_opencode_plugin_compact.bats |
| REQ-OC-005 | S2 | mb-dispatch.sh | test_mb_dispatch_host_detection.bats |
| REQ-OC-006 | S2 | Host routing | test_mb_dispatch_routing.bats |
| REQ-OC-007 | S3 | Hook parity | test_opencode_hooks_parity.bats |
| REQ-OC-008 | S4 | Install OpenCode path | test_install_opencode_path.bats |
| REQ-OC-009 | S4 | Command frontmatter | test_commands_opencode_frontmatter.bats |
| REQ-OC-010 | S4 | Model resolver probe | test_model_resolver_opencode_probe.bats |
| REQ-OC-011 | S4 | Provider-neutral aliases | test_model_aliases_provider_neutral.bats |
| REQ-OC-012 | S5 | Documentation | Manual smoke |

---

## 7. Integration with existing waves

This plan produces **infrastructure** consumed by W1–W12:

- **W1 reviewer-v2**: consumes `mb-dispatch.sh` for reviewer/test-runner dispatch; OpenCode plugin provides guard hooks.
- **W2 work-loop-v2**: consumes `mb-dispatch.sh` for pivot and contract review dispatch.
- **W3 handoff-v2**: OpenCode plugin implements `experimental.session.compacting` → pre-compact actualize.
- **W4 cost-multi-model**: provider-neutral aliases + OpenCode probe in resolver.
- **W5–W11 goal-driven-autopilot**: `mb-dispatch.sh` for debugger, implementer, parallel waves.
- **W12 parallel-pipeline**: `mb-dispatch.sh` for adapter layer; OpenCode plugin for native parallel subtask delegation (future enhancement).

---

## 8. Notes

- **Plugin vs bash:** The plugin is intentionally a thin wrapper around existing bash scripts. We do NOT reimplement logic in JS. Example:
  ```js
  onBeforeToolExecute: (input, output) => {
    if (['write', 'edit'].includes(input.tool)) {
      const result = spawnSync('bash', ['hooks/mb-protected-paths-guard.sh', output.args.path]);
      if (result.status !== 0) {
        output.blocked = true;
        output.reason = result.stdout.toString();
      }
    }
  }
  ```
- **Auto-discovery:** OpenCode discovers `.opencode/plugins/*.js` automatically. We do NOT write to `opencode.json`.
- **Backward compat:** Claude Code users see zero changes. All modifications are additive or behind host-detection.
- **Future:** Once OpenCode plugin stabilizes, W12 parallel-pipeline can explore plugin-driven parallel subtask delegation (native `opencode run` parallelism via plugin orchestration).
