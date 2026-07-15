// Memory Bank — Pi subagent dispatch core logic (adapter-parity Task 4,
// REQ-008/009). Managed by adapters/pi.sh (install-global-extensions).
//
// Pure logic, NO value dependency on the Pi extension SDK (`typebox` /
// `@earendil-works/pi-coding-agent`) — deliberately split out of
// pi_subagent_extension.ts so this module stays importable/testable with a
// bare `node` process (no package install, no `--experimental-strip-types`).
// pi_subagent_extension.ts is the thin ExtensionAPI glue that wires this
// logic into `pi.registerTool()`.
//
// Design.md "Subagent dispatch" (T1, D-09): Pi has no native
// agent-registry/dispatch flag — the guaranteed floor is a headless `pi
// --mode json -p --no-session` subprocess per invocation, scoped with
// --tools/--append-system-prompt resolved from the role's agents/<role>.md
// (installed to <agentDir>/agents/ by adapters/pi.sh — the same convention
// Pi's own reference `examples/extensions/subagent/index.ts` uses). Scoping
// is LOAD-BEARING for latency + cost (measured: an unscoped run took 5 turns
// / ~$0.02 to answer "pong") — every dispatch here always resolves and
// passes them.
//
// REQ-009 (never a silent drop): any resolution/spawn/exit failure returns
// `dispatched: false` plus an explicit inline-execution warning string, so
// the calling agent loop does the work itself instead of silently assuming
// a subagent ran.

import { spawn } from "node:child_process";
import { mkdtemp, writeFile, rm, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";

// Pi's own agent-config dir convention (`~/.pi/agent`), overridable via the
// SAME env var Pi itself honours (`PI_CODING_AGENT_DIR`, i.e.
// `${APP_NAME}_CODING_AGENT_DIR` with APP_NAME="pi").
export const PI_AGENT_DIR = process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
export const AGENTS_DIR = join(PI_AGENT_DIR, "agents");

const PI_BIN = process.env.MB_PI_BIN || "pi";
const DISPATCH_TIMEOUT_MS = Number(process.env.MB_PI_DISPATCH_TIMEOUT_MS || 300000);

// Codex review MAJOR #4: agents/*.md `tools:` frontmatter uses Claude-Code-style
// capitalized names (Bash, Read, Write, Edit, Grep, Glob, SendMessage). Pi's own
// --tools allowlist is an EXACT, case-sensitive match against its built-in tool
// names — verified against the REAL installed `@earendil-works/pi-coding-agent`
// SDK: `docs/usage.md` documents "Built-in tools: read, bash, edit, write, grep,
// find, ls", and executing the SDK's own `createBashToolDefinition()` /
// `createReadToolDefinition()` / etc. factories directly (no live model call,
// no API cost) confirms their `.name` fields are exactly those lowercase
// strings. `core/agent-session.js`'s `isAllowedTool` is a plain
// `allowedToolNames.has(name)` Set lookup — passing the CC names through
// verbatim matches ZERO registered Pi tools, silently leaving the dispatched
// subagent with NO tools at all. "Glob" has no exact Pi equivalent; "find" is
// Pi's closest built-in (file-finding) and is what it maps to. "SendMessage"
// has no Pi equivalent (Pi's headless single-subprocess dispatch has no
// cross-agent teammate-messaging concept) and is DROPPED rather than passed
// through unmatched, since an untranslated name still fails the same exact
// Set.has() check.
const CC_TO_PI_TOOL_NAME = {
  bash: "bash",
  read: "read",
  write: "write",
  edit: "edit",
  grep: "grep",
  glob: "find",
  find: "find",
  ls: "ls",
};

/**
 * @param {string[]} tools
 * @returns {string[]} Pi's exact built-in tool names, deduped, unknown names dropped.
 */
export function translateToolsToPi(tools) {
  const seen = new Set();
  const out = [];
  for (const t of tools) {
    const piName = CC_TO_PI_TOOL_NAME[t.toLowerCase()];
    if (piName && !seen.has(piName)) {
      seen.add(piName);
      out.push(piName);
    }
  }
  return out;
}

/**
 * Minimal frontmatter reader for agents/<role>.md — only `tools:` + body are
 * needed for dispatch scoping (the caller already names the role
 * explicitly, so name/description/model discovery isn't required here).
 * @param {string} content
 * @returns {{ tools: string[], systemPrompt: string }}
 */
export function parseAgentFile(content) {
  const lines = content.split("\n");
  let tools = [];
  let bodyStart = 0;
  if (lines[0]?.trim() === "---") {
    let end = -1;
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === "---") {
        end = i;
        break;
      }
      const m = lines[i].match(/^tools:\s*(.*)$/);
      if (m) tools = m[1].split(",").map((t) => t.trim()).filter(Boolean);
    }
    bodyStart = end >= 0 ? end + 1 : 0;
  }
  return { tools, systemPrompt: lines.slice(bodyStart).join("\n").trim() };
}

/**
 * @param {string} role
 * @returns {Promise<{ tools: string[], systemPrompt: string } | null>}
 */
export async function loadRoleAgent(role) {
  if (!/^[A-Za-z0-9_-]+$/.test(role)) return null;
  const filePath = join(AGENTS_DIR, `${role}.md`);
  if (!existsSync(filePath)) return null;
  try {
    return parseAgentFile(await readFile(filePath, "utf-8"));
  } catch {
    return null;
  }
}

