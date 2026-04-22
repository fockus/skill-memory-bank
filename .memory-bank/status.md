# claude-skill-memory-bank: Статус проекта

## Текущая фаза
**Phase: v3.1.2 released.** Review findings hardening + installer boundary refactor shipped. Два плана закрыты: `review-hardening-installer-boundaries` (7/7 stages) и `core-files-v3-1` (14/15 stages + stage 12 dogfood done). Git tag `v3.1.2`, PyPI `memory-bank-skill==3.1.2`, Homebrew tap bumped, GitHub Release published.

## Завершено 2026-04-21 — v3.1.2 release + plan closures
- ✅ `review-hardening-installer-boundaries` plan: 7/7 stages complete, plans/done/ moved
- ✅ `core-files-v3-1` plan: Stage 12 dogfood (backlog.md migrated to I-NNN/ADR-NNN format, 22 ideas, 11 ADRs), plan closed
- ✅ Git tag `v3.1.2` + commit `beb2f9b`, Homebrew formula sync `197d2eb`
- ✅ PyPI `memory-bank-skill==3.1.2` published via OIDC Trusted Publishing
- ✅ GitHub Release https://github.com/fockus/skill-memory-bank/releases/tag/v3.1.2
- ✅ bats: 526/526, e2e: 75/75, pytest: 246/246, shellcheck: clean, drift-check: 0 warnings

## Завершено раньше 2026-04-21 — Website launch
- ✅ TDD smoke для лендинга: `tests/pytest/test_landing_page.py` сначала RED, затем GREEN
- ✅ Статический сайт в `site/`: hero, problem, workflow, supported agents, install, CTA
- ✅ GitHub Pages включён через REST API в режиме `build_type=workflow`
- ✅ Actions deploy run `24703240655` SUCCESS, live URL отвечает `HTTP/2 200`

## Завершено в rc3
- ✅ `install.sh` byte-level idempotency через `cmp -s` в `install_file()` + новый `install_file_localized()` (compose-to-tmp → `cmp -s dst` → skip или `mv`) + `localize_path_inplace()` helper
- ✅ `backup_if_exists()` расширен опциональным 2-м аргументом `expected_content_path` (возврат `2` на match)
- ✅ `install_cursor_user_rules_paste()` переписан под compose-to-tmp + `cmp -s`
- ✅ Step 7 manifest фильтрует `backups[]` по `os.path.exists`
- ✅ 5 bats-сценариев зелёные: second install = 0, src bump = 1 per changed, external delete = 0, language swap → backup только localize-target files, manifest без stale paths
- ✅ VERSION 3.0.0-rc2 → 3.0.0-rc3 (+ `memory_bank_skill/__init__.py`), CHANGELOG `[3.0.0-rc3]` секция, README FAQ entry, progress.md запись

## Завершено в rc2
- ✅ Cursor global parity: `~/.cursor/skills/memory-bank/` symlink, `~/.cursor/hooks.json` + `~/.cursor/hooks/*.sh` (3 хука с `_mb_owned: true`), `~/.cursor/commands/*.md`, `~/.cursor/AGENTS.md` managed section `memory-bank-cursor:start/end`, `~/.cursor/memory-bank-user-rules.md` paste-file для Settings → Rules → User Rules
- ✅ Fix double `# Global Rules` heading в `adapters/cursor.sh`
- ✅ 17 bats e2e в `tests/e2e/test_cursor_global.bats` + pytest smoke в `tests/pytest/test_cli.py`
- ✅ Docs: SKILL.md (native full support tier + Host-specific notes → Cursor), `docs/cross-agent-setup.md` (supported clients, Cursor раздел, resource matrix, troubleshooting User Rules), `README.md` (Cursor-only quick start + adapter table)
- ✅ CHANGELOG секция `[3.0.0-rc2]` — Added/Fixed + свёрнутый предыдущий Unreleased

