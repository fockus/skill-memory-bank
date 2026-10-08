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
import { existsSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

// ── Install-time placeholders (replaced by adapters/pi.sh) ────────────────
const PROJECT_ROOT = __MB_PROJECT_ROOT_JSON__;
// adapter-parity T3: the skill root, used to resolve hooks/scripts/* siblings
// regardless of WHERE this file is installed (project-local .pi/extensions/
// or the global ~/.pi/agent/extensions/ accept path). The session lifecycle
// itself lives in the skill bundle (adapters/pi_native_session.mjs), so a
// single-file install keeps working without copying sibling modules.
const SKILL_DIR = __MB_SKILL_DIR_JSON__;

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
  // Handlers register synchronously; the lifecycle module loads once per runtime.
  const memory = import(pathToFileURL(join(SKILL_DIR, "adapters", "pi_native_session.mjs")).href)
    .then((mod) => ({ mod, api: mod.createSessionMemory({ skillDir: SKILL_DIR, projectRoot: PROJECT_ROOT }) }))
    .catch((error) => ({ error }));

  pi.on("session_start", async (event, ctx) => {
    const cwd = PROJECT_ROOT || ctx.cwd;
    // REQ-013/019: update-notify is a separate transport from session capture
    // (MB_SESSION_CAPTURE governs capture only) and must never block startup.
    const notice = await renderUpdateNotice(SKILL_DIR, cwd).catch(() => null);
    const loaded = await memory;
    const message = loaded.error
      ? `Memory Bank session memory unavailable (${SKILL_DIR}/adapters/pi_native_session.mjs): ${String(loaded.error).split("\n")[0]}`
      : null;
    for (const text of [notice, message]) {
      if (!text || typeof ctx.ui?.notify !== "function") continue;
      try {
        ctx.ui.notify(text);
      } catch {
        // fail-open: a host whose ctx.ui.notify throws must not block session_start.
      }
    }
    return loaded.api?.session_start(event, ctx);
  });

  for (const name of ["input", "tool_execution_start", "tool_execution_end", "agent_end", "before_agent_start",
    "session_before_compact", "session_compact", "session_compact_failed", "session_shutdown"]) {
    pi.on(name as any, async (event: any, ctx: any) => (await memory).api?.[name](event, ctx));
  }
}
