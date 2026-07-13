#!/usr/bin/env bats
# Cross-agent RUNTIME parity (C4): unlike the per-adapter install/uninstall
# suites (which assert install-time file shapes), these assert the actual
# RUNTIME behavior each client's wired mechanism produces:
#   (a) placeholder substitution — an installed extension has no leftover
#       __MB_ template tokens (Pi, F-2);
#   (b) capture population — the wired capture mechanism actually writes
#       something real when triggered, honestly reflecting each host's tier
#       (rich session/*.md for Claude Code/Cursor vs. the lesser
#       progress.md git-hooks-fallback for Codex/Kilo/Pi, F-4/F-5);
#   (c) a client with no session-memory transport at all is SKIPPED with an
#       explicit reason, never silently passed or failed.

setup() {
  # Hermetic env: these hooks read their mode from the ambient shell. A dev with
  # MB_AUTO_CAPTURE=off exported turns every capture assertion into a false red
  # (CI runs clean, so it never surfaced). Per-test modes are exported in-test.
  unset MB_AUTO_CAPTURE MB_SESSION_CAPTURE MB_PATH
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOKS_DIR="$REPO_ROOT/hooks"
  PROJECT="$(mktemp -d)"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# ═══════════════════════════════════════════════════════════════
# (a) Pi native extension — placeholder substitution (F-2)
# ═══════════════════════════════════════════════════════════════

@test "parity: Pi's installed graph-rag extension has no unresolved __MB_ placeholders" {
  command -v rsync >/dev/null || skip "rsync required"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)

  run bash "$REPO_ROOT/adapters/pi.sh" install "$PROJECT"
  [ "$status" -eq 0 ]

  ext="$PROJECT/.pi/extensions/memory-bank-graph-rag.ts"
  [ -f "$ext" ]
  ! grep -q '__MB_' "$ext"
  # Positive control: the substituted values are real JSON string literals,
  # not just "placeholder happened to vanish because the file is empty".
  grep -qE 'const SKILL_DIR = ".+";' "$ext"
  grep -qE 'const PROJECT_ROOT = ".+";' "$ext"
}

# ═══════════════════════════════════════════════════════════════
# (b) Claude Code / Cursor — rich session/*.md capture (shared hook)
# ═══════════════════════════════════════════════════════════════
#
# Cursor wires the exact same CC-compatible hook scripts as Claude Code
# (docs/cursor-extension.md: "no Cursor-specific fork of the hook logic") —
# exercising hooks/mb-session-turn.sh directly against a sandboxed bank is
# therefore a faithful simulation of BOTH hosts' capture path, without
# needing a live `claude` CLI (turn-logging is explicitly LLM-free).

@test "parity: the shared Claude Code/Cursor turn hook populates session/*.md on a simulated turn" {
  mkdir -p "$PROJECT/.memory-bank"
  sid="11111111-2222-3333-4444-555555555555"
  transcript="$PROJECT/transcript.jsonl"

  # Minimal realistic transcript: one real user message + one tool_use, so
  # the extractor's stub-guard sees non-empty content and the hook actually
  # creates the session file (an empty/contentless turn is deliberately
  # dropped — see hooks/mb-session-turn.sh's stub guard).
  cat > "$transcript" <<EOF
{"type":"user","uuid":"u-1","message":{"content":"fix the flaky upload test"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/upload.py"}}]}}
EOF

  payload="$(jq -n --arg cwd "$PROJECT" --arg sid "$sid" --arg tp "$transcript" \
    '{cwd: $cwd, session_id: $sid, transcript_path: $tp, stop_hook_active: false}')"

  # Explicit override (not just the default): keeps this test independent of
  # whichever MB_SESSION_CAPTURE this dev shell happens to have exported.
  run env MB_SESSION_CAPTURE=auto bash -c "printf '%s' \"\$1\" | bash \"\$2/mb-session-turn.sh\"" _ "$payload" "$HOOKS_DIR"
  [ "$status" -eq 0 ]

  found=0
  for f in "$PROJECT/.memory-bank/session"/*"${sid:0:8}"*.md; do
    [ -f "$f" ] && found=1
  done
  [ "$found" -eq 1 ]
  grep -rq "fix the flaky upload test" "$PROJECT/.memory-bank/session/"
  grep -rq "Edit" "$PROJECT/.memory-bank/session/"
}

# ═══════════════════════════════════════════════════════════════
# (c) Codex / Kilo / Pi — git-hooks-fallback capture (honest lesser tier)
# ═══════════════════════════════════════════════════════════════

@test "parity: Codex/Kilo/Pi git-hooks-fallback captures to progress.md, NOT session/*.md (honest degradation)" {
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"

  run bash "$REPO_ROOT/adapters/git-hooks-fallback.sh" install "$PROJECT"
  [ "$status" -eq 0 ]

  # Explicit override: this repo's own dev shell sets MB_AUTO_CAPTURE=off to
  # keep dogfooding commits quiet — the hook must default to "auto" for a
  # real end-user checkout, so force that here rather than inherit ours.
  (cd "$PROJECT" && MB_AUTO_CAPTURE=auto bash -c 'echo x > a.txt && git add a.txt && git commit -q -m "first"')

  grep -q "Auto-capture" "$PROJECT/.memory-bank/progress.md"
  # No session/*.md richness from this fallback — that is the documented
  # gap this hook exists to (partially) cover, not a hidden regression.
  [ ! -d "$PROJECT/.memory-bank/session" ] || [ -z "$(ls -A "$PROJECT/.memory-bank/session" 2>/dev/null)" ]
}

# ═══════════════════════════════════════════════════════════════
# (d) OpenCode plugin — summarize wiring resolves to the real hook binary
# ═══════════════════════════════════════════════════════════════

@test "parity: OpenCode plugin's summarize wiring resolves to the real mb-session-end.sh hook" {
  grep -q "summarizeHookPath" "$REPO_ROOT/adapters/opencode.sh"
  grep -q "mb-session-end.sh" "$REPO_ROOT/adapters/opencode.sh"
  # D-6 regression guard: must describe GraphRAG-lite access as agent/CLI-routed,
  # not as registered native OpenCode tool wrappers (adapter never registers any).
  ! grep -q "native tool wrappers may expose" "$REPO_ROOT/adapters/opencode.sh"
}

# ═══════════════════════════════════════════════════════════════
# (e) Windsurf — no session-memory transport: skip, don't silently pass
# ═══════════════════════════════════════════════════════════════

@test "parity: Windsurf has no rich session-memory capture transport (documented gap, explicit skip)" {
  # Windsurf's own hooks.json only wires user-prompt-submit/model-response
  # checks (docs/cross-agent-setup.md) — no CC-compatible SessionEnd/Stop
  # equivalent exists to drive session/*.md population. Per the platform-limit
  # contract (honest degradation, not silent pass), this case is explicitly
  # skipped with its reason rather than asserted as if it worked.
  skip "Windsurf has no CC-compatible SessionEnd/Stop hook — no session/*.md transport to test"
}
