<div class="mb-hero" markdown>

<p class="mb-kicker">Documentation · v5.4.1</p>

# Memory, a process and a *team* for your coding agent

Long-term project memory, engineering rules, spec-driven planning, a work pipeline you dial by
risk, parallel agent teams, a goal loop that stops on evidence, a code graph and acceptance QA.
Plain files next to your code, for nine agent hosts.

[Quick start](quick-start.md){ .md-button .md-button--primary }
[The development flow](flow.md){ .md-button }
[Agent guide](agent-guide.md){ .md-button }

</div>

## New in 5.4

<div class="grid cards" markdown>

-   **[/mb team](mb-team.md)** <span class="mb-chip">new</span>

    ---

    Run one task as parallel tracks in one working tree. Owned file globs, waves, locks, shared
    foundations, executable contracts, a scoped commit.

-   **[/mb drive](mb-drive.md)** <span class="mb-chip">rebuilt</span>

    ---

    Hand over a goal with acceptance criteria. Plan it together once, then let it run to
    `stop_success`, `stop_budget` or `stop_human`.

-   **[/mb qa](mb-qa.md)** <span class="mb-chip">new</span>

    ---

    Acceptance QA: a runner agent walks markdown scenarios against the live product and files
    bugs by severity.

-   **[The development flow](flow.md)** <span class="mb-chip">new</span>

    ---

    Eight stations from a raw request to verified code, and the five task tiers that decide how
    many of them a task visits.

-   **[Routes, firewall and cost](routes-and-firewall.md)**

    ---

    Five routes with a deterministic floor, one firewall with one exit code, four presets and
    three cost tiers.

-   **[Code graph](concepts/code-graph.md)**

    ---

    Bash and Bats join the graph, `mb-graph.sh` is one short command, and every subagent prompt
    gets a `## Graph` block.

</div>

## Start here

<div class="grid cards" markdown>

-   **[Install](install.md)**

    ---

    pipx, Homebrew or git clone, with troubleshooting.

-   **[Quick start](quick-start.md)**

    ---

    `/mb init` → `/mb start` → work → `/mb done`, in five minutes.

-   **[Your first feature](first-feature.md)**

    ---

    A worked example: plan → TDD → verify → done.

-   **[Cross-agent setup](cross-agent-setup.md)**

    ---

    Claude Code, Cursor, Codex, OpenCode, Windsurf, Cline, Kilo, Pi, Hermes.

</div>

!!! agent "Working with an agent?"
    Hand it the **[Agent operating guide](agent-guide.md)** — one plain-markdown page that tells
    an AI coding agent what Memory Bank gives it, which command answers which request, and what
    is and is not shipped in 5.4.1.

## How the pieces fit

| Layer | What it does | Read |
|---|---|---|
| **Memory** | Status, plans, decisions and past sessions in `.memory-bank/` | [Overview](concepts/overview.md) · [Layout](concepts/memory-bank-layout.md) · [Session memory](concepts/session-memory.md) |
| **Rules** | Key rules, TDD, architecture boundaries, profiles | [Engineering rules](concepts/rules.md) · [Rule profiles](rule-profiles.md) |
| **Specs** | Brief → requirements → spec triple → plan | [The development flow](flow.md) · [Spec-driven development](concepts/sdd.md) |
| **Pipeline** | Role agents implement each item; gates join by preset | [/mb work](mb-work.md) · [Reviewer 2.0](reviewer-2.md) |
| **Team** | Several tracks at once in one tree | [/mb team](mb-team.md) · [Coordination board](coordination.md) |
| **Drive** | A goal driven to completion | [/mb drive](mb-drive.md) |
| **Graph** | Structural answers without grep | [Code graph & semantic search](concepts/code-graph.md) |
| **Gates** | One firewall decides "done" | [Routes, firewall and cost](routes-and-firewall.md) · [/mb qa](mb-qa.md) |

## Reference

- **[Commands](commands.md)** — every `/mb` sub-command, and commands grouped by job.
- **[`pipeline.yaml` schema](pipeline-yaml.md)** — roles, workflows, presets, cost tiers, QA, team.
- **[Agents reference](agents-reference.md)** — all subagents grouped by role, and which command
  invokes each.
- **[Hooks](hooks.md)** · **[Environment variables](environment-variables.md)**
- **[Design principles](../references/design-principles.md)** — the contract every feature is
  checked against.
- **[Memory Bank structure](../references/structure.md)** — every file in `.memory-bank/`.
- **[Task tiers](../references/effort-tiers.md)** · **[Coordination](../references/coordination.md)**
  · **[Agreements](../references/agreements.md)**

## Operations

- **[Updating](updating.md)** · **[Troubleshooting](troubleshooting.md)** · **[i18n](i18n.md)**
- **[Release process](release-process.md)** · **[Repository migration](repo-migration.md)**
- Migrations: **[v4 → v5](MIGRATION-v4-v5.md)** · **[v3.0 → v3.1](MIGRATION-v3-v3.1.md)** ·
  **[v1 → v2](MIGRATION-v1-v2.md)** · **[install v1 → v2](MIGRATION-install-v1-v2.md)**
- Security: **[policy](../SECURITY.md)** · **[archived audit (2026-04-21)](security/audit-2026-04-21.md)**

## Contributing to docs

- Each `docs/*.md` stays at 300 lines or fewer. If a page grows, split it.
- Cross-link liberally; do not duplicate content. `commands/<name>.md` is the contract, a guide is
  the map.
- Every guide ends with **Limits** and a **For agents** block: what is not shipped, and the rules
  an agent must follow.
- Existing files are not moved while their paths are referenced from `README.md`,
  `CONTRIBUTING.md` or tests.
