# Host model matrix — pipeline-presets-cost-tiers, Stage 0

Date: 2026-10-07. Plan: `plans/2026-10-07_feature_pipeline-presets-cost-tiers.md` (Stage 0, read-only).
Tiers per AGR-074: `premium` = top model everywhere; `optimal` = mid on implementer/verifier/researcher, top on planner/reviewer/judge; `economy` = mid everywhere (never the cheapest model).
Anything not read in a primary source is marked **UNVERIFIED**.

## 1. Matrix: host × tier × role class → model value

`P` = the host's premium id, `M` = the host's mid id (table 2). Tier composition is the same on every host:

| role class | premium | optimal | economy |
|---|---|---|---|
| implementer | P | M | M |
| planner | P | P | M |
| researcher | P | M | M |
| verifier | P | M | M |
| reviewer | P | P | M |
| judge | P | P | M |

Per-host values:

| host | P (premium) | M (mid) | excluded as "cheapest" | value form |
|---|---|---|---|---|
| claude-code | `opus` (→ Opus 5.5) | `sonnet` (→ Sonnet 5.5 on the Anthropic API) | `haiku` | alias or full id (`claude-opus-5-5`) |
| codex | `gpt-6-astra` | `gpt-6.1-sol` | `gpt-6-luna` | bare OpenAI id |
| cursor | `claude-opus-5-5` (OpenAI alt: `gpt-5.6-sol`) | `claude-sonnet-5-5` (OpenAI alt: `gpt-5.6-terra`) | `gpt-5.6-luna`, `composer-2.5`, Grok pool | Cursor model id, optional `[effort=…]` suffix |
| pi | user-chosen `provider/id` | user-chosen `provider/id`, **same provider** | — | `provider/id[:thinking]` |
| opencode | user-chosen `provider/id` | user-chosen `provider/id` | — | `provider/id` |

Example, claude-code `optimal`: developer/backend/…/qa/debugger/analyst = sonnet, researcher = sonnet, verifier = sonnet, architect/planner = opus, reviewer + `reviewer_*` = opus, judge = opus. This matches the existing `mb-agent-caps.sh` claude-agent fallback (`xhigh_roles` → opus, everything else → sonnet), so the fallback **already is** the claude-code `optimal` row.

Choices made here, not stated by AGR-074:
- Claude Code: `fable` / `best` (Fable 5.1) sits above Opus. It is left out of `premium` so `premium` stays consistent with the project's current `opus` and the caps fallback. It can be offered as an explicit override.
- Cursor: the Anthropic pair is the default because the rest of the skill is Claude-tuned. The OpenAI pair is a documented alternative. Cursor's own models (Composer 2.5, Grok) are cheap-pool models and are excluded from every tier.

## 2. Per-host notes

