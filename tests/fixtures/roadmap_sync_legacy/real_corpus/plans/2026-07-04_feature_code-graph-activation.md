---
type: feature
scope: code-graph-activation
created: 2026-07-04
status: queued
priority: HIGH
backlog: I-087
parallel_safe: true
linked_report: .memory-bank/notes/2026-07-01_swarmline-gap-plans-created.md
cross_repo: [taskloom, swarmline]
---

# Feature: Code-Graph Activation (Path A — all four steps)

Make the Memory Bank **code graph a used tool, not shelf-ware.** Audit evidence
over 12 days (68 744 bash commands, 214 sessions): **0** calls to
`mb-graph-query`, **1** call to `mb-semantic-search`, **0** `jq` over `graph.json`
— against ~6 000 structural `grep`/`rg` invocations. Four root causes, four steps.

## Goal

After this feature: (1) `graph.json` exists and is **fresh** for taskloom +
swarmline; (2) every graph artifact carries a **freshness stamp** and staleness is
checked against **git HEAD**, not only file mtime; (3) `/mb context` **advertises**
the graph (freshness + counts + 2-3 ready commands) and the project worker agents
**route structural questions to the graph first**; (4) a **non-blocking nudge**
redirects structural `grep`/`rg` to `mb-graph-query` when the graph is fresh.

### Confirmed root causes (verified in code, 2026-07-04)

1. **Artifact stale/absent.** swarmline `graph.json` built 2026-04-25 (376 `.py`
   changed since); taskloom `.memory-bank/codebase/` does **not** exist. The
   writer `mb-codegraph.py::_write_graph_jsonl` (lines 301-321) emits `node` +
   `edge` + additive `node-attr` rows only — **no `generated_at`, no commit** — so
   there is nothing to check freshness against except file mtime.
2. **No delivery to context.** `mb-context.sh` (lines 58-81) reads only
   `codebase/*.md`; it **never mentions `graph.json`**. The SessionStart cheat-sheet
   (`hooks/mb-session-start.sh:35-43`) names the graph in prose only.
