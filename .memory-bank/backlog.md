# Backlog

## Ideas

- I-086 follow-up (LOW) — propagate `memory_bank_skill.pipeline_yaml.load_file` to all 13 `safe_load` pipeline callers (Stage 2 scoped validate path only).
- I-114 (LOW, docs-site plan Stage 1, 2026-07-15) — consolidate duplicated docs deps in `pyproject.toml`: they live in both `[project.optional-dependencies].docs` and `[dependency-groups].docs` (deliberate — `uv --group` reads PEP 735, `pip install .[docs]` reads extras), but versions can drift out of sync. Keep in sync or consolidate when tooling allows. Source: verifier + judge (GO_WITH_BACKLOG).
- I-115 (LOW, docs-site plan Stage 1, 2026-07-15) — `mkdocs build --strict` alone will NOT fail on a Stage 2/3 page forgotten from nav: `links.not_found` is downgraded to `info` and mkdocs treats orphan/omitted pages as INFO by default. Keep the deterministic file-vs-nav cross-check (`find docs -name '*.md'` ↔ nav) in Stage 2/3 verification. Source: verifier + judge.
- I-117 (LOW, docs-site plan Stage 4, 2026-07-15) — SHA-pin GitHub Actions in `.github/workflows/pages.yml` (`astral-sh/setup-uv@v3`, `actions/*`) for reproducible/supply-chain-hardened deploys. Non-blocking: docs-only deploy, and the repo does not SHA-pin actions elsewhere (consistency, not regression). Do it as part of a repo-wide action-pinning pass. Source: codex-review + judge.
- I-116 (LOW, docs-site plan Stage 2/3, 2026-07-15) — README.md lines ~548–578 ("Staying up to date" + env-var table, from committed work a46473a) document `MB_UPDATE_CHECK`/`MB_UPDATE_CHECK_TTL`/`MB_AUTO_UPDATE`, but these ship with update-notify which is still in CHANGELOG [Unreleased]. New docs-site pages deliberately excluded them, so README and `docs/environment-variables.md` will diverge until update-notify tags a release. Reconcile at that release: move update-notify out of [Unreleased] and add the env-var rows to `docs/environment-variables.md`. Source: judge (GO_WITH_BACKLOG) + main-agent.



<!-- Cluster I-082..I-086 — codex/GPT-5.5 adversarial review 2026-06-23. Source: reports/2026-06-23_codex-gpt5.5-skill-review.md (9 read-only sessions). -->

### I-082 — Security hardening: code-exec + path traversal + private/secret leak [HIGH, DONE 2026-07-15, 2026-06-23] — Wave 1, commit 49f9ad5, план plans/done/2026-06-23_fix_security-hardening.md

**Context:** codex/GPT-5.5 security pass (`reports/2026-06-23_codex-gpt5.5-skill-review.md` §05). Affects SHIPPED 5.1.0 code — 5.1.1 candidate. Threat model: `/mb` run on a cloned/untrusted repo, or a project path/bank path containing a `'`.

- `hooks/_skill_root.sh:110` [BLOCKER] `bash -c` built by interpolating `cwd`/`MB_PROJECT_ROOT`/`agent` without quoting → project path with `'` = command injection on hook fire. (corroborated by §01) Fix: source `_lib.sh` in-process, call with quoted positional args — no shell-string.
- `scripts/mb-plan-done.sh:379` [BLOCKER] `.` (source) of repo-controlled `.memory-bank/.mbenv` → arbitrary code. Fix: whitelist `KEY=value` parser, no `source`.
- `scripts/mb-work-resolve.sh:51,110` [MAJOR] active-plan link from `roadmap.md` may be `../../…`; realpath'd → read/exfil outside bank. Fix: accept only canonical paths under `$BANK/plans/*.md` | `$BANK/specs/*/tasks.md`.
- `scripts/mb-pipeline.sh:130,169` [MAJOR] `MB_PIPELINE` / `.mb-config pipeline=` skip `valid_pipeline_name` → `../../x` selects YAML outside `<bank>/pipelines` → bypass protected_paths/gates. Fix: validate name before path-join + realpath inside bank.
- `scripts/mb-work-protected-check.sh:138` [MAJOR] absolute paths bypass `ci/**`/`.github/workflows/**`; basename fallback only catches `.env`/`Dockerfile`. Fix: canonicalize candidate path, derive repo root, match repo-relative + basename.
- `hooks/mb-protected-paths-guard.sh:31`, `hooks/block-dangerous.sh:67` [MAJOR] guard only on `Write|Edit`; Bash `tee`/`sed -i`/redirect into `.env`/`ci/**`/`.pem` bypasses. Fix: Bash PreToolUse protected-path parser routing extracted write targets through `mb-work-protected-check.sh`.
- `hooks/mb-session-turn.sh:128`, `hooks/lib/session-common.sh:140` [MAJOR] `<private>…</private>` NOT stripped before `session/*.md` persist or LLM summary — documented privacy feature is broken. Fix: shared sanitizer strips `<private>` before persist + summary.
- `scripts/mb-context.sh:39` [MAJOR] `cat` follows symlinks → `status.md -> ~/.ssh/config` exfil into context. Fix: reject symlinks, realpath under bank, regular-files only.
- `scripts/mb-search.sh:107,127` [MAJOR] tag mode trusts `index.json` path, `head "$MB_PATH/$rel"` → `../../` traversal. Fix: canonicalize each indexed path under `$MB_PATH`.
- `scripts/mb-flow-sync.sh:130`, `scripts/mb-handoff.sh:111` [MAJOR] trap-string interpolates lock path → exec on `EXIT` for a path with `'`. Fix: cleanup function + globals, `trap _cleanup EXIT`.
- `hooks/file-change-log.sh:127` [MAJOR] prints full secret line to stderr → transcript/log leak. Fix: emit only `file:line`+var name, value `[REDACTED]`.

**Plan:** `plans/2026-06-23_fix_security-hardening.md`
**Outcome:** no shell-string interpolation of untrusted paths; no `source` of repo-controlled files; all bank/pipeline/index paths canonicalized under their root; `<private>` honored on persist; protected-path guard covers Bash writes.

### I-083 — Verification gates fail-closed + multi-stack test runner + CI surface [HIGH, DONE 2026-07-15, 2026-06-23] — Wave 1, commit 49f9ad5, план plans/done/2026-06-23_fix_verification-gates.md

**Context:** §04. Gates can silently pass un-run/crashed checks — undermines trust in `/mb done` and `/mb work`.

- `scripts/mb-done-gates.sh:227,261` [BLOCKER] runner crash / malformed JSON / `tests_pass=null` silently → WARN/pass via `|| true`. Fix: fail when runner exits non-zero, output is invalid JSON, or `tests_pass=null` without explicit `not_applicable=true`; bats per path.
- `scripts/mb-test-run.sh:10,84` [BLOCKER] only Python+Go; exits 0 for bats/node/rust → project with red shell tests passes `/mb done`. Fix: consistent stack detection via `_lib.sh` or require `test_command`; cover bats/node/rust/no-pytest/failing-cmd.
- `.github/workflows/test.yml:44` + `hooks/tests/*.bats` [MAJOR] tracked `hooks/tests/` not run in CI. Fix: add `bats hooks/tests/*.bats` (+ any pytest) to CI + README verification commands.
- `.github/workflows/test.yml:77` [MINOR] shellcheck skips `hooks/lib/*.sh`, adapters, install; ruff skips `scripts/*.py`, `hooks/lib/*.py`, `memory_bank_skill/`. Fix: expand static-analysis targets.

**Plan:** `plans/2026-06-23_fix_verification-gates.md`
**Outcome:** gates fail-closed on un-run/crashed/null; runner covers the project's real stacks incl. bats; CI runs the full test+lint surface.

### I-084 — Capability dispatcher: wire into execution + transports + default routing [HIGH, OPEN, 2026-06-23]

**Context:** §01/02/06/07/08/09 — dominant root cause (6/9 reviewers). `mb-agent-caps.sh` (pi/opencode/codex resolver) is NOT called by the execution path; transports are not executable end-to-end. Likely the next unfinished dynamic-flow Phase 2 task (relates to [[I-080]], `mb-fanout.sh`, Task 12 sub-invoke).

- `scripts/mb-work-plan.sh:319` [BLOCKER] caps not wired: reads `agent/model/thinking` from YAML directly; nothing calls `mb-agent-caps.sh resolve` → `dispatch.priority/prefer/model_map` inert. Fix: resolve each role via caps, emit `transport` into JSONL, route CLI transports through subinvoke.
- `scripts/mb-subinvoke-resolve.sh:114` [BLOCKER] only `codex`+`claude-code`; `pi`/`opencode` fail unless `--cmd`. Fix: add tested `pi` (`pi -p --no-session --model …`) + `opencode` templates; `adapters/opencode.sh` `subinvoke` action.
- `references/pipeline.default.yaml:10` + `mb-agent-caps.sh:210` [MAJOR] default roles have no `model` → `resolve` exits 1 (no tier fallback). Fix: default contract models OR empty-contract → `claude-agent` tier default.
- `references/pipeline.default.yaml:292,298,305` [MAJOR] default `prefer={}`/`model_map={}`/priority excludes codex → codex-family not routed by default. Fix: ship real defaults (`prefer: {"openai-codex/*": codex, "gpt-*": codex}`, matching `model_map`).
- `scripts/mb-agent-caps.sh:124` [MAJOR] `roles.<role>.agent` ignored; `agent: codex-cli` → resolves to `claude-agent/opus` (`.memory-bank/pipeline.yaml:29`). Fix: translate transport-like agents into `prefer`.
- `scripts/mb-agent-caps.sh:63` [MAJOR] `codex --list-models`/`codex models` are non-existent CLI commands; codex is trusted → should not probe. Fix: drop the bad probe; when enumeration is needed parse `codex debug models` JSON (`.models[].slug`). VERIFIED 2026-06-23 vs live codex 0.137.0 (`--bundled` is NOT a flag).
- `scripts/mb-agent-caps.sh:89` + `scripts/mb-reviewer-resolve.sh:47` [MAJOR] caps/reviewer resolvers bypass `mb-pipeline.sh path` → ignore `MB_PIPELINE`/named pipelines/host-binding. Fix: resolve pipeline only via `mb-pipeline.sh path`.
- `scripts/mb-agent-caps.sh:118,121` [MAJOR] YAML parse error swallowed as `{}` → misleading "no model" exit 1 instead of documented parse-fail exit 2. Fix: emit error, return 2; bats with invalid YAML.
- `scripts/mb-agent-caps.sh:59` [MAJOR] `opencode models` errors silenced → indistinguishable from missing model; strict gating falls through silently. Fix: distinguish empty-list vs command-failure; on `on_none_available: error` fail.
- `scripts/mb-agent-caps.sh:134` [MINOR] `dispatch.enumerable: []` impossible (empty → default). Fix: check key presence, not truthiness.
- `scripts/mb-agent-caps.sh:62` [MINOR] pi parser: malformed stdout (`NF>=2`) parsed as models; header skip only `NR==1`. Fix: parse only after `provider model` header, validate provider/model regex.

