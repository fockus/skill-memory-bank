# Tasks: adapter-parity

> Numbered, checkbox-tracked work items. Each task references the REQ-IDs it
> satisfies via the Covers field.
>
> Dependency order: T1 (host-API research) gates T4/T5 design choices; T2 (offer
> plumbing) gates T3/T4/T5 install paths; T6/T7 are independent after T2; T8 last.
> Global invariant (NFR-001): a DECLINED install stays byte-identical to today's
> adapter output — T2 authors the regression fixture, every later task keeps it green.

<!-- mb-task:1 -->
## Task 1: Host-API research — Pi dispatch + OpenCode plugin events

**Covers:** REQ-009, REQ-011, REQ-022
**Role:** researcher

**What to do:**
- Establish with evidence (docs/source/experiment): (a) Pi's viable subagent-dispatch
  mechanism — native agent registry vs extension tool spawning headless `pi -p --agent`
  (D-09: headless spawn is built even if slow — T1 picks the best mechanism and
  measures, it does not gate the feature); (b) which OpenCode plugin events exist for
  session-start injection and per-turn capture (exact event names + payloads);
  (c) whether the Pi extension API supports registering native slash commands for the
  `/mb` surface (REQ-022, D-12); (d) whether either host exposes a prompt-submit
  surface usable for semantic-recall later.
- Write findings + the selected mechanism per host into `design.md` (replace the T1
  placeholders) and a short note under `.memory-bank/notes/`.

**Testing (TDD — tests BEFORE implementation):**
- N/A (research task) — DoD is evidence quality: every claim carries a doc link or a
  reproducible experiment transcript; no "probably".

**DoD:**
- [ ] Pi dispatch mechanism selected with evidence; OpenCode event map documented.
- [ ] design.md updated; infeasible capabilities routed to `platform_limited` explicitly.

<!-- mb-task:2 -->
## Task 2: Extension offer plumbing (interactive + flag + CI-safe)

**Covers:** REQ-001, REQ-002, REQ-004, REQ-005, REQ-020
**Role:** backend

**What to do:**
- `install.sh`: when the client list includes pi/opencode — TTY prompt (default N);
  `--with-extensions[=pi,opencode]` flag + `MB_WITH_EXTENSIONS` env for non-interactive
  accept; no TTY + no flag → silent skip. Manifest records `extensions_installed`.
- `/mb install` command doc: surface the offer in the AskUserQuestion flow.
- Session-start nudge (D-08): the pi/opencode AGENTS.md managed block gains a one-line
  instruction — on a bare host (no parity extensions), suggest the install command once
  per session, silent after install (REQ-020).

**Testing (TDD — tests BEFORE implementation):**
- Declined/silent path → **byte-identical fixture**: diff installed tree vs pre-spec
  output (this is the NFR-001 regression guard reused by all later tasks).
- Flag/env accept → extensions land, manifest lists them; prompt never shown without TTY.

**DoD:**
- [ ] Offer works interactive + flag + CI; declined path byte-identical; manifest honest.
- [ ] bats pass · shellcheck clean · bash 3.2.

<!-- mb-task:3 -->
## Task 3: Pi session-memory + graph-rag extensions installed on accept

**Covers:** REQ-003, REQ-006, REQ-007, REQ-010, REQ-013, REQ-019
**Role:** backend

