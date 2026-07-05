# Golden calibration suite (reviewer-2.0, GAP-7)

`tests/calibration/` is the golden calibration suite for the `mb-review.sh` /
`mb-reviewer` review layer (design: `.memory-bank/specs/reviewer-2.0/design.md`
§6 "Golden calibration suite", REQ-104/REQ-105). It answers one question:
**does the reviewer still produce the verdicts we expect on a fixed set of
known-bad diffs?** — and it does so with a fully offline, deterministic smoke
path plus an (opt-in, host-driven) live-reviewer mode.

## Purpose

Two independent things can silently drift over time and neither is caught by
the rest of the test suite:

1. **Editing `references/rubric-examples/*.md`** — tightening a message,
   renaming an `example_id`, or moving a category can change which examples
   the layered loader (`scripts/mb-review-examples.sh`) selects and how the
   reviewer attributes findings back to them.
2. **Upgrading the model behind the reviewer** (`mb-reviewer` / `codex-cli` /
   whichever `pipeline.yaml` names) — a new model version may judge the same
   diff differently: a different verdict, more/fewer issues, or looser
   category coverage.

The calibration suite is the regression harness for both: a fixed pool of
representative diffs with hand-authored *expected* verdicts, checked against
either the deterministic payload shape (offline) or an actual verdict (live).

## Directory layout

```
tests/calibration/
├── README.md            ← this file
├── run.sh               ← the runner
├── cases/
│   ├── PY-001-srp-violation/
│   │   ├── case.json
│   │   ├── diff.patch
│   │   ├── files-touched.txt
│   │   ├── prior-tests.json
│   │   └── verdict.sample.json   (optional — offline self-test only)
│   ├── PY-002-missing-tests/     (the red-tests case)
│   ├── GO-001-error-wrap/
│   ├── TS-001-any-leak/
│   └── BACK-001-idor/
└── results/              ← gitignored, regenerated every run
    └── <UTC-timestamp>_run.json
```

At S1 close there are 5 cases, one per reviewer category
(`code_rules` x2, `code_rules`, `code_rules`, `security` — see the table
below); the backlog target for later sprints is 15+.

| case_id | stack | category | tests | expected verdict |
|---|---|---|---|---|
| `PY-001-srp-violation` | python | code_rules | green | `CHANGES_REQUESTED` |
| `PY-002-missing-tests` | python | tests | **red** (`tests_pass:false`) | `CHANGES_REQUESTED` |
| `GO-001-error-wrap` | go | code_rules | green | `CHANGES_REQUESTED` |
| `TS-001-any-leak` | typescript | code_rules | green | `CHANGES_REQUESTED` |
| `BACK-001-idor` | backend | security | green | `CHANGES_REQUESTED` |

`PY-002-missing-tests` is the one red-tests case in the pool: its
`prior-tests.json` has `tests_pass:false`, so its assembled payload MUST show
the `## Auto-generated findings (MUST INCLUDE)` section (design.md §5). The
other four are green and MUST NOT show it — the runner asserts both branches.

## `case.json` schema

```json
{
  "case_id": "PY-001-srp-violation",
  "description": "UserService aggregates 3 distinct concerns",
  "stack": "python",
  "expected": {
    "verdict": "CHANGES_REQUESTED",
    "counts": {
      "blocker_min": 1, "blocker_max": 2,
      "major_max": 3,
      "minor_max": 5
    },
    "must_have_categories": ["code_rules"],
    "must_not_have_categories": [],
    "expected_example_refs": ["PY-SRP-001"]
  }
}
```

Each case directory also carries:

- **`diff.patch`** — a small, real unified diff representative of the
  category being tested (not necessarily `git apply`-able; it is rendered as
  literal text inside the payload's `## Diff` section, never applied to a
  working tree).
- **`files-touched.txt`** — the touched-file list for the case (documents
  scope; `scripts/mb-review.sh --input` currently reads the diff/prior-tests
  verbatim and does not re-derive touched files from this list).