**Plan:** `plans/2026-06-23_feature_dispatcher-wiring-transports.md`
**Outcome:** `/mb work` resolves transport+model via caps; pi/opencode/codex executable end-to-end; shipped default pipeline usable + routes codex-family; single pipeline-resolution path. (Or: gate transports as experimental and de-advertise.)

### I-085 — Logic correctness & GNU/BSD portability [MED, DONE 2026-07-15, 2026-06-23] — Wave 1, commit 49f9ad5, план plans/done/2026-06-23_fix_logic-correctness-portability.md

**Context:** §01/02/04. Correctness bugs + latent Linux portability in product helpers (the deferred mtime issue).

- `scripts/mb-work-range.sh:151` + `mb-work-plan.sh:285` [BLOCKER] empty `--range N` (marker gaps) → treated as "all" → whole plan executes. Fix: range emitting no existing item → non-zero; default-to-all only when no range requested.
- `scripts/mb-flow-route.sh:428` [MAJOR] route-floor misses lowercase `*interface*`/`*contract*`/`*protocol*`/`*abc*`. Fix: normalize lowercase basename/path + tests.
- `scripts/mb-flow-route.sh:390` [MAJOR] changed-file detection ignores untracked. Fix: add `git ls-files --others --exclude-standard`.
- `scripts/mb-work-plan.sh:108` [MAJOR] regex frontmatter misses `tasks: 1-3 # comment` / quoted `linked_spec` → runs all spec tasks. Fix: comment-aware scalar / YAML frontmatter parse.
- `scripts/mb-conflicts.sh:342` [MAJOR] `base64 --decode` not BSD-portable + `|| true` masks → empty bodies to judge. Fix: decode via Python stdlib or `base64 -d || base64 -D`.
- `scripts/mb-handoff.sh:35`, `scripts/mb-flow-sync.sh:56`, `scripts/_lib.sh:66` [MAJOR] BSD-first `stat -f %m || stat -c %Y` broken on GNU when `stat -f` exits 0 non-numeric; helpers lack the regression test the hook has. Fix: centralize numeric mtime (GNU-first + validation); stat-shim tests for all call sites.
- `scripts/mb-fanout.sh:393` [MINOR] branch stderr discarded → aggregate only `exit N`. Fix: capture `err.<i>`, include truncated snippet.
- `scripts/mb-conflicts.sh:81` [MINOR] `--threshold nan/inf` accepted. Fix: require finite `0<=t<=1`, else exit 64.
- `scripts/mb-work-resolve.sh:124` [MINOR] bank-relative `specs/<topic>/tasks.md` targets fail. Fix: resolve `plans/*`/`specs/*` relative to `BANK` before sanitization.

**Plan:** `plans/2026-06-23_fix_logic-correctness-portability.md`
**Outcome:** range/route/frontmatter false-positives eliminated; conflict bodies decoded portably; one validated mtime helper across all call sites.

### I-086 — Config validation, executable defaults & doc-vs-code drift [MED, OPEN, 2026-06-23]

**Context:** §06/03. Config knobs documented but unenforced/ignored; public docs drift from `commands/*.md` + `settings/hooks.json`.

Config:
- `scripts/mb-pipeline-validate.sh:442` [MAJOR] validator skips runtime blocks (`review`/`judge`/`review_ensemble`/`done_gates`/`dispatch.*`); bad enum/type reach runtime. Fix: schema-check all top-level knobs.
- `.memory-bank/pipeline.yaml:34,41` [MAJOR] duplicate YAML key `judge`; `validate` returns 0 (PyYAML keeps last). Fix: duplicate-key-rejecting loader in validator + runtime. DECIDED 2026-06-23: canonical judge = `mb-judge` (delete line 34 `{ agent: main-agent }` + its stale comment; behavior-preserving).
- `references/pipeline.default.yaml:217` + `scripts/mb-work-budget.sh:41` [MAJOR] `budget.default_limit` documented but ignored when no `--budget` (`commands/work.md:298`). Fix: apply non-null `default_limit` when CLI budget absent.
- `memory_bank_skill/rules_profile.py:125` [MINOR] profile validation skips `scope` (docs: `user|project`). Fix: validate, reject unknown.
- `scripts/mb-rules-check.sh:39` [MINOR] `mb-profile.sh init --scope=project` profiles not auto-consumed (only `MB_PROFILE`/`--profile`). Fix: default to `<bank>/rules-profile.json` + user profile, CLI override wins.
- `scripts/mb-config.sh:9` [MINOR] `mb-config` only `lang`, while `mb-pipeline.sh:96` stores `pipeline=` in same `.mb-config` — split ownership. Fix: add `pipeline` get/set/validate or rename.

Docs:
- `README.md:39` vs `:259` [MAJOR] `25` vs `29` commands; table omits `/analyze-task`, `/flow`, `/goal`. Fix: regenerate count/table from `commands/*.md` + add generated consistency check.
- `/mb reindex` [MAJOR] documented (`README:312`, `SKILL:290`) but absent from `commands/mb.md` router (only `hooks/mb-reindex.sh`). Fix (DECIDED 2026-06-23): ADD `reindex [--full|--incremental]` route in `commands/mb.md` → `hooks/mb-reindex.sh`; keep README/SKILL; generated pytest enforces router↔docs consistency.
- `references/hooks.md` [MAJOR] says "five hooks" but `settings/hooks.json` has many lifecycle hooks. Fix: regenerate from `settings/hooks.json`; split tool vs lifecycle.
- [MINOR/NIT] stale counts: `commands/mb.md:52` graph flags (`--docs`/`--sessions`), `work.md:12` `--slim`/`--full`/"Phase 4", `mb.md:929` "18 subcommands", `done.md:42` "6-step"=8 steps, `SKILL.md:219` missing `tests_failed`, `work.md:472` `max-cycles` vs `--max-cycles`, `structure.md:269` god-nodes PageRank-vs-degree.

**Plan:** `plans/2026-06-23_fix_config-validation-docs.md`
**Outcome:** validator covers runtime config + rejects duplicate keys; documented defaults (budget/profile) actually apply; public docs generated from source-of-truth with a consistency test.

### I-081 — session-lifecycle review residuals (3 minor, APPROVED) [LOW, OPEN, 2026-06-22]

**Context:** независимое ревью session-lifecycle (catchup/summarize/prune/timeout) дало APPROVED — 0 blocker / 0 major / 3 minor. Логика error-rejection присутствует и покрыта end-to-end в `session-end-summary.bats`; пункты ниже — упрочнение, не баги.

- **Test-coverage:** `session-summarize.bats` заявляет «proven identical» после DRY-extraction, но не портировал 3 кейса из `session-end-summary.bats` — (1) error-shaped LLM output → `summarized:false`, no `## Summary`; (2) `_recent` keeps newest `MB_RECENT_KEEP`; (3) oversized transcript → distilled Live-log fallback.
- **Edge (theoretical):** `mb-settings-ensure-timeout.py` `LINE_RE` требует `command` последним ключом объекта; нет теста на trailing-comma случай (exit 1 с понятным сообщением — текущее поведение).
- **Hygiene (low-prob):** `mb-session-summarize.sh` `_recent.md` пишет через `$RECENT.tmp.$$` + `mv` без cleanup-trap на сбой `mv` (disk-full); `$$`-суффикс исключает коллизии.

### I-080 — Architect / Decomposition-as-Artifact stage перед параллельным исполнением [MED, PROPOSED, 2026-06-16]

**Context:** Сейчас раскладку фичи на параллельные потоки делает сам оркестратор (main-loop) — декомпозиция эфемерна (не аудируется/не реплеится), на сам план нет независимого гейта, и параллелизм небезопасен без декларации владения файлами. Предложение: промотировать декомпозицию в явный **execution-DAG** (deps + `owns_paths` + контракт) с одним ревью-гейтом до фан-аута; исполнители — по фиксированным role-контрактам (Contract-First); per-item verify + integration-reviewer (barrier) → `mb-judge`. Off by default, threshold-gated. Достраивает планировочную половину к runtime фан-аута (`mb-fanout.sh` / паттерн `fanout-synthesize`); `owns_paths` — верхняя половина гарантии к fence из dynamic-flow Task 12.

**Proposal (детально):** `reports/2026-06-16_parallel-architect-decomposition-proposal.md` — мотивация, дизайн (§4), связка с Task 12 (§6), open questions (§7), EARS-seeds (§8), ICE (§9), риски (§10).

**Spec:** TBD — кандидат в `specs/<topic>/` (Phase 3, после fanout/sub-invoke Task 12–14). Базировать на §8 (acceptance/EARS-seeds) и §7 (open questions).

**Outcome (целевой):** Декомпозиция = durable ревьюируемый артефакт; гейт на план до траты токенов исполнителей; безопасный параллелизм by construction (непересекающиеся `owns_paths`).

### I-061 — Cursor compatibility remediation (hook bundle paths + global storage) [HIGH, PLANNED, 2026-05-24]

