# Design: adapter-parity

> Architecture, interfaces, and decisions backing requirements.md.
> Source of decisions: `context/adapter-parity.md` (D-01…D-07) + three-agent parity
> audit of 2026-07-15. Position: FIRST in the roadmap queue, ahead of donor v5.4.0
> (AGR-012).

## Architecture

The proven parity-by-construction channel in this repo is **AGENTS.md + client-agnostic
scripts** (`/mb agree` reached every host with zero adapter work). What that channel can
NOT carry is live lifecycle (session capture, session-start injection, update-notify)
and subagent dispatch — those need a per-host transport. This spec adds exactly that
transport as **opt-in host-native extensions**, single-sourced under `adapters/`:

```
                       ┌── decline ──► today's install, byte-identical (REQ-002/NFR-001)
install.sh / /mb install
  targets pi|opencode ─┤
  (offer, REQ-001)     └── accept ──► Pi:  ~/.pi/agent/extensions/
                                      │      memory-bank-session.ts   (exists! wire it)
                                      │      memory-bank-graph-rag.ts (promote to global)
                                      │    + agents/*.md for role dispatch (new)
                                      └► OpenCode: parity plugin (extend memory-bank.js)
                                           + global ~/.config/opencode/agent/*.md

runtime nudge: /mb doctor + mb-session-doctor.sh (REQ-003)  — suggest, never install
update-notify: renders wherever a session-start transport exists (REQ-013/014)
honesty:       manifest platform_limited[] + negative bats (REQ-015/017)
```

Codex deliberately stays on the honest-degradation tier (D-03): no extension mechanism
exists — its scope here is prompt-hook update-notify (best-effort), the existing
git-hooks-fallback capture, and machine-readable `platform_limited`.

Touchpoints (single source per capability):
- `install.sh` — the offer step (interactive prompt + `--with-extensions` flag), the
  Pi agents install loop, the OpenCode global agent scope.
- `adapters/pi.sh` — installs BOTH Pi extensions (session-memory + graph-rag) on accept.
- `adapters/pi_session_memory_extension.ts` — already implements the full lifecycle;
  wiring only, no rewrite (D-04).
- `adapters/opencode.sh` — plugin gains session-start injection + per-turn capture
  handlers (subject to the host-API research task T1).
- `hooks/mb-update-notify.sh` + `scripts/mb-version-check.sh` — reused as-is; each new
  transport just invokes them (same TTL cache).
- `adapters/codex.sh` — before-prompt hook gains the TTL-gated notice; manifest gains
  `platform_limited`.
