# Install Idempotency Fix — `3.0.0-rc3`

**Тип:** bugfix
**Дата:** 2026-04-20
**Статус:** active

## Context

14 последовательных прогонов `install.sh` на одной машине накопили **1628** `.pre-mb-backup.*` файлов. Из них **37 из 48** созданных за один чистый прогон — с содержимым идентичным текущим файлам (подтверждено `cmp -s`; mtime показывает, что `mv` просто переименовал уже-установленный файл).

## Root cause

[install.sh](../../install.sh):284-291 `backup_if_exists()` делает безусловный `mv` на любой существующий файл. [install.sh](../../install.sh):293-299 `install_file()` вызывает `backup_if_exists` перед `cp`, не сравнивая содержимое. Результат: каждый install на установленной системе бэкапит все managed-файлы (18 commands × 3 targets + 4 agents + 4 hooks + ...), даже когда бэкапить нечего.

Два подслучая:
1. **No-localize файлы** (commands/*, agents/*, hooks/*): `cmp -s src dst` → идентичны → backup избыточен.
2. **Localize-target файлы** (RULES.md, cursor user-rules): `src ≠ dst` на диске (dst отлокализован), но `cmp -s localize(src) dst` → идентичны. Нужен compose-and-compare паттерн.

## Target state

```bash
$ bash install.sh --non-interactive --clients claude-code,cursor,codex
$ bash install.sh --non-interactive --clients claude-code,cursor,codex  # repeat
$ find ~/.claude ~/.cursor ~/.codex -name "*.pre-mb-backup.*" | wc -l
0
```

Первый install на чистой системе: 0 бэкапов (файлов нет).
Второй install поверх первого: 0 бэкапов (контент идентичен).
Install после правки source repo: backups только для реально изменившихся файлов.

## Scope

- Fix `install_file()` + `backup_if_exists()` в install.sh для honoring content identity.
- Добавить `install_file_localized()` + `localize_path_inplace()` helpers.
- Fix `install_cursor_user_rules_paste()` — compose expected, compare, skip.
- Manifest cleanup: фильтровать `backups[]` оставляя только существующие на диске пути.

**Out of scope:**
- Политика keep-last-N для бэкапов (skip-if-identical отменяет нужду).
- Рефакторинг adapters/*.sh (не источник проблемы — не используют `backup_if_exists`).

## File changes

### install.sh

1. **`backup_if_exists(target, [expected_content_path])`** — принимает optional 2-й аргумент. Если указан и `cmp -s target expected` → `return 2` (skip marker). Legacy 1-arg вызовы работают как раньше.
2. **`install_file(src, dst)`** — перед `backup_if_exists` делать `cmp -s src dst`. Идентичны — записать в `INSTALLED_FILES` и выйти no-op.
3. **`localize_path_inplace(path, [marker])`** — обёртка над python3-heredoc из `localize_installed_file`, работает на произвольном пути.
4. **`install_file_localized(src, dst, [marker])`** — cp в tmp, localize, cmp, skip или backup+mv.
5. **Step 1 RULES.md** — `install_file + localize_installed_file` → `install_file_localized`.
6. **`install_cursor_user_rules_paste()`** — compose expected в mktemp + `cmp -s` + skip.
7. **Step 7 Manifest** — python-блок фильтрует `.backups[]` от несуществующих на диске путей.

### tests/e2e/test_install_idempotent.bats (новый)

Пять сценариев:
- `second install creates zero new .pre-mb-backup.*`
- `install after src bump creates exactly one backup per changed file`
- `install after external delete of managed files creates zero backups`
- `localize-target files (RULES.md) idempotent across language changes`
- `manifest backups[] contains only existing paths`

### CHANGELOG.md / VERSION / README.md

`3.0.0-rc2` → `3.0.0-rc3`. CHANGELOG секция с Fixed/Added/Changed. README — строка про идемпотентность.

## Stages (bite-sized)

1. **plan-file** — этот файл + обновить `checklist.md`, `status.md`, `roadmap.md` <!-- mb-stage:1 -->
2. **bats-red** — `tests/e2e/test_install_idempotent.bats`, 5 сценариев, RED confirmed <!-- mb-stage:2 -->
3. **helpers** — `localize_path_inplace()` + расширение `backup_if_exists()` (optional 2-nd arg) <!-- mb-stage:3 -->
4. **install_file-cmp** — `install_file()` с ранним cmp-skip <!-- mb-stage:4 -->
5. **install_file_localized** — новая функция + использование в Step 1 для RULES.md <!-- mb-stage:5 -->
6. **cursor-user-rules-cmp** — `install_cursor_user_rules_paste()` compose-to-tmp + cmp skip <!-- mb-stage:6 -->
7. **manifest-prune** — фильтрация `.backups[]` от несуществующих путей <!-- mb-stage:7 -->
8. **bats-green** — 5 сценариев зелёные + test_cursor_global.bats без регрессий <!-- mb-stage:8 -->
9. **release** — VERSION bump, CHANGELOG, README, progress.md <!-- mb-stage:9 -->

## Verification

- `bats tests/e2e/test_install_idempotent.bats` → all green
- `bats tests/e2e/test_cursor_global.bats` → 17/17 green (no regression)
- Ручная проверка: sandbox-HOME, двойной install → `find … -name "*.pre-mb-backup.*" | wc -l` == 0

## DoD

- [ ] Stage 1-9 выполнены
- [ ] 5 bats-сценариев зелёные
- [ ] `test_cursor_global.bats` без регрессий
- [ ] CHANGELOG.md содержит `[3.0.0-rc3]` с Fixed/Added/Changed
- [ ] VERSION == 3.0.0-rc3, sync'нут с `memory_bank_skill/__init__.py`
- [ ] progress.md запись с итогом
