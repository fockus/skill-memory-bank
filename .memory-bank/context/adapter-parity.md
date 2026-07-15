---
topic: adapter-parity
created: 2026-07-15
status: ready
---

# Context: adapter-parity

Full functional parity of the Memory Bank skill on OpenCode, Pi and Codex with the
Claude Code reference install. Parity for hooks and subagents is reached through
**host-native extensions offered opt-in to the user** at install time and during
skill usage — never auto-installed. Where a platform physically cannot support a
capability, the degradation is honest and machine-declared (`platform_limited`).
Source: three-agent parity audit of 2026-07-15 (this session) + user directives.

## Purpose & Users

Users: everyone running the skill on a non-Claude-Code host (OpenCode, Pi, Codex) and
mixed teams sharing one repo across hosts. Problem: today the three hosts silently lose
core capabilities — session memory is dead on all three (nobody writes `session/*.md`),
Pi gets no subagents at all, update-notify reaches only Claude Code, and the ready-made
`pi_session_memory_extension.ts` ships in the repo but is never installed. Success:
after accepting the extension offer, a Pi/OpenCode user has working session memory,
role-agent dispatch for `/mb work`, and update notices — the same skill capabilities as
Claude Code; a declining user keeps today's behavior byte-identically; Codex declares
its platform limits explicitly instead of implying parity.

## Research Digest

Facts from the 2026-07-15 three-agent audit — one fact + citation per line.

- `adapters/pi_session_memory_extension.ts` implements the full lifecycle (session_start
  header + catchup, per-turn log, before_compact capsule, shutdown finalize + reindex)
  but is installed by nothing — `docs/cross-agent-setup.md:292-296`,
  `scripts/mb-session-doctor.sh:140-153`
- The agents install loop writes only to `$CLAUDE_DIR/agents/` — Pi never receives
  `agents/*.md` — `install.sh:1048-1056`
- OpenCode DOES receive agents, but only project-scope `.opencode/agent/*.md`; no global
  `~/.config/opencode/agent/` — `adapters/opencode.sh:261-266`
- OpenCode plugin registers only `session.idle/deleted`, `tool.execute.before`,
  `experimental.session.compacting` — no session-start injection, no per-turn capture,
  no prompt-submit recall — `adapters/opencode.sh:125-158`
- `mb-session-end.sh` is a no-op without a session file, so OpenCode session memory is
  dead by construction — `adapters/opencode.sh:102-103`
- Pi graph-rag extension installs only project-local via `adapters/pi.sh install`, never
  in the global `install.sh` path — `adapters/pi.sh:146,170`
- update-notify is wired solely in Claude Code's `settings/hooks.json:156`; no other
  host has a session-start transport — `tests/bats/test_mb_update_notify.bats:1161`
- Codex has no extension mechanism: native surface is experimental `userpromptsubmit`
  (danger-block only) + git-hooks-fallback capture — `adapters/codex.sh:66-103,360-365`
- Codex `/mb work` degrades to single-model `codex exec`; known bug: detached exec can
  fake completion — `scripts/mb-subinvoke-resolve.sh:120-129`, note
  disown-detached-codex-exec-fakes-completion
- No adapter manifest declares `platform_limited`; the contract supports it as an
  optional documented array — `adapters/_contract.sh:26-33`
- `/mb agree` reached all hosts with zero adapter work because it syncs through
  project-root AGENTS.md + wildcard `commands/*.md` — `scripts/mb-agree.sh:681-725`;
  the AGENTS.md/scripts channel is the proven parity-by-construction path
- Per-adapter bats suites exist (codex 39, opencode ~30, pi 13 tests) but none cover
  extension installation, update-notify absence, or negative parity assertions —
  `tests/bats/test_{codex,opencode,pi}_adapter.bats`

## Decision Log

- **D-01**: adapter-parity is a standalone spec and goes **first in the roadmap queue,
  ahead of donor v5.4.0** — the skill must work everywhere before the donor build-out.
  — Source: explicit user directive 2026-07-15 (AGR-012). Rejected: fold into
  install-parity backlog line (too big, needs its own triple); queue after donor
  (user overrode).
- **D-02**: Parity mechanism = **host-native extensions** (Pi TS extensions, OpenCode
  JS plugin) **offered opt-in** at install time and nudged during usage (`/mb doctor`,
  session-start notice where a transport exists). Never auto-installed; declining keeps
  today's install byte-identical. — Source: user directive (AGR-013) + design contract
  "defaults never change without explicit opt-in". Rejected: auto-install (violates
  contract); docs-only guidance (proven not to happen — the Pi extension sat uninstalled).
- **D-03**: Codex = honest degradation, not extension parity: no extension mechanism
  exists; scope for Codex is best-effort update-notify via its prompt hook, keeping
  git-hooks-fallback capture, and declaring `platform_limited` in the manifest.
  Rejected: skip Codex entirely (loses cheap honesty wins).
- **D-04**: Pi hooks build ON the existing `pi_session_memory_extension.ts` — wire its
  installation, do not rewrite it. Same for the graph-rag extension (promote to the
  global install offer).
