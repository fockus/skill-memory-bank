---
type: feature
topic: global-storage-core
status: done
parallel_safe: false
depends_on: []
linked_specs: []
sprint: Sprint 1
phase_of: global-storage
---

# Plan: feature — global-storage-core

**Baseline commit:** f16e5715854828431fe5820c10d0ad062e4f9892

## Context

**Problem:** Memory Bank сейчас по умолчанию живёт в `<project>/.memory-bank/`. Это удобно для командного режима, когда банк осознанно хранится в git, но неудобно для личного использования в чужом репозитории: папка может попасть в diff, создать шум для коллег и потребовать дополнительных `.gitignore` договорённостей. В `scripts/_lib.sh` уже есть частичная legacy-поддержка внешнего хранилища через `.claude-workspace`, но она привязана к Claude и требует проектного файла, что не решает требование «без следов в репозитории» и не покрывает все поддерживаемые агенты.

**Expected result:** Пользователь при `/mb init` может выбрать режим хранения: `local` создаёт `<project>/.memory-bank/` как сейчас; `global` создаёт банк в глобальной области выбранного code agent и регистрирует текущий проект в глобальном registry без записи служебных файлов в репозиторий. Все runtime scripts получают путь через единый resolver, старый `.claude-workspace` остаётся backward-compatible, а default поведение остаётся `local`.

**Phase split:** Требование затрагивает resolver, init UX, команды, hooks, adapters, docs и тесты. Это больше одного безопасного Sprint. Этот файл — Sprint 1: core storage model + init flow. Sprint 2: [feature — global-storage-agent-support](2026-05-21_feature_global-storage-agent-support.md) — адаптеры, hooks и документация для всех code agents.

**Related files:**
- `scripts/_lib.sh` — общий `mb_resolve_path`; сейчас знает только explicit arg, `.claude-workspace`, fallback `.memory-bank`.
- `scripts/mb-init-bank.sh` — scaffolder банка; сейчас всегда создаёт `<MB_ROOT>/.memory-bank`.
- `commands/mb.md`, `commands/start.md`, `commands/plan.md`, `commands/done.md` — user-facing workflow; сейчас описывают только project-local `.memory-bank/`.
- `memory_bank_skill/cli.py` — CLI init hint; сейчас не умеет storage mode.
- `tests/bats/test_mb_config.bats`, `tests/bats/test_context_integration.bats`, `tests/bats/test_mb_plan.bats`, `tests/pytest/test_cli.py` — ближайшие тестовые паттерны.

## Requirements by example

| Scenario | Input | Expected behavior |
|----------|-------|-------------------|
| Default local init | `bash scripts/mb-init-bank.sh --lang=ru --mb-root=/repo` | Creates `/repo/.memory-bank/` and writes `storage_mode=local` to `/repo/.memory-bank/.mb-config`. |
| Global init for Pi | `bash scripts/mb-init-bank.sh --storage=global --agent=pi --project-root=/repo --lang=ru` | Creates `$HOME/.pi/agent/memory-bank/projects/<project_id>/.memory-bank/`, writes registry entry under `$HOME/.pi/agent/memory-bank/registry.json`, does not create `/repo/.memory-bank/`. |
| Existing local bank | Run global init in project with `/repo/.memory-bank/` | Fails with a clear message unless `--force` or migration command is explicitly used; no data moved implicitly. |
| Runtime in registered project | `cd /repo && bash scripts/mb-context.sh` after global init | Reads the external bank path resolved from agent registry. |
| Legacy workspace | `.claude-workspace` with `storage: external` | Still resolves to the old `~/.claude/workspaces/<id>/.memory-bank` path until documented migration is added. |
| Unknown project with global rules installed | No local bank, no registry entry, global skill/rules are installed | First response is `[MEMORY BANK: ABSENT]`; agent does not initialize Memory Bank, but TDD/SOLID/Clean Architecture/FSD/DRY/KISS/YAGNI/Testing Trophy rules still apply to normal code work. |
| Unknown project | No local bank, no registry entry | `mb-context.sh` prints inactive status and suggests `/mb init`, without creating files. |

## Architecture decision for this Sprint

1. Introduce a single storage resolver in `scripts/_lib.sh`:
   - explicit script argument wins;
   - `MB_PATH` env override wins over discovery;
   - local `<project>/.memory-bank/` wins when present;
   - global registry lookup for current project wins when present;
   - legacy `.claude-workspace` remains supported after registry lookup for backward compatibility;
   - fallback stays `.memory-bank` for compatibility with existing scripts.