/**
 * Spawn a headless Pi subprocess scoped to the resolved role's
 * --tools/--append-system-prompt. Mirrors the invocation shape
 * `scripts/mb-subinvoke-resolve.sh --agent pi --role <role>` emits for the
 * fan-out path, so both entry points share the exact same D-09 mechanism.
 *
 * @param {string} role
 * @param {string} task
 * @param {string | undefined} model
 * @param {string} cwd
 * @returns {Promise<{ dispatched: boolean, warning?: string, output: string, exitCode: number | null }>}
 */
export async function dispatchRole(role, task, model, cwd) {
  const agent = await loadRoleAgent(role);
  if (!agent) {
    return {
      dispatched: false,
      warning:
        `[mb-pi-dispatch] no agent definition for role "${role}" at ${join(AGENTS_DIR, role + ".md")}` +
        " — falling back to inline execution.",
      output: "",
      exitCode: null,
    };
  }

  const args = ["--mode", "json", "-p", "--no-session"];
  if (model) args.push("--model", model);
  const piTools = translateToolsToPi(agent.tools);
  if (piTools.length > 0) args.push("--tools", piTools.join(","));

  let tmpDir = null;
  try {
    if (agent.systemPrompt) {
      // Codex review MAJOR #1: mkdtemp/writeFile can throw (ENOSPC, /tmp
      // perms, etc.) — this must land as the SAME dispatched:false+warning
      // shape as every other failure path (REQ-009), never an uncaught
      // throw out of dispatchRole() (which pi_subagent_extension.ts's
      // execute() awaits with no try/catch of its own).
      try {
        tmpDir = await mkdtemp(join(tmpdir(), "mb-pi-dispatch-"));
        const promptPath = join(tmpDir, "system-prompt.md");
        await writeFile(promptPath, agent.systemPrompt, "utf-8");
        args.push("--append-system-prompt", promptPath);
      } catch (err) {
        return {
          dispatched: false,
          warning:
            `[mb-pi-dispatch] failed to write the system-prompt tmpfile for role "${role}" (${err.message})` +
            " — falling back to inline execution.",
          output: "",
          exitCode: null,
        };
      }
    }
    args.push(`Task: ${task}`);

    return await new Promise((resolve) => {
      let settled = false;
      let proc;
      try {
        proc = spawn(PI_BIN, args, { cwd, shell: false, stdio: ["ignore", "pipe", "pipe"] });
      } catch (err) {
        resolve({
          dispatched: false,
          warning:
            `[mb-pi-dispatch] failed to spawn "${PI_BIN}" for role "${role}" (${err.message})` +
            " — falling back to inline execution.",
          output: "",
          exitCode: null,
        });
        return;
      }

      let stdout = "";
      let stderr = "";
      const timer = setTimeout(() => {
        if (settled) return;
        settled = true;
        proc.kill("SIGTERM");
        resolve({
          dispatched: false,
          warning: `[mb-pi-dispatch] role "${role}" timed out after ${DISPATCH_TIMEOUT_MS}ms — falling back to inline execution.`,
          output: stdout,
          exitCode: null,
        });
      }, DISPATCH_TIMEOUT_MS);

      proc.stdout?.on("data", (d) => {
        stdout += d.toString();
      });
      proc.stderr?.on("data", (d) => {
        stderr += d.toString();
      });
      proc.on("error", (err) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({
          dispatched: false,
          warning:
            `[mb-pi-dispatch] failed to spawn "${PI_BIN}" for role "${role}" (${err.message})` +
            " — falling back to inline execution.",
          output: "",
          exitCode: null,
        });
      });
      proc.on("close", (code) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (code !== 0) {
          resolve({
            dispatched: false,
            warning:
              `[mb-pi-dispatch] role "${role}" subprocess exited ${code} — falling back to inline execution.` +
              (stderr.trim() ? ` stderr: ${stderr.trim().slice(0, 400)}` : ""),
            output: stdout,
            exitCode: code,
          });
          return;
        }
        resolve({ dispatched: true, output: stdout, exitCode: code });
      });
    });
  } finally {
    if (tmpDir) {
      try {
        await rm(tmpDir, { recursive: true, force: true });
      } catch {
        // best-effort cleanup only
      }
    }
  }
}

/**
 * Extract the final assistant text from `pi --mode json` NDJSON output.
 * Best-effort: on parse failure the raw stdout tail is surfaced rather than
 * swallowed (REQ-009 — never silent).
 * @param {string} ndjson
 * @returns {string}
 */
export function extractFinalText(ndjson) {
  const lines = ndjson.split("\n").filter((l) => l.trim());
  let last = "";
  for (const line of lines) {
    try {
      const event = JSON.parse(line);
      if (event.type === "message_end" && event.message?.role === "assistant") {
        const content = event.message.content;
        if (typeof content === "string") {
          last = content;
        } else if (Array.isArray(content)) {
          last = content
            .filter((c) => c.type === "text")
            .map((c) => c.text)
            .join("\n");
        }
      }
    } catch {
      // ignore malformed lines, keep the last successfully parsed value
    }
  }
  return last || ndjson.slice(-2000);
}
