---
type: feature
topic: rule-profiles-and-stack-presets
status: queued
parallel_safe: false
depends_on: [2026-05-21_feature_global-storage-agent-support.md]
linked_specs: []
sprint: Sprint 3
phase_of: global-storage
---

# Plan: feature — rule-profiles-and-stack-presets

**Baseline commit:** f16e5715854828431fe5820c10d0ad062e4f9892

## Context

**Problem:** Global quality rules must keep working when a project intentionally has no Memory Bank, but real projects use different architectural styles and stack-specific practices. A single hard-coded ruleset cannot fit Clean Architecture, modular monolith, microservices, DDD, API-first, Contract-first, SDD, FSD, mobile UDF, Go, Python, JS/TS and Java equally well.

**Expected result:** Memory Bank supports configurable rule profiles with role presets and stack presets without increasing prompt bloat or weakening safety rules. Users can choose an immutable baseline plus configurable backend/frontend/mobile role presets and Go/Python/JavaScript/TypeScript/Java stack presets. In projects without Memory Bank, global user profiles still personalize rules-only mode. In projects with local or global Memory Bank, project profiles override user defaults explicitly and are consumed by planning, review, `/mb work`, and rules checks through compact resolved summaries.

**Dependency:** Execute after Sprint 1 (`global-storage-core`) and Sprint 2 (`global-storage-agent-support`) because profiles must work across local/global/rules-only storage and all supported agents.

## Requirements by example

| Scenario | Input | Expected behavior |
|----------|-------|-------------------|
| Backend Go API | Profile: `role=backend`, `stack=go`, `architecture=microservices`, `delivery=contract-first`, `api=protobuf` | Rules emphasize interface boundaries, context propagation, goroutine safety, protobuf compatibility, contract tests before implementation. |
| Frontend TS app | Profile: `role=frontend`, `stack=typescript`, `architecture=fsd`, `delivery=sdd+tdd` | Rules emphasize FSD import direction, public slice APIs, accessibility, component tests, contract with backend API mocks. |
| Mobile Android | Profile: `role=mobile`, `stack=kotlin`, `architecture=mobile-udf`, `delivery=api-first` | Rules emphasize UDF, immutable UI state, ViewModel/UseCase/Repository boundaries, offline behavior, API schema compatibility. |
| Python data service | Profile: `role=backend`, `stack=python`, `architecture=modular-monolith`, `delivery=tdd` | Rules emphasize type hints, dependency injection, module boundaries, pytest integration tests, no business logic mocks. |
| Java DDD service | Profile: `role=backend`, `stack=java`, `architecture=ddd`, `delivery=api-first` | Rules emphasize bounded contexts, aggregates, repositories as interfaces, OpenAPI compatibility, integration tests. |
| No Memory Bank in repo | Global user profile: `role=backend`, `stack=go` | First response remains `[MEMORY BANK: ABSENT]`; global rules-only mode still applies Go/backend presets without creating project files. |

## Profile model

Profiles are resolved in two layers: immutable safety baseline first, then configurable preferences.

```text
Immutable safety baseline (non-overridable)
  + task instruction, if it does not weaken safety baseline
  > project Memory Bank profile (`<mb>/rules-profile.json`)
  > repository `RULES.md` / existing project rules
  > user global profile (`<agent-config>/memory-bank/rules-profile.json`)
  > built-in configurable defaults
```

Immutable safety baseline is always active and cannot be disabled by task, user profile, or project profile:
- no placeholders;
- protected files;
- destructive actions require explicit confirmation;
- fail-fast;
- DRY / KISS / YAGNI;
- verification before completion;
- explicit user choice for storage/profile writes.

Configurable rules may tune test mode, architecture style, delivery flow and stack guidance, but cannot weaken the immutable safety baseline. Example: a legacy profile may allow test-after remediation for existing untested code, but it cannot allow placeholders, unverified completion, or destructive changes without confirmation.

Canonical machine format is JSON (`rules-profile.json`, `rules-presets/*.json`) so shell scripts can parse through Python stdlib without adding runtime YAML dependencies. YAML may appear only in documentation examples and must be converted by CLI before storage.

Profile dimensions for Sprint 3 MVP:
- **role preset:** backend, frontend, mobile.
- **stack preset:** go, python, javascript, typescript, java, generic.
- **architecture preset:** clean, hexagonal, modular-monolith, microservices, ddd, fsd, mobile-udf, event-driven, custom.
- **delivery preset:** tdd, contract-first, api-first, sdd, legacy-safe, exploratory.
- **strictness:** advisory, warn, block.

