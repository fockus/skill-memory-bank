---
type: spec-requirements
topic: pi-extension
status: ready
created: 2026-05-24
linked_design: design.md
linked_tasks: tasks.md
---

# Requirements: Pi Extension

EARS-validated functional requirements for the Pi Code extension that closes the
compatibility gap identified in `reports/2026-05-24_pi-compatibility-audit.md`.

## Functional Requirements (EARS)

### Subagent Dispatch (Pipeline)

- **REQ-200** The extension shall register a custom tool `mb_dispatch` callable by the LLM.
- **REQ-201** When `mb_dispatch` receives a `dispatches.json` path, the extension shall spawn `pi --mode json --no-session` subprocesses for each dispatch entry.
- **REQ-202** The extension shall support parallel execution of up to 8 tasks with 4 concurrent subprocesses.
- **REQ-203** The extension shall support chain execution where the output of step N is injected into step N+1 via a `{previous}` placeholder.
- **REQ-204** When the extension spawns a subprocess, it shall pass the role agent definition via `--append-system-prompt <agent-file>`.
- **REQ-205** When the resolved model alias has `via: native`, the extension shall pass `--model <alias>` to the spawned subprocess.
- **REQ-206** The extension shall write each subprocess result to the `expected_artifact` path specified in `dispatches.json`.
- **REQ-207** The extension shall return aggregated results to the main agent after all dispatches complete.

### Hook Guards

- **REQ-208** The extension shall block `bash` tool calls that match dangerous patterns (`rm -rf /`, `rm -rf ~`, `curl ... | bash`, `npm publish`, `pip upload`, `cargo publish`) via the `tool_call` event.
- **REQ-209** The extension shall block `write` and `edit` tool calls to paths matching `pipeline.yaml:protected_paths` globs via the `tool_call` event.
- **REQ-210** The extension shall append a placeholder to `progress.md` on `session_shutdown` when the project is a git repo and `MB_AUTO_CAPTURE` is not `off`.
- **REQ-211** The extension shall invoke `mb-compact-actualize.sh` on `session_before_compact` and allow the native compact to proceed.
- **REQ-212** The extension shall notify the user via `ctx.ui.notify` on `session_start` if `.last-compact` is older than 7 days.

### Commands

- **REQ-213** The extension shall register `/mb` as a command with argument passthrough.
- **REQ-214** The extension shall register `/mb-work` as a command accepting `--auto`, `--budget`, `--max-cycles`, and topic arguments.
- **REQ-215** The extension shall register `/mb-run` as a command accepting plan paths, `--preset`, `--dry-run`, `--restart`, and `--continue-on-failed-plan` flags.

### Model Provider Registration

- **REQ-216** The extension shall support `via: native` by passing `--model <alias>` to spawned subprocesses.
- **REQ-217** The extension shall support `via: cli:<cmd>` by shelling out via `child_process.exec()` and capturing stdout to `expected_artifact`.
- **REQ-218** The extension shall support `via: skill:<name>` by falling back to the host default model and logging a fallback record in `state-<plan>.json`.
- **REQ-219** If the user has configured cross-provider credentials (e.g., `OPENAI_API_KEY`), the extension shall optionally register those models via `pi.registerProvider()` so that pipeline phases can dispatch to them.

### Extension Lifecycle

- **REQ-220** The extension shall be installable via `install.sh` to `~/.pi/agent/extensions/memory-bank/`.
- **REQ-221** The extension shall be hot-reloadable with Pi's `/reload` command.
- **REQ-222** The extension shall be loadable via `jiti` without a pre-build step.

## Constraints

- Extension code must be TypeScript and use only Pi-bundled packages (`@earendil-works/pi-coding-agent`, `typebox`, `@earendil-works/pi-ai`, `@earendil-works/pi-tui`).
- No npm dependencies beyond Pi's built-ins.
- Extension must coexist with the existing Pi skill (`~/.pi/agent/skills/memory-bank/`); skill provides prompts, extension provides tools/commands/events.
- Extension must not break Pi when the project has no `.memory-bank/` directory (graceful no-op).
