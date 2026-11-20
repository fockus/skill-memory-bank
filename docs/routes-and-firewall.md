# Routes, firewall and cost

<p class="mb-lede" markdown>Three controls decide how a piece of work is run and when it may be
called finished: the **route** picks the shape of the flow, the **firewall** owns the verdict, and
the **cost tier** decides which model does which job.</p>

| | |
|---|---|
| **Use it for** | Understanding why a flow took the path it did, and what "green" means |
| **Commands** | `/mb analyze-task`, `/mb flow <route>`, `/mb config`, `/mb cost` |
| **Scripts** | `mb-flow-route.sh`, `mb-flow-verify.sh`, `mb-work-plan.sh` |
| **Status in 5.4.1** | Routes and the firewall are stable; presets and cost tiers changed in 5.4 |

## Routes

A route is the shape of a flow. `/mb analyze-task` reads `goal.md` and the changed-file scope from
git, picks **one** candidate — the lowest route that genuinely fits — and writes the resolved
route into the `<!-- mb-flow -->` fence in `status.md`.

| Route | When | Defining loop |
|---|---|---|
| `research` | An investigation or spike; no production change expected | The report is the result |
| `bugfix` | A localized defect | reproduce (a new failing test) → debug → patch → verify |
| `code-change` | A feature or change inside existing seams. **Default when unsure** | The `/mb work` loop, as one skill |
| `arch` | Contracts, domain rules, ports or cross-module structure | Design first, then the loop |
| `migration` | A schema, data or dependency migration with ordering risk | Ordered, reversible steps |

```text
/mb analyze-task          # auto-route (the default entry point)
/mb flow arch             # pin a route by hand, skipping classification
/mb flow arch --dry-run   # preview without writing the fence
```

### The route floor

The floor is deterministic and only ever **raises** a route. If any changed file matches one of
these, the route resolves to at least `arch`:

- a path under `domain/`
- an `application/ports` path
- an interface, `Protocol`, `ABC` or contract file
- a declared `protected_path`
- a linked plan with `depends_on` greater than zero

`/mb flow bugfix` on a diff that touches `domain/` resolves to `arch`, not `bugfix`. The resolver
reports it: `{"candidate": …, "floor": …, "route": …, "floor_triggered": true, "reasons": […]}`.

!!! note "An override can raise a route, never lower it"
    Choosing a route by hand changes only the starting candidate. The floor and the firewall
    still apply.

## The firewall

`mb-flow-verify.sh` is the single exit-code authority. It fans out to every check runner, turns
each verdict into severity counts and hands them to the severity gate. A flow is never declared
finished on red.

| Check | Runner | Severity when red |
|---|---|---|
| `acceptance` | `mb-goal-acceptance.sh` — the goal's criteria | **blocker** |
| `tests` | `mb-test-run.sh` | **blocker** |
| `diff_scope` | `mb-diff-scope.sh` — out-of-scope changes | **blocker** |
| `protected` | protected-path breach | **blocker** |
| `qa` | `mb-qa-bug.sh` — an open critical or major bug | **blocker** |
| `rules` | deterministic engineering-rule violations | major |
| `lint` | `mb-lint-run.sh` | major |
| `no_todo` | `mb-no-todo.sh` — a placeholder shipped in code | major |

| Exit | Verdict | Meaning |
|---|---|---|
| `0` | pass | Every check is green or skipped, and the gate passes |
| `1` | fail | At least one check is cleanly red. Every breaching check is named with its findings |
| `2` | broke | A check **script itself** broke: it crashed, was missing, or printed unparseable output |

`2` dominates `1` dominates `0`: a broken check is the loudest failure and is never swallowed as a
pass. A check that cannot apply returns a skip and contributes nothing — `qa` without
`qa/bugs.md`, `diff_scope` without a configured scope.

```text
mb-flow-verify.sh                       # the default check set
mb-flow-verify.sh --skip acceptance     # reuse the defaults minus one check
mb-flow-verify.sh --check 'tests=make test'
```

### The closure gate

