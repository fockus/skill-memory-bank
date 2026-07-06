---
type: fix
scope: install-and-cross-agent-parity
created: 2026-07-04
status: queued
priority: CRITICAL
backlog: I-088
source: "audit 2026-07-04 — Claude install-audit + parity-audit + Codex gpt-5.5 cross-review (parity DONE + install received 2026-07-04; дельта: B7-B9, C5-C6, A17-A25, C7)"
verified: "все находки подтверждены по коду на указанных file:line; C-1 и H-2 доказаны end-to-end в чистом venv; F-2 подтверждена вручную"
related_plans:
  - path: 2026-07-04_fix_session-capture-and-mb-hygiene.md
    boundary: "Track A (capture-format correctness) там. Здесь — только adapter-wiring паритета capture (B4/B5). НЕ дублировать формат bullet'ов/caps/summarize."
  - path: 2026-07-04_feature_code-graph-activation.md
    boundary: "Graph freshness/delivery/routing там. Здесь — только корректность установки Pi native-tool extension (B1/F-2). Смежно, не пересекается."
---

# Fix: Install reliability + cross-agent parity

Закрывает находки двух аудитов от **2026-07-04** (backlog **I-088**):
**install-audit** (ставится ли скилл без проблем через pipx/pip/brew на всех целях)
и **parity-audit** (одинаково ли работают Claude Code / Codex / Pi / OpenCode / Cursor).
Все находки верифицированы по коду на указанных `file:line`. **C-1** и **H-2** доказаны
end-to-end в чистом venv; **F-2** подтверждена вручную. Codex cross-review в процессе — план
может получить дельту (новые этапы допишутся хвостом, нумерация не переиспользуется).

Три трека:
- **Track A — Install reliability**: пакет должен ставиться без затирания пользовательских
  файлов, без падений на worktree/pipx/sudo, с восстановимым uninstall.
- **Track B — Cross-agent parity**: Codex/Pi/OpenCode/Cursor получают слэш-команды, агентов,
  session-capture и рабочие native-tools наравне с Claude Code (в пределах платформенных лимитов).
- **Track C — Docs + tests**: доки приведены в соответствие реальности; закрыты тестовые дыры
  (e2e `/mb init` против wheel, upgrade vN→vN+1, runtime-паритет).

## Goal

После этой работы: (1) `pipx install memory-bank-skill && memory-bank init` завершается **exit 0**
на чистой машине (сейчас **exit 3** — templates не в wheel); (2) ни один адаптер не затирает
пользовательский конфиг/хук без бэкапа и атомарной записи; (3) Homebrew-формула ставит **актуальную**
версию; (4) Codex получает `/mb` как промпты, OpenCode — 29 агентов, Pi — синтаксически валидный
GraphRAG-extension с подставленными путями; (5) доки не обещают несуществующих фич; (6) есть тесты,
ловящие эти классы багов на упакованном артефакте, а не только на дереве репозитория.

## Scope

### Входит
- Упаковка `templates/` (+`flow-templates/`) в wheel `shared-data` и sdist include (C-1).
- Backup + merge/atomic-write во всех адаптерах, затирающих юзерские файлы (C-2, H-3, H-4, M-5, M-8).
- Homebrew bump + CI-инвариант «формула == VERSION» (H-1).
- Portable `${MB_PYTHON:-python3}` + однократный install-global (H-2).
- Инкрементальный/атомарный манифест + восстановимый uninstall всех клиентов (H-5, M-1, M-4).
- Portability-фиксы: `git rev-parse --git-dir` вместо `[ -d .git ]`, BSD-mktemp, quoting (H-7, M-6, M-7).
- Codex prompts, OpenCode agents, OpenCode skill-alias, Pi extension-подстановка (F-1, F-2, F-3, A-1).
- Adapter-wiring session-capture паритета (Cursor→`mb-session-end.sh`, Codex git-hooks-fallback) (F-4, F-5).
- Doc-vs-reality правки (D-1…D-6, M-3, L-1, L-6) + git-hygiene (L-7).
- Тесты: e2e `/mb init` против wheel, upgrade vN→vN+1, runtime-паритет (placeholder/capture/gates).

### НЕ входит
- **Формат session-capture** (bullets/caps/summarize) — это `2026-07-04_fix_session-capture-and-mb-hygiene.md`
  (Track A). Здесь только **какой** capture-скрипт вешает каждый адаптер, не **что** он пишет.
- **Graph freshness/delivery/routing** — это `2026-07-04_feature_code-graph-activation.md`.
  Здесь только корректность **установки** Pi native-tool extension (подстановка плейсхолдеров).
- Платформенные лимиты, которые нельзя закрыть кодом (P-1 statusline только CC [✅ подтверждён двумя моделями как platform-limit]; P-2 governed
  subagent-dispatch вне CC; P-3 Cursor User Rules) — по ним только честная деградация + доки.
- Новые библиотеки/фреймворки; смена дефолтных флагов на «on»; редизайн query-семантики.

## Assumptions
- `templates/` и `flow-templates/` — статические файлы; их достаточно доставить в bundle-дерево
  (`share/memory-bank-skill/…`), `mb-init-bank.sh:42` резолвит `REPO_ROOT=$SCRIPT_DIR/..` = корень
  bundle, поэтому `templates/locales/**` встанет на место без изменения кода резолвинга.
- Целевые агенты и их пути: `~/.codex/prompts/`, `.opencode/agent/*.md`, `.pi/extensions/*.ts` —
  подтверждены существующим кодом (`install.sh:848-853`, `opencode.sh:152-186`, `pi.sh:163-173`).
- Все изменяемые shell-файлы обязаны работать на bash 3.2 (macOS) И 5.x (Linux).
- CI гоняет `bats tests/bats/`, `bats tests/e2e/`, `pytest tests/pytest/` (`.github/workflows/test.yml:44-52`);
  новые e2e-тесты кладём в `tests/e2e/`, unit — в `tests/bats/` / `tests/pytest/`.
- `.venv` присутствует; bats/shellcheck/`python -m build` доступны (проверено).
- Codex cross-review может добавить/переклассифицировать находки → это допустимая дельта, не блокер.

## Constraints (apply by construction)
- **TDD-first**: КАЖДЫЙ этап пишет падающий тест ПЕРВЫМ (bats/pytest, доказывающий баг), затем фикс
  делает его зелёным. Нет фикс-коммита без предшествующего red-теста.
- **Backup-before-overwrite invariant**: любой адаптер, пишущий в путь, который мог создать
  пользователь, обязан: (a) `backup_if_exists` до записи, (b) писать через `tmp + mv` (атомарно),
  (c) для конфигов — merge только СВОИХ ключей, не затирать чужие. Первый истинный бэкап юзера
  никогда не перетирается ротацией.
- **Fail-open hooks/installers**: ошибка (нет dep, не резолвится bank, bad stdin) → инсталлятор/хук
  не должен ронять весь установочный прогон беззвучно; частичный сбой обязан оставлять восстановимый
  манифест (H-5).
- **Dual-shell**: bash 3.2 + 5.x. Никаких `mapfile`/`declare -A` в hot-path/`${var^^}`; `case`/`printf`/`awk`.
- **File budget**: ни один файл > 400 строк после правки; общий код выносить в существующие
  `adapters/_framework.sh` / `adapters/_lib_agents_md.sh`.
- **No placeholders**: copy-paste-ready, без TODO/`...`/pseudocode.
- **Static analysis**: `shellcheck` clean на каждом изменённом shell-файле; `ruff`/`black` clean на
  любом изменённом Python.

## Риски

| Риск | Вероятность | Impact | Mitigation |
|------|-------------|--------|------------|
| Merge-конфликты в `install.sh` (6 этапов трогают его) | Высокая | Med | Серилизовать install.sh-этапы (см. § Merge conflicts); один writer за раз |
| Config-merge (codex TOML / opencode JSON) сломает валидный конфиг юзера | Средняя | High | Merge только known-keys; тест с реальным пользовательским конфигом «чужие ключи целы» |
| Bump Homebrew до релиза, где sha256 ещё не на PyPI | Средняя | Med | H-1 ставит CI-инвариант «formula==VERSION», bump выполняется в release-лейне; до релиза допустим `head`/локальный url |
| F-2 подстановка путей ломает `.ts` при пробелах/кавычках в $HOME | Средняя | High | Подставлять JSON-encoded путь (не сырой); тест с $HOME с пробелом |
| Codex cross-review переклассифицирует находку после старта | Средняя | Low | Дельта дописывается хвостом; ID-этапов не переиспользуются |
| Изменение capture-wiring (B4/B5) пересечётся с session-capture планом | Средняя | Med | Явная граница в frontmatter; B4/B5 меняют ТОЛЬКО какой скрипт вешается, не его тело |

## Track ordering (приоритет)

**Phase 0 — MUST-FIX gate «ставится без проблем»** (блокирует всё остальное по смыслу):
`A1 (C-1)` · `A2 (C-2)` · `A3 (H-1)` · `A4 (H-2)` · `B1 (F-2)`.
**Phase 1 — Track A HIGH** → **Phase 2 — Track A MED/LOW** → **Phase 3 — Track B parity** →
**Phase 4 — Track C docs+tests**. Внутри фаз этапы независимых файлов идут параллельно;
`install.sh`/`cursor.sh`-этапы серилизованы (см. § Merge conflicts).

---

# Track A — Install reliability

<!-- mb-stage:1 -->
## Этап A1 — C-1: templates/ (+flow-templates/) в wheel + sdist + e2e `/mb init` (CRITICAL, must-fix)
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester для red)
**Файлы:** `pyproject.toml` (edit `[tool.hatch.build.targets.wheel.shared-data]` + `[…sdist].include`),
`tests/e2e/test_pipx_install.bats` (extend, тест FIRST),
`tests/pytest/test_wheel_ships_templates.py` (new, тест FIRST)

**Confirmed:** `pyproject.toml:66-124` перечисляет `adapters/agents/commands/hooks/rules/scripts/references/settings/docs`,
но **не `templates`** и **не `flow-templates`**. `mb-init-bank.sh:179-183` читает
`$REPO_ROOT/templates/locales/$LANG/.memory-bank`; `REPO_ROOT=$SCRIPT_DIR/..` (`:42`) = корень bundle.
На pipx/pip дерево `templates/` отсутствует → `exit 3` «missing template bundle». `templates/` содержит
`locales/`, `.memory-bank/`, `goal.md`, `handoff.md`, `project.md`; `flow-templates/` содержит
`patterns/` + 5 route-шаблонов (потребляются flow-routing + pytest). Существующий
`tests/e2e/test_pipx_install.bats` доходит только до `doctor` (`:44-51`), `/mb init` не проверяет.

### Задачи:
1. **Тест FIRST** `tests/pytest/test_wheel_ships_templates.py`: `python -m build --wheel --sdist`
   во временный outdir → распаковать (`zipfile` для whl, `tarfile` для sdist) → assert присутствуют
   `share/memory-bank-skill/templates/locales/en/.memory-bank/status.md` и
   `share/memory-bank-skill/flow-templates/patterns/` (в sdist — `templates/` и `flow-templates/`).
2. **Тест FIRST** `tests/e2e/test_pipx_install.bats` (+2 case): после `build_and_install` создать
   temp project (`git init`), `"$VENV_DIR/bin/memory-bank" init --project-root "$P"` (или
   `mb-init-bank.sh` из venv share) → assert exit 0 и `$P/.memory-bank/status.md` существует;
   негатив: до фикса ожидается exit 3.
3. **Fix** `pyproject.toml`: в `[tool.hatch.build.targets.wheel.shared-data]` добавить
   `"templates" = "share/memory-bank-skill/templates"` и `"flow-templates" = "share/memory-bank-skill/flow-templates"`;
   в `[tool.hatch.build.targets.sdist].include` — `"/templates"` и `"/flow-templates"`;
   в `[tool.hatch.build].include` — `"templates/**/*"`, `"flow-templates/**/*"`.

### DoD:
- [x] Built wheel содержит `share/memory-bank-skill/templates/locales/en/.memory-bank/*` и `flow-templates/patterns/*`.
- [x] sdist содержит `templates/` и `flow-templates/`.
- [x] В чистом venv `memory-bank init` → **exit 0**, `.memory-bank/status.md` создан (было exit 3).
- [x] Тесты: 1 pytest (wheel+sdist) + 2 bats e2e; оба RED→GREEN.
- [x] `ruff` clean на новом pytest.

### Тестовые сценарии:
- `test_wheel_ships_templates_locales` — распакованный whl содержит templates+flow-templates.
- `test_sdist_ships_templates` — sdist tar содержит оба дерева.
- `pipx-like install: memory-bank init scaffolds bank exit 0` — e2e init против venv.

### Команды проверки:
```bash
cd /Users/fockus/Apps/skill-memory-bank
python -m pytest tests/pytest/test_wheel_ships_templates.py -q
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_pipx_install.bats
# ручная проверка упаковки:
python3 -m build --wheel --outdir /tmp/mb-whl >/dev/null && unzip -l /tmp/mb-whl/*.whl | grep -E 'templates/(locales|patterns)'
```
### Edge cases:
локаль `ru` (проверить `templates/locales/ru/`); `flow-templates/` реально нужен flow-routing —
не забыть его, иначе route-шаблоны отсутствуют на pipx; wheel glob `templates/**/*` включает скрытые
`.memory-bank` поддиректории (hatch include с `**` их берёт — проверить в тесте).

---

<!-- mb-stage:2 -->
## Этап A2 — C-2: codex.sh backup + merge config.toml/hooks.json (CRITICAL, must-fix)
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/codex.sh` (edit `install_codex` + `config_toml_body`/`hooks_json_body` call-sites),
`tests/bats/test_codex_adapter.bats` (extend, тест FIRST)

**Confirmed:** `codex.sh:103` `config_toml_body > "$CONFIG_TOML"` и `:106` `hooks_json_body > "$HOOKS_JSON"` —
безусловная перезапись. Если у юзера уже есть `~/.codex/config.toml` (модель, ключи) или `hooks.json`,
они **затираются без бэкапа и без merge**. В репозитории есть `backup_if_exists`/`agents_md_install`
(`adapters/_lib_agents_md.sh`) и manifest-`backups` — паттерн бэкапа уже существует.

### Задачи:
1. **Тест FIRST** `test_codex_adapter.bats`:
   - `test_codex_backs_up_existing_config_toml` — seed `$HOME/.codex/config.toml` с маркерной строкой
     `user_key = "keep"` → install → assert бэкап-файл существует И содержит `user_key = "keep"`.
   - `test_codex_merge_preserves_foreign_keys` — тот же seed → после install `config.toml` СОДЕРЖИТ
     `user_key = "keep"` И MB-секцию.
   - `test_codex_hooks_json_backed_up` — seed `hooks.json` → бэкап создан.
2. **Fix** `codex.sh`: перед записью — `backup_if_exists "$CONFIG_TOML"` / `backup_if_exists "$HOOKS_JSON"`
   (регистрировать в manifest `backups`); для `config.toml` — вставлять/обновлять только MB-блок между
   парными маркерами `# >>> memory-bank >>>` / `# <<< memory-bank <<<` (idempotent upsert через awk),
   для `hooks.json` — merge через `jq` (свои ключи в существующий объект), с `tmp+mv`.

### DoD:
- [x] Существующий `config.toml`/`hooks.json` бэкапится до записи; путь бэкапа в manifest `backups`.
- [x] Чужие ключи юзера сохранены после install (merge, не overwrite).
- [x] Повторный install идемпотентен (нет дублей MB-блока).
- [x] Тесты: 3 bats RED→GREEN (по факту 33/33); `shellcheck adapters/codex.sh` clean.
- [ ] файл ≤400 строк — ⚠️ НЕ выполнено: 439 строк (safety-комментарии из 2 раундов ревью). Backlog R-1 ниже: вынести merge/backup/strip в `adapters/_lib_codex_config.sh`.