**Context:** Audit `reports/2026-05-24_cursor-compatibility-audit.md`. Copied hooks in `.cursor/hooks/` break `scripts/` resolution; five hooks fail silently. Global storage not wired without `MB_AGENT=cursor`.

**Plan:** `plans/2026-05-24_fix_cursor-compatibility-remediation.md`  
**Spec:** `specs/cursor-extension/` (REQ-300..REQ-324)

**Outcome:** Ten CC-compat hooks functional from skill bundle; docs accurate; optional W12 `adapters/cursor/dispatch.md`.

### I-033 — `mb-checklist-prune.sh` — auto-archive completed sections to progress.md [HIGH, DONE, 2026-04-25]

**Outcome:** SHIPPED 2026-04-25. `scripts/mb-checklist-prune.sh` + 12 pytest tests + CI cap-test + wire-ins (`commands/done.md`, `mb-plan-done.sh`, `mb-compact.sh`). Repo checklist auto-pruned to 36 lines under hard cap of 120. Plan: `plans/done/2026-04-25_refactor_checklist-prune-i033.md`.

**Original sketch (kept for reference):**

**Problem:** `checklist.md` росла до 534 строк потому что `mb-plan-done.sh` только меняет `⬜` → `✅` в существующих секциях, но никогда не удаляет завершённые sprint-секции. Spec §3 (line 61, 67) явно говорит: "checklist.md ... ротируется ... после `/mb done` → `progress.md`". Spec §13 объявляет `mb-checklist-auto-update.sh` как non-hook script, вызываемый из `/mb done` — но он так и не был построен. В результате каждый закрытый Sprint оставался в checklist'е навсегда и дублировал то, что уже есть в `progress.md` + `roadmap.md "Recently completed"` + `plans/done/`.

**Sketch:**
1. `scripts/mb-checklist-prune.sh [--dry-run|--apply] [--mb <path>]`:
   - Сканирует `## ` секции в checklist.md.
   - Помечает к архивации: секцию, где все bullets имеют `✅` AND содержит ссылку на `plans/done/...`. Опционально дополнительный фильтр "old enough" (≥7d с момента закрытия плана — найти по mtime done-плана).
   - Compresses секцию в одну строку: `### <heading> ✅ — Plan: [path]`. Полный текст уже есть в plans/done и progress.md, дубль не нужен.
   - Hard cap: после prune файл ≤120 строк. Если всё ещё длинный — emit warning о ручном trim.
   - Pre-write backup: copy в `.checklist.md.bak.<timestamp>`.

2. Wire в `/mb done` flow (commands/done.md): после actualize + note + progress, run prune --apply automatically.

3. Wire в `/mb compact` (scripts/mb-compact.sh) как опциональный шаг при `--apply`.

4. Wire в `mb-plan-done.sh`: после flip checkmarks, проверить — если вся секция плана теперь зелёная, immediately collapse её в одну строку (instead of waiting for `/mb done`).

5. Test coverage: pytest для prune script (RED tests for >120 lines triggers warn, all-✅-section collapses, dry-run shows plan, --apply mutates).

6. Add explicit "Hard cap ≤120 lines" convention к header чеклиста (уже сделано вручную 2026-04-25, требуется инструментальное enforcement).

**Plan:** Фолды в Phase 4 Sprint 3 как pre-release polish, либо отдельным small refactor sprint после Phase 4 close.

### I-001 — Benchmarks (LongMemEval + custom 10 scenarios) [HIGH, DEFERRED, 2026-04-20]

**Problem:** нет baseline для recall/tokens/session/precision; public release заявляет преимущества без измерений.
**Sketch:** 3 configs — A (CLAUDE.md only), B (claude-mem stock, optional с API credits), C (наш skill). Вернуться после v3.0 с 1+ месяцем реального использования.
**Plan:** — (решение ADR-009)

### I-002 — sqlite-vec semantic search [HIGH, DEFERRED, 2026-04-20]

**Problem:** grep-based `mb-search.sh` не поднимает семантически близкие заметки.
**Sketch:** заменить на embedding-поиск через sqlite-vec + local MiniLM. Отложено до v3.1+ после того как реальные use-cases покажут недостаточность keyword+tags+codegraph.
**Plan:** — (решение ADR-007)

### I-003 — Bridge to native Claude Code memory [HIGH, NEW, 2026-04-19]

**Problem:** нет программной синхронизации ключевых записей между `.memory-bank/` и `~/.claude/projects/.../memory/` — только документация coexistence (Stage 5).
**Sketch:** двунаправленный mapper: MB `notes/` ↔ auto-memory entries.
**Plan:** —

### I-004 — Auto-commit hook после `/mb done` [HIGH, DONE, 2026-04-25]

**Outcome:** SHIPPED 2026-04-25. `scripts/mb-auto-commit.sh` — opt-in (`MB_AUTO_COMMIT=1` env or `--force` flag) auto-commit `.memory-bank/` после `/mb done`. Safety gates: refuses on dirty source outside bank, during rebase/merge/cherry-pick, on detached HEAD, no-op when bank clean. Subject из last `### ` heading в `progress.md` (truncated to 60 chars), fallback `chore(mb): session-end YYYY-MM-DD`. Never pushes. Wired into `commands/done.md` step 7. 10 pytest tests + registration test green. Plan: `plans/done/2026-04-25_feature_i004-auto-commit.md`.

**Original sketch (kept for reference):**
**Problem:** изменения в `.memory-bank/` теряются при переключении веток если не закоммичены руками.
**Sketch:** post-`/mb done` хук создаёт `chore(mb): <session-summary>` commit с дельтой `.memory-bank/`.
**Plan:** [plans/done/2026-04-25_feature_i004-auto-commit.md](plans/done/2026-04-25_feature_i004-auto-commit.md)

### I-005 — /mb graph — визуализация связей plan→checklist→STATUS→progress [HIGH, NEW, 2026-04-20]

**Problem:** для больших проектов сложно проследить откуда пришла задача и где она закрылась.
**Sketch:** SVG/DOT-граф с cross-references между core-файлами. Подпитывает contextual recall.
**Plan:** —

### I-006 — Tree-sitter adapter для non-Python языков [HIGH, DONE, 2026-04-20]

**Problem:** `mb-codegraph.py` был Python-only, не покрывал Go/JS/TS/Rust/Java в polyglot проектах.
**Outcome:** SHIPPED 2026-04-20. 6 языков через `HAS_TREE_SITTER` флаг (fallback на Python-only без зависимости). 14 bats/pytest тестов зелёные.
**Plan:** shipped as part of v2.2 / Stage 6.5.

### I-007 — i18n error-сообщений [LOW, NEW, 2026-04-19]

**Problem:** сейчас часть stderr сообщений на русском, часть на английском — несогласованность.
**Sketch:** единый source-of-truth строк + env `MB_LOCALE`. Отложено как LOW priority (v3.1+ backlog).
**Plan:** —

### I-008 — GUI/TUI для просмотра банка (`mb ui`) [LOW, NEW, 2026-04-19]

**Problem:** для adoption новым пользователям полезен overview без ручного `cat`.
**Sketch:** TUI через `gum` / fzf; возможно простой localhost dashboard. Пересмотреть если Gate v3.0 показывает что UI — bottleneck adoption.
**Plan:** —

### I-009 — Экспорт банка в Obsidian/Logseq vault [LOW, NEW, 2026-04-19]

**Problem:** пользователи Obsidian хотят читать MB в своём knowledge management.
**Sketch:** `mb export --format obsidian` — конвертирует frontmatter + backlinks.
**Plan:** —

### I-010 — Webhook integration: Slack-нотификация при изменении status.md [LOW, NEW, 2026-04-19]

**Problem:** команды не видят когда milestone/gate сдвинулись без проверки репо.
**Sketch:** опциональный post-commit hook, POST на webhook URL из env.
**Plan:** —

### I-011 — Auto-generate README.md проекта из .memory-bank/ data [LOW, NEW, 2026-04-19]

**Problem:** README проекта часто устаревает относительно plan/STATUS.
**Sketch:** `mb readme-gen` — пересобирает README.md из STATUS + tech stack из codebase.
**Plan:** —

### I-012 — Split skill на 3 плагина (core, dev-commands, hooks) [MED, DECLINED, 2026-04-19]

**Problem:** (рассмотрено) слишком много фрагментации UX для v2. Может быть в v3 если скилл вырастет.
**Decision:** DECLINED — единый skill проще для install/update.

### I-013 — Миграция bash → Python для всех скриптов [LOW, DECLINED, 2026-04-19]

**Problem:** (рассмотрено) shell-скрипты якобы плохо тестируются.
**Decision:** DECLINED — shell приемлем для lightweight ops; Python overhead не оправдан для `cat status.md`.

### I-014 — Drop YAML frontmatter, использовать JSON-only [LOW, DECLINED, 2026-04-19]

**Problem:** (рассмотрено) frontmatter якобы усложняет парсинг.
**Decision:** DECLINED — frontmatter industry standard для note-taking (Obsidian, Logseq); сохраняем совместимость.

### I-015 — Hash-based IDs для заметок/планов [LOW, DECLINED, 2026-04-20]

**Problem:** (предложено в ревью 2026-04-20) решает multi-device конфликты.
**Decision:** DECLINED — YAGNI. Single-user workflow; multi-device — теоретическая проблема. Sequential IDs (H-NNN, EXP-NNN, I-NNN) работают.

### I-016 — KB compilation (concepts/, connections/, qa/ иерархия) [MED, DECLINED, 2026-04-20]

**Problem:** (предложено в ревью) преждевременная структура a-la Karpathy.
**Decision:** DECLINED — у нас ≤50 notes, Karpathy-pattern имеет смысл при 300+.

### I-017 — GWT (Given/When/Then) в DoD [LOW, DECLINED, 2026-04-20]

**Problem:** (предложено из GSD) добавить BDD-секцию в DoD шаблона планов.
**Decision:** DECLINED — дублирует test requirements; BDD tests достаточны без редундантной markdown-секции.

