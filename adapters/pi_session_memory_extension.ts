// Memory Bank — Pi session-memory extension
// Native Pi adapter for the Memory Bank session-memory subsystem.
// Writes session files to .memory-bank/session/*.md using the same v2 schema
// as the Claude Code adapter. No Memorix dependency.
//
// Managed by adapters/pi.sh. Placeholders __MB_*__ are replaced at install time.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";

// ── Install-time placeholders (replaced by adapters/pi.sh) ────────────────
const PROJECT_ROOT = __MB_PROJECT_ROOT_JSON__;

// ── Helpers ────────────────────────────────────────────────────────────────

/** Walk up from dir to find nearest .memory-bank/ */
function resolveMemoryBank(fromDir: string): string | null {
  let dir: string = fromDir;
  while (true) {
    const mb = join(dir, ".memory-bank");
    if (existsSync(mb)) return mb;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

/** Format a date as YYYY-MM-DD */
function fmtDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/** Pad to 2 digits */
function pad(n: number): string {
  return n.toString().padStart(2, "0");
}

/** Build a session filename: <date>_<hhmm>_pi_<sid8>.md */
function sessionFileName(sessionId: string): string {
  const d = new Date();
  const sid8 = sessionId.slice(0, 8);
  return `${fmtDate(d)}_${pad(d.getHours())}${pad(d.getMinutes())}_pi_${sid8}.md`;
}

/** Check if session capture is disabled */
function captureDisabled(): boolean {
  return process.env.MB_SESSION_CAPTURE === "off";
}

/** Get a safe timestamp ISO string */
function nowISO(): string {
  return new Date().toISOString();
}

// ── Extension ──────────────────────────────────────────────────────────────

export default function mbPiSessionExtension(pi: ExtensionAPI) {
  let mbPath: string | null = null;
  let sessionFile: string | null = null;
  let sessionId: string | null = null;
  let turnCount = 0;

  pi.on("session_start", async (event, ctx) => {
    if (captureDisabled()) return;

    // Resolve Memory Bank from project root or cwd
    mbPath = resolveMemoryBank(PROJECT_ROOT || ctx.cwd);
    if (!mbPath) return;

    // Ensure session directory exists
    const sessionDir = join(mbPath, "session");
    await mkdir(sessionDir, { recursive: true }).catch(() => {});

    // Get or derive session id from Pi session manager
    sessionId = ctx.sessionManager?.getSessionFile?.() ?? null;
    if (!sessionId) {
      // Fallback: generate from Pi session file path
      const sf = ctx.sessionManager?.getSessionFile?.();
      sessionId = sf ? sf.replace(/[^a-zA-Z0-9]/g, "-").slice(-36) : `pi-${Date.now().toString(36)}`;
    }

    const fname = sessionFileName(sessionId);
    sessionFile = join(sessionDir, fname);

    // Write header
    const header = [
      "---",
      `session_id: ${sessionId}`,
      "agent: pi",
      `started: ${nowISO()}`,
      "turns: 0",
      "summarized: false",
      "summary_schema: v2",
      "---",
      "",
      "## Live log",
      "",
    ].join("\n");

    await appendFile(sessionFile, header, "utf-8").catch(() => {});

    // Fire-and-forget: run catchup in background via shell if available
    const catchupScript = join(dirname(__dirname), "hooks", "mb-session-catchup.sh");
    if (existsSync(catchupScript)) {
      const { spawn } = await import("node:child_process");
      const proc = spawn("bash", [catchupScript], {
        cwd: PROJECT_ROOT || ctx.cwd,
        env: { ...process.env, MB_CATCHUP_FOREGROUND: "0", MB_SESSION_CAPTURE: "on" },
        stdio: "ignore",
        detached: true,
      });
      proc.unref();
    }
  });

  pi.on("input", async (event, ctx) => {
    if (!sessionFile || captureDisabled()) return;
    const ts = new Date().toLocaleTimeString("en-GB", { hour12: false });
    const text = (event.text || "").slice(0, 200); // cap user text
    const entry = `- ${ts} — User: "${text}"\n`;
    await appendFile(sessionFile, entry, "utf-8").catch(() => {});
  });

  pi.on("tool_execution_end", async (event, ctx) => {
    if (!sessionFile || captureDisabled()) return;
    const ts = new Date().toLocaleTimeString("en-GB", { hour12: false });
    const toolName = event.toolName || "unknown";
    const isError = event.isError ? " · ERROR" : "";
    const entry = `  - Tools: ${toolName}${isError}\n  - Outcome: ${isError ? "error" : "ok"}\n`;
    await appendFile(sessionFile, entry, "utf-8").catch(() => {});
  });

  pi.on("agent_end", async (event, ctx) => {
    if (!sessionFile || captureDisabled()) return;
    turnCount++;
    // Update turns in frontmatter
    const { readFile, writeFile } = await import("node:fs/promises");
    try {
      let content = await readFile(sessionFile, "utf-8");
      content = content.replace(/^turns: \d+$/m, `turns: ${turnCount}`);
      await writeFile(sessionFile, content, "utf-8");
    } catch {}

    // Append turn summary
    const entry = `- Turn ${turnCount}: completed\n`;
    await appendFile(sessionFile, entry, "utf-8").catch(() => {});
  });

  pi.on("session_before_compact", async (event, ctx) => {
    if (!sessionFile || !mbPath || captureDisabled()) return;
    const handoffEntry = [
      "",
      "## Handoff capsule",
      `- ${new Date().toISOString()}: context compaction — ${event.reason || "threshold"}`,
      `- Turns captured: ${turnCount}`,
      "",
    ].join("\n");
    await appendFile(sessionFile, handoffEntry, "utf-8").catch(() => {});
  });

  pi.on("session_shutdown", async (event, ctx) => {
    if (!sessionFile || !mbPath || captureDisabled()) return;

    // Finalize session
    const ended = [
      `ended: ${nowISO()}`,
      `turns: ${turnCount}`,
    ].join("\n");
    await appendFile(sessionFile, "\n" + ended, "utf-8").catch(() => {});

    // Best-effort: recent rebuild via shell
    const recentScript = join(dirname(__dirname), "scripts", "mb-session-recent-rebuild.sh");
    if (existsSync(recentScript)) {
      const { spawn } = await import("node:child_process");
      const proc = spawn("bash", [recentScript, mbPath], {
        env: { ...process.env, MB_SESSION_CAPTURE: "on" },
        stdio: "ignore",
      });
      proc.unref();
    }

    // Best-effort: background reindex
    const reindexScript = join(dirname(__dirname), "hooks", "mb-reindex.sh");
    if (existsSync(reindexScript)) {
      const { spawn } = await import("node:child_process");
      const proc = spawn("bash", [reindexScript, "--incremental"], {
        cwd: PROJECT_ROOT || ctx.cwd,
        env: { ...process.env, MB_SESSION_CAPTURE: "on", MB_ROOT: mbPath },
        stdio: "ignore",
        detached: true,
      });
      proc.unref();
    }

    // Reset state
    sessionFile = null;
    sessionId = null;
    turnCount = 0;
  });
}
