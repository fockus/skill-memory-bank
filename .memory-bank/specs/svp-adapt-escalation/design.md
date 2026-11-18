# Design: svp-adapt-escalation

> Slice S5. Revision 4 (2026-11-19, master-completion Stage 18a): rebased on ADaPT-lite (commit
> `190251c`, AGR-080, AGR-082). Contracts and Eval declarations only (D-05); code lands in the work phase.
> Revisions 1-3 (2026-07-17) designed a new `scripts/mb-work-adapt.sh` with `escalation:` config, an
> `MB_WORK_RESULT_JSON` envelope in nine agents and a `replan-gate`. The code took another route first, so
> this revision keeps the contracts that still hold (journal schemas, cascade, stub gate, backlog chain)
> and moves them onto the existing `scripts/mb_work_adapt.py` and the `adapt:` block. Hard dependency on
> `svp-parallel-engine` (S3) is dropped; `svp-sdd-core` (grammar) and `svp-roadmap-backlog-db`
> (`mb_lock_acquire`, `annotate`) are shipped and consumed as they are.

## Architecture

Pattern of the lite slice, kept: **the script decides and records, the orchestrator applies.**

1. **`scripts/mb_work_adapt.py`** (existing, 338 lines) — CLI dispatcher and the lite logic: config,
   `parse`, `split`, `sub-done`, `gate`, `carry`, `adapt-check`. This revision adds the remaining guards
   to `check()` and registers the new subcommands.
2. **Two sibling modules** (new, because the dispatcher is already past the 300-line SRP threshold):
   `scripts/mb_work_adapt_journal.py` (journal, cascade, summary) and `scripts/mb_work_adapt_stub.py`
   (stub gate, backlog sequencer). They hold no CLI of their own; `mb_work_adapt.py` imports them with the
   same `sys.path` pattern it uses for `mb_work_waves`.
3. **`adapt:` block** of `references/pipeline.default.yaml:286` — the single config home; validated by
   `validate()` in `mb_work_adapt.py` (the hook `mb-pipeline-validate.sh` already calls).
4. **`commands/work.md` step 5c1** — wiring only, every edit net-zero lines (zone cap 400).
5. **`agents/plan-verifier.md`** — calls `verify-stub`.

Write separation (D-23): the bank is written by the orchestrator through existing writers. The journal
is the only file this slice owns (`<bank>/tmp/escalations.jsonl`); `stub-backlog` only sequences the S4
writers `mb-idea.sh` and `mb-backlog-state.sh`, it never edits `backlog.md` itself.

## Interfaces

### C1. Delivered by ADaPT-lite (Task 1, waiver)

| Piece | Where | REQ |
|---|---|---|
| `complexity_escalation` block parser (YAML or JSON; invalid → exit 3) | `scripts/mb_work_adapt.py:155` | REQ-001 |
| `adapt:` config defaults and validator (`enabled`, `verify_fail_cycles: 3`, `item_token_budget`, `max_depth: 2`) | `mb_work_adapt.py:37/51/72`, `references/pipeline.default.yaml:286` | REQ-003 (verify) |
| Verify guard and token guard in `adapt-check` | `mb_work_adapt.py:247` | REQ-002 (part) |
| Four HITL choices; auto split by `roles.planner` | `references/adapt.md` § Fork, `commands/work.md` 5c1 | REQ-005 |
| In-run sub-items: `split`, `sub-done`, parent `gate` (exit 6), depth ≤ `max_depth` | `mb_work_adapt.py:195/227/239` | REQ-006 |

Dropped from revisions 1-3: the `MB_WORK_RESULT_JSON` envelope (the lite block already carries `reason`,
`estimate` and sub-items, and invalid input is handled by exit 3), the `replan-gate` with
`requirements_sha256`, and the decomposed-spec registry route (decomposition stays inside the run).

### C2. Remaining guards in `adapt-check` (Task 2)

```
mb_work_adapt.py adapt-check [ITEM] --state S [--pipeline P] [--item-tokens N]
                 [--declared "<Files csv>"] [--changed <path|->]
```

Output keeps the lite JSON (`enabled`, `item`, `verify_fails`, `trigger`, `reasons`) and adds
`degraded_guards`. Reasons are tokens; several in one call are **one** escalation:

