// Memory Bank — Pi subagent dispatch + native `/mb` command
// Managed by adapters/pi.sh (install-global-extensions), which installs this
// file AND its sibling ./pi_subagent_dispatch_core.mjs (verbatim basename —
// the relative import below is baked as literal text and must resolve
// post-install) side by side into the global Pi extensions dir. Placeholder
// __MB_SKILL_DIR_JSON__ is replaced at install time (same convention as the
// sibling extensions).
//
// adapter-parity Task 4 (REQ-008/009/022, design.md "Subagent dispatch"):
// this file is the thin ExtensionAPI glue — pi_subagent_dispatch_core.mjs
// owns the actual spawn/scoping/fallback logic (kept dependency-free there
// so it stays testable with a bare `node` process; this file's `typebox`
// value import, like the sibling pi_graph_rag_extension.ts, is only
// resolvable inside a live Pi process — see
// tests/bats/test_mb_python_resolution.bats' "no TS compiler available
// here" note for that same limitation).
//
// REQ-022: `pi.registerCommand("mb", ...)` registers a full native `/mb`
// command (a real handler, not the static ~/.pi/agent/prompts/*.md
// expansion) that forwards to the bundled commands/mb.md router prompt.

import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { dispatchRole, extractFinalText } from "./pi_subagent_dispatch_core.mjs";

// ── Install-time placeholder (replaced by adapters/pi.sh) ─────────────────
const SKILL_DIR = __MB_SKILL_DIR_JSON__;

export default function memoryBankSubagentExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "mb_dispatch_subagent",
    label: "Memory Bank subagent dispatch",
    description:
      "Dispatch a Memory Bank /mb work role (mb-backend, mb-reviewer, ...) as a scoped headless Pi " +
      "subprocess (D-09 guaranteed floor). Never silently drops — a failed dispatch reports a warning " +
      "so the caller falls back to inline execution.",
    promptSnippet: "Use mb_dispatch_subagent to run a /mb work role (e.g. mb-backend) as a scoped subagent.",
    promptGuidelines: [
      "Always pass the exact role name from agents/*.md (e.g. mb-backend, mb-reviewer, mb-qa).",
      "If dispatched:false comes back, do the work inline yourself — never treat it as done.",
    ],
    parameters: Type.Object({
      role: Type.String({ description: "Agent role name, e.g. mb-backend, mb-reviewer" }),
      task: Type.String({ description: "Task description to hand to the role" }),
      model: Type.Optional(Type.String({ description: "Model id override" })),
      cwd: Type.Optional(Type.String({ description: "Working directory; defaults to the current project" })),
    }),
    async execute(_toolCallId, params) {
      const cwd = params.cwd || process.cwd();
      const result = await dispatchRole(params.role, params.task, params.model, cwd);
      if (!result.dispatched) {
        const warning = result.warning || "[mb-pi-dispatch] dispatch failed — falling back to inline execution.";
        return { content: [{ type: "text", text: warning }], details: result };
      }
      return { content: [{ type: "text", text: extractFinalText(result.output) }], details: result };
    },
  });

  // REQ-022: a full native command (handler function, session-aware ctx) —
  // distinct from the static ~/.pi/agent/prompts/*.md expansion already
  // installed. Forwards to the bundled router prompt as a real user message
  // rather than re-implementing /mb's routing logic here.
  pi.registerCommand("mb", {
    description: "Memory Bank command router (/mb work, /mb start, /mb plan, ...)",
    handler: async (args: string, _ctx: ExtensionCommandContext) => {
      const routerPath = join(SKILL_DIR, "commands", "mb.md");
      let routerPrompt = "";
      try {
        routerPrompt = await readFile(routerPath, "utf-8");
      } catch {
        pi.sendUserMessage(`/mb ${args}`.trim());
        return;
      }
      const trimmedArgs = args.trim();
      const message = trimmedArgs ? `${routerPrompt}\n\nArguments: ${trimmedArgs}` : routerPrompt;
      pi.sendUserMessage(message);
    },
  });
}
