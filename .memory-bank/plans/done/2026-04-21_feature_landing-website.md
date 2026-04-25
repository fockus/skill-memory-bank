# Plan: feature — landing-website

## Context

**Problem:** У проекта `memory-bank-skill` нет публичного лендинга для GitHub Pages. Репозиторий и README уже объясняют продукт, но нет отдельного красивого сайта для showcase, onboarding и sharable entrypoint.

**Expected result:** В репозитории появляется выразительный одностраничный сайт в стиле reference `launchx.page/mex`, но с собственной айдентикой `memory-bank-skill`; сайт проходит локальный smoke, деплоится через GitHub Pages и доступен из GitHub-репозитория.

**Related files:**
- `README.md`
- `SKILL.md`
- `.github/workflows/`
- `https://www.launchx.page/mex`

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Контракт страницы и smoke-тест

**What to do:**
- Зафиксировать структуру лендинга: hero, problem, workflow, integrations, install, CTA
- Добавить pytest smoke-тест на существование ключевых секций и связанных ассетов
- Выбрать способ хранения сайта в репозитории без нового frontend-стека

**Testing (TDD — tests BEFORE implementation):**
- Pytest: `site/index.html` существует
- Pytest: ключевые `id`/CTA/metadata присутствуют
- Pytest: локальные CSS/JS/SVG ассеты, упомянутые в HTML, существуют на диске

**DoD (Definition of Done):**
- [x] Появился красный тест, описывающий контракт лендинга
- [x] Структура страниц и ассетов определена без добавления новых runtime dependencies
- [x] tests pass
- [x] lint clean

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

<!-- mb-stage:2 -->
### Stage 2: Реализация визуального лендинга

**What to do:**
- Реализовать статический сайт в `site/` с собственным художественным направлением
- Перенести ключевые value props из README/SKILL в продающий лендинг
- Добавить адаптивность, выразительную типографику, атмосферный фон и terminal-style demo blocks

**Testing (TDD):**
- Pytest smoke из Stage 1 должен стать зелёным
- Локальный smoke через статический preview/сборку должен подтвердить, что страница рендерится без missing assets

**DoD:**
- [x] Лендинг визуально завершён и адаптивен для desktop/mobile
- [x] Контент отражает 8 поддерживаемых агентов, workflow и install path
- [x] Локальный smoke подтверждает корректную загрузку страницы

---

<!-- mb-stage:3 -->
### Stage 3: GitHub Pages и project wiring

**What to do:**
- Настроить workflow деплоя GitHub Pages
- Обновить документацию/README ссылкой на сайт
- Выложить изменения в `origin/main` и включить Pages для репозитория

**Testing (TDD):**
- Проверка workflow YAML на валидную привязку к `site/`
- Smoke после push: GitHub Pages deployment job создаётся успешно
- Проверка live URL после включения Pages

**DoD:**
- [x] GitHub Pages настроен и сайт опубликован
- [x] Repo metadata указывают на публичный сайт
- [x] Verification выполнен и зафиксирован в Memory Bank

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Лендинг получится красивым, но не будет отражать реальный продукт | M | Брать контент напрямую из README/SKILL и проверять каждую секцию против фактических фич |
| GitHub Pages workflow окажется несовместим с текущей структурой репозитория | M | Использовать официальный Pages workflow без дополнительного build toolchain |
| Деплой не поднимется из-за repo settings | M | После push включить Pages через `gh api` и проверить live URL |

## Gate (plan success criterion)

План завершён, когда репозиторий содержит протестированный статический лендинг, GitHub Pages публикует его из текущего `main`, а ссылка на публичный сайт отражена в документации проекта.

**Status:** ✅ Completed on 2026-04-21. Live URL: `https://fockus.github.io/skill-memory-bank/`