| Token | Condition |
|---|---|
| `verify_fail_cycles` | `steps.count("verify_fail") >= adapt.verify_fail_cycles` (lite) |
| `item_token_budget` | `--item-tokens > adapt.item_token_budget` (lite, off while null) |
| `review_cycles` | `steps.count("review_cycle") >= adapt.review_cycles` (default 3) |
| `judge_cycles` | `steps.count("judge_cycle") >= adapt.judge_cycles` (default 2) |
| `eval_not_green` | `steps.count("eval_fail") >= state.max_cycles` |
| `scope_violation` | a `--changed` path matches no `--declared` entry |

Comparison is `count >= threshold`. For a sub-item the step names carry the `@<id>` suffix, as
`verify_fail@<id>` does today. The orchestrator records the steps (`mb-work-state.sh step eval_fail |
review_cycle | judge_cycle`) right after the phase event and before adapt-check, so the order is
`phase → step → adapt-check → pivot-check → on_max_cycles`; the existing cycle policy is unchanged.
`agent_signal` is added by the orchestrator when `parse` exits 0.

**Scope guard (minimal).** Declared entries are exact paths, `dir/**`, or paths with `*` inside one
segment (the restricted grammar of svp-sdd-core C1); the changed list comes from
`mb-work-diff.sh --name-only`. No declared list or no changed list → no trigger and
`degraded_guards: ["scope"]`, never a silent pass. The item's `Files:` are the only scope truth, so S3's
`mb-work-scope-check.sh` is not needed.

**Config.** `adapt: {enabled: true, verify_fail_cycles: 3, item_token_budget: null, max_depth: 2,
review_cycles: 3, judge_cycles: 2, cascade_stop: 3}`: each new key is an int ≥ 1, unknown keys stay
rejected, an absent key resolves to its default (legacy pipelines keep working). `verify_fail_cycles: 3`
is not changed (AGR-082).

### C3. Escalation journal (Task 3)

File `<bank>/tmp/escalations.jsonl`, not git-tracked (analytics, like `tmp/pivot-log.jsonl`). One JSON
object per line, exactly three closed schemas, keys in this order. Umbrella §Interfaces 3 and 5 style:
append-only, mandatory `ts`, explicit counter, last valid line wins.

```json
{"ts":"<ISO-8601-UTC>","event":"opened","escalation_id":"<id>","seq":1,"run_id":"<id>",
 "item_id":"<key>","cycle":0,"mode":"autonomous|hitl",
 "decision":"auto_split|stub_continue|fork_user|stop_run","triggers":["<token>"],
 "degraded_guards":["<token>"],"consecutive":1}
{"ts":"<ISO-8601-UTC>","event":"resolved","escalation_id":"<id>","seq":1,"run_id":"<id>",
 "item_id":"<key>","cycle":0,"mode":"autonomous|hitl",
 "resolution":"continue|simplify|decompose|skip|stub_continue","backlog_id":null,
 "resolved_by":"user|orchestrator"}
{"ts":"<ISO-8601-UTC>","event":"clean","run_id":"<id>","item_id":"<key>","cycle":0}
```

- `escalation_id` = `<run_id>:<item_id>:<cycle>:<seq>`, an opaque token compared byte-wise and never
  parsed back (`item_id` may contain `:`); `resolve` copies the components from the `opened` line.
  `seq` counts escalations of the same `(run_id, item_id, cycle)` from 1.
- `triggers` and `degraded_guards` are deduplicated in the order of the C2 table; `opened` without a
  trigger does not exist.
- `resolved_by` comes from the `decision` of the matching `opened`, not from the mode: `fork_user` →
  `user`, `auto_split` and `stub_continue` → `orchestrator`; `stop_run` has no `resolved` (resolve → exit 2).
- Allowed resolution per decision: `auto_split` → `decompose`; `stub_continue` → `stub_continue`;
  `fork_user` → `continue | simplify | decompose | skip`. `backlog_id` is **required** (`I-NNN`) for
  `stub_continue` and `skip`, forbidden otherwise; a violation is exit 2 with nothing appended.
- Idempotency and correction by the tuple `(resolution, backlog_id)`: identical → no-op, exit 0; any
  difference → a corrective `resolved` line (append-only), and every correction is listed in the summary.
- Validation on read: unknown `event`, missing or extra key, wrong type or value outside an enum →
  **exit 1, nothing appended**, stderr `code=invalid_log_line line=<n>`. Fail-loud (unlike the pivot log)
  because this file is durable guard state: `consecutive` and correlation come from it.
- `consecutive` = number of `opened` lines of the current `run_id` after its last `clean`, the current
  escalation included. `esc-clean` is called on a clean `done`.

