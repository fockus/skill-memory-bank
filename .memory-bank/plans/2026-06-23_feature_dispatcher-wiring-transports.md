---
type: feature
scope: dispatcher-wiring-transports
created: 2026-06-23
status: queued
priority: HIGH
backlog: I-084
linked_specs: [specs/dynamic-flow]
---

# Feature: Capability Dispatcher Wiring + Transports

Closes backlog **I-084** — the DOMINANT root cause (6/9 reviewers) in
`reports/2026-06-23_codex-gpt5.5-skill-review.md` §01/02/06/07/08/09: the
capability-aware dispatcher (`mb-agent-caps.sh` + the `dispatch:` block in
`references/pipeline.default.yaml`) is built and unit-tested but **never wired
into the execution path**, and the CLI transports (pi / opencode / codex) are
either non-executable or mis-resolved.

## Goal

Make the capability dispatcher real: the `dispatch.priority` / `prefer` /
`model_map` config must actually steer which CLI transport (pi / opencode /
codex / claude-agent) and which model runs a governed `/mb work` step, and a
pi/opencode/codex transport must produce a runnable sub-invoke command.

### Confirmed root cause (verified in code)

- **`mb-agent-caps.sh resolve` has ZERO callers.** `grep -rln mb-agent-caps`
  across `scripts/ commands/ hooks/` returns only the script itself. The
  execution path (`mb-work-plan.sh:184-200,319-321`) reads
  `roles.<role>.{agent,model,thinking}` straight from YAML and emits them into
  the JSONL dispatch lines — it never calls caps `resolve`. Therefore
  `dispatch.priority` / `prefer` / `model_map` / `enumerable` are **inert at
  runtime**. Central claim CONFIRMED.
- The `dispatch:` block ships with **empty defaults** (`prefer: {}`,
  `model_map: {}`, `fallback.claude-agent: {}`) and default `roles` carry **no
  `model:`** → even if wired, `resolve` exits 1 for every default role and the
  codex family is never preferred.
- `mb-subinvoke-resolve.sh` only knows `codex` + `claude-code`; pi/opencode fall
  to the fail-loud arm (exit 2) unless `MB_SUBINVOKE_CMD`/`--cmd` is supplied.

### Staging context (verified)

This is NOT vapor: the resolver, the `dispatch:` YAML contract, and **19 green
bats** (`tests/bats/test_mb_agent_caps.bats`) already exist. The dynamic-flow
spec's Phase 2 sub-invoke layer (`specs/dynamic-flow/tasks.md`) is also largely
done — **Task 12 (CC + Codex sub-invoke) is checked done**; **Task 13
(pi/opencode sub-invoke) is explicitly Phase 3, deferred, UNCHECKED** (`- [ ]`).
The caps/`dispatch:` machinery is a *separate, parallel* build from dynamic-flow
(dynamic-flow uses `mb-fanout.sh` + `mb-subinvoke-resolve.sh`, not caps), so
this plan does not belong to a single dynamic-flow task — it completes the
orphaned dispatcher AND pulls Task 13's pi/opencode sub-invoke forward.

### The fork

- **(A) COMPLETE the wiring** — finish the resolver, ship real `dispatch`
  defaults, add pi/opencode sub-invoke templates, and wire caps `resolve` into
  `mb-work-plan.sh` so pi/opencode/codex are selectable end-to-end.
- **(B) GATE transports as experimental** — leave caps unwired, de-advertise
  pi/opencode/codex routing in `work.md`/`SKILL.md`/`pipeline.default.yaml`
  comments, and mark `mb-agent-caps.sh` experimental until a later cycle.

### Recommendation: **(A) COMPLETE the wiring.**