A Stop hook, `mb-flow-closure-guard.sh`, keeps a session from ending on a red flow. While known
work is still running — an open `/mb team` with working tracks, a fresh `/mb work` run — it waits
quietly instead of blocking and prints one reminder per interval.

| Setting (`.mb-config` or env) | Default | Meaning |
|---|---|---|
| `flow_closure_remind` · `MB_FLOW_CLOSURE_REMIND` | 30 min | Reminder interval; `0` is silent |
| `flow_closure_busy_max_age` · `MB_FLOW_CLOSURE_BUSY_MAX_AGE` | 120 min | How long running work defers the gate; `0` never defers |
| `MB_FLOW_CLOSURE=off` | — | Disables the gate entirely |

## Presets — how long the chain is

`/mb work` runs each item through a chain of subagents. The preset sets its length; the task tier
picks the preset (`effort_tiers:` in `pipeline.yaml`).

| Preset | Tier | Chain | Dispatches per item |
|---|---|---|---|
| `simple` | small | implement → done | 1 |
| `medium` | standard · **default** | implement → verify → done | 1, plus 1 verifier per plan |
| `complex` | large | + review → fix | 2 clean, up to 6 with fix cycles |
| `governed` | extra | + review ensemble → judge → fix or backlog | 8 clean, up to about 25 |

```text
/mb work --workflow governed     # name the preset
/mb work --tier large            # or name the size
/mb work --verify=stage          # verifier cadence: stage | plan | run | off
```

Aliases: `execution` → `medium`; `governed-execution` and `strict` → `governed`. Full detail:
[/mb work](mb-work.md).

## Cost tiers — which model does which job

A cost tier maps every role class to a model slot. Each host has two slots, `premium` and `mid`.

| Role | `premium` | `optimal` (default) | `economy` |
|---|---|---|---|
| planner | premium | premium | mid |
| reviewer | premium | premium | mid |
| judge | premium | premium | mid |
| implementer | premium | mid | mid |
| verifier | premium | mid | mid |
| researcher | premium | mid | mid |

```yaml
cost: optimal
model_profiles:
  claude-code: {premium: opus, mid: sonnet}
  codex:       {premium: gpt-6-astra, mid: gpt-6.1-sol}
  cursor:      {premium: claude-opus-5-5, mid: claude-sonnet-5-5}
```

An explicit `roles.<role>.model` still wins over the tier. `hosts.<host>.{cost,preset,verify}` set
per-host defaults. `/mb config show` prints the resolved config and where each value came from.

### Measuring it

```text
/mb cost                  # sessions, subagent roles, work items
/mb cost --since 7        # only the last seven days
/mb cost --json           # the machine format, for baselines
```

`/mb cost` mines the transcripts for what a run actually spent: turns, tool calls, dispatches,
tokens, peak context and compactions per session; totals per role; totals per work item.

## Limits in 5.4.1

- There is no local build check: `build` always resolves to a skip.
- `diff_scope` is a skip unless a scope is configured.
- `/mb cost` reads Claude Code transcripts. Other hosts are not reported.
- On OpenCode and Cursor the tier model is applied **statically**, through the installed agent
  files. Re-render them after changing the pipeline: `/mb config init --host opencode|cursor|codex`.
- Pi and OpenCode ship no model profile: they inherit the session model until you write one with
  `/mb config init --host pi|opencode --model-mid <provider/id>`.

!!! agent "For agents"
    1. The firewall's exit code is the verdict. Never report success on exit `1` or `2`, and never
       print a done signal on red.
    2. On exit `1`, fix what the named checks report and run it again. On exit `2`, repair the
       check itself first — do not treat it as a pass.
    3. Auto-routing is the default. Use `/mb flow <route>` only when the user pins a route.
    4. If `floor_triggered` is `true`, say so and name the reasons.
    5. Dispatch each role with the exact model the resolved plan prints. Do not substitute a
       fuzzy model name.

## Related

- [/mb work — the execution engine](mb-work.md) · [The development flow](flow.md)
- [`pipeline.yaml` schema](pipeline-yaml.md)
- [/mb qa — acceptance QA](mb-qa.md)
