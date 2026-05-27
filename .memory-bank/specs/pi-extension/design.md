---
type: spec-design
topic: pi-extension
status: ready
created: 2026-05-24
linked_requirements: requirements.md
linked_tasks: tasks.md
---

# Design: Pi Extension

Closes the Pi compatibility gap identified in `reports/2026-05-24_pi-compatibility-audit.md`.
Pi has no built-in subagent API or hook system, but its **Extension API** (TypeScript)
provides event interception, custom tools, commands, and provider registration — everything
needed to achieve first-class parity with Claude Code.

## 1. Extension architecture

```
~/.pi/agent/extensions/memory-bank/
├── index.ts              # Entry point — registers tools, commands, events
├── package.json          # Empty deps (uses Pi-bundled packages only)
├── pipeline.ts           # mb_dispatch tool + spawn logic (parallel/chain/single)
├── hooks.ts              # tool_call guards, session lifecycle hooks
├── commands.ts           # /mb, /mb-work, /mb-run command handlers
├── providers.ts          # registerProvider wrappers for OpenAI/Google (optional)
└── lib/
    ├── resolve.ts        # dispatches.json reader + model resolver
    └── spawn.ts          # pi subprocess spawn + JSON output parsing
```

## 2. Subagent dispatch (`mb_dispatch` tool)

### 2.1 Tool registration

```typescript
pi.registerTool({
  name: "mb_dispatch",
  label: "Memory Bank Dispatch",
  description: "Dispatch pipeline waves via Pi subprocess spawn.",
  parameters: Type.Object({
    dispatches_path: Type.String({ description: "Path to dispatches.json" }),
    mode: Type.Optional(StringEnum(["single", "parallel", "chain"] as const)),
    max_concurrent: Type.Optional(Type.Number({ default: 4 })),
  }),
  async execute(toolCallId, params, signal, onUpdate, ctx) {
    // ... pipeline.ts logic
  },
});
```

### 2.2 Spawn contract

Each dispatch becomes a `pi --mode json --no-session` subprocess:

```bash
pi --mode json \
   --no-session \
   --model "<resolved-alias>" \
   --append-system-prompt "<agents-dir>/<role>.md" \
   --tools "read,write,edit,bash,grep,find,ls" \
   "Task: <assembled prompt>"
```

