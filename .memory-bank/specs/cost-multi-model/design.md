---
spec_id: cost-multi-model
topic: Cost — multi-model role assignment
status: ready
author: brainstorming-session
created: 2026-05-23
parent_roadmap: harness-upgrade (S4 of S1..S4)
addresses_gaps: [GAP-10]
non_addresses: [GAP-1, GAP-2, GAP-3, GAP-4, GAP-5, GAP-6, GAP-7, GAP-8, GAP-9]
depends_on_specs: [reviewer-2.0, work-loop-v2]
breaking_changes: no (resolver falls back to host default when unsupported)
---

# Cost — multi-model role assignment (S4)

Last and lightest sub-project of the harness upgrade. Assigns appropriate Claude model tiers to roles based on what they actually do: cheap fast models for stable judgmental work (review, rules-enforcement, test-running), capable models for creative work (architecture, generation), balanced models for verification gates.

Depends on S1 (Reviewer 2.0) and S2 (Work loop 2.0) — the reviewer must be calibrated and the work loop must be reliable before downshifting model tiers for cost.

## 1. Goals & Non-goals

### Goals

- **G1 (GAP-10)** — Per-role model assignment in `pipeline.yaml:roles.<role>.model`. Sensible defaults applied centrally so projects benefit out of the box. Override per project.
- **G2** — A resolver `scripts/mb-model-resolve.sh <role>` returns the model ID, used by `commands/work.md` step 3 and other dispatch sites before invoking `Task(subagent_type=<role>, model=<resolved>)`.
- **G3** — Aliases (`fast` / `balanced` / `powerful`) decouple defaults from concrete model IDs, so the model frontier can shift without rewriting every project's `pipeline.yaml`.

### Non-goals

- Cost telemetry / token ledger (backlog).
- Dynamic model selection at runtime based on task complexity (backlog).
- Routing across providers (OpenAI / Gemini etc.) — out of scope.
- Plan / spec changes — S4 is purely a dispatch-layer change.

## 2. Architecture overview

```
commands/work.md step 3:
  for each item in plan/spec:
    role = pipeline.yaml:roles.<role-key>.agent  (existing)
    model = bash scripts/mb-model-resolve.sh <role-key>  (NEW)
    Task(subagent_type=role, model=model, prompt=...)
                                    ▲
                                    │
                                    │ resolver reads (in order):
                                    │   1. .memory-bank/pipeline.yaml: roles.<role>.model
                                    │   2. references/pipeline.default.yaml: roles.<role>.model
                                    │   3. resolver built-in default by role-class
                                    │      (generator → balanced, evaluator → fast,
                                    │       architect → powerful)
                                    │
                                    │ aliases:
                                    │   fast     → claude-haiku-4-5-20251001
                                    │   balanced → claude-sonnet-4-6
                                    │   powerful → claude-opus-4-7
                                    │   <verbatim model id>: passed through
```

The change surface is small: a resolver, a per-role mapping in defaults, a dispatch-site update in `commands/work.md`, and similar updates in `done.md` / `verify.md` / `review.md` for the agents they dispatch.

### OpenCode dispatch

OpenCode does not use `Task(subagent_type=role, model=model)`. Instead, dispatch routes through `scripts/mb-dispatch.sh` (see `plans/2026-05-24_feature_opencode-first-adaptation.md`):

```
commands/work.md step 3 (OpenCode):
  for each item in plan/spec:
    role = pipeline.yaml:roles.<role-key>.agent
    model = bash scripts/mb-model-resolve.sh <role-key>
    bash scripts/mb-dispatch.sh <role> <prompt-file> --model <model>
      → opencode run --agent <role> --model <resolved> --prompt-file <prompt-file>
```

`mb-dispatch.sh` detects the active host and routes to the appropriate dispatch primitive. OpenCode uses `opencode run` CLI with `--agent` and `--model` flags.

## 3. File inventory

### New files

| Path | Kind | Purpose |
|------|------|---------|
| `scripts/mb-model-resolve.sh` | bash | Resolver: `mb-model-resolve.sh <role-key>` → model id |
| `references/model-aliases.yaml` | yaml | Alias → model id table (single source of truth for the model frontier) |
| `tests/bats/test_mb_model_resolve.bats` | bats | Resolver tests |
| `tests/bats/test_pipeline_default_models.bats` | bats | Defaults sanity tests |
| `docs/cost-multi-model.md` | docs | User-facing guide |

### Modified files