### I-018 — Schema drift detection [MED, DECLINED, 2026-04-20]

**Problem:** (предложено из GSD) проверять DB schema migrations на drift.
**Decision:** DECLINED — domain-specific для fintech; не fits generic skill, оставляем pre-commit hooks пользователей.

### I-019 — /mb debug (4-phase systematic debugging) [LOW, DECLINED, 2026-04-20]

**Problem:** (предложено из Superpowers) встроить отладочный workflow.
**Decision:** DECLINED — дублирует `superpowers:debugging` skill. Tool composition > duplication.

### I-020 — REST API / daemon mode [HIGH, DECLINED, 2026-04-20]

**Problem:** (предложено из mcp-memory-service) серверный режим для shared memory.
**Decision:** DECLINED — ломает архитектурное преимущество (93% Shell, simplicity, offline). Ниша занята mcp-memory-service (1500+ тестов), не конкурируем.

### I-021 — Viewer UI / localhost dashboard [MED, DECLINED, 2026-04-20]

**Problem:** (предложено для adoption) веб-интерфейс для просмотра банка.
**Decision:** DECLINED — chrome over substance. Пересмотреть если Gate v3.0 покажет что UI — bottleneck adoption. Пересекается с I-008 (LOW/NEW), как LOW-severity альтернатива оставляем.

### I-022 — OpenAI/Cohere embeddings через API [LOW, DECLINED, 2026-04-20]

**Problem:** (рассмотрено как альтернатива I-002) SaaS embeddings вместо local MiniLM.
**Decision:** DECLINED — теряем детерминированность и оффлайн-работу. Local MiniLM (если когда-нибудь добавим sqlite-vec) достаточен.

### I-023 — Унифицировать v1-detection grep → find (commands/start.md, agents/mb-doctor.md) [MED, NEW, 2026-04-22]

**Problem:** (ревью Phase 1 Sprint 1) detection в `commands/start.md` и `agents/mb-doctor.md` использует `ls | grep -E '^(STATUS|BACKLOG|RESEARCH|plan)\.md$'` — на macOS APFS это чувствительно к кэшированию FS. Migrator уже использует корректный `find -maxdepth 1 -type f -name`. Три entry-точки должны давать одинаковый ответ.
**Sketch:** заменить `ls | grep` на `find .memory-bank -maxdepth 1 -type f -name STATUS.md` и аналоги в обоих файлах.
**Plan:** Sprint 2 (часть plan-verifier расширения).

### I-024 — Добавить `--` end-of-options handling в mb-migrate-v2.sh [LOW, NEW, 2026-04-22]

**Problem:** (ревью Phase 1 Sprint 1) `bash mb-migrate-v2.sh -- somepath` упадёт с `[error] unknown flag: --`, хотя GNU convention — `--` означает конец опций.
**Sketch:** в `case "$arg" in` добавить `--) shift ;;` до `--*)`. Одна строка.
**Plan:** Sprint 2 (low priority — one-shot скрипт, manual users unlikely to pass `--`).

### I-025 — Переименовать переменные `PLAN_MD` → `ROADMAP_MD` в mb-plan-sync.sh / mb-plan-done.sh [LOW, NEW, 2026-04-22]

**Problem:** (ревью Phase 1 Sprint 1) переменные `PLAN_MD="$MB_PATH/roadmap.md"` — имя устарело после переименования. Работает, но misleading при чтении.
**Sketch:** `sed -i '' 's/PLAN_MD/ROADMAP_MD/g'` в двух скриптах + визуальная проверка что нет коллизий с комментариями.
**Plan:** Sprint 2 (cleanup, вместе с обучением обоих скриптов парсить Phase/Sprint/Task структуру).

### I-026 — Научить mb-plan-done.sh / mb-plan-sync.sh парсить Phase/Sprint/Task структуру [MED, NEW, 2026-04-22]

**Problem:** (Sprint 1 carry-over) скрипты распознают только `### Stage N:` — новый формат `## Phase N / ### Sprint M / #### Task K` не парсится. В Sprint 1 пришлось вручную move'ить план в `plans/done/`.
**Sketch:** расширить regex в обоих скриптах: `^#{2,4} (Phase|Sprint|Stage|Task) [0-9]+`. Добавить тесты на новый формат.
**Plan:** Sprint 2 baseline item (перед новыми планами которые будут использовать новый формат).

### I-027 — Test-guard против bash 4+ конструкций в mb-migrate-v2.sh [LOW, NEW, 2026-04-22]

**Problem:** (ревью Phase 1 Sprint 1 recommendation) macOS bash намертво 3.2. Будущие edit'ы могут reintroduce `declare -A`, `${var,,}`, `${var^^}` и сломать миграцию на Mac.
**Sketch:** pytest который grep'ом ищет запрещённые конструкции и fail'ит если найдены.
**Plan:** Sprint 2 (часть расширения test-suite для migrator).

### I-028 — multi-active plan collision in checklist.md (Sprint 2 reviewer C1) [HIGH, DONE, 2026-04-22]

**Problem:** mb-plan-sync.sh keys checklist sections by `## Stage N: <name>` heading. Two active plans sharing a section name (e.g. both have `## Task 1: Setup`) collapse onto one checklist entry. When one plan is closed via mb-plan-done.sh, its removal takes the other plan's entry with it — silent data loss.
**Repro:** create two plans with `## Task 1: Setup`. `mb-plan-sync.sh p1.md && mb-plan-sync.sh p2.md && mb-plan-done.sh p1.md` → checklist now empty, p2 orphaned.
**Sketch:** emit `<!-- mb-plan:<basename> -->` marker above each `## Stage N:` section; key remove-logic by marker (plan-scoped), not section heading. Backward-compat: sections without markers are treated as owned by the currently-being-closed plan (conservative legacy behavior).
**Plan:** [plans/done/2026-04-25_refactor_sprint3-multi-active-fix.md](plans/done/2026-04-25_refactor_sprint3-multi-active-fix.md)
**Outcome:** SHIPPED 2026-04-25. Marker `<!-- mb-plan:<basename> -->` emitted above each checklist section by mb-plan-sync.sh; mb-plan-done.sh keys removal by marker (plan-scoped). Backward-compat path for legacy unmarked sections preserved (conservative removal — only when no marker conflict). pytest 289 → 293 (4 new collision tests + bats fixture refresh from Sprint-1 v2 rename catch-up). bats 479 → 515 passed (legacy-marker-aware contract update for `test_plan_sync.bats` line ~105).

### I-029 — mb-traceability-gen: extension list is hard-coded, no `.rb/.kt/.swift/.java/.c/.cpp/.h` [LOW, NEW, 2026-04-22]

**Problem:** (Batch C reviewer M1) `tf.suffix not in {".py", ".ts", ".tsx", ".js", ".go", ".rs", ".sh"}` — hard-coded list excludes common languages. Plan spec said "substrings in file content" without enumerating.
**Sketch:** move extensions to `_lib.sh` env variable `MB_TRACEABILITY_EXTENSIONS` with sensible default; document override.
**Plan:** Sprint 3 or later.

### I-030 — mb-roadmap-sync: `.md` file scan omitted from REQ detection [LOW, NEW, 2026-04-22]

**Problem:** (Batch C reviewer M1) Prose mentions of REQ-NNN in `.md` design documents are not counted as coverage. This is probably correct (too noisy), but not documented.
**Sketch:** add a comment in mb-traceability-gen.sh header explaining the intentional `.md` exclusion.
**Plan:** Sprint 3 polish.

### I-031 — mb-traceability-gen: traceability.md full-overwrite isn't documented [LOW, NEW, 2026-04-22]

**Problem:** (Batch C reviewer I4) Manual edits to `traceability.md` are silently clobbered. Current header says "Do not edit manually" but the write semantics ("FULL OVERWRITE — any manual edits are lost") should be in the script header comment too.
**Sketch:** one-line doc addition in `scripts/mb-traceability-gen.sh`.
**Plan:** Sprint 3 polish.

### I-032 — Phase/Sprint/Task parser: Phase and Sprint as container-only? [LOW, NEW, 2026-04-22]

**Problem:** (final reviewer recommendation) `^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:` accepts all four equally. In plans like Sprint 2's own (which has `## Phase 1 > Sprint 2 > Task N` nesting), both `Phase 1` and `Task N` become checklist entries. Probably tracking-correct, but semantically `Phase`/`Sprint` are containers, not executable units.
**Sketch:** decide — allow all four (current), or restrict to `Task|Stage` only with `Phase|Sprint` being document structure. If the latter: narrow regex to `^#{2,4} (Task|Stage) [0-9]+:`.
**Plan:** Sprint 3 design discussion.


### I-034 — Plugin-namespaced skill detection for mb-reviewer-resolve.sh + install.sh probe [MED, NEW, 2026-04-25]

**Problem:** Phase 4 Sprint 3 ship-нул `mb-reviewer-resolve.sh` который ищет `superpowers` skill только по path `~/.claude/skills/superpowers/`. В реальности у пользователей skill часто живёт в **plugin namespace** (например `superpowers:requesting-code-review`, `commit-commands:commit`, `gsd:*`, `kaizen:*`) — это plugin-bundled skills, и они НЕ создают `~/.claude/skills/<name>/` директорию. Probe в `install.sh` step 6.5 говорит "superpowers skill not detected", и `mb-reviewer-resolve.sh` всегда возвращает `mb-reviewer` даже когда plugin-version skill реально доступен. Validated на этой машине 2026-04-25 — `superpowers:requesting-code-review` есть в Skill list, но resolver его не видит.

**Sketch:**
1. **Inventory mechanism для plugin-namespaced skills.** Claude Code skills могут попасть в session тремя способами:
   - file-system skill: `~/.claude/skills/<name>/` (наш текущий probe).
   - plugin-bundled skill: `<plugin-root>/skills/<plugin>:<skill-name>/` (e.g. `~/.claude/plugins/superpowers/skills/requesting-code-review/`).
   - marketplace/installed plugin: location depends on plugin manager.
   
   Reliable detection: scan `~/.claude/plugins/*/skills/<name>/` AND `~/.claude/skills/<name>/`. If either matches, skill is "present".

