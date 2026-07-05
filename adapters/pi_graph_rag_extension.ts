// Memory Bank — Pi GraphRAG-lite tools
// Managed by adapters/pi.sh. Native tools delegate to portable CLI scripts.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import * as path from "node:path";

const execFileAsync = promisify(execFile);
const SKILL_DIR = __MB_SKILL_DIR_JSON__;
const PROJECT_ROOT = __MB_PROJECT_ROOT_JSON__;
// A19 (CDX-I6): a bare "python3" breaks on pipx/venv installs where python3
// isn't the interpreter that owns memory_bank_skill (or isn't on PATH at
// all). There is no install-time templating for this file beyond
// SKILL_DIR/PROJECT_ROOT (no build step to run here), so read the same
// MB_PYTHON convention the rest of the skill honors directly from the Pi
// extension host's process environment, falling back to "python3" unchanged.
const PYTHON_COMMAND = process.env.MB_PYTHON || "python3";

async function runPythonJson(script: string, args: string[]) {
  const scriptPath = path.join(SKILL_DIR, script);
  try {
    const { stdout } = await execFileAsync(PYTHON_COMMAND, [scriptPath, ...args], {
      cwd: PROJECT_ROOT,
      maxBuffer: 1024 * 1024,
    });
    return JSON.parse(stdout);
  } catch (caught) {
    const error = caught as { stdout?: string };
    const stdout = typeof caught === "object" && caught !== null && "stdout" in caught
      ? String(error.stdout || "")
      : "";
    if (stdout.trim()) {
      return JSON.parse(stdout);
    }
    return { ok: false, error: "tool_execution_failed", message: String(caught) };
  }
}

function graphPath(projectRoot?: string, mbPath?: string): string {
  return path.join(mbPath || path.join(projectRoot || PROJECT_ROOT, ".memory-bank"), "codebase", "graph.json");
}

export default function memoryBankGraphRagExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "code_context",
    label: "Memory Bank code_context",
    description: "GraphRAG-lite code context: optional semantic input, graph expansion, text/read fallback.",
    promptSnippet: "Use code_context for ambiguous code-understanding questions.",
    promptGuidelines: [
      "Use code_context when the user asks where logic lives or how code fits together.",
      "Use graph tools directly for exact callers/imports/impact/tests questions.",
    ],
    parameters: Type.Object({
      query: Type.String({ description: "Natural-language code question" }),
      projectRoot: Type.Optional(Type.String({ description: "Project root; defaults to current project" })),
      mbPath: Type.Optional(Type.String({ description: "Memory Bank path; defaults to <project>/.memory-bank" })),
      mode: Type.Optional(Type.String({ description: "auto | graph | semantic" })),
      semanticCandidates: Type.Optional(Type.String({ description: "JSON file with semantic candidates" })),
      semanticProvider: Type.Optional(Type.String({ description: "none | unavailable" })),
      semanticOnly: Type.Optional(Type.Boolean({ description: "Use only semantic candidates and recommended reads" })),
    }),
    async execute(_toolCallId, params) {
      const projectRoot = params.projectRoot || PROJECT_ROOT;
      const mbPath = params.mbPath || path.join(projectRoot, ".memory-bank");
      const args = [
        "--query", params.query,
        "--project-root", projectRoot,
        "--mb-path", mbPath,
        "--mode", params.mode || "auto",
        "--json",
      ];
      if (params.semanticCandidates) args.push("--semantic-candidates", params.semanticCandidates);
      if (params.semanticProvider) args.push("--semantic-provider", params.semanticProvider);
      if (params.semanticOnly) args.push("--semantic-only");
      const payload = await runPythonJson("scripts/mb-code-context.py", args);
      return { content: [{ type: "text", text: JSON.stringify(payload, null, 2) }], details: payload };
    },
  });

  const registerGraphTool = (name: string, command: string, description: string) => {
    pi.registerTool({
      name,
      label: "Memory Bank " + name,
      description,
      parameters: Type.Object({
        symbol: Type.Optional(Type.String({ description: "Symbol name" })),
        file: Type.Optional(Type.String({ description: "File path" })),
        projectRoot: Type.Optional(Type.String({ description: "Project root; defaults to current project" })),
        mbPath: Type.Optional(Type.String({ description: "Memory Bank path; defaults to <project>/.memory-bank" })),
      }),
      async execute(_toolCallId, params) {
        const projectRoot = params.projectRoot || PROJECT_ROOT;
        const mbPath = params.mbPath || path.join(projectRoot, ".memory-bank");
        const args = [command, "--graph", graphPath(projectRoot, mbPath), "--json"];
        if (params.symbol) args.push("--symbol", params.symbol);
        if (params.file) args.push("--file", params.file);
        const payload = await runPythonJson("scripts/mb-graph-query.py", args);
        return { content: [{ type: "text", text: JSON.stringify(payload, null, 2) }], details: payload };
      },
    });
  };

  registerGraphTool("graph_neighbors", "neighbors", "Find incoming/outgoing graph edges for a symbol or file.");
  registerGraphTool("graph_impact", "impact", "Find dependents, dependencies and tests for a symbol or file.");
  registerGraphTool("graph_tests", "tests", "Find tests linked to a symbol or file.");
}