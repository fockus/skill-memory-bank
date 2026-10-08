// Opted-in native Memory Bank commands and public pi-subagents bridge.
// Install alongside pi_native_{commands,work,subagents}.mjs and pi_native_argv.py.
// Legacy pi_subagent_dispatch_core.mjs remains available to legacy installations;
// this native lane never executes its subprocess or inline fallback.
import { getAgentDir, getPackageDir, hasTrustRequiringProjectResources, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { mkdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { registerNativeCommands } from "./pi_native_commands.mjs";
import { createBackend, selectBackend } from "./pi_native_backend.mjs";
import { registerOrdinaryHost } from "./pi_native_ordinary.mjs";

const SKILL_DIR = __MB_SKILL_DIR_JSON__;

export default async function memoryBankSubagentExtension(pi: ExtensionAPI) {
  await registerOrdinaryHost(pi, { agentDir: getAgentDir(), sdkRoot: getPackageDir(), source: import.meta.url,
    requiresProjectTrust: hasTrustRequiringProjectResources });
  const ports = await registerNativeCommands(pi, SKILL_DIR);
  pi.registerTool({
    name: "mb_dispatch_subagent",
    label: "Memory Bank named role",
    description: "Launch a named leaf role through the owned native service in ordinary Pi or the optional mb-pi runtime. Inherits the live parent model/provider. No inline, CLI or engine fallback.",
    promptSnippet: "Use mb_dispatch_subagent for explicitly authorized named-role work.",
    promptGuidelines: ["Use the exact registered agent name. Failed dispatch is not completion; retain the partial work and stop."],
    parameters: Type.Object({
      role: Type.String(),
      task: Type.String(),
      backend: Type.Optional(Type.String({ description: "Explicit nico or tintin selection; otherwise bank policy then Tintin." })),
      model: Type.Optional(Type.String({ description: "Available provider/id on the current provider only; cross-provider authorization is owner command-only." })),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const runId = `mb-role-${randomUUID()}`;
      const folder = join(ctx.cwd, ".pi", "mb-native-output", runId);
      const output = join(folder, "result.md");
      const bank = await ports.resolveBank(ctx.cwd);
      const backend = await createBackend({ name: await selectBackend(params.backend, bank), pi, ctx: { ...ctx, pi }, decoder: ports.decoder, runId });
      const child = await backend.preflight({ agent: params.role, model: params.model }, params.task, output);
      await mkdir(folder, { recursive: true });
      const receipt = await backend.dispatch("role", child, { signal });
      return { content: [{ type: "text", text: await readFile(output, "utf8") }], details: { runId, output, receipt } };
    },
  });
}