3. **Worker agents don't know the graph.** Graph-first routing lives ONLY in
   `agents/mb-research.md` (lines 36-49) and `agents/mb-codebase-mapper.md` (lines
   43-67, the only staleness check: `stat` mtime vs `MB_GRAPH_STALE_HOURS=24`).
   taskloom's project agents (`developer/architect/verifier/tester/analyst/
   documentor`) grep by definition; skill role agents (`mb-developer/mb-backend/
   mb-frontend/mb-architect/mb-qa/plan-verifier`) carry no graph routing.
4. **No enforcement + a counter-incentive.** No hook nudges toward the graph, and
   the rtk hook (`PreToolUse Bash` rewrite `grep → rtk grep`) makes grep *cheaper*.

### The fork

- **(A) Activate — all four steps** (chosen by the user): build/refresh artifacts,
  add freshness + auto-update, deliver into context + agents, add an enforcement
  nudge.
- **(B) Delete the graph** — walk back a tested, documented subsystem
  (`mb-codegraph.py`, `mb-graph-query.py`, `mb-semantic-search.py`, 20+ pytest
  files, two graph-aware agents). Strictly more churn than last-mile activation.

### Recommendation: **(A) Activate.** All four steps below.

The expensive parts are already paid: the builder, the query CLI, the semantic
search, the canonical loader, and two graph-aware agents exist and are green. What
is missing is **freshness metadata, delivery, and adoption pressure** — additive,
backward-compatible wiring, not a new subsystem.

## Scope

### In scope
- Build taskloom `graph.json` + `codebase/*.md`; refresh swarmline `graph.json`.
- Additive `meta` header row in `graph.json` (`generated_at` + git `commit` +
  node/edge counts) — backward-compatible (all readers filter by row `type`).
- Git-HEAD staleness helper + a `status` subcommand on `mb-graph-query.py`.
- Opt-in background incremental rebuild from SessionStart (`MB_GRAPH_AUTO`, default
  **off**) + an opt-in git `post-commit` template (documented, **not** auto-installed).
- `mb-context.sh` code-graph section (freshness + counts + ready commands; never
  injects graph contents).
- Compact graph-first routing block in 6 skill role agents + 6 taskloom project
  agents (cross-repo).
- Non-blocking `mb-graph-nudge.sh` PreToolUse hook (fires only when the graph is
  fresh; throttled; off-switch; fail-safe) + registration.

### Out of scope
- tree-sitter install for non-Python languages (taskloom + swarmline are Python;
  stdlib `ast` suffices). Non-Python coverage is a follow-up.
- Reworking `mb-graph-query.py` query semantics or `mb-semantic-search` ranking.
- Injecting graph contents into the prompt (the 7.5 MB artifact stays on disk).
- Auto-installing the git hook or flipping any existing default flag to "on".
- `--cochange` co-change edges by default (deferred — see Assumptions).

## Assumptions
- **taskloom + swarmline are Python** → `mb-codegraph.py` stdlib `ast` path is
  sufficient; tree-sitter absence does not block (verified: builder has a Python
  AST path; `codegraph_treesitter.py` is optional).
- **`--docs` = YES, `--cochange` = deferred.** `--docs` enriches nodes with
  `doc`/`signature` and directly improves `mb-semantic-search` (a shipped feature);
  cost is build-time only (never injected into context). `--cochange` only sharpens
  secondary god-node/impact analytics, adds a git-history pass, and can be added
  later without a rebuild-format change — deferred to keep first-activation surface
  small. (mb-research's own rebuild command uses `--docs` only, no `--cochange`.)
- **`git -C <src_root> rev-parse HEAD` is available** where builds run (already used
  by `mb-codegraph.py:90` and `codegraph_cochange.py:169`). Fail-open when git is
  absent → `commit=null`, freshness degrades to age-only.
- **The `meta` row is always-on, not flag-gated.** Freshness must exist on every
  graph or staleness cannot be checked. It is additive + backward-compatible; no
  consumer behavior changes (all readers filter by `type`). This is a deliberate,
  documented format change (design-contract note in Stage 3), not a default flip.
- bats + pytest run under the repo `.venv` (`PATH="$PWD/.venv/bin:$PATH"`).

## Risks
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| A new `meta` row breaks a `graph.json` consumer | Low | High | All 4 readers filter by row `type` (verified: `codegraph_loader.load_graph` ignores non-node/edge; `semantic_search.load_churn` filters `"node-attr"`; mapper's python example skips `type!="node"`; jq `select(.type==…)`). Stage 3 ships a regression test asserting `(nodes,edges)` parse byte-for-byte unchanged. |
| Background rebuild dirties git-tracked `graph.json` unexpectedly | Medium | Medium | `MB_GRAPH_AUTO` default **off**; when on, rebuild only if graph already exists AND is stale; lockfile; fail-safe exit 0. Documented that it mutates a committable file. |
| Nudge is noisy / fights the rtk grep hook | Medium | Medium | Fires only when graph is FRESH; throttled 1×/session (marker file); `MB_GRAPH_NUDGE=off`; detects `rtk grep`/`rtk rg` too; non-blocking `additionalContext` only. |
| tree-sitter absent → graph misses non-Python files → nudge points at an incomplete graph | Low | Low | Both target repos are Python. Nudge is a *hint*, never a block; agent can still grep. Note non-Python as a follow-up. |
| git worktrees (`.clone/worktrees/*`) → graph commit ≠ HEAD in the worktree | Medium | Low | Staleness uses `git -C <src_root> rev-parse HEAD` + `rev-list --count <commit>..HEAD`; on any git error fall back to mtime-only; never error. |
| Large repo → first build slow | Low | Low | First build stays manual (Stages 1-2); auto path is incremental via `.cache` (seconds) and only refreshes an existing graph. |

---

<!-- mb-stage:1 -->
## Stage 1: taskloom — build graph + codebase docs (ops, cross-repo)

**Complexity:** M · **Time:** ~5 min · **Dependencies:** — · **Agent:** mb-developer (ops)
**Repo:** `/Users/fockus/Apps/taskloom` (CROSS-REPO — do not commit skill-repo files here)
**Files (created in taskloom):**
- `/Users/fockus/Apps/taskloom/.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md`
- `/Users/fockus/Apps/taskloom/.memory-bank/codebase/graph.json`
- `/Users/fockus/Apps/taskloom/.memory-bank/codebase/god-nodes.md`

### Tasks
1. `/mb map` (focus `all`) → writes the four `codebase/*.md` (none exist today).
2. Build the graph with docs enrichment (no `--cochange` — see Assumptions):
   ```bash
   cd /Users/fockus/Apps/taskloom
   PATH="$PWD/.venv/bin:$PATH" python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py \
     --apply --docs .memory-bank src
   ```
3. Sanity-query the fresh graph:
   ```bash
   python3 ~/.claude/skills/memory-bank/scripts/mb-graph-query.py impact \
     --graph .memory-bank/codebase/graph.json --symbol AccessContext
   ```

### DoD
- [ ] `.memory-bank/codebase/graph.json` exists, non-empty, `nodes>0` and `edges>0`
      (`python3 -c "from memory_bank_skill.codegraph_loader import load_graph as g;n,e=g(__import__('pathlib').Path('.memory-bank/codebase/graph.json'));print(len(n),len(e))"` → both > 0).
- [ ] All four `codebase/*.md` present, each ≤70 lines, header `Graph: used`.
- [ ] `mb-graph-query.py impact --symbol AccessContext` returns `ok:true` with a
      non-empty `dependents` OR `dependencies` list.
- [ ] `god-nodes.md` lists ≥3 ranked nodes.

### Test scenarios (ops verification, not unit)
- `verify_taskloom_graph_nonempty` — loader returns nodes>0 & edges>0.
- `verify_taskloom_impact_query_resolves` — `impact` on a known symbol → `ok:true`.

### Commands
```bash
cd /Users/fockus/Apps/taskloom
PATH="$PWD/.venv/bin:$PATH" python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py --apply --docs .memory-bank src
python3 ~/.claude/skills/memory-bank/scripts/mb-graph-query.py summary --graph .memory-bank/codebase/graph.json --out-dir /tmp/tl-graph
```

### Edge cases
- taskloom has a `src/` layout (`src.root = "src"`) → pass `src` as `src_root`, not `.`.
- Do NOT commit generated `graph.json`/`codebase/*.md` unless the user asks (large
  artifact; git policy). Leave the tree state for the user to decide.

---

<!-- mb-stage:2 -->
## Stage 2: swarmline — refresh stale graph (ops, cross-repo)

**Complexity:** S · **Time:** ~3 min · **Dependencies:** — (parallel with Stage 1) · **Agent:** mb-developer (ops)
**Repo:** swarmline checkout (locate via the swarmline `.memory-bank/codebase/graph.json`)
**Files (regenerated):** swarmline `.memory-bank/codebase/graph.json`, `god-nodes.md`

### Tasks
1. Incremental refresh (reuses `.cache` — fast; 376 changed `.py` reparsed, rest cached):
   ```bash
   cd <swarmline-root>
   PATH="$PWD/.venv/bin:$PATH" python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py \
     --apply --docs .memory-bank <src_root>
   ```
2. If the `.cache` is from an incompatible old build, clear it and full-rebuild:
   `rm -rf .memory-bank/codebase/.cache` then re-run.

### DoD
- [ ] swarmline `graph.json` mtime is today; `reparsed>0` printed by the builder.
- [ ] Loader returns `nodes>0` & `edges>0`.
- [ ] `mb-graph-query.py summary` writes GRAPH_SUMMARY/IMPACT_MAP/TEST_LINKS with
      non-zero node/edge counts.

### Test scenarios (ops verification)
- `verify_swarmline_graph_refreshed` — mtime today AND `reparsed>0`.

### Commands
```bash
cd <swarmline-root>
PATH="$PWD/.venv/bin:$PATH" python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py --apply --docs .memory-bank <src_root>
```

### Edge cases
- If swarmline is checked out inside a git worktree, the incremental build still
  works (reparse is content-hash based, not git-based).

---

<!-- mb-stage:3 -->
## Stage 3: `meta` header row in the writer + `read_meta` in the loader (TDD)

**Complexity:** M · **Time:** ~5 min · **Dependencies:** — (parallel with Stages 1-2) · **Agent:** mb-backend
**Files:**
- `scripts/mb-codegraph.py` (`_write_graph_jsonl` 301-321; `run()` 359-464 to compute + pass `commit`/`generated_at`/counts)
- `memory_bank_skill/codegraph_loader.py` (add `read_meta`)
- `tests/pytest/test_codegraph_loader.py` (extend — backward-compat + read_meta)
- `tests/pytest/test_codegraph.py` (extend — writer emits meta)

### Design-contract note (record in the stage commit body)
The `meta` row is **always-on** (freshness must exist on every graph) and is
**additive + backward-compatible**: node/edge bytes are unchanged, and every reader
filters by row `type`. No CLI/env default flips; no consumer behavior changes. This
is the intended format change of Step 2, not a default alteration.

### Tasks (TDD)
1. **RED** in `test_codegraph_loader.py`:
   - `test_load_graph_ignores_meta_row` — a JSONL whose FIRST line is
     `{"type":"meta","generated_at":"…","commit":"abc1234","nodes":2,"edges":1}`
     followed by 2 node + 1 edge rows → `load_graph` returns exactly `(2 nodes, 1
     edge)`, identical to the same file without the meta row.
   - `test_read_meta_returns_stamp` — `read_meta(path)` → dict with
     `generated_at`, `commit`, `nodes`, `edges`.
   - `test_read_meta_absent_returns_none` — legacy graph (no meta row) → `None`.
   - `test_read_meta_malformed_returns_none` — first line is not JSON → `None` (fail-open).
2. **RED** in `test_codegraph.py`:
   - `test_writer_prepends_meta_row` — build+write a tiny graph; first line parses
     to `type=="meta"` with `nodes==len(nodes)`, `edges==len(edges)`, an ISO-8601
     `generated_at` (ends with `Z`), and a `commit` (7-40 hex chars OR `null`).
3. Add `read_meta(path: Path) -> dict | None` to `codegraph_loader.py`: read only
   the FIRST non-blank line; if `json.loads(...).get("type")=="meta"` return it, else
   `None`; any exception → `None`.
4. In `mb-codegraph.py::run()`, before `_write_graph_jsonl`, compute:
   - `generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")`
   - `commit = subprocess git -C <src> rev-parse HEAD` → short (first 12), `None` on
     any failure (mirror the existing `rev-parse --show-toplevel` guard at line 90).
   Pass `meta={"type":"meta","schema":1,"generated_at":…,"commit":…,"nodes":N,"edges":M,"src_root":str(src)}`.
5. In `_write_graph_jsonl`, PREPEND the meta line (first element of `lines`) when
   `meta` is provided; keep node/edge/node-attr ordering byte-identical after it.

### DoD
- [ ] `read_meta` added; returns stamp for new graphs, `None` for legacy/malformed.
- [ ] Writer prepends exactly one `meta` row with `generated_at` (Z-suffixed),
      `commit` (hex or null), and `nodes`/`edges` counts matching the payload.
- [ ] `load_graph` byte-identical `(nodes,edges)` with vs without the meta row
      (regression test green).
- [ ] `semantic_search.load_churn` still returns the same churn map when a meta row
      is present (add one assertion referencing an existing churn fixture).
- [ ] Tests: +5 pytest; existing `test_codegraph*.py` + `test_semantic_search_churn.py` green.
- [ ] `ruff check scripts/mb-codegraph.py memory_bank_skill/codegraph_loader.py` clean.

### Test scenarios
- `test_load_graph_ignores_meta_row`
- `test_read_meta_returns_stamp`
- `test_read_meta_absent_returns_none`
- `test_read_meta_malformed_returns_none`
- `test_writer_prepends_meta_row`

### Commands
```bash
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_codegraph_loader.py tests/pytest/test_codegraph.py tests/pytest/test_semantic_search_churn.py -q
PATH="$PWD/.venv/bin:$PATH" ruff check scripts/mb-codegraph.py memory_bank_skill/codegraph_loader.py
```

### Edge cases
- Detached HEAD / no commits yet → `commit=null`; still emit `generated_at`.
- A repo with `rev-parse` returning an error to stderr must not crash the build
  (fail-open, `commit=null`), and must not print git noise into `graph.json`.

---

<!-- mb-stage:4 -->
## Stage 4: freshness module + `status` subcommand (git-HEAD staleness) (TDD)

**Complexity:** M · **Time:** ~5 min · **Dependencies:** Stage 3 · **Agent:** mb-backend
**Files:**
- `memory_bank_skill/codegraph_freshness.py` (NEW — SRP, keeps loader thin)
- `scripts/mb-graph-query.py` (add `status` subcommand)
- `tests/pytest/test_codegraph_freshness.py` (NEW)
- `tests/pytest/test_graph_query.py` (extend — `status` subcommand)

### Tasks (Contract-First + TDD)
1. **Contract:** `graph_freshness(graph_path, src_root, *, stale_hours, stale_commits) -> dict`
   returns:
   `{ "exists": bool, "generated_at": str|None, "commit": str|None,
      "age_hours": float|None, "commits_behind": int|None, "stale": bool,
      "reason": "absent"|"fresh"|"age"|"commits"|"unknown" }`.
   - `commits_behind = git -C <src_root> rev-list --count <commit>..HEAD` (None on
     any git error OR when `commit` is null).
   - `stale = True` when `not exists`, OR `age_hours>stale_hours`, OR
     `commits_behind>stale_commits`. When git is unavailable, use age only.
2. **RED** `test_codegraph_freshness.py`:
   - `test_freshness_absent_graph_is_stale` — missing file → `exists:False, stale:True, reason:"absent"`.
   - `test_freshness_recent_within_thresholds_is_fresh` — meta with `generated_at`
     = now, HEAD == commit (monkeypatch git) → `stale:False, reason:"fresh"`.
   - `test_freshness_old_age_marks_stale` — `generated_at` 48h ago, `stale_hours=24`
     → `stale:True, reason:"age"`.
   - `test_freshness_many_commits_behind_marks_stale` — `commits_behind=120`,
     `stale_commits=50` → `stale:True, reason:"commits"`.
   - `test_freshness_git_unavailable_falls_back_to_age` — git raises → `commits_behind:None`,
     staleness decided by age only, never crashes.
3. **RED** `test_graph_query.py`:
   - `test_status_subcommand_json_reports_freshness` — `status --graph <g> --src-root <r> --json`
     → JSON with `exists/stale/commits_behind`; exit 0.
   - `test_status_subcommand_missing_graph_exit3` — absent graph → exit `EXIT_MISSING_GRAPH` (3).
4. Implement `codegraph_freshness.py` (uses `codegraph_loader.read_meta` +
   `subprocess`); read thresholds from args (defaults `MB_GRAPH_STALE_HOURS=24`,
   `MB_GRAPH_STALE_COMMITS=50`).
5. Add `status` to `mb-graph-query.py::build_parser` (new subparser: `--graph`
   required, `--src-root` default `.`, `--json`); in `run()` call `graph_freshness`
   and print markdown or JSON; return 0 when exists else 3.

### DoD
- [ ] `graph_freshness` returns the documented dict; git errors never raise.
- [ ] `mb-graph-query.py status` prints freshness (markdown default, `--json` flag);
      exit 0 when the graph exists, 3 when absent.
- [ ] Thresholds honor `MB_GRAPH_STALE_HOURS` (24) + `MB_GRAPH_STALE_COMMITS` (50)
      env overrides.
- [ ] Tests: +7 pytest; existing `test_graph_query.py` green.
- [ ] `ruff check` clean on both changed files; `codegraph_freshness.py` ≤120 lines.

### Test scenarios
- `test_freshness_absent_graph_is_stale`
- `test_freshness_recent_within_thresholds_is_fresh`
- `test_freshness_old_age_marks_stale`
- `test_freshness_many_commits_behind_marks_stale`
- `test_freshness_git_unavailable_falls_back_to_age`
- `test_status_subcommand_json_reports_freshness`
- `test_status_subcommand_missing_graph_exit3`

### Commands
```bash
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_codegraph_freshness.py tests/pytest/test_graph_query.py -q
PATH="$PWD/.venv/bin:$PATH" ruff check memory_bank_skill/codegraph_freshness.py scripts/mb-graph-query.py
python3 scripts/mb-graph-query.py status --graph .memory-bank/codebase/graph.json --src-root . --json
```

### Edge cases
- `<commit>..HEAD` where `<commit>` is unknown to the repo (graph built elsewhere)
  → `rev-list` errors → `commits_behind:None` → age-only decision.
- Worktree: `git -C <src_root> rev-parse HEAD` resolves the worktree HEAD; mismatch
  vs the graph commit correctly reports commits_behind (or None) — never crashes.

---

<!-- mb-stage:5 -->
## Stage 5: opt-in background incremental rebuild in SessionStart (MB_GRAPH_AUTO) (TDD)

**Complexity:** M · **Time:** ~5 min · **Dependencies:** Stage 4 · **Agent:** mb-backend
**Files:**
- `hooks/mb-session-start.sh` (add a graph-auto block after the semantic-reindex block, lines 21-27)
- `tests/bats/test_session_start.bats` (extend — auto-rebuild decision)

### Decision (record in commit body)
Default **`MB_GRAPH_AUTO=off`**. Rationale: `graph.json` is a **committable /
git-tracked** artifact; a background mutation would dirty the working tree
unexpectedly (unlike the semantic index under gitignored `.index/`). Off-by-default
respects the design contract (expensive/side-effecting paths opt-in). When set to
`on`/`auto`, rebuild ONLY an existing + stale graph, incrementally, in the
background, under a lock, fail-safe.

### Tasks (TDD)
1. Factor the decision into a sourceable helper `_mb_graph_auto_should_rebuild()`
   (returns 0 = rebuild) so bats can test it without forking. Guards:
   - `MB_GRAPH_AUTO` in `on|auto` (default `off` → return 1);
   - `graph.json` exists (first build stays manual → return 1 if absent);
   - `mb-graph-query.py status` reports `stale:true` (fresh → return 1);
   - `python3` present (else return 1).
2. When it returns 0, run the incremental rebuild in a background subshell with a
   lockfile:
   ```bash
   LOCK="$MB/.index/.graph-rebuild.lock"
   if mkdir "$LOCK" 2>/dev/null; then
     ( trap 'rmdir "$LOCK" 2>/dev/null' EXIT
       "$_PY" ~/.claude/skills/memory-bank/scripts/mb-codegraph.py --apply --docs "$MB" . >/dev/null 2>&1
     ) >/dev/null 2>&1 &
   fi
   ```
   Add a `MB_GRAPH_AUTO_DRYRUN=1` branch that PRINTS the rebuild command instead of
   forking (for the bats assertion). The hook must still `exit 0`.
3. **RED** `test_session_start.bats`:
   - `test_graph_auto_off_by_default_no_rebuild` — no `MB_GRAPH_AUTO` + stale graph
     → helper returns non-zero (no rebuild), hook prints `{}` or the recent block, exit 0.
   - `test_graph_auto_on_stale_graph_triggers_rebuild_cmd` — `MB_GRAPH_AUTO=on`,
     `MB_GRAPH_AUTO_DRYRUN=1`, existing stale graph fixture → stdout contains
     `mb-codegraph.py --apply`.
   - `test_graph_auto_on_absent_graph_no_rebuild` — `MB_GRAPH_AUTO=on` but no
     `graph.json` → no rebuild command (first build stays manual).
   - `test_graph_auto_on_fresh_graph_no_rebuild` — fresh graph → no rebuild.
   - `test_graph_auto_failsafe_exit0_when_python_missing` — PATH without python3 →
     hook still exits 0, no crash.

### DoD
- [ ] Default (`MB_GRAPH_AUTO` unset) → **no** rebuild spawned; SessionStart output
      unchanged from today (recent block only).
- [ ] `MB_GRAPH_AUTO=on` + existing + stale graph → rebuild command constructed
      (proven via `MB_GRAPH_AUTO_DRYRUN`); absent/fresh graph → no rebuild.
- [ ] Lockfile prevents concurrent rebuilds; hook always `exit 0` (fail-safe).
- [ ] Tests: +5 bats; existing `test_session_start.bats` green.
- [ ] `shellcheck hooks/mb-session-start.sh` clean; runs under `/bin/bash` (3.2) + 5.x.

### Test scenarios
- `test_graph_auto_off_by_default_no_rebuild`
- `test_graph_auto_on_stale_graph_triggers_rebuild_cmd`
- `test_graph_auto_on_absent_graph_no_rebuild`
- `test_graph_auto_on_fresh_graph_no_rebuild`
- `test_graph_auto_failsafe_exit0_when_python_missing`

### Commands
```bash
bash -n hooks/mb-session-start.sh
shellcheck hooks/mb-session-start.sh
PATH="$PWD/.venv/bin:$PATH" /bin/bash "$(command -v bats)" tests/bats/test_session_start.bats
```

### Edge cases
- Stale lock (previous crash left the dir) — acceptable to skip this session; add a
  comment noting a TTL cleanup is a follow-up (do NOT auto-delete a fresh lock).
- The rebuild writes to a git-tracked file: the SessionStart injection MUST not
  block on it (background `&`), and MUST not surface the rebuild in `additionalContext`.

---

<!-- mb-stage:6 -->
## Stage 6: opt-in git post-commit template (documented, NOT auto-installed) (TDD)

**Complexity:** S · **Time:** ~4 min · **Dependencies:** Stage 4 · **Agent:** mb-developer
**Files:**
- `hooks/git/post-commit-codegraph.sh` (NEW — opt-in template)
- `references/code-graph.md` (add a "Keep the graph fresh on commit (opt-in)" section)
- `tests/bats/test_git_post_commit_codegraph.bats` (NEW)

### Decision (record in commit body)
**Decline auto-install; ship a documented opt-in template.** The 2026-04-20-planned
`mb-codegraph-precommit.sh` is absent; a *post-commit* hook is safer than pre-commit
(never slows a commit). But it is per-repo, lives outside the skill's Claude-Code
hook system, and mutates a tracked `graph.json` → auto-installing it would dirty the
next diff and touch git plumbing (protected-paths). So: real script + one-line
manual install doc, **not** wired into `install.sh`.

### Tasks (TDD)
1. Write `hooks/git/post-commit-codegraph.sh` (executable): resolve the MB via a
   minimal check; if `graph.json` exists, run an incremental `--apply --docs`
   rebuild in the background, fail-safe (`exit 0` always); if absent, do nothing.
2. **RED** `test_git_post_commit_codegraph.bats`:
   - `test_post_commit_absent_graph_is_noop_exit0` — no graph → no rebuild, exit 0.
   - `test_post_commit_existing_graph_rebuilds` — with a graph + `..._DRYRUN=1` →
     stdout contains `mb-codegraph.py --apply`.
   - `test_post_commit_failsafe_when_python_missing` — PATH without python3 → exit 0.
3. Document the opt-in installer line in `references/code-graph.md`:
   `ln -sf ~/.claude/skills/memory-bank/hooks/git/post-commit-codegraph.sh .git/hooks/post-commit`
   with an explicit warning that it mutates the tracked `graph.json`.

### DoD
- [ ] `hooks/git/post-commit-codegraph.sh` exists, executable bit set, `exit 0` on
      every path (no graph, no python, rebuild).
- [ ] NOT referenced by `install.sh` or `settings/hooks.json`
      (`grep -c post-commit-codegraph install.sh settings/hooks.json` → 0).
- [ ] `references/code-graph.md` documents the opt-in `ln -sf` install + the
      tracked-file warning.
- [ ] Tests: +3 bats; `shellcheck hooks/git/post-commit-codegraph.sh` clean.

### Test scenarios
- `test_post_commit_absent_graph_is_noop_exit0`
- `test_post_commit_existing_graph_rebuilds`
- `test_post_commit_failsafe_when_python_missing`

### Commands
```bash
bash -n hooks/git/post-commit-codegraph.sh
shellcheck hooks/git/post-commit-codegraph.sh
PATH="$PWD/.venv/bin:$PATH" /bin/bash "$(command -v bats)" tests/bats/test_git_post_commit_codegraph.bats
grep -c post-commit-codegraph install.sh settings/hooks.json
```

### Edge cases
- Executable bit must survive install/copy — assert `-x` in the bats setup (RULES:
  new executable scripts test the executable expectation).

---

<!-- mb-stage:7 -->
## Stage 7: `mb-context.sh` code-graph section (TDD)

**Complexity:** M · **Time:** ~5 min · **Dependencies:** Stage 4 · **Agent:** mb-developer
**Files:**
- `scripts/mb-context.sh` (add a "Code graph" section after the Codebase-summary block, ~line 81)
- `tests/bats/test_context_integration.bats` (extend)

### Tasks (TDD)
1. **RED** `test_context_integration.bats`:
   - `test_context_shows_fresh_graph_line` — bank with a FRESH graph fixture (meta
     now + counts) → output contains `Code graph`, `nodes=`, `edges=`, and a
     `god-nodes.md` pointer.
   - `test_context_shows_stale_graph_hint` — stale graph → output contains
     `stale` AND a rebuild hint (`mb-codegraph.py --apply`).
   - `test_context_absent_graph_shows_build_hint` — no graph → `not built` + the
     build command; never errors (`set -e` safe).
2. Add the section: if `$MB_PATH/codebase/graph.json` exists, call
   `mb-graph-query.py status --graph … --src-root . --json` (degrade to a plain
   `-f` existence + mtime check if python3 absent). Print:
   - line 1: `Code graph: ✅ fresh (age Nh, K commits behind)` OR `⚠️ stale (…) → rebuild: <cmd>` OR `not built → build: <cmd>`;
   - line 2: `nodes=<N> edges=<M>` (from `read_meta`/status, NOT by parsing 7.5 MB);
   - line 3: `god-nodes: $MB_PATH/codebase/god-nodes.md`;
   - lines 4-6: 2-3 ready commands, e.g.
     `impact before refactor: python3 …/mb-graph-query.py impact --graph … --symbol <Name>`.
   - **Never** `cat graph.json` (do not inject contents).
3. Keep the whole section behind an existence guard; fail-open (any error → skip
   the section, do not abort `mb-context.sh`).

### DoD
- [ ] Fresh graph → `/mb context` shows a one-line freshness verdict + counts +
      god-nodes pointer + 2-3 ready commands.
- [ ] Stale graph → visible `stale` + rebuild command; absent → build hint.
- [ ] Section NEVER prints graph.json contents (assert output size delta < 2 KB in
      a bats check).
- [ ] Fail-open: python3 absent → mtime-only line, `mb-context.sh` still exits 0.
- [ ] Tests: +3 bats; existing `test_context_integration.bats` green.
- [ ] `shellcheck scripts/mb-context.sh` clean.

### Test scenarios
- `test_context_shows_fresh_graph_line`
- `test_context_shows_stale_graph_hint`
- `test_context_absent_graph_shows_build_hint`

### Commands
```bash
bash -n scripts/mb-context.sh
shellcheck scripts/mb-context.sh
PATH="$PWD/.venv/bin:$PATH" /bin/bash "$(command -v bats)" tests/bats/test_context_integration.bats
```

### Edge cases
- `--deep` mode must still work (the graph section is independent of the
  `codebase/*.md` deep dump).
- A bank with `codebase/*.md` but no `graph.json` → summary section prints, graph
  section shows "not built" — both coexist.

---

<!-- mb-stage:8 -->
## Stage 8: graph-first routing block in 6 skill role agents (TDD doc test)

**Complexity:** S · **Time:** ~5 min · **Dependencies:** Stage 4 (commands referenced) · **Agent:** mb-developer
**Files:**
- `agents/mb-developer.md`, `agents/mb-backend.md`, `agents/mb-frontend.md`,
  `agents/mb-architect.md`, `agents/mb-qa.md`, `agents/plan-verifier.md`
- `tests/bats/test_agent_graph_routing.bats` (NEW — doc/registration test)

### The block (≤10 lines, identical across the six; adapt only the lead verb)
```markdown
## Code-graph routing (when the graph is fresh)
Before structural greps, check `/mb context`'s "Code graph" line. If fresh:
- who-calls / blast-radius / which-tests → `python3 ~/.claude/skills/memory-bank/scripts/mb-graph-query.py impact --graph .memory-bank/codebase/graph.json --symbol <Name>`
- neighbors / relates-to → `… mb-graph-query.py neighbors --graph … --symbol <Name>`
- concept / "where is the logic for X" → `python3 ~/.claude/skills/memory-bank/scripts/mb-semantic-search.py "<question>" .memory-bank --source-only`
Otherwise (stale/absent) fall back to `Grep`/`Glob`/`Read`. Never block on the graph.
```

### Tasks (TDD)
1. **RED** `test_agent_graph_routing.bats`: for each of the six files assert it
   contains the sentinel `Code-graph routing (when the graph is fresh)` AND the
   string `mb-graph-query.py impact`.
2. Insert the block near each agent's "how to research / explore" area (after the
   role/why section, before task execution). Keep additions ≤10 lines each; do not
   restructure existing prompt sections.

### DoD
- [ ] All six agent files contain the sentinel heading + the `impact` command.
- [ ] Each file's net addition is ≤12 lines (`git diff --stat` per file).
- [ ] Tests: +1 bats (loops the six files); existing agent tests green.
- [ ] No agent prompt exceeds its prior size class disruptively (block is compact).

### Test scenarios
- `test_all_skill_role_agents_carry_graph_routing` — parametrized over the six files.

### Commands
```bash
PATH="$PWD/.venv/bin:$PATH" /bin/bash "$(command -v bats)" tests/bats/test_agent_graph_routing.bats
git diff --stat agents/mb-developer.md agents/mb-backend.md agents/mb-frontend.md agents/mb-architect.md agents/mb-qa.md agents/plan-verifier.md
```

### Edge cases
- `plan-verifier.md` and `mb-qa.md` are longer, structured prompts — insert the
  block as a standalone section, not inside an existing numbered list.

---

<!-- mb-stage:9 -->
## Stage 9: cross-repo rollout — taskloom project agents (ops)

**Complexity:** S · **Time:** ~5 min · **Dependencies:** Stage 1 (taskloom graph exists), Stage 8 (block text finalized) · **Agent:** mb-developer (ops)
**Repo:** `/Users/fockus/Apps/taskloom` (CROSS-REPO)
**Files (in taskloom):** `.claude/agents/{developer,architect,verifier,tester,analyst,documentor}.md`

### Tasks
1. Insert the SAME ≤10-line block from Stage 8 into each of the six taskloom agents,
   adjusting the graph path to taskloom's layout (`.memory-bank/codebase/graph.json`,
   `src` root as needed).
2. Verify each file references `mb-graph-query.py`.

### DoD
- [ ] All six taskloom agents contain the `Code-graph routing` sentinel + `impact` command
      (`grep -l 'Code-graph routing' /Users/fockus/Apps/taskloom/.claude/agents/*.md` → 6 files).
- [ ] taskloom `/mb context` (Stage 7 code) shows the graph as **fresh** (Stage 1).
- [ ] No skill-repo files changed in this stage.

### Test scenarios (ops verification)
- `verify_taskloom_agents_have_graph_block` — all six files match the sentinel.

### Commands
```bash
grep -l 'Code-graph routing' /Users/fockus/Apps/taskloom/.claude/agents/*.md | wc -l   # expect 6
```

### Edge cases
- taskloom is a separate git repo → its own commit/PR policy applies; do not
  commit without the user's go. Flag the diff for review.

---

<!-- mb-stage:10 -->
## Stage 10: `mb-graph-nudge.sh` PreToolUse hook + registration (TDD)

**Complexity:** L · **Time:** ~5 min · **Dependencies:** Stage 4 (freshness gate) · **Agent:** mb-backend
**Files:**
- `hooks/mb-graph-nudge.sh` (NEW)
- `settings/hooks.json` (add a PreToolUse entry, matcher `Grep|Bash`)
- `tests/bats/test_mb_graph_nudge.bats` (NEW)

### Behavior contract
Non-blocking `additionalContext` nudge that fires **only** when: the tool is `Grep`
OR a `Bash` structural `grep`/`rg` (including `rtk grep`/`rtk rg`) over source; AND
`graph.json` exists AND is **fresh** (reuse Stage 4 freshness, cheaply); AND not
already nudged this session (throttle marker). Off-switch `MB_GRAPH_NUDGE=off`.
Fail-safe: any error / missing dep → print `{}` and `exit 0`. Never blocks the tool.

### Tasks (Contract-First + TDD)
1. Parse stdin JSON (`tool_name`, `tool_input.command` for Bash, presence for Grep).
   Structural-grep detection (Bash): command matches
   `(^|[; &|])(rtk[[:space:]]+)?(grep|rg|egrep)([[:space:]]|$)` AND targets code
   (`-r`/`-R`/`--include`/a `src`/`*.py`-like arg). Grep tool → always structural.
2. Gate on freshness: `mb-graph-query.py status --graph <mb>/codebase/graph.json
   --src-root . --json` → nudge only if `exists:true` AND `stale:false`.
3. Throttle: marker `"$MB/.index/.graph-nudge.$SESSION"` (SESSION from
   `CLAUDE_SESSION_ID` else a date-hour bucket). If marker exists → `{}`. Else touch
   + emit the nudge.
4. Emit `additionalContext`:
   `Structural query detected. If the code graph is fresh, prefer:
    python3 ~/.claude/skills/memory-bank/scripts/mb-graph-query.py impact|neighbors|tests --graph .memory-bank/codebase/graph.json --symbol <Name> (deterministic who-calls/blast-radius/tests). Grep stays fine for regex/raw text.`
5. **RED** `test_mb_graph_nudge.bats`:
   - `test_nudge_fires_on_grep_tool_when_fresh` — Grep tool + fresh graph fixture →
     `additionalContext` contains `mb-graph-query`.
   - `test_nudge_fires_on_rtk_grep_bash_when_fresh` — Bash `rtk grep -rn foo src/`
     + fresh → fires (rtk-wrapped detected).
   - `test_nudge_silent_when_graph_absent` — no graph → `{}`, exit 0.
   - `test_nudge_silent_when_graph_stale` — stale graph → `{}` (don't push toward stale).
   - `test_nudge_off_switch` — `MB_GRAPH_NUDGE=off` → `{}`, exit 0.
   - `test_nudge_throttled_second_call_same_session` — second invocation, same
     `CLAUDE_SESSION_ID` → `{}`.
   - `test_nudge_ignores_non_structural_bash` — `Bash: ls -la` → `{}`.
   - `test_nudge_failsafe_on_malformed_stdin` — garbage stdin → `{}`, exit 0.
6. Register in `settings/hooks.json` PreToolUse: new object
   `{ "matcher": "Grep|Bash", "hooks": [{ "type":"command", "command":"~/.claude/hooks/mb-graph-nudge.sh # [memory-bank-skill]" }] }`.
   `install.sh` already globs `hooks/*.sh` (line 830) → copied automatically; add
   nothing to `install.sh`.

### DoD
- [ ] Nudge fires on `Grep` tool AND on `Bash` structural `grep`/`rg`/`rtk grep`,
      ONLY when the graph exists + is fresh.
- [ ] Silent (`{}`, exit 0) when: graph absent, graph stale, `MB_GRAPH_NUDGE=off`,
      already nudged this session, non-structural command, malformed stdin.
- [ ] Registered in `settings/hooks.json` under PreToolUse `Grep|Bash`; picked up by
      `merge-hooks.py` (no `install.sh` edit needed).
- [ ] Coexists with `block-dangerous.sh` (both run on Bash; nudge never blocks).
- [ ] Tests: +8 bats; `shellcheck hooks/mb-graph-nudge.sh` clean; `/bin/bash` (3.2) + 5.x.
- [ ] `settings/hooks.json` stays valid JSON (`python3 -m json.tool settings/hooks.json`).

### Test scenarios
- `test_nudge_fires_on_grep_tool_when_fresh`
- `test_nudge_fires_on_rtk_grep_bash_when_fresh`
- `test_nudge_silent_when_graph_absent`
- `test_nudge_silent_when_graph_stale`
- `test_nudge_off_switch`
- `test_nudge_throttled_second_call_same_session`
- `test_nudge_ignores_non_structural_bash`
- `test_nudge_failsafe_on_malformed_stdin`

### Commands
```bash
bash -n hooks/mb-graph-nudge.sh
shellcheck hooks/mb-graph-nudge.sh
python3 -m json.tool settings/hooks.json >/dev/null
PATH="$PWD/.venv/bin:$PATH" /bin/bash "$(command -v bats)" tests/bats/test_mb_graph_nudge.bats
```

### Edge cases
- The freshness call adds latency to EVERY Grep/Bash — keep it cheap: short-circuit
  on `MB_GRAPH_NUDGE=off` and on absent `graph.json` BEFORE spawning python; the
  `status` call runs only past those guards.
- Non-Python repo (graph misses the file) → still may nudge; acceptable (hint only).
  Note as a follow-up to gate by file-language once tree-sitter lands.
- `rtk` may rewrite the Bash command AFTER this PreToolUse hook — the regex must
  match BOTH `grep …` and `rtk grep …` forms (test both).

---

## Success metrics (review 2 weeks after rollout)
- **Adoption:** ≥20 real `mb-graph-query` invocations in `~/.claude/bash-audit.log`
  across taskloom + swarmline (baseline: **0** over 12 days); ≥5 `mb-semantic-search`
  (baseline: **1**). Measure: `grep -c mb-graph-query ~/.claude/bash-audit.log`.
- **Freshness:** taskloom + swarmline `/mb context` shows `Code graph: ✅ fresh`
  (not `stale`, not `not built`) in normal use.
- **Delivery:** `/mb context` emits the code-graph line in 100% of runs where a
  graph exists (Stage 7 test proves the mechanism).
- **No regression:** all pre-existing `test_codegraph*`, `test_graph_query`,
  `test_semantic_search*`, `test_context_integration`, `test_session_start` suites
  stay green.

## Dependency graph
```
Stage 1 (taskloom build) ──┐
Stage 2 (swarmline refresh)│  (ops, parallel)
                           │
Stage 3 (meta + read_meta) ── Stage 4 (freshness + status)
                                   │
                     ┌─────────────┼───────────────┬───────────────┐
                     │             │               │               │
              Stage 5 (auto)  Stage 6 (git    Stage 7 (context   Stage 10 (nudge)
                               post-commit)    section)
Stage 8 (skill agents) ── Stage 9 (taskloom agents)  [needs Stage 1 + Stage 8]
```

## Parallelization
| Phase | Stages | Agents |
|-------|--------|--------|
| 1 | 1, 2, 3, 8 | ops-1 (S1), ops-2 (S2), mb-backend (S3), mb-developer (S8) |
| 2 | 4, 6 | mb-backend (S4, after S3), mb-developer (S6) |
| 3 | 5, 7, 10, 9 | mb-backend (S5), mb-developer (S7), mb-backend-2 (S10), ops-1 (S9) |

Stages 1, 2, 3, 8 have no code dependency on each other → start together. Stages 5,
7, 10 all depend on Stage 4 but touch disjoint files → fully parallel.

## Potential merge conflicts
- Stages 3 and 4 both touch `memory_bank_skill/codegraph_loader.py` (S3 adds
  `read_meta`, S4 imports it) → **serialize** (3 before 4); one owner.
- Stage 10 is the only editor of `settings/hooks.json`.
- Stages 5 / 7 / 10 / 6 edit disjoint files (`mb-session-start.sh` / `mb-context.sh`
  / `mb-graph-nudge.sh` + `settings/hooks.json` / `post-commit-codegraph.sh`) → no conflict.
- Stages 8 (skill agents) and 9 (taskloom agents) are in different repos → no conflict.

## Whole-feature verification
```bash
# Skill unit/integration suites
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_codegraph_loader.py tests/pytest/test_codegraph.py \
  tests/pytest/test_codegraph_freshness.py tests/pytest/test_graph_query.py \
  tests/pytest/test_semantic_search_churn.py -q
PATH="$PWD/.venv/bin:$PATH" /bin/bash "$(command -v bats)" \
  tests/bats/test_session_start.bats tests/bats/test_context_integration.bats \
  tests/bats/test_agent_graph_routing.bats tests/bats/test_mb_graph_nudge.bats \
  tests/bats/test_git_post_commit_codegraph.bats
# Static
shellcheck hooks/mb-session-start.sh scripts/mb-context.sh hooks/mb-graph-nudge.sh hooks/git/post-commit-codegraph.sh
python3 -m json.tool settings/hooks.json >/dev/null
PATH="$PWD/.venv/bin:$PATH" ruff check scripts/mb-codegraph.py scripts/mb-graph-query.py memory_bank_skill/codegraph_loader.py memory_bank_skill/codegraph_freshness.py
# Full gate
PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json
bash scripts/mb-rules-check.sh
# Live smoke (after Stages 1-2)
python3 scripts/mb-graph-query.py status --graph .memory-bank/codebase/graph.json --src-root . --json
```

## Feature DoD
- [ ] taskloom `graph.json` + `codebase/*.md` built; swarmline `graph.json` refreshed.
- [ ] Every new `graph.json` carries a `meta` row (`generated_at` + `commit` + counts);
      all readers ignore it (regression test green).
- [ ] Staleness checked against git HEAD via `graph_freshness` + `mb-graph-query status`.
- [ ] Background auto-rebuild exists, **off by default**, safe when on.
- [ ] Opt-in git post-commit template shipped + documented, NOT auto-installed.
- [ ] `/mb context` advertises the graph (freshness + counts + ready commands),
      never injects contents.
- [ ] 6 skill role agents + 6 taskloom agents carry the graph-first routing block.
- [ ] `mb-graph-nudge.sh` fires only when fresh, throttled, off-switchable, fail-safe,
      registered, coexists with rtk + block-dangerous.
- [ ] Net new tests: +5 pytest (S3) +7 pytest (S4) +5 bats (S5) +3 bats (S6) +3 bats
      (S7) +1 bats (S8) +8 bats (S10) = **12 pytest + 20 bats**; full suites green.
- [ ] Every new/edited `.sh` shellcheck-clean; every new/edited `.py` ruff-clean and
      ≤400 lines; no placeholders.

## Checklist (copy into checklist.md)
- ⬜ I-087 Stage 1: build taskloom graph.json + codebase/*.md (ops, cross-repo)
- ⬜ I-087 Stage 2: refresh swarmline graph.json incrementally (ops, cross-repo)
- ⬜ I-087 Stage 3: meta header row in writer + read_meta in loader (backward-compat, TDD)
- ⬜ I-087 Stage 4: freshness module + status subcommand (git-HEAD staleness, TDD)
- ⬜ I-087 Stage 5: opt-in background rebuild in SessionStart (MB_GRAPH_AUTO=off default, TDD)
- ⬜ I-087 Stage 6: opt-in git post-commit template, documented not auto-installed (TDD)
- ⬜ I-087 Stage 7: mb-context.sh code-graph section — freshness + counts + commands (TDD)
- ⬜ I-087 Stage 8: graph-first routing block in 6 skill role agents (doc test)
- ⬜ I-087 Stage 9: cross-repo rollout — 6 taskloom project agents (ops)
- ⬜ I-087 Stage 10: mb-graph-nudge.sh PreToolUse hook + registration (fresh-gated, throttled, TDD)

## Summary table
| # | Stage | Step | Complexity | Agent | Deps | Status |
|---|-------|------|-----------|-------|------|--------|
| 1 | taskloom build graph + docs | 1 (artifacts) | M | ops | — | ⬜ |
| 2 | swarmline refresh graph | 1 (artifacts) | S | ops | — | ⬜ |
| 3 | meta row + read_meta | 2 (freshness) | M | mb-backend | — | ⬜ |
| 4 | freshness module + status cmd | 2 (freshness) | M | mb-backend | 3 | ⬜ |
| 5 | SessionStart auto-rebuild (opt-in) | 2 (freshness) | M | mb-backend | 4 | ⬜ |
| 6 | git post-commit template (opt-in) | 2 (freshness) | S | mb-developer | 4 | ⬜ |
| 7 | mb-context.sh graph section | 3 (delivery) | M | mb-developer | 4 | ⬜ |
| 8 | skill role agents routing block | 3 (delivery) | S | mb-developer | 4 | ⬜ |
| 9 | taskloom agents routing block | 3 (delivery) | S | ops | 1, 8 | ⬜ |
| 10 | mb-graph-nudge PreToolUse hook | 4 (enforcement) | L | mb-backend | 4 | ⬜ |
