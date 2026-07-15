---
topic: agreements
created: 2026-07-15
status: ready
---

# Context: agreements — Running List of Agreements

## Purpose & Users

**Кто использует.** Пользователь скилла memory-bank и сама модель (плюс сабагенты `/mb work`): реестр — канонический слой «какие решения действуют прямо сейчас», отделённый от истории обсуждения (progress.md), обоснований (ADR) и правил стека (RULES.md).

**Проблема.** В длинных сессиях решения размазаны по десяткам сообщений: модель реализует отменённый вариант, переоткрывает закрытые вопросы, передаёт сабагентам устаревшие требования. Резюме сохраняет повествование; реестр сохраняет исполняемые решения.

**Критерии успеха.**
- Модель в новой сессии соблюдает действующие договорённости без напоминаний (они в CLAUDE.md/AGENTS.md).
- Закрытые вопросы не переобсуждаются: rejected/superseded видны с их статусом.
- `/mb verify` ловит нарушения договорённостей до `/mb done`.
- Ноль токен-налога в банках, где фича не используется (lazy-активация).

**Источник дизайна:** grilling-интервью 2026-07-15 (8 подтверждённых решений) по мотивам `running-list-of-agreements-llm.md`.

## Functional Requirements (EARS)

- **REQ-001** (ubiquitous): The agreements registry shall store confirmed decisions in `<bank>/agreements.md` with monotonic never-reused `AGR-NNN` identifiers, an ISO date, a source, and exactly one of four statuses: active, deferred, superseded, rejected.
- **REQ-002** (event-driven): When a confirmed decision is captured, the system shall persist it exclusively through `mb-agree.sh` subcommands (`add`, `supersede`, `defer`, `reject`, `question`, `resolve`, `list`, `sync`) rather than direct file edits by the model.
- **REQ-003** (event-driven): When `mb-agree.sh add` is invoked in a bank without `agreements.md`, the system shall create the file from the template (sections: Active / Deferred / Open Questions / Archive) — lazy activation, no artifacts before first use.
- **REQ-004** (event-driven): When `mb-agree.sh add --supersedes N` is invoked, the system shall atomically create the new active entry, mark `AGR-N` as superseded with a link to the new ID, and move it to the Archive section in the same operation.
- **REQ-005** (event-driven): When any mutating subcommand completes, the system shall regenerate the managed block (`<!-- mb-agreements:start -->` … `<!-- mb-agreements:end -->`) in the project-root `CLAUDE.md` and `AGENTS.md` with every active agreement as a one-liner `AGR-NNN: statement` plus a single pointer line to `<bank>/agreements.md`.
- **REQ-006** (unwanted): If neither `CLAUDE.md` nor `AGENTS.md` exists in the project root, then the system shall create `AGENTS.md` containing only the managed block.
- **REQ-007** (unwanted): If the number of active agreements exceeds 25, then the system shall print a prune warning and shall still include all active agreements in the managed block without silent truncation.
- **REQ-008** (state-driven): While `MB_AGREEMENTS=off` is set in `.mb-config`, the system shall reject every `mb-agree.sh` subcommand as an explained no-op and shall not modify `CLAUDE.md`, `AGENTS.md`, or `agreements.md`.
- **REQ-009** (ubiquitous): The skill rules shall instruct the model to record only explicitly confirmed user decisions, to announce every recorded entry visibly as `→ AGR-NNN записано: <statement>`, and to route unconfirmed hypotheses to Open Questions instead of Active.
- **REQ-010** (event-driven): When `/mb verify` runs in a bank where `agreements.md` exists, the verifier shall classify every active agreement as satisfied, violated, or not-applicable and shall include the classification in its report.
- **REQ-011** (unwanted): If any active agreement is classified as violated, then the verifier shall return a FAIL verdict and shall present the explicit choice: fix the implementation or supersede the agreement.
- **REQ-012** (ubiquitous): The file `agreements.md` shall be the single source of truth; `mb-agree.sh sync` shall rebuild the managed block from the file so that manual file edits can be reconciled.
- **REQ-013** (unwanted): If `--supersedes N` references a non-existent or non-active agreement, then the system shall exit with a clear error and shall change nothing.
- **REQ-014** (event-driven): When two parallel sessions mutate the registry concurrently, the system shall serialize mutations via a lock so that issued IDs remain unique and no update is lost.
- **REQ-015** (optional): Where a decision has a companion ADR, the registry entry shall carry a `→ ADR-NNN` reference and the detailed rationale shall live in the ADR, not in the registry.
- **REQ-016** (event-driven): When `mb-agree.sh question` or `resolve` is invoked, the system shall add or close an entry in the Open Questions section without touching the managed block (Open Questions are not injected).