### Claude Code: subagent model YES (dynamic), effort YES
- Frontmatter `model`: alias (`sonnet`, `opus`, `haiku`, `fable`), full id (`claude-opus-5-5`) or `inherit`. Frontmatter `effort`: `low|medium|high|xhigh|max`, depending on the model. Without `effort`, the subagent inherits the session effort.
- Resolution order: (1) the per-invocation `model` parameter of the Agent tool call, (2) frontmatter `model` (`inherit` = main conversation model), (3) env `CLAUDE_CODE_SUBAGENT_MODEL`, (4) the main conversation model. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` forces one model on every subagent (v2.1.257+).
- Catch: a family alias (`opus`) resolves to the main conversation's **exact** model when the main model is in that family.
- Aliases: `opus` → Opus 5.5; `sonnet` → Sonnet 5.5 on the Anthropic API, but Sonnet 4.6 / 4.5 on AWS / Bedrock / Vertex / Foundry; `default` → Opus 5.5.
- `inherit` = the parent conversation's model.
- In this repo: `commands/work.md` §5 passes `model="<json.model>"` per dispatch, so a per-run tier needs no agent-file rewrite. `agents/*.md` declare `effort:` (no `model:` except `mb-wiki-author: haiku`).

### Codex: subagent model YES, effort YES
- Custom agents are TOML files in `~/.codex/agents/` or `.codex/agents/`, with keys `model` and `model_reasoning_effort`. Effort levels: `low|medium|high|xhigh|max|ultra`, depending on the model; Luna has no `ultra`.
- Resolution: explicit spawn value → `[agents]` default in `config.toml` (`agents.default_subagent_model`, `agents.default_subagent_reasoning_effort`) → parent value. A value set in the agent file takes precedence.
- No model and no effort configured = the subagent inherits the parent's model **and** reasoning effort. A model chosen without an effort gets that model's default effort.
- Current family: `gpt-6-astra` (most capable), `gpt-6.1-sol` (near-Astra, lower cost; the docs say "start here"), `gpt-6-luna` (most efficient). GPT-5.6 Sol/Terra/Luna "remain available during the rollout".
- **GPT-5.5 retires 2026-10-14** in ChatGPT/Codex sign-in plans. The OpenAI API is not affected.
- In this repo: `mb-agent-render.py --host codex` writes `model_reasoning_effort` from `effort` but **no `model`**, so installed roles inherit the parent model. The external reviewer runs on the `codex` CLI (`codex exec --model <id>`, `-m` alias, documented).
- Per-call model on the spawn request: the docs name "explicit spawn value" and "request a specific model … in your prompt". The exact `spawn_agent` parameter name is **UNVERIFIED**.

### Cursor: subagent model YES (static frontmatter), effort YES (via id suffix)
- Subagents are Markdown + YAML in:
  - project: `.cursor/agents/`, `.claude/agents/`, `.codex/agents/`;
  - user: `~/.cursor/agents/`, `~/.claude/agents/`, …
- Frontmatter `model`: `inherit` (the default) or a specific model id. Per-model options go in brackets, e.g. `claude-opus-5-5[effort=high]`, `composer-2.5[fast=false]`, `[context=300k]`.
- Cursor falls back to "a compatible model" in three cases: admin block, legacy-plan Max Mode not enabled, or the model is not on the plan. On legacy request-based plans, subagents may default to Composer.
- Ids: `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-fable-5-1`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `composer-2.5`.
- `inherit` = the parent agent's model.
- Whether the Task tool accepts a per-call model: **UNVERIFIED** (no doc found). Treat Cursor tiers as static frontmatter written at `config init`/install.
- Whether Cursor honours a bare `effort:` frontmatter key: **UNVERIFIED** (only the bracket form is documented).
- **Stale claim in the repo:** `adapters/cursor.sh` (lines ~155-175) and `platform_limited: subagents` say Cursor has no subagent dispatch. Current Cursor docs say otherwise: it natively discovers `~/.cursor/agents/` **and `~/.claude/agents/`**, so our Claude-installed `mb-*` agents may already be visible to Cursor. One of them is `mb-wiki-author` with `model: haiku`. Whether Cursor accepts the bare alias `haiku` is **UNVERIFIED**.

### Pi + pi-subagents: subagent model YES (provider-scoped by AGR-056), thinking YES
- Pi core has no native subagents. Delegation goes through the `pi-subagents` package (nicobailon, installed v0.76.0) or the repo's own dispatcher.
  - The dispatcher, `adapters/pi_subagent_dispatch_core.mjs`, runs `pi -p --model <m> --thinking <t>`. Without a model it uses the parent's.
- Pi CLI: `--model <pattern>` (exact or fuzzy, `provider/id`, optional `:<thinking>` suffix) and `--thinking off|minimal|low|medium|high|xhigh|max`.
- Settings (`~/.pi/agent/settings.json` or project `.pi/settings.json`): `defaultProvider`, `defaultModel`, `defaultThinkingLevel`.
  - **Current-model source for `config init`:** `defaultProvider` + `defaultModel`.
  - On this machine: `opencode-go` / `deepseek-v4-pro`, thinking `max`.
- pi-subagents precedence: per-run override (`/run reviewer[model=prov/id:high]`) → `agentOverridesByProvider.<provider>.<name>` → `agentOverrides.<name>.model` → frontmatter `model` → `subagents.defaultModel` → parent session model.
  - `model: inherit` = the parent session model.
  - Thinking: frontmatter `thinking`, `agentOverrides.<name>.thinking`, `subagents.defaultThinking`, ceiling `subagents.maxThinking`.
- AGR-056 + code (`adapters/pi_native_roles.mjs:12-15`, `adapters/pi_native_subagents.mjs:29-37`):
  - the aliases `opus|sonnet|haiku|inherit` → the parent `provider/id`;
  - an explicit model must contain `/`, be in `ctx.modelRegistry.getAvailable()`, and share the parent's provider unless the owner authorised that run.
  - **Consequence:** a claude-code-style profile (`opus`/`sonnet`) on Pi silently collapses to inherit, so the tier is a no-op there.
- `mb-agent-render.py --host pi` drops `model` and maps `effort` → `thinking`.
- **Recommendation:** Pi templates store two `provider/id` values from the **same provider as `defaultProvider`**.
  - `premium` defaults to `defaultProvider/defaultModel`.
  - `mid` comes from `--model-mid`, or is left unset; unset `mid` = `inherit`, and `config show` warns that the tier has no effect.
  - Validate both with `pi --list-models` (already parsed in `mb-agent-caps.sh caps_models`).
  - The pi-subagents `agentOverridesByProvider` map is the host-native way to keep one profile per provider. Optional; do not generate it in v1.

### OpenCode: subagent model YES (static, per agent), effort PARTIAL (provider passthrough)
- Agents are defined in `opencode.json` `agent.<name>` or as Markdown in `~/.config/opencode/agents/` or `.opencode/agents/` (the singular `agent/` used by our adapter is still supported "for backwards compatibility").
- `model` = `provider/model-id`. With `model` omitted:
  - **subagents inherit the model of the primary agent that invoked them**;
  - primary agents use the global `model`.
- Effort: no generic key. "Any other options … passed through directly" to the provider, e.g. `"reasoningEffort": "high"` for OpenAI.
  - Built-in variants: Anthropic `high|max`; OpenAI `none…xhigh`.
  - A per-agent `variant` key is **UNVERIFIED** (not documented on the agents page).
- Current-model source for `config init`: the `model` and `small_model` keys.
  - Precedence: global `~/.config/opencode/opencode.json` → `OPENCODE_CONFIG` → project `opencode.json` → `OPENCODE_CONFIG_CONTENT`.
  - Startup order: `--model/-m` → config `model` → last used → internal priority.
  - List available models with `opencode models`.
- Whether the `task(subagent_type)` tool accepts a per-call model: **UNVERIFIED**. Treat OpenCode tiers as static, written into the agent file or config at `config init`.
- In this repo: `mb-agent-render.py --host opencode` **drops `model` and `effort`**, so every installed `mb-*` agent inherits today. `mb-agent-caps.sh` has hard-coded OpenCode Zen candidates (`opencode/claude-opus-4-5`, `opencode/claude-sonnet-4-5`, …) that are older than the current Anthropic generation.
- `small_model` is OpenCode's "cheap" slot and must **not** become `mid` (AGR-074: no cheapest).

## 3. How `dispatch.model_map` + `mb-agent-caps.sh` work today, and reuse

**Today.** `mb-agent-caps.sh resolve --role R` works like this:
1. It reads `roles.R.model` (the "contract" model) and `thinking`.
2. It orders **transports** (`dispatch.prefer` glob → `dispatch.priority`; default pi → opencode → claude-agent).
3. For each installed transport, it maps the contract id through `dispatch.model_map[contract][transport]`, else through built-in candidates (`caps_default_model_candidates`, OpenCode-only alias lists).
4. It checks availability (`opencode models` / `pi --list-models`; codex is "trusted").
5. Otherwise it falls back to claude-agent with `dispatch.fallback.claude-agent[R]` or the tier default (reviewer*/judge/planner/architect → opus, else sonnet).

