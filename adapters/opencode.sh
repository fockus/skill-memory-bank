#!/usr/bin/env bash
# adapters/opencode.sh — OpenCode cross-agent adapter.
#
# OpenCode plugins are JS/TS modules auto-discovered from .opencode/plugins/.
# Key events: session.created/idle/deleted, tool.execute.before/after,
#             experimental.session.compacting (direct PreCompact equivalent).
# AGENTS.md is the shared-format instructions file (used by OpenCode, Codex,
# Pi fallback, auto-read by Cline).
#
# Usage:
#   adapters/opencode.sh install [PROJECT_ROOT]
#   adapters/opencode.sh uninstall [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[opencode-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OC_DIR="$PROJECT_ROOT/.opencode"
COMMANDS_DIR="$OC_DIR/commands"
AGENT_DIR="$OC_DIR/agent"
PLUGIN_DIR="$OC_DIR/plugins"
PLUGIN_FILE="$PLUGIN_DIR/memory-bank.js"
PLUGIN_REF="./.opencode/plugins/memory-bank.js"
OC_JSON="$PROJECT_ROOT/opencode.json"
MANIFEST="$OC_DIR/.mb-manifest.json"

# adapter-parity T5 (REQ-012): global-scope agent roster, mirroring Pi's
# $HOME/.pi/agent/agents/ accept-path dir + its
# .mb-global-extensions-manifest.json convention exactly (same manifest
# basename, same "one file per host family, not per project" scope).
OC_GLOBAL_AGENT_DIR="$HOME/.config/opencode/agent"
OC_GLOBAL_MANIFEST="$HOME/.config/opencode/.mb-global-extensions-manifest.json"

# shellcheck disable=SC1091
. "$(dirname "$0")/_lib_agents_md.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

# ═══ Plugin file ═══
# adapter-parity T5 (REQ-011/012/013/019/020): plugin_body takes an
# extended flag (0|1, default 0). Base (0) is written by every plain
# `install` (unconditional, whenever "opencode" is a --clients target) and
# stays a byte-for-byte-shaped variant of the pre-T5 plugin PLUS the two
# unconditional/read-only additions (REQ-013 update-notify render, REQ-020
# nudge — neither writes to .memory-bank/session/). Extended (1) is ONLY
# ever written by install_opencode() when MB_OC_PARITY_ACCEPTED=1 is set in
# its environment — set exactly once, by install.sh's
# mb_install_host_extensions "opencode" branch, after explicit user consent
# (never on a plain/declined install — AGR-013). The two variants share a
# SINGLE template (_opencode_plugin_template, one quoted heredoc — no
# escaping hazard) with one substituted boolean token, so there is exactly
# one source of truth for the hook bodies both variants share.
plugin_body() {
  local extended="${1:-0}"
  local extended_flag="false"
  [ "$extended" = "1" ] && extended_flag="true"
  _opencode_plugin_template | sed "s/__MB_OC_PARITY_EXTENDED__/$extended_flag/"
}