**What to do:**
- `adapters/pi.sh` + global install path: on accept, install
  `pi_session_memory_extension.ts` (currently dead code — wire, don't rewrite) and
  `pi_graph_rag_extension.ts` into the resolved Pi extensions dir with placeholder
  substitution; session_start handler renders update-notify via `mb-update-notify.sh`.
- Extend `mb-session-doctor.sh` Pi check to print the exact install command.

**Testing (TDD — tests BEFORE implementation):**
- Install → both `.ts` present, no `__MB_` placeholders (extend the runtime-parity suite).
- Simulated Pi turn (extension harness) → `session/*.md` with CC v2 schema fields.
- Extension failure (broken python path) → session continues, fallback intact (REQ-019).

**DoD:**
- [ ] Pi session memory alive end-to-end; update-notify renders on Pi session start.
- [ ] bats (incl. new runtime-parity Pi case) pass · shellcheck clean.

<!-- mb-task:4 -->
## Task 4: Pi subagent definitions + role dispatch

**Covers:** REQ-008, REQ-009, REQ-022
**Role:** backend

**What to do:**
- Install `agents/*.md` for the pi client (mirror the opencode partial-exclusion logic).
- Implement the T1-selected dispatch mechanism (headless `pi -p --agent` spawn is the
  guaranteed floor per D-09); register it in `mb-subinvoke-resolve.sh` (single
  registry); `/mb work` role routing resolves on Pi.
- If T1 confirmed Pi command registration (REQ-022): register the `/mb` command surface
  in the parity extension; otherwise document prompts-tier in `platform_limited`.

**Testing (TDD — tests BEFORE implementation):**
- Install → agents present in the Pi location, partials excluded, manifest lists them.
- Dispatch resolver returns the Pi mechanism; dispatch failure → inline-execution
  warning, never silent drop.

**DoD:**
- [ ] Pi gets the full agent roster + working `/mb work` role dispatch per T1 decision.
- [ ] bats pass · shellcheck clean.

<!-- mb-task:5 -->
## Task 5: OpenCode parity plugin + global agents

**Covers:** REQ-011, REQ-012, REQ-013, REQ-019
**Role:** backend

**What to do:**
- Extend the OpenCode plugin per T1 event map: session-start context injection +
  update-notify render; per-turn capture writing `session/*.md` (or the documented
  degraded tier if the API lacks per-turn — then `platform_limited`).
- Add global-scope agents: `~/.config/opencode/agent/*.md` in
  `install_opencode_global_agents`.

**Testing (TDD — tests BEFORE implementation):**
- Node harness (extend the existing B4-style functional test): simulated session →
  `session/*.md` created; session-start handler invokes the update-notify hook.
- Global install → agents in `~/.config/opencode/agent/`, project scope unchanged.
- Plugin handler throw → session unaffected (REQ-019).

**DoD:**
- [ ] OpenCode session memory alive (or degraded tier declared); global agents installed.
- [ ] bats pass · shellcheck clean.

<!-- mb-task:6 -->
## Task 6: Codex honest tier — prompt-hook update-notify

**Covers:** REQ-014, REQ-019
**Role:** backend

**What to do:**
- `adapters/codex.sh` before-prompt hook: TTL-gated call to
  `mb-version-check.sh --cache-only` render (≤3 lines, once per TTL window,
  `MB_UPDATE_CHECK=off` honored, fail-open).

**Testing (TDD — tests BEFORE implementation):**
- Stale version + empty cache → notice once; second prompt within TTL → silent.
- `MB_UPDATE_CHECK=off` → no output, no network; check failure → prompt proceeds.

**DoD:**
- [ ] Codex users see release notices without any new transport claims.
- [ ] bats pass · shellcheck clean.

<!-- mb-task:7 -->
## Task 7: platform_limited manifests + negative parity tests

**Covers:** REQ-015, REQ-017, REQ-021
**Role:** qa

**What to do:**
- Add `platform_limited` arrays (closed vocabulary from design.md) to **all 8 client
  adapter manifests** (D-10) — extension machinery stays focused on pi/opencode/codex,
  the honesty layer does not.
- New bats suite: for every declared limit, assert the capability is genuinely absent
  AND the reason is discoverable (manifest or doctor output) — the pair is the guard.
- Cursor positive parity check (REQ-021): tests proving cursor renders update-notify
  and captures sessions at the CC tier (it wires the same hooks — prove, don't assume).

**Testing (TDD — tests BEFORE implementation):**
- The negative suite itself IS the deliverable; plus a meta-test: a manifest limit
  without a matching negative assertion fails the suite.

**DoD:**
- [ ] Every adapter manifest declares its limits; every limit has a negative test.
- [ ] bats pass · shellcheck clean.

<!-- mb-task:8 -->
## Task 8: Upgrade refresh + docs

**Covers:** REQ-016, REQ-018
**Role:** developer

**What to do:**
- `mb-upgrade.sh` / re-install path: refresh installed extensions to the bundled
  version; user-modified file → timestamped backup, then replace, name the backup.
- Docs: `docs/cross-agent-setup.md` parity matrix updated (extension tiers, offer
  flags, platform_limited vocabulary); README client table refreshed.

**Testing (TDD — tests BEFORE implementation):**
- Upgrade over an installed extension → new content; over a user-modified one →
  backup exists + replaced; uninstall removes extensions + manifest entries (REQ-016
  closure across T3/T4/T5 paths).

**DoD:**
- [ ] Upgrade/uninstall lifecycle complete for every extension path; docs match reality.
- [ ] bats pass · shellcheck clean · docs grep-guard green.