Facts that matter for Stage 3:
- **Not wired into `/mb work`.** Only `references/scripts.md`, `references/pipeline.default.yaml` and `tests/bats/test_mb_agent_caps.bats` mention it. `mb-work-plan.sh` (~l.194, 316) reads `roles.<role>.model` directly, and `commands/work.md` never calls caps.
- `model_map` translates **contract model → transport (CLI) id**. A transport is "which CLI runs the step"; that is not the same as the **host** the orchestrator runs in. The keys are model ids, not tiers or role classes.
- `model_map: {}` is empty by default.

**Recommendation: no second mapping table, and a slimmer shape than `model_profiles.<host>.<tier>.<class>`.**
1. One host-independent table of tier composition, in `pipeline.default.yaml`:
   `cost_tiers: {premium: {all: premium}, optimal: {implementer: mid, verifier: mid, researcher: mid, planner: premium, reviewer: premium, judge: premium}, economy: {all: mid}}`.
   It is identical for every host (AGR-074), so it should not be repeated five times.
2. Per host, only two slots: `model_profiles.<host>: {premium: <id>, mid: <id>}`. This is the **only** host-specific model data, about 10 values in total.
   - The full `<host>.<tier>.<class>` shape can still be accepted as an optional override for odd cases.
   - The validator should reject a profile whose `mid` matches `discipline.strict_models` (e.g. `*haiku*`, `*-nano`, `*-mini`), which enforces "no cheapest".
3. Resolver (Stage 3) = CLI flag → `roles.<role>.model` → `model_profiles[host][ cost_tiers[cost][class] ]` → `inherit`. The resolved value is already host-native, so `model_map` is **not** consulted for the host.
4. `model_map` + `mb-agent-caps.sh` stay where they belong: translating a resolved id when the step runs on **another transport** (e.g. a Claude Code orchestrator dispatching the reviewer to the `codex` CLI). Stage 3 should call `mb-agent-caps.sh resolve` with the resolved model instead of `roles.R.model`. This needs a small `--model <id>` input flag on caps instead of a new table.
5. The claude-agent fallback `xhigh_roles` set in caps duplicates the class split. Derive it from `cost_tiers.optimal` (premium classes → opus) so there is one source.

## 4. Gaps and recommended handling