- `scripts/mb-session-doctor.sh` — the runtime nudge already half-exists ("extension
  not installed" check); extend to print the exact command (REQ-003).

## Interfaces

### Extension offer contract (install-time)
Input: client list + interactivity (TTY?) + `--with-extensions[=pi,opencode]` flag /
`MB_WITH_EXTENSIONS` env. Behavior: TTY without flag → one prompt per host family
(default N); flag present → install without prompting (REQ-005); no TTY and no flag →
skip silently (REQ-002 default). Output: manifest records `extensions_installed: [...]`
per host. Errors: unwritable extensions dir → named error, rest of install completes.

### Pi session-memory extension (existing file)
Events: session_start (context header + catchup + update-notify render), per-turn log,
before_compact (handoff capsule), shutdown (finalize + recent-rebuild + reindex).
Writes `session/<date>_<hhmm>_<sid8>.md`, schema v2 — byte-compatible with CC captures
(REQ-007; the cross-agent runtime parity suite gains a Pi case mirroring the CC one).

### Subagent dispatch (per-host, resolved by T1 research)
Contract consumed by `/mb work`: given a role (mb-backend…), resolve host mechanism:
- Claude Code: Task tool (reference).
- Pi: **no native agent-registry/dispatch flag exists in Pi core** (T1 confirmed —
  `--agent` only appears as an extension-defined flag via `pi.registerFlag`, never a
  built-in). The viable — and officially reference-implemented — mechanism is an
  extension-registered `pi.registerTool()` that spawns a **headless `pi` subprocess per
  invocation**: `pi --mode json -p --no-session [--model <m>] [--tools <t1,t2>]
  [--append-system-prompt <tmpfile>] "Task: <task>"`, reading newline-delimited JSON
  events from stdout for streaming + usage. This is exactly the pattern in Pi's own
  `examples/extensions/subagent/index.ts` (agent `.md` files discovered from
  `~/.pi/agent/agents/`, same convention our design already assumes) — D-09 floor IS
  the best available mechanism, not a fallback under something better. Reference caps
  worth carrying into our extension: `MAX_PARALLEL_TASKS=8`, `MAX_CONCURRENCY=4`,
  abort via `AbortSignal` killing the child process. Design constraint unchanged: the
  `mb-subinvoke-resolve.sh` table stays the single registry across hosts.

  **Measured (this env, pi v0.75.5, local `pi --mode json -p --no-session "Task: reply pong"` with no `--tools`/`--append-system-prompt` scoping):** wall 38.7s / user 1.6s / sys 0.4s — subprocess spawn overhead itself is ~1-2s CPU, latency is dominated by model choice + thinking level, not the spawn mechanism. Without the role's `--tools` allowlist + `--append-system-prompt` scoping (both used by the reference `subagent/index.ts`), the unscoped run took 5 turns / 4 tool calls / ~$0.02 just to answer "pong" — confirms scoping flags are load-bearing for latency AND cost, not optional polish; our extension must always pass them.
- OpenCode: native `.opencode/agent/*.md` discovery already works project-scope;
  add the global dir; dispatch unchanged.
- Codex: stays `codex exec` (documented `platform_limited: [subagents]`).

### T1 findings (host-API research, 2026-07-15)

**OpenCode plugin events** (primary source: `@opencode-ai/plugin` `Hooks` interface,
`packages/plugin/src/index.ts` on the `dev` branch — read directly, not just docs):

| Hook | Fires | Payload (input → output) |
|------|-------|---------------------------|
| `event` | any bus event (`session.created`, `session.updated`, `session.idle` *(deprecated → `session.status`)*, `session.error`, `session.deleted`, `session.compacted`, `message.updated`, `message.part.updated`, …) | `{ event: Event }` (discriminated union, read-only) |
| `chat.message` | new user message received, **before** it is sent to the LLM — the prompt-submit-equivalent hook | in: `{sessionID, agent?, model?, messageID?, variant?}` → out: `{message: UserMessage, parts: Part[]}` (mutable) |
| `experimental.chat.system.transform` | per LLM call, system-prompt assembly | in: `{sessionID?, model}` → out: `{system: string[]}` (mutable) — **the injection point for future semantic-recall context** |
| `experimental.session.compacting` | before compaction | in: `{sessionID}` → out: `{context: string[], prompt?}` (already used in `adapters/opencode.sh`) |
| `tool.execute.before` / `.after` | around tool calls | in: `{tool, sessionID, callID[, args]}` → out mutable (already used in `adapters/opencode.sh`) |
| `command.execute.before` | slash-command invocation | in: `{command, sessionID, arguments}` → out: `{parts}` |
| `permission.ask` | permission prompt | in: `Permission` → out: `{status}` |

`session.created`/`session.idle`/`session.deleted` exist as event-bus members (confirmed
via GitHub issue #30043 discussing `session.status` deprecating `session.idle`); our
adapter's reliance on `session.idle` is functionally correct today but should migrate to
`session.status` in a future slice (tracked as a risk below, not blocking T1-gated work).
No standalone "prompt-submit" hook exists outside `chat.message`/`experimental.chat.*`;
those two ARE the surface.

**Pi native slash commands (REQ-022):** confirmed via `docs/extensions.md` —
`pi.registerCommand(name, options)` registers a **full native command**, not a prompt
template: it gets its own handler function (can run arbitrary code, call `ctx.ui.*`,
`ctx.reload()`, `sendUserMessage()`, etc.), is listed alongside prompt templates and
skill commands in the session's command discovery, and is distinct from the
`~/.pi/agent/prompts/*.md` prompt-template mechanism (which only expands static text).
Verdict: Pi CAN carry `/mb`-style commands as native extension commands — no
`platform_limited` needed for this capability once the extension ships.

**Pi prompt-submit surface (for (d) / future semantic-recall):** three composable hooks,
all confirmed in `docs/extensions.md`: `pi.on("input", …)` (raw user text, before
skill/template expansion, supports `transform`/`handle` actions), `pi.on
("before_agent_start", …)` (fires after prompt submit, before the agent loop; can inject
a persistent message and/or rewrite `systemPrompt`), `pi.on("context", …)` (fires before
**every** LLM call, can filter/inject messages non-destructively). Verdict: Pi's surface
is richer than OpenCode's for this purpose (three hook points vs. two).

**OpenCode prompt-submit surface:** `chat.message` (per new message, pre-LLM) +
`experimental.chat.system.transform` (per LLM call, system-prompt only) — narrower than
Pi (no raw-input-transform hook and no per-call full-message-list hook), but sufficient
for session-start injection (already used for update-notify) and would be sufficient for
a future semantic-recall injection via `experimental.chat.system.transform`.

Evidence: `adapters/pi_session_memory_extension.ts` (existing event usage in this repo),
`adapters/opencode.sh:125-158` (existing plugin hook usage), upstream primary sources
listed in the research note.

### update-notify transport contract
Each transport calls `hooks/mb-update-notify.sh` (or `mb-version-check.sh --cache-only`
for non-shell hosts) exactly once per session start / TTL window; renders ≤3 lines;
`MB_UPDATE_CHECK=off` honored everywhere; failure never blocks the session (REQ-019).

### Manifest honesty
`platform_limited: ["<capability>", ...]` — closed vocabulary: `statusline`,
`subagents`, `lifecycle-hooks`, `session-memory`, `update-notify`, `role-routing`. A
capability listed there MUST have a matching negative bats assertion (REQ-017) — the
pair is the regression guard. A meta-test (`test_platform_limited_honesty.bats`) scans
every client manifest and fails if any declared value falls outside this vocabulary or
lacks a matching negative assertion, so the suite cannot silently drift from the
manifests.

**Semantics — the manifest describes THIS install as configured, per install-state.**
A value in `platform_limited` means the capability is **not available in the install this
manifest describes**, with a discoverable reason. This is deliberately *per-install-state*,
not a hypothetical host ceiling: an accept-gated capability is declared limited on the
**declined/base** manifest (reason: "requires accepting the opt-in parity extension") and
**omitted** on the **accepted/extended** manifest (where it genuinely works). Rationale:
the honesty layer exists so a user/agent reading the manifest of the install they actually
have learns the truth about it — declaring a ceiling the current install doesn't reach
would be dishonest-by-omission (a declined OpenCode/Pi install genuinely does NOT capture
`session/*.md`, proven by the base-plugin no-op tests). Three tiers result:
- **Hard ceiling** (no install state provides it): `statusline` on every non-CC host;
  `session-memory`/`lifecycle-hooks`/`update-notify` on windsurf/cline/kilo; `subagents`
  where no dispatch primitive exists — declared in **every** manifest for that host.
- **Accept-gated** (base absent, accepted present): OpenCode `session-memory` (extended
  `chat.message` capture) and Pi `session-memory` (accept-path extension) — declared
  limited on the base/declined manifest, omitted on the accepted manifest. The negative
  test asserts the PAIR per state: base manifest lists it **and** base plugin is a capture
  no-op; accepted manifest omits it **and** accepted plugin writes a real v2 `session/*.md`.
- **Always-limited regardless of accept** (a real gap the extension does not close):
  `role-routing` on pi/opencode — the host has a genuine dispatch primitive but `/mb work`
  never routes per-host (I-121/I-122), so it is limited in both base and accepted states.

**`role-routing` (added by T7, reconciling T4's Pi shipment):** narrower than
`subagents` — it means "this host has its own genuine, working subagent-dispatch
primitive, but `/mb work`'s per-role automated dispatch (`commands/work.md` step 5a)
only ever calls the Claude Code Task tool; no cross-host routing harness exists yet
(backlog I-121/I-122)". `subagents` (the coarser term) means "this host has no
subagent-dispatch primitive at all — nothing to route to in the first place". T4
shipped Pi with `platform_limited: ["role-routing"]` on its accept-path
`.mb-global-extensions-manifest.json`, correctly recognizing that Pi's opt-in
`mb_dispatch_subagent` tool made blanket `subagents` inaccurate — but `role-routing`
was not yet in the closed vocabulary at the time. **T7 decision: extend the closed
vocabulary to include `role-routing` (not remap Pi to `subagents`)** — collapsing it
would be dishonest-by-omission of the tool Pi genuinely has, and the underlying
I-121 finding ("no host has `/mb work`'s deterministic per-role dispatch") is
real, narrow, and worth its own term. OpenCode, which independently ships its own
genuine native subagent-dispatch primitive (`.opencode/agent/*.md` discovery, T5),
gets the same `role-routing` term for the same reason and is added to the honesty
layer in T7 alongside Pi.

**Per-client `platform_limited`, evidence-based (T7, verified by direct adapter
inspection — see the manifest write site in each adapter for the full inline
rationale):**

| Client | `platform_limited` | Why (one-line evidence) |
|---|---|---|
| claude-code | `[]` | Reference tier — every capability ships natively. |
| cursor | `statusline`, `subagents` | Full CC-compatible lifecycle (12 `_mb_owned` hooks incl. `stop`→`mb-session-turn.sh`, T7), genuine update-notify + v2-schema `session/*.md` (REQ-021). No statusline surface; `agents/*.md` is a reference-only prompt library, no dispatch mechanism. |
| windsurf | `statusline`, `subagents`, `lifecycle-hooks`, `session-memory`, `update-notify` | Only `user-prompt-submit`/`model-response` wired — no session-start-class hook, no CC v2-schema capture (1-line `progress.md` stub only), no update-notify, no agent dispatch, no statusline. |
| cline | `statusline`, `subagents`, `lifecycle-hooks`, `session-memory`, `update-notify` | Same tier as Windsurf — `beforeToolExecution`/`afterToolExecution`/`onNotification` only, no session-start-class hook, stub capture only, no update-notify. |
| kilo | `statusline`, `subagents`, `lifecycle-hooks`, `session-memory`, `update-notify` | No native hooks API at all (own header comment) — 100% git-hooks-fallback (stub `progress.md` capture on commit only), no update-notify, no agent dispatch, no statusline. |
| opencode | `statusline`, `role-routing` | Base plugin (unconditional, no accept required) wires the full CC-shaped event set + genuine update-notify (T5) + native `.opencode/agent/*.md` dispatch. No statusline; `/mb work` routing gap (I-121). |
| pi | `statusline`, `role-routing` | Declared on BOTH the per-project manifest (baseline, accept-independent) and the accept-path global-extensions manifest (T4, unchanged). No statusline; `/mb work` routing gap (I-121), even though Pi's own `mb_dispatch_subagent` tool works. |
| codex | `statusline`, `subagents`, `lifecycle-hooks`, `session-memory` | D-03 honest-degradation tier. update-notify (T6) genuinely renders — NOT limited. No Task-tool-equivalent (`codex exec` only), no session-start-class hook (experimental prompt-submit hook + git-hooks-fallback only), stub capture only. |

## Decisions

Condensed from `context/adapter-parity.md` — full Options/Rejected there.

- **D-01** First in roadmap, ahead of donor v5.4.0 (user directive, AGR-012).
- **D-02** Opt-in host-native extensions + runtime nudge; never auto-install; declined
  install byte-identical (AGR-013, design contract).
- **D-03** Codex = honest degradation tier: prompt-hook notice + git-hooks-fallback +
  `platform_limited`; no extension parity pretence.
- **D-04** Wire the existing `pi_session_memory_extension.ts`, don't rewrite; promote
  graph-rag to the global offer.
- **D-05** Subagent dispatch mechanism per host is decided by research task T1 BEFORE
  implementation — no API assumptions.
- **D-06** update-notify reuses the existing check/render scripts on every transport,
  same TTL cache, fail-open.
- **D-07** Honesty layer (platform_limited + negative tests) ships in the same slice.

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| OpenCode plugin API lacks per-turn/session-start events | M | H | T1 research first; if absent → documented degraded tier (capture on idle/compact only) + `platform_limited`, never silent |
| Pi extension API drifts between Pi versions | M | M | Extension pins to documented events only; fail-open (REQ-019); doctor reports a broken extension |
| Offer prompt breaks non-interactive/CI installs | L | H | No TTY + no flag → skip silently; bats cover the CI path (REQ-005 fixture) |
| Installed extension diverges from bundled source after upgrade | M | M | `/mb upgrade` re-syncs (REQ-018); user-modified file → backup, never clobber |
| Byte-identity of the declined path regresses | M | H | NFR-001 regression fixture: declined install diffed against pre-spec adapter output in bats |
| Subagent spawn on Pi is slow/flaky (headless CLI) | M | M | T1 measures; `/mb work` keeps the single-agent fallback path; dispatch failure → inline execution warning |
