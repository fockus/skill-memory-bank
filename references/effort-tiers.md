# Effort tiers — size the task before you start

Match plan, tests, docs and checks to the size of the task. A one-sentence diff does not need a plan;
a payment flow does need a review. This file is the single source of the five tiers (AGR-067). The
tier → `/mb work` preset mapping lives in `pipeline.yaml` `effort_tiers:`
(default: `references/pipeline.default.yaml`).

## How to pick a tier

1. Before the first edit, estimate the tier from the signals below and say it in one line
   (`Tier: small — one new client module, one test`).
2. **An explicit user request beats the tier estimate.** `/mb work`, "make a plan", "no tests",
   "write docs for it" — do what was asked, even if the tier says otherwise.
3. **When unsure between neighbours, pick the lower one** and raise it as soon as a risk shows up
   (unclear requirements, a second module pulled in, data or money touched).
4. A task that touches security, money, user data, reliability or numerical accuracy is `extra`,
   whatever its size.
5. Plan coarse; decompose as needed — ADaPT: the implementer takes an item whole and only a stuck
   item gets split (`references/adapt.md`).

## Tiers

### trivial

- **Signals:** a typo, a config value, a rename, a version bump; the diff fits in one sentence.
- **Plan:** none. **Tests:** no new tests. **Docs:** none.
- **Verification:** one command — the test or lint that covers the touched line.
- **Workflow:** none — edit directly, no `/mb work`.

### small

- **Signals:** one feature in 1–3 files with a clear contract, e.g. integrating an external API client.
- **Plan:** none, no `/mb work`. **Tests:** one test per stated behavior, no mock-tests of glue,
  config or external SDK calls. **Docs:** no new documents; README/CHANGELOG get 1–2 lines if relevant.
- **Verification:** targeted tests and lint of the changed files.
- **Workflow:** inline; when the user does ask for `/mb work`, preset `simple` (implementer self-checks).

### standard

- **Signals:** a change across several modules, a new endpoint with storage, a refactor with callers.
- **Plan:** `/mb plan` with SMART DoD for the plan (per stage only at a real boundary). **Tests:** TDD on the new logic, behavior not lines.
  **Docs:** update the touched docs; new documents only on request.
- **Verification:** targeted checks while working; the full suite in `/mb verify` and before commit.
- **Workflow:** `/mb work`, preset `medium` (implementer + one verifier pass at the end of the plan).

### large

- **Signals:** a new subsystem, unclear or conflicting requirements, several plausible designs.
- **Plan:** `/mb discuss` → `/mb sdd` → tasks; the spec is the source of truth. **Tests:** TDD,
  one test per spec scenario. **Docs:** what the spec requires.
- **Verification:** per the spec; the full suite in `/mb verify` and before commit.
- **Workflow:** `/mb work` on the spec, preset `complex` (adds one reviewer and a bounded fix loop).

### extra

- **Signals:** security, money, user data, reliability or accuracy at stake, at any size.
- **Plan:** a plan or spec. **Tests:** full rules — TDD, contract tests, coverage on for the task.
  **Docs:** what the change needs to be operated safely.
- **Verification:** the full suite and every configured gate.
- **Workflow:** `/mb work`, preset `governed` (verifier, review ensemble, independent judge, fix loop).

## Parallel work (AGR-073)

Independent tasks — no shared files and no ordering dependency — go out as one wave of parallel
subagents. Every shared file has exactly one owner; the others read it, they do not edit it. This
makes the work faster, not cheaper: each subagent loads its own context. The user can decline and
keep it sequential.
