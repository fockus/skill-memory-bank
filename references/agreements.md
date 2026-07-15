# Running list of agreements — `.memory-bank/agreements.md`

Protocol for the canonical registry of **confirmed decisions currently in force** — a layer
distinct from `progress.md` (what happened), ADRs (why we chose it), and `RULES.md` (how we always
work). Battle-tested problem: in long sessions decisions get buried in dozens of messages — the
model re-implements an already-postponed option, reopens a closed question, or hands a subagent a
stale requirement. `progress.md` preserves the narrative; `agreements.md` preserves the *executable
decisions* — the "what is in force right now" that a fresh session must obey without being
reminded.

## What IS an agreement

A statement the user **explicitly confirmed** in this session, one of:

- a confirmed **decision** — "yes, use bcrypt for password hashing"
- a **requirement** — "the export must support CSV and JSON, nothing else for v1"
- a **constraint** — "no new dependencies without asking first"
- a **definition** — "'active user' means logged in within the last 30 days"
- a **priority** call — "ship the API before the UI polish"
- a **scope** cut — "Kanban view is out of v1, phase 2"
- a **responsibility** split — "backend owns validation, frontend only displays the error"
- an **acceptance criterion** — "the p95 latency budget is 200ms"

## What is NOT an agreement (anti-examples)

| Looks like an agreement | Why it is NOT one | Where it belongs instead |
|---|---|---|
| "We could use a vector database here" | A **proposal**, not a confirmed choice — the user has not said yes | `question "<text>"` → Open Questions |
| "I'd recommend Redis for the cache layer" | A **model hypothesis/recommendation** — the model's own suggestion, unconfirmed | `question` — never Active |
| "Presumably the API stays REST" | An **implicit assumption** — nobody confirmed it, it was inferred | `question`, or ask the user to confirm explicitly first |
| "Then we discussed rate limiting for a while and looked at three options" | **Conversation detail / narrative** — no decision was reached | `progress.md` (if worth recording at all) — never the registry |
| "Let's try Postgres and see how it goes" | A tentative **experiment**, not a locked-in decision | `question`, or an `EXP-NNN` in `research.md` if it is a real experiment |

Rule of thumb: if the user did not say something equivalent to "yes", "confirmed", "go with X", or
"decided", it is not yet an agreement. Recording a proposal as Active is the #1 failure mode this
protocol guards against — the visible-announce rule below exists specifically so every write is
reviewable and reversible with one command (`reject`/`supersede`).

## The 4 statuses

| Status | Meaning | Section |
|---|---|---|
| `active` | In force right now — every fresh session must obey it | `## Active` |
| `deferred` | Confirmed but postponed (a later phase, a future decision) | `## Deferred` |
| `superseded` | Replaced by a newer active entry (`AGR-N` → `AGR-M` via `--supersedes N`) | `## Archive` |
| `rejected` | Confirmed as "no" — explicitly ruled out, kept for history | `## Archive` |

`proposed`/`confirmed` intermediate states do not exist — only confirmed decisions get written at
all (see anti-examples above), so there is nothing to move from "proposed" to "confirmed".
`deprecated`/`invalidated` are rare shades already covered by `superseded`/`rejected`. Statuses are
derived from which section an entry lives in plus its trailing marker
(`[superseded by AGR-Y]`, `[rejected]`) — see `design.md` for the exact line grammar.

## The visible-announce rule

Every write is announced back to the user in the same turn, verbatim:

```
→ AGR-NNN записано: <statement>
```

No re-asking on an explicit decision (it is already confirmed — asking again is friction), and no
silent writes (the announce line is the only trust mechanism: it makes every entry reviewable and
one command away from `reject`/`supersede` if the model over-recorded).

## ADR routing

Some confirmed decisions are also **big architectural** ones — hard to reverse, surprising without
context, the result of a real trade-off (the same 3-gate test `/mb adr` uses). For those:

1. Record the agreement as usual: `mb-agree.sh add "<statement>" --adr NNN`.
2. Create the companion ADR via `/mb adr` — full Context / Options / Decision / Rationale /
   Consequences live there.
3. The registry entry carries only `→ ADR-NNN`, nothing more.

Rationale, alternatives, and consequences live in the ADR — the registry line stays a compact
one-liner. This keeps `agreements.md` cheap to inject into every session while the deep reasoning
stays discoverable one hop away in `backlog.md`.

## Subagents propose, never write

`/mb work` dev-role subagents (and any other subagent) do **not** call `mb-agree.sh` directly. When
a subagent's work surfaces something that looks like a new agreement (a scope cut it had to make, a
constraint it discovered), it reports the candidate back to the dispatching session in its STATUS
report; only the orchestrating session — talking to the user, or acting on an already-explicit user
instruction — runs the write. This keeps the registry a record of decisions the *user* actually
confirmed, not a side effect of implementation work.

## Lazy activation and kill-switch

The rules trigger below ships with the skill for every project, but it produces **zero artifacts**
until the first `mb-agree.sh add` — no `agreements.md`, no managed block in `CLAUDE.md`/`AGENTS.md`,
zero added tokens in banks that never use the feature (the skill's defaults-never-change contract).
Turn it off entirely with `MB_AGREEMENTS=off` (env var or a `.mb-config` line) — every subcommand
becomes an explained no-op, exit 0, no writes to any of the three files.

## Compact rules-layer trigger

The always-on trigger text that ships in `rules/CLAUDE-GLOBAL.md` and `rules/RULES.md`:

- Explicit user decision → `mb-agree.sh add "<statement>"`, then announce `→ AGR-NNN записано: <statement>`.
- Unconfirmed idea/hypothesis (the model's own or the user's tentative one) → `mb-agree.sh question "<text>"`.
- A changed decision → `mb-agree.sh add "<new statement>" --supersedes N` (never leave two active entries saying different things).
- Full protocol → this file.

## Relation to other MB files

- `agreements.md` is the **single source of truth** for "what is decided right now"; `CLAUDE.md`/
  `AGENTS.md` only carry a generated, injected mirror (the managed block) — never hand-edit the
  block, edit the registry and run `sync`.
- `progress.md` stays the narrative log (what happened, when); the registry is not a duplicate of
  it — an agreement is the *outcome* of a discussion, not the discussion itself.
- `backlog.md`'s ADR section carries rationale for the subset of agreements big enough to need one
  (`→ ADR-NNN`); the registry never repeats that rationale.
- `/mb verify` (`agents/plan-verifier.md`) reads `## Active` and checks the plan/diff against every
  entry — see the "Agreement Compliance" step there for the fail-or-supersede gate.