### Тестовые сценарии:
- `test_codex_merge_preserves_foreign_keys` — foreign TOML key survives.
- `test_codex_backs_up_existing_config_toml` — backup captured.
- `test_codex_install_idempotent_no_dup_block` — second install ⇒ один MB-блок.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_codex_adapter.bats
shellcheck adapters/codex.sh
```
### Edge cases:
пустой/битый существующий TOML (не падать — бэкап + свежий MB-блок); `hooks.json` не-JSON (jq
fail → бэкап + записать свой, не молча терять); `.codex/` отсутствует (mkdir -p сохранить).

---

<!-- mb-stage:3 -->
## Этап A3 — H-1: Homebrew bump до VERSION + CI-инвариант «formula == VERSION» (HIGH, must-fix)
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `packaging/homebrew/memory-bank.rb` (edit url/sha256/`depends_on python`),
`tests/pytest/test_homebrew_formula_version.py` (new, тест FIRST), `.github/workflows/test.yml` (add step)

**Confirmed:** `memory-bank.rb:7-8` прибит к `3.1.2` (url + sha256), `:12` `depends_on "python@3.12"`,
при `VERSION=5.2.0`. `brew install` ставит древнюю версию. Нет CI-чека соответствия.

### Задачи:
1. **Тест FIRST** `tests/pytest/test_homebrew_formula_version.py`: прочитать `VERSION`, распарсить в
   `.rb` `url` (regex `memory_bank_skill-(?P<v>[0-9.]+)\.tar\.gz`) → assert `== VERSION`.
2. **Fix** `.rb`: обновить `url` на `…memory_bank_skill-5.2.0.tar.gz`; `sha256` — плейсхолдер-контракт:
   документировать, что оба поля обновляются в release-лейне (`brew bump-formula-pr`); версию url
   привести к VERSION сейчас (sha будет валиден после PyPI-публикации 5.2.0).
3. **CI**: в `test.yml` добавить step, запускающий новый pytest (он уже попадёт в `pytest tests/pytest/`,
   но добавить явный assert в job, чтобы падал на version-drift).

### DoD:
- [x] `url` в формуле = `VERSION` (5.2.0).
- [x] pytest падает, если формула ≠ VERSION (RED на 3.1.2, GREEN после bump).
- [x] CI гоняет этот инвариант (в `pytest tests/pytest/`).
- [x] `ruff` clean.

### Тестовые сценарии:
- `test_homebrew_formula_url_matches_version` — url-версия == VERSION.

### Команды проверки:
```bash
python -m pytest tests/pytest/test_homebrew_formula_version.py -q
```
### Edge cases:
url с `+`-суффиксом/pre-release (regex толерантен к `[0-9.]+`); `python@3.12` vs проектное
требование >=3.11 — оставить 3.12 (ок), но задокументировать min в M-3.

---

<!-- mb-stage:4 -->
## Этап A4 — H-2: portable `${MB_PYTHON:-python3}` в cursor.sh + однократный install-global (HIGH, must-fix)
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/cursor.sh:84-87` (edit `run_texttool`), `install.sh:859` (gate install-global),
`tests/bats/test_cursor_adapter.bats` (extend, тест FIRST)

**Confirmed:** `cursor.sh:85-86` — голый `python3 -m memory_bank_skill._texttools` вместо
`${MB_PYTHON:-python3}` → на pipx (изолированный venv) `ModuleNotFoundError`. `install.sh:859` зовёт
`cursor.sh install-global` при **каждой** установке (лишняя работа/потенциальный clobber).

### Задачи:
1. **Тест FIRST** `test_cursor_adapter.bats`: `test_cursor_texttool_honors_MB_PYTHON` — установить
   `MB_PYTHON=/custom/python`, вызвать функцию/скрипт, перехватить исполняемое имя (stub на PATH) →
   assert используется `MB_PYTHON`, не голый `python3`.
2. **Fix** `cursor.sh:85`: `PYTHONPATH=… "${MB_PYTHON:-python3}" -m memory_bank_skill._texttools "$@"`.
   Проверить остальные вызовы `python3` в cursor.sh — все привести к `${MB_PYTHON:-python3}`.
3. **Fix** `install.sh:859`: обернуть install-global в guard (напр. по наличию global-маркера/версии),
   чтобы не выполнять при каждом прогоне; идемпотентность через существующий refcount/manifest.

### DoD:
- [x] `run_texttool` использует `${MB_PYTHON:-python3}` (нет голых `python3` в cursor.sh).
- [x] install-global не выполняется повторно без нужды (idempotent guard `_cursor_global_up_to_date`, сверяет skill_version+lang).
- [x] Тесты: 1+ bats RED→GREEN; `shellcheck adapters/cursor.sh install.sh` clean.

### Тестовые сценарии:
- `test_cursor_texttool_honors_MB_PYTHON` — кастомный интерпретатор уважается.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_cursor_adapter.bats
shellcheck adapters/cursor.sh
grep -n "python3" adapters/cursor.sh   # ожидание: только ${MB_PYTHON:-python3}
```
### Edge cases:
`MB_PYTHON` с пробелом в пути (кавычки); `MB_PYTHON` невалидный — fail с внятной ошибкой, не молча;
install-global на повторном прогоне другой версии — guard должен позволить re-install при version bump.

---

<!-- mb-stage:5 -->
## Этап A5 — H-3: opencode.sh backup + атомарная запись opencode.json (HIGH)
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/opencode.sh:122-134` (edit), `tests/bats/test_opencode_adapter.bats` (extend, FIRST)

**Confirmed:** `opencode.sh:122-134` переписывает/удаляет пользовательский `opencode.json` без бэкапа,
неатомарно; при не-MB ключах может удалить файл.

### Задачи:
1. **Тест FIRST** `test_opencode_adapter.bats`: `test_opencode_backs_up_and_preserves_foreign_keys` —
   seed `opencode.json` с `"theme":"custom"` → install → бэкап есть, `theme` цел, MB-ключи добавлены.
2. **Fix**: `backup_if_exists`; merge через `jq` (свои ключи), `tmp+mv`; **не удалять** файл, если
   в нём есть не-MB ключи (только убрать свои при uninstall).

### DoD:
- [x] `opencode.json` бэкапится (once, regular-file-verified); чужие ключи сохранены; запись атомарна (`mktemp+mv`, mode-preserving); битый JSON не затирается.
- [x] Файл не удаляется при наличии не-MB ключей.
- [x] Тесты: 5 bats RED→GREEN (backup/foreign-keys/broken-json/idempotent/glob-false-positive/mode); `shellcheck` 0 new.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_opencode_adapter.bats
shellcheck adapters/opencode.sh
```
### Edge cases:
битый JSON (jq fail → бэкап + свежий); отсутствующий файл (создать чистый); пустой `{}`.

---

<!-- mb-stage:6 -->
## Этап A6 — H-4: ротация бэкапов не уничтожает оригинал юзера (HIGH)
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `install.sh:327-331,349` (`install_file`/rotation), `adapters/cursor.sh:283-314,592-601`,
`tests/e2e/test_install_uninstall.bats` (extend, FIRST) или `tests/bats/test_upgrade.bats`

**Confirmed:** ротация бэкапов при апгрейде перетирает первый истинный бэкап пользователя контентом
предыдущей установки MB (`install.sh:327-331`, `install_file:349`; `cursor.sh:283-314,592-601`) →
после нескольких апгрейдов оригинал юзера потерян.

### Задачи:
1. **Тест FIRST**: seed юзерский файл `X` (маркер `USER_ORIGINAL`) → install v1 → install v2 →
   assert существует бэкап, содержащий `USER_ORIGINAL` (истинный первый бэкап не потерян).
2. **Fix**: ротировать только **свой** (MB-generated) контент; первый бэкап пользовательского
   контента маркировать (`.mb-orig` суффикс) и никогда не перетирать; проверять «это уже наш файл?»
   по MB-маркеру перед бэкапом.

### DoD:
- [x] После двух апгрейдов истинный первый бэкап юзера сохранён (oldest никогда не ротируется; install.sh `backup_if_exists` + cursor.sh `global_backup_if_exists`); backup-имя `.$(date +%s).$$` устойчиво к коллизии timestamp.
- [x] Ротация трогает только MB-generated бэкапы (оригинал re-record в манифест для корректного restore).
- [x] Тесты: 1 e2e RED→GREEN (RULES.md upgrade preserves true original); `shellcheck` 0 new.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_uninstall.bats tests/bats/test_upgrade.bats
shellcheck install.sh adapters/cursor.sh
```
### Edge cases:
файл, который юзер не трогал (MB-generated с прошлой версии → ротировать нормально); коллизия имён
бэкапов при том же timestamp (использовать инкремент/pid).

---

<!-- mb-stage:7 -->
## Этап A7 — H-5: инкрементальный/атомарный манифест + trap на частичный сбой (HIGH) — ✅ подтверждено двумя моделями (манифест пишется поздно)
**Complexity:** M · **~5 мин** · **Зависимости:** A6 (общий install.sh writer) · **Агент:** developer (+ tester)
**Файлы:** `install.sh:900-931` + адаптеры (codex:116/opencode:178/cursor:547/cline:199/kilo:76/windsurf:183/pi:148),
`tests/e2e/test_install_uninstall.bats` (extend, FIRST)

**Confirmed:** манифест пишется **последним** шагом (`install.sh:895-933` step 7; адаптеры пишут свой в
конце `install_*`). При сбое до этого шага uninstall не имеет что откатывать → мусор + невосстановимо.

### Задачи:
1. **Тест FIRST**: смоделировать сбой install после части файлов (inject fail в середину) → запустить
   uninstall → assert установленные до сбоя файлы удалены/бэкапы восстановлены (сейчас — остаются).
2. **Fix**: писать манифест **инкрементально** (регистрировать каждый installed/backup сразу) ИЛИ
   поставить `trap 'flush_manifest' ERR EXIT`, сбрасывающий накопленные `INSTALLED_FILES`/`BACKED_UP_FILES`
   в манифест при любом выходе. Атомарно (`tmp+mv`).

### DoD:
- [x] Частичный сбой оставляет валидный манифест с уже сделанными операциями (`trap _mb_on_exit EXIT` → `flush_manifest`, атомарно `mkstemp`+`os.replace`, идемпотентно через `MB_MANIFEST_FLUSHED`, exit-код сбоя сохранён).
- [x] `uninstall` откатывает частичную установку (манифест `files`+`backups` пишется даже при сбое до Step 7). Env-seam `MB_MANIFEST_PATH` для sandbox-изоляции тестов.
- [x] Тесты: 1 e2e RED→GREEN (poison Step 2 → манифест с ≥1 файлом); `shellcheck` 0 new.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_uninstall.bats
shellcheck install.sh
```
### Edge cases:
двойной trap (ERR+EXIT) не должен писать манифест дважды; сбой во время самого flush (best-effort,
не зацикливать); совместимость `schema_version:1`.

---

<!-- mb-stage:8 -->
## Этап A8 — H-6: cline.sh детект файловой формы `.clinerules` (HIGH)
**Complexity:** S · **~3 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/cline.sh:157` (edit), `tests/bats/test_cline_adapter.bats` (extend, FIRST)

**Confirmed:** `cline.sh:157` делает `mkdir -p` на `.clinerules`, который может быть **файлом** (Cline
поддерживает и файл, и директорию) → `mkdir` падает «Not a directory».

### Задачи:
1. **Тест FIRST** `test_cline_adapter.bats`: `test_cline_handles_clinerules_as_file` — seed `.clinerules`
   как обычный файл → install → **exit 0** (сейчас падает).
2. **Fix**: перед `mkdir -p` проверить `[ -f "$P/.clinerules" ]` → работать в файловой форме (append/merge
   в файл) вместо директории; если директория/отсутствует — прежний путь.

### DoD:
- [x] install не падает при `.clinerules`-файле; MB-контент добавлен корректно для обеих форм (маркер-блок + sibling-манифест); idempotent, symlink-chain-safe, byte-exact round-trip, mode-preserving.
- [x] Тесты: 5 bats RED→GREEN (file-form/uninstall/blank-accum/symlink/multi-hop/byte-exact/mode); `shellcheck` 0 new.
- [x] file-form backup safety-net + both-marker gate (R2a-1 закрыт в Batch 2b): `_cline_backup_once` перед любой перезаписью + strip только при ПАРНЫХ маркерах (повреждённый END не срезает до EOF). +2 bats.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_cline_adapter.bats
shellcheck adapters/cline.sh
```
### Edge cases:
`.clinerules` — симлинк; директория с уже существующим MB-файлом (идемпотентность).

---

<!-- mb-stage:9 -->
## Этап A9 — H-7: `git rev-parse --git-dir` вместо `[ -d .git ]` (worktree/submodule) (HIGH)
**Complexity:** S · **~3 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/kilo.sh:37`, `adapters/git-hooks-fallback.sh:81`,
`tests/bats/test_kilo_adapter.bats` + `tests/bats/test_git_hooks_fallback.bats` (extend, FIRST)

**Confirmed:** `[ -d .git ]` (`kilo.sh:37`, `git-hooks-fallback.sh:81`) ложно в git-worktree/submodule,
где `.git` — файл-указатель, не директория → git-фичи молча не ставятся.

### Задачи:
1. **Тест FIRST** (обе suites): `test_*_detects_git_in_worktree` — создать `git worktree add` →
   assert адаптер определяет репо и ставит git-часть (сейчас — нет).
2. **Fix**: заменить `[ -d .git ]` на `git rev-parse --git-dir >/dev/null 2>&1` (учёт core.hooksPath
   для fallback — использовать `git rev-parse --git-path hooks`).

### DoD:
- [x] Оба скрипта корректно детектят репо в worktree (`.git`-файл) + honor `core.hooksPath`; repo-root guard (`--show-toplevel`==PROJECT_ROOT) отвергает вложенный non-root subdir.
- [x] Тесты: 4 bats RED→GREEN (worktree kilo+git-hooks, nested-subdir reject kilo+git-hooks); `shellcheck` 0 new. (submodule-тест → backlog R2a-3, механизм идентичен worktree)

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_kilo_adapter.bats tests/bats/test_git_hooks_fallback.bats
shellcheck adapters/kilo.sh adapters/git-hooks-fallback.sh
```
### Edge cases:
не-git директория (git-часть пропускается, не падает); bare-repo; вложенный submodule.

---

<!-- mb-stage:10 -->
## Этап A10 — M-1: uninstall.sh вызывает per-adapter uninstall + refcount декремент (MED)
**Complexity:** M · **~5 мин** · **Зависимости:** A7 (клиенты в манифесте) · **Агент:** developer (+ tester)
**Файлы:** `uninstall.sh:136-139` (edit), `tests/e2e/test_install_uninstall.bats` (extend, FIRST)

**Confirmed:** `uninstall.sh:136-139` не зовёт per-adapter uninstall (codex/pi/cline/kilo/windsurf/opencode)
→ остаётся мусор + `.mb-agents-owners.json` refcount не декрементится.

### Задачи:
1. **Тест FIRST**: install с `--clients codex,opencode` → uninstall → assert их артефакты удалены И
   refcount в `.mb-agents-owners.json` декрементирован (сейчас — нет).
2. **Fix**: писать список установленных клиентов в манифест (зависит от A7); в uninstall итерировать
   клиентов и звать `adapters/<client>.sh uninstall`, который декрементит refcount.

### DoD:
- [x] uninstall зовёт per-adapter uninstall для каждого установленного клиента (манифест несёт `clients`+`project_root`, re-flush после Step-8 loop).
- [x] refcount `.mb-agents-owners.json` декрементится; при 0 — owners-файл + shared AGENTS.md блок удаляются. Missing adapter → `[ ! -x ]` warn+continue (set -e-safe).
- [x] Тесты: 1 e2e RED→GREEN (#27 per-adapter uninstall+refcount); `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_uninstall.bats
shellcheck uninstall.sh
```
### Edge cases:
клиент установлен, но его uninstall-функции нет (skip + warn); refcount уже 0 (не уходить в минус);
частично установленный клиент.

---

<!-- mb-stage:11 -->
## Этап A11 — M-2: mb-deps-check.sh проверяет python >= 3.11 (MED)
**Complexity:** S · **~3 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-deps-check.sh:163` (edit), `tests/bats/test_deps_check.bats` (extend, FIRST)

