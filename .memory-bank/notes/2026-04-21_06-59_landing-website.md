# Landing Website Launch

- Для project-site на GitHub Pages достаточно держать сайт в `site/` и деплоить его официальным workflow через `actions/upload-pages-artifact`.
- В HTML лучше использовать только относительные локальные пути (`styles.css`, `app.js`), тогда проектный URL вида `/skill-memory-bank/` работает без дополнительного base-path слоя.
- Внешние шрифты можно импортировать из CSS, а HTML smoke-тестом проверять только локальные ассеты и ключевые секции.
- Для безопасного rollout удобно сначала создать pytest contract test на страницу и workflow, а уже потом добавлять разметку и CI.
- После push Pages можно включить через GitHub REST API: `POST /repos/{owner}/{repo}/pages` с `build_type=workflow`.
- Полезный follow-up: держать repo homepage URL синхронизированным с Pages, чтобы сайт был виден прямо в шапке GitHub-репозитория.