**Subcommands** (registered in `mb_work_adapt.py`, logic in `mb_work_adapt_journal.py`):

```
esc-open    --bank B --run-id R --item-id I --cycle N --mode autonomous|hitl
            --triggers a,b [--split-refused] [--pipeline P]     → JSON {escalation_id, decision, triggers, consecutive}
esc-resolve --bank B --id ID --resolution <enum> [--backlog-id I-NNN]
esc-clean   --bank B --run-id R --item-id I
esc-summary --bank B --run-id R
```

`--run-id` is mandatory and non-empty (the orchestrator passes its local `RUN_ID`; `MB_WORK_RUN_ID` is
not exported). Exit codes: 0 ok · 1 invalid journal line · 2 usage or forbidden combination.

**Concurrency under `mb_lock_acquire`.** Several orchestrator sessions may share one working tree, so the
whole path read → validate (`seq`, `consecutive`) → one append runs under
`mb_lock_acquire "<bank>/tmp/.escalations.lock" 5 30` from `scripts/_lib.sh`. The lock records the
holder's shell PID and reclaims by owner liveness, so a Python writer holds it through a bash holder
subprocess that stays alive for the critical section: it sources `_lib.sh`, acquires, prints the token,
blocks on `read`, then runs `mb_lock_release` when Python closes its stdin (or dies). `esc-summary`
reads its snapshot under the same lock. No fifth lock implementation. The `PIPE_BUF` argument is not
used: it concerns pipes, not concurrent appends to a regular file.

### C4. Stub gate `verify-stub` (Task 4)

```
mb_work_adapt.py verify-stub --repo <root> --diff-file <path> --backlog <path>
```

`--diff-file` lists changed repo-relative paths (same surface as `mb-work-diff.sh --name-only`),
`--backlog` is `backlog.md`. Marker line, in a docstring or comment of the stub:
`MB-ADAPT-STUB backlog=I-NNN flag=<NAME> eval=<repo-relative-driver>`.

Structural checks per changed file: (1) `I-NNN` exists in the backlog, else `unknown_backlog_id`;
(2) the marker line matches `^[[:space:]]*("""|'''|///|//|/\*|\*|#|--|;)?[[:space:]]*MB-ADAPT-STUB `,
else `marker_not_in_docstring`; (3) `<NAME>` appears in the same file outside the marker line, else
`flag_token_unused`; (4) a bare `NotImplementedError`/`TODO`/`FIXME`/`...` stub without a marker →
`bare_placeholder`.

Behavioural proof, because 1-3 accept a default-on flag and an unused token: the `eval=` driver runs
twice from `--repo`, each in its own process group with a 120 s timeout (`subprocess.run(timeout=…)`
replaces the former bash `mb_adapt_bounded_run`: stock macOS has no `timeout`, Python does not need one):

| Run | Env | Required |
|---|---|---|
| 1 | `<NAME>` unset | exit 0 and stdout holds `MB-ADAPT-STUB-PATH: baseline` (flag default-off) |
| 2 | `<NAME>=1` | exit 0 and stdout holds `MB-ADAPT-STUB-PATH: staged` (flag switches the stub on) |

Violations: no `eval=` → `missing_stub_eval`; run 1 prints `staged` → `flag_default_on`; wrong or missing
token → `flag_does_not_gate_stub`; non-zero exit → `stub_eval_failed`; timeout → `stub_eval_timeout`.
A driver that is missing or not executable → exit 2 (a tooling defect, never a silent pass). stdout JSON
`{"stubs":[{"file","backlog_id","flag","eval"}],"violations":[{"file","line","reason"}]}`; exit 0 clean,
1 violations, 2 usage. Honest limit: default-off, real branching on the flag and the marker position are
machine-proven; **completeness of the docstring** (what it does, what it replaces, when) stays a
review judgment (`rules/RULES.md` § Staged stubs) and is not claimed as checked. The gate has no
"trust me" mode: no driver, no pass. `agents/plan-verifier.md` and the verify step treat exit 1 and
exit 2 as FAIL of the task and list the valid stubs with their backlog items for the summary.

### C5. Stub path and backlog chain (Task 5)

Order inside the autonomous branch: the backlog item exists **before** any code edit, because the marker
must reference an existing `I-NNN`.

```
stub-backlog --bank B --spec-topic <slug> --task-id <n> --reason <text> --flag <NAME> --capability <phrase>
```