| Path | Change |
|------|--------|
| `references/pipeline.default.yaml` | New section `roles.<role>.model` (alias or model id) for every role. See §4 for the default matrix. |
| `commands/work.md` | Step 3a/3b/3c/3f dispatch sites updated to call `mb-model-resolve.sh` and pass `model=...` into `Task`. |
| `commands/done.md` | Where it dispatches `mb-manager` and gate agents — same resolver call. |
| `commands/verify.md` | Where it dispatches `plan-verifier` — same resolver call. |
| `commands/review.md` | Where it dispatches `mb-reviewer` (post-S1 via `scripts/mb-review.sh`) — orchestrator reads model from resolver. |
| `scripts/mb-review.sh` (from S1) | When dispatching `Task → mb-reviewer`, includes resolved model. |
| `scripts/mb-reviewer-resolve.sh` (existing) | Augmented: in addition to resolving the agent name, also resolves the model and emits both. |
| `agents/*.md` (every role) | Frontmatter gets an optional `model_class: fast | balanced | powerful` hint that the resolver uses as the role-class fallback. |
| `install.sh` | Distributes `references/model-aliases.yaml` to the installed skill location. |
| `CHANGELOG.md` | Enumerates: multi-model assignment, default matrix, aliases. |

## 4. Default model matrix

| Role | Class | Default alias | Rationale |
|------|-------|---------------|-----------|
| `mb-developer` | generator | `balanced` | Standard implementation; can shift to powerful for complex domains |
| `mb-backend` | generator | `balanced` | Same as developer |
| `mb-frontend` | generator | `balanced` | Same |
| `mb-ios` | generator | `balanced` | Same |
| `mb-android` | generator | `balanced` | Same |
| `mb-devops` | generator | `balanced` | Same |
| `mb-qa` | generator | `balanced` | Test design benefits from balanced model |
| `mb-analyst` | generator | `balanced` | Same |
| `mb-architect` | architect | `powerful` | Design decisions, cross-system reasoning — pay for capability |
| `mb-reviewer` | evaluator | `fast` | Calibrated by S1; fresh eyes; cost-efficient |
| `mb-test-runner` | evaluator | `fast` | Deterministic stack detection + parsing; capability headroom unnecessary |
| `mb-rules-enforcer` | evaluator | `fast` | Mostly mechanical |
| `plan-verifier` | gate | `balanced` | Final gate — quality > speed |
| `mb-codebase-mapper` | utility | `balanced` | Graph + summarisation — balanced is the sweet spot |
| `mb-doctor` | utility | `fast` | Mostly mechanical drift checks |
| `mb-manager` | utility | `fast` | Bookkeeping |

These defaults live in `references/pipeline.default.yaml`. Projects override per role in `.memory-bank/pipeline.yaml` if they want different choices.

## 5. Aliases

`references/model-aliases.yaml`:

```yaml
schema_version: 2
aliases:
  fast:
    claude: claude-haiku-4-5-20251001
    opencode: kimi-k2-mini
    codex: gpt-4o-mini
  balanced:
    claude: claude-sonnet-4-6
    opencode: kimi-k2.5
    codex: gpt-4o
  powerful:
    claude: claude-opus-4-7
    opencode: kimi-k2.6
    codex: gpt-4.5
```

The resolver reads the active host (from `$MB_HOST` or `.memory-bank/.mb-host`) and resolves the alias to the concrete model ID for that host. If no host-specific entry exists, falls back to `claude` (backward compat).

The resolver loads this once per invocation. When the model frontier shifts (e.g., Sonnet 4.7 ships), updating this single file is enough — every project benefits automatically.

