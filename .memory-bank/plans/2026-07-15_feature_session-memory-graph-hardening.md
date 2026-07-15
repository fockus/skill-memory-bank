---
title: "Session-memory + code-graph hardening (fix-plan)"
type: feature
topic: session-memory-graph-hardening
status: Draft
created: 2026-07-15
complexity: M
depends_on: []
parallel_safe: false
linked_spec: none
owner: planner — plan; /mb work — execution
roles: "implement=sonnet · verify=mb-test-runner · review off by default"
source: ".memory-bank/reports/2026-07-15_review_session-memory-graph.md"
stages: 1-9
---

# Plan: Session-memory + code-graph hardening

Operationalizes the file:line-grounded findings in
`.memory-bank/reports/2026-07-15_review_session-memory-graph.md` (3 research agents,
re-verified in the main session). Two tracks: **A** — session-memory quality bugs +
doc drift; **B** — make the code graph actually adopted (rebuild + auto-refresh +
implementer permissions + reachable freshness).

## Relation to the donor roadmap (AGR-003)

This is a **standalone quality/bug fix-plan**, NOT a donor-program slice. It touches
no release-numbered donor scope, reorders no donor release, and needs **no ICE slot**.
It runs independently of the AGR-003 freeze (fixes to existing shipped subsystems:
session-memory capture/recall + the code-graph adoption path). No new agreement is
required or invented. Publication (tag/PyPI) is out of scope — these land on `main`
as normal fixes and ride the next release.

## Scope

### Входит
- Track A: chunker line/field alignment (HIGH), dangling-embedding fix (MEDIUM ×2 files),
  doc reconciliation of `references/session-memory.md` + `SKILL.md` (MEDIUM), optional
  transcript drill-down (LOW).
- Track B: graph rebuild (cheap, unblocks), `/mb work` auto-refresh, implementer rebuild
  permission, reachable freshness in role files + engineering-core pointer.

### НЕ входит
- 600-char cap `truncated: true` marker (report §1.3, MEDIUM) — deferred, not in the brief.
- memsearch-style LLM-per-turn summaries or Milvus (explicit non-goal — our $0 capture wins).
- Any change to donor-program specs/roadmap/release numbering.
- Publishing / tagging / PyPI.

## Assumptions
- CI runs Python 3.11/3.12; local is 3.13 — verify pytest under the repo venv before "green"
  (lesson: CI Python version gap).
- `hooks/mb-semantic.py prune` already exists (`prune_index`) → Stage 4 wires an existing
  subcommand, adds no new indexer code.
- The graph's `meta` stamp feature (I-087) postdates the last build (2026-05-27, 284 commits
  back) → `mb-graph-query.py status` = `stale (unknown)` until Stage 1 rebuilds it. Confirmed:
  `Code graph: stale (unknown)`.
- Live-log bullets have the stable shape `- HH:MM — User: … · tools: … · files: …`
  (verified in `.memory-bank/session/2026-06-07_2030_935cc833.md`).

## Риски
| Риск | Вероятность | Impact | Mitigation |
|------|-------------|--------|------------|
| Chunker fix regresses `test_session_redaction.py` (shares `chunk_markdown`) | M | H | Re-run redaction suite in every chunker-stage verify; redaction is applied in `_sanitize` before packing, order preserved |
| Rebuilt `graph.json` is a large tracked-artifact diff | M | M | Scoped `git add .memory-bank/codebase/graph.json`; commit separately; note byte-size in DoD |
| `MB_AUTO_CAPTURE=auto` default is intentional dual-writer | L | M | Stage 8 flags it as an **open decision for the user** — reconcile docs to code first, do not flip the default without confirmation |
| Auto-refresh in `/mb work` 5g slows the loop | L | M | Background + atomic lock, mirror `post-commit-codegraph.sh`; fail-open exit 0 |
| Two conflicting freshness protocols in dispatched prompt | M | M | Stage 7 makes role files self-contained via `mb-graph-query.py status`; remove `/mb context`-dependent wording |

---