**Confirmed:** `mb-deps-check.sh:158-166` проверяет наличие `python3`, но не версию; проект требует >=3.11
(`pyproject.toml:128 target-version=py311`).

### Задачи:
1. **Тест FIRST** `test_deps_check.bats`: stub `python3` печатающий `Python 3.10.0` → deps-check
   репортит fail/warn о версии (сейчас — проходит).
2. **Fix**: после `check_required python3` — `python3 -c 'import sys; sys.exit(0 if sys.version_info>=(3,11) else 1)'`,
   при fail — say_err с требуемой версией; не ронять весь скрипт (сохранить exit-семантику).

### DoD:
- [x] deps-check явно репортит, если python < 3.11 (`check_python_version` через `python3 -c 'sys.version_info>=(3,11)'`, per-OS hint; case-паттерны с `>` закавычены — bare `>` = redirect).
- [x] Тесты: 3 bats RED→GREEN (stub python3 на `--version`/`-c`); `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_deps_check.bats
shellcheck scripts/mb-deps-check.sh
```
### Edge cases:
`python3` печатает версию в stderr (учесть `2>&1`); 3.11.0rc; python3.13 (ok).

---

<!-- mb-stage:12 -->
## Этап A12 — M-4: user-writable путь манифеста для pip/sudo (MED) — ✅ подтверждено двумя моделями (манифест не туда при sudo)
**Complexity:** M · **~5 мин** · **Зависимости:** A7 (общий manifest writer) · **Агент:** developer (+ tester)
**Файлы:** `install.sh:900-931` (edit MANIFEST path resolution), `tests/e2e/test_install_uninstall.bats` (extend, FIRST)

**Confirmed:** при pip/sudo манифест пишется в `<prefix>/share` (не writable обычному юзеру); ошибка
глушится (`|| echo 'Manifest write failed'`) → uninstall без манифеста.

### Задачи:
1. **Тест FIRST**: сделать целевую manifest-директорию read-only → install → assert манифест записан в
   user-writable fallback (`$XDG_STATE_HOME`/`~/.local/state/memory-bank/` или `~/.memory-bank-skill/`),
   а не молча потерян.
2. **Fix**: резолвить `MANIFEST` в user-writable путь по умолчанию; при недоступности — внятный fallback
   с логом (не глушить ошибку echo-заглушкой); uninstall ищет манифест в том же fallback.