| # | Gap | Handling |
|---|---|---|
| G1 | `mb-agent-caps.sh` not used by `/mb work` | Stage 3 wires it in for cross-transport steps only (see 3.4); not a blocker for host profiles |
| G2 | Pi: `opus`/`sonnet` aliases collapse to parent model (AGR-056); cross-provider forbidden | Pi template = same-provider `provider/id` from `~/.pi/agent/settings.json` (`defaultProvider`/`defaultModel`); unset mid → `inherit` + `config show` warning |
| G3 | OpenCode render drops `model`/`effort`; tiers only static | `config init --host opencode` writes the resolved `model:` (and optional `reasoningEffort`) into `.opencode/agent(s)/<mb-role>.md` or `opencode.json agent.<name>`; per-run `--cost` on OpenCode = re-render, or document as static |
| G4 | Cursor per-call model UNVERIFIED; adapter wrongly says "no subagents" | treat as static frontmatter written at init (`model: claude-sonnet-5-5[effort=medium]`); separate follow-up to correct `adapters/cursor.sh` platform_limited and to check `~/.claude/agents` double-discovery |
| G5 | Codex installed TOML roles carry no `model` | either write `model` into `~/.codex/agents/*.toml` at init (static) or name the model in the spawn request (dynamic; param name UNVERIFIED) |
| G6 | `gpt-5.5` retires 2026-10-14 (ChatGPT sign-in) | `scripts/mb-subinvoke-resolve.sh` default `gpt-5.5` and the `model_map` example in `pipeline.default.yaml:335` need updating to `gpt-6.1-sol`; out of Stage 0 scope, log to backlog |
| G7 | Claude `sonnet` alias maps to older Sonnet on Bedrock/Vertex/Foundry | acceptable (still mid tier); `config show` prints alias, not version |
| G8 | Effort per tier not specified by AGR-074 | keep agent-file `effort`/`thinking` as is; tiers change model only. Hosts: Claude `effort` frontmatter; Codex `model_reasoning_effort`; Cursor `[effort=…]` suffix; Pi `thinking`/`:level`; OpenCode provider passthrough |
| G9 | Model ids go stale (risk H in plan) | ids live only in the 2-slot `model_profiles`; `config show` prints resolved values; host defaults reviewed per release |
| G10 | This repo's `pipeline.yaml` uses `gpt-5.6-sol` for the reviewer | still available "during the rollout" of GPT-6.x; explicit role model wins over profiles, so unaffected |

## Sources

- Claude Code subagents (model/effort, resolution order, env vars): https://code.claude.com/docs/en/sub-agents
- Claude Code model aliases: https://code.claude.com/docs/en/model-config
- Codex models (Astra / 6.1 Sol / Luna, `-m`, GPT-5.5 retirement): https://learn.chatgpt.com/docs/models (redirect from https://developers.openai.com/codex/models)
- Codex subagents / custom agents (TOML keys, inheritance, `[agents]`): https://learn.chatgpt.com/docs/agent-configuration/subagents (redirect from https://developers.openai.com/codex/subagents)
- Cursor subagents (locations, `model`, `inherit`, `[effort=…]`, fallback): https://cursor.com/docs/agent/subagents
- Cursor models and ids: https://cursor.com/docs/models, https://cursor.com/docs/models/claude-opus-5-5, https://cursor.com/docs/models/claude-sonnet-5-5, https://cursor.com/docs/models/gpt-5-6-sol, https://cursor.com/docs/models/gpt-5-6-terra
- OpenCode agents (model format, subagent inheritance, passthrough options): https://opencode.ai/docs/agents/
- OpenCode models/config (variants, default model, precedence, plural dirs): https://opencode.ai/docs/models/, https://opencode.ai/docs/config/
- Pi CLI + settings (installed `@earendil-works/pi-coding-agent` 1.0.2, repo github.com/earendil-works/pi): `docs/cli.md` (`--model`, `--thinking`, `--list-models`), `docs/settings.md` (`defaultProvider`, `defaultModel`, `defaultThinkingLevel`)
- pi-subagents 0.76.0 (github.com/nicobailon/pi-subagents, `docs/models.md`): precedence, `inherit`, thinking settings
- Repo: `scripts/mb-agent-caps.sh`, `scripts/mb-agent-render.py`, `scripts/mb-work-plan.sh`, `scripts/mb-subinvoke-resolve.sh`, `references/pipeline.default.yaml` (`dispatch:` l.321-339), `references/hosts.md`, `adapters/cursor.sh`, `adapters/opencode.sh`, `adapters/pi_native_roles.mjs`, `adapters/pi_native_subagents.mjs`, `adapters/pi_subagent_dispatch_core.mjs`, `adapters/pi_subagent_extension.ts`, `.memory-bank/agreements.md` (AGR-056, AGR-074), `.memory-bank/pipeline.yaml`