- **D-05**: Subagent parity: both hosts get `agents/*.md` installed (Pi: new; OpenCode:
  add global scope). The dispatch mechanism per host is resolved by a research task
  first (Pi extension custom tools vs headless CLI spawn; OpenCode native agent
  invocation) — design must not assume an API that does not exist.
- **D-06**: update-notify renders on every host that has a session-start transport
  (CC hook, Pi extension, OpenCode plugin); Codex best-effort via prompt hook with the
  same TTL cache — never more than the existing ≤3-line notice, fail-open.
- **D-07**: Honesty layer ships in the same slice: `platform_limited` arrays in every
  adapter manifest + negative bats asserting "absent with a reason" for unsupported
  capabilities — parity regressions become catchable.

## Functional Requirements (EARS)

Offer & consent:

- **REQ-001** (event-driven): When installation targets the pi or opencode client, the system shall offer opt-in installation of the host parity extensions.
- **REQ-002** (unwanted): If the user declines the extension offer, then the system shall complete the installation without extensions and without behavior change.
- **REQ-003** (event-driven): When `/mb doctor` runs on a pi or opencode host without installed parity extensions, the system shall suggest the exact extension install command.
- **REQ-004** (ubiquitous): The system shall install host extensions only after explicit user consent.
- **REQ-005** (optional): Where a non-interactive installation passes the extensions flag, the system shall install the offered extensions without prompting.

Pi parity:

- **REQ-006** (event-driven): When the user accepts the Pi extension offer, the system shall install the session-memory extension into the resolved Pi extensions directory.
- **REQ-007** (optional): Where the Pi session-memory extension is installed, the system shall capture session start, per-turn, pre-compact and shutdown events into `session/*.md` using the same schema as Claude Code.
- **REQ-008** (event-driven): When installation targets the pi client, the system shall install the skill subagent definitions for Pi role dispatch.
- **REQ-009** (optional): Where the Pi parity extensions are installed, the system shall dispatch `/mb work` role agents through the mechanism selected by the host-API research task.
- **REQ-010** (event-driven): When the user accepts the Pi extension offer during global installation, the system shall install the graph-rag extension without requiring a separate project-local run.

OpenCode parity:

- **REQ-011** (event-driven): When the user accepts the OpenCode extension offer, the system shall install the parity plugin providing session-start context injection and per-turn session capture.
- **REQ-012** (ubiquitous): The system shall install skill subagent definitions for opencode at global scope in addition to project scope.

update-notify transports:

- **REQ-013** (state-driven): While a host has a session-start capable transport, the system shall render the update notice on session start on that host.
- **REQ-014** (optional): Where codex experimental hooks are enabled, the system shall render the update notice through the prompt-submit hook at most once per cache TTL window.

Honesty, lifecycle & tests:

- **REQ-015** (ubiquitous): The system shall record capabilities a host cannot support in the adapter manifest `platform_limited` array.
- **REQ-016** (ubiquitous): The system shall cover every extension install path with tests for installation, idempotent re-run and uninstallation.
- **REQ-017** (ubiquitous): The system shall assert through negative tests that unsupported host capabilities are reported as absent with a reason.
- **REQ-018** (event-driven): When `/mb upgrade` updates the skill, the system shall refresh installed host extensions to the bundled version.
- **REQ-019** (unwanted): If a host extension fails at runtime, then the system shall degrade to the pre-extension fallback behavior without blocking the session.

## Non-Functional Requirements

- **NFR-001**: A declined or unmodified install stays byte-identical to today's output (the REQ-009-style regression contract of this repo).
- **NFR-002**: No new runtime dependencies; extensions use only the host's own API surface; installers stay bash 3.2 compatible.
- **NFR-003**: All install/validate paths work offline; update-notify keeps its existing TTL cache and never blocks a session (fail-open).
- **NFR-004**: Extensions are single-sourced under `adapters/` — installers copy, never fork.

## Constraints + Out of Scope

Constraints: never auto-install extensions; protected files (`ci/`, `.github/workflows/`, `.env`) untouched; scoped `git add` only; user-modified installed extensions are backed up, never clobbered.

Out of scope: parity uplift for cursor/windsurf/cline/kilo (separate later slice); statusline on non-CC hosts (declared `platform_limited`); OpenSpec runtime (stays iceboxed, AGR-004); fixing the detached `codex exec` fake-completion bug (tracked separately).

## Edge Cases & Failure Modes

- Host CLI (pi/opencode) not present on the machine → offer is skipped with a one-line notice, install continues.
- Extensions directory missing/unwritable on accept → clear error naming the path, install of everything else completes.
- Non-interactive install without the extensions flag → no prompt, no extensions (default off).
- `/mb upgrade` finds a user-modified extension file → back up, replace, name the backup.
- OpenCode plugin API lacks a needed event (per-turn) → documented degraded capture tier, not silent absence.
- Parallel AGENTS.md ownership (refcount with codex/opencode/pi) must survive extension install/uninstall cycles.
