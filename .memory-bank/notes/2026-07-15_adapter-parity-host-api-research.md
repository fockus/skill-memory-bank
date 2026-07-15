# adapter-parity T1: Pi + OpenCode host-API research (2026-07-15)

- Pi has **no native agent-registry/`--agent` dispatch flag** (`pi --help` v0.75.5
  confirms). Reference mechanism (Pi's own `examples/extensions/subagent/index.ts`) is
  `pi.registerTool()` spawning headless `pi --mode json -p --no-session --model <m>
  --tools <t1,t2> --append-system-prompt <tmpfile> "Task: <task>"` — D-09 floor IS the
  best mechanism, not a fallback.
- Measured locally (pi v0.75.5): unscoped spawn ("reply pong") → wall 38.7s / user 1.6s
  cpu, 5 turns, ~$0.02 — spawn overhead is negligible; missing `--tools`/
  `--append-system-prompt` scoping (not model choice alone) drove the wander/cost.
- Pi `pi.registerCommand()` = full native command API (REQ-022 answered: yes).
- Pi prompt-submit surface: `input` → `before_agent_start` → `context` (3 hooks).
- OpenCode (`@opencode-ai/plugin` `Hooks`, primary source): `chat.message` = pre-LLM
  prompt-submit hook; `experimental.chat.system.transform` = per-call system-prompt
  injection (semantic-recall hook point); `session.idle` deprecated → `session.status`.
- Full tables in `specs/adapter-parity/design.md` § T1 findings.

Sources: badlogic/pi-mono `docs/extensions.md`, `examples/extensions/subagent/*.ts`;
sst/opencode `packages/plugin/src/index.ts` (dev branch); sst/opencode#30043.