_opencode_plugin_template() {
  cat <<'PLUGIN_EOF'
// Memory Bank — OpenCode plugin
// Registers hooks for session lifecycle + tool guard + compact-reminder.
// Auto-captures session placeholder to .memory-bank/progress.md.
// GraphRAG-lite retrieval (code_context, graph_neighbors, graph_impact,
// graph_tests): this plugin does NOT register native OpenCode tool wrappers
// for them. Use the CLI fallback — call scripts/mb-code-context.py or
// scripts/mb-graph-query.py directly (or through an agent) instead.
// memory-bank: managed plugin (do not remove marker line)
//
// adapter-parity T5: MB_OC_PARITY_EXTENDED is baked at generation time by
// adapters/opencode.sh's plugin_body() — true only after explicit opt-in
// (REQ-011/012, AGR-013). It gates the per-turn session/*.md capture
// (chat.message) and the REQ-020 "extensions not installed" nudge; the
// REQ-013 update-notify render itself is unconditional on every variant.
const MB_OC_PARITY_EXTENDED = __MB_OC_PARITY_EXTENDED__;

import { spawn } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

export const MemoryBankPlugin = async ({ directory }) => {
  // Resolve Memory Bank path: MB_PATH env override → local project bank
  const mbDir = () => {
    const override = process.env.MB_PATH;
    if (override && fs.existsSync(override)) return override;
    return path.resolve(directory, '.memory-bank');
  };
  const hasMb = () => {
    try { return fs.statSync(mbDir()).isDirectory(); } catch { return false; }
  };

  const appendProgress = (sessionId) => {
    if (!hasMb()) return;
    const progress = path.join(mbDir(), 'progress.md');
    if (!fs.existsSync(progress)) return;
    const captureMode = process.env.MB_AUTO_CAPTURE ?? 'auto';
    if (captureMode === 'off' || captureMode === 'strict') return;

    const sidPrefix = String(sessionId).slice(0, 8);
    const existing = fs.readFileSync(progress, 'utf8');
    if (existing.includes(`Auto-capture`) && existing.includes(`oc-${sidPrefix}`)) return;

    const today = new Date().toISOString().slice(0, 10);
    const entry = `\n## ${today}\n\n### Auto-capture ${today} (oc-${sidPrefix})\n- OpenCode session detected via session.idle hook\n- Details will be restored on next /mb start\n`;
    fs.appendFileSync(progress, entry);
  };

  // B4 (F-4): mb-session-end.sh is the CC-compatible rich capture (Haiku
  // summary + gated Sonnet judge notes) that Claude Code/Cursor invoke on
  // session end. Wire OpenCode to the SAME script via its OpenCode skill
  // alias (~/.config/opencode/skills/memory-bank/, installed unconditionally
  // — see install.sh's OPENCODE_SKILL_ALIAS), so all three hosts share one
  // capture implementation. MB_SUMMARIZE_BIN overrides the path (test seam,
  // mirrors hooks/mb-session-catchup.sh's own MB_SUMMARIZE_BIN override).
  const summarizeHookPath = () => (
    process.env.MB_SUMMARIZE_BIN
    ?? path.join(os.homedir(), '.config', 'opencode', 'skills', 'memory-bank', 'hooks', 'mb-session-end.sh')
  );

  // Fail-open: missing summarize CLI / missing bank / any spawn error must
  // never throw back into OpenCode's session lifecycle — this is best-effort
  // capture, not a blocking gate. The payload matches the JSON-over-stdin
  // contract mb-session-end.sh already reads from Claude Code/Cursor hooks
  // (.cwd, .session_id); the script itself no-ops when no session file
  // exists (OpenCode does not yet write per-turn session/*.md files).
  const runSummarize = (sessionId) => {
    if (!hasMb()) return;
    try {
      const bin = summarizeHookPath();
      if (!fs.existsSync(bin)) return; // fail-open: summarize CLI absent
      const payloadFile = path.join(os.tmpdir(), `mb-oc-summarize-${process.pid}-${Date.now()}.json`);
      fs.writeFileSync(payloadFile, JSON.stringify({ cwd: directory, session_id: String(sessionId) }));
      // Detached + ignored stdio: the payload file (already flushed above) is
      // read by the child directly, so nothing keeps the parent's event loop
      // alive — OpenCode's session lifecycle is never delayed by this call.
      const child = spawn(
        'sh',
        ['-c', 'bash "$1" < "$2" >/dev/null 2>&1; rm -f "$2"', '_', bin, payloadFile],
        { detached: true, stdio: 'ignore' },
      );
      child.unref();
    } catch {
      // fail-open — summarize is best-effort, never blocks the OpenCode session lifecycle.
    }
  };

  // ── T5 additions: session-start context injection (REQ-013/020) +
  // per-turn capture (REQ-011/007-parity) ──────────────────────────────────

  const captureDisabled = () => process.env.MB_SESSION_CAPTURE === 'off';

  const pad = (n) => String(n).padStart(2, '0');
  const fmtDate = (d) => d.toISOString().slice(0, 10);
  const nowISO = () => new Date().toISOString();

  // <date>_<hhmm>_oc_<sid8>.md — same naming convention as the Pi extension
  // (…_pi_<sid8>.md) and the Claude Code capture, just with the `oc` host tag.
  const ocSessionFileName = (sessionId) => {
    const d = new Date();
    const sid8 = String(sessionId).slice(0, 8);
    return `${fmtDate(d)}_${pad(d.getHours())}${pad(d.getMinutes())}_oc_${sid8}.md`;
  };

  // Best-effort current branch name — same fallback ('-') as
  // hooks/mb-session-turn.sh / the Pi extension's resolveBranch.
  const resolveBranch = async (cwd) => {
    try {
      const { execFile } = await import('node:child_process');
      const { promisify } = await import('node:util');
      const execFileAsync = promisify(execFile);
      const { stdout } = await execFileAsync(
        'git',
        ['-C', cwd, 'rev-parse', '--abbrev-ref', 'HEAD'],
        { timeout: 2000 },
      );
      const branch = stdout.trim();
      return branch || '-';
    } catch {
      return '-';
    }
  };

  // REQ-013: same TTL-cached, network-free (--cache-only is baked into the
  // hook script itself, mirrors codex.sh/the Pi extension), fail-open
  // render as every other transport — a missing script, a broken
  // interpreter, a slow/hanging resolver, or any spawn error must never
  // throw back into OpenCode's LLM-call pipeline; every failure resolves to
  // "render nothing", same contract hooks/mb-update-notify.sh itself
  // guarantees. MB_UPDATE_NOTIFY_BIN overrides the path (test seam, mirrors
  // MB_SUMMARIZE_BIN above).
  const updateNotifyHookPath = () => (
    process.env.MB_UPDATE_NOTIFY_BIN
    ?? path.join(os.homedir(), '.config', 'opencode', 'skills', 'memory-bank', 'hooks', 'mb-update-notify.sh')
  );

  const renderUpdateNotice = async () => {
    try {
      const bin = updateNotifyHookPath();
      if (!fs.existsSync(bin)) return null;
      const { execFile } = await import('node:child_process');
      const { promisify } = await import('node:util');
      const execFileAsync = promisify(execFile);
      const { stdout } = await execFileAsync('bash', [bin], {
        cwd: directory,
        timeout: 3000,
        env: process.env,
      });
      const text = stdout.trim();
      return text.length > 0 ? text : null;
    } catch {
      return null;
    }
  };

  // REQ-020: the exact accept-path command, mirrored from
  // scripts/mb-session-doctor.sh's Pi hint / the T2 AGENTS.md nudge text.
  // This handler is the STATE-DRIVEN half (checks the baked
  // MB_OC_PARITY_EXTENDED flag, i.e. whether THIS project actually accepted
  // the offer) — the AGENTS.md line is only the pre-transport static
  // fallback (T2).
  const MB_OC_NUDGE_TEXT =
    '[memory-bank-skill] OpenCode parity extensions not installed — run: install.sh --clients opencode --with-extensions=opencode';

  // Per-sessionID dedup: render at most once per session (REQ-013/020 —
  // "on session start", not on every LLM call, even though
  // experimental.chat.system.transform itself fires per call).
  const notifiedSessions = new Set();

  // Per-sessionID per-turn capture state: { file, turns }. A Map (not
  // closure-scoped like the Pi extension's single-session locals) because a
  // single OpenCode plugin instance can serve MULTIPLE concurrent sessions.
  const ocSessionState = new Map();

  const finalizeSessionCapture = async (sessionId) => {
    const state = ocSessionState.get(sessionId);
    if (!state) return;
    try {
      const ended = [`ended: ${nowISO()}`, `turns: ${state.turns}`].join('\n');
      await fs.promises.appendFile(state.file, `\n${ended}\n`, 'utf-8').catch(() => {});
    } catch {
      // fail-open (REQ-019).
    } finally {
      ocSessionState.delete(sessionId);
    }
  };

  return {
    // Codex review fix (major, REQ-019): the whole body is wrapped — the
    // pre-existing appendProgress()/runSummarize() calls below are NOT
    // internally try/catch'd (appendProgress uses unguarded synchronous
    // fs.readFileSync/appendFileSync), so a perms/ENOSPC/TOCTOU throw used
    // to reject this async handler and escape into OpenCode's session
    // lifecycle — the one hook in this plugin that was NOT fail-open like
    // every other T5 addition. Also fixes the notifiedSessions leak (minor):
    // previously only cleared inside finalizeSessionCapture, which (a) only
    // ran on the extended variant and (b) early-returned before the delete
    // when no capture state existed — a base-variant session, or an
    // extended session that never reached chat.message, never freed its
    // entry. Cleared here unconditionally, regardless of
    // MB_OC_PARITY_EXTENDED or capture state.
    event: async ({ event }) => {
      try {
        if (event?.type === 'session.idle' || event?.type === 'session.deleted') {
          const sessionId = event?.properties?.info?.id ?? event?.properties?.sessionID ?? 'oc-unknown';
          appendProgress(sessionId);
          runSummarize(sessionId);
          if (MB_OC_PARITY_EXTENDED) {
            await finalizeSessionCapture(sessionId).catch(() => {});
          }
          notifiedSessions.delete(sessionId);
        }
      } catch {
        // fail-open (REQ-019): never throw back into OpenCode's session lifecycle.
      }
    },
    // REQ-013/020: session-start context injection. Fires per LLM call —
    // the per-sessionID dedup above makes the FIRST call of a session the
    // practical "session start" for the notice/nudge. Fail-open: wrapped
    // end-to-end so a throw anywhere inside (a monkey-patched builtin, a
    // malformed `output`, a spawn error) never breaks the LLM call this
    // hook is attached to (REQ-019).
    'experimental.chat.system.transform': async (input, output) => {
      try {
        const sessionId = input?.sessionID ?? 'oc-unknown';
        if (notifiedSessions.has(sessionId)) return;
        notifiedSessions.add(sessionId);

        const notice = await renderUpdateNotice().catch(() => null);
        if (notice && Array.isArray(output?.system)) {
          output.system.push(notice);
        }
        if (!MB_OC_PARITY_EXTENDED && Array.isArray(output?.system)) {
          output.system.push(MB_OC_NUDGE_TEXT);
        }
      } catch {
        // fail-open (REQ-019): never throw back into OpenCode's LLM call.
      }
    },
    // REQ-011/REQ-007-parity: per-turn capture, extended variant only.
    // Fires per NEW USER MESSAGE, before it reaches the LLM — the closest
    // OpenCode analogue to the Pi extension's pi.on("input", ...) turn log.
    // Writes the SAME v2 schema header fields as the Claude Code / Pi
    // captures (session_id/agent/started/branch/turns/last_turn/
    // summarized/summary_schema). `transcript` has no OpenCode-side
    // analogue exposed by this hook (no on-disk transcript path, unlike
    // Pi's sessionManager.getSessionFile()) — left blank rather than
    // fabricated.
    'chat.message': async (input, output) => {
      if (!MB_OC_PARITY_EXTENDED || captureDisabled()) return;
      try {
        if (!hasMb()) return;
        const sessionId = input?.sessionID ?? 'oc-unknown';
        const sessionDir = path.join(mbDir(), 'session');
        await fs.promises.mkdir(sessionDir, { recursive: true }).catch(() => {});

        let state = ocSessionState.get(sessionId);
        if (!state) {
          const file = path.join(sessionDir, ocSessionFileName(sessionId));
          const branch = await resolveBranch(directory);
          const header = [
            '---',
            `session_id: ${sessionId}`,
            'transcript:',
            'agent: opencode',
            `started: ${nowISO()}`,
            `branch: ${branch}`,
            'turns: 0',
            'last_turn:',
            'summarized: false',
            'summary_schema: v2',
            '---',
            '',
            '## Live log',
            '',
          ].join('\n');
          await fs.promises.appendFile(file, header, 'utf-8').catch(() => {});
          state = { file, turns: 0 };
          ocSessionState.set(sessionId, state);
        }

        state.turns += 1;
        const parts = Array.isArray(output?.parts) ? output.parts : [];
        const text = parts
          .filter((p) => p && p.type === 'text' && typeof p.text === 'string')
          .map((p) => p.text)
          .join(' ')
          .slice(0, 200);
        const lastTurn = `oc-turn-${state.turns}`;

        const content = await fs.promises.readFile(state.file, 'utf-8').catch(() => null);
        if (content !== null) {
          const updated = content
            .replace(/^turns: \d+$/m, `turns: ${state.turns}`)
            .replace(/^last_turn:.*$/m, `last_turn: ${lastTurn}`);
          await fs.promises.writeFile(state.file, updated, 'utf-8').catch(() => {});
        }

        const ts = new Date().toLocaleTimeString('en-GB', { hour12: false });
        const entry = `- ${ts} — User: "${text}"\n`;
        await fs.promises.appendFile(state.file, entry, 'utf-8').catch(() => {});
      } catch {
        // fail-open (REQ-019): never throw back into OpenCode's chat pipeline.
      }
    },
    'tool.execute.before': async (input, output) => {
      // Block dangerous shell commands.
      const cmd = String(output?.args?.command ?? '');
      const dangerous = [
        /rm\s+-rf\s+\//,
        /rm\s+-rf\s+~/,
        /:\(\)\s*\{\s*:\|:&\s*\};:/,
      ];
      if (dangerous.some((re) => re.test(cmd))) {
        throw new Error(`[MB-opencode] BLOCKED dangerous command: ${cmd}`);
      }
    },
    'experimental.session.compacting': async (input, output) => {
      // Direct PreCompact equivalent: persist a checkpoint and enrich compaction context.
      if (!hasMb()) return;
      const stamp = new Date().toISOString();
      const progress = path.join(mbDir(), 'progress.md');
      if (!fs.existsSync(progress)) return;
      const sessionId = input?.session?.id ?? 'unknown';
      const marker = `opencode-compacting-checkpoint ${stamp} session=${String(sessionId).slice(0, 8)}`;
      fs.appendFileSync(progress, `\n<!-- ${marker} -->\n`);
      if (Array.isArray(output?.context)) {
        output.context.push(`Memory Bank checkpoint: ${marker}`);
      }
    },
  };
};

export default MemoryBankPlugin;
PLUGIN_EOF
}

