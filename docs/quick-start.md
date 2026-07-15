# 5-minute quick start

This is the condensed path from "nothing installed" to "agent remembers my project."
For a slower, worked example with a real feature, see
[Your First Feature](first-feature.md). For every install flavor and cross-agent
adapter detail, see [Install](install.md).

## 1. Install

Pick whichever installer matches your platform (see [Install](install.md) for the
full comparison):

```bash
pipx install memory-bank-skill && memory-bank install
```

`memory-bank install` copies the rules, commands, agent prompts, and hooks for your
selected clients (`claude-code`, `cursor`, `windsurf`, `cline`, `kilo`, `opencode`,
`pi`, `codex`) into their respective global config directories.

## 2. Open your project and initialize the bank

Inside your AI agent (Claude Code, Cursor, OpenCode, …), in the project directory, run:

```
/mb init
```

This creates `.memory-bank/` with `status.md`, `checklist.md`, `roadmap.md`,
`progress.md`, `plans/`, `notes/`, and the rest of the layout (see
[Memory Bank Layout](concepts/memory-bank-layout.md)), detects your stack, and
generates a `CLAUDE.md`/`AGENTS.md` pointing the agent at the bank. You should see
`[MEMORY BANK: INITIALIZED]`.

## 3. Every session starts with `/mb start`

```
/mb start
```

The agent loads `status.md`, `checklist.md`, `roadmap.md`, `research.md` (and any
active plan) — it knows exactly what you were working on and what comes next.

## 4. As you work: the checklist updates immediately

The agent flips `checklist.md` items `⬜ → ✅` as soon as a task is genuinely
finished — not in a batch at the end of the session.

## 5. Every session ends with `/mb done`

```
/mb done
```

This appends a session entry to `progress.md` (append-only — old entries are
never rewritten), updates `status.md` if the facts on the ground changed, and
writes a knowledge note under `notes/` if something worth remembering was learned.

That's it. Rinse and repeat.

## The core workflow: build a feature

`init` / `start` / `done` are the session bookends. The real feature work runs
through a **plan or spec → `work` → `verify` → `done`** loop. Two entry points:

**Plan-based** — for a well-understood change:

```
/mb plan feature "user avatar upload"   # staged plan with SMART DoD + TDD notes
/mb work                                # executes the plan stage by stage (TDD → verify per stage)
/mb verify                              # audits the diff against every DoD item — REQUIRED before done
/mb done
```

**Spec-driven (SDD)** — for a larger or fuzzier feature, add an interview + spec first:

```
/mb discuss billing-overhaul            # 5-phase interview → EARS-validated context/billing-overhaul.md
/mb sdd billing-overhaul                # specs/billing-overhaul/{requirements,design,tasks}.md
/mb work billing-overhaul               # executes the tasks.md items (<!-- mb-task:N -->) in order
/mb verify
/mb done
```

Use one kebab-case slug for the whole feature (`billing-overhaul`, not
`"billing overhaul"`): `/mb discuss` uses the topic verbatim as the filename,
so keeping it already-slugged makes every later command resolve to the same
`context/` and `specs/` paths.

`/mb work` runs **implement (TDD) → verify → done** by default — review is off,
so it stays fast and cheap. `/mb verify` is **mandatory before `/mb done`**
whenever the work followed a plan: it re-reads the plan and checks every DoD item
against the real code. See [/mb work](mb-work.md) for the full composable engine.

## Configuring the pipeline

`/mb work` is driven by a declarative **`pipeline.yaml`** — it maps roles → agents
(which model implements, reviews, judges), picks the default workflow, and sets
review tolerance, severity gates, and protected paths. You rarely touch it, but
when you do:

```
/mb config init        # copy the bundled default into .memory-bank/pipeline.yaml
/mb config show        # print the resolved config (project override → bundled default)
/mb config validate    # schema-check before running work
/mb config path        # print the absolute path of the resolved pipeline
```

**Compose a workflow per run** with launch flags — no config edit needed
(precedence: flags > `pipeline.yaml` > default):

```
/mb work --review                       # implement → verify → review → done
/mb work --review --judge               # add an independent GO / NO_GO judge gate
/mb work billing-overhaul --workflow full   # whole chain from scratch: discuss → sdd → plan → … → done (needs a topic)
/mb work --stages implement,verify      # run an exact subset
```

**Or just describe the intent in a prompt** — *"execute the billing spec with
review and an independent judge"* runs `/mb work billing --review --judge`. To make
a choice permanent, set it in `pipeline.yaml` (`review.enabled: true`,
`workflow.default: governed-execution`) or keep several presets side by side with
named pipelines (`/mb pipeline new codex --agent claude-code`, `/mb pipeline use
codex`). Full schema: [pipeline.yaml Schema](pipeline-yaml.md).