stdout `I-NNN` and exit 0 when the item is `READY`; exit 1 halts the stub path before code; exit 2 usage.
The sequence runs the shipped S4-C3 contract and nothing else:

1. `id=$(bash scripts/mb-idea.sh "[ADAPT] <spec-topic>#<task-id>: <reason>" HIGH <bank>)` — born `NEW`,
   no `--force`: the similarity gate against `## Out of scope` refusing (`similar_out_of_scope`) is the
   right outcome, silently stubbing work already declared out of scope would be the worst case.
2. `bash scripts/mb-backlog-state.sh list --mb <bank>` — `mb-idea.sh` is idempotent by title, so a repeat
   escalation returns the existing item in its current state; a blind transition chain would fail on an
   invalid edge.
3. Shortest valid path to `READY` by single `transition` calls: `NEW → NEEDS-INFO → TRIAGED → READY`,
   from `NEEDS-INFO` and `TRIAGED` the remaining edges; `READY`/`IN-PROGRESS` are reused as they are;
   `DONE`/`WONTFIX` halt the path (terminal, and `WONTFIX` means out of scope). `PLANNED` is never set.
4. Before `READY`: `bash scripts/mb-backlog-state.sh annotate "$id" --brief "<BRIEF>" --mb <bank>`
   (S4-C3 revision 4, the single `**Brief:**` writer; its READY gate wants a behavioural brief with
   `should|shall|must|когда|если` and no file path or line number). Fixed template, only constrained
   values substituted, the raw `<reason>` never goes into the brief:
   `While <NAME> is off, the existing behavior shall remain unchanged; when <NAME> is on, <capability> shall be available.`
   with `<NAME>` = `[A-Z][A-Z0-9_]*` and `<capability>` = `[A-Za-z0-9 ,-]+`.
5. Any non-zero step stops the stub path before code and lands in the summary.

Stub = a full implementation of the interface plus a docstring, behind a **default-off** named flag
(`MB-ADAPT-STUB` marker, C4), plus a driver at `eval=<path>` that prints `baseline`/`staged`. A bare
`NotImplementedError`/`TODO` is forbidden without exception.

### C6. Fork semantics by mode (consumes C1-C5; prompt contract in `commands/work.md` 5c1)

| Mode | Trigger handling | `decision` |
|---|---|---|
| any, `consecutive >= adapt.cascade_stop` | stop before the next item, print the recommendation to revise the whole spec (D-35) | `stop_run` |
| HITL | AskUserQuestion: continue / simplify / decompose / skip | `fork_user` |
| autonomous | `roles.planner` splits the item in decompose mode, then `split` (lite) | `auto_split` |
| autonomous, `split` exited 6 (refused at `max_depth`) | stub path of C5 | `stub_continue` |

The checkbox flips only on a successful `done`. continue records `step adapt_override`, simplify leaves
the item pending and stops the run, skip records `step adapt_skip` with a backlog item and goes to the next
item, decompose is the lite split. After `continue` any later failed event opens a **new** fork. A
requirement change is the simplify path (the user edits scope, DoD or requirements before the next run).

**Boundary with S8.** `fake_red`, `foreign_failure` and `unobservable_requirement` are local immediate hard
stops of the S8 contract runner and are not routed through ADaPT; routing them would delay an immediate
refusal until `max_cycles` is exhausted.

## Seams

Declared outside any code fence so the validator counts it (the former revisions showed the form but
never declared it).

**Seams:**
- Python CLI surface of `scripts/mb_work_adapt.py` — subcommands called as a process from pytest, exit code plus JSON or JSONL on stdout/file; the journal and stub modules are reached only through it
**Seam rationale:** one seam; every new behavior (guards, journal, stub gate, backlog sequencer) is a subcommand of the CLI that ADaPT-lite already exposes and `tests/pytest/test_mb_work_adapt.py` already drives, so no new seam is introduced (D-17: existing over new). The prompt wiring in `commands/work.md` is checked by the file-size contract test and by running the subcommands it names, not by a seam of its own.

## Decisions

S5-A-01…04 and D-16/33/35 live in context. Fixed by this revision:

- **Rebase on the shipped code (AGR-080, AGR-082).** The lite slice is authoritative for what is
  delivered; the full spec only adds what AGR-082 left to it: stubs behind a flag, the journal and the
  cascade stop. Four tasks on existing files replace five tasks on a script that was never written.