2. Add a global registry, not a project pointer file, for the new `global` mode:
   - registry path is `<agent_config_dir>/memory-bank/registry.json`;
   - registry key is deterministic from canonical project root plus git remote when available;
   - project id is `<repo-basename>-<sha256_12>` and must match `^[A-Za-z0-9_-]+$`.
3. Agent config roots are explicit and testable:
   - `claude-code`: `$HOME/.claude`
   - `cursor`: `$HOME/.cursor`
   - `codex`: `$HOME/.codex`
   - `opencode`: `$HOME/.config/opencode`
   - `pi`: `$HOME/.pi/agent`
   - `windsurf`: `$HOME/.windsurf`
   - `cline`: `$HOME/.cline`
   - `kilo`: `$HOME/.kilocode`
4. Keep no-new-dependency policy: JSON read/write is implemented through `python3` stdlib in shell scripts; `jq` remains optional where already optional.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Storage resolver contract tests

**What to do:**
- Add `tests/bats/test_mb_storage_resolver.bats` with behavior-first tests for the resolver and registry format before changing production code.
- Cover local default, explicit arg precedence, `MB_PATH` precedence, global registry lookup, invalid project id rejection, legacy `.claude-workspace`, and inactive project behavior.
- Add helper fixtures inside the test file only; do not introduce a new test framework.

**Testing (TDD — tests BEFORE implementation):**
- Unit-style bats tests source `scripts/_lib.sh` and call shell functions directly in temp dirs.
- Integration-style bats tests run `bash scripts/mb-context.sh` against a registered temp project to prove scripts consume resolver output.
- Edge cases: project paths with spaces, no git repo, git repo with remote, invalid JSON registry, missing registry file, HOME sandbox.
- Red phase command: `bats tests/bats/test_mb_storage_resolver.bats` must fail because `mb_storage_*` helpers do not exist yet.

**DoD (Definition of Done):**
- [ ] `tests/bats/test_mb_storage_resolver.bats` exists and includes at least 10 named cases covering the scenarios above.
- [ ] Red run fails for missing resolver functionality, not because of syntax errors or missing fixtures.
- [ ] Test names describe business behavior, for example `resolver: global registry maps current project to external bank`.
- [ ] No production files are changed in this stage.
- [ ] Stage can be verified in under 30 seconds with `bats tests/bats/test_mb_storage_resolver.bats`.

**Code rules:** TDD red phase first, Specification by Example, no new dependencies.

---

<!-- mb-stage:2 -->
### Stage 2: Implement agent-agnostic storage resolver in `scripts/_lib.sh`

**What to do:**
- Extend `scripts/_lib.sh` with small focused functions:
  - `mb_agent_config_dir <agent>` returns a supported agent config root.
  - `mb_project_key <project_root>` emits deterministic key from realpath plus optional git remote.
  - `mb_project_id <project_root>` emits safe slug with 12-char hash suffix.
  - `mb_registry_path <agent>` returns `<agent_config_dir>/memory-bank/registry.json`.
  - `mb_registry_lookup <agent> <project_root>` prints registered bank path when present.
  - `mb_resolve_path [explicit]` applies the precedence from Architecture decision.
- Keep functions side-effect free except explicit registry read; registry write belongs to Stage 3.
- Preserve `.claude-workspace` compatibility exactly for existing users.

**Testing (TDD — tests BEFORE implementation):**
- First rerun `bats tests/bats/test_mb_storage_resolver.bats` and confirm failures identify missing functions.
- Implement minimal code until resolver tests pass.
- Add or adjust tests only when a failure reveals an unstated requirement; do not weaken assertions.
- Verification commands:
  - `bats tests/bats/test_mb_storage_resolver.bats`
  - `bats tests/bats/test_context_integration.bats`

**DoD (Definition of Done):**
- [ ] All Stage 1 resolver tests pass.
- [ ] `mb_resolve_path` remains backward-compatible for explicit path and local `.memory-bank/` usages.
- [ ] Invalid registry JSON fails closed: resolver ignores it with a warning and falls back to existing behavior.
- [ ] Paths are normalized; project paths with spaces pass tests.
- [ ] `shellcheck scripts/_lib.sh scripts/mb-context.sh` reports no new warnings.
- [ ] No existing bats test that uses a temp `.memory-bank/` changes its expected behavior.

**Code rules:** SRP for shell helpers, KISS precedence order, backward compatibility, fail closed on corrupt config.

---

<!-- mb-stage:3 -->
### Stage 3: Global init mode in `mb-init-bank.sh`