## Storage modes

Memory Bank supports three ways to store your bank — pick the one that fits your
workflow.

**Local (default)** — `/mb init` (same as `/mb init --storage=local`). The bank
lives in the repo at `.memory-bank/`. Commit it to share with your team, or
`.gitignore` it for solo use.

**Global (opt-in personal storage)** — `/mb init --storage=global --agent=<name>`
(e.g. `--agent=claude-code`, `--agent=cursor`, `--agent=codex`). The bank lives
outside the repo, under `~/.<agent>/memory-bank/projects/<id>/.memory-bank`, and
must **not** be committed to the project repo.

**Rules-only (no init required)** — skip `/mb init` entirely. The agent prints
`[MEMORY BANK: ABSENT]` and the `/mb` lifecycle commands stay inactive, but all
engineering rules still apply: TDD, SOLID, Clean Architecture, DRY/KISS/YAGNI,
Testing Trophy, protected files, no placeholders. Run `/mb init` at any later
point to activate Memory Bank without losing any code.

## Rule profiles (optional personalization)

Tune the configurable rules layer to your stack without weakening the immutable
safety baseline (TDD, no placeholders, protected files, verification before
completion — these never turn off):

```bash
# User-global profile (works even without a project Memory Bank):
mb-profile.sh init --scope=user --role=backend --stack=go \
  --architecture=microservices --delivery=contract-first

# Project profile:
mb-profile.sh init --scope=project --role=frontend --stack=typescript \
  --architecture=fsd --delivery=sdd
```

Supported presets — role: `backend`, `frontend`, `mobile`; stack: `go`, `python`,
`javascript`, `typescript`, `java`, `generic`; architecture: `clean`, `hexagonal`,
`modular-monolith`, `microservices`, `ddd`, `fsd`, `mobile-udf`, `event-driven`;
delivery: `tdd`, `contract-first`, `api-first`, `sdd`, `legacy-safe`, `exploratory`.

## Notes, reports, backlog & roadmap

Beyond `status.md`/`checklist.md`, the bank has four surfaces you accumulate
knowledge in — and you reference all of them in plain prompts (*"check the notes
before you start"*, *"add that to the backlog"*, *"what's next on the roadmap?"*).
The agent reads and writes them directly.

- **`notes/`** — short, reusable **patterns and lessons** (5–15 lines each, not a
  chronological log). Write one with `/mb note <topic>`; `/mb done` also drops a
  note when a session learned something worth keeping, and `/mb consolidate`
  distils recurring facts from old sessions into notes automatically.
- **Research reports** — `/mb research <query>` dispatches the `mb-research` agent
  (graph → semantic → web) and returns `file:line`-grounded findings; larger
  investigations and audits land as dated files under `reports/`, which you can
  point later prompts at.
- **`backlog.md`** — the running list of **ideas and ADRs** with monotonic IDs
  (`I-NNN`, `ADR-NNN` via `/mb adr <title>`). Governed reviews feed it on their
  own: a `GO_WITH_BACKLOG` judge verdict registers every non-blocking finding
  here before the work is marked done — nothing is lost, nothing blocks a clean
  stage.
- **`roadmap.md`** — the prioritized plan queue. Its autosync block is regenerated
  from `plans/*.md` frontmatter by `/mb roadmap-sync`, so the roadmap always
  reflects the real plans instead of drifting.
- **`agreements.md`** — the running registry of **confirmed decisions**. When you
  settle something with the agent, it records `AGR-NNN` with a one-line statement;
  a changed decision supersedes the old one (`--supersedes N`) instead of leaving
  two active. The active list is mirrored into `CLAUDE.md`/`AGENTS.md`, so every
  future session — and every subagent — starts already knowing what was agreed.
  Manage with `/mb agree` (`add` / `question` / `list`); unconfirmed ideas park as
  open questions until you decide.

The through-line: **researchers, reviewers, and the judge maintain these files as
a side effect of running** — you don't hand-curate them, and any later prompt (or
teammate's agent) can build on what they wrote. For the invariants behind each
file, see [Memory Bank Layout](concepts/memory-bank-layout.md).

## Where to go next

- [Your First Feature](first-feature.md) — a full plan → work → verify → done loop
- [Memory Bank Layout](concepts/memory-bank-layout.md) — what every bank file is for
- [Rules](concepts/rules.md) — the engineering baseline the agent always applies
- [SDD flow](concepts/sdd.md) — `discuss → sdd → work` for larger features
- [Cross-Agent Setup](cross-agent-setup.md) — per-client install details
