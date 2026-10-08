// Memory Bank — Pi GraphRAG tools and graph lifecycle
// Managed by adapters/pi.sh (install-time path placeholders below).
// Thin glue: tools (code_context, graph_neighbors/impact/tests, search_code) and the
// catch-up / dirty-queue / nudge hooks live in <skill>/adapters/pi_native_graph.mjs; the guard and
// plan-sync tool hooks in pi_native_hooks.mjs (registered here: this extension is installed in both tiers).

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const SKILL_DIR = __MB_SKILL_DIR_JSON__;
// Empty for a global install: every call then resolves the bank of the live ctx.cwd.
const PROJECT_ROOT = __MB_PROJECT_ROOT_JSON__;

export default async function memoryBankGraphRagExtension(pi: ExtensionAPI) {
  // A project copy yields to the global install: both register the same tools and guard hooks,
  // and Pi refuses the second registration of a tool name.
  // Agent dir as Pi resolves it (PI_CODING_AGENT_DIR, else ~/.pi/agent), without a runtime SDK import.
  const agentDir = (process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent")).replace(/^~(?=$|\/)/, homedir());
  if (PROJECT_ROOT && existsSync(join(agentDir, "extensions", "memory-bank-graph-rag.ts"))) return;
  const mod = await import(pathToFileURL(join(SKILL_DIR, "adapters", "pi_native_graph.mjs")).href);
  // A19 (CDX-I6): honor the MB_PYTHON convention; the module falls back to the skill venv, then python3.
  mod.registerGraphRag(pi, { Type, skillDir: SKILL_DIR, projectRoot: PROJECT_ROOT, python: process.env.MB_PYTHON });
  const hooks = await import(pathToFileURL(join(SKILL_DIR, "adapters", "pi_native_hooks.mjs")).href);
  hooks.registerGuardHooks(pi, { skillDir: SKILL_DIR, projectRoot: PROJECT_ROOT });
}