2. **Update `scripts/mb-reviewer-resolve.sh`:**
   - Replace `if os.path.isdir(skill_dir)` block with helper `def skill_present(skill_name, roots)`.
   - `roots`: env-injected `MB_SKILLS_ROOT` + `MB_PLUGINS_ROOT` (default `~/.claude/skills` and `~/.claude/plugins`).
   - For plugin namespace `<plugin>:<inner>` syntax in pipeline.yaml (already supported in `agent` field), check `<plugins-root>/<plugin>/skills/<inner>/` first.
   - Fallback to legacy `<skills-root>/<skill>/` for back-compat.

3. **Update `install.sh` step 6.5:** mirror the same probe logic. Print which path matched: `superpowers detected via plugin (~/.claude/plugins/superpowers/skills/requesting-code-review/)` vs `via skill dir (~/.claude/skills/superpowers/)`.

4. **Tests:**
   - `test_mb_reviewer_resolve.py` — new cases: plugin-style skill present in `MB_PLUGINS_ROOT`, both present, neither.
   - Mirror in registration test.

5. **Risk:** plugin paths are not stable Claude Code public API yet. Document the assumption in `mb-reviewer-resolve.sh` header. If layout changes, the resolver still fails-safe (returns `mb-reviewer`).

**Effort estimate:** 1 short sprint (1-2 hours): resolver patch + 3-4 new tests + install.sh probe update + docs comment.

**Plan:** —


### I-035 — Refresh bats fixtures referencing legacy plan.md after roadmap.md migration [MED, NEW, 2026-04-27]

### I-036 — Worktree per item (sub-isolation within plan) [MED, NEW, 2026-05-23]

**Problem:** parallel-pipeline (S5) использует worktree per plan, но items внутри одного плана работают в shared tree. Если два item'а в плане touch overlapping files (например оба правят `commands/work.md`) — implicit race condition.

**Sketch:** опция `--isolate-items` для `/mb run`, или per-stage frontmatter marker `<!-- mb-stage:N isolate -->`. Создаёт sub-worktree per item внутри плана. Lead cherry-pick'ит результаты последовательно при merge phase. Cost: больше worktree management, дольше старт.

**Trigger:** ждать пока появится реальный кейс с конфликтами; tracking — `pivot-log.jsonl` или новый `parallel-collision.jsonl`.

### I-037 — DAG cycles вне `loop_target` (general cycles support) [LOW, NEW, 2026-05-23]

**Problem:** parallel-pipeline (S5) разрешает только явные loops (phase → phase по условию failure). Не разрешает циклы вида A → B → C → A через произвольные триггеры.

**Sketch:** расширить валидатор pipeline.yaml: разрешить named cycle groups с явным max_iterations. Сейчас планировщик это блокирует.

**Trigger:** появится реальный сценарий, где нужен treble loop (например QA → security → arch-review → QA).

### I-038 — Динамическое создание ролей на ходу [LOW, NEW, 2026-05-23]

**Problem:** parallel-pipeline (S5) фиксирует все роли в pipeline.yaml до запуска. Невозможно создать ad-hoc роль по факту обнаруженной проблемы.

**Sketch:** runtime API `spawn_role(name, prompt, model)` доступен из bash executor'а; роль existует только до конца текущего run'а. Use case: «mb-reviewer обнаружил security issue → spawn временную роль mb-security-auditor с узким контекстом».

**Trigger:** появится паттерн где нужно эфемерное расширение ролей.

### I-039 — Real-time UI / progress bars для `/mb run` [LOW, NEW, 2026-05-23]

**Problem:** parallel-pipeline (S5) выводит только текстовый stderr log. На длинных run'ах (несколько часов, multi-plan) сложно отследить прогресс.

**Sketch:** опциональный TUI dashboard (через `tput` или внешний `--watch` процесс) показывающий: текущая wave, items in-flight, items waiting, budget consumed. Не блокирует исполнение, чисто observability.

**Trigger:** real-world feedback что текстовый log недостаточен.

### I-040 — Auto-merge conflict resolution через mb-architect [MED, NEW, 2026-05-23]

**Problem:** parallel-pipeline (S5) при cherry-pick conflict между worktree → main делает fail-fast (halt, surface to user). На multi-plan run'ах с большой степенью overlap это блокирует прогресс.

**Sketch:** при cherry-pick conflict — автоматически dispatch'ить Task → mb-architect с conflict diff + контекст обоих планов, запрашивать resolution; если architect возвращает clean resolution — apply, otherwise — escalate to user.