Evidence: the expensive parts are already paid for. The resolver exists with 19
green hermetic tests; the `dispatch:` schema is documented and shipped; the
sub-invoke resolver already has the security seam, the model-id grammar guard,
and a CC+Codex table — adding pi/opencode is two `case` arms (≈ Task 13, already
spec'd). Choosing (B) would mean *deleting documented, tested capability the
project deliberately built across two work streams* and re-writing user-facing
docs to walk it back — strictly more churn than finishing the last-mile wiring.
The remaining work is correctness fixes + two `case` arms + one call site, not a
new subsystem (ADR-1′ "no standalone dispatcher rebuilt" still holds: we wire
the existing resolver, we do not build a daemon).

## Scope

### In scope
- Single pipeline-resolution path for caps + reviewer resolvers (via
  `mb-pipeline.sh path`).
- Resolver correctness: no-model tier fallback, parse-fail exit 2, `roles.<role>.agent`
  → `prefer`, codex probe correctness, opencode error-vs-empty, `enumerable: []`
  presence check, pi parser hardening.
- Real `dispatch` defaults in `references/pipeline.default.yaml` (prefer +
  model_map + default role models).
- pi + opencode sub-invoke templates in `mb-subinvoke-resolve.sh` + an
  `opencode.sh` `subinvoke` action.
- Wiring caps `resolve` into `mb-work-plan.sh` and emitting `transport` into the
  JSONL dispatch lines.

### Out of scope
- A new standalone dispatcher / daemon / durable journal (ADR-1′ forbids it).
- Native parallel-feature preference (dynamic-flow Task 13 REQ-DF-083) — separate.
- Changing `mb-fanout.sh` orchestration semantics.
- `critique`/`risk-find`/`final-report` skills (dynamic-flow Task 14).

## Assumptions
- `python3` + PyYAML are present in CI (the existing caps tests assume it; CI
  pins 3.11/3.12, local is 3.13 — verify fixes under 3.11 before claiming green).
- `codex debug models --bundled` is the real enumeration command; `codex
  --list-models` / `codex models` do NOT exist. **UNCONFIRMED against a live
  codex binary** — treated as a documented fact from the review; Stage 2.4
  hides it behind the trusted-non-enumerable path so a wrong subcommand never
  blocks resolution. If a live codex contradicts this, only the probe arm
  changes, not the contract.
- pi headless form is `pi -p --no-session --model <provider/model> "<prompt>"`
  and opencode is `opencode run --model <model> "<prompt>"`. **UNCONFIRMED
  against live binaries** — modelled on the existing CC/Codex templates and the
  pi/opencode adapter conventions; Stage 4 ships them behind the same
  single-quoted-heredoc seam so a wrong flag is a one-line fix, never a security
  hole.
- bash 3.2 (macOS default) AND bash 5.x must both pass; no associative arrays,
  no `${v^^}`.

## Risks
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Wiring caps into `mb-work-plan.sh` changes the JSONL contract → breaks existing consumers | Medium | High | `transport` is ADDITIVE; keep `agent`/`model`/`thinking` keys; add a test asserting old keys unchanged + claude-agent default reproduces today's values |
| Real `prefer`/`model_map` defaults route a default-role step to an absent CLI | Medium | Medium | `on_none_available: fallback` keeps claude-agent as the safety net; default role models map to a transport that falls through to claude-agent when absent |
| Live pi/opencode/codex flags differ from assumed | Medium | Medium | Templates emitted from single-quoted heredocs (no eval); model-id grammar guard already present; flags isolated to one `case` arm each |
| bash 3.2 regression from new array/string ops | Low | Medium | Run bats under `/bin/bash` (3.2) AND a 5.x bash in Stage gates |
| Default-role model with no `model_map` entry → caps uses contract id verbatim on a transport that rejects it | Medium | Low | Stage 3 ships `model_map` entries for every default contract model; enumerable transports still gate on availability |

---

## Stage 1: Single pipeline-resolution path (mb-pipeline.sh path)

**Complexity:** M
**Time:** ~5 min
**Dependencies:** —
**Agent:** mb-developer
**Files:**
- `scripts/mb-agent-caps.sh` (modify `resolve_pipeline_path`)
- `scripts/mb-reviewer-resolve.sh` (modify pipeline resolution block)
- `tests/bats/test_mb_agent_caps.bats` (extend)
- `tests/bats/test_mb_reviewer_resolve.bats` (extend; create if absent)

### Context (verified)
`mb-agent-caps.sh:89-107` and `mb-reviewer-resolve.sh:47-63` each re-implement a
2-step ladder (`<bank>/pipeline.yaml` → bundled default). They IGNORE
`MB_PIPELINE`, named pipelines under `<bank>/pipelines/`, `.mb-config`, and
host-binding — all of which `mb-pipeline.sh path` already implements (the 6-step
ladder, `mb-pipeline.sh:42-49`). Report §08.

### Tasks (TDD)
1. **RED first** — add to `test_mb_agent_caps.bats`: create
   `$BANK/pipelines/codexflow.yaml` with a distinct `roles.reviewer.model`,
   set `MB_PIPELINE=codexflow`, assert `resolve --role reviewer` reads the named
   pipeline (currently it ignores `$MB_PIPELINE` → fails). Mirror the same red
   test in `test_mb_reviewer_resolve.bats` asserting the reviewer agent comes
   from the named pipeline.
2. Replace the body of `resolve_pipeline_path` in `mb-agent-caps.sh` with a call
   to `bash "$script_dir/mb-pipeline.sh" path "$mb_arg"` (capture stdout; on
   non-zero exit, return 2 with the same `[caps] no pipeline.yaml` stderr).
3. Replace the `PROJECT_PIPELINE`/`DEFAULT_PIPELINE` ladder in
   `mb-reviewer-resolve.sh` (lines 51-63) with `PIPELINE_PATH=$(bash
   "$SCRIPT_DIR/mb-pipeline.sh" path "$MB_ARG")` (exit 2 on failure).
4. Keep `MB_PIPELINE` flowing: do not unset it; `mb-pipeline.sh path` reads it.

### DoD
- [ ] `mb-agent-caps.sh resolve` and `mb-reviewer-resolve.sh` both resolve their
      pipeline ONLY via `bash mb-pipeline.sh path` (no local 2-step ladder remains —
      `grep -c 'pipeline.default.yaml' scripts/mb-agent-caps.sh scripts/mb-reviewer-resolve.sh` → 0).
- [ ] With `MB_PIPELINE=codexflow` set and `<bank>/pipelines/codexflow.yaml`
      present, `resolve --role reviewer` reads `codexflow.yaml`'s model.
- [ ] Exit 2 preserved when no pipeline resolves at all.
- [ ] Tests: +2 bats (caps named-pipeline, reviewer named-pipeline); existing 19
      caps bats still green.
- [ ] `shellcheck scripts/mb-agent-caps.sh scripts/mb-reviewer-resolve.sh` clean.

### Test scenarios
- `test_caps_resolve_honors_MB_PIPELINE_named_pipeline` — named pipeline model wins over `<bank>/pipeline.yaml`.
- `test_reviewer_resolve_honors_MB_PIPELINE_named_pipeline` — reviewer agent from named pipeline.
- `test_caps_resolve_exit2_when_no_pipeline` — empty bank + missing default → exit 2.

### Commands
```bash
bash -n scripts/mb-agent-caps.sh scripts/mb-reviewer-resolve.sh
shellcheck scripts/mb-agent-caps.sh scripts/mb-reviewer-resolve.sh
/bin/bash $(command -v bats) tests/bats/test_mb_agent_caps.bats
/bin/bash $(command -v bats) tests/bats/test_mb_reviewer_resolve.bats
```

### Edge cases
- `mb-pipeline.sh path` exit 3 (named pipeline requested but missing) → caps must
  surface as exit 2 (config error), not swallow to claude-agent fallback.
- Existing callers of caps `resolve` with a plain bank dir (no named pipelines)
  must behave byte-identically (legacy → bundled default).

---

## Stage 2: Resolver correctness (six bugs)

**Complexity:** L (split into 2.1–2.6 sub-tasks; each ≤ 5 min, commit per sub-task)
**Time:** ~5 min each
**Dependencies:** Stage 1
**Agent:** mb-developer
**Files:**
- `scripts/mb-agent-caps.sh`
- `tests/bats/test_mb_agent_caps.bats`

### 2.1 — No-model role → tier fallback, not exit 1 (report §02)
Default roles have no `model:` → `emit_role_facts` prints empty `contract=`, and
`cmd_resolve:210` exits 1. Fix: when `contract` is empty, skip the
transport-selection loop and go straight to the claude-agent tier fallback
(`xhigh_roles → opus, else sonnet`) when `on_none != error`.
- **RED:** `test_caps_resolve_empty_contract_falls_back_to_tier` — bank with
  `roles: { reviewer: { agent: mb-reviewer } }` (no model), empty fixture →
  expect `transport=claude-agent`, `model=opus`, `substituted=true`, exit 0.
- **RED:** same with `on_none_available: error` → exit 3 (not 1).
- Fix: in `cmd_resolve`, replace the `[ -z "$contract" ]` exit-1 block with the
  empty-contract fallback path; keep exit 1 only for the truly-unknown-role case
  (role block absent entirely — distinguish via a `role_present` fact from
  `emit_role_facts`).

### 2.2 — YAML parse error → exit 2, not swallowed to {} (report §07)
`emit_role_facts:118-122` catches every `yaml.safe_load` exception as `data={}`,
so a malformed pipeline looks like "role has no model" → misleading exit 1
instead of the documented parse-fail exit 2.
- **RED:** `test_caps_resolve_malformed_yaml_exits_2` — write `pipeline.yaml`
  with a tab-indent / unbalanced bracket; expect exit 2 + stderr mentioning
  parse failure.
- Fix: in the python heredoc, on `yaml.safe_load` exception write the error to
  `sys.stderr` and `sys.exit(2)`; propagate 2 out of `cmd_resolve` (capture the
  python exit code; do not let `while read` mask it).

### 2.3 — `roles.<role>.agent` transport-like value → prefer (report §06)
`agent: codex-cli` (a transport, not an Agent-tool name) is ignored by caps →
resolves to claude-agent/opus. Fix: translate a transport-like `roles.<role>.agent`
into an implicit `prefer` for that transport.
- **RED:** `test_caps_resolve_transport_like_agent_routes_via_prefer` — bank role
  `reviewer: { agent: codex, model: openai-codex/gpt-5.5 }`, fixture
  `transport codex` → expect `transport=codex`.
- Fix: in `emit_role_facts`, if `role_block.agent` matches a known transport
  (`pi|opencode|codex|claude-agent`, or `*-cli` stripped), emit it as the
  highest-priority `prefer` token; otherwise ignore (it is an Agent-tool name).

### 2.4 — codex probe uses non-existent CLI commands (report §08)
`caps_models:63` calls `codex --list-models` / `codex models` — neither exists
(actual: `codex debug models`). codex is in `enumerable: [pi, opencode]` → NOT
enumerable by default → already "trusted", so the wrong command is masked TODAY,
but it fires the moment a project adds codex to `enumerable`.
- **RED:** `test_caps_codex_probe_empty_unless_debug_models` — fake `codex` on
  PATH that errors on `--list-models`/`models` but prints a table for `debug
  models --bundled`; with codex NOT enumerable, `detect` shows codex
  `models=0` (trusted, no probe); with codex enumerable, the probe parses
  `codex debug models --bundled`.
- Fix: replace the codex arm with
  `codex debug models --bundled 2>/dev/null | <parser> || true`; keep codex out
  of default `enumerable` so it stays trusted by default.

### 2.5 — opencode probe: error vs empty list (report §09)
`caps_models:59` runs `opencode models 2>/dev/null || true` → a command FAILURE
(opencode crash) is indistinguishable from "no models". Under
`on_none_available: error` this silently falls back instead of failing.
- **RED:** `test_caps_opencode_command_failure_distinct_from_empty` — fake
  `opencode` that exits 1; with `on_none_available: error` → exit 3 + stderr
  naming the probe failure (not a silent claude-agent fallback).
- Fix: capture opencode exit status separately; on non-zero exit treat as
  "transport unavailable" and, under `on_none: error`, fail with a probe-error
  message distinct from "no model offered".

### 2.6 — `enumerable: []` impossible + pi parser hardening (report §10/11, MINOR)
- `enumerable` falsiness: `dispatch.get("enumerable") or ["pi","opencode"]`
  (line 134) treats an explicit `[]` as absent. Fix: `enumerable =
  dispatch["enumerable"] if "enumerable" in dispatch else ["pi","opencode"]`
  (key-presence, not truthiness).
- pi parser: `caps_models:62` parses any `NF>=2` line as a model and only skips
  the header at `NR==1`; malformed stdout becomes phantom models. Fix: only emit
  rows AFTER the `provider model` header is seen, and validate
  `provider` and `model` against `^[A-Za-z0-9._-]+$`.
- **RED:** `test_caps_enumerable_empty_disables_strict_check` — `enumerable: []`
  + codex present + chatgpt contract → codex (trusted) chosen even though
  nothing is enumerable.
- **RED:** `test_caps_pi_parser_skips_garbage_rows` — fake pi printing a banner
  line + a blank line + the header + two valid rows → exactly 2 models counted.

### DoD (Stage 2 overall)
- [ ] Empty-contract role → claude-agent tier fallback (opus/sonnet) exit 0;
      `on_none=error` → exit 3; truly-unknown role still exit 1.
- [ ] Malformed YAML → exit 2 with stderr (documented contract honored).
- [ ] Transport-like `roles.<role>.agent` routes via `prefer`.
- [ ] codex probe uses `codex debug models --bundled`; codex trusted by default
      (not in `enumerable`).
- [ ] opencode command-failure distinguishable from empty list; fails under
      `on_none=error`.
- [ ] `enumerable: []` honored via key-presence; pi parser validates header +
      provider/model regex.
- [ ] Tests: +8 bats (one per sub-task + the two parser/enumerable cases);
      all 19 prior caps bats still green.
- [ ] `shellcheck scripts/mb-agent-caps.sh` clean; bash 3.2 + 5.x both pass.

### Commands
```bash
shellcheck scripts/mb-agent-caps.sh
/bin/bash $(command -v bats) tests/bats/test_mb_agent_caps.bats      # bash 3.2
bash5() { /opt/homebrew/bin/bash "$@" 2>/dev/null || /usr/local/bin/bash "$@"; }
bash5 $(command -v bats) tests/bats/test_mb_agent_caps.bats          # bash 5.x
```

### Edge cases
- A role present with `model: ""` (explicit empty) vs role-block absent — both
  must NOT exit 1 for the "no model" case; only an absent role block is exit 1.
- python exit code 2 must propagate through the `while IFS= read -r line` loop
  (capture via `set -o pipefail` is already on; verify the subshell exit reaches
  `cmd_resolve`).

---

## Stage 3: Default pipeline routing defaults

**Complexity:** M
**Time:** ~4 min
**Dependencies:** Stage 2
**Agent:** mb-developer
**Files:**
- `references/pipeline.default.yaml` (lines 10-34 roles, 291-309 dispatch)
- `tests/bats/test_mb_agent_caps.bats`
- `scripts/mb-pipeline-validate.sh` (verify the new defaults still validate)

### Context (verified)
`dispatch.prefer: {}`, `model_map: {}`, `fallback.claude-agent: {}` are empty
(lines 298,305,309) and `priority` excludes codex (line 292) → the codex family
is never routed by default. Default roles (lines 11-34) carry no `model:` →
`resolve` had no contract (now tier-fallback after Stage 2.1, but still never
reaches a transport). Report §01.

### Tasks (TDD)
1. **RED first** — add a bats that runs `resolve --role reviewer` against the
   BUNDLED default (`--mb` pointing at an empty bank so the default is used) with
   a fixture offering `transport codex`, and asserts `transport=codex` for the
   reviewer contract. Today it cannot (no prefer, no default model) → fails.
2. Ship real `dispatch` defaults:
   - `prefer: { "openai-codex/*": codex, "gpt-*": codex }`
   - `model_map: { "openai-codex/gpt-5.5": { codex: gpt-5.5, opencode: opencode/gpt-5.2 } }`
     (one concrete entry per default contract model added in step 3).
   - keep `priority: [pi, opencode, claude-agent]` (codex reached via `prefer`,
     matching the existing test at `test_mb_agent_caps.bats:111`).
3. Give the review/judge/planner/architect roles a default contract `model:` so
   `prefer` can match (e.g. `reviewer: { agent: mb-reviewer, model: openai-codex/gpt-5.5, ... }`)
   — choose a model present in `model_map`. Non-codex roles MAY stay model-less
   (Stage 2.1 tier-fallback covers them).
4. Re-run `mb-pipeline-validate.sh` against the edited default.

### DoD
- [ ] `references/pipeline.default.yaml` ships non-empty `prefer` + `model_map`;
      `prefer` routes `openai-codex/*` and `gpt-*` to codex.
- [ ] A default-pipeline `resolve --role reviewer` with codex present →
      `transport=codex`, mapped `model=gpt-5.5`, `substituted=false`.
- [ ] `bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml` →
      exit 0.
- [ ] Tests: +1 bats (default-pipeline codex routing); existing dispatch-block
      tests still green.
- [ ] Diff to `pipeline.default.yaml` touches only `roles` model fields +
      `dispatch.prefer`/`model_map` (no workflow/budget churn).

### Test scenarios
- `test_default_pipeline_resolve_reviewer_routes_codex` — empty bank → bundled default → codex.
- `test_default_pipeline_validates` — validator exit 0 after edit.

### Commands
```bash
bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml
/bin/bash $(command -v bats) tests/bats/test_mb_agent_caps.bats
```

### Edge cases
- A project that copied the OLD empty `dispatch` block via `/mb config init` must
  still work (their override wins; the new defaults only apply to projects on the
  bundled file). No migration required — document in the dispatch comment.

---

## Stage 4: Subinvoke pi/opencode templates

**Complexity:** M
**Time:** ~5 min
**Dependencies:** —  (parallelizable with Stages 1-3)
**Agent:** mb-developer
**Files:**
- `scripts/mb-subinvoke-resolve.sh` (add `pi` + `opencode` `case` arms; update header)
- `adapters/opencode.sh` (add a `subinvoke` action to the `case "$ACTION"` at line 216)
- `tests/bats/test_mb_subinvoke_resolve.bats` (extend)

### Context (verified)
`mb-subinvoke-resolve.sh:114-150` has only `codex` + `claude-code` arms; pi and
opencode hit the fail-loud `*)` arm (exit 2). The header (lines 23-42) explicitly
marks pi/opencode as "Task 13" extension points "INTENTIONALLY absent". This is
dynamic-flow Task 13 DoD line 1 (`adapters/{pi,opencode}.sh declare their
sub-invoke command`), unchecked. Report §02. `adapters/opencode.sh` already
dispatches on `ACTION` (line 216) but has no `subinvoke` action.

### Tasks (Contract-First + TDD)
1. **Contract** — the pi/opencode templates obey the SAME seam as codex/cc:
   the prompt reaches the template ONLY via the literal `$MB_FANOUT_PROMPT`
   token (single-quoted heredoc / `printf` with a literal token); only the
   trusted model is interpolated, after the existing model-id grammar guard
   (lines 106-113). This is the transport sub-invoke contract — identical
   guarantees across all four agents.
2. **RED first** — add to `test_mb_subinvoke_resolve.bats`:
   - `--agent pi` with no `MB_SUBINVOKE_CMD` → exit 0, output contains
     `pi -p` + `--no-session` + `--model` + literal `$MB_FANOUT_PROMPT` (assert
     the token is LITERAL, not expanded).
   - `--agent pi MB_SUBINVOKE_MODEL=openai-codex/gpt-5.5` → model interpolated.
   - `--agent pi MB_SUBINVOKE_MODEL='a b'` → exit 1 (grammar guard).
   - `--agent opencode` → `opencode run --model <m> "$MB_FANOUT_PROMPT"` form.
   - `MB_SUBINVOKE_CMD` override still wins for pi/opencode.
3. Add the `pi` arm:
   `printf 'pi -p --no-session --model "%s" "$MB_FANOUT_PROMPT"\n' "$SUB_MODEL"`
   with `[ -n "$SUB_MODEL" ] || SUB_MODEL="openai-codex/gpt-5.5"` (a default in
   `model_map`). Keep the `# shellcheck disable=SC2016` seam comment.
4. Add the `opencode` arm:
   `printf 'opencode run --model "%s" "$MB_FANOUT_PROMPT"\n' "$SUB_MODEL"` with
   a sensible `opencode/...` default.
5. Update the header (lines 23-42) to drop "Task 13 INTENTIONALLY absent" and
   document the four supported agents.
6. Add an `opencode.sh` `subinvoke` action that prints the resolved template by
   delegating to `mb-subinvoke-resolve.sh --agent opencode` (mirror how codex.sh
   surfaces its sub-invoke, if it does; otherwise a thin pass-through).

### DoD
- [ ] `mb-subinvoke-resolve.sh --agent pi` and `--agent opencode` each emit a
      runnable template (exit 0) carrying the literal `$MB_FANOUT_PROMPT` token.
- [ ] The model-id grammar guard rejects a malformed `MB_SUBINVOKE_MODEL` for
      pi/opencode (exit 1) before emission.
- [ ] `MB_SUBINVOKE_CMD` override still wins for pi/opencode (authoritative).
- [ ] `adapters/opencode.sh subinvoke` prints the opencode template.
- [ ] Header no longer claims pi/opencode are absent.
- [ ] Tests: +6 bats; existing subinvoke bats still green.
- [ ] `shellcheck scripts/mb-subinvoke-resolve.sh adapters/opencode.sh` clean;
      bash 3.2 + 5.x both pass.

### Test scenarios
- `test_subinvoke_pi_default_template_has_literal_prompt_token`
- `test_subinvoke_pi_interpolates_valid_model`
- `test_subinvoke_pi_rejects_malformed_model`
- `test_subinvoke_opencode_default_template`
- `test_subinvoke_override_wins_for_pi`
- `test_opencode_adapter_subinvoke_action_prints_template`

### Commands
```bash
bash -n scripts/mb-subinvoke-resolve.sh adapters/opencode.sh
shellcheck scripts/mb-subinvoke-resolve.sh adapters/opencode.sh
/bin/bash $(command -v bats) tests/bats/test_mb_subinvoke_resolve.bats
```

### Edge cases
- A model id containing `/` (e.g. `openai-codex/gpt-5.5`) must PASS the grammar
  guard (`/` is allowed) — verify the pi default does not trip it.
- The literal-token assertion must check the emitted string contains the bytes
  `$MB_FANOUT_PROMPT` UNEXPANDED (use single-quote matching in bats).

---

## Stage 5: Wire caps into mb-work-plan dispatch + transport in JSONL

**Complexity:** L
**Time:** ~5 min
**Dependencies:** Stages 1, 2, 3 (resolver correct + defaults); Stage 4 for the
runnable transport command, but the wiring itself only needs the resolver.
**Agent:** mb-backend
**Files:**
- `scripts/mb-work-plan.sh` (the python emit block, lines 158-348)
- `commands/work.md` (JSONL schema §, lines 226-266; dispatch step 5a)
- `tests/bats/test_mb_work_plan.bats` (extend) — verify path with `ls tests/bats/`

### Context (verified)
`mb-work-plan.sh:319-321` sets `agent/model/thinking` from
`ROLE_AGENT/ROLE_MODEL/ROLE_THINKING` (raw YAML `roles`). It never calls caps.
The JSONL has no `transport` key (`work.md:230-245` schema). Report §01 BLOCKER.

### Tasks (TDD)
1. **RED first** — add to `test_mb_work_plan.bats`: a bank whose
   `pipeline.yaml` has a `dispatch` block with `prefer: { "openai-codex/*": codex }`
   and a reviewer-ish role mapped to a chatgpt contract, plus a plan/spec with a
   matching stage; with a caps fixture/PATH making codex present, assert the
   emitted JSON Line contains `"transport":"codex"` and the caps-resolved
   `model`. Today there is no `transport` key → fails.
2. **RED first** — a second test: with NO transport available (empty fixture),
   the JSON Line carries `"transport":"claude-agent"` and the SAME
   `agent`/`model`/`thinking` the code emits today (regression guard — old keys
   unchanged).
3. In the `mb-work-plan.sh` python block, for each item AFTER `role` is decided,
   shell out to `mb-agent-caps.sh resolve --role <role> --mb <bank>` (pass the
   resolved pipeline through `MB_PIPELINE` so caps reads the SAME file):
   - parse `transport=`, `model=`, `thinking=`, `substituted=`;
   - set `obj["transport"]`; OVERRIDE `obj["model"]`/`obj["thinking"]` with the
     caps-resolved values when present;
   - keep `obj["agent"]` from the role→agent map (the Agent-tool name stays the
     identity for claude-agent dispatch; `transport` is the new routing axis).
4. Fail-open: if caps `resolve` exits non-zero, fall back to the current raw
   behaviour (`transport="claude-agent"`, existing model/thinking) and emit a
   stderr WARN — never break the JSONL stream. (caps exit 2 = config error
   should still surface a WARN but not abort the whole plan emission.)
5. Update `work.md`: add `transport` to the JSONL schema table + the example,
   and in dispatch step 5a note that a non-`claude-agent` `transport` means the
   step runs via the resolved sub-invoke command (`mb-subinvoke-resolve.sh
   --agent <transport>`), not the Claude Code Task tool.

### DoD
- [ ] Every JSON Line from `mb-work-plan.sh` carries a `transport` key
      (`pi|opencode|codex|claude-agent`).
- [ ] `transport` is caps-resolved: a chatgpt-contract role with codex present →
      `"transport":"codex"`; nothing available → `"transport":"claude-agent"`.
- [ ] Existing keys `agent`/`model`/`thinking`/`status`/`source`/`kind`/`covers`
      unchanged for the claude-agent default path (regression test green).
- [ ] caps non-zero exit → fail-open to claude-agent + stderr WARN; JSONL stream
      never aborts mid-plan.
- [ ] caps reads the SAME pipeline as `mb-work-plan` (MB_PIPELINE threaded).
- [ ] `work.md` JSONL schema + example + dispatch step document `transport`.
- [ ] Tests: +2 bats (transport=codex routing, claude-agent regression);
      existing `test_mb_work_plan.bats` green.
- [ ] `shellcheck scripts/mb-work-plan.sh` clean; `python3 -c` syntax check of
      the heredoc passes under 3.11.

### Test scenarios
- `test_work_plan_emits_transport_codex_for_chatgpt_role`
- `test_work_plan_transport_claude_agent_preserves_legacy_keys`
- `test_work_plan_caps_failure_fails_open_to_claude_agent`

### Commands
```bash
bash -n scripts/mb-work-plan.sh
shellcheck scripts/mb-work-plan.sh
/bin/bash $(command -v bats) tests/bats/test_mb_work_plan.bats
```

### Edge cases
- A spec task with an explicit `**Role:** developer` (no model) → caps tier
  fallback → `transport=claude-agent`, `model=sonnet`; must NOT exit 1 (relies
  on Stage 2.1).
- `--dry-run` output must still print without invoking caps per item more than
  necessary (acceptable to call caps; just don't double-emit).
- Performance: caps is invoked once per work item (a subprocess each) — for a
  large plan this is N python launches. Acceptable for now (work items are few);
  note as a follow-up if a plan has > ~30 items.

---

## Dependency graph

```
Stage 1 (single pipeline path)
   │
   ├──> Stage 2 (resolver correctness)
   │        │
   │        └──> Stage 3 (default routing defaults)
   │                  │
Stage 4 (pi/opencode subinvoke)  [parallel — no dep on 1/2/3]
   │                  │
   └────────┬─────────┘
            └──> Stage 5 (wire caps into mb-work-plan + transport JSONL)
```

## Parallelization
| Phase | Stages | Agents |
|-------|--------|--------|
| 1 | 1, 4 | mb-developer (S1), mb-developer-2 (S4) |
| 2 | 2 | mb-developer (S1's file owner) |
| 3 | 3 | mb-developer |
| 4 | 5 | mb-backend |

Stage 4 touches only `mb-subinvoke-resolve.sh` + `opencode.sh` + its bats — no
overlap with Stages 1-3 (which own `mb-agent-caps.sh` / `mb-reviewer-resolve.sh`
/ `pipeline.default.yaml`), so it runs fully in parallel from the start.

## Potential merge conflicts
- Stages 1 and 2 both edit `scripts/mb-agent-caps.sh` → SERIALIZE (1 before 2);
  one owner.
- Stages 1, 2, 3 all extend `tests/bats/test_mb_agent_caps.bats` → append-only
  additions per stage; serialize the bats edits to avoid hunk conflicts.
- Stage 5 edits `commands/work.md` (JSONL schema) — no other stage touches it.

## Verification (whole feature)
- `bash scripts/mb-agent-caps.sh resolve --role reviewer --mb /tmp/emptybank`
  against the BUNDLED default succeeds (exit 0) and, with codex present, prints
  `transport=codex` (routes the codex family by default) — the headline gate.
- `bash scripts/mb-subinvoke-resolve.sh --agent pi` and `--agent opencode` each
  print a runnable command carrying the literal `$MB_FANOUT_PROMPT` token.
- `bash scripts/mb-work-plan.sh --target <plan> --mb <bank>` emits JSON Lines
  each carrying a caps-resolved `transport`.
- Full suites green: `bats tests/bats/test_mb_agent_caps.bats
  test_mb_subinvoke_resolve.bats test_mb_work_plan.bats
  test_mb_reviewer_resolve.bats` under bash 3.2 AND 5.x.
- `shellcheck` clean on every modified `.sh`.
- `bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml` exit 0.

## DoD (feature)
- [ ] `mb-agent-caps.sh resolve` is CALLED by `mb-work-plan.sh` (no longer dead
      code) — `grep -l mb-agent-caps scripts/mb-work-plan.sh` matches.
- [ ] `dispatch.priority`/`prefer`/`model_map` measurably steer the emitted
      `transport`/`model` (proven by the headline gate + the work-plan tests).
- [ ] pi, opencode, codex each have a runnable sub-invoke template.
- [ ] Default pipeline routes the codex family by default (real `prefer` +
      `model_map`); no default role exits 1 (tier fallback).
- [ ] Resolver correctness: parse-fail exit 2, opencode error≠empty, codex probe
      uses `codex debug models`, `enumerable: []` honored, pi parser hardened,
      transport-like `agent` → prefer.
- [ ] All resolvers resolve their pipeline ONLY via `mb-pipeline.sh path`
      (MB_PIPELINE / named pipelines / host-binding honored).
- [ ] JSONL `transport` key documented in `work.md`; legacy keys unchanged.
- [ ] Net new tests: ≥ 19 bats across the four test files; full suites green
      under bash 3.2 + 5.x.
- [ ] Every modified `.sh` ≤ 400 lines, shellcheck clean, no placeholders.

## Checklist (copy into checklist.md)
- ⬜ I-084 Stage 1: single pipeline-resolution path (mb-pipeline.sh path) in caps + reviewer resolvers
- ⬜ I-084 Stage 2: resolver correctness — no-model fallback, parse-exit-2, agent→prefer, codex probe, opencode error≠empty, enumerable[], pi parser
- ⬜ I-084 Stage 3: real dispatch defaults (prefer + model_map + default role models) in pipeline.default.yaml
- ⬜ I-084 Stage 4: pi + opencode sub-invoke templates + opencode.sh subinvoke action
- ⬜ I-084 Stage 5: wire caps resolve into mb-work-plan + transport in JSONL
