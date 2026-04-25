---
status: done
type: feature
sprint: i-004
created: 2026-04-25
closed: 2026-04-25
covers_requirements: [I-004]
---

# I-004 — Auto-commit hook после `/mb done`

## Context

`MB` artefacts (`status.md`, `progress.md`, `checklist.md`, новые `notes/`) могут осиротеть в working tree после `/mb done`, если пользователь забыл сделать `git commit` и переключил ветку или сделал `git stash drop`. Real failure mode подтверждён в этой же сессии — после Phase 4 Sprint 3 ранние коммиты прошли только потому, что я делал их явно. Без auto-commit'а сессия закрылась бы с unstaged bank changes.

## Goal

Opt-in (`MB_AUTO_COMMIT=1`) хелпер, который в конце `/mb done` атомарно коммитит **только** `.memory-bank/` изменения с осмысленным `chore(mb): ...` subject из `progress.md` last entry. Никогда не сжирает source changes вне `.memory-bank/` (отказ + warning), никогда не пушит, no-op если `.memory-bank/` чистый.

## DoD (SMART)

- [x] **`scripts/mb-auto-commit.sh`** — bash dispatcher.
  - Triggers только при `MB_AUTO_COMMIT=1` или `--force` flag.
  - Pre-flight gates (отказ + предупреждение, exit 0 — non-fatal):
    1. `.memory-bank/` пустой / нет changes → no-op.
    2. dirty file outside `.memory-bank/` (in `git status --porcelain` без префикса `.memory-bank/`) → skip + warn.
    3. repo in rebase/merge/cherry-pick (`.git/{REBASE_HEAD,MERGE_HEAD,CHERRY_PICK_HEAD}`) → skip + warn.
    4. detached HEAD (`git symbolic-ref -q HEAD` fails) → skip + warn.
  - Commit subject: `chore(mb): <last ### heading from progress.md>` truncated to 60 chars. Fallback: `chore(mb): session-end YYYY-MM-DD`.
  - Body: ничего (subject + Co-Authored-By trailer достаточно).
  - Не пушит. Никогда. Push — explicit user action.
- [x] **Wire-in в `commands/done.md`** — новый Step 7 "auto-commit (opt-in)" после index regeneration. Зеркальный hint в reporting.
- [x] **`tests/pytest/test_mb_auto_commit.py`** — pytest покрытие:
  - `MB_AUTO_COMMIT` unset → exit 0, no commit (default off).
  - `MB_AUTO_COMMIT=1` + clean bank → exit 0, no commit.
  - `MB_AUTO_COMMIT=1` + dirty bank + dirty src → skip + warn, no commit.
  - `MB_AUTO_COMMIT=1` + dirty bank + clean src → commit created with correct subject.
  - subject derives from `progress.md` last `### <heading>`.
  - subject fallback when no `### ` in progress.md.
  - skip during rebase (`.git/REBASE_HEAD` present).
  - skip on detached HEAD.
  - `--force` overrides `MB_AUTO_COMMIT` unset.
  - `--help` flag exits 0.
- [x] **Registration test** `tests/pytest/test_i004_registration.py` — script exists+executable, `commands/done.md` references `mb-auto-commit.sh`, backlog I-004 flipped to DONE.
- [x] **Backlog `I-004` → DONE** with `**Outcome:**` line and `**Plan:**` link.
- [x] Full pytest suite green: 615 → 615+N. shellcheck `-x` clean.
- [x] Single commit `feat(i-004): mb-auto-commit.sh — opt-in /mb done auto-commit` + push.
- [x] Plan moved to `plans/done/`.

## Stages

### Stage 1: tests RED
Write `test_mb_auto_commit.py` (10 cases) + `test_i004_registration.py`. Confirm RED.

### Stage 2: implement script
`scripts/mb-auto-commit.sh` per spec above. Inline progress.md parsing in awk/python heredoc.

### Stage 3: wire commands/done.md + flip backlog
Add Step 7 + reporting line; flip I-004 NEW → DONE in backlog with outcome.

### Stage 4: regress + close-out + commit
pytest, shellcheck, plan → done/, status/roadmap/progress updates, single commit.