Проверено в этом аудите:
- `mb-metrics.sh`: `stack=python`, `src_count=16`, `test_cmd=pytest -q`, `lint_cmd=ruff check .`
- `pytest -q`: **115 passed, 14 skipped**
- `bats tests/bats tests/e2e`: **368/368 ok**
- `ruff check .`: **All checks passed!**
- `python3 -m build`: успешно собраны `dist/memory_bank_skill-3.0.0rc1.tar.gz` и `dist/memory_bank_skill-3.0.0rc1-py3-none-any.whl`
- `pipx` smoke в clean temp-env: `pipx install --force dist/memory_bank_skill-3.0.0rc1-py3-none-any.whl` → ok; `memory-bank version` → `memory-bank-skill 3.0.0-rc1`; `memory-bank doctor` корректно резолвит bundle root из `pipx` shared-data; `memory-bank self-update` печатает `pipx upgrade memory-bank-skill`
- Homebrew smoke: local path formula больше невалидна на Homebrew 5, поэтому проверка выполнена через реальный user-path `brew tap fockus/tap && brew install fockus/tap/memory-bank`; затем `memory-bank version` и `memory-bank doctor` → ok; cleanup выполнен через `brew uninstall memory-bank` и `brew untap fockus/tap`
- `VERSION`: **3.0.0-rc2** (корневой `VERSION`, синхронизирован с `memory_bank_skill/__init__.py`)
- Hardening update 2026-04-20: targeted Codex/installer regression suite зелёная:
  - `pytest -q tests/pytest/test_merge_hooks.py tests/pytest/test_index_json.py tests/pytest/test_import.py tests/pytest/test_runtime_contract.py` → **65/65 passed**
  - `bats tests/bats/test_codex_adapter.bats tests/e2e/test_install_clients.bats tests/e2e/test_install_uninstall.bats` → **46/46 passed**

Three-in-one skill: (1) long-term project memory через `.memory-bank/`, (2) global dev rules, (3) dev toolkit из 18 команд.

## Ключевые метрики
- Shell-скрипты: **14**, Python-скрипты: **4**, Агенты: **4**, Команды: **18**
- Client adapters: **7** (`cursor`, `windsurf`, `cline`, `kilo`, `opencode`, `pi`, `codex`) + **2** shared adapter helpers
- Tests: **bats 526/526**, **e2e 75/75**, **pytest 246/246**, shellcheck: 0 warnings
- VERSION: **3.1.2** (PyPI `memory-bank-skill==3.1.2`, Homebrew tap bumped)
- Public website: **https://fockus.github.io/skill-memory-bank/**
- Текущий remote: `origin=https://github.com/fockus/skill-memory-bank.git`

## Roadmap

### ✅ v2.0.0 (released)
- Базовый refactor завершён, план перенесён в `plans/done/`
- Language-agnostic stack detection, CI и TDD-based workflow внедрены

### ✅ v2.1.0 (released)
- Auto-capture, drift checkers, `<private>...</private>`, compaction decay реализованы и задокументированы

### 🔄 v2.2 → v3.0-rc1 (в работе)
- Этапы 5-8 по `checklist.md` реализованы
- Stage 8.5 выполнен частично: migration на `skill-memory-bank` отражена в `origin`, `README.md`, `CHANGELOG.md`, но старый repo/archive/release continuity ещё не закрыты полностью
- Stage 9 выполнен частично: `pyproject.toml`, `memory_bank_skill/`, publish workflow, Homebrew formula template и install docs уже есть; verification и release smoke зелёные, не закрыты только final release chores
- Codex hardening выполнен: canonical source `~/.claude/skills/skill-memory-bank`, symlink aliases для Claude/Codex, managed `~/.codex/AGENTS.md`, полный bundle ресурсов (`commands/`, `agents/`, `hooks/`, `scripts/`, `references/`, `rules/`)
- Verification hardening закрыт: `tests/pytest/test_codegraph_ts.py` корректно skip'ает Stage 6.5 при неполном наборе tree-sitter language bindings, поэтому `pytest -q` теперь стабильно проходит в разных Python environments

