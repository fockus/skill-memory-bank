# The development flow

<p class="mb-lede" markdown>One path, eight stations, each leaving a file behind. How many stations a
task visits depends on its size: a typo does not get a ceremony, a payment flow does not get a
shortcut.</p>

| | |
|---|---|
| **Use it for** | Deciding which commands a task needs, in which order |
| **Entry point** | Plain language ("plan this", "implement the spec") or the commands below |
| **Source of truth** | [`references/effort-tiers.md`](../references/effort-tiers.md), `pipeline.yaml` `effort_tiers:` |
| **Status in 5.4.1** | Stable. Task tiers and `/mb brief` are new in 5.4 |

## The eight stations

<div class="mb-steps" markdown>

1. **Brief** — `/mb brief <topic>`

    A raw request plus attached documents becomes a one-page brief.
    Writes `briefs/<topic>/` (the brief and a copy of every input).

2. **Discuss** — `/mb discuss <topic>`

    A five-phase interview writes EARS-validated requirements.
    Writes `context/<topic>.md`.

3. **Spec** — `/mb sdd <topic>`

    Requirements, design and executable tasks: one spec triple.
    Writes `specs/<topic>/{requirements,design,tasks}.md`.

4. **Plan** — `/mb plan <type> <topic>`

    Stages with a SMART Definition of Done; QA is declared up front.
    Writes `plans/<date>_<type>_<topic>.md`.

5. **Work** — `/mb work [target]`

    Role agents implement each item under TDD; gates join by preset.
    Writes code, tests and ticked checkboxes.

6. **QA** — `/mb qa run`

    A runner agent walks acceptance scenarios against the live product.
    Writes `qa/runs/<run-id>/report.md` and `qa/bugs.md`.

7. **Verify** — `/mb verify`

    The plan-verifier audits the real diff against every DoD line.
    Returns a verdict with evidence.

8. **Done** — `/mb done`

    Progress, status and a session note are saved.
    Writes `progress.md`, `status.md`, `notes/`.

</div>

## Which stations a task visits

Size the task before the first edit and say it in one line (`Tier: small — one client module, one
test`). When unsure between two neighbours, pick the lower one and raise it as soon as a risk shows
up.

| Tier | Signals | Stations | `/mb work` preset |
|---|---|---|---|
| **trivial** | A typo, a config value, a rename; the diff fits in one sentence | Edit, then the one check that covers the line | none |
| **small** | One feature in 1–3 files with a clear contract | Work (inline) → Done | `simple` if you ask for `/mb work` |
| **standard** | Several modules, an endpoint with storage, a refactor with callers | Plan → Work → QA → Verify → Done | `medium` (default) |
| **large** | A new subsystem; unclear or conflicting requirements | Brief → Discuss → Spec → Work → QA → Verify → Done | `complex` |
| **extra** | Security, money, user data, reliability or accuracy, at any size | Every station, every configured gate | `governed` |

Three rules override the table:

- **An explicit request beats the estimate.** "Make a plan", "no tests", "review it" — do what was
  asked, whatever the tier says.
- **Security, money, user data, reliability and numerical accuracy are `extra`**, however small
  the diff.
- **Plan coarse, split only when stuck.** The implementer takes an item whole; only an item that
  stalls gets decomposed.

## What each tier owes

| Tier | Plan | Tests | Verification | QA |
|---|---|---|---|---|
| trivial | none | no new tests | one command | none |
| small | none | one test per stated behavior | targeted tests and lint of the changed files | off |
| standard | `/mb plan` with a SMART DoD | TDD on the new logic | targeted while working; full suite in `/mb verify` | on when `qa/README.md` exists |
| large | `/mb discuss` → `/mb sdd` | TDD, one test per spec scenario | per the spec; full suite before commit | on when `qa/README.md` exists |
| extra | a plan or a spec | TDD, contract tests, coverage on | full suite and every gate | on when `qa/README.md` exists |

## Two worked routes

=== "Standard — a plan"

    ```text
    /mb plan feature avatar-upload      # stages, DoD, qa: on|off
    /mb work avatar-upload              # implement → one verifier pass at plan end
    /mb verify                          # audit the diff against the DoD
    /mb done                            # save the session
    ```

=== "Large — a spec"

    ```text
    /mb brief billing --input PRD.md    # optional: raw request → one-page brief
    /mb discuss billing                 # interview → context/billing.md
    /mb sdd billing                     # specs/billing/{requirements,design,tasks}.md
    /mb work billing                    # runs tasks.md items in order, preset complex
    /mb verify
    /mb done
    ```

Use one kebab-case slug for the whole feature (`billing-overhaul`, not `"billing overhaul"`): every
later command resolves the same `context/` and `specs/` paths from it.

## What sits inside station 5

One item of `/mb work` is itself a short chain. The preset decides how long it is.

| Preset | implement | verify | review | judge | fix loop |
|---|---|---|---|---|---|
| `simple` | self-check | — | — | — | — |
| `medium` | role agent | once per plan | — | — | — |
| `complex` | role agent | once per plan | 1 reviewer | — | bounded |
| `governed` | role agent | once per plan | 5-lens ensemble | independent | fix or backlog |

Details, flags and cost: [/mb work](mb-work.md) and [Routes, firewall and cost](routes-and-firewall.md).

## Limits in 5.4.1

- `/mb brief` has no overwrite flag: re-formalize under a new topic, or delete `briefs/<topic>/`
  by hand first.
- The tier is an estimate made by the agent. It is stated out loud so you can correct it; it is
  not enforced by a script.
- QA is only declared `on` when the bank has a QA target (`qa/README.md`).

!!! agent "For agents"
    1. Before the first edit, estimate the tier and state it in one line.
    2. Route by the table above. A task that refers to an existing plan or spec always runs through
       `/mb work` — never implement planned work inline unless the user says to skip it.
    3. `specs/<topic>/tasks.md` blocks marked `<!-- mb-task:N -->` and plan blocks marked
       `<!-- mb-stage:N -->` are the executable source of truth.
    4. `/mb verify` is required before `/mb done` whenever the work followed a plan.
    5. Never claim completion without the command output that proves it.

## Related

- [/mb work — the execution engine](mb-work.md)
- [/mb team — parallel tracks](mb-team.md) · [/mb drive — the goal loop](mb-drive.md) · [/mb qa — acceptance QA](mb-qa.md)
- [Spec-driven development](concepts/sdd.md)
- [Agent operating guide](agent-guide.md)