## Stage 1: Rebuild this repo's code graph + verify fresh
<!-- mb-stage:1 -->
**Complexity:** S · **Время:** ~3 мин · **Зависимости:** — · **Агент:** mb-tooling-core / mb-developer
**Файлы (изменить):** `.memory-bank/codebase/graph.json` (regenerated), `.memory-bank/codebase/god-nodes.md` (if emitted)

Cheap and unblocks everything: a fresh, meta-stamped graph makes `status` self-report
`fresh` so routing (Stages 6-7) and auto-refresh (Stage 5) actually engage. The current
graph predates the stamp feature → permanently `stale (unknown)` until rebuilt.

### Задачи
1. Run `python3 scripts/mb-codegraph.py --apply --docs .memory-bank .`
2. Confirm the first `graph.json` row is now a `meta` row with `generated_at` + `commit`.
3. Scoped-stage the artifact for a dedicated commit.

### DoD
- [ ] `python3 scripts/mb-graph-query.py status --graph .memory-bank/codebase/graph.json` prints `fresh` (not `stale (unknown)`).
- [ ] First line of `graph.json` is `{"type":"meta",…}` with non-null `generated_at` and `commit == HEAD`.
- [ ] `python3 scripts/mb-graph-query.py neighbors --graph .memory-bank/codebase/graph.json --symbol chunk_markdown` returns ≥1 edge (graph indexed hooks/lib).
- [ ] Only `.memory-bank/codebase/*` staged (scoped `git add`, no `-A`).

### Тестовые сценарии
- Manual gate (no code test): `status` verdict flips `stale`→`fresh`. Regression guard is `tests/bats/test_mb_freshness.bats` (must stay green).

### Команды проверки
```bash
python3 scripts/mb-codegraph.py --apply --docs .memory-bank .
python3 scripts/mb-graph-query.py status --graph .memory-bank/codebase/graph.json
head -c 200 .memory-bank/codebase/graph.json
bats tests/bats/test_mb_freshness.bats
```

### Edge cases
- Graph build fails / python missing → do NOT commit a partial graph; report BLOCKED.
- Large diff: note byte-size; the artifact is already tracked, so this is an update not an add.

---

## Stage 2: Chunker — align on Live-log bullet boundaries (HIGH)
<!-- mb-stage:2 -->
**Complexity:** M · **Время:** ~5 мин · **Зависимости:** — · **Агент:** mb-developer (TDD)
**Файлы:** create `tests/pytest/test_semantic_chunk_livelog.py`; edit `hooks/lib/semantic_chunk.py`

Root cause (`semantic_chunk.py:26-65`): `_split_long` flattens real `\n` into spaces and
`_pack` overlap is a raw `buf[-OVERLAP_CHARS:]` char slice → an injected "Relevant Memory"
line begins mid-path (`rs/fockus/Apps/…`) / mid-field. Fix: split a Live-log body on bullet
boundaries (`\n- HH:MM`) into atomic units BEFORE generic packing, and never let overlap
cross a bullet boundary (drop char-slice overlap for bullet-structured text; overlap by
whole preceding bullet or none).