# ═══ opencode.json management ═══
# Back up the user's TRUE original opencode.json exactly once (rotation-safe:
# never clobber it on re-install). Skip only if a real regular-FILE MB backup
# already exists — a coincidental dir/other match must not suppress the backup.
opencode_backup_json() {
  [ -f "$OC_JSON" ] || return 0
  local b
  for b in "$OC_JSON".pre-mb-backup.*; do
    [ -f "$b" ] && return 0
  done
  cp "$OC_JSON" "$OC_JSON.pre-mb-backup.$$"
}

# Strip MB's plugin ref, write atomically (unique tmp + mv, same dir). Broken
# JSON → leave the user's file untouched (jq failed; a backup was already taken
# on install). Empty object → remove. Foreign keys are preserved by jq.
_opencode_strip_plugin_ref() {
  [ -f "$OC_JSON" ] || return 0
  local tmp
  if ! tmp=$(jq --arg ref "$PLUGIN_REF" '
    .plugin = ((.plugin // []) - [$ref])
    | if (.plugin | length) == 0 then del(.plugin) else . end
  ' "$OC_JSON" 2>/dev/null); then
    return 0
  fi
  if [ "$(printf '%s' "$tmp" | jq 'length' 2>/dev/null)" = "0" ]; then
    rm -f "$OC_JSON"
  else
    local out mode
    out="$(mktemp "$(dirname "$OC_JSON")/.opencode.json.mbXXXXXX")" || return 1
    mode="$(mb_file_mode "$OC_JSON")"
    if printf '%s\n' "$tmp" > "$out"; then
      [ -n "$mode" ] && chmod "$mode" "$out" 2>/dev/null
      mv "$out" "$OC_JSON"
    else
      rm -f "$out"; return 1
    fi
  fi
}

install_opencode_json() {
  [ -f "$OC_JSON" ] || return 0
  opencode_backup_json
  _opencode_strip_plugin_ref
}

uninstall_opencode_json() {
  _opencode_strip_plugin_ref
}

# ═══ Agents (.opencode/agent/*.md) ═══
# OpenCode natively discovers dispatchable subagents from .opencode/agent/*.md
# (same contract as Claude's ~/.claude/agents/). Partials — prepended by
# `/mb work` into a dispatchable agent's own prompt, never dispatched on their
# own (frontmatter `partial: true`, e.g. mb-engineering-core/mb-tooling-core)
# — are excluded, matching install.sh's global agents registry filter.
_opencode_agent_is_partial() {
  head -5 "$1" 2>/dev/null | grep -qiE '^partial:[[:space:]]*true[[:space:]]*$'
}

# Back up a pre-existing file ONCE before we overwrite it (never clobber
# without a recoverable copy — same convention as opencode.json/codex
# config.toml backups). Generic: used for both agent files and the plugin.js.
_opencode_backup_once() {
  local f="$1" b
  [ -f "$f" ] || return 0
  for b in "$f".pre-mb-backup.*; do [ -f "$b" ] && return 0; done
  cp "$f" "$f.pre-mb-backup.$(date +%s).$$" 2>/dev/null || true
}

_opencode_write_agent_file() {
  local src="$1" dst="$2"
  python3 - "$src" "$dst" <<'PY'
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()

if not text.startswith("---\n"):
    open(dst, "w", encoding="utf-8").write(text)
    raise SystemExit(0)

_, frontmatter, body = text.split("---\n", 2)

color_map = {
    "red": "error",
    "blue": "primary",
    "green": "success",
    "yellow": "warning",
    "purple": "accent",
    "magenta": "accent",
    "cyan": "info",
}
valid_colors = {"primary", "secondary", "accent", "success", "warning", "error", "info"}
tool_map = {
    "Bash": "bash",
    "Read": "read",
    "Grep": "grep",
    "Glob": "glob",
    "Edit": "edit",
    "Write": "edit",
    "WebFetch": "webfetch",
    "WebSearch": "websearch",
}
permission_order = ["bash", "read", "edit", "grep", "glob", "webfetch", "websearch"]

tools = []
lines = []
has_mode = False
for line in frontmatter.splitlines():
    if line.startswith("tools:"):
        raw_tools = line.split(":", 1)[1]
        tools = [part.strip() for part in raw_tools.split(",") if part.strip()]
        continue
    if line.startswith("color:"):
        raw = line.split(":", 1)[1].strip().strip('"\'')
        if raw in valid_colors or re.fullmatch(r"#[0-9a-fA-F]{6}", raw):
            color = raw
        else:
            color = color_map.get(raw, "info")
        lines.append(f"color: {color}")
        continue
    if line.startswith("mode:"):
        has_mode = True
        lines.append("mode: subagent")
        continue
    lines.append(line)

if not has_mode:
    lines.append("mode: subagent")

permissions = []
seen = set()
for tool in tools:
    permission = tool_map.get(tool)
    if permission and permission not in seen:
        permissions.append(permission)
        seen.add(permission)

if permissions:
    lines.append("permission:")
    for permission in permission_order:
        if permission in seen:
            lines.append(f"  {permission}: allow")

open(dst, "w", encoding="utf-8").write("---\n" + "\n".join(lines) + "\n---\n" + body)
PY
}

# ═══ Install ═══
install_opencode() {
  adapter_require_jq "opencode-adapter" || exit 1
  mkdir -p "$PLUGIN_DIR" "$COMMANDS_DIR" "$AGENT_DIR"

  local owned
  owned=$(agents_md_install "$PROJECT_ROOT" "opencode" "$SKILL_DIR")
  # A16 (M-8): back up a pre-existing (possibly user-modified) plugin file
  # before overwriting, and write atomically (tmp in the same dir + mv) so a
  # crash mid-write never leaves OpenCode trying to load a truncated plugin.
  # adapter-parity T5: MB_OC_PARITY_ACCEPTED=1 is exported by install.sh's
  # mb_install_host_extensions "opencode" branch exactly once explicit
  # consent exists (REQ-011/012, AGR-013) — a plain `install` call (no
  # accept, e.g. bats invoking this adapter directly) always writes the
  # base variant.
  _opencode_backup_once "$PLUGIN_FILE"
  local plugin_tmp plugin_extended=0
  [ "${MB_OC_PARITY_ACCEPTED:-0}" = "1" ] && plugin_extended=1
  plugin_tmp=$(mktemp "$PLUGIN_DIR/.memory-bank.js.XXXXXXXX")
  plugin_body "$plugin_extended" > "$plugin_tmp"
  mv "$plugin_tmp" "$PLUGIN_FILE"
  install_opencode_json

  local f
  for f in "$SKILL_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    # A23 (CDX-I8): back up a pre-existing same-named user command file before
    # the plain `cp` overwrite below — mirrors the agent-file backup right below.
    _opencode_backup_once "$COMMANDS_DIR/$(basename "$f")"
    cp "$f" "$COMMANDS_DIR/$(basename "$f")"
  done

  for f in "$SKILL_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    _opencode_agent_is_partial "$f" && continue
    _opencode_backup_once "$AGENT_DIR/$(basename "$f")"
    _opencode_write_agent_file "$f" "$AGENT_DIR/$(basename "$f")"
  done

  local files_json
  files_json=$(
    {
      printf '%s\n' "$PLUGIN_FILE"
      for f in "$SKILL_DIR"/commands/*.md; do
        [ -f "$f" ] || continue
        printf '%s\n' "$COMMANDS_DIR/$(basename "$f")"
      done
      for f in "$SKILL_DIR"/agents/*.md; do
        [ -f "$f" ] || continue
        _opencode_agent_is_partial "$f" && continue
        printf '%s\n' "$AGENT_DIR/$(basename "$f")"
      done
    } | adapter_json_array_from_lines
  )

  adapter_write_manifest \
    "$MANIFEST" \
    "opencode" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"plugin_ref\": $(jq -Rn --arg ref "$PLUGIN_REF" '$ref'), \"agents_md_owned\": $owned}"

  echo "[opencode-adapter] installed to $PROJECT_ROOT"
}

# ═══ Global agents (adapter-parity T5, REQ-012) ═══
# Opt-in accept-path installer, mirroring pi.sh's install_global_extensions:
# invoked ONLY from install.sh's mb_install_host_extensions "opencode"
# branch after explicit user consent (never from install_opencode()'s
# normal per-client flow — NFR-001: a declined/plain install never creates
# $OC_GLOBAL_AGENT_DIR). Copies the SAME non-partial roster + partial filter
# (_opencode_agent_is_partial, already defined above and shared with the
# project-scope copy loop in install_opencode()) to global scope, in
# ADDITION to (never instead of) the project-scope copy. $PROJECT_ROOT is
# accepted for contract-signature parity with every other adapter action
# (install/uninstall/install-global-agents all take it positionally) but is
# not otherwise used here — this action's own artifacts are all global.
install_global_extensions() {
  adapter_require_jq "opencode-adapter" || return 1
  mkdir -p "$OC_GLOBAL_AGENT_DIR"

  local f agent_files="" agent_count=0
  for f in "$SKILL_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    _opencode_agent_is_partial "$f" && continue
    _opencode_backup_once "$OC_GLOBAL_AGENT_DIR/$(basename "$f")"
    _opencode_write_agent_file "$f" "$OC_GLOBAL_AGENT_DIR/$(basename "$f")"
    agent_files="${agent_files}${OC_GLOBAL_AGENT_DIR}/$(basename "$f")"$'\n'
    agent_count=$((agent_count + 1))
  done

  local files_json
  files_json=$(printf '%s' "$agent_files" | adapter_json_array_from_lines)

  adapter_write_manifest \
    "$OC_GLOBAL_MANIFEST" \
    "opencode" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"agents_installed\": $agent_count}"

  echo "[opencode-adapter] global agents: $agent_count installed -> $OC_GLOBAL_AGENT_DIR"
  [ "$agent_count" -gt 0 ]
}

# ═══ Uninstall ═══
uninstall_opencode() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[opencode-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "opencode-adapter" || exit 1

  # 1. Remove plugin file
  adapter_remove_manifest_files "$MANIFEST"

  # 2. Strip from opencode.json
  uninstall_opencode_json

  # 3. Decrement AGENTS.md ownership (shared lib handles file removal)
  agents_md_uninstall "$PROJECT_ROOT" "opencode"

  # 4. Remove manifest
  rm -f "$MANIFEST"

  # 5. Clean empty dirs
  rmdir "$PLUGIN_DIR" 2>/dev/null || true
  rmdir "$COMMANDS_DIR" 2>/dev/null || true
  rmdir "$AGENT_DIR" 2>/dev/null || true
  rmdir "$OC_DIR" 2>/dev/null || true

  echo "[opencode-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)                install_opencode ;;
  uninstall)               uninstall_opencode ;;
  install-global-agents)   install_global_extensions ;;
  *)
    echo "Usage: $0 install|uninstall|install-global-agents [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac

adapter_contract_require_functions install_opencode uninstall_opencode >/dev/null