Non-MVP presets such as fullstack, qa, architect, devops, data, kotlin, swift and rust are accepted only as `generic` fallback guidance in Sprint 3 unless each preset has schema validation, fixtures, docs and contract tests in the same change.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Profile schema and contract tests

**What to do:**
- Create a profile schema spec in `references/rules-profile.schema.md` that defines canonical JSON profile format.
- Add fixture profiles under `tests/fixtures/rules-profiles/` for backend-go, frontend-typescript, frontend-javascript, mobile-generic, python-modular, java-ddd, and rules-only-global.
- Add tests before implementation for parsing, precedence, immutable baseline and validation.

**Testing (TDD — tests BEFORE implementation):**
- Add `tests/pytest/test_rules_profile_schema.py` with cases:
  - valid JSON profile dimensions parse;
  - unknown role/stack/architecture/delivery fails with a clear error;
  - project profile overrides user profile for configurable preferences;
  - task instruction can override strictness for a single run only if it does not weaken immutable baseline;
  - attempts to disable protected files, no-placeholders, DRY/KISS/YAGNI, or verification-before-completion are rejected;
  - no Memory Bank uses user global profile;
  - invalid JSON profile fails closed and falls back to immutable baseline with warning;
  - YAML examples are documentation-only and are not used as runtime source of truth.
- Red command: `pytest -q tests/pytest/test_rules_profile_schema.py` must fail because resolver/parser does not exist.

**DoD (Definition of Done):**
- [ ] Schema doc lists all fields, allowed values, defaults, immutable baseline and precedence rules.
- [ ] At least 7 fixture profiles exist and are used by tests.
- [ ] Red test run fails for missing profile resolver, not syntax errors.
- [ ] Schema includes backend/frontend/mobile presets and Go/Python/JavaScript/TypeScript/Java stack presets.
- [ ] Schema states JSON is canonical machine format and YAML is docs-only unless explicitly converted by CLI.
- [ ] No production profile logic is added before red tests exist.

**Code rules:** Contract-first, TDD red phase, no new runtime dependencies, immutable baseline, fail closed.

---

<!-- mb-stage:2 -->
### Stage 2: Profile resolver CLI

**What to do:**
- Add `scripts/mb-profile.sh` with subcommands:
  - `init` — interactive or flag-driven profile creation;
  - `show` — print resolved merged profile;
  - `path` — print active profile path and source layer;
  - `validate` — validate a profile file;
  - `set` — update one field in user or project profile.
- Support `--scope=user|project`, `--role`, `--stack`, `--architecture`, `--delivery`, `--strictness`, `--agent`, `--mb`.
- Store user profile under the agent global storage root from Sprint 1; store project profile under resolved Memory Bank path when active.
- Persist profiles as deterministic pretty-printed JSON and validate through Python stdlib only.

**Testing (TDD — tests BEFORE implementation):**
- Add `tests/bats/test_mb_profile.bats` before implementation.
- Required cases:
  - `profile: show returns baseline when no profiles exist`;
  - `profile: init user backend go writes global profile outside project`;
  - `profile: init project frontend typescript writes <mb>/rules-profile.json`;
  - `profile: project overrides user for architecture`;
  - `profile: immutable baseline cannot be disabled by profile set`;
  - `profile: invalid stack exits 2`;
  - `profile: validate reports unknown field with line/key context`;
  - `profile: no Memory Bank project rejects --scope=project with hint`.
- Verification command: `bats tests/bats/test_mb_profile.bats`.

**DoD (Definition of Done):**
- [ ] `mb-profile.sh --help` documents all subcommands and examples for user/project profiles.
- [ ] User-scope profile can be created with no project Memory Bank and creates no files in the project.
- [ ] Project-scope profile works with local and global Memory Bank paths.
- [ ] Output of `show` is deterministic JSON and machine-readable by other scripts.
- [ ] CLI never parses runtime YAML directly; YAML examples must be converted to JSON first.
- [ ] `shellcheck scripts/mb-profile.sh` is clean.

**Code rules:** SRP for shell functions, idempotency, no repository writes in user-scope mode.

---

<!-- mb-stage:3 -->
### Stage 3: Built-in role and stack presets

