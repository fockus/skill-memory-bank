# Reviewer 2.0 — calibrated, tests-aware review

Shipped in **5.3.0**. Reviewer 2.0 replaces an ad-hoc "read the diff and judge" reviewer prompt
with a deterministic payload-assembly pipeline: the reviewer agent never reconstructs context by
reading files itself — it receives one pre-assembled markdown document and judges only that.

## The problem it solves

Before Reviewer 2.0, a reviewer subagent had to open the plan, run its own `git diff`, guess what
tests exist, and decide from scratch what a "good enough" review looks like for this stack. That
meant every review cycle reconstructed context slightly differently, calibration was inconsistent
across languages, and a reviewer could approve a diff whose tests were actually failing simply
because it never checked.

Reviewer 2.0 fixes all three: one deterministic payload, layered calibration examples, and a
test-evidence cache the payload assembler consults before the reviewer ever runs.

## `scripts/mb-review.sh` — the payload orchestrator

`mb-review.sh --emit-payload` is the single entry point that assembles the markdown document a
reviewer judges. It owns diff discovery, calibration-example selection, and touched-file
test-cache resolution, and never dispatches an LLM itself — it is pure assembly.

```bash
bash scripts/mb-review.sh --emit-payload --plan <plan path> --item <N> --run-id "$RUN_ID" --mb <bank>
```

The assembled payload has five fixed sections, in order:

1. `## Plan context` — plan/spec path, the active stage heading, and the item body (the DoD
   reference the reviewer scores against).
2. `## Diff` — the unified diff of touched files against this stage's baseline.
3. `## Calibration examples` — layered few-shot reference patterns (see below); never part of the
   current diff, referenced only via `referenced_example_id`.
4. `## Prior evidence (from mb-test-runner)` — this item's touched-file test status: `tests_pass`,
   pass/fail/skip counts, failure detail.
5. `## Auto-generated findings (MUST INCLUDE)` — present **only** when `tests_pass == false`. Every
   entry here must appear verbatim (severity and category preserved) as the first issue(s) in the
   reviewer's output JSON.

`mb-review.sh` also supports `--input <case-dir>` so the same production code path can run offline
against a fixture — this is what the golden calibration suite (below) exercises without touching a
real diff or dispatching a live model.

## Test-evidence cache — `scripts/mb-review-cache.sh`

The touched-file test-evidence cache lives at `.memory-bank/tmp/last-tests.json`. It is TTL-bounded
and keyed on a SHA of the touched-files set: a HIT means the payload assembler can embed a recent,
known-good (or known-bad) test result without re-running the suite; a MISS means no fresh evidence
exists yet for these files. `--refresh-tests` is the manual escape hatch that forces a MISS,
useful when you know the cache is stale but the TTL hasn't expired.

This cache is what makes the `## Auto-generated findings` section possible: if the cache reports
`tests_pass: false` for the files this item touched, the payload assembler injects a `tests`
blocker into the prompt before the reviewer even starts — the reviewer cannot silently skip past a
red test suite because it never saw the failure.

## Layered calibration examples

`scripts/mb-review-examples.sh` resolves few-shot rubric examples from
`references/rubric-examples/{common,python,go,typescript,frontend,mobile,backend}.md`. A project
may add its own override set at `.memory-bank/rubric-examples/` using the same
`example_id`/`stack`/`category`/`severity` frontmatter and `### Bad` / `### Expected verdict
fragment` block format; on an `example_id` collision the project override wins. Every bundled
stack file ships at least 3 examples in total, and across the full bundled pool every rubric
category (`logic`, `code_rules`, `security`, `scalability`, `tests`) has at least 3 examples, so a
reviewer judging, say, a Go diff sees Go-shaped bad examples instead of generic prose.

Examples are reference patterns only — the reviewer's job is to reference a matching
`example_id` in its own findings via `referenced_example_id`, never to parrot the example's
snippet verbatim into a new finding.

## `--require-tests-blocker` — the safety net

`mb-work-review-parse.sh --require-tests-blocker` is appended to the parse step whenever this
item's touched-file tests were failing. If the reviewer's normalized output still lacks a
`category: "tests"` / `severity: "blocker"` issue — because the reviewer dropped it, downgraded
it, or the review wave itself was skipped — the parser prepends the missing finding, forces the
verdict to `CHANGES_REQUESTED`, and logs a warning. This is idempotent (an existing tests/blocker
finding is left untouched, never duplicated) and strictly opt-in: when tests were passing, parsing
stays byte-identical to before. A red test suite can never silently pass the severity gate through
an omitted, softened, or skipped review.

## Golden calibration suite — `tests/calibration/`

The calibration suite is what keeps Reviewer 2.0 from drifting: a fixed set of fixture diffs with
known-good expected verdicts, run offline through `mb-review.sh --input <case-dir>` without a live
model call in the deterministic-assembly path. It asserts the payload assembler produces the
right sections in the right order, the right auto-generated findings when tests are red, and the
right calibration examples for each stack — catching a regression in the assembly logic before it
ever reaches a real review cycle.

## Review modes: implementation vs. contract

`agents/mb-reviewer.md` documents two rubric modes, switched by a `review_mode` field in the
payload preamble:

- **`implementation`** (default, backward compatible) — the five categories above: `logic`,
  `code_rules`, `security`, `scalability`, `tests`.
- **`contract`** — used only by the sprint-contract phase of `/mb work` (see [/mb work](mb-work.md)
  § *Sprint contracts*), reviewing a contract document instead of a code diff, before any
  implementation exists. Its four categories are `scope`, `dod`, `test_plan`, `out_of_scope` — a
  silent/empty `out_of_scope` section is always a blocker. The `## Auto-generated findings`
  pre-injection does not apply here, since there are no tests yet.

## Output contract

Regardless of mode, the reviewer emits strict JSON on stdout only:

```json
{
  "verdict": "APPROVED" | "CHANGES_REQUESTED",
  "counts": { "blocker": 0, "major": 0, "minor": 0 },
  "issues": [
    {
      "severity": "blocker" | "major" | "minor",
      "category": "logic" | "code_rules" | "security" | "scalability" | "tests",
      "file": "relative/path/to/file.py",
      "line": 42,
      "message": "concrete violation description",
      "fix": "concrete one-line fix proposal",
      "referenced_example_id": "PY-SRP-001"
    }
  ],
  "strengths": ["specific, file:line-grounded — never generic praise"]
}
```

`verdict == "APPROVED"` requires an empty `issues` list and all counts at zero — any finding at
all, even a single gate-passing minor, forces `CHANGES_REQUESTED`. Whether that cycle *passes* is
a separate decision made downstream by `mb-work-severity-gate.sh` against the configured
`severity_gate` thresholds; the reviewer's only job is honest findings, never the pass/fail call.

## Related

- [/mb work](mb-work.md) — the loop that dispatches Reviewer 2.0 at its `review` step.
- [pipeline.yaml reference](pipeline-yaml.md) — `review_rubric`, `severity_gate`, and
  `review_ensemble` configuration.
- `agents/mb-reviewer.md` — the full reviewer prompt contract (categories, severity tree, output
  schema, fix-cycle behavior, hard guardrails).