**What to do:**
- Add CLI flags to `scripts/mb-init-bank.sh`:
  - `--storage=local|global`, default `local`;
  - `--agent=<claude-code|cursor|codex|opencode|pi|windsurf|cline|kilo>`, default auto-detected from `MB_AGENT` or `claude-code` in non-interactive shell scripts;
  - `--project-root=PATH`, default current `$PWD`;
  - keep `--mb-root=PATH` as backward-compatible alias for local mode.
- Add registry write for global mode using Python stdlib JSON with atomic temp-file rename.
- Write `.mb-config` keys inside the bank: `lang`, `storage_mode`, `project_root`, `project_id`, `agent`.
- Refuse unsafe implicit migration: if local bank exists and user requests global mode, print exact migration guidance and exit non-zero without copying data.

**Testing (TDD — tests BEFORE implementation):**
- Add `tests/bats/test_mb_init_storage.bats` before implementation.
- Red tests:
  - `init storage: local remains default and creates project bank`.
  - `init storage: global creates bank under agent config root`.
  - `init storage: global writes registry and no project .memory-bank`.
  - `init storage: local bank blocks global init without force`.
  - `init storage: second global init is idempotent`.
  - `init storage: invalid agent exits 2 with supported list`.
- Verification commands:
  - `bats tests/bats/test_mb_init_storage.bats`
  - `bats tests/bats/test_mb_config.bats`

**DoD (Definition of Done):**
- [ ] `mb-init-bank.sh --help` documents storage flags with concrete examples for local and global modes.
- [ ] Local mode output and file layout remain compatible with existing tests.
- [ ] Global mode creates exactly one external `.memory-bank/` and one registry entry in a sandboxed `$HOME`.
- [ ] Re-running global init for the same project is idempotent and does not duplicate registry entries.
- [ ] Existing local bank is never silently moved, copied, deleted, or overwritten.
- [ ] `shellcheck scripts/mb-init-bank.sh scripts/_lib.sh` reports no new warnings.

**Code rules:** No destructive actions without explicit migration command, idempotency, no new dependencies, atomic writes.

---

<!-- mb-stage:4 -->
### Stage 4: `/mb init` UX and CLI hint update

**What to do:**
- Update `commands/mb.md` `init` section to ask the user explicitly when interactive:
  1. `local` — create `.memory-bank/` inside the project and optionally commit it with the team;
  2. `global` — create personal Memory Bank under the selected agent config directory and keep repository clean.
- Add non-interactive command examples for scripts and CLI:
  - `bash scripts/mb-init-bank.sh --storage=local --lang=ru`.
  - `bash scripts/mb-init-bank.sh --storage=global --agent=pi --project-root "$PWD" --lang=ru`.
- Update `memory_bank_skill/cli.py` `memory-bank init` output to mention `--storage local|global` and the fact that project-local remains default.
- Keep the actual `/mb init --full|--minimal` semantics: storage selection wraps where the bank is created, not which core files are created.

**Testing (TDD — tests BEFORE implementation):**
- Add or extend pytest in `tests/pytest/test_cli.py` for `memory-bank init --storage global --agent pi --project-root <tmp>` output.
- Add bats assertions in `tests/bats/test_install_interactive.bats` or a new `tests/bats/test_mb_init_command_docs.bats` to verify the command docs mention both storage choices and non-interactive examples.
- Red run commands:
  - `pytest -q tests/pytest/test_cli.py -k init`
  - `bats tests/bats/test_mb_init_command_docs.bats`

**DoD (Definition of Done):**
- [ ] User-facing prompt text clearly explains repository impact of both modes in one screen.
- [ ] Non-interactive default remains local; no automated path creates global storage unless a flag/env value says so.
- [ ] CLI help/hint includes exact `local` and `global` examples.
- [ ] Tests assert the wording for repository cleanliness and team-shared local mode.
- [ ] No command doc contains stale claim that active Memory Bank can only be `./.memory-bank/`.

**Code rules:** User choice explicit, backward compatibility, no behavior hidden behind install side effects.

---

<!-- mb-stage:5 -->
### Stage 5: Runtime command docs and active-state semantics

**What to do:**
- Update `commands/start.md`, `commands/plan.md`, `commands/done.md`, `commands/test.md`, and `commands/mb.md` to say: resolve Memory Bank through `mb_resolve_path`; local `.memory-bank/` is one storage mode, not the only active-state signal.
- Update first-response / session-start guidance in `rules/RULES.md`, `rules/CLAUDE-GLOBAL.md`, and `SKILL.md` so future agents distinguish:
  - `[MEMORY BANK: ACTIVE]` when resolved bank exists;
  - `[MEMORY BANK: ABSENT]` when neither local nor registered global bank exists;
  - project-local `.memory-bank/` vs global per-agent bank;
  - **rules-only mode**: when Memory Bank is absent by user choice, global engineering rules (TDD, SOLID, Clean Architecture/FSD, DRY, KISS, YAGNI, Testing Trophy, protected files, no placeholders) still apply to all code work, while Memory Bank lifecycle commands stay opt-in.