- **Python, not a second bash script.** `mb_work_adapt.py` is already the ADaPT entry point called by
  `mb-work-state.sh`; a parallel `mb-work-adapt.sh` would be a second implementation (DRY).
- **Config stays in `adapt:`.** No `escalation:` section; `thresholds.verify` is the existing
  `verify_fail_cycles`, so the AGR-082 default 3 is untouched. Only review, judge and cascade keys are new.
- **Scope guard without S3.** A minimal match of the changed list against the item's `Files:` inside
  `mb_work_adapt.py`; S3 stays out of scope and may later feed the same `--changed` input.
- **Auto mode splits first, stubs last.** AGR-082 makes auto-mode decomposition the lite behavior, so
  REQ-004's stub is the fallback when the split is refused at `max_depth`, instead of a halt.
- **Fail-loud journal, closed schemas, lock by owner liveness** — unchanged reasoning from revision 3,
  now with the Python writer holding the lock through a bash holder.
- **Stub proven by behavior, not markup** — the two canonical driver tokens, default-off by construction.
- **No cross-slice requests remain.** X5-01 (`annotate`) is satisfied by S4-C3 revision 4; X5-02 (S8
  boundary) is accepted as written in C6.

## Eval declarations (red → green in the work phase)

All Evals are behavioural pytest runs on fixtures. Each carries an `output~:` anchor naming a test that is
written first (S2 REQ-054/055): a pytest run on a missing file exits non-zero without a `FAILED` line, so
the anchor cannot match "file absent".

- **T1** — delivered lite slice, green since 190251c, retro-red on 190251c~1 (module absent):
  **Eval:** `pytest tests/pytest/test_mb_work_adapt.py tests/pytest/test_adapt_lite_rules.py` — red: retro-red observed on 190251c~1, where scripts/mb_work_adapt.py does not exist so every test errors on import, green since 190251c; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt\.py::test_escalation_block_parses_with_and_without_pyyaml
- **T2** — scope, review, judge and eval-not-green guards; new config keys; degraded scope guard:
  **Eval:** `pytest tests/pytest/test_mb_work_adapt.py` — red: adapt-check knows only the verify and token guards, so a changed path outside Files and a third review cycle are not triggers; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt\.py::test_adapt_check_scope_violation_triggers
- **T3** — journal schemas, resolve matrix, cascade stop, concurrency under the lock, summary:
  **Eval:** `pytest tests/pytest/test_mb_work_adapt_journal.py` — red: the esc-* subcommands and the journal do not exist, no opened record is written; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt_journal\.py::test_esc_open_writes_opened_record
- **T4** — structural checks and the two-run behavioural proof of the stub gate:
  **Eval:** `pytest tests/pytest/test_mb_work_adapt_stub.py` — red: the verify-stub subcommand does not exist, so a default-on flag passes verification; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt_stub\.py::test_verify_stub_default_on_flag_fails
- **T5** — backlog chain to READY before code, reuse, halts:
  **Eval:** `pytest tests/pytest/test_mb_work_adapt_backlog.py` — red: the stub-backlog subcommand does not exist and no backlog item reaches READY before the stub; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt_backlog\.py::test_stub_backlog_reaches_ready_before_code

## Risks & mitigation

| Risk | P | I | Mitigation |
|---|---|---|---|
| False guard triggers choke progress | M | M | thresholds in `adapt:` plus the journal for calibration; `continue` is always offered in HITL |
| Conflict with pivot logic | M | M | order `phase → step → adapt-check → pivot-check → on_max_cycles`; shared counters are read, never mutated |
| Orchestrator forgets to record a step counter, so a guard stays silent | M | H | work.md wiring is part of each task DoD; a missing counter reads as 0 and an unreadable state as `degraded_guards`, never as a pass |
| Python writer outlives its bash lock holder | L | H | holder blocks on stdin and releases on EOF or death of the writer; liveness reclaim of `mb_lock_acquire` covers a crash |
| `commands/work.md` hits the 400-line cap | H | M | each edit is net-zero; the size contract test is in every task |
| Driver `eval=` degenerates into a formality | M | M | two runs must print different canonical tokens, unreachable without real branching; seam completeness is review's call |

## Open questions

- Owner confirmation of the amended REQ-004, REQ-005 and REQ-006 wording (stub as fallback when the split
  is refused; `decompose` in place of `replan`; no child-spec registry), see the rebase map in requirements.md.
- Threshold calibration after the first governed runs (journal data).