### DoD:
- [x] Манифест пишется в user-writable путь при недоступности prefix/share (`scripts/_lib.sh::mb_resolve_manifest_path` → fallback `${XDG_DATA_HOME:-$HOME/.local/share}/memory-bank/.installed-manifest.json`; `MB_MANIFEST_PATH` override выигрывает; ЕДИНЫЙ путь в install.sh и uninstall.sh — judge подтвердил).
- [x] Ошибка записи логируется реальным stderr (не глушится `2>/dev/null`); строится на A7-trap/atomic-flush (не регрессит).
- [x] Тесты: 3 e2e RED→GREEN (#45 XDG fallback, #46 write-failure logged, #47 uninstall finds fallback); `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_uninstall.bats
shellcheck install.sh
```
### Edge cases:
`XDG_STATE_HOME` не задан (fallback `~/.local/state`); sudo с `HOME=/root` (см. L-6); оба пути read-only.

---

<!-- mb-stage:13 -->
## Этап A13 — M-5 + L-4: бэкап + парные маркеры при refresh MB-секций (MED/LOW)
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `install.sh:774-790` (M-5, CLAUDE.md refresh), `adapters/_lib_agents_md.sh` (L-4, версия в маркерах),
`tests/pytest/test_hooks_registration.py` или новый `tests/bats/test_claude_md_refresh.bats` (тест FIRST)

**Confirmed:** M-5 — `install.sh:774-790` рефрешит MB-секцию `~/.claude/CLAUDE.md` без бэкапа, контент
юзера после маркера удаляется. L-4 — `_lib_agents_md.sh` пишет AGENTS.md блок-маркеры без версии
(нельзя надёжно найти/обновить свой блок при апгрейде).

### Задачи:
1. **Тест FIRST**: seed `CLAUDE.md` = `<MB start>…<MB end>\nUSER_TAIL` → refresh → assert `USER_TAIL`
   цел И бэкап создан (сейчас tail теряется). + assert AGENTS.md маркеры содержат версию.
2. **Fix M-5**: `backup_if_exists` перед refresh; заменять строго между **парными** start/end
   маркерами (не от start до EOF); контент вне маркеров сохранять.
3. **Fix L-4**: добавить версию в маркеры AGENTS.md (`<!-- memory-bank vX.Y.Z start -->`), обновлять
   по паре маркеров.

### DoD:
- [x] Контент юзера после MB-секции сохранён; бэкап CLAUDE.md создан (slice читается ДО `backup_if_exists` mv — ordering-баг найден и исправлен по TDD; uninstall тоже strip между-маркерами, не до EOF).
- [x] Замена строго между парными start/end маркерами.
- [x] AGENTS.md блок версионирован ОТДЕЛЬНОЙ строкой `<!-- memory-bank-skill-version: X.Y.Z -->` (не в тексте маркера — строки `memory-bank:start` ассертятся verbatim в ~6 тест-файлах; judge подтвердил все 6 adapter-suites зелёные).
- [x] Тесты: 6 bats (new `test_claude_md_refresh.bats`) + 3 (L-4 в `test_agents_md_lib.bats`) RED→GREEN; `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_claude_md_refresh.bats
shellcheck install.sh adapters/_lib_agents_md.sh
```
### Edge cases:
CLAUDE.md без маркеров (append свежий блок, не трогать существующее); только start без end (не съесть
до EOF — искать пару, иначе безопасный append); несколько MB-блоков (dedup).

---

<!-- mb-stage:14 -->
## Этап A14 — M-6 + L-3: adapter framework lib hardening (BSD mktemp + `[""]`) (MED/LOW)
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/_lib_agents_md.sh:152-154` (M-6), `adapters/_framework.sh:12-14` (L-3),
`tests/bats/test_agents_md_lib.bats` + `tests/bats/test_adapter_framework.bats` (extend, FIRST)

**Confirmed:** M-6 — `_lib_agents_md.sh:152-154` использует `mktemp` с суффиксом `XXXXXX.tmp`; BSD mktemp
не рандомит символы после точки → коллизия/`EEXIST` abort. L-3 — `adapter_json_array_from_lines`
(`_framework.sh:12-14`) на пустом входе выдаёт `[""]` вместо `[]`.

### Задачи:
1. **Тест FIRST**: `test_mktemp_pattern_is_portable` — вызвать хелпер дважды, assert разные имена
   (BSD-safe шаблон `XXXXXXXX` без суффикса после X); `test_json_array_empty_input_yields_empty_array` —
   пустой stdin → `adapter_json_array_from_lines` = `[]`.
2. **Fix M-6**: шаблон `mktemp "${TMPDIR:-/tmp}/mb.XXXXXXXX"` (X-ы в конце), затем `mv` в `.tmp`-имя при
   необходимости. **Fix L-3**: в `adapter_json_array_from_lines` фильтровать пустые строки перед сборкой,
   пустой вход → `[]`.

### DoD:
- [x] mktemp-шаблон рандомит на BSD и GNU (trailing-X only, без литерального суффикса после X-run); реальный триггер — stale-остаток от прерванного прогона, воспроизведён тестом.
- [x] Пустой вход → `[]` (не `[""]`) — `jq -R 'select(length>0)'` перед slurp.
- [x] Тесты: 6 bats RED→GREEN (3 в agents_md_lib, 3 в adapter_framework); `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_agents_md_lib.bats tests/bats/test_adapter_framework.bats
shellcheck adapters/_lib_agents_md.sh adapters/_framework.sh
```
### Edge cases:
`TMPDIR` с пробелом (кавычки); вход из одной пустой строки; вход с trailing newline.

---

<!-- mb-stage:15 -->
## Этап A15 — M-7: quoting `MB_SKILLS_ROOT` в cursor.sh (пробелы в $HOME) (MED)
**Complexity:** S · **~3 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/cursor.sh:140-146,190` (edit), `tests/bats/test_cursor_adapter.bats` (extend, FIRST)

**Confirmed:** `cursor.sh:140-146,190` пишет `MB_SKILLS_ROOT=%s` без кавычек в generated-файл → ломается
на пробелах в `$HOME` (`/Users/john doe/…`).

### Задачи:
1. **Тест FIRST**: `test_cursor_skills_root_quoted_with_spaces` — `HOME` с пробелом → сгенерированный
   файл содержит `MB_SKILLS_ROOT="…/…"` (в кавычках) и валиден (source без ошибки).
2. **Fix**: printf-формат `MB_SKILLS_ROOT="%s"` (кавычки) + экранирование при необходимости.

### DoD:
- [x] Сгенерированный `MB_SKILLS_ROOT` shell-safe через `%q` (сильнее `"%s"`: держит пробелы И кавычки/`$` разом); source-able при пробелах в пути.
- [x] Тесты: 1 bats RED→GREEN (HOME с пробелом → команда исполнима, не 127); `shellcheck` 0. (единственный write-site; план-строка :190 устарела после ребейзов)

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_cursor_adapter.bats
shellcheck adapters/cursor.sh
```
### Edge cases:
путь с `"`/`$` (экранировать); пустой `MB_SKILLS_ROOT`.

---

<!-- mb-stage:16 -->
## Этап A16 — M-8: hook-файлы — бэкап + атомарная запись + core.hooksPath (MED) — ✅ подтверждено двумя моделями (перезапись без бэкапа)
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/opencode.sh:162-165`, `adapters/cline.sh:185-188`,
`adapters/windsurf.sh:142-144,176`, `adapters/git-hooks-fallback.sh:72`,
соответствующие `tests/bats/test_*_adapter.bats` + `test_git_hooks_fallback.bats` (extend, FIRST)

**Confirmed:** hook-файлы затирают юзерские без бэкапа (`opencode.sh:162-165`, `cline.sh:185-188`,
`windsurf.sh:142-144`; `:176` неатомарно); `git-hooks-fallback.sh:72` игнорит `core.hooksPath`.

### Задачи:
1. **Тест FIRST** (в затронутых suites): seed юзерский hook с маркером → install → бэкап есть, MB-hook
   установлен, запись атомарна; `test_git_hooks_fallback_respects_core_hookspath` — задать
   `git config core.hooksPath custom` → fallback ставит в custom-путь.
2. **Fix**: `backup_if_exists` + `tmp+mv` во всех трёх адаптерах; в git-hooks-fallback резолвить
   `git rev-parse --git-path hooks` / уважать `core.hooksPath`.

### DoD:
- [x] Юзерские hooks бэкапятся + атомарная запись (mktemp-in-dir+chmod+mv, inode меняется) во ВСЕХ 4 адаптерах: opencode (plugin), cline (3 hook-write), git-hooks-fallback (`install_one_hook`), windsurf (2 hook-скрипта + hooks.json). +x сохраняется после mv.
- [x] git-hooks-fallback уважает `core.hooksPath` — уже закрыто прошлым батчем (`git rev-parse --git-path hooks`), verified 2 тестами (relative+absolute), не дублировано.
- [x] Тесты: RED→GREEN во всех suites (opencode +2, cline +2, git-hooks +4, windsurf +5 через inode-identity); `shellcheck` 0 ×4.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_opencode_adapter.bats tests/bats/test_cline_adapter.bats tests/bats/test_windsurf_adapter.bats tests/bats/test_git_hooks_fallback.bats
shellcheck adapters/opencode.sh adapters/cline.sh adapters/windsurf.sh adapters/git-hooks-fallback.sh
```
### Edge cases:
существующий hook — симлинк; `core.hooksPath` относительный/абсолютный; hook уже наш (идемпотентность).

---

<!-- mb-stage:32 -->
## Этап A17 — CDX-I3: падение адаптера роняет top-level install (exit nonzero) (HIGH) [Codex install delta]
**Complexity:** M · **~5 мин** · **Зависимости:** A7 (статус адаптеров в манифест) · **Агент:** developer (+ tester)
**Файлы:** `install.sh:946-960` (Step 8 loop) + финальный exit, `tests/e2e/test_install_clients.bats` (extend, тест FIRST)

**Confirmed:** `install.sh:955-960` — при провале адаптера печатается `✗ adapter <c> failed` в stderr, но
цикл продолжается и top-level install **завершается success**. Пользователь видит «установлено», хотя
клиент не поставлен; CI/скрипты не ловят сбой.

### Задачи:
1. **Тест FIRST** `test_install_clients.bats`: `--clients <заведомо падающий адаптер>` (stub, exit 1) →
   assert top-level install **exit nonzero** (сейчас RED: exit 0).
2. **Fix**: собирать провалившиеся адаптеры в массив `ADAPTERS_FAILED`; после Step 8 — если непусто,
   писать их статус в манифест (`adapters_failed`) и `exit 1`. Успешные продолжают ставиться (не abort).

### DoD:
- [x] Провал ≥1 адаптера → top-level install exit nonzero.
- [x] Статус адаптеров (invoked/failed) в манифесте.
- [x] Успешные адаптеры ставятся несмотря на сбой другого.
- [x] Тесты: 1+ e2e RED→GREEN; `shellcheck install.sh` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_clients.bats
shellcheck install.sh
```
### Edge cases:
все адаптеры падают (exit nonzero, манифест валиден — см. A7); claude-code уже сделан выше (не в цикле);
adapter missing/not-executable (`:951` warn) — считать fail с явным кодом.

---

<!-- mb-stage:33 -->
## Этап A18 — CDX-I4: `--language es|zh` даёт пустые правила → честный fallback/строки (HIGH) [Codex install delta]
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `install.sh:47` (`VALID_LANGUAGES`), `memory_bank_skill/_texttools.py:~40-64` (localization),
`tests/pytest/test_cli_lang.py` (extend, тест FIRST)

**Confirmed:** `install.sh:47` `VALID_LANGUAGES=(en ru es zh)` принимает `es`/`zh`, но localization-helpers
в `_texttools.py` дают реальные строки только для en/ru → для es/zh language-rule подставляется пустым
(`> **Language** — ` без содержимого).

### Задачи:
1. **Тест FIRST** `test_cli_lang.py`: localization для `es` и `zh` → assert строка правила НЕ пустая (RED).
2. **Fix (выбрать один):** (a) честный fallback на `en` с warning `[install] language 'es' not yet
   localized — using en`, убрав es/zh из `VALID_LANGUAGES` до готовности; ИЛИ (b) реальные строки es/zh.
   Рекомендация: (a) fallback+warning (меньше риск, YAGNI), пока нет вычитанных строк.

### DoD:
- [x] es/zh больше не дают пустое language-правило (fallback+warning ИЛИ реальные строки).
- [x] `VALID_LANGUAGES` согласован с реально поддержанными локалями.
- [x] Тесты: 2 pytest RED→GREEN; `ruff` clean.

### Команды проверки:
```bash
python -m pytest tests/pytest/test_cli_lang.py -q
```
### Edge cases:
`ru` по-прежнему полноценна (регресс); неизвестная локаль (уже отвергается arg-parse); `MB_LANG=es` (fallback).

---

<!-- mb-stage:34 -->
## Этап A19 — CDX-I6: хардкод `python3` в _lib/init-bank/pi-ext → `${MB_PYTHON:-python3}` (MED) [Codex install delta]
**Complexity:** S · **~4 мин** · **Зависимости:** A4 (тот же MB_PYTHON-паттерн), B1 (pi-ext уже трогается) · **Агент:** developer (+ tester)
**Файлы:** `scripts/_lib.sh:20`, `scripts/mb-init-bank.sh:226`, `adapters/pi_graph_rag_extension.ts:17`
(`pythonCommand`), `tests/bats/test_skill_root_resolver.bats` или новый invariant-тест (тест FIRST)

**Confirmed:** голый `python3` остался в `_lib.sh:20` (`mb_normalize_path`), `mb-init-bank.sh:226`
(registry write), `pi_graph_rag_extension.ts:17` (`execFileAsync("python3", …)`) → на pipx/venv без
`python3` в PATH → сбой резолвинга/init/graph-tools.

### Задачи:
1. **Тест FIRST**: grep-инвариант `test_no_bare_python3_in_hotpaths` — assert в перечисленных файлах нет
   голого `python3` вне `${MB_PYTHON:-python3}` (RED); pi-ext — подстановка `MB_PYTHON` при install (с B1).
2. **Fix**: `_lib.sh:20` и `mb-init-bank.sh:226` → `${MB_PYTHON:-python3}`; pi-ext — `pythonCommand`
   конфигурируемый (подставлять при install, как SKILL_DIR/PROJECT_ROOT в B1).

### DoD:
- [x] Нет голого `python3` в `_lib.sh:20`, `mb-init-bank.sh:226`, pi-ext.
- [x] Инвариант-тест ловит регресс.
- [x] Тесты: 1+ RED→GREEN; `shellcheck`/`ruff` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_skill_root_resolver.bats
grep -rn "python3" scripts/_lib.sh scripts/mb-init-bank.sh   # ожидание: только ${MB_PYTHON:-python3}
shellcheck scripts/_lib.sh scripts/mb-init-bank.sh
```
### Edge cases:
`MB_PYTHON` c пробелом (кавычки); heredoc-вызовы `python3 - <<'PY'` (тоже параметризовать); pi-ext `.ts`
— подстановка ДО записи (JSON-encode, как B1).

---

<!-- mb-stage:35 -->
## Этап A20 — CDX-I9: uninstall не затирает пост-install правки CLAUDE.md (MED) [Codex install delta]
**Complexity:** M · **~5 мин** · **Зависимости:** A13 (managed-блок маркеры) · **Агент:** developer (+ tester)
**Файлы:** `uninstall.sh:92-98` (restore-логика), `tests/e2e/test_install_uninstall.bats` (extend, тест FIRST)

**Confirmed:** `uninstall.sh:96` восстанавливает pre-install бэкап `~/.claude/CLAUDE.md` **целиком**
(`mv "$bak" "$orig"`), затирая правки, сделанные пользователем **после** установки MB.

### Задачи:
1. **Тест FIRST**: install → добавить в CLAUDE.md `USER_POST_INSTALL_EDIT` вне MB-блока → uninstall →
   assert `USER_POST_INSTALL_EDIT` **сохранён** (RED: теряется).
2. **Fix**: по умолчанию — **strip только managed-блока** (по парным маркерам из A13), сохраняя остальной
   текущий контент; полный restore бэкапа — только если текущий файл побайтово == ожидаемому installed.

### DoD:
- [x] Пост-install правки юзера вне MB-блока сохранены при uninstall.
- [x] Managed-блок удалён по маркерам; полный restore — только при неизменённом файле.
- [x] Тесты: 1+ e2e RED→GREEN; `shellcheck` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_uninstall.bats
shellcheck uninstall.sh
```
### Edge cases:
файл без маркеров (nothing to strip — не трогать); юзер удалил маркеры вручную (не восстанавливать вслепую);
бэкап отсутствует (только strip).

---

<!-- mb-stage:36 -->
## Этап A21 — CDX-I10: mb-upgrade сохраняет install-опции при re-run (MED) [Codex install delta]
**Complexity:** M · **~5 мин** · **Зависимости:** A7/A12 (манифест как источник опций) · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-upgrade.sh:92-97,176-181`, `install.sh` (persist опций в манифест), `tests/bats/test_upgrade.bats` (extend, тест FIRST)

**Confirmed:** `mb-upgrade.sh:179` перезапускает `bash "$SKILL_DIR/install.sh"` **без сохранённых опций**
→ язык сбрасывается на `en`, интерактив может зависнуть, выбранные project-adapters теряются.

### Задачи:
1. **Тест FIRST**: install с `--language ru --clients codex` → upgrade → assert повторный install
   non-interactive с `ru` + `codex` (RED: en/дефолт).
2. **Fix**: install персистит опции (language, clients, project-root) в манифест; `mb-upgrade.sh` читает
   их и rerun `install.sh` non-interactive с теми же флагами.

### DoD:
- [x] upgrade сохраняет language/clients/project-root из предыдущей установки.
- [x] Re-run non-interactive (не виснет в no-tty).
- [x] Тесты: 1+ bats RED→GREEN; `shellcheck` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_upgrade.bats
shellcheck scripts/mb-upgrade.sh install.sh
```
### Edge cases:
манифест старой схемы без опций (fallback на дефолты + warning); опции переданы явно upgrade'у (override);
clients изменились между версиями (валидировать против `VALID_CLIENTS`).

---

<!-- mb-stage:37 -->
## Этап A22 — CDX-I11: атомарная запись манифеста + fail на битом манифесте (MED) [Codex install delta]
**Complexity:** S · **~4 мин** · **Зависимости:** A7 (общий manifest writer) · **Агент:** developer (+ tester)
**Файлы:** `adapters/_framework.sh:20-28` (`adapter_write_manifest`), `uninstall.sh:71`, `tests/e2e/test_install_uninstall.bats` (extend, тест FIRST)

**Confirmed:** запись манифеста неатомарна (`_framework.sh:24` jq → прямой redirect) → прерывание оставляет
битый JSON; `uninstall.sh:71` `|| true` трактует битый манифест как **пустой** → тихо не удаляет ничего.

### Задачи:
1. **Тест FIRST**: подсунуть битый (truncated) манифест → uninstall без `--force` → assert **exit nonzero**
   с внятной ошибкой (RED: тихо «пусто»); + `test_manifest_written_atomically`.
2. **Fix**: `adapter_write_manifest` пишет в `tmp` + `mv` (атомарно); `uninstall.sh` — валидировать JSON,
   на битом падать nonzero с подсказкой (`--force` для игнора).

### DoD:
- [x] Манифест пишется атомарно (`tmp+mv`); прерывание не оставляет частичный JSON.
- [x] uninstall на битом манифесте → nonzero (без `--force`).
- [x] Тесты: 2 RED→GREEN; `shellcheck` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_uninstall.bats
shellcheck adapters/_framework.sh uninstall.sh
```
### Edge cases:
`--force` игнорит битый манифест (документировать); манифест отсутствует (не ошибка); конкурентная запись
двух адаптеров (tmp с pid).

---

<!-- mb-stage:38 -->
## Этап A23 — CDX-I8: backup/refuse при whole-file перезаписи одноимённых юзер-файлов (MED) [Codex install delta]
**Complexity:** M · **~5 мин** · **Зависимости:** A16 (тот же backup-invariant — НЕ дублировать hooks-скоуп) · **Агент:** developer (+ tester)
**Файлы:** `adapters/cursor.sh:361` (rules `.mdc`), `adapters/cline.sh:159` (rules), `adapters/opencode.sh:164` (commands `cp`),
соответствующие `tests/bats/test_*_adapter.bats` (extend, тест FIRST)
**⚠️ Граница:** A16 покрывает **hook-файлы**; A23 — **rules/commands** одноимённые файлы. Один backup-invariant,
разные цели — не пересекаться по строкам.

**Confirmed:** whole-file перезапись пользовательских одноимённых файлов **без бэкапа**: `cursor.sh:361`
(rules `.mdc` блоком `{ echo … }`), `cline.sh:159` (rules), `opencode.sh:164` (`cp "$f" "$COMMANDS_DIR/…"`).
Если у юзера был свой файл с тем же именем — потерян.

### Задачи:
1. **Тест FIRST** (в затронутых suites): seed юзерский `memory-bank.mdc`/command с маркером → install →
   бэкап есть, MB-контент установлен (RED: юзер-файл затёрт без бэкапа).
2. **Fix**: `backup_if_exists` перед записью rules/commands (в манифест `backups`); для не-managed
   одноимённых файлов — backup или refuse с внятным сообщением; запись атомарна.

### DoD:
- [x] rules/commands не затираются без бэкапа; бэкап в манифесте.
- [x] Non-managed одноимённые файлы — backup/refuse, не тихий clobber.
- [x] Тесты: RED→GREEN во всех затронутых suites; `shellcheck` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_cursor_adapter.bats tests/bats/test_cline_adapter.bats tests/bats/test_opencode_adapter.bats
shellcheck adapters/cursor.sh adapters/cline.sh adapters/opencode.sh
```
### Edge cases:
файл уже наш (MB-marker → идемпотентная перезапись без лишнего бэкапа); симлинк; координация с A16 (hooks)
и A2/A5 (config merge) — общий `backup_if_exists`.

---

<!-- mb-stage:39 -->
## Этап A24 — CDX-I12: uninstall в no-tty без `-y` — явный exit, не зависание (LOW) [Codex install delta]
**Complexity:** S · **~3 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `uninstall.sh:63-68` (`read -r c`), `tests/e2e/test_install_uninstall.bats` (extend, тест FIRST)

**Confirmed:** `uninstall.sh:64` `read -r c` в no-tty окружении (CI/pipe) без `-y`/`--yes` → зависание или
невнятный сбой EOF.

### Задачи:
1. **Тест FIRST**: `test_uninstall_no_tty_without_yes_exits_with_hint` — uninstall со stdin из `/dev/null`
   без `-y` → assert exit nonzero + подсказка «use -y» (RED: висит/невнятно).
2. **Fix**: перед `read` — `if [ ! -t 0 ] && [ "$NON_INTERACTIVE" -eq 0 ]; then` печатать подсказку и `exit`.

### DoD:
- [x] no-tty без `-y` → быстрый exit с подсказкой (не висит).
- [x] `-y`/`--yes` в no-tty работает штатно.
- [x] Тесты: 1 e2e RED→GREEN; `shellcheck` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_uninstall.bats
shellcheck uninstall.sh
```
### Edge cases:
tty присутствует (интерактив как раньше); `-y` задан (skip prompt); pipe с реальным вводом «y».

---

<!-- mb-stage:40 -->
## Этап A25 — CDX-I13: глобальные agent-ресурсы независимо от клиентов — документировать (LOW, docs) [Codex install delta]
**Complexity:** S · **~3 мин** · **Зависимости:** — · **Агент:** documentor (+ tester)
**Файлы:** `README.md` / `docs/cross-agent-setup.md` (документировать поведение), `install.sh:806-808` (комментарий)
**Open question:** гейтить глобальную установку по выбранным клиентам — **отдельное продуктовое решение**;
здесь фиксируем документированием (per team-lead).

**Confirmed:** `install.sh:806-808` всегда зовёт `install_opencode_global_agents`/`install_codex_global_agents`/
`install_pi_global_agents` **независимо** от `--clients` → глобальные agent-ресурсы для opencode/codex/pi
ставятся даже если клиент не выбран.

### Задачи:
1. **Fix (docs)**: задокументировать в README/cross-agent-setup, что глобальные agent-ресурсы
   opencode/codex/pi ставятся всегда (не гейтятся `--clients`); добавить комментарий у `install.sh:806-808`.
2. **Open question в плане**: гейтинг по клиентам — отдельное решение (отметить как open, не реализовывать).

### DoD:
- [x] Поведение «global agents always installed» задокументировано (README + doc).
- [x] Комментарий у call-site объясняет намеренность.
- [x] Open question про gating зафиксирован.

### Команды проверки:
```bash
grep -n "global agent\|global agents\|independently of --clients" README.md docs/cross-agent-setup.md
```
### Edge cases:
если позже решат гейтить — доки обновляются синхронно; uninstall глобальных ресурсов (см. A10/M-1).

---

# Track B — Cross-agent parity

<!-- mb-stage:17 -->
## Этап B1 — F-2: Pi GraphRAG extension — подстановка JSON-путей + тест (HIGH, must-fix) 🔴 — ✅ подтверждено двумя моделями (Claude + Codex gpt-5.5)
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/pi.sh:163-173` (edit `_install_graph_rag_extension`),
`tests/bats/test_graph_rag_adapters.bats` (extend, тест FIRST)
**Смежность:** улучшает Pi graph-UX; не пересекается с `2026-07-04_feature_code-graph-activation.md`
(там freshness/delivery, здесь корректность установки extension).

**Confirmed:** `pi_graph_rag_extension.ts:11-12` содержит плейсхолдеры
`const SKILL_DIR = __MB_SKILL_DIR_JSON__;` / `const PROJECT_ROOT = __MB_PROJECT_ROOT_JSON__;`;
`pi.sh:171` делает голый `cp "$src" "$dest"` **без подстановки** → `.ts` синтаксически невалиден,
native graph-tools Pi не грузятся. Тест `test_graph_rag_adapters.bats:30-43` проверяет только
наличие строк (`grep -q`), не подстановку.

### Задачи:
1. **Тест FIRST** `test_graph_rag_adapters.bats`: `test_pi_extension_has_no_unresolved_placeholders` —
   после install assert `! grep -q '__MB_' "$ext"`; `test_pi_extension_paths_are_valid_json` — извлечь
   `SKILL_DIR`/`PROJECT_ROOT` значения, assert валидный JSON-строка-литерал (в кавычках, экранирован).
2. **Fix** `_install_graph_rag_extension`: заменить `cp` на подстановку — сгенерировать JSON-encoded
   пути (`printf '%s' "$SKILL_DIR" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'`
   или `jq -Rn --arg p "$SKILL_DIR" '$p'`), затем `sed`-заменить `__MB_SKILL_DIR_JSON__` /
   `__MB_PROJECT_ROOT_JSON__` в скопированном файле (`tmp+mv`, экранирование sed-спецсимволов).

### DoD:
- [x] В установленном `.ts` нет `__MB_` плейсхолдеров.
- [x] `SKILL_DIR`/`PROJECT_ROOT` — валидные JSON-строки (устойчивы к пробелам/кавычкам в пути).
- [x] Тесты: 2 bats RED→GREEN; `shellcheck adapters/pi.sh` clean.

### Тестовые сценарии:
- `test_pi_extension_has_no_unresolved_placeholders` — нет `__MB_` после install.
- `test_pi_extension_paths_are_valid_json` — пути в JSON-форме.
- `test_pi_extension_survives_home_with_spaces` — `$HOME` с пробелом → подстановка корректна.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_graph_rag_adapters.bats
shellcheck adapters/pi.sh
```
### Edge cases:
путь с `"`, `\`, `/`, `&` (sed-replacement экранирование, поэтому JSON-encode ДО sed); отсутствующий
src (`.ts` нет → вернуть "false", как сейчас); повторный install (идемпотентная перезапись).

---

<!-- mb-stage:18 -->
## Этап B2 — F-1: Codex получает `/mb` как промпты (`~/.codex/prompts/`) (HIGH) — ✅ подтверждено двумя моделями
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `install.sh:848-853` (extend commands-loop) ИЛИ `adapters/codex.sh` (add prompt install),
`tests/bats/test_codex_adapter.bats` (extend, тест FIRST)

**Confirmed:** `install.sh:848-853` копирует `commands/*.md` в `$CLAUDE_DIR/commands`,
`$OPENCODE_DIR/commands`, `$PI_AGENT_DIR/prompts` — но **не** в `~/.codex/prompts/`. Codex не получает
`/mb` как слэш-команды.

### Задачи:
1. **Тест FIRST** `test_codex_adapter.bats`: `test_codex_installs_mb_prompts` — install → assert
   `~/.codex/prompts/mb.md` (и ≥1 dispatcher) существует, сгенерирован из `commands/`.