- Keep this repo's current local Memory Bank unchanged.

**Testing (TDD — tests BEFORE implementation):**
- Extend `tests/pytest/test_global_prompt_guard.py` to verify global-storage wording in `rules/CLAUDE-GLOBAL.md`, `rules/RULES.md`, and Pi installed prompt.
- Add assertions that `[MEMORY BANK: ABSENT]` does **not** disable TDD/SOLID/Clean Architecture/FSD/DRY/KISS/YAGNI/Testing Trophy rules.
- Add `tests/pytest/test_runtime_contract.py` assertions that `SKILL.md` documents agent-agnostic global storage and does not only reference `.claude-workspace`.
- Verification commands:
  - `pytest -q tests/pytest/test_global_prompt_guard.py tests/pytest/test_runtime_contract.py`
  - `rg -n "only .*\.memory-bank|\[ -d \./\.memory-bank \]" commands rules SKILL.md` returns no active docs that contradict resolver semantics.

**DoD (Definition of Done):**
- [ ] All start/done/plan docs refer to resolved `mb_path`, not hard-coded local-only paths.
- [ ] Prompt guard still preserves mandatory first line behavior and now supports external resolved banks.
- [ ] Rules-only mode is explicit: users may choose no Memory Bank for a project and still get global quality rules.
- [ ] Legacy `.claude-workspace` is documented as backward compatibility, not the recommended new global mode.
- [ ] No code-agent doc tells users to silently initialize a bank when only global install exists.
- [ ] Tests fail if future edits regress to local-only wording.

**Code rules:** SSoT propagation, drift prevention, no contradiction across user-visible surfaces.

---

<!-- mb-stage:6 -->
### Stage 6: Sprint 1 verification and handoff to adapter support

**What to do:**
- Run the focused Sprint 1 suite and then the broad lightweight suite.
- Update the Sprint 2 plan if implementation details discovered during Sprint 1 change adapter requirements.
- Regenerate `.memory-bank/index.json` only after plan/checklist updates if Memory Bank tooling requires it.

**Testing (TDD):**
- Focused verification:
  - `bats tests/bats/test_mb_storage_resolver.bats tests/bats/test_mb_init_storage.bats tests/bats/test_context_integration.bats`
  - `pytest -q tests/pytest/test_cli.py tests/pytest/test_global_prompt_guard.py tests/pytest/test_runtime_contract.py`
- Broad smoke:
  - `pytest -q`
  - `bats tests/bats/test_mb_config.bats tests/bats/test_mb_plan.bats tests/bats/test_plan_sync.bats`

**DoD:**
- [ ] Focused resolver/init/doc tests pass locally.
- [ ] Broad smoke listed above passes or every pre-existing failure is identified with file/test name and not caused by this Sprint.
- [ ] `git diff --stat` shows Sprint 1 changes only: resolver, init, CLI hint, command/rules docs, and associated tests.
- [ ] Sprint 2 plan remains accurate and names every adapter/hook class that still requires global-path support.
- [ ] `/mb verify` can be run against this plan before `/mb done`.

**Code rules:** Verification before completion, no broad refactor outside planned files, update Memory Bank immediately when stages close.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Existing users rely on `.claude-workspace` | Medium | Keep legacy resolver branch and add tests; document it as compatibility path. |
| Global registry accidentally writes into project | Medium | Tests assert no project `.memory-bank/` and no pointer file in global mode. |
| Agent-specific path guesses are wrong | Medium | Put path table in resolver tests and docs; keep `MB_AGENT_CONFIG_DIR` override for advanced users if implementation needs escape hatch. |
| Corrupt registry breaks every command | Medium | Fail closed: warn, ignore registry, fall back to local behavior. |
| Prompt guard becomes ambiguous | Low | Tests assert exact active/absent wording and distinction between global install and project bank activation. |
| Scope creep into migration tooling | High | This Sprint refuses implicit migration; migration can be a later plan after core support ships. |

## Gate (Sprint 1 success criterion)

Sprint 1 is complete when `mb-init-bank.sh` can create either local or registered global Memory Bank in a sandboxed `$HOME`, `mb-context.sh` resolves both modes through `mb_resolve_path`, docs/prompts describe the choice without local-only contradictions, and all focused tests listed in Stage 6 pass.