- **`prior-tests.json`** — the test-cache evidence document the case injects
  verbatim (design.md §5's schema): `tests_pass`, `counts`, `failures`, etc.
- **`verdict.sample.json`** *(optional)* — see "Default mode" below.

## Match metric

The full match metric (design.md §6), implemented in `run.sh`'s
`match_metric()` and exercised whenever an actual verdict is available:

```
PASS if all hold:
  actual.verdict == expected.verdict
  expected.blocker_min <= actual.counts.blocker <= expected.blocker_max
  actual.counts.major <= expected.major_max
  actual.counts.minor <= expected.minor_max
  set(expected.must_have_categories) subset-of set(i.category for i in actual.issues)
  set(expected.must_not_have_categories) disjoint-from set(i.category for i in actual.issues)

WARN (does not fail) if PASS holds but:
  set(expected.expected_example_refs) not subset-of
    set(i.referenced_example_id for i in actual.issues)
  -> calibration patterns are not being attributed correctly

FAIL otherwise.
```

## Running it

```
bash tests/calibration/run.sh                    # all cases, default mode
bash tests/calibration/run.sh --emit-payload      # payload-shape smoke test (offline)
bash tests/calibration/run.sh --stack=python      # filter by case.json:stack
bash tests/calibration/run.sh --case=PY-001       # filter by case id prefix
bash tests/calibration/run.sh --help
```

### `--emit-payload` — the offline smoke path (load-bearing, CI-safe)

For each selected case, this invokes:

```
bash scripts/mb-review.sh --emit-payload --input tests/calibration/cases/<id> --mb <tmp-bank>
```

i.e. the *exact* production payload-assembly code path (`mb-review.sh`'s
`--input` mode) that the real `/mb work` review step uses, but reading
`diff.patch` / `prior-tests.json` from the case directory instead of git /
`.memory-bank/tmp/`. **No reviewer is dispatched, no LLM is called, no
network is touched.** Each temp bank carries a `rules-profile.json` pinning
the case's own `stack`, so the layered examples loader
(`scripts/mb-review-examples.sh`) resolves that stack's baseline rather than
degrading to `common`-only.

The runner then shape-checks the assembled payload:

- the 4 unconditional sections (`## Plan context`, `## Diff`,
  `## Calibration examples ...`, `## Prior evidence ...`) are present, in
  the fixed design.md §7 order;
- the conditional `## Auto-generated findings (MUST INCLUDE)` section is
  present **iff** the case's `prior-tests.json` has `tests_pass:false`;
- the `## Calibration examples` section actually resolved real examples
  (not the loader's empty/degraded placeholder), and — WARN, not FAIL, if
  missing — that the case's `expected_example_refs` show up among the
  rendered example headers.

This is the path `tests/bats/test_calibration_suite.bats` exercises; it is
pure and deterministic (no clock/network/LLM dependency), so two consecutive
runs produce byte-identical stdout.

### Default mode — the live-reviewer path (host-driven, not CI-blocking)

Per design.md §6, default mode is meant to dispatch an actual reviewer with
the assembled payload and apply the full match metric to its verdict. This
repository's `run.sh` **never fakes an LLM call** to do that. Concretely:

- If a case ships an optional `verdict.sample.json`, default mode treats it
  as a **labelled, offline self-test fixture** (never a live verdict — see
  the `_note` field inside each sample) and runs the real match-metric logic
  against it end to end. This is how the metric itself gets exercised
  without a reviewer: two shipped samples demonstrate the PASS branch
  (`PY-001-srp-violation`) and the WARN branch
  (`GO-001-error-wrap`, whose sample deliberately omits
  `referenced_example_id`).
- Otherwise the case is reported `SKIP`, with the reason "reviewer dispatch
  is host-driven; run under the scheduled workflow" — honest about the fact
  that no LLM call happened, rather than fabricating a verdict.

`SKIP` never fails the run (exit 0 if nothing else is FAIL/WARN). Wiring an
actual reviewer dispatch into `run.sh` (so default mode produces real PASS/
WARN/FAIL instead of SKIP) is the job of the scheduled CI workflow described
below, which has host access to the reviewer model.

## What this protects

- **Editing `references/rubric-examples/*.md`** — run
  `bash tests/calibration/run.sh --emit-payload` locally before committing a
  rubric-examples change. If a case's `## Calibration examples` section
  stops resolving the stack you touched, or an `expected_example_refs` id
  disappears from the rendered pool, this is your signal *before* it reaches
  a live reviewer.
- **Upgrading the model behind `mb-reviewer` / `codex-cli`** — re-run the
  suite (live mode, via the scheduled workflow below) after a model bump,
  observe which cases shift from PASS to WARN/FAIL, and decide whether to
  update the examples, the thresholds in `case.json`, or accept the drift.

## Non-blocking scheduled workflow (documented, NOT added by this task)

Design.md §6 "CI integration" specifies a weekly, non-blocking scheduled
workflow that runs the suite in live-reviewer mode. **This task intentionally
does NOT add a `.github/workflows/*.yml` file** — CI workflow files are
protected and adding one requires explicit maintainer approval. The workflow
below is the exact, ready-to-add content a maintainer can copy into
`.github/workflows/calibration.yml`:

```yaml
name: Calibration suite (non-blocking)

on:
  workflow_dispatch: {}
  schedule:
    # Weekly, Monday 06:00 UTC.
    - cron: '0 6 * * 1'

jobs:
  calibrate:
    runs-on: ubuntu-latest
    # Non-blocking by design: LLM verdict variance makes this suite
    # unsuitable as a PR-merge gate (design.md §6, §10 "Risks"). This job
    # never affects branch protection / required checks.
    continue-on-error: true
    env:
      # Token budget for the live-reviewer dispatch this job wires in
      # (host-driven; see tests/calibration/README.md "Default mode").
      MB_CALIBRATION_TOKEN_BUDGET: '200000'
    steps:
      - uses: actions/checkout@v4
      - name: Run golden calibration suite
        run: bash tests/calibration/run.sh
      - name: Upload results artifact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: calibration-results
          path: tests/calibration/results/*.json
          if-no-files-found: warn
```

A maintainer adding this file separately still needs to wire an actual
reviewer dispatch into `run.sh`'s default-mode path (today it only self-tests
the match metric against optional `verdict.sample.json` fixtures — see
"Default mode" above) before the job produces real PASS/WARN/FAIL instead of
`SKIP` rows.

## Adding a new case

1. Pick the next free id in the relevant stack series (e.g. `PY-003-...`).
2. Write a small, real `diff.patch` representative of one specific rubric
   category (mirror the "Bad" snippet from the matching
   `references/rubric-examples/<stack>.md` block if one exists).
3. Write `files-touched.txt` (the touched-file list) and `prior-tests.json`
   (green, unless this is deliberately a red-tests case).
4. Write `case.json` per the schema above — `expected.expected_example_refs`
   should name the `example_id` you expect the reviewer to cite.
5. Run `bash tests/calibration/run.sh --emit-payload --case=<new-id>` and
   confirm PASS before committing.
