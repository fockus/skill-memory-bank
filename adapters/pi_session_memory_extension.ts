// Memory Bank — Pi session-memory extension
// Native Pi adapter for the Memory Bank session-memory subsystem.
// Writes session files to .memory-bank/session/*.md using the same v2 schema
// as the Claude Code adapter. No Memorix dependency.
//
// Managed by adapters/pi.sh. Placeholders __MB_*__ are replaced at install time.
//
// REQ-020 (once-per-session install nudge, silent once installed): this
// file only RUNS when Pi has already loaded it — i.e. when the extension IS
// installed. There is nothing to nudge from inside a handler that only
// executes post-install; the "bare host" side of REQ-020 lives in
// scripts/mb-session-doctor.sh (REQ-003, static /mb doctor check) and the
// AGENTS.md managed-block line adapters/pi.sh installs pre-transport (T2).
// This module's silence on that front is the intended "already installed →
// stay quiet" half of the same state machine, not a gap.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";

// ── Install-time placeholders (replaced by adapters/pi.sh) ────────────────
const PROJECT_ROOT = __MB_PROJECT_ROOT_JSON__;
// adapter-parity T3: the skill root, used to resolve hooks/scripts/* siblings
// regardless of WHERE this file is installed (project-local .pi/extensions/
// or the global ~/.pi/agent/extensions/ accept path) — a bare
// dirname(__dirname) breaks in both real destinations (it only worked by
// accident for a file sitting directly under the un-installed source tree).
const SKILL_DIR = __MB_SKILL_DIR_JSON__;

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

/** Best-effort current branch name — same fallback as hooks/mb-session-turn.sh ('-'). */
async function resolveBranch(cwd: string): Promise<string> {
  try {
    const { execFile } = await import("node:child_process");
    const { promisify } = await import("node:util");
    const execFileAsync = promisify(execFile);
    const { stdout } = await execFileAsync(
      "git",
      ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
      { timeout: 2000 },
    );
    const branch = stdout.trim();
    return branch || "-";
  } catch {
    return "-";
  }
}

/**
 * Render the update-notify notice (REQ-013). Fail-open (REQ-019): a missing
 * script, a broken MB_PYTHON, a slow/hanging resolver, or a host with no
 * ctx.ui.notify() must never block or crash session_start — every failure
 * mode here resolves to "print nothing", the same silence contract
 * hooks/mb-update-notify.sh itself guarantees. `--cache-only` semantics live
 * inside that script; this wrapper only bounds wall-clock time and never
 * throws past its own boundary.
 */
async function renderUpdateNotice(skillDir: string, cwd: string): Promise<string | null> {
  try {
    const script = join(skillDir, "hooks", "mb-update-notify.sh");
    if (!existsSync(script)) return null;
    const { execFile } = await import("node:child_process");
    const { promisify } = await import("node:util");
    const execFileAsync = promisify(execFile);
    const { stdout } = await execFileAsync("bash", [script], {
      cwd,
      timeout: 3000,
      env: process.env,
    });
    const text = stdout.trim();
    return text.length > 0 ? text : null;
  } catch {
    return null;
  }
}

// ── Extension ──────────────────────────────────────────────────────────────

export default function mbPiSessionExtension(pi: ExtensionAPI) {
  let mbPath: string | null = null;
  let sessionFile: string | null = null;
  let sessionId: string | null = null;
  let turnCount = 0;

  pi.on("session_start", async (event, ctx) => {
    const cwd = PROJECT_ROOT || ctx.cwd;

    // REQ-013/019: update-notify is a SEPARATE transport from session
    // capture (MB_SESSION_CAPTURE governs capture only) — render it BEFORE
    // the capture-disabled gate below, otherwise MB_SESSION_CAPTURE=off
    // would silently also suppress the update notice, which is not what
    // that switch is documented to control. Independent of whether a
    // Memory Bank resolves below — an out-of-date skill is worth knowing
    // about even in a bare project. renderUpdateNotice already swallows
    // every internal error; the outer .catch is belt-and-suspenders so a
    // host whose event loop treats a rejected handler as fatal never sees
    // one from this call.
    const notice = await renderUpdateNotice(SKILL_DIR, cwd).catch(() => null);
    if (notice && typeof ctx.ui?.notify === "function") {
      try {
        ctx.ui.notify(notice);
      } catch {
        // fail-open: a host whose ctx.ui.notify throws must not block session_start.
      }
    }

    if (captureDisabled()) return;

    // Resolve Memory Bank from project root or cwd
    mbPath = resolveMemoryBank(cwd);
    if (!mbPath) return;

    // Ensure session directory exists
    const sessionDir = join(mbPath, "session");
    await mkdir(sessionDir, { recursive: true }).catch(() => {});

    // Get or derive session id from Pi session manager
    sessionId = ctx.sessionManager?.getSessionFile?.() ?? null;
    // Pi's own session-manager save file doubles as the closest analogue to
    // Claude Code's `transcript_path` field (REQ-007 v2 schema parity).
    let transcript = sessionId ?? "";
    if (!sessionId) {
      // Fallback: generate from Pi session file path
      const sf = ctx.sessionManager?.getSessionFile?.();
      sessionId = sf ? sf.replace(/[^a-zA-Z0-9]/g, "-").slice(-36) : `pi-${Date.now().toString(36)}`;
    }

    const fname = sessionFileName(sessionId);
    sessionFile = join(sessionDir, fname);

    const branch = await resolveBranch(cwd);

    // Write header — same v2 schema fields as the Claude Code capture
    // (session_id/transcript/started/branch/turns/last_turn/summarized —
    // hooks/mb-session-turn.sh), plus `agent: pi` (host marker) and
    // `summary_schema: v2` (REQ-007).
    const header = [
      "---",
      `session_id: ${sessionId}`,
      `transcript: ${transcript}`,
      "agent: pi",
      `started: ${nowISO()}`,
      `branch: ${branch}`,
      "turns: 0",
      "last_turn:",
      "summarized: false",
      "summary_schema: v2",
      "---",
      "",
      "## Live log",
      "",
    ].join("\n");

    await appendFile(sessionFile, header, "utf-8").catch(() => {});

    // Fire-and-forget: run catchup in background via shell if available
    const catchupScript = join(SKILL_DIR, "hooks", "mb-session-catchup.sh");
    if (existsSync(catchupScript)) {
      const { spawn } = await import("node:child_process");
      const proc = spawn("bash", [catchupScript], {
        cwd,
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
    // REQ-007: last_turn is part of the shared v2 schema (dedup anchor on
    // the Claude Code side); Pi has no transcript uuid to anchor on, so a
    // stable per-turn counter id fills the same field.
    const lastTurn = `pi-turn-${turnCount}`;
    // Update turns + last_turn in frontmatter
    const { readFile, writeFile } = await import("node:fs/promises");
    try {
      let content = await readFile(sessionFile, "utf-8");
      content = content.replace(/^turns: \d+$/m, `turns: ${turnCount}`);
      content = content.replace(/^last_turn:.*$/m, `last_turn: ${lastTurn}`);
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
    const recentScript = join(SKILL_DIR, "scripts", "mb-session-recent-rebuild.sh");
    if (existsSync(recentScript)) {
      const { spawn } = await import("node:child_process");
      const proc = spawn("bash", [recentScript, mbPath], {
        env: { ...process.env, MB_SESSION_CAPTURE: "on" },
        stdio: "ignore",
      });
      proc.unref();
    }

    // Best-effort: background reindex
    const reindexScript = join(SKILL_DIR, "hooks", "mb-reindex.sh");
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