**What to do:**
- Add MVP preset definitions under `references/rules-presets/` as JSON:
  - `roles/backend.json`, `roles/frontend.json`, `roles/mobile.json`.
  - `stacks/go.json`, `stacks/python.json`, `stacks/javascript.json`, `stacks/typescript.json`, `stacks/java.json`, `stacks/generic.json`.
  - `architecture/clean.json`, `architecture/hexagonal.json`, `architecture/modular-monolith.json`, `architecture/microservices.json`, `architecture/ddd.json`, `architecture/fsd.json`, `architecture/mobile-udf.json`, `architecture/event-driven.json`.
  - `delivery/tdd.json`, `delivery/contract-first.json`, `delivery/api-first.json`, `delivery/sdd.json`, `delivery/legacy-safe.json`, `delivery/exploratory.json`.
- Keep preset files declarative: rule ids, severity defaults, compact guidance text, verification hints, and optional script checks.
- Do not add non-MVP presets in Sprint 3 unless each one includes schema validation, fixture, docs and contract tests in the same patch.

**Testing (TDD — tests BEFORE implementation):**
- Extend `tests/pytest/test_rules_profile_schema.py` to assert every preset file validates and every referenced rule id exists.
- Add snapshot-style tests for resolved examples:
  - backend+go+microservices+contract-first;
  - frontend+typescript+fsd+sdd;
  - mobile+kotlin+mobile-udf+api-first;
  - backend+java+ddd+api-first;
  - backend+python+modular-monolith+tdd.
- Verification command: `pytest -q tests/pytest/test_rules_profile_schema.py`.

**DoD (Definition of Done):**
- [ ] Backend/frontend/mobile role presets exist and are documented.
- [ ] Go/Python/JavaScript/TypeScript/Java stack presets exist and are documented.
- [ ] Modular monolith, microservices, DDD, Contract-first, API-first and SDD presets exist.
- [ ] Presets compose without duplicate contradictory severities; conflicts are reported deterministically.
- [ ] Preset text is compact; resolved prompt summary for active profile stays under 4 KB.
- [ ] No preset embeds project-specific assumptions such as hard-coded source directories.

**Code rules:** Declarative config over branching, DRY rule ids, YAGNI for unsupported stacks.

---

<!-- mb-stage:4 -->
### Stage 4: Rules checks consume resolved profiles

**What to do:**
- Update `scripts/mb-rules-check.sh` and related review prompts so checks read the resolved profile.
- Map profile dimensions to concrete checks:
  - Go: context propagation, goroutine leak/race risk hints, interface size, table tests.
  - Python: type hints, dependency injection, pytest naming, Pydantic v2 when used.
  - JS/TS: strict typing where configured, FSD/public API boundaries for frontend, component test expectations.
  - Java: package boundaries, interfaces for repositories/gateways, API schema compatibility.
  - Microservices/API-first/Contract-first: OpenAPI/protobuf/AsyncAPI contract path checks and contract-test requirements.
  - DDD: bounded context and aggregate boundary guidance as review criteria.
  - SDD: context/spec/task traceability requirements when enabled.
- Keep deterministic checks separate from LLM judgment and label each finding with profile rule id.
- Do not duplicate complete language best-practice guides inside Memory Bank presets. Stack presets should emit compact rule ids and optionally link to dedicated skills/docs for deep guidance.

**Testing (TDD — tests BEFORE implementation):**
- Add bats or pytest cases for `mb-rules-check.sh --profile <fixture>`:
  - profile-specific warnings appear for relevant diffs;
  - unrelated stack rules do not fire;
  - strictness `block` turns configured critical findings into non-zero exit;
  - strictness `advisory` reports without failing;
  - resolved prompt summary remains under 4 KB for every fixture profile;
  - stack presets reference optional deep guidance instead of embedding large language guides.
- Verification commands:
  - `bats tests/bats/test_rules_enforcer_tdd.bats`
  - `pytest -q tests/pytest/test_rules_profile_schema.py`

**DoD (Definition of Done):**
- [ ] Rules checker prints resolved profile summary in JSON output.
- [ ] Findings include `rule_id`, `severity`, `profile_source`, and `evidence`.
- [ ] Existing immutable baseline rules still apply when no profile exists.
- [ ] Stack-specific rules are opt-in through detected/selected stack, not globally enforced everywhere.
- [ ] Review prompts receive only active rule ids and top constraints, not all preset text.
- [ ] Review prompts tell agents to follow the resolved profile before generic preferences.

**Code rules:** DIP-style separation of profile resolution and rule evaluation, no false hard-blocks by default.

---

<!-- mb-stage:5 -->
### Stage 5: Interactive profile UX and docs

**What to do:**
- Add `/mb profile` route in `commands/mb.md` and a dedicated `commands/profile.md`.
- Extend `/mb init` flow: after storage choice, ask whether to configure a profile now, use auto-detected recommendation, or skip.
- Add docs:
  - `docs/rule-profiles.md` with concepts, immutable baseline, precedence, examples and migration guidance;
  - README section for rules-only mode personalization;
  - SKILL.md summary for profiles and presets.