**Trigger:** появится паттерн где cross-plan conflicts частые (например когда несколько sub-projects одной phase'ы трогают один config).

### I-041 — Engine sharing с claude-skill-build (extract to shared package) [LOW, NEW, 2026-05-23]

**Problem:** parallel-pipeline (S5) и claude-skill-build реализуют схожий wave-pipeline engine независимо. Schema общая (по нашей договорённости), engine — нет. Дублирование maintenance.

**Sketch:** вынести `mb_pipeline_plan.py` + `mb-pipeline-run.sh` в отдельный PyPI пакет или git-submodule `pipeline-engine`. Оба скила импортируют. Требует stable contract API между пакетом и скилами.

**Trigger:** если оба скила будут активно эволюционировать engine — раньше; если один из них уйдёт в backlog — отпадает.

### I-042 — Full Python re-write pipeline engine (Approach B) [LOW, NEW, 2026-05-23]

**Problem:** parallel-pipeline (S5) реализован как hybrid (Python planner + bash executor). Marshalling через JSON-файлы — overhead и точка ошибок.

**Sketch:** перенести executor в Python (asyncio для параллельного Task dispatch). Bash остаётся только как тонкие action-primitives (`mb-work-budget.sh`, `mb-work-protected-check.sh`).

**Trigger:** если bash executor превысит 500 LOC и/или будут systematic bugs в JSON marshalling layer.

### I-062 — Ужесточить EARS-валидатор и spec-checking [MED, NEW, 2026-05-29]

**Problem:** `scripts/mb-ears-validate.sh` проверяет лишь наличие слова-триггера (`The|When|While|Where|If`) И слова `shall` как отдельных токенов в `- **REQ-NNN** ...`. Строка `The when shall while` проходит. Структура EARS-паттерна не валидируется; нет проверок атомарности, уникальности REQ-ID, раннего REQ→task покрытия; traceability на regex молча промахивается при дрейфе формата. Замечено на реальном проходе `/mb discuss` во внешнем проекте-потребителе.

**Sketch:**
1. Per-pattern structural regex (ровно один из 5 шаблонов с порядком слов): Ubiquitous `^The .+ shall`, Event `^When .+, the .+ shall`, State `^While .+, the .+ shall`, Optional `^Where .+, the .+ shall`, Unwanted `^If .+, then the .+ shall`.
2. Atomicity warning при >1 `shall` в одной REQ-строке.
3. REQ-ID uniqueness/monotonic lint (дубли + пропуски).
4. Ранний REQ→task coverage lint (каждый REQ упомянут в `tasks.md` `**Covers:** REQ-NNN`) — сейчас только в `/mb verify`.
5. `mb-traceability-gen.sh`: warning, если REQ-подобные строки не попали в матрицу (drift-resistance).

**Trigger:** при следующем касании SDD-тулинга (`discuss`/`sdd`/`verify`) — дешевле сделать вместе. Не блокер: текущий валидатор ловит главное.

**Детали:** [`notes/2026-05-29_ears-validator-hardening.md`](notes/2026-05-29_ears-validator-hardening.md).

### I-063 — Code graph `--semantic` LLM code↔docs layer [LOW, DONE, 2026-06-06]

**Outcome (2026-06-06):** Realized as the opt-in LLM wiki + surprising-connections layer + semantic search, with the contract carve-out the user explicitly approved (opt-in commands, graceful degradation, LLM via host subagents — no API key; default path byte-identical). `semantic` edges + `/mb wiki` + `mb-semantic-search.py` (BM25 default, optional embeddings). Plan: [`plans/done/2026-06-06_feature_graph-wiki-semantic.md`](plans/done/2026-06-06_feature_graph-wiki-semantic.md).


**Problem:** The code graph is purely structural (AST + tree-sitter + git co-change). It cannot link a concept described in a doc/spec to the code that implements it, nor surface "these two functions solve the same problem" without a shared call/import. graphify gets this from an LLM extraction pass.

**Sketch:** opt-in `--semantic` flag that runs an LLM pass over docs/specs + selected source to emit `semantically_similar_to` / `implements_concept` edges (INFERRED, with confidence). Reuse the `codegraph_*` module layout; new pure `codegraph_semantic.py` + an injectable LLM port so the core stays testable.

**Why deferred:** Breaks the three contract pillars that are the skill's differentiator — **$0** (LLM tokens), **deterministic** (non-reproducible edges), **zero required deps** (needs an API/provider). Warrants its own ADR (contract carve-out) + plan, not a drive-by. Default path must remain byte-identical and offline.

**Trigger:** explicit user demand for concept↔code linking that keyword + structural graph + co-change cannot satisfy. Decided alongside `feature_codegraph-cochange` (2026-06-06) where co-change + decomposition shipped and `--semantic` was scoped out.


### I-064 — rrf.py: test + docstring for duplicate-keys-in-one-ranking semantics (review tier1 task1 #1) [MED, NEW, 2026-06-12]

_Still OPEN — LOW/MED, not release-gated; deferred past 5.1.0._

### I-065 — rrf.py:47 docstring example — replace ellipsis with concrete tuples (review tier1 task1 #2) [LOW, NEW, 2026-06-12]

_Still OPEN — LOW/MED, not release-gated; deferred past 5.1.0._

### I-066 — BEFORE 5.1.0: bind_calls unique-fallback — build definitions from module-level symbols only (exclude methods/nested; Codex tier1-task3 r3 major) [HIGH, RESOLVED 2026-06-14 — 306835a]


### I-067 — BEFORE 5.1.0: unique-fallback dst for root __init__.py formats as '.foo' — guard empty module prefix (Codex tier1-task3 r3 minor) [MED, RESOLVED 2026-06-14 — 306835a]


### I-068 — Flaky test: session-end-judge.bats 'judge returns [] still marks judged=true' fails ~1/6 (pre-existing, reproduced on pristine hook; found during tier1 task 8) [MED, NEW, 2026-06-12]

_Still OPEN — pre-existing flaky test, not introduced by tier1; not release-gated._

### I-069 — BEFORE 5.1.0: strict v2 heading state machine in mb-session-end.sh — reject duplicate/out-of-order recognized headings inside the summary body (Codex r3 finding, task 8); add duplicate+out-of-order bats tests [HIGH, RESOLVED 2026-06-14 — 07221e9]

### I-071 — cursor-extension requirements.md: 13 REQ bullets fail EARS validation (pre-existing) [LOW, NEW, 2026-06-15]

_Pre-existing, not introduced by the cursor-finish work (`mb-spec-validate cursor-extension` already exit=1 on HEAD before the 2026-06-15 changes). REQ-308, 309, 310, 311–316, 318, 319, 320, 322 use "On `<event>`, when `<cond>`, the hook shall …" phrasing, which the EARS validator rejects because the bullet does not START with an EARS keyword (When/While/Where/If/The). Fix = mechanical rephrase "On X, when Y, the hook shall Z" → "When X and Y, the hook shall Z", preserving meaning, then re-run to exit 0. Deferred from cursor-finish (S, light gate): rewording normative requirements warrants its own review pass. Orphan-coverage (REQ-310→Task 2, REQ-312–317) and Task 9 missing-Testing were fixed in the 2026-06-15 pass; EARS phrasing is the only remaining validator failure._

### I-072 — sc_lock stale-break is not single-writer-safe repo-wide (mkdir lock TOCTOU) [MEDIUM, NEW, 2026-06-15]

_The shared lock primitive `hooks/lib/session-common.sh::sc_lock` (and its mirror in `scripts/mb-handoff.sh`) breaks a stale lock with `mkdir` + `rm -rf` on TTL expiry — a TOCTOU window where a slow original writer can delete a newer owner's lock. `mb-handoff.sh` now writes an owner token (`<pid>-<rand>`) at acquire and only `rm -rf`s on release when the on-disk token still matches (handoff-v2 Stage 1, MAJOR #6). The acquire-loop stale-break itself was left at `sc_lock` parity (out of scope for Stage 1). Follow-up: apply the same owner-token stale-break consistently in `session-common.sh::sc_lock` AND make handoff's TTL-break path verify the token before deleting, so the fix lands repo-wide in one pass._

### I-073 — session-start hook checklist grep misses ⬜ emoji items [LOW, NEW, 2026-06-15]

_`hooks/mb-session-start-context.sh:48` greps `^- \[ \]` for unfinished checklist items, but the live checklist format uses `⬜` (the same emoji dialect the handoff capsule's `unchecked_items` now handles). On real banks the "checklist (unfinished)" injection is therefore empty. Fix: match `⬜` (and `- [ ]` for back-compat), mirroring `handoff_capsule.unchecked_items`. Found independently by the Task 2 and Task 4 reviewers during handoff-v2; cosmetic (context-injection only), out of scope for the hook-rename task._

### I-074 — done-gate placeholder scan reads working-tree, not the staged blob [LOW, NEW, 2026-06-15]

_`mb_rules_check_lib.sh::scan_placeholders` greps the working-tree file, so a placeholder staged in the index but already removed from the working tree is not seen (Codex handoff-v2 Task 3 finding). Consistent with the rest of `mb-rules-check.sh`, which reads working-tree content everywhere — fixing only the placeholder scan would be inconsistent. Follow-up: decide whether the whole rules checker should scan staged blobs (`git show :path`) and apply uniformly._


### I-078 — Harden `_phase_makes_false_claim` against exotic verbs/phrasing [LOW, NEW, 2026-06-16]

_`tests/pytest/test_flow_route_templates.py::_phase_makes_false_claim` guards a ROUTE template from falsely claiming the firewall `--phase` flag is load-bearing (it is informational — `scripts/mb-flow-verify.sh`). The detector is now broad (14+ active verbs + passive voice + two-sided negation-awareness, pinned by 22 good/bad examples), but open-ended NL claim-detection can always be probed with an unregistered verb/construction. No actual route template contains such a claim today, so this is hardening for future template authors, not a shipped defect. Backlog raised by the `mb-judge` GO_WITH_BACKLOG verdict on dynamic-flow Task 11 (independent Codex review rounds R3–R5). Follow-up: add parametrized examples (e.g. `restricts which checks`, `governs the gate`) as new routes are introduced, or replace the verb-blocklist with a disclaimer-required inversion if drift recurs._

### I-079 — `mb-idea.sh` allocates next `I-NNN` from backlog.md only → collides with progress.md IDs [MED, NEW, 2026-06-16]

_`scripts/mb-idea.sh` computes the next idea id by scanning `backlog.md` alone. But the `I-NNN` sequence is GLOBAL across the bank — `progress.md` carries implementation entries `I-075/076/077` that the script never sees. On Task 11 it emitted `I-075` (backlog max was `I-074`) which collided with the existing `progress.md` I-075 "handoff-v2 delivered" entry; had to be hand-corrected to I-078. This violates the never-reused-ID invariant. Fix: `mb-idea.sh` (and any `I-`/`EXP-`/`ADR-` allocator) must take the max id across BOTH `backlog.md` AND `progress.md` (and ideally `index.json`) before incrementing — a single shared next-id helper in `_lib.sh`. Found while recording the Task 11 judge backlog._

### I-087 — Session-capture correctness + Memory-Bank drift hygiene [HIGH, RESOLVED 2026-07-04]

_Plan `plans/2026-07-04_fix_session-capture-and-mb-hygiene.md`. Track A (capture correctness,
A1-A7) + Track B (drift/enforcement, B1-B4) shipped, TDD red→green, governed review
(codex-cli gpt-5.5 CHANGES_REQUESTED → all findings fixed) + mb-judge (NO_GO on one broken
proxy test → fixed → clean). Commits `89caee6`/`37a4409`/`27e4d6a`/`cd6c387`/`e2bce6c`/`f2b2d56`/`4a8e29c`/`740cf5d`/`f4d8051`/`3ca4653`/`85c57ff`/`6207346`.
A1 splice-before-Summary + resummarize; A2 bullet/file caps; A3 user-cap 1000; A4 wrapper
filter (+opt-out); A5 _recent cap; A6 summary window 60k; A7 mb-session-repair.sh + prune
threshold; B1 mb-freshness.sh drift alarm; B2 auto-commit/freshness docs; B3 checklist
autoprune hook; B4 memsearch per-turn summarize disabled. Track C: taskloom + swarmline
sessions repaired + MB tails committed (MB-only, no push); content-archiving/stray-dir
removal deferred → I-092._

### I-088 — mb-session-repair.sh: add regression test for multi-`## ` section preservation (Auto-notes) [LOW, NEW, 2026-07-04]

_The plan edge case "`## Auto-notes emitted` preserved as its own section, only `- HH:MM ` bullets
moved" is implemented in the repair awk (verified by inspection) but has no dedicated bats case.
Raised by the mb-judge GO_WITH_BACKLOG on I-087._

### I-089 — Re-verify memsearch search after summarize.enabled=false (B4 smoke) [LOW, NEW, 2026-07-04]

_`~/.memsearch/config.toml` summarize disabled + verified via `memsearch config get` (=False);
the "search still returns results" DoD smoke wasn't independently re-run (memsearch CLI is via
uvx, not on PATH in the sandbox). Run a `memsearch` query once to confirm recall unaffected._

### I-090 — Pre-existing `test_mb_agent_caps.bats:147` env/pi-CLI-dependent failure [LOW, NEW, 2026-07-04]

_Full-suite sweep during I-087 judging found `test_mb_agent_caps.bats:147` (`resolve: real pi
2-column --list-models`) failing independent of the I-087 diff (last touched by `3c16381`/`45e01df`).
Environment/`pi`-CLI-dependent; track + fix separately._

### I-091 — mb-checklist-prune can't collapse flat `- ✅` checklists → cross-project checklists stay over-cap [MED, NEW, 2026-07-04]

_`mb-checklist-prune.sh` only collapses `### ` sections carrying a `plans/done/…` link with no
`⬜`/`[ ]`. taskloom (904 lines) and swarmline (680 lines) use flat `## Stage` + `- ✅` items,
so prune is a no-op and they never reach the 120-line cap. Found during I-087 Track C. Fix: add
a flat-format collapse mode (fold a fully-`✅` `## Stage` block to a one-line `plans/done` link)._

### I-092 — I-087 Track C residue: swarmline content-archiving + stray-dir cleanup (deferred) [MED, NEW, 2026-07-04]

_Deferred from I-087 Track C as too risky to auto-apply on the users' ACTIVE repos:
(a) swarmline `progress.md` March verify-boilerplate → `progress.archive.md`; extract RESOLVED
I-066/I-072 + ADR-004/006/007 from `BACKLOG.md` into dedicated files — large manual surgery on
live domain files. (b) taskloom/swarmline stray `~/.claude/projects/*--memory-bank*` dirs were
NOT removed: they hold nested session `tool-results/` (some dated today), contradicting the
plan's "empty, 0 jsonl" premise. Do deliberately, with review._

### I-093 — /mb work engine resilience: durable state, gated flip, external parse, codex preflight [HIGH, DONE, 2026-07-04]

_Closed same day. 9 stages, TDD (red commit before each feat, 18 commits c46d9ac..82624b2):
(T1) `mb-work-state.sh` durable `.work-state.json` + max_cycles enforcement by exit 3, budget bound
to run_id; (T2) `mb-work-checkbox.sh` deterministic DoD flip gated on `phase=done` + implementer ban;
(T3) `mb-work-review-parse.sh --external` normalizes cross-model "APPROVED with issues" + consumes
codex-reviewer SKIPPED contract, one bounded retry; (T4) `mb-work-codex-preflight.sh` fail-safe
health-check + loud `cross-model review SKIPPED` degradation + --auto confirmation hard-stop.
Verification: 49 pytest + 22 bats green, shellcheck clean, all scripts <=400 lines.
Plan: `plans/2026-07-04_fix_mb-work-resilience.md`. Zero file overlap with I-087 (verified)._


### I-095 — reviewer-2.0 backlog: DRY-fold resolve_touched_files/resolve_diff_text in mb-review.sh (~85% dup) [LOW, NEW, 2026-07-05]


### I-096 — reviewer-2.0 backlog: cover or remove inert last_verdict_cache_path() (Phase-2 hook, output discarded) [LOW, NEW, 2026-07-05]


### I-097 — reviewer-2.0 Task 2 backlog: wire pipeline.yaml:review_examples.max_count/rotation into mb-review.sh render_examples_section (loader currently uses built-in defaults --max 8/hash_run_id; keys not yet in pipeline.yaml) [LOW, NEW, 2026-07-05]


### I-098 — reviewer-2.0 backlog: split scripts/mb-review.sh (501 ln > 400 SRP threshold; pre-existing from Task 1, grows on Task 4/5 — extract plan-context/cache-resolution helpers) [MED, NEW, 2026-07-05]

### I-099 — work-loop-v2/reviewer-2.0: reconcile cache key — mb-review.sh last_verdict_cache_path() uses mb_sanitize_topic(item) but mb-work-trend.sh uses sha256(plan+stage+item); wire mb-review.sh to call `mb-work-trend.sh key` so the last-verdict cache doesn't diverge when progress_trend goes live (extends I-096) [MED, NEW, 2026-07-05]

### I-100 — work-loop-v2: mb-workflow.sh --loop returns {} (no on_max_cycles/max_cycles) for the composable `execution`+`--review`/`review.enabled` path — stage composition toggles `steps` but never synthesizes a `loop` from the top-level `review:` block, so a composable review loop has no max-cycle policy. Presets with an explicit `loop` (full/governed-execution/review-fix/review-only) are unaffected. [MED, NEW, 2026-07-05]

### I-101 — tooling: mb-traceability-gen.sh test-suffix whitelist excludes `.bats`, so bats-only-tested requirements (e.g. all drive-loop REQ-DR-*) show 🏗️ not ✅ in traceability.md despite passing tests. Add `.bats` to the suffix set. Project-wide visibility gap, not correctness. [LOW, NEW, 2026-07-05]

### I-102 — drive-loop: scripts/mb-drive.sh is 455 lines, over the 400 file-size budget. Overflow is load-bearing after fix-cycle 1 (6 fail-closed guards + timeout wrapper), not prose. Split candidate (Task-1b): hoist the timeout wrapper (`_mbd_init_timeout`/`_mbd_run`) and/or the `_mbd_json` introspection helper into a tiny sourced lib (e.g. `mb-drive-lib.sh`) to land ≤400 without churning the just-hardened decision core. Quality debt, not correctness. [LOW, NEW, 2026-07-06]

### I-103 — update-notify: scripts/_lib.sh is 814 lines, over the 400 file-size budget. Pre-existing (702 at HEAD before Stage 1 added the 113-line flavor block), and the file is sourced by 66 scripts, so a split is a cross-cutting refactor of its own. Suggested cut: hoist the install/upgrade helpers (`mb_install_flavor`/`mb_upgrade_command`/`mb_resolve_install_alias`) into `scripts/_lib_install.sh`, sourced from `_lib.sh`. Quality debt, not correctness. [MED, NEW, 2026-07-13]

### I-104 — update-notify: `mb_upgrade_command git` falls back to the cwd-relative `scripts/mb-upgrade.sh --force` when no install_dir is passed. Deliberate and tested, and every current caller passes `$SKILL_DIR` — but nothing *forces* a future caller to, so the footgun is contained, not removed. Fix: self-locate the bundle root from `${BASH_SOURCE[0]}` and default to it, making the relative form unreachable. [MED, NEW, 2026-07-13]

### I-105 — update-notify: the DRY guard in tests/bats/test_upgrade.bats ("no second copy of the flavor pattern-matching remains") keys on glob punctuation, so a quoted reintroduction like `*"site-packages"*)` slips through. Replace with the keyword form `grep -cE 'site-packages|dist-packages|Cellar|pipx/venvs' == 0`, which cannot be evaded. [LOW, NEW, 2026-07-13]

### I-106 — update-notify: `mb_install_flavor` forks `brew --prefix` (~100–200ms cold) on every path that reaches the unknown branch. Harmless today (Stage 2 caches the check with a TTL), but memoize the prefix in a global once the SessionStart hook lands, so a session start never pays it twice. [LOW, NEW, 2026-07-13]

### I-107 — agents: 20 of our 29 agents have no `SendMessage` in `tools:` — including the WHOLE review ensemble (`mb-reviewer-{logic,quality,security,scalability,tests,lead}`), `mb-rules-enforcer`, `mb-test-runner`, `mb-research`, `mb-doctor`, `mb-codebase-mapper`. Harmless today because `/mb work` dispatches them **synchronously** (a sync agent's final text comes back as the tool result). But a background/teammate dispatch can ONLY report through `SendMessage` — its plain output goes nowhere. So any of these, run in background, does the work and then goes silent. This is exactly where drive-loop (Phase 3) and work-loop-v2 parallel branches are heading, so it will bite there. Discovered when a `debugger` subagent (a GLOBAL agent, `~/.claude/agents/debugger.md`, tools = `Read, Bash, Grep, Glob` — no SendMessage, no Write/Edit either) was dispatched in background: it could neither fix nor report, and just idled. Fix: audit `tools:` across `agents/*.md`, add `SendMessage` to every agent that a background dispatcher may spawn, and add a test asserting it. [RESOLVED 2026-07-15, commit 72fcf2f] — 15 report-role agents (the review ensemble incl. `mb-reviewer-lead`, the 4 implementer specialists, `mb-rules-enforcer`, `mb-test-runner`, `mb-doctor`, `mb-research`, `mb-researcher`) got `SendMessage` + the canonical `## Report delivery (background runs)` block; `mb-engineering-core` got a rationalization-table row (the behavioural nudge — `mb-backend` had the section yet still went silent). `test_agent_report_delivery.bats` pins the invariant. Deliberately EXCLUDED: `mb-codebase-mapper`, `mb-wiki-{author,synthesizer}` — their deliverable is files on disk, not a message, so `SendMessage` would be an unused tool (YAGNI). [HIGH, NEW, 2026-07-13]

### I-108 — codegraph: `graph.json`'s meta record embeds `generated_at: datetime.now(UTC)` at second resolution, so ANY byte-identity test that builds twice races the clock — it flakes 1-in-10 locally and reds CI on the slower macOS runner. The byte-identity invariant (opt-in layers must not alter base output) is correct; a wall clock in the payload just makes it unverifiable. Fix in flight: honour `SOURCE_DATE_EPOCH` (the reproducible-builds convention) and have the byte-identity tests set it. [HIGH, RESOLVED 2026-07-15, 2026-07-13] — починено в 3eb9b96 (SOURCE_DATE_EPOCH, reproducible-builds convention)

### I-109 — agents: add our own `mb-debugger` (modelled on the global `~/.claude/agents/debugger.md`, but with the toolset it actually needs). The global one has `tools: Read, Bash, Grep, Glob` — no `Write`/`Edit`, so it cannot apply the fix it just root-caused, and no `SendMessage`, so a background dispatch of it does the work and then goes silent (see [[I-107]]). Dispatching it for a find-and-fix task is therefore structurally impossible, which is exactly what happened on 2026-07-13. Ours should keep the global's 4-phase root-cause discipline (reproduce → isolate → hypothesize → verify) and add `Write`, `Edit`, `SendMessage`. Do this as part of the same pass as I-107 — audit `tools:` for the whole roster, not one agent at a time, and add a test that every agent a background dispatcher may spawn has `SendMessage`. [PARTIAL 2026-07-15] — the roster-wide `tools:` audit + `SendMessage` + the parity test are done (see [[I-107]], commit 72fcf2f). Still OPEN: creating the actual `mb-debugger` agent (4-phase discipline + `Write`/`Edit`/`SendMessage`) so find-and-fix can be delegated. [HIGH, NEW, 2026-07-13]

### I-110 — update-notify Stage 4: the auto-update/watchdog bats tests assert on wall-clock deadlines with real `sleep` (hang→watchdog kill, "capture reaches EOF fast", 20s `MB_AUTO_UPDATE_TIMEOUT`). Green in an isolated run (43/43), but 2 flaked when 3 hook suites ran concurrently under load (measured this session). The hook LOGIC is correct — this is test determinism only. Fix: replace wall-clock deadline assertions with a fake/injectable clock or a much smaller injected timeout (`MB_AUTO_UPDATE_TIMEOUT`/`MB_UPDATE_NOTIFY_TIMEOUT` already env-overridable — drive them to sub-second in tests and assert on behavior, not elapsed seconds), so a busy CI runner cannot flake them. Related to the same watchdog pattern in Stage 3's tests (lines 468-594). [MED, NEW, 2026-07-15]

### I-111 — update-notify Stage 4 (codex round-3, non-blocking): the bats helper `make_clean_git_root` (tests/bats/test_mb_update_notify.bats ~112-119) asserts `.git` exists and `git status` exits 0, but does NOT prove the fixture's `git commit` actually succeeded — a repo where `git init` succeeds but `commit` fails would pass those checks yet be a dirty, uncommitted tree. In practice the 50/50 positive tests are green (so fixtures are genuinely clean today) and a failed-commit fixture would make a positive test FAIL loudly rather than falsely pass — hence non-blocking, test-hygiene only. Fix: also assert `git -C "$dir" rev-parse --verify HEAD` AND empty `git status --porcelain --untracked-files=all --ignore-submodules=none` before returning the path. Also (info) fix the stale comment in hooks/_skill_root.sh:9-20 / the Stage-4 note that says the shared resolver is "untouched" — cycle 1 DID add a SKILL.md-OR-VERSION gate to the MB_SKILL_ROOT override candidate (intentional; just document it accurately). [LOW, NEW, 2026-07-15]


### I-112 — Lift kill-0-gated _lock_acquire into scripts/_lib.sh and retire blind-rm-rf TOCTOU in mb-handoff.sh + mb-work-progress-append.sh [HIGH, NEW, 2026-07-15]


### I-113 — Optional fcntl/flock hardening for mb-agree.sh lock to close documented sub-ms crash-recovery race (recoverable single-write dup, never corruption) [LOW, NEW, 2026-07-15]


### I-118 — adapter-parity: forward --with-extensions CLI flag through memory_bank_skill/cli.py argparse to install.sh (env MB_WITH_EXTENSIONS already passes; only the flag form is missing) — closes REQ-005 for pipx/pip/brew [MED, NEW, 2026-07-15]


### I-119 — Pi session-memory: reuse session_start's resolved cwd const in session_shutdown reindex spawn instead of recomputing PROJECT_ROOT || ctx.cwd inline (pi_session_memory_extension.ts:288) — inert DRY nit from T3 judge [LOW, NEW, 2026-07-15]


### I-120 — openspec-adapter: apply anchor_safe hardening to design.md REMOVED/RENAMED headings (defense-in-depth) [LOW, NEW, 2026-07-15]


### I-121 — adapter-parity: /mb work has no deterministic per-role headless dispatch path for non-CC hosts today — commands/work.md 5a dispatches via Claude Code's Task tool only; mb-fanout.sh/mb-subinvoke-resolve.sh is a same-prompt parallel fan-out (dynamic-flow Task 9/12), not per-role routing, and mb-agent-caps.sh's transport/model resolver is never called from any dispatch site. Task 4 ships the guaranteed-floor registry primitive (--role scoping) + opt-in mb_dispatch_subagent tool on Pi; a real cross-host per-role dispatch harness for /mb work is future work [MED, NEW, 2026-07-15]


### I-122 — adapter-parity: no headless host dispatch path (mb-fanout.sh/mb-subinvoke-resolve.sh, any agent) prepends agents/mb-engineering-core.md or mb-tooling-core.md — that core+tooling+role composition only exists in commands/work.md's prose for the CC Task-tool path (5a). Pi's mb_dispatch_subagent tool is at parity with every other headless host on this (role-body only); if/when a deterministic non-CC role-dispatch harness lands, it must compose core+tooling+role like 5a does [LOW, NEW, 2026-07-15]


### I-123 — openspec-normalize: symmetry — convert.py mb_openspec_normalize import except-branch re-import (# pragma no cover, unreachable) + route cache write through _assert_within [LOW, NEW, 2026-07-15]


### I-124 — adapter-parity T8: align OpenCode adapter's install-global-agents action name with Pi's install-global-extensions (or document the intentional agents-vs-extensions distinction) before wiring uninstall/upgrade symmetry across adapters [LOW, NEW, 2026-07-15]


### I-125 — openspec-adapter: race-free openat-style NormalizeCache write guard (fully close TOCTOU beyond single-user CLI threat model) [LOW, NEW, 2026-07-15]


### I-126 — openspec-adapter: strengthen non-discriminating security tests (absolute-path-leak via absolute arg; R4 cache-OSError e2e) [LOW, NEW, 2026-07-15]

## ADR

### ADR-001 — Оставить skill structure под ~/.claude/skills/memory-bank/ [2026-04-19]

**Context:** native plugins пока недостаточно зрелые для multi-file distribution.
**Options:**
- A: plugin-based packaging — требует manifest rewrite и migration
- B: keep as-is — zero migration cost

**Decision:** B.
**Rationale:** скорость выпуска важнее canonical form; пересмотреть в v3.
**Consequences:** users продолжают клонировать skill repo; нет CI/CD через Anthropic plugin marketplace (пока).

### ADR-002 — Bats-core для shell, pytest для Python [2026-04-19]

**Context:** нужна unified testing story, но shell и Python имеют разные idioms.
**Options:**
- A: только bats, мокать Python через shell
- B: перевести merge-hooks.py → shell
- C: раздельные frameworks

**Decision:** C.
**Rationale:** native test idioms побеждают искусственную унификацию.
**Consequences:** CI запускает оба набора; developers знают оба framework'а.

### ADR-003 — index.json минимальная реализация (без vector) [2026-04-19]

**Context:** sqlite-vec добавляет runtime dependency и усложняет install.
**Options:**
- A: полный semantic search
- B: только frontmatter index (tags/type/importance)
- C: отказаться от index.json

**Decision:** B.
**Rationale:** покрывает 80% use-cases при 20% сложности.
**Consequences:** semantic queries невозможны без отдельного opt-in (ADR-007).

### ADR-004 — Профиль развития — гибрид C (personal → public через v3.0) [2026-04-20]

**Context:** skill опубликован на GitHub, но не рекламируется; пользователь хочет продолжать для себя, затем публично продвигать.
**Options:**
- A: только personal — minimal invest, теряем потенциал
- B: сразу public — преждевременные npm/benchmarks без отработки на себе
- C: гибрид — v2.1/v2.2 для себя, v3.0 для public

**Decision:** C.
**Rationale:** dogfooding даёт реальный signal до public commitment.
**Consequences:** двухфазный release cycle; Stage 9 готовит PyPI/Homebrew к public.

### ADR-005 — Auto-capture через SessionEnd + Haiku [2026-04-20]

**Context:** `progress.md` append-only; нужен cheap auto-summary без полного actualize.
**Options:**
- A: Sonnet — overhead на каждой сессии
- B: без LLM (bash append) — теряем summary
- C: Haiku с ограниченной областью (только progress.md)

**Decision:** C.
**Rationale:** Haiku 4× дешевле; full actualize остаётся в manual `/mb done` с Sonnet.
**Consequences:** две точки записи (auto + manual); доп. сложность в coordination.

### ADR-006 — Code graph через tree-sitter — opt-in через extras [2026-04-20]

**Context:** tree-sitter = C-extensions, install может быть heavy на Windows/legacy системах.
**Options:**
- A: всегда включено — ломает install в 10% случаев
- B: separate package — users пропустят
- C: opt-in через `pip install memory-bank[codegraph]`

**Decision:** C.
**Rationale:** default работает без codegraph; advanced users включают явно.
**Consequences:** документация должна чётко показать когда нужен extras.

### ADR-007 — Отказ от sqlite-vec в v2.1/v2.2 [2026-04-20]

**Context:** ревью настаивало на semantic search, но benefits не подтверждены реальным usage.
**Options:**
- A: включить в v2.2 — preemptive complexity
- B: v3.1+ backlog — ждём реальной потребности

**Decision:** B.
**Rationale:** (1) keyword+tags+codegraph покрывают 80%; (2) sqlite-vec+MiniLM ~100MB download; (3) benchmark покажет нужно ли.
**Consequences:** I-002 остаётся DEFERRED; пересмотр после реальных v3.0 use cases.

### ADR-008 — Distribution — pipx/PyPI primary, Homebrew secondary [2026-04-20]

**Context:** mix-stack skill (88% bash + 12% Python).
**Options:**
- A: npm — требует Node.js runtime при отсутствии JS-кода
- B: pipx/PyPI — Python уже in-stack, `pipx` изолирует env, `pipx upgrade` решает update story
- C: Homebrew tap — native macOS/linuxbrew, но ограниченная аудитория
- D: `curl | bash` — простейший, но security concerns

**Decision:** B primary + C secondary + Anthropic plugin tertiary.
**Rationale:** pipx канонично для CLI с mix deps; Homebrew — secondary для macOS-only пользователей.
**Consequences:** npm убран; scope `@fockus/memory-bank` зарезервирован. PyPI имя `memory-bank-skill` (не `skill-memory-bank`) — избегаем rename pain.

### ADR-009 — Benchmarks отложены в v3.1+ backlog [2026-04-20]

**Context:** ревью настаивало на benchmarks как обязательная фича v3.0 для public release.
**Options:**
- A: synthetic benchmark сразу — low-value
- B: отложить до реальной usage-baseline
- C: skip навсегда — теряем adoption

**Decision:** B.
**Rationale:** для valid baseline нужно 1+ месяц реального использования v3.0; без сравнения с claude-mem — single-point measurement.
**Consequences:** I-001 остаётся DEFERRED; differentiator сейчас — TDD/plan-verifier/cross-agent, не recall цифры.

### ADR-010 — Codex CLI 7-м adapter в Stage 8 [2026-04-20]

**Context:** OpenAI Codex CLI использует `AGENTS.md` как стандарт конфига (совпадает с OpenCode).
**Options:**
- A: не добавлять — пропустим аудиторию
- B: `AGENTS.md` shared с OpenCode — конфликт при одновременной установке
- C: `AGENTS.md` + optional `.codex/config.toml` — явный marker владения

**Decision:** C.
**Rationale:** manifest фиксирует ownership per-client; совместная установка с OpenCode возможна при shared `AGENTS.md`.
**Consequences:** 6→7 adapters; 14→16 e2e tests; uninstall одного не затирает файл пока второй active.

### ADR-011 — Repository migration claude-skill-memory-bank → skill-memory-bank [2026-04-20]

**Context:** после Stage 8 skill работает с 7 клиентами, имя `claude-skill-*` misleading.
**Options:**
- A: оставить старое имя + rebrand в README — запутано
- B: fresh public repo с clean-break history — теряем ADR/research transparency
- C: full history migration в новый `skill-memory-bank` + archive старого

**Decision:** C.
**Rationale:** canonical path; сохраняет authorship и link continuity.
**Consequences:** Stage 8.5 до Stage 9 (иначе PyPI/Homebrew нужен перевыпуск). PyPI имя остаётся `memory-bank-skill` (ADR-008 — не переименовываем). URL в project_urls.Repository → `fockus/skill-memory-bank`.