Project override: `.memory-bank/model-aliases.yaml` overrides per-alias entries (same precedence pattern as the rest of the skill's layered config).

Verbatim model IDs in `pipeline.yaml:roles.<role>.model` are passed through unchanged; the resolver doesn't validate them (the dispatch tool will report an invalid id).

## 6. Resolver — `scripts/mb-model-resolve.sh`

### Contract

```
Usage:
  bash scripts/mb-model-resolve.sh <role-key>

Output (stdout):
  <model-id>          # never an alias; always a concrete model ID
Exit codes:
  0    success
  1    role-key not recognised
  2    alias resolution failed (e.g., aliases file missing required entry)
```

### Resolution order

```
0. Detect active host: $MB_HOST env → .memory-bank/.mb-host file → "claude" fallback.

1. Read .memory-bank/pipeline.yaml: roles.<role>.model
   (yq if available, awk fallback)
   If a value exists:
     If it matches an alias → resolve via aliases table for detected host → emit
     Else (assume verbatim model id) → emit

2. Read references/pipeline.default.yaml: roles.<role>.model
   Same resolution.

3. Read agents/<role>.md frontmatter: model_class
   If present → resolve via aliases (key = model_class) for detected host → emit

4. Hardcoded fallback: balanced
   Resolve via aliases for detected host → emit.

(yq absent + awk unable to read → exit 2)
```

### Why bash (not python)

The resolver is hot-path (called for every dispatch). Bash + yq/awk is fast, no interpreter spin-up. Existing skill scripts follow this pattern (`mb-reviewer-resolve.sh`, `mb-work-budget.sh`).

## 7. Testing strategy

### Integration (≈75%)

- `test_mb_model_resolve.bats` —
  - alias resolution: `fast` → expected model id per host (Claude / OpenCode / Codex)
  - verbatim pass-through: `claude-sonnet-4-6` returned as-is
  - per-project override beats baseline
  - missing project pipeline → falls back to defaults
  - missing role in both → falls back to agent frontmatter `model_class`
  - missing everywhere → falls back to `balanced`
  - unknown role-key → exit 1
  - OpenCode host: `fast` resolves to `kimi-k2-mini`
- `test_pipeline_default_models.bats` —
  - every role-agent listed in §4 has a `model` entry in `pipeline.default.yaml`
  - all aliases used are defined in `model-aliases.yaml`

### Unit (≈15%)

- Tiny tests on the awk fallback path (set yq=missing in env).

### E2E (≈10%)

- Manual: run `/mb work` with a no-op stage; confirm dispatch sites pass the resolved model and the `Task` tool accepts it. (Hard to automate fully without a real Task invocation; verified via log capture.)

### Static

- `shellcheck` on the resolver.
- `mb-rules-check.sh` CLEAN.

## 8. Definition of Done (SMART)

- [ ] `scripts/mb-model-resolve.sh` exists, executable, `shellcheck` clean.
- [ ] `references/model-aliases.yaml` exists with `fast/balanced/powerful` mapped to current Claude 4.x IDs.
- [ ] `references/pipeline.default.yaml` has the full §4 default matrix; every role from the existing agents directory is covered.
- [ ] Every agent file in `agents/*.md` has a `model_class` frontmatter entry consistent with §4.
- [ ] All dispatch sites in `commands/{work,done,verify,review}.md` updated to call the resolver and pass `model=...` into `Task` (Claude Code) or `mb-dispatch.sh` (OpenCode/Codex/Pi).
- [ ] `scripts/mb-reviewer-resolve.sh` augmented to also emit model (or its callers call `mb-model-resolve.sh` directly — pick one in implementation; documented in `docs/cost-multi-model.md`).
- [ ] `tests/bats/test_mb_model_resolve.bats` ≥7 tests, all PASS.
- [ ] `tests/bats/test_pipeline_default_models.bats` ≥2 tests, all PASS.
- [ ] `docs/cost-multi-model.md` covers default matrix, override mechanics, and aliases lifecycle.
- [ ] `CHANGELOG.md` entry under `[Unreleased]` enumerates: multi-model assignment + default matrix + aliases.
- [ ] `/mb verify` clean — no regression in existing bats.

## 9. Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| A "fast" reviewer misclassifies subtle issues that the calibrated rubric was tuned for at "balanced" tier | S1 calibration suite (`tests/calibration/run.sh`) re-run at S4 close on the new default; PASS threshold enforced before merging the change. If degradation observed, downgrade defaults selectively. |
| Aliases file drift between skill releases and installed projects | `install.sh` always overwrites `references/model-aliases.yaml`; project override file is separate. Documented. |
| A role frontmatter `model_class` contradicts the pipeline default matrix | Resolver precedence (project > defaults > frontmatter > fallback) is deterministic; the contradiction simply means the defaults win. Bats test asserts this for one such case. |
| Multi-model dispatch raises Task tool errors on unsupported model IDs | Resolver doesn't validate; Task tool error is the canonical surface. Log includes model id for diagnosis. |
| Stack-specific role-agents (mb-backend / mb-ios / etc.) need different defaults per stack | Out of scope for S4; revisit in a follow-up if empirical data justifies. |

## 10. Out-of-scope follow-ups

- Cost telemetry (per-stage token spend ledger) — backlog.
- Dynamic upshift on stagnant pivots (use "powerful" for the second pivot cycle even if default is "balanced") — backlog; would compose with S2 pivot logic.
- Multi-provider routing — backlog.
- Per-stack model defaults (e.g., mb-android default to "powerful" but mb-frontend stays "balanced") — backlog.

## 11. Open questions to resolve during implementation

- Whether to depend on `yq` being installed or always fall back to awk (existing skill scripts already prefer the latter for portability — likely settle on awk-first).
- Whether the resolver should warn (stderr) when a project-level override picks a deprecated alias.
- Exact aliases for the next model frontier (currently using known 4.x IDs; update in implementation if Anthropic ships a 4.8 between S1 and S4).