2. **Fix**: добавить целевую директорию `~/.codex/prompts/` в commands-loop `install.sh:848-853`
   (или установить в codex-adapter из `commands/*.md`); зарегистрировать файлы в манифесте.

### DoD:
- [x] `commands/*.md` доставлены в `~/.codex/prompts/` (29 файлов — тест ассертит динамически, не хардкодит счёт). `install.sh:938` в commands-loop.
- [x] Файлы в манифесте (uninstall их удаляет + `rmdir` пустой prompts-дир).
- [x] Тесты: 2 bats RED→GREEN (delivery + manifest/uninstall, full-install sandbox); `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_codex_adapter.bats
shellcheck install.sh adapters/codex.sh
```
### Edge cases:
существующий пользовательский промпт с тем же именем (бэкап, см. паттерн A2); frontmatter
Codex-совместимость (если Codex не понимает поля — оставить, он игнорит неизвестные).

---

<!-- mb-stage:19 -->
## Этап B3 — F-3: OpenCode получает агентов (`.opencode/agent/*.md`) (HIGH) — ✅ подтверждено двумя моделями
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/opencode.sh:152-186` (add agents install), `tests/bats/test_opencode_adapter.bats` (extend, FIRST)

**Confirmed:** OpenCode нативно поддерживает `.opencode/agent/*.md`, но `opencode.sh:152-186` не ставит
ни одного агента (0 из 29). Skill role-агенты недоступны в OpenCode.

### Задачи:
1. **Тест FIRST** `test_opencode_adapter.bats`: `test_opencode_installs_agents` — install → assert
   `.opencode/agent/mb-developer.md` (и ≥5 других) существуют, скопированы из `agents/`.
2. **Fix**: копировать `agents/*.md` → `$PROJECT_ROOT/.opencode/agent/` (dispatchable-агенты; partials
   `mb-engineering-core`/`mb-tooling-core` — исключить); регистрировать в манифесте.

### DoD:
- [x] Dispatchable-агенты (27 из 29; partials `mb-engineering-core`/`mb-tooling-core` исключены по `head -5|grep '^partial: true'`) в `.opencode/agent/`; existing user-agent бэкапится once.
- [x] Файлы в манифесте (`files_json`); uninstall удаляет + `rmdir` AGENT_DIR.
- [x] Тесты: 3 bats RED→GREEN (copy+exclude, manifest/uninstall, user-agent backup); `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_opencode_adapter.bats
shellcheck adapters/opencode.sh
```
### Edge cases:
OpenCode frontmatter-требования (`agent`/`subtask` поля — см. I-049; если недоступны, агенты всё равно
как markdown-контекст); существующий пользовательский агент (бэкап).

---

<!-- mb-stage:20 -->
## Этап B4 — F-4: Cursor → `mb-session-end.sh`; OpenCode summarize из плагина (MED)
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `adapters/cursor.sh:74` (swap `session-end-autosave.sh`→`mb-session-end.sh`),
`adapters/opencode.sh` (plugin summarize wiring), `tests/bats/test_cursor_adapter.bats` +
`tests/bats/test_opencode_adapter.bats` (extend, FIRST)
**⚠️ Граница:** пересекается с `2026-07-04_fix_session-capture-and-mb-hygiene.md`. Здесь меняем ТОЛЬКО
**какой** capture-скрипт вешает адаптер (wiring), НЕ трогаем **тело** capture (формат/caps/summarize —
там). Если session-capture план ещё не смёржен — B4 всё равно валиден (вешает существующий
`mb-session-end.sh`, чьё тело чинит тот план).

**Confirmed:** rich session-capture (`session/*.md` для `/mb recall`) только у Claude
(`settings/hooks.json` Stop/SessionEnd). Cursor вешает грубый `session-end-autosave.sh` (`cursor.sh:74`)
вместо CC-совместимого `mb-session-end.sh`. OpenCode summarize не проброшен в плагин.

### Задачи:
1. **Тест FIRST**: `test_cursor_wires_cc_session_end` — install → assert зарегистрирован
   `mb-session-end.sh`, НЕ `session-end-autosave.sh`; `test_opencode_plugin_summarizes` — assert
   плагин вызывает summarize.
2. **Fix**: `cursor.sh:74` — заменить хук на `mb-session-end.sh`; opencode-плагин — добавить вызов
   summarize (mapping bash-hook → TS plugin, см. I-050).

### DoD:
- [x] Cursor регистрирует `mb-session-end.sh` (CC-совместимый capture).
- [x] OpenCode plugin вызывает summarize.
- [x] Тесты: 2 bats RED→GREEN; `shellcheck` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_cursor_adapter.bats tests/bats/test_opencode_adapter.bats
shellcheck adapters/cursor.sh adapters/opencode.sh
```
### Edge cases:
Cursor без Stop-hook API (fallback на git-hooks); двойная регистрация (идемпотентность); плагин без
summarize-CLI (fail-open).

---

<!-- mb-stage:21 -->
## Этап B5 — F-5: Codex session capture через git-hooks-fallback (MED)
**Complexity:** S · **~4 мин** · **Зависимости:** A9 (git detect), A16 (hooks backup) · **Агент:** developer (+ tester)
**Файлы:** `adapters/codex.sh:56-70` (add git-hooks-fallback wiring, по образцу `pi.sh:137-141`),
`tests/bats/test_codex_adapter.bats` (extend, FIRST)
**⚠️ Граница:** как B4 — только wiring capture, не тело.

**Confirmed:** Codex вообще без session capture (`codex.sh:56-70` — только userpromptsubmit guard), нет
даже git-hooks-fallback (у `pi.sh:137-141` он есть).

### Задачи:
1. **Тест FIRST** `test_codex_adapter.bats`: `test_codex_installs_git_hooks_fallback` — install в git-репо
   → assert установлен git-hooks-fallback для session-capture (сейчас — нет).
2. **Fix**: в `codex.sh` вызвать `git-hooks-fallback.sh` (как `pi.sh:137-141`); учесть A9 (git detect)
   и A16 (backup/core.hooksPath).

### DoD:
- [x] Codex получает git-hooks-fallback session-capture в git-репо.
- [x] Тесты: 1+ bats RED→GREEN; `shellcheck` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_codex_adapter.bats
shellcheck adapters/codex.sh
```
### Edge cases:
не-git репо (skip, не падать); worktree (зависит от A9); существующий post-commit hook (бэкап, A16).

---

<!-- mb-stage:22 -->
## Этап B6 — A-1: OpenCode skill-alias / `MB_SKILLS_ROOT` для команд (HIGH)
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `install.sh:485-488` (symlink/alias), `commands/mb.md:249,295,480…` (или `MB_SKILLS_ROOT` var),
`tests/bats/test_skill_root_resolver.bats` (extend, тест FIRST)

**Confirmed:** commands хардкодят `~/.claude/skills/memory-bank/…` (`commands/mb.md:249,295,480…`);
OpenCode без собственного skill-алиаса целиком зависит от дерева `~/.claude` (симлинки создаются только
для claude/codex/cursor/pi, `install.sh:485-488`) → на машине без Claude Code команды `/mb` в OpenCode
резолвят несуществующий путь.

### Задачи:
1. **Тест FIRST** `test_skill_root_resolver.bats`: `test_opencode_gets_skill_alias` — install `--clients opencode`
   без Claude-дерева → assert skill-путь резолвится (symlink/alias или `MB_SKILLS_ROOT` установлен и
   команды его используют).
2. **Fix**: добавить OpenCode в список skill-alias (`install.sh:485-488`) ИЛИ ввести переменную
   `MB_SKILLS_ROOT` и заменить хардкод `~/.claude/skills/memory-bank` в `commands/mb.md` на
   `${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}`.

### DoD:
- [x] Команды `/mb` в OpenCode резолвят skill-корень без Claude Code: `OPENCODE_SKILL_ALIAS` symlink (идемпотентный `install_symlink`) + `commands/mb.md` рантайм-ссылки → `${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}` (27 замен; `MB_SKILLS_ROOT` юзера уважается; прозаическая строка :596 оставлена).
- [x] Тесты: 3 bats RED→GREEN (opencode alias, mb.md grep-contract, no-regression для claude/codex/cursor/pi); `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_skill_root_resolver.bats
shellcheck install.sh
```
### Edge cases:
symlink уже существует (идемпотентность); `MB_SKILLS_ROOT` задан юзером (уважать); global-storage bank.

---

<!-- mb-stage:23 -->
## Этап B7 — CDX-2: mb-subinvoke-resolve.sh — транспорты pi/opencode (HIGH) [Codex delta]
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-subinvoke-resolve.sh:20-40` (edit help + builtin-таблица),
`tests/bats/test_mb_agent_caps.bats` или новый `tests/bats/test_subinvoke_resolve.bats` (тест FIRST)

**Confirmed:** `mb-subinvoke-resolve.sh:23` в help заявляет «Task 13 adds pi/opencode», но builtin-таблица
(`:31-40`) содержит **только** `codex` и `claude-code`. Ветка 3 (`:38-40`, REQ-DF-052 fail-loud) →
для `--agent pi|opencode` без `MB_SUBINVOKE_CMD` резолвер **exit non-zero** → governed review/fan-out
на Pi/OpenCode тихо деградирует до serial или падает.

### Задачи:
1. **Тест FIRST**: `test_subinvoke_resolves_pi` / `test_subinvoke_resolves_opencode` — вызвать
   `mb-subinvoke-resolve.sh --agent pi` (и `opencode`) без `MB_SUBINVOKE_CMD` → assert **exit 0** и
   печатается команда суб-инвока (сейчас RED: non-zero WARN).
2. **Fix**: добавить в builtin-таблицу записи `pi` и `opencode` с их sub-invoke командами (по образцу
   `codex`/`claude-code`, с `MB_SUBINVOKE_MODEL`-подстановкой); синхронизировать help-текст с реальностью.

### DoD:
- [x] `--agent pi` (`pi -p --no-session --model %s`) и `--agent opencode` (`opencode run --model %s`) резолвят команду суб-инвока (exit 0); grammar-guard `:111-118` гейтит модель ПЕРЕД case → injection-safe для pi/opencode; `MB_SUBINVOKE_CMD` override (branch 1) по-прежнему выигрывает; unknown-agent → exit 2 (REQ-DF-052).
- [x] Help-текст синхронизирован (убрано «Task 13 adds»/«INTENTIONALLY absent»; документированы все 4 агента).
- [x] Тесты: 13 bats RED→GREEN (new `test_subinvoke_resolve.bats`) + 2 инвертированных в `test_mb_subinvoke_resolve.bats`; `shellcheck` 0.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_subinvoke_resolve.bats
shellcheck scripts/mb-subinvoke-resolve.sh
```
### Edge cases:
`MB_SUBINVOKE_CMD` override по-прежнему выигрывает (ветка 1); неизвестный агент → прежний fail-loud;
`MB_SUBINVOKE_MODEL` не задан → дефолт per-host.

---

<!-- mb-stage:24 -->
## Этап B8 — CDX-5: mb-reviewer-resolve.sh — skill-roots codex/pi/opencode (MED) [Codex delta]
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-reviewer-resolve.sh:64-70` (edit `SKILLS_ROOTS`), `tests/bats/test_reviewer_resolve*.bats`
или существующий reviewer suite (тест FIRST)

**Confirmed:** `mb-reviewer-resolve.sh:65-70` собирает `SKILLS_ROOTS` только из `MB_SKILLS_ROOT`,
`$HOME/.cursor/skills`, `$HOME/.claude/skills`. Reviewer-override, лежащий в Codex/Pi/OpenCode
skill-root, **не находится** → discovery-паритет нарушен.

### Задачи:
1. **Тест FIRST**: положить reviewer-override в OpenCode/Pi skill-root (без Claude/Cursor) → resolve →
   assert override найден (сейчас RED).
2. **Fix**: добавить в `SKILLS_ROOTS` кандидатов `$HOME/.codex/skills`, `$HOME/.pi/skills` (или
   актуальные Pi-локации), OpenCode skill-root (`~/.config/opencode/skills`, см. I-057) — по образцу
   существующих `[ -d … ] && SKILLS_ROOTS=…` строк.

### DoD:
- [x] Reviewer-override находится из codex/pi/opencode skill-roots.
- [x] `MB_SKILLS_ROOT` по-прежнему имеет приоритет.
- [x] Тесты: 1+ bats RED→GREEN; `shellcheck` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_reviewer_resolve.bats
shellcheck scripts/mb-reviewer-resolve.sh
```
### Edge cases:
несколько skill-roots с override (детерминированный порядок); отсутствующие директории (skip); дубли путей.

---

<!-- mb-stage:25 -->
## Этап B9 — CDX-6: OpenCode plugin registration — единый контракт (code+docs+tests) (MED) [Codex delta]
**Complexity:** S · **~4 мин** · **Зависимости:** B3, B4 (координация правок opencode.sh) · **Агент:** developer/documentor (+ tester)
**Файлы:** `adapters/opencode.sh:121` (решение контракта), `docs/cross-agent-setup.md` (текст),
`tests/bats/test_opencode_adapter.bats:48-54,115-120` (align)

**Confirmed:** контракт регистрации плагина **противоречив**: `opencode.sh:121` (`install_opencode_json`)
удаляет ref из `opencode.json`, тесты (`test_opencode_adapter.bats:51` «relies on plugin directory
auto-discovery», `:118` «removes stale legacy plugin registration») фиксируют **auto-discovery**, а доки
всё ещё описывают project-`opencode.json` регистрацию.

### Задачи:
1. **Решение (выбрать одно, консистентно везде):** задекларировать **auto-discovery** контрактом
   (плагин в `.opencode/plugins/`, ref в `opencode.json` не нужен) — соответствует текущему коду+тестам.
2. **Fix**: привести доки (`cross-agent-setup.md`) к auto-discovery; убедиться, что `opencode.sh:121`
   и тесты остаются согласованы; если выбран альтернативный путь (явная регистрация) — обновить и код,
   и тесты, и доки синхронно.
3. **Тест**: добавить assert «доки не обещают project-opencode.json регистрацию» (grep-guard) ИЛИ
   закрепить auto-discovery в существующих bats.

### DoD:
- [x] Код, тесты и доки согласованы на одном контракте регистрации OpenCode-плагина.
- [x] grep-guard/bats фиксирует выбранный контракт.
- [x] `shellcheck adapters/opencode.sh` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_opencode_adapter.bats
grep -n "opencode.json" docs/cross-agent-setup.md   # ожидание: соответствует auto-discovery
```
### Edge cases:
legacy `opencode.json` с ref (удаляется — уже покрыто `:118`); отсутствующий `opencode.json`
(auto-discovery всё равно работает); координация с B4 (summarize wiring в том же файле).

---

# Track C — Docs + tests

<!-- mb-stage:26 -->
## Этап C1 — D-1…D-6: doc-vs-reality правки cross-agent доков (docs) — ✅ D-1 (Pi lifecycle overclaim) подтверждена двумя моделями
**Complexity:** M · **~5 мин** · **Зависимости:** B1, B4, B5 (доки должны отражать пост-фикс реальность)
· **Агент:** documentor/developer (+ tester для doc-drift)
**Файлы:** `docs/cross-agent-setup.md:117-118,251-254,290-292`, `SKILL.md:18,119`,
`docs/cursor-extension.md:69-72`, `install.sh:641-643` / `scripts/_lib_pi_global.sh:26-28` (текст),
`adapters/opencode.sh:47-49` (текст), `tests/pytest/test_docs_drift_recipe.py` или новый doc-assert (тест FIRST где применимо)

**Confirmed:** D-1 `cross-agent-setup.md:251-254` обещает Pi lifecycle-хуки extension'а — их нет;
D-2 там же Codex «SessionEnd auto-capture» — нет (закрывается B5, тогда правка = «git-hooks-fallback»);
D-3 `SKILL.md:18` Cursor «full parity» завышено; D-4 противоречие `cross-agent-setup.md:117-118,290-292`
vs `cursor-extension.md:69-72` про IDE↔CLI; D-5 `install.sh:641-643`/`_lib_pi_global.sh:26-28` skill-mode
Pi обещает подпапки, которых нет; D-6 `SKILL.md:119`/`opencode.sh:47-49` «native tool wrappers» для Pi
(были сломаны — чинит B1) и OpenCode (не регистрируются).

### Задачи:
1. Привести D-1…D-6 в соответствие: Pi lifecycle-хуки — убрать/пометить как git-hooks-fallback; Codex
   capture — «git-hooks-fallback (B5)»; Cursor parity — честная деградация (команды только global,
   capture через session-end); устранить IDE↔CLI противоречие (единая формулировка); skill-mode Pi
   подпапки — убрать обещание; native-tools — Pi «работает после B1», OpenCode «через агентов».
2. **Тест где возможно**: расширить `test_docs_drift_recipe.py`/doc-assert, чтобы ключевые ложные
   утверждения (напр. «full parity», «SessionEnd auto-capture») не возвращались (grep-guard).
3. **Codex-дельта (CDX-D1…D4)** оформлена отдельным хвостовым **Этапом C6** (README `~/.cursor/hooks`
   vs bundle-пути, `install.sh:4` «18»→29, README-таблица без `/flow` `/analyze-task` `/goal`,
   стейл «4 hooks» матрица). C1 и C6 — один doc-vs-reality лейн; правьте согласованно.

### DoD:
- [x] D-1/D-2/D-4/D-5(install.sh)/D-6(opencode) отражают реальность после Track B. (D-3 уже исправлено апстримом; D-6 SKILL.md-часть + D-5 pi.sh compat-путь отложены — R7-1/R7-2, SKILL.md/pi.sh вне скоупа батча)
- [x] Doc-guard тест ловит регресс ложных утверждений (scoped на docs/, 3 grep-guard теста).
- [x] `ruff` clean на изменённом Python.

### Команды проверки:
```bash
python -m pytest tests/pytest/test_docs_drift_recipe.py -q
grep -n "full parity\|SessionEnd auto-capture" docs/ SKILL.md   # ожидание: нет ложных утверждений
```
### Edge cases:
формулировки, верные только после мержа Track B (C1 зависит от B1/B4/B5); не переусердствовать с
grep-guard (ложные срабатывания на легитимном тексте).

---

<!-- mb-stage:27 -->
## Этап C2 — M-3 + L-1 + L-6 + L-7: README-deps, версия, sudo-doc, git-hygiene (docs/hygiene) — ✅ M-3 (git dep) подтверждено двумя моделями
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** documentor/developer (+ tester)
**Файлы:** `README.md:94` (M-3 deps), `README.md:562` (L-1 версия), `docs/*` (L-6 sudo -E),
`.installed-manifest.json` + `.gitignore` (L-7), `tests/pytest/test_gitignore_invariants.py` (extend, FIRST)

**Confirmed:** M-3 — git/bash обязательные deps не в README (`README.md:94`); L-1 — README «stable
v5.0.0» устарел (`README.md:562`, VERSION=5.2.0); L-6 — sudo без `-E` → `HOME=/root` (документировать);
L-7 — закоммичен `.installed-manifest.json` с pytest-путями (мусор в репо).

### Задачи:
1. **Тест FIRST** `test_gitignore_invariants.py`: assert `.installed-manifest.json` в `.gitignore` И не
   трекается git (`git ls-files` пуст) — сейчас RED.
2. **Fix**: README — добавить git+bash в required deps (M-3), обновить версию/«stable» на актуальную
   (L-1); доки — предупреждение про `sudo -E` (L-6); `git rm --cached .installed-manifest.json` +
   добавить в `.gitignore` (L-7).

### DoD:
- [x] README перечисляет git+bash как required; версия актуальна (v5.2.0, из VERSION).
- [x] `.installed-manifest.json` untracked + в `.gitignore` (L-7 уже выполнено; инвариант-тест добавлен как гард).
- [x] Doc про `sudo -E` присутствует (troubleshooting.md).
- [x] Тесты: 1 pytest guard; `ruff` clean.

### Команды проверки:
```bash
python -m pytest tests/pytest/test_gitignore_invariants.py -q
git ls-files .installed-manifest.json   # ожидание: пусто
```
### Edge cases:
локальный `.installed-manifest.json` не удалять с диска (только из git); README-версия читать из VERSION,
не хардкодить дважды.

---

<!-- mb-stage:28 -->
## Этап C3 — Test gap: e2e upgrade vN→vN+1 (tests)
**Complexity:** M · **~5 мин** · **Зависимости:** A6, A7, A13 (upgrade-семантика фиксится там)
· **Агент:** tester (+ developer)
**Файлы:** `tests/e2e/test_upgrade_e2e.bats` (new) ИЛИ extend `tests/bats/test_upgrade.bats`

**Confirmed:** нет теста апгрейда vN→vN+1 (сохранность юзер-бэкапов, refresh маркеров, манифест) на
реальном install→install прогоне. Существующий `test_upgrade.bats` не покрывает full-cycle upgrade.

### Задачи:
1. Написать e2e: seed юзер-файлы (CLAUDE.md tail, config.toml foreign key, hook) → install (текущая
   версия как «vN») → сменить `VERSION`/переустановить как «vN+1» → assert: юзер-контент цел, истинный
   первый бэкап сохранён, манифест валиден, маркеры версионированы.

### DoD:
- [x] e2e upgrade проверяет сохранность юзер-контента + бэкапов + манифеста через 2 установки.
- [x] Тест зелёный после A6/A7/A13 (и красный без них — служит регресс-гардом). 3/3 на writable rsync-копии.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_upgrade_e2e.bats
```
### Edge cases:
downgrade (vN+1→vN) — вне scope, но не должен ломать манифест; upgrade без изменений (no-op идемпотентность).

---

<!-- mb-stage:29 -->
## Этап C4 — Test gap: runtime-паритет (placeholder / capture / gates) (tests)
**Complexity:** M · **~5 мин** · **Зависимости:** B1, B4, B5 · **Агент:** tester
**Файлы:** `tests/bats/test_cross_agent_runtime_parity.bats` (new)

**Confirmed:** адаптерные bats проверяют механику установки, но не рантайм-паритет: (a) подстановку
плейсхолдеров (F-2), (b) наполнение `session/*.md` при capture (F-4/F-5), (c) срабатывание гейтов.

### Задачи:
1. Написать runtime-parity suite: для каждого клиента, где применимо — assert установленный extension
   без `__MB_` (Pi), assert capture-скрипт создаёт `session/*.md` при симуляции session-end
   (Cursor/Codex), assert governed-гейт резолвится (где транспорт доступен).

### DoD:
- [x] Suite покрывает placeholder-substitution + capture-наполнение + gate-resolution.
- [x] Все case зелёные после Track B; красные без фиксов (регресс-гард). 4 ok + 1 explicit Windsurf skip; MB_AUTO_CAPTURE override для честного дефолта.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_cross_agent_runtime_parity.bats
```
### Edge cases:
клиент без транспорта (skip с явной причиной, не fail); platform-limit кейсы (P-1/P-2/P-3 — assert
честная деградация, не полная фича).

---

<!-- mb-stage:30 -->
## Этап C5 — CDX-8: adapters/_contract.sh — artifact-level per-host проверки (MED, tests) [Codex delta]
**Complexity:** M · **~5 мин** · **Зависимости:** B1-B6 (артефакты, которые контракт проверяет) · **Агент:** tester (+ developer)
**Файлы:** `adapters/_contract.sh` (extend), `tests/bats/test_adapter_framework.bats` или
`test_*_adapter.bats` (тест FIRST)

**Confirmed:** `_contract.sh:4` `adapter_contract_require_functions` проверяет только **существование
функций** (`declare -F`). Сломанный parity (адаптер объявляет функции, но не производит артефакты)
**проходит** валидацию → тесты дают ложную зелень.

### Задачи:
1. **Тест FIRST**: адаптер-заглушка с объявленными функциями, но без реальной установки артефактов →
   assert контракт **падает** (сейчас RED: проходит).
2. **Fix**: расширить `_contract.sh` до проверки **артефактов per host** после install: наличие
   commands/prompts, rules, hooks (где применимо), agents (где применимо), manifest; для
   platform-limit хостов — assert документированной деградации (напр. Codex без statusline — ожидаемо).

### DoD:
- [x] Контракт проверяет артефакты (`adapter_contract_require_artifacts` — каждый `files[]` путь существует), не только функции.
- [x] Сломанный-parity адаптер падает контракт (RED→GREEN на реальном).
- [x] Тесты: 4 bats RED→GREEN; `shellcheck adapters/_contract.sh` clean.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_adapter_framework.bats
shellcheck adapters/_contract.sh
```
### Edge cases:
platform-limit артефакты (не required для хоста — не должны фейлить); опциональные артефакты
(agents только где хост поддерживает); manifest в user-writable fallback (см. A12).

---

<!-- mb-stage:31 -->
## Этап C6 — CDX-D1…D4: doc-vs-reality (Cursor hooks, 18→29, /flow /analyze-task /goal, hooks matrix) [Codex delta]
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** documentor/developer (+ tester)
**Файлы:** `README.md` (CDX-D1 cursor hooks, CDX-D3 команды), `install.sh:4` (CDX-D2 header),
`docs/cross-agent-setup.md` (CDX-D4 hooks matrix), doc-guard в `tests/pytest/test_doc_counts.py` (тест где применимо)

**Confirmed:** CDX-D1 — README заявляет копирование `~/.cursor/hooks/*.sh`, а `cursor.sh:1-8` явно
«Hook scripts are NOT copied into .cursor/hooks/» (`test_cursor_global.bats:48` подтверждает bundle-пути).
CDX-D2 — `install.sh:4` header «18 dev commands» устарел (реально **29** `commands/*.md`; `SKILL.md:12`=29).
CDX-D3 — README-таблица команд не содержит `/flow`, `/analyze-task`, `/goal`. CDX-D4 —
`cross-agent-setup.md` матрица «4 hooks» устарела против реального lifecycle-набора
(`settings/hooks.json`, `cursor.sh:69`).

### Задачи:
1. **Fix CDX-D1**: README — исправить на «hooks reference bundle scripts, NOT copied» (соответствие
   `cursor.sh:1-8`). **CDX-D2**: `install.sh:4` — «18 dev commands» → актуальное число (29).
   **CDX-D3**: добавить `/flow`, `/analyze-task`, `/goal` в README-таблицу команд.
   **CDX-D4**: обновить hooks-матрицу в `cross-agent-setup.md` под реальный lifecycle-набор.
2. **Тест где применимо**: `test_doc_counts.py` — assert число команд в README/install.sh header ==
   `len(glob commands/*.md)` (ловит будущий drift 18↔29).

### DoD:
- [x] README/`install.sh` header отражают реальное число команд (29) и корректный Cursor-hooks контракт («references bundle scripts, NOT copied»).
- [x] README-таблица включает `/flow`, `/analyze-task`, `/goal`.
- [x] hooks-матрица в доках соответствует lifecycle-набору.
- [x] Doc-count тест ловит command-count drift (install.sh header == glob commands/*.md); `ruff` clean.

### Команды проверки:
```bash
python -m pytest tests/pytest/test_doc_counts.py -q
grep -c "^" <(ls commands/*.md)   # сверить с числом в install.sh:4 и README
grep -n "NOT copied\|not copied" README.md   # Cursor hooks контракт
```
### Edge cases:
число команд читать из glob, не хардкодить в двух местах; `/flow` sub-команды (одна запись, не дубли);
матрица hooks — не перечислять внутренние хуки, только lifecycle-события.

---

## Этап C7 — Test gap: install-reliability regression suite (tests) [Codex install delta]
**Complexity:** M · **~5 мин** · **Зависимости:** A17, A22, A24 · **Агент:** tester
**Файлы:** `tests/e2e/test_install_reliability.bats` (new)

**Confirmed:** Codex install-аудит выделил классы, не покрытые e2e: (a) manifest write failure, (b) adapter
failure не роняет install, (c) no-tty uninstall. Эти assert'ы служат регресс-гардами к A17/A22/A24.

### Задачи:
1. `test_manifest_write_failure_nonzero_and_uninstall_works` — manifest-путь недоступен/битый →
   assert предсказуемое поведение install (fallback/nonzero, A12/A22) И uninstall работает.
2. `test_adapter_failure_top_level_nonzero` — падающий адаптер → top-level install nonzero (A17).
3. `test_uninstall_no_tty_without_yes` — uninstall no-tty без `-y` → exit+подсказка (A24).

### DoD:
- [x] 3 e2e-кейса покрывают manifest-failure / adapter-failure / no-tty-uninstall. 4/4, sandboxed HOME.
- [x] Красные без A17/A22/A24, зелёные после — регресс-гарды.

### Команды проверки:
```bash
PATH="$PWD/.venv/bin:$PATH" bats tests/e2e/test_install_reliability.bats
```
### Edge cases:
пересечение с A17/A22/A24 DoD-тестами (C7 — агрегирующий e2e-гард, не дубль unit-уровня);
no-tty эмулировать stdin из `/dev/null`.

---

## Граф зависимостей

```
Phase 0 (MUST-FIX gate):
  A1 (C-1) ─┐
  A2 (C-2) ─┤
  A3 (H-1) ─┼─ независимы, параллельно
  A4 (H-2) ─┤
  B1 (F-2) ─┘

Track A (install.sh серилизован):
  A4 ── A6 ── A7 ── A12          (install.sh writer chain)
              A7 ── A10          (клиенты в манифесте → uninstall)
              A7 ── A13          (manifest/refresh)
  A5, A8, A9, A11, A14, A15, A16  (независимые файлы — параллельно)
  A9 ─┐
  A16 ┴─ B5                       (git detect + hooks backup → codex capture)
  A4 ── A17 ── A25               (install.sh chain, продолжение)
  A10 ── A20 ── A22 ── A24       (uninstall.sh — серилизовать)
  A18 (install.sh+py), A19, A21 (mb-upgrade) — независимые
  A16 ── A23                     (backup-invariant для rules/commands)

Track B:
  B1, B2, B3, B4, B6  (независимы, параллельно; B2 трогает install.sh → после A13)
  A9 + A16 ── B5
  B7, B8  (независимые scripts — параллельно)
  B3 + B4 ── B9  (opencode.sh координация)

Track C:
  B1+B4+B5 ── C1        (доки отражают пост-фикс реальность)
  C2                    (независим)
  A6+A7+A13 ── C3       (upgrade e2e)
  B1+B4+B5 ── C4        (runtime parity)
  B1..B6    ── C5        (artifact-level contract)
  C6                    (независим — docs)
  A17+A22+A24 ── C7      (install-reliability regression e2e)
```

## Параллелизация

| Фаза | Этапы | Агенты |
|------|-------|--------|
| 0 (gate) | A1, A2, A3, A4, B1 | developer-1..3 + tester (разные файлы) |
| 1 (Track A HIGH) | A5, A8, A9 ∥ A6→A7 (install.sh chain) | developer-1 (install.sh), developer-2 (adapters), tester |
| 2 (Track A MED/LOW) | A11, A14, A15, A16 ∥ A10→(A7), A12→(A7), A13 | developer-1 (install.sh), developer-2 (adapters/scripts), tester |
| 3 (Track B) | B2 (после A13), B3, B4, B6, B7, B8 ∥ B5 (после A9,A16) ∥ B9 (после B3,B4) | developer-1..2 + tester |
| 4 (Track C) | C2, C6 ∥ C1 (после B), C3 (после A6/A7/A13), C4+C5 (после B), C7 (после A17/A22/A24) | documentor + tester |
| 1b (Codex install HIGH) | A17 (install.sh chain), A18 (install.sh+py) | developer-1 + tester |
| 2b (Codex install MED/LOW) | A19, A21 ∥ A20→A22→A24 (uninstall chain) ∥ A23 (после A16) ∥ A25 (docs) | developer-2 + documentor + tester |

## Потенциальные конфликты при merge (серилизовать)

- **`install.sh`** — трогают A4, A6, A7, A12, A13, A17, A18, A25, B2, B6. **Строгий порядок:** A4 → A6 →
  A7 → A12 → A13 → A17 → A25 → B2 → B6 (A18 — регион arg-parse `:47`, координировать отдельно). Один
  writer за раз; каждый ребейзит на предыдущий. Не параллелить.
- **`adapters/cursor.sh`** — A4, A6, A15, B4, A23. **Порядок:** A4 → A6 → A15 → B4 → A23.
- **`adapters/codex.sh`** — A2, B2, B5. **Порядок:** A2 → B2 → B5.
- **`adapters/opencode.sh`** — A5, A16, B3, B4, B9. **Порядок:** A5 → A16 → B3 → B4 → B9.
- **`scripts/mb-subinvoke-resolve.sh`** (B7) и **`scripts/mb-reviewer-resolve.sh`** (B8) — отдельные файлы, параллельно.
- **`adapters/_contract.sh`** (C5) — отдельный файл, параллельно; зависит логически от Track B артефактов.
- **`uninstall.sh`** — A10, A20, A22, A24 (+ C7 добавляет кейсы). **Порядок:** A10 → A20 → A22 → A24.
- **`adapters/cline.sh`** — A8, A16, A23. **Порядок:** A8 → A16 → A23. **`_framework.sh`** — A14, A22 (разные функции).
- **`scripts/mb-upgrade.sh`** (A21), **`scripts/_lib.sh`**+**`mb-init-bank.sh`** (A19) — отдельные файлы, параллельно.
- **`install.sh:4`** (C6 header) — правка комментария, вне writer-цепочки; координировать после B2/B6 если те трогают соседние строки.
- **`adapters/_lib_agents_md.sh`** — A13 (L-4) и A14 (M-6) трогают разные функции — можно параллелить,
  но лучше A14 → A13.
- **`tests/e2e/test_install_uninstall.bats`** — A6, A7, A10, A12 добавляют кейсы; append-only, конфликты
  тривиальны, но координировать порядок append.

## Checklist (копировать в `.memory-bank/checklist.md`)

- ⬜ **A1** (C-1, CRIT): templates+flow-templates в wheel/sdist + e2e `/mb init`
- ⬜ **A2** (C-2, CRIT): codex.sh backup+merge config.toml/hooks.json
- ⬜ **A3** (H-1): Homebrew bump + CI-инвариант formula==VERSION
- ⬜ **A4** (H-2): cursor.sh `${MB_PYTHON:-python3}` + однократный install-global
- ⬜ **B1** (F-2, 🔴): Pi extension подстановка JSON-путей + тест «нет `__MB_`»
- ⬜ **A5** (H-3): opencode.json backup + атомарная запись
- ⬜ **A6** (H-4): ротация бэкапов не уничтожает оригинал юзера
- ⬜ **A7** (H-5): инкрементальный/атомарный манифест + trap
- ⬜ **A8** (H-6): cline.sh детект `.clinerules`-файла
- ⬜ **A9** (H-7): `git rev-parse --git-dir` (kilo + git-hooks-fallback)
- ⬜ **A10** (M-1): uninstall зовёт per-adapter uninstall + refcount
- ⬜ **A11** (M-2): deps-check python >=3.11
- ⬜ **A12** (M-4): user-writable путь манифеста (pip/sudo)
- ⬜ **A13** (M-5+L-4): бэкап + парные маркеры CLAUDE.md/AGENTS.md
- ⬜ **A14** (M-6+L-3): BSD mktemp + `[]` вместо `[""]`
- ⬜ **A15** (M-7): quoting `MB_SKILLS_ROOT` в cursor.sh
- ⬜ **A16** (M-8): hook-файлы backup+atomic + core.hooksPath
- ✅ **B2** (F-1): Codex `/mb` промпты в `~/.codex/prompts/`
- ✅ **B3** (F-3): OpenCode агенты в `.opencode/agent/`
- ✅ **B4** (F-4): Cursor→`mb-session-end.sh`, OpenCode summarize
- ✅ **B5** (F-5): Codex git-hooks-fallback capture
- ✅ **B6** (A-1): OpenCode skill-alias / `MB_SKILLS_ROOT`
- ✅ **C1** (D-1…D-6): doc-vs-reality cross-agent доки (D-3 апстрим; D-5 pi.sh + D-6 SKILL.md отложены → R7-1/R7-2)
- ✅ **C2** (M-3+L-1+L-6+L-7): README deps/версия, sudo-doc, git-hygiene
- ✅ **C3**: e2e upgrade vN→vN+1
- ✅ **C4**: runtime-паритет suite (placeholder/capture/gates)
- ✅ **B7** (CDX-2, HIGH): mb-subinvoke-resolve транспорты pi/opencode
- ✅ **B8** (CDX-5, MED): mb-reviewer-resolve skill-roots codex/pi/opencode
- ✅ **B9** (CDX-6, MED): OpenCode plugin registration — единый контракт (code+docs+tests)
- ✅ **C5** (CDX-8, MED): _contract.sh artifact-level per-host проверки
- ✅ **C6** (CDX-D1…D4): README/install.sh/docs — Cursor hooks, 18→29, /flow /analyze-task /goal, hooks matrix
- ✅ **A17** (CDX-I3, HIGH): падение адаптера → top-level install nonzero + статус в манифест
- ✅ **A18** (CDX-I4, HIGH): es/zh пустые правила → fallback на en+warning / реальные строки
- ✅ **A19** (CDX-I6, MED): `${MB_PYTHON:-python3}` в _lib/init-bank/pi-ext + инвариант-тест
- ✅ **A20** (CDX-I9, MED): uninstall strip managed-блока, не затирать пост-install правки CLAUDE.md
- ✅ **A21** (CDX-I10, MED): mb-upgrade сохраняет install-опции (language/clients) при re-run
- ✅ **A22** (CDX-I11, MED): атомарный манифест (tmp+mv) + uninstall падает на битом без --force
- ✅ **A23** (CDX-I8, MED): backup/refuse для rules/commands одноимённых юзер-файлов (сошлись с A16)
- ✅ **A24** (CDX-I12, LOW): uninstall no-tty без -y → exit+подсказка, не зависание
- ✅ **A25** (CDX-I13, LOW/docs): глобальные agent-ресурсы независимо от --clients — документировать (gating = open question)
- ✅ **C7**: install-reliability regression suite (manifest-failure / adapter-failure / no-tty-uninstall)

## Validation gate (самопроверка плана)

- [x] Каждый этап ≤5 мин (bite-sized; крупные разбиты, LOW сгруппированы попарно по общему файлу).
- [x] Каждый этап имеет точные файлы (file:line из аудита).
- [x] Каждый этап имеет SMART DoD (измеримо: exit-код, число тестов, RED→GREEN, shellcheck clean).
- [x] Каждый этап имеет тест-сценарии + команды верификации (bats/pytest конкретные).
- [x] Зависимости — DAG без циклов (см. граф); install.sh-цепочка серилизована.
- [x] Production wiring учтён (manifest, uninstall, CI-инвариант, регистрация файлов).
- [x] Нет пропусков между этапами (backup/merge/atomic/manifest покрыты сквозным invariant'ом).
- [x] Assumptions зафиксированы; пересечения с двумя queued-планами разграничены в frontmatter.
- [x] **Codex gpt-5.5 cross-review DONE (2026-07-04)** — parity-дельта: B7-B9 + C5-C6; install-дельта: A17-A25 + C7. Все находки заземлены по коду (parity: CDX-2 `:31`, CDX-5 `:65`, CDX-6 `:121`, CDX-8 `:4`, CDX-D1 `cursor.sh:1-8`, CDX-D2 `install.sh:4`; install: CDX-I3 `install.sh:955`, CDX-I4 `install.sh:47`+`_texttools.py`, CDX-I6 bare-python3 ×3, CDX-I9 `uninstall.sh:96`, CDX-I11 `_framework.sh:24`). Подтверждены двумя моделями: F-2/F-1/F-3/D-1/P-1 (parity) + H-5(A7)/M-4(A12)/M-3(C2)/M-8(A16) (install). Исключены как уже покрытые: CDX-I1≈A2, CDX-I2≈A7+A12, CDX-I7≈C2, sha256-тест≈A3.

---

## Batch 1 — исполнено (A1·A2·A3·A4·B1), judge = GO_WITH_BACKLOG (2026-07-04)

Governed-цикл: implement → verify (PASS) → review×2 (Codex gpt-5.5: r1 5 находок, r2 4 находки — все 9 реальные, воспроизведены и исправлены) → judge (независимо перепрогнал 69/69 green, sha256 сверил с живым PyPI). Итог: **69/69 тестов green** (codex 33, cursor 12, graph-rag 9, e2e 9, pytest 6), shellcheck 0 новых замечаний, ruff clean.

### Backlog-резидуалы (из judge GO_WITH_BACKLOG):
- **R-1 [MAJOR, maintainability]** `adapters/codex.sh` вырос 177→439 строк, нарушает собственный DoD A2 «файл ≤400». Не корректность/безопасность — только file-budget (overage = safety-комментарии, пережившие 2 раунда adversarial-ревью; тесты/shellcheck green). Механический фикс: вынести `codex_backup_if_exists`/`codex_markers_well_formed`/`codex_config_body_no_dupes`/`codex_upsert_config_toml`/`codex_merge_hooks_json`/`codex_mb_created_file`/`codex_strip_*_or_remove` → новый `adapters/_lib_codex_config.sh` (source из codex.sh). Кандидат в отдельный этап Track C.
- **R-2 [MINOR, tests]** нет отдельного bats-теста на `install.sh::_cursor_global_up_to_date` (guard проверен вручную для 3 кейсов: same version+lang→skip, lang-switch→re-run, version-bump→re-run, но не через автотест). В enumerated-сценариях A4 этого пункта не было — гигиена, не unmet-DoD. Добавить bats в Track C.

_Формальные backlog-ID (I-NNN) отложены: `.memory-bank/backlog.md` сейчас содержит незакоммиченные правки параллельной сессии (I-087/I-093) — не смешиваю. Резидуалы трекаются здесь до финального `/mb done` по плану._

---

## Batch 2a — исполнено (A5·A8·A9 — install-safety адаптеров), judge = GO_WITH_BACKLOG (2026-07-04)

Governed: implement → verify → Codex-review ×2 (gpt-5.5) → mb-judge. **9 реальных находок** (r1: 6 major — glob-бэкап, ×2 fixed-tmp клоббер, накопление blank-строк, symlink-детач, git-dir walk-up; r2: R1-3 residual byte-inexact, R1-4 residual single-hop symlink, +1 minor mode-drop) — все воспроизведены и исправлены. mb-judge независимо перепрогнал (opencode 20/20, cline 20/22, kilo 12/13, git-hooks 24/27; 6 падений = pre-existing capture, подтверждено stash-ем), вручную протрассировал delay-buffer awk (byte-exact), multi-hop symlink, repo-root guard, worktree + `core.hooksPath`. shellcheck 0 new; все файлы ≤400 строк.

### Backlog-резидуалы (из judge GO_WITH_BACKLOG):
- **R2a-1 [MAJOR, data-safety]** `adapters/cline.sh` file-form путь не делает backup перед `_cline_strip_block` mktemp+awk+mv-перезаписью `.clinerules`. Воспроизведено: повреждённый END-маркер (start есть, end нет) → uninstall молча срезает всё от start до EOF, невосстановимо. Вне заявленного scope A8, не round-2 регрессия. **Закрыть первым в Batch 2b** (там консолидация backup-before-overwrite для installer'а).
- **R2a-2 [MINOR, logging]** `adapters/git-hooks-fallback.sh` success-лог хардкодит `"$PROJECT_ROOT/.git/hooks/"`, хотя реальный HOOKS_DIR может отличаться (worktree common-dir, custom `core.hooksPath`). Косметика — хуки ставятся в правильное место. Закрыть в Batch 2b/C.
- **R2a-3 [MINOR, tests]** A9 покрыт worktree-тестом (kilo+git-hooks), но нет отдельного submodule-теста (план называет submodule в edge-cases). Механизм детекта идентичен → риск низкий. Закрыть в Track C.

---

## Batch 2b — исполнено (A6·A7 + R2a-1·R2a-2), self-review (governed gates infra-down) (коммит 5cababa, 2026-07-05)

A6 (H-4): `backup_if_exists`/`global_backup_if_exists` сохраняют САМЫЙ СТАРЫЙ бэкап (истинный оригинал юзера), прунят только MB-generated; `.$$`-суффикс против timestamp-коллизии. A7 (H-5): `flush_manifest` через `trap _mb_on_exit EXIT` (армится ПОСЛЕ deps-check → `MB_PY` всегда определён), атомарно `mkstemp`+`os.replace`, идемпотентно `MB_MANIFEST_FLUSHED`, exit-код сохранён; env-seam `MB_MANIFEST_PATH`. R2a-1: cline `_cline_backup_once` перед любой перезаписью + strip только при ОБОИХ маркерах. R2a-2: git-hooks логирует резолвнутый `$HOOKS_DIR`.

**Гейты:** оба governed-ревьюера недоступны по инфре (Codex companion timeout ×2; mb-judge 401 auth) → замена строгим адверсариальным саморевью + полным перепрогоном. e2e **43/43** (bats exit 0, + кейсы A6 true-original и A7 trap-flush), cline 22/24, git-hooks 25/28 (падения = pre-existing `hooks/` auto-capture, baseline-подтверждено stash-ем), shellcheck 0 new ×4. install.sh(1038)/cursor.sh(640) — предсуществующие крупные installer-скрипты (backlog-остаток размера, не регрессия).

---

## Batch 3 — исполнено (B2·B3·B6·B7 — cross-agent parity), judge = GO_WITH_BACKLOG (2026-07-05)

Governed: implement (mb-developer, TDD RED→GREEN) → независимая верификация → Codex-review **SKIPPED** (companion пусто ×2, инфра) → **mb-judge как первичный гейт** (расширенный мандат). B2: `install.sh:938` доставляет `commands/*.md`→`$CODEX_DIR/prompts/` (29). B3: `opencode.sh` копирует 27/29 dispatchable-агентов (partials исключены), backup-once, манифест, uninstall rmdir. B6: `OPENCODE_SKILL_ALIAS` symlink + `commands/mb.md` 27 ссылок→`${MB_SKILLS_ROOT:-…}`. B7: `mb-subinvoke-resolve.sh` арм-ы pi/opencode, grammar-guard гейтит модель ПЕРЕД case (injection-safe), override branch-1 сохранён.

mb-judge независимо перепрогнал: комбинированный **95/95** (4 подряд green); единичный флейк `test_codex_adapter #34` = артефакт `rsync $REPO_ROOT/` живого дерева при конкурентной мутации параллельной сессией (в изоляции 3/3 green, не дефект B2-кода). shellcheck 0 TOTAL ×4, injection-тесты pass, ноль запутывания с файлами параллельной сессии.

### Backlog-резидуалы (из judge GO_WITH_BACKLOG):
- **R3-1 [MINOR, tests]** `setup_codex_prompts_sandbox`/`setup_skill_alias_sandbox` делают `rsync -a "$REPO_ROOT/"` живого дерева → конкурентная мутация даёт неконсистентный снимок (транзиентный флейк #34). Харден через `git archive`/clean-checkout снимок или retry. Проявляется только при аномальной конкурентной мутации; тихий CI не затронут.
- **R3-2 [MINOR, docs]** Дрейф счётчиков в plan-тексте исправлен inline (24→29 total, 17→27 dispatchable) в DoD B2/B3; исходные оценки были устаревшими, рантайм-влияния нет.

---

## Batch 4 — исполнено (A10-A16 — Track A MED/LOW), judge = GO_WITH_BACKLOG (2026-07-05)

Governed: implement (mb-developer, TDD RED→GREEN, строго последовательно) → независимая верификация → Codex-review **SKIPPED** (companion пусто, инфра) → **mb-judge первичный гейт** (расширенный мандат). A10: uninstall.sh per-adapter uninstall + refcount декремент (клиенты+root в манифесте). A11: deps-check python>=3.11. A12: `_lib.sh::mb_resolve_manifest_path` user-writable fallback (XDG) — единый путь install/uninstall, поверх A7. A13: CLAUDE.md refresh backup + парные маркеры (slice-before-mv ordering-фикс) + версия отдельной строкой. A14: BSD-safe mktemp + `[]`-фильтр. A15: `%q` для MB_SKILLS_ROOT. A16: backup+atomic hook-write во ВСЕХ 4 адаптерах (opencode/cline/git-hooks/**windsurf** — windsurf добавлен follow-up'ом чтобы закрыть stage полностью).

mb-judge независимо перепрогнал (последовательно, чистя манифест между): 9 unit/adapter suites **143/148** + e2e **47/47**; 5 red = pre-existing `hooks/` auto-capture (cline #8/#17, git-hooks #10/#11/#29), воспроизведены на unmodified HEAD (`git show HEAD:`) → parallel-session домен, не A16-регрессия. shellcheck 0 ×11; A12 highest-risk (единый путь, XDG-fallback, override, A7 цел), A13 ordering, A14/A15/A16 — все руками сверены. Дифф-скоуп чист (21 файл, ноль запутывания с reviewer-2.0/work-loop).

### Backlog-резидуалы (из judge GO_WITH_BACKLOG):
- **R4-1 [MINOR, maintainability]** `scripts/_lib.sh` = 581 строк (+39 здесь) — предсуществующая крупная общая библиотека > ≤400. Кандидат на разбиение. Track C / отдельный рефактор.
- **R4-2 [MAJOR, out-of-scope]** 5 pre-existing `hooks/` auto-capture падений (cline #8/#17 after-tool; git-hooks #10/#11/#29 post-commit placeholder/session-lock/MB_PATH) — домен параллельной сессии (`hooks/lib/session-common.sh`, `hooks/mb-session-turn.sh`), baseline-подтверждено across all batches. Чинить в их треке, не здесь.
- **R3-1 расширен** — hermeticity касается и A12 e2e (`setup_readonly_skill_sandbox` rsync живого дерева). Тот же fix (git-archive/clean-checkout снимок).

## Batch 5 — исполнено (A17-A22 — Codex install delta), judge = GO_WITH_BACKLOG (2026-07-06)

Governed: implement (mb-developer, TDD RED→GREEN, строго последовательно A17→A22) → независимая верификация → Codex-review **SKIPPED** (companion инфра-down всю сессию) → **mb-judge первичный гейт** (расширенный адверсариальный мандат). A17: провал адаптера → `ADAPTERS_FAILED` + top-level `exit 1` + статус `adapters_failed/adapters_invoked` в манифест (missing/not-exec теперь тоже fail); успешные ставятся. A18: единый source of truth `_texttools.resolve_language_strings` — es/zh → honest fallback на en + one-time warning (никогда не пусто), опция (a) по рекомендации плана; ru не задет. A19: ноль голого `python3` в `_lib.sh` (все 5 вхождений: mb_normalize_path/mb_resolve_real_path/mb_project_id/mb_registry_lookup/mb_pipeline_meta) + `mb-init-bank.sh:226` + pi-ext (`process.env.MB_PYTHON||"python3"`) → `${MB_PYTHON:-python3}`; heredocs параметризованы, MB_PYTHON закавычен; grep-инвариант тест. A20: uninstall strip managed-блока по парным A13-маркерам, пост-install правки CLAUDE.md сохранены; попутно root-cause фикс latent install.sh бага («no-marker» ветка mv'ила оригинал прочь и `>>`-аппендила в отсутствующий путь = вела себя как `>`); legacy `has_start&&!has_end` ветка намеренно не тронута. A21: install персистит language/clients_requested/project_root в манифест, mb-upgrade rerun non-interactive с ними; старая схема → fallback+warning; явные флаги override; неподдержанные clients дропаются. A22: `adapter_write_manifest` атомарно (mktemp-same-dir + mode-preserve + mv); uninstall валидирует JSON, на битом → nonzero без `--force`; попутно пофикшен latent unbound `YELLOW` (set -u краш).

mb-judge независимо перепрогнал (последовательно, чистя манифест): pytest test_cli_lang **21/21**; bats test_mb_python_resolution **6/6**, test_adapter_framework **8/8**, test_upgrade **10/10**, test_install_clients **16/16** (A17 #14-16), test_install_uninstall **50/50** (A20 #38, A22 #44-45). shellcheck 0 ×6, ruff clean. **Усилил baseline-доказательство:** заметил, что `_framework.sh` (A22) реально подключается cline/kilo/git-hooks и они зовут `adapter_write_manifest`, поэтому не остановился на «не ссылается» — откатил `adapters/_framework.sh` к `git show HEAD:` in-place, перепрогнал → идентичные 6 red (cline #8/#17, kilo #6, git-hooks #10/#11/#29 — все runtime auto-capture), install-time manifest-тесты зелёные → доказано pre-existing, не Batch 5-регресс; файл восстановлен. Общий прогон оркестратора: BATS **340/346** (те же 6 baseline-red) + pytest 21/21. A19 TDD-девиация (dedicated-тест написан чуть после фикса) принята — компенсирована реальным RED против pristine `git show HEAD:` копий (6/6 упали по правильной причине), shipped-инвариант — настоящий регресс-гард.

### Backlog-резидуалы (из judge GO_WITH_BACKLOG):
- **R5-1 [MINOR, logic]** `scripts/mb-upgrade.sh:263` — partial-override (`mb-upgrade --language en` в одиночку) пропускает чтение персистнутого `--clients` из-за гарда `[ -z lang ] && [ -z clients ]`, сбрасывая адаптеры. Не регресс (до A21 дропалось всё), full-override протестирован и работает. Фикс: читать каждую персистнутую опцию независимо от переданных флагов.
- **R5-2 [MINOR, cleanup]** `uninstall.sh:137` — CLAUDE.md-ветка `continue`'ит мимо `.pre-mb-backup.*` не удаляя его → бэкап-копия остаётся в `~/.claude` после uninstall (не потеря данных, возможно намеренный safety-net). Решить: удалять после успешного strip или задокументировать как намеренное.
- **R5-3 [MINOR, tests]** `tests/bats/test_adapter_framework.bats:61` — `find -name '*.XXXXXX'` никогда не матчит развёрнутый mktemp-суффикс → no-op ассерт; вторая ассерция (`basename.*`) делает реальную работу. Косметика — заменить на матч реального tmp-паттерна.

## Batch 6 — исполнено (A23·A24·A25·B4·B5·B8·B9 — хвост Track A/B), judge = GO_WITH_BACKLOG (2026-07-06)

Governed: implement (mb-developer, TDD RED→GREEN, строго последовательно A24→A23→B4→B9→B5→B8→A25) → независимая верификация → Codex-review **SKIPPED** (инфра-down) → **mb-judge первичный гейт** (расширенный адверсариальный мандат). A23: `backup_if_exists` + `_*_backup_once` идемпотентные хелперы перед whole-file записью rules/commands (cursor `.mdc`, cline rules, opencode commands) + запись в манифест `backups`; граница с A16 (hooks) соблюдена. A24: uninstall EOF-детект `if ! read -r c; then <hint>; exit 1` — **поведенчески лучше** предложенного `[ ! -t 0 ]` гарда (сохраняет `echo y | uninstall.sh`). A25: docs-only — README + cross-agent-setup документируют «global agents ставятся всегда, не гейтятся --clients» + call-site комментарий; gating оставлен явным OPEN-решением (не реализовано). B4: cursor вешает `mb-session-end.sh` (CC-совместимый rich capture) вместо `session-end-autosave.sh`; opencode-плагин `runSummarize` detached+unref, fail-open (fs.existsSync + try/catch), `MB_SUMMARIZE_BIN` seam; e2e cursor_global обновлён. B5: codex.sh git-hooks-fallback (зеркалит pi.sh), worktree-safe (`git -C … rev-parse --git-dir`, .git-as-file), non-git → skip; `git_hooks_installed` в манифесте, uninstall читает флаг ДО rm. B8: `mb-reviewer-resolve.sh` `SKILLS_ROOTS` += `~/.codex/skills`, `~/.pi/agent/skills`, `~/.config/opencode/skills`; `MB_SKILLS_ROOT` short-circuit сохранён; новый `test_reviewer_resolve.bats`; тронут ТОЛЬКО resolve (не `mb-review.sh` — reviewer-2.0 домен). B9: opencode plugin registration = **auto-discovery** (код только *стрипает* stale-ref из opencode.json, никогда не добавляет; docs выровнены; grep-guard тест).

mb-judge независимо перепрогнал (последовательно, чистя манифест): cursor 15/15, opencode 28/28, codex **39/39**, reviewer_resolve **6/6** (new), cline 25/27, e2e install_uninstall A24 3/3, e2e cursor_global B4 зелёный. shellcheck 0 ×7. **Регресс-доказательство:** откатил `adapters/cline.sh` к HEAD, перепрогнал cline #9/#18 → падают и на HEAD → pre-existing runtime after-tool auto-capture (домен hooks/), не A23-регресс (A23 = install-time `_cline_backup_once`, ортогонально). Остальные 4 red (kilo #6, git-hooks #10/#11/#29) — в hooks/, Batch 6 не трогал. Boundary-аудит: ноль изменений в `hooks/`/`scripts/mb-review.sh`; дифф не ссылается на mb-drive.sh/test_mb_drive.bats (параллельный drive-loop не тронут). Общий прогон оркестратора: BATS **242/248** (те же 6 baseline-red).

### Backlog-резидуалы (из judge GO_WITH_BACKLOG):
- **R6-1 [MINOR, tests]** A23 idempotency-регресс-тест отсутствует — `_*_backup_once` гарантируют «no proliferation» по построению, но тест не фиксирует. Добавить re-install тест на единственный `.pre-mb-backup.*` в cursor/cline/opencode suites.
- **R6-2 [MINOR, logic]** `adapters/opencode.sh:256` — `_opencode_backup_once` на commands-цикле бэкапит MB-собственный контент на 2-й install (ключуется на «бэкап уже есть», не на «маркер/юзер-контент») → один лишний `.pre-mb-backup` MB-файла; не потеря данных, зеркалит предсуществующий agent-file паттерн. Marker-aware skip чище.

## Batch 7 — исполнено (C1·C2·C3·C4·C5·C6·C7 — Track C docs+tests), judge = GO_WITH_BACKLOG (2026-07-06) — **ПЛАН ЗАВЕРШЁН**

Governed: implement (mb-developer, TDD-first где применимо, строго последовательно C2→C1→C6→C5→C3→C4→C7) → независимая верификация → Codex-review **SKIPPED** (инфра-down) → **mb-judge первичный гейт** (расширенный мандат). C1: doc-vs-reality D-1/D-2/D-4/D-5(install.sh)/D-6(opencode) — Pi lifecycle-overclaim → git-hooks-fallback, Codex SessionEnd → «git-hooks-fallback (B5)», IDE↔CLI противоречие исправлено (cursor-extension.md авторитетно), opencode «native tool wrappers» убрано; 3 grep-guard теста scoped на docs/. C2: README git+bash deps (M-3) + версия v5.2.0 из VERSION (L-1) + `sudo -E` doc (L-6) + инвариант-тест для L-7 (уже выполнено). C3: новый `test_upgrade_e2e.bats` (3/3, writable rsync-копия, true-first-backup через vN→vN+1). C4: новый `test_cross_agent_runtime_parity.bats` (4 ok + 1 explicit Windsurf skip; placeholder/capture/gate + честная деградация git-hooks-fallback; MB_AUTO_CAPTURE override для реального дефолта). C5: `adapter_contract_require_artifacts` — проверяет наличие каждого `files[]` пути (не только `declare -F`); broken-parity stub падает; 12/12. C6: install.sh:4 18→29, README cursor-hooks «not copied», /flow+/analyze-task+/goal в таблицу, hooks-матрица, doc-count guard. C7: новый `test_install_reliability.bats` (4/4, агрегирующие гарды A17/A22/A24, sandboxed HOME).

mb-judge независимо перепрогнал ВСЁ (не доверял summary): pytest **22 passed / 1 failed**, все новые/расширенные bats зелёные (adapter_framework 12/12, runtime_parity 5/5, upgrade_e2e 3/3, install_reliability 4/4), shellcheck 0 ×3, ruff clean. **Baseline-доказательства:** (1) pytest-фейл `test_skill_md_script_table_lists_all_scripts` — запустил HEAD-версию теста in-tree, падает идентично; 4 недостающих скрипта (mb-drive/mb-work-contract/pivot/trend) — коммиты параллельной сессии (a39d4a2), SKILL.md параллельно-владеемый+нетронутый, reflow behavior-preserving. (2) 6 bats-reds (cline #9/#18, kilo #6, git-hooks #10/#11/#29) — Batch 7 не трогает hooks//cline/kilo/git-hooks; корень = ambient `MB_AUTO_CAPTURE=off` (подтверждено).

### Backlog-резидуалы (из judge GO_WITH_BACKLOG + deferrals):
- **R7-1 [MAJOR, docs-vs-code]** Pi TS lifecycle-extension всё ещё описан как устанавливаемый: `references/hooks.md:264-273` + `scripts/mb-session-doctor.sh:139-141` ожидают `~/.pi/.../extensions/*.ts`, которого ни один адаптер не копирует (D-1 residual, вне скоупа батча). Либо реализовать установку extension, либо убрать обещание.
- **R7-2 [MAJOR, code]** Pi skill-mode подпапки vs реальность: `adapters/_lib_pi_global.sh:28` обещает `{commands,agents,hooks,scripts,references,rules}/`, но `adapters/pi.sh:58` `install_skill_mode` пишет только минимальный SKILL.md (:100) (D-5 реальный баг, вне скоупа). Wire install_skill_mode или смягчить текст compat-пути.
- **R7-3 [MINOR, docs]** `SKILL.md:106` «## Tools» таблица не перечисляет mb-drive.sh / mb-work-contract.sh / mb-work-pivot.sh / mb-work-trend.sh (владеет параллельная сессия; красный тест до добавления строк владельцем SKILL.md).
- **R7-4 [MINOR, tests]** README версия без drift-guard: `README.md:575` хардкодит «v5.2.0» в прозе; у homebrew/cli есть VERSION-drift тесты, у README-прозы нет → риск тихого дрейфа при следующем bump. Рассмотреть README-vs-VERSION тест.

---

## ✅ ПЛАН ЗАВЕРШЁН (2026-07-06)

Все 34 стадии (Track A: A1-A25, Track B: B1-B9, Track C: C1-C7) исполнены через governed-циклы (implement→verify→judge, Codex-канал infra-down всю сессию → mb-judge первичный гейт с расширенным мандатом), закоммичены пакетно: Batch 1 (A1-A4·B1), 2a (A5·A8·A9), 2b (A6·A7), 3 (B2·B3·B6·B7), 4 (A10-A16), 5 (A17-A22), 6 (A23-A25·B4·B5·B8·B9), 7 (C1-C7). Каждый батч: независимая верификация (последовательный прогон, чистка манифеста) + mb-judge GO_WITH_BACKLOG. Отложенные остатки (R-серии, все MINOR кроме R7-1/R7-2 которые вне скоупа плана и касаются pi.sh/references) — в этом же файле выше. 6 baseline hooks/ auto-capture reds + 1 SKILL.md-drift pytest-fail — домен параллельной сессии (корень: ambient `MB_AUTO_CAPTURE=off`), подтверждено baseline на каждом батче, не регрессии этого плана.