## Non-Functional Requirements

- **NFR-001**: Token economy — managed block contains only active one-liners + one pointer line; no dates, sources, rationale. Banks without agreements get zero added tokens and zero files.
- **NFR-002**: Compatibility — pure bash, bash 3.2 compatible, no new dependencies; shellcheck clean; works with local, global (registry.json), and legacy bank layouts via `mb_resolve_path`.
- **NFR-003**: Atomicity — all writes go through temp-file + `mv`; concurrent safety via the same lock idiom used elsewhere in the skill.
- **NFR-004**: Idempotence — `sync` is idempotent: repeated runs over an unchanged registry produce byte-identical CLAUDE.md/AGENTS.md.
- **NFR-005**: Preservation — outside the managed block, CLAUDE.md/AGENTS.md content is byte-preserved on every regeneration.

## Constraints

- Дизайн-контракт скилла: дефолты не меняются — до первого `/mb agree` в банке фича не оставляет следов; kill-switch `MB_AGREEMENTS=off`.
- Инварианты банка: `AGR-NNN` монотонные и никогда не переиспользуются; записи Archive не удаляются (append-only, как progress.md).
- Внутри CLAUDE.md/AGENTS.md скрипт трогает только managed-блок (protected-files дисциплина).
- TDD: bats-тесты пишутся до реализации; роли исполнения — по standing role division (`/mb work`: Sonnet-имплементер, ревью, Opus-судья).
- Statement — одна строка (скрипт отклоняет переводы строк): формат `- AGR-NNN (YYYY-MM-DD, source): statement [supersedes AGR-X] [→ ADR-YYY]`.

## Edge Cases & Failure Modes

- **Повреждённый managed-блок**: start-маркер без end-маркера → скрипт завершается с ошибкой, файл не трогает (не рискуем чужим содержимым). Оба маркера отсутствуют → блок добавляется заново в конец файла.
- **Ручная правка agreements.md** сломала формат строки → мутирующие команды падают с указанием строки; `sync` не пересобирает блок из невалидного файла.
- **supersede уже superseded/rejected записи** → ошибка «AGR-N is not active», без изменений (REQ-013).
- **Два параллельных `add`** (реальный кейс: COORDINATION.md-сессии) → лок сериализует, оба получают уникальные ID (REQ-014).
- **Global bank**: `agreements.md` живёт в резолвленном банке, но блок пишется в CLAUDE.md/AGENTS.md корня проекта.
- **CLAUDE.md недоступен на запись** → запись в реестр удаётся, синк падает громко с подсказкой запустить `sync` позже; реестр и блок расходятся временно, но file-of-truth цел.
- **Active > 25** → предупреждение, полный блок (REQ-007); чистка — решение пользователя.

## Out of Scope

- YAML-зеркало с метаданными (scope, evidence, owner).
- Conflict registry (`CONFLICT-NNN`) и автодетект противоречий.
- Scoped-файлы по областям и выборочная передача сабагентам (`relevant_agreements`).
- Agreement-гейт на каждой стадии `/mb work` (только `/mb verify`).
- Статусы proposed/confirmed/deprecated/invalidated (двухуровневый цикл кандидатов).
- Pinned-подмножества и top-N эвристики для инжекта.
- Семантическая дедупликация записей.
