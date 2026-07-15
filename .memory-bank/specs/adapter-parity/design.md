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
- Pi: candidate mechanisms — extension-registered tool spawning headless `pi -p
  --agent <file>`, or a native Pi agent registry if the API provides one. T1 decides;
  design constraint: the `mb-subinvoke-resolve.sh` table stays the single registry.
- OpenCode: native `.opencode/agent/*.md` discovery already works project-scope;
  add the global dir; dispatch unchanged.
- Codex: stays `codex exec` (documented `platform_limited: [subagents]`).

### update-notify transport contract
Each transport calls `hooks/mb-update-notify.sh` (or `mb-version-check.sh --cache-only`
for non-shell hosts) exactly once per session start / TTL window; renders ≤3 lines;
`MB_UPDATE_CHECK=off` honored everywhere; failure never blocks the session (REQ-019).

### Manifest honesty
`platform_limited: ["<capability>", ...]` — closed vocabulary: `statusline`,
`subagents`, `lifecycle-hooks`, `session-memory`, `update-notify`. A capability listed
there MUST have a matching negative bats assertion (REQ-017) — the pair is the
regression guard.

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
