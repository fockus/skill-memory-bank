---
type: pattern
tags: [audit, regression, source-identity, privacy]
importance: high
created: 2026-09-14
---
# Проверять границы между памятью, исполнением и упаковкой
- Подтверждение задачи связывается с canonical source в момент init; повторный resolve после done может перенести подтверждение через symlink.
- Relative/legacy paths должны одинаково разрешаться при init и Eval; неоднозначное состояние не даёт право менять DoD.
- Pending goal acceptance не означает ошибку текущей реализации; финальная готовность проверяется полным firewall отдельно.
- Private spans нужно разбирать до извлечения структурных записей, сохраняя публичный текст за закрытым блоком.
- Shell-фрагменты Markdown проверяются из чужого cwd и с global-only bank; prompt paths также должны использовать установленный skill root.
- Точное qualified определение в code context резервирует место до semantic-кандидатов и одноимённых методов.
- Source-bundle smoke дополняется установленным wheel и тестом соседства со старым Python-пакетом.
Доказательства: [исправления 15 находок](../reports/2026-09-14_skill-audit-remediation.md).