- `--model` is omitted when `via: native` and no alias is specified (uses Pi's current model).
- `--append-system-prompt` injects the role agent definition from `agents/<role>.md`.
- Task prompt includes the item context, DoD, and TDD instructions from `dispatches.json`.

### 2.3 Parallel execution

Uses `mapWithConcurrencyLimit` (max 8 tasks, 4 concurrent) — identical to Pi's official
`subagent/` example:

```typescript
const results = await mapWithConcurrencyLimit(tasks, maxConcurrent, async (task, index) => {
  const result = await spawnPiSubprocess(task, signal);
  onUpdate?.({ /* streaming progress */ });
  return result;
});
```

### 2.4 Chain execution

Sequential with `{previous}` placeholder replacement:

```typescript
let previousOutput = "";
for (const step of chain) {
  const taskWithContext = step.task.replace(/\{previous\}/g, previousOutput);
  const result = await spawnPiSubprocess({ ...step, task: taskWithContext }, signal);
  previousOutput = extractFinalOutput(result);
}
```

### 2.5 Output capture

Subprocess stdout is parsed as JSON Lines (`message_end`, `tool_result_end` events).
The final assistant message text is written to `expected_artifact` as JSON:

```json
{
  "dispatch_id": "stage-1",
  "exit_code": 0,
  "output": "...",
  "usage": { "input": 1200, "output": 800, "cost": 0.012 }
}
```

## 3. Hook guards (`hooks.ts`)

### 3.1 PreToolUse block-dangerous

```typescript
pi.on("tool_call", async (event, ctx) => {
  if (isToolCallEventType("bash", event)) {
    const cmd = event.input.command;
    if (DANGEROUS_PATTERNS.some(p => p.test(cmd))) {
      return { block: true, reason: `Blocked dangerous command: ${cmd}` };
    }
  }
});
```

Patterns:
- `rm\s+-rf\s+(/|~)` — recursive delete
- `curl\s+.*\|\s*(bash|sh)` — pipe to shell
- `npm\s+publish|pip\s+.*upload|cargo\s+publish` — publish without review

### 3.2 Protected-paths guard

```typescript
pi.on("tool_call", async (event, ctx) => {
  if (isToolCallEventType("write", event) || isToolCallEventType("edit", event)) {
    const path = event.input.path || event.input.file_path;
    if (matchesProtectedPaths(path, pipelineYaml)) {
      return { block: true, reason: `Blocked write to protected path: ${path}` };
    }
  }
});
```

Protected paths loaded from `<bank>/pipeline.yaml:protected_paths` globs (cached at session start).

### 3.3 SessionEnd auto-capture

```typescript
pi.on("session_shutdown", async (_event, ctx) => {
  const mbPath = await resolveMbPath(ctx.cwd);
  if (!mbPath) return;
  
  const mode = process.env.MB_AUTO_CAPTURE || "auto";
  if (mode === "off") return;
  
  // Append placeholder to progress.md
  await appendProgressPlaceholder(mbPath);
});
```

### 3.4 PreCompact actualize

```typescript
pi.on("session_before_compact", async (_event, ctx) => {
  const mbPath = await resolveMbPath(ctx.cwd);
  if (!mbPath) return;
  
  // Run mb-compact-actualize.sh
  await execFile("bash", ["scripts/mb-compact-actualize.sh", mbPath]);
  // Allow native compact to proceed
});
```

### 3.5 Weekly compact reminder

```typescript
pi.on("session_start", async (_event, ctx) => {
  const mbPath = await resolveMbPath(ctx.cwd);
  if (!mbPath) return;
  
  const lastCompact = await readLastCompactTimestamp(mbPath);
  const daysSince = (Date.now() - lastCompact) / (1000 * 60 * 60 * 24);
  
  if (daysSince > 7) {
    ctx.ui.notify("Memory Bank: run /mb compact — last compact was ${Math.floor(daysSince)} days ago", "warning");
  }
});
```

## 4. Commands (`commands.ts`)

### 4.1 `/mb` — hub command

```typescript
pi.registerCommand("mb", {
  description: "Memory Bank hub",
  handler: async (args, ctx) => {
    // args = everything after /mb
    // e.g. "/mb work reviewer-v2 --auto --budget 50000"
    // Parse args, route to appropriate handler
  },
});
```

### 4.2 `/mb-work` — work dispatch

```typescript
pi.registerCommand("mb-work", {
  description: "Dispatch work item with flags",
  handler: async (args, ctx) => {
    const parsed = parseWorkArgs(args); // --auto, --budget, --max-cycles, topic
    // Build prompt from spec/plan, inject into session as user message
    ctx.ui.notify(`Dispatching /mb work ${parsed.topic}`, "info");
  },
});
```

### 4.3 `/mb-run` — pipeline run

```typescript
pi.registerCommand("mb-run", {
  description: "Run pipeline plans",
  handler: async (args, ctx) => {
    const parsed = parseRunArgs(args); // plan paths, --preset, --dry-run, etc.
    // Emit dispatches.json, invoke mb_dispatch tool
  },
});
```

## 5. Model provider registration (`providers.ts`)

Optional cross-provider support via `pi.registerProvider()`:

```typescript
pi.registerProvider("openai-judge", {
  name: "OpenAI Judge",
  baseUrl: "https://api.openai.com",
  apiKey: "OPENAI_API_KEY",
  api: "openai-responses",
  models: [
    {
      id: "gpt-5.5",
      name: "GPT-5.5 Judge",
      reasoning: false,
      input: ["text"],
      cost: { input: 0.00001, output: 0.00003, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000,
      maxTokens: 4096,
    }
  ]
});
```

Then spawn with `--model openai-judge:gpt-5.5`.

## 6. Installation

### 6.1 `install.sh` changes

Add Step X (after Step 7 Manifest):

```bash
# ═══ Step X: Pi Extension ═══
echo -e "${BLUE}[X/X] Pi Extension${NC}"
PI_EXT_DIR="$PI_AGENT_DIR/extensions/memory-bank"
mkdir -p "$PI_EXT_DIR"

for f in "$SOURCE_SKILL_DIR/extensions/pi"/*.ts "$SOURCE_SKILL_DIR/extensions/pi"/package.json; do
  [ -f "$f" ] || continue
  install_file "$f" "$PI_EXT_DIR/$(basename "$f")"
done

echo -e "  ${GREEN}✓${NC} Pi extension (pipeline + hooks + commands + tools)"
```

### 6.2 `adapters/pi.sh` changes

Add third mode `extension` (or make it default alongside `skill`):

```bash
install_extension_mode() {
  # Same as skill mode, but also verifies extension files exist
  install_skill_mode
  
  local ext_dir="$PI_AGENT_DIR/extensions/memory-bank"
  if [ ! -f "$ext_dir/index.ts" ]; then
    echo "[pi-adapter] WARNING: memory-bank-pipeline extension not found." >&2
    echo "  Install it via: install.sh --clients pi" >&2
    echo "  Without the extension, Pi runs in sequential fallback mode." >&2
  fi
}
```

## 7. Testing strategy

### Integration (≈65%)

- `tests/bats/test_pi_extension_hooks.bats` — tool_call block on dangerous commands, protected paths.
- `tests/bats/test_pi_extension_dispatch.bats` — single/parallel/chain dispatch with fixture dispatches.json.
- `tests/bats/test_pi_extension_commands.bats` — `/mb`, `/mb-work`, `/mb-run` command registration.
- `tests/bats/test_pi_extension_providers.bats` — registerProvider fallback when env var missing.

### Python (≈20%)

- `tests/pytest/test_pi_extension_resolve.py` — dispatches.json parsing, model resolution.
- `tests/pytest/test_pi_extension_spawn.py` — spawn argument assembly (mocked subprocess).

### E2E (≈15%)

- Manual smoke: install extension, open Pi in a project with `.memory-bank/`, run `/mb work <topic>`, verify subprocess spawn.
- Manual smoke: trigger `rm -rf /` in Pi, verify block.

## 8. Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Extension breaks on Pi version update | Pin to tested Pi version in `package.json:engines.pi`; CI tests against latest stable |
| Subprocess spawn fails on Windows | Document POSIX-only; Windows users use WSL or sequential fallback |
| Extension conflicts with other Pi extensions | Use unique tool names (`mb_*`) and event handlers that chain gracefully |
| `registerProvider` requires API keys in env | Keys live in user env, never in extension code or pipeline.yaml |

## 9. Out-of-scope follow-ups

- Real-time UI progress bars for parallel dispatch — backlog (I-039).
- Streaming partial model outputs back into orchestrator state — backlog (I-043).
- Auto-selection of cheapest passing model per phase via telemetry — backlog (I-044).