- The UX must make clear that skipping a profile keeps immutable baseline rules active.
- The UX must show profile changes as compact diffs and require confirmation before writing user or project profile files.

**Testing (TDD — tests BEFORE implementation):**
- Add docs/runtime contract tests:
  - `commands/mb.md` lists `profile`;
  - `commands/profile.md` exists and references `mb-profile.sh`;
  - README documents backend/frontend/mobile presets and Go/Python/JavaScript/TypeScript/Java presets;
  - rules-only mode docs mention user-global profile;
  - docs state immutable baseline cannot be disabled;
  - docs state profile summaries are compact and deep stack guidance is loaded only when relevant.
- Verification command: `pytest -q tests/pytest/test_runtime_contract.py`.

**DoD (Definition of Done):**
- [ ] `/mb profile init/show/validate/set/path` is documented.
- [ ] `/mb init` can skip profile setup without disabling immutable baseline rules.
- [ ] Auto-detection is advisory and requires user confirmation before writing a profile.
- [ ] Docs include copy-paste examples for backend Go, frontend TS, mobile generic, Python service and Java DDD service.
- [ ] Docs explain JSON is canonical runtime format and YAML is docs-only unless converted.
- [ ] No docs imply one architecture style is mandatory for all projects.

**Code rules:** Explicit user choice, no silent strictness escalation, documentation as contract.

---

<!-- mb-stage:6 -->
### Stage 6: Verification and closeout

**What to do:**
- Run focused profile suites, then broad smoke tests.
- Update `CHANGELOG.md` with the profile system summary.
- Run `/mb verify` for all active global-storage Phase plans before `/mb done`.

**Testing (TDD):**
- Focused profile suite:
  - `pytest -q tests/pytest/test_rules_profile_schema.py tests/pytest/test_runtime_contract.py`
  - `bats tests/bats/test_mb_profile.bats tests/bats/test_rules_enforcer_tdd.bats`
- Broad smoke:
  - `pytest -q`
  - `bats tests/bats tests/e2e`
  - `ruff check .`
  - `shellcheck scripts/*.sh adapters/*.sh hooks/*.sh install.sh`

**DoD:**
- [ ] Profile resolver, preset validation and rules-check integration tests pass.
- [ ] Existing global-storage Sprint 1/2 tests still pass.
- [ ] Generated docs explain immutable baseline, user profile, project profile and safe task override precedence.
- [ ] Changelog names the new role presets, stack presets and architecture/delivery presets.
- [ ] Prompt budget tests prove active profile summaries stay under 4 KB.
- [ ] `/mb verify` reports no CRITICAL items for Sprint 3.

**Code rules:** Verification before completion, profile changes are additive/backward-compatible, no new runtime dependency.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Profile system becomes too complex | High | Ship Sprint 3 MVP only: backend/frontend/mobile roles and Go/Python/JavaScript/TypeScript/Java/generic stacks; strictness defaults to `warn`, not `block`. |
| Conflicting presets confuse agents | Medium | Resolver reports deterministic conflict resolution and includes final merged compact profile summary in prompts. |
| Stack presets encode shallow stereotypes | Medium | Start with widely accepted baseline checks; keep language-specific deep guidance in optional skills/docs. |
| Profile weakens safety rules | Medium | Immutable baseline is non-overridable; tests reject attempts to disable protected files, no placeholders or verification. |
| Prompt bloat reduces agent effectiveness | High | Active profile summary must stay under 4 KB; full preset text is lazy/on-demand only. |
| Runtime YAML parsing adds fragile dependency | Medium | JSON is canonical runtime format; Python stdlib handles parsing/validation. |
| Auto-detection misclassifies project architecture | Medium | Detection is recommendation-only and requires confirmation before writing. |
| Rules-only mode writes to a repo accidentally | Low | User-scope profile writes only under agent global storage; tests assert no project files are created. |
| More docs drift | Medium | Runtime contract tests assert presence of profile references in commands, README and SKILL.md. |

## Gate (Sprint 3 success criterion)

Sprint 3 is complete when Memory Bank can resolve a layered rule profile in local, global and rules-only modes without weakening immutable safety rules; built-in backend/frontend/mobile role presets and Go/Python/JavaScript/TypeScript/Java stack presets compose with architecture and delivery presets; active prompt summaries stay under 4 KB; `mb-rules-check.sh` reports findings with profile rule ids; and docs/commands let users personalize rules without forcing one architecture style on every project.