### Задачи (TDD — red FIRST)
1. **RED:** write `test_semantic_chunk_livelog.py` with a `files:`-heavy multi-bullet Live-log
   fixture (2+ bullets, one bullet's `files:` list > `CHUNK_CHARS`). Assert every produced
   chunk's first non-empty line starts at a bullet (`- HH:MM`) OR a clean field token
   (`tools:`/`files:`/a full absolute path segment beginning `/`), never a decapitated path
   like `rs/fockus`. Run → fails.
2. **GREEN:** add `_split_bullets(text)` that cuts on `^\n?- \d{2}:\d{2}` boundaries; route
   Live-log-shaped markdown through it before `_pack`; make `_pack`'s overlap bullet-aware
   (no cross-boundary char slice).
3. Keep `chunk_transcript` and non-bullet markdown behavior unchanged.

### DoD (SMART)
- [ ] New test: ≥3 assertions (first-line-clean, no mid-path start, bullet count preserved) — all green.
- [ ] A single oversized `files:` bullet splits WITHOUT starting a chunk mid-path (regression the report cites).
- [ ] `tests/pytest/test_session_redaction.py` still green (shared `chunk_markdown`).
- [ ] No new placeholder / TODO; `semantic_chunk.py` stays ≤400 lines.
- [ ] `ruff check hooks/lib/semantic_chunk.py` clean.

### Тестовые сценарии
- `test_chunk_livelog_files_heavy_first_line_is_clean_field` — files-dense bullet → first line is a field/path, not decapitated.
- `test_chunk_livelog_overlap_never_crosses_bullet` — no chunk starts inside a previous bullet's char tail.
- `test_chunk_markdown_plain_paragraph_unchanged` — non-bullet doc packing identical to before.

### Команды проверки
```bash
python3 -m pytest tests/pytest/test_semantic_chunk_livelog.py tests/pytest/test_session_redaction.py -q
ruff check hooks/lib/semantic_chunk.py
```

### Edge cases
- Bullet with no `files:` field; bullet exactly at `CHUNK_CHARS`; file with `## Live log`
  but zero bullets (empty session); CRLF; a `- HH:MM` string appearing inside quoted user text
  (anchor on line-start only, `re.MULTILINE`).

---

## Stage 3: Recall drops dangling hits when source file is gone (MEDIUM)
<!-- mb-stage:3 -->
**Complexity:** S · **Время:** ~4 мин · **Зависимости:** — · **Агент:** mb-developer (TDD)
**Файлы:** create `tests/pytest/test_recall_dangling.py`; edit `hooks/lib/recall_index.py`

`age: "?"` in live output = a hit whose `source` file no longer exists (pruned/moved) but
whose embedding still lives in the index (`indexer.py:73-75` never prunes incrementally).
Primary fix at recall layer (self-contained, directly satisfies "recall returns no dangling
hit"): in `_build_hits`, drop any hit whose `(mb / source)` does not exist. `_age` already
signals this via `?`.

### Задачи (TDD — red FIRST)
1. **RED:** `test_recall_dangling.py` builds a request with two semantic hits — one whose
   `source` exists on a tmp `mb`, one whose `source` file is absent. Assert the renderer's hit
   set contains only the existing source (no `age: "?"` row). Run → fails.
2. **GREEN:** in `_build_hits`, skip hits where `source` resolves under `mb` but the file is
   missing. Keep hits when `mb` itself is unresolvable (fail-open — don't drop everything).
3. Ensure `render_compact`/`inject` never emit an `age: "?"` line for a missing file.

### DoD (SMART)
- [ ] New test proves a pruned-source hit is absent from compact + inject output; existing hit remains.
- [ ] Fail-open: with a bogus `mb` path, no hits are dropped (separate assertion).
- [ ] Existing recall tests green (`tests/pytest/test_semantic_search_rrf.py`).
- [ ] `recall_index.py` ≤400 lines; `ruff check` clean.

### Тестовые сценарии
- `test_build_hits_missing_source_is_dropped` — absent file → not rendered.
- `test_build_hits_present_source_is_kept` — sibling existing hit survives.
- `test_build_hits_unresolvable_mb_keeps_all` — fail-open guard.

### Команды проверки
```bash
python3 -m pytest tests/pytest/test_recall_dangling.py tests/pytest/test_semantic_search_rrf.py -q
ruff check hooks/lib/recall_index.py
```

### Edge cases
- Lexical-only hit whose file was deleted after the grep; `source` with leading `./`;
  a note vs session vs transcript source kind; `mb` given as absolute vs relative.

---

## Stage 4: Prune `--apply` invalidates the index (MEDIUM)
<!-- mb-stage:4 -->
**Complexity:** S · **Время:** ~4 мин · **Зависимости:** — · **Агент:** mb-developer (TDD)
**Файлы:** create `tests/bats/test_session_prune_reindex.bats`; edit `scripts/mb-session-prune.sh`

Complements Stage 3 by keeping the on-disk index lean: after `--apply` moves/deletes stub
files, call the existing `mb-semantic.py prune` subcommand (→ `prune_index`, drops blocks
whose source disappeared). Best-effort, backgrounded, never blocks or fails the prune.

### Задачи (TDD — red FIRST)
1. **RED:** `test_session_prune_reindex.bats` — seed a session dir + a minimal index manifest
   containing a stub's source; run `mb-session-prune.sh --apply`; assert the prune invokes the
   semantic prune (assert on the `MB_GRAPH_AUTO_DRYRUN`-style dry-run echo OR that the manifest
   no longer lists the removed source). Run → fails.
2. **GREEN:** append, after the apply loop, a guarded best-effort call:
   `command -v python3 && MB_ROOT="$MB_PATH" python3 "$HOOK_DIR/mb-semantic.py" prune >/dev/null 2>&1 &`
   only when `APPLY=1` and at least one stub was moved/deleted. Resolve `HOOK_DIR` like the
   existing reindex callers (`hooks/mb-reindex.sh`).
3. Keep dry-run (`APPLY=0`) side-effect-free.

### DoD (SMART)
- [ ] `--apply` with ≥1 stub triggers exactly one semantic-prune invocation; dry-run triggers none.
- [ ] Prune script still exits 0 when python3 is absent (fail-open).
- [ ] `shellcheck scripts/mb-session-prune.sh` clean.
- [ ] Existing `tests/bats/test_session_prune.bats` green.

### Тестовые сценарии
- `test_prune_apply_invokes_semantic_prune` — apply path calls the prune subcommand.
- `test_prune_dryrun_no_index_side_effect` — dry-run leaves the index untouched.
- `test_prune_no_python_still_exit_zero` — missing python3 → exit 0.

### Команды проверки
```bash
bats tests/bats/test_session_prune_reindex.bats tests/bats/test_session_prune.bats
shellcheck scripts/mb-session-prune.sh
```

### Edge cases
- Zero stubs found (no invocation); `--hard` delete path; current-session file skipped;
  index dir absent (prune subcommand no-ops).

---

## Stage 5: Auto-refresh graph in `/mb work` step 5g
<!-- mb-stage:5 -->
**Complexity:** S · **Время:** ~4 мин · **Зависимости:** Stage 1 · **Агент:** mb-developer
**Файлы:** edit `commands/work.md` (step 5g, ~449); ref `hooks/git/post-commit-codegraph.sh`

Without a manually-installed git hook the graph drifts silently. Wire a background,
lock-guarded incremental refresh into 5g AFTER a governed item commits, mirroring
`post-commit-codegraph.sh` (fail-open exit 0, atomic `mkdir` lock, build against repo root).

### Задачи (TDD — red FIRST)
1. **RED:** extend `tests/bats/test_git_post_commit_codegraph.bats` (or a new
   `test_work_5g_graph_refresh.bats`) asserting `work.md` step 5g documents a graph-refresh
   call guarded by graph-exists + lock + background + fail-open. Run → fails.
2. **GREEN:** add to 5g, after `mb-work-checkbox.sh flip`, a fenced block that runs
   `python3 scripts/mb-codegraph.py --apply --docs <bank> <repo>` in the background under
   `<bank>/.index/.graph-rebuild.lock`, only when `graph.json` exists; never blocks the loop.
3. Note: refresh is skipped when no graph exists (first build stays manual, per Stage 1/6).

### DoD (SMART)
- [ ] `work.md` 5g contains a graph-refresh step with all four guards (exists · lock · background · fail-open exit 0).
- [ ] Test asserts the documented command matches `mb-codegraph.py --apply --docs`.
- [ ] No refresh when `graph.json` absent (documented).
- [ ] `execution`-workflow path (no judge) still reaches the refresh (it lives after `flip`, which both paths hit).

### Тестовые сценарии
- `test_work_5g_documents_background_graph_refresh` — block present with guards.
- `test_work_5g_refresh_skipped_when_no_graph` — absent-graph branch documented.

### Команды проверки
```bash
bats tests/bats/test_git_post_commit_codegraph.bats
grep -n "graph-rebuild.lock\|mb-codegraph.py --apply" commands/work.md
```

### Edge cases
- Concurrent items racing the lock (mkdir atomic → one wins, others skip); commit that
  changed no source (refresh is cheap/no-op); `pipeline.yaml` protected-paths must not block a background build.

---

## Stage 6: Give implementers one-time rebuild permission
<!-- mb-stage:6 -->
**Complexity:** S · **Время:** ~2 мин · **Зависимости:** — · **Агент:** mb-developer
**Файлы:** edit `agents/mb-tooling-core.md`

Only `mb-research` may currently rebuild a stale graph; implementers are told to fall back to
Grep, so an orphan graph is never repaired. Add ONE line to the shared tooling-core (reaches
all role agents via the `/mb work` prepend) permitting a single opportunistic
`mb-codegraph.py --apply` when the graph is stale, then continue fail-open.

### Задачи (TDD — red FIRST)
1. **RED:** extend `tests/bats/test_agent_graph_routing.bats` to assert `mb-tooling-core.md`
   grants a one-time rebuild-on-stale permission (grep for `mb-codegraph.py --apply` + "once"/"one-time"). Run → fails.
2. **GREEN:** add the line under the fail-open note in `mb-tooling-core.md`: when the graph is
   stale, an implementer MAY run `python3 scripts/mb-codegraph.py --apply --docs <bank> .` ONCE,
   then proceed; never loop, never block if it fails.

### DoD (SMART)
- [ ] `mb-tooling-core.md` documents a bounded ("once") rebuild permission on stale.
- [ ] Fail-open wording preserved (rebuild failure → Grep/Glob/Read, never block).
- [ ] `test_agent_graph_routing.bats` green.

### Тестовые сценарии
- `test_tooling_core_grants_one_time_rebuild` — permission line present, bounded, fail-open.

### Команды проверки
```bash
bats tests/bats/test_agent_graph_routing.bats
```

### Edge cases
- Two parallel implementers both trying to rebuild → the Stage-5 lock also guards this;
  reference the same `.graph-rebuild.lock` so a concurrent rebuild is skipped, not doubled.

---

## Stage 7: Reachable freshness in role files + engineering-core pointer
<!-- mb-stage:7 -->
**Complexity:** M · **Время:** ~5 мин · **Зависимости:** Stage 1 · **Агент:** mb-developer
**Файлы:** edit `agents/mb-developer.md`, `agents/mb-backend.md`, `agents/mb-frontend.md`, `agents/mb-qa.md`, `agents/mb-architect.md`, `agents/mb-engineering-core.md`

Role files tell agents to "check the Code graph line in `/mb context`" — but the dispatched
prompt has no `/mb context`, and tooling-core gives a different (fail-open) protocol → two
conflicting freshness signals. Make role files self-contained: check freshness via
`mb-graph-query.py status` directly. Add a one-line graph pointer to the primacy file
`mb-engineering-core.md` (currently zero graph mentions) so the first-composed block isn't
blind to the graph.

### Задачи (TDD — red FIRST)
1. **RED:** extend `tests/bats/test_agent_graph_routing.bats` — assert NO role file references
   `/mb context` for freshness, all five reference `mb-graph-query.py status`, and
   `mb-engineering-core.md` contains a one-line graph pointer. Run → fails.
2. **GREEN:** in each of the 5 role files' "Code-graph routing" block, replace
   "check `/mb context`'s Code graph line" with
   "run `python3 scripts/mb-graph-query.py status --graph .memory-bank/codebase/graph.json`; if `fresh` …".
3. Add to `mb-engineering-core.md` one line pointing to tooling-core's graph-first routing.

### DoD (SMART)
- [ ] 0 occurrences of `/mb context` as a freshness source across the 5 role files (grep proves it).
- [ ] All 5 role files call `mb-graph-query.py status` for the fresh/stale decision.
- [ ] `mb-engineering-core.md` has exactly one graph pointer line (primacy no longer blind).
- [ ] Single freshness protocol (self-contained `status`) — no conflict with tooling-core.
- [ ] `test_agent_graph_routing.bats` green.

### Тестовые сценарии
- `test_role_files_use_graph_query_status_not_mb_context` — all 5 self-contained.
- `test_engineering_core_has_graph_pointer` — primacy file references the graph.

### Команды проверки
```bash
bats tests/bats/test_agent_graph_routing.bats
grep -rn "mb context" agents/mb-developer.md agents/mb-backend.md agents/mb-frontend.md agents/mb-qa.md agents/mb-architect.md
```

### Edge cases
- Keep the routing intent identical (only the freshness-source changes); don't break the
  existing impact/neighbors/semantic-search command lines the same block already documents.

---

## Stage 8: Reconcile session-memory docs to code (MEDIUM) + MB_AUTO_CAPTURE decision
<!-- mb-stage:8 -->
**Complexity:** M · **Время:** ~5 мин · **Зависимости:** Stages 2, 3 · **Агент:** mb-developer
**Файлы:** edit `references/session-memory.md`, `SKILL.md` (~439)

Report §1.4 enumerates 8 doc/code drifts. Reconcile docs to the real code (the code is
correct; the docs lie). **`MB_AUTO_CAPTURE` decision RESOLVED (2026-07-15):** keep the code
default `auto` (the dual-writer is intended); this stage ONLY corrects the doc to `default:
auto`. Do NOT flip the code default and do NOT add an "under review" note — the default is
confirmed.

### Задачи
1. Frontmatter schema (`references/session-memory.md:33-45`): mark `agent`/`ended`/`mtime`/
   `summary_backend` as **not currently emitted** (or remove) — match what capture actually writes.
2. Live-log format (`:52-58`): single-line-per-turn (not multi-line) — match real files.
3. Summary sections: **4** (`### What changed / Decisions / Open questions / Files`), not 6.
4. Remove the non-existent `## Diagnostics` section (`:99-106`).
5. Remove the dead `MB_RECALL` variable (`:190`).
6. `MB_AUTO_CAPTURE` default `off`→`auto` (`:193`) — plain correction, no "under review" note (decision resolved: default stays `auto`).
7. `MB_CATCHUP_MAX` `5`→`2` (`:188`).
8. `SKILL.md:439` "ripgrep" → "hybrid semantic + lexical fused by RRF" (matches `mb-recall.sh`).

### DoD (SMART)
- [ ] All 8 items reconciled; a doc-vs-code assertion test (below) passes.
- [ ] `references/session-memory.md` states `MB_AUTO_CAPTURE` default = `auto` (plain fact, no "under review" wording).
- [ ] `SKILL.md` no longer describes recall as ripgrep-only.
- [ ] Doc-count guard (`tests/pytest/test_doc_counts.py` if it asserts section counts) stays green.

### Тестовые сценарии
- `test_session_memory_doc_matches_code_defaults` (new or extend `test_doc_counts.py`) — asserts `MB_CATCHUP_MAX=2`, `MB_AUTO_CAPTURE=auto`, no `MB_RECALL`, no `## Diagnostics`, 4 Summary sections, SKILL.md recall mentions RRF.

### Команды проверки
```bash
python3 -m pytest tests/pytest/test_doc_counts.py -q
grep -n "MB_CATCHUP_MAX\|MB_AUTO_CAPTURE\|MB_RECALL\|Diagnostics\|ripgrep" references/session-memory.md SKILL.md
```

### Edge cases
- Don't delete env vars that are actually live elsewhere — grep the codebase for each before removing
  (`MB_RECALL` dead-check: `grep -rn MB_RECALL hooks/ scripts/`).

---

## Stage 9 (OPTIONAL, last): Transcript drill-down `/mb recall --transcript`
<!-- mb-stage:9 -->
**Complexity:** M · **Время:** ~5 мин · **Зависимости:** — · **Агент:** mb-developer (TDD)
**Файлы:** create `tests/pytest/test_recall_transcript.py`; edit `hooks/mb-recall.sh` + a small helper in `hooks/lib/`

The one capability memsearch has that we lack: anchor a hit back to the raw JSONL and show
±N turns around a `turn_uuid`. `transcript:` is already in session frontmatter — only the
"show ±N turns around turn_uuid" tool is missing. **Mark optional** — ship only if Stages 1-8
are green and time remains.

### Задачи (TDD — red FIRST)
1. **RED:** `test_recall_transcript.py` — given a fixture JSONL with N turns and a target
   `turn_uuid`, assert the helper returns exactly ±2 turns around it (role-tagged, redacted). Run → fails.
2. **GREEN:** add `hooks/lib/transcript_window.py` (`window(jsonl_text, turn_uuid, n=2)`);
   wire `mb-recall.sh --transcript <turn_uuid> [--context N]` to resolve the transcript path
   from the session frontmatter and print the window.
3. Redact secrets + strip `<private>` (reuse `_sanitize`).

### DoD (SMART)
- [ ] `--transcript <uuid>` prints ±N role-tagged turns; unknown uuid → exit 3 + clear message.
- [ ] Secrets redacted in the window (reuse `redact_secrets`).
- [ ] New helper ≤400 lines; `ruff` + `shellcheck` clean.
- [ ] Marked OPTIONAL — plan is complete-and-shippable without this stage.

### Тестовые сценарии
- `test_transcript_window_returns_pm_n_turns` — exact ±N slice.
- `test_transcript_window_unknown_uuid_errors` — exit 3.
- `test_transcript_window_redacts_secrets` — no key leaks.

### Команды проверки
```bash
python3 -m pytest tests/pytest/test_recall_transcript.py -q
shellcheck hooks/mb-recall.sh
```

### Edge cases
- uuid at file start/end (clamped window); malformed JSONL lines skipped; transcript file
  missing (graceful message, exit 3); huge transcript (stream, don't load twice).

---

## Граф зависимостей

```
Stage 1 (rebuild) ──┬── Stage 5 (work 5g refresh)
                    └── Stage 7 (reachable freshness)
Stage 2 (chunker) ──── Stage 8 (docs)
Stage 3 (recall drop) ┘
Stage 4 (prune→reindex)   ─ independent
Stage 6 (rebuild perm)    ─ independent
Stage 9 (transcript, OPTIONAL) ─ independent
```

## Параллелизация
| Wave | Stages | Заметка |
|------|-------|---------|
| 1 | 1, 2, 3, 4, 6 | все независимы; 1 первый (cheap, unblocks) |
| 2 | 5, 7 | зависят от 1 (fresh graph) |
| 3 | 8 | зависит от 2+3 (docs describe fixed behavior) |
| 4 | 9 | OPTIONAL, только если время осталось |

## Потенциальные конфликты при merge
- Stages 6 и 7 оба редактируют `agents/*` и общий тест `test_agent_graph_routing.bats` → один
  developer на оба, либо строгий порядок 6→7 (не параллелить внутри одного файла теста).
- Stages 2 и 8 оба косвенно про session-memory, но разные файлы (`semantic_chunk.py` vs docs) — merge-safe.

## Open decisions (для пользователя) — РЕШЕНО 2026-07-15
1. **`MB_AUTO_CAPTURE=auto` (Stage 8)** — ✅ РЕШЕНО: оставить код-дефолт `auto` (двойная запись
   признана намеренной), Stage 8 правит ТОЛЬКО `references/session-memory.md` к реальности
   (`default: auto`). Код-дефолт НЕ флипается. Снять из DoD Stage 8 требование «flag as under
   review» — дефолт подтверждён, док просто выравнивается.
2. **Stage 9 (transcript drill-down)** — ✅ РЕШЕНО: остаётся в скоупе этого fix-плана (последний
   OPTIONAL-stage).

Исполнение: старт с **Stage 1** (пересборка графа) — по решению пользователя.

## Checklist (копировать в checklist.md)
- ✅ Stage 1: Rebuild code graph + verify fresh (commit aeb40db — fresh, 2498 nodes/12644 edges)
- ✅ Stage 2: Chunker bullet-boundary alignment (HIGH) — implement→verify PASS (49/49 py3.11, ruff clean, 191 LOC)
- ⬜ Stage 3: Recall drops dangling hits
- ⬜ Stage 4: Prune --apply invalidates index
- ⬜ Stage 5: Auto-refresh graph in /mb work 5g
- ⬜ Stage 6: Implementer one-time rebuild permission
- ⬜ Stage 7: Reachable freshness in role files + engineering-core pointer
- ⬜ Stage 8: Reconcile session-memory docs + MB_AUTO_CAPTURE decision
- ⬜ Stage 9 (OPTIONAL): /mb recall --transcript drill-down