### ⬜ v3.0 final release
- Release smoke подтверждён: clean-environment `pipx`, real-path Homebrew tap install и `memory-bank self-update` работают
- Public GitHub Pages landing запущен и доступен пользователям
- Довести migration/release chores до конца и выпустить `3.0.0`

### ⬜ v3.1+ backlog
- Benchmarks (LongMemEval + custom scenarios)
- sqlite-vec semantic search
- i18n error-сообщений
- Native memory bridge
- Viewer dashboard

## Gate v2 — passed ✅
1. ✅ Language coverage: 12 стеков
2. ✅ Cross-platform CI добавлен
3. ✅ Legacy `Task(` убран, coexistence documented
4. ✅ `_lib.sh` и базовые тестовые контуры внедрены
5. ✅ Skill dogfooding через `.memory-bank/` включён

## Gate v2.1 — passed ✅
1. ✅ Auto-capture реализован
2. ✅ `mb-drift.sh` реализован и dogfooding-checked
3. ✅ PII redaction через `<private>` реализована
4. ✅ `/mb compact` реализован
5. ✅ Исторический release `v2.1.0` отражён в CHANGELOG/checklist

## Gate v2.2 — implementation done, formal release skipped
- ✅ Этапы 5-7 реализованы в репозитории
- ✅ Текущая verification на рабочем дереве зелёная
- ⬜ Отдельный formal cut `v2.2.0` не подтверждён; ветка фактически ушла сразу к `3.0.0-rc1`

## Gate v3.0 — in progress
- ✅ 7 adapters присутствуют в кодовой базе и документации
- ✅ Repo migration на `fockus/skill-memory-bank` отражена в remote/docs
- ✅ `3.0.0-rc1` уже зафиксирован в `VERSION` и `CHANGELOG.md`
- ✅ `pytest` green на текущем дереве: `115 passed, 14 skipped`
- ✅ Полный bats/e2e re-audit зелёный: `368/368 ok`
- ✅ `ruff` clean на текущем дереве: `All checks passed!`
- ✅ `pipx install` из clean env работает
- ✅ `brew install fockus/tap/memory-bank` работает
- ✅ `memory-bank self-update` работает как documented wrapper (`pipx upgrade memory-bank-skill`)
- ⬜ Финальный `3.0.0` tag / GitHub Release / VERSION bump / release continuity / Anthropic plugin status не закрыты

## Известные ограничения
- Stage 6.5 остаётся optional dependency path: без полного набора tree-sitter language bindings TS/JS/Go/Rust/Java coverage корректно skip'ается, а не тестируется
- Homebrew 5 не принимает local path formula для полноценного smoke: для реальной проверки нужен tap-based install path
- Final release choreography ещё не завершена, поэтому `3.0.0` readiness пока не закрыта полностью

## Решённые вопросы
- ✅ Pi Code остаётся adapter'ом Stage 8; Codex добавлен как 7-й adapter через ADR-010
- ✅ Distribution strategy: pipx/PyPI primary, Homebrew secondary, Anthropic plugin tertiary
- ✅ Benchmarks перенесены в v3.1+ backlog

## Open questions
1. Нужно ли доводить отдельный formal `v2.2.0`, или считать его absorbed в `3.0.0-rc1`?
2. Когда архивировать старый `claude-skill-memory-bank` repo и переносить historical releases?
3. Anthropic plugin manifest остаётся обязательным для Gate v3.0 или уже de-scoped до post-release?

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Recently done

<!-- mb-recent-done -->
- 2026-04-21 — [plans/done/2026-04-21_refactor_core-files-v3-1.md](plans/done/2026-04-21_refactor_core-files-v3-1.md) — refactor — core-files-v3-1
- 2026-04-21 — [plans/done/2026-04-21_refactor_review-hardening-installer-boundaries.md](plans/done/2026-04-21_refactor_review-hardening-installer-boundaries.md) — refactor — review-hardening-installer-boundaries
- 2026-04-21 — [plans/done/2026-04-21_refactor_agents-quality.md](plans/done/2026-04-21_refactor_agents-quality.md) — refactor — agents-quality
<!-- /mb-recent-done -->
