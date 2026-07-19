#!/usr/bin/env bats
# adapter-parity T7 (REQ-015/017/021) — the honesty-layer test suite.
#
# For EVERY capability a client manifest declares in `platform_limited`, this
# suite asserts the PAIR: (a) the capability is genuinely ABSENT from that
# client's actual install output/behavior, AND (b) the reason is discoverable
# (the manifest's own `platform_limited_notes`). A capability declared without
# a matching negative test here is a REQ-017 violation — the meta-test at the
# bottom of this file scans every manifest and fails on any drift, so this
# suite cannot silently rot out of sync with the manifests it is guarding.
#
# Closed vocabulary (design.md): statusline, subagents, lifecycle-hooks,
# session-memory, update-notify, role-routing.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WORKDIR="$(mktemp -d)"
  command -v jq >/dev/null || skip "jq required"
  command -v python3 >/dev/null || skip "python3 required"
}

teardown() {
  [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ] && rm -rf "$WORKDIR"
}

# bats-core has no built-in `fail` (that is a bats-assert helper this repo
# does not load) — a tiny local equivalent: print the message, exit 1.
fail() {
  printf '%s\n' "$*" >&2
  return 1
}

# True (exit 0) when $2 appears only in COMMENT lines or platform_limited
# honesty-note text (`--arg <name> "<human sentence>"` jq lines) of $1, or
# not at all — i.e. the adapter's own honesty-layer rationale (which
# legitimately names the absent capability while explaining why) does not
# count as "wiring it". False (exit 1) when $2 appears in real code.
_absent_from_code() {
  local file="$1" needle="$2"
  ! grep -v '^\s*#' "$file" | grep -v -- '--arg [a-z_]* "' | grep -q "$needle"
}

# ═══════════════════════════════════════════════════════════════
# Manifest producers — one per client, returns the manifest path on stdout.
# Each installs into an isolated tmp project (+ sandboxed HOME where the
# adapter reads $HOME) so results never depend on the host running the tests.
# ═══════════════════════════════════════════════════════════════

manifest_claude_code() {
  local home manifest
  home="$(mktemp -d -p "$WORKDIR")"
  manifest="$(mktemp -d -p "$WORKDIR")/manifest.json"
  MB_MANIFEST_PATH="$manifest" HOME="$home" MB_SKIP_DEPS_CHECK=1 \
    bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null 2>&1
  printf '%s' "$manifest"
}

manifest_cursor() {
  local project
  project="$(mktemp -d -p "$WORKDIR")"
  bash "$REPO_ROOT/adapters/cursor.sh" install "$project" >/dev/null 2>&1
  printf '%s' "$project/.cursor/.mb-manifest.json"
}

manifest_windsurf() {
  local project
  project="$(mktemp -d -p "$WORKDIR")"
  bash "$REPO_ROOT/adapters/windsurf.sh" install "$project" >/dev/null 2>&1
  printf '%s' "$project/.windsurf/.mb-manifest.json"
}

manifest_cline() {
  local project
  project="$(mktemp -d -p "$WORKDIR")"
  bash "$REPO_ROOT/adapters/cline.sh" install "$project" >/dev/null 2>&1
  printf '%s' "$project/.clinerules/.mb-manifest.json"
}

manifest_kilo() {
  local project
  project="$(mktemp -d -p "$WORKDIR")"
  (cd "$project" && git init -q && git config user.email t@t && git config user.name t)
  bash "$REPO_ROOT/adapters/kilo.sh" install "$project" >/dev/null 2>&1
  printf '%s' "$project/.kilocode/.mb-manifest.json"
}

manifest_opencode() {
  local project
  project="$(mktemp -d -p "$WORKDIR")"
  bash "$REPO_ROOT/adapters/opencode.sh" install "$project" >/dev/null 2>&1
  printf '%s' "$project/.opencode/.mb-manifest.json"
}

manifest_pi() {
  local project
  project="$(mktemp -d -p "$WORKDIR")"
  bash "$REPO_ROOT/adapters/pi.sh" install "$project" >/dev/null 2>&1
  printf '%s' "$project/.mb-pi-manifest.json"
}

manifest_pi_global_extensions() {
  local project home
  project="$(mktemp -d -p "$WORKDIR")"
  home="$(mktemp -d -p "$WORKDIR")"
  HOME="$home" bash "$REPO_ROOT/adapters/pi.sh" install-global-extensions "$project" >/dev/null 2>&1
  printf '%s' "$home/.pi/agent/.mb-global-extensions-manifest.json"
}

manifest_codex() {
  local project
  project="$(mktemp -d -p "$WORKDIR")"
  bash "$REPO_ROOT/adapters/codex.sh" install "$project" >/dev/null 2>&1
  printf '%s' "$project/.codex/.mb-manifest.json"
}

# adapter-parity T7 Codex-review fix: the SECOND OpenCode manifest (global
# scope, written by install-global-agents) is a distinct artifact from
# manifest_opencode() above and must declare its own platform_limited — a
# manifest limit declared here is guarded by the meta-tests below the same
# way as every project-scope manifest.
manifest_opencode_global_extensions() {
  local project home
  project="$(mktemp -d -p "$WORKDIR")"
  home="$(mktemp -d -p "$WORKDIR")"
  HOME="$home" bash "$REPO_ROOT/adapters/opencode.sh" install-global-agents "$project" >/dev/null 2>&1
  printf '%s' "$home/.config/opencode/.mb-global-extensions-manifest.json"
}

# ═══════════════════════════════════════════════════════════════
# (0) Every client declares SOMETHING (REQ-015: for every supported client)
# ═══════════════════════════════════════════════════════════════

@test "honesty: claude-code declares platform_limited == [] (reference tier)" {
  local m
  m="$(manifest_claude_code)"
  [ -f "$m" ]
  jq -e '.platform_limited == []' "$m" >/dev/null
}

@test "honesty: every non-reference client manifest has a platform_limited array" {
  local fn
  for fn in manifest_cursor manifest_windsurf manifest_cline manifest_kilo manifest_opencode manifest_pi manifest_codex; do
    local m
    m="$("$fn")"
    [ -f "$m" ]
    jq -e '.platform_limited | type == "array"' "$m" >/dev/null
  done
}

# ═══════════════════════════════════════════════════════════════
# (1) statusline — declared on all 7 non-CC clients; genuinely absent means
# no client wires scripts/mb-statusline.py or a statusLine-equivalent config
# key anywhere in its adapter.
# ═══════════════════════════════════════════════════════════════

@test "honesty negative: statusline is declared limited (with a reason) and genuinely never wired, on every non-CC client" {
  local adapter
  for adapter in cursor windsurf cline kilo opencode pi codex; do
    local m
    m="$(manifest_$adapter)"
    [ -f "$m" ]
    jq -e '.platform_limited | index("statusline") != null' "$m" >/dev/null \
      || fail "$adapter: platform_limited does not declare statusline"
    jq -e '.platform_limited_notes.statusline | length > 0' "$m" >/dev/null \
      || fail "$adapter: platform_limited_notes has no reason for statusline"
    _absent_from_code "$REPO_ROOT/adapters/$adapter.sh" "mb-statusline.py" \
      || fail "$adapter: adapter source references mb-statusline.py — statusline is not actually absent"
  done
}

# ═══════════════════════════════════════════════════════════════
# (2) subagents — declared on cursor/windsurf/cline/kilo/codex; genuinely
# absent means no dispatch mechanism reaches these hosts. Verified via
# scripts/mb-subinvoke-resolve.sh's TABLE (the single cross-host dispatch
# registry — pi.sh/opencode.sh cite it as such) having no entry for them.
# ═══════════════════════════════════════════════════════════════

@test "honesty negative: subagents is declared limited (with a reason) and genuinely absent, on hosts with no dispatch primitive" {
  local adapter
  for adapter in cursor windsurf cline kilo codex; do
    local m
    m="$(manifest_$adapter)"
    [ -f "$m" ]
    jq -e '.platform_limited | index("subagents") != null' "$m" >/dev/null \
      || fail "$adapter: platform_limited does not declare subagents"
    jq -e '.platform_limited_notes.subagents | length > 0' "$m" >/dev/null \
      || fail "$adapter: platform_limited_notes has no reason for subagents"
  done
  # No cross-host dispatch registry entry exists for any of them (the
  # single source of truth cited by pi.sh/codex.sh for their own dispatch
  # declarations) — genuinely nothing to route to.
  local a
  for a in cursor windsurf cline kilo; do
    refute_grep -q "\-\-agent $a\b" "$REPO_ROOT/scripts/mb-subinvoke-resolve.sh" \
      || fail "$a: mb-subinvoke-resolve.sh has a dispatch entry — subagents is not actually absent"
  done

  # adapter-parity T7 Codex-review fix (MAJOR): codex is NOT simply absent
  # from mb-subinvoke-resolve.sh's TABLE like cursor/windsurf/cline/kilo —
  # adapters/codex.sh HAS a `subinvoke` path (codex_subinvoke_cmd) and the
  # resolver has a `codex` TABLE entry, so the "not in the registry" check
  # above cannot prove codex's claim. What "subagents" actually means here
  # (design.md D-03): a Task-tool-equivalent IN-SESSION role/subagent
  # dispatch primitive — NOT a plain CLI fan-out invocation. Prove the
  # distinction genuinely: the resolver's --role scoping (the actual
  # per-ROLE dispatch mechanism — agents/<role>.md --tools/
  # --append-system-prompt injection, D-09) is implemented ONLY for pi;
  # passing --role to the codex arm must be silently ignored (same generic
  # `codex exec ... "$MB_FANOUT_PROMPT"` template regardless of role) — if a
  # future change made codex's template role-sensitive, that WOULD be a
  # genuine subagent-dispatch primitive and this assertion must fail.
  local codex_generic codex_with_role
  codex_generic="$(bash "$REPO_ROOT/scripts/mb-subinvoke-resolve.sh" --agent codex)"
  codex_with_role="$(bash "$REPO_ROOT/scripts/mb-subinvoke-resolve.sh" --agent codex --role mb-backend)"
  [ "$codex_generic" = "$codex_with_role" ] \
    || fail "codex: mb-subinvoke-resolve.sh --role changes the codex template — a real per-role subagent-dispatch primitive now exists, subagents is not actually absent"

  # And: no /mb work per-role headless dispatch call to codex exists either
  # (the in-session Task-tool-equivalent commands/work.md would need to
  # genuinely route per-role to codex to constitute "subagents").
  refute_grep -Eq -- '--agent codex --role' "$REPO_ROOT/commands/work.md" \
    || fail "codex: commands/work.md routes per-role to codex — subagents is not actually absent"
}

@test "honesty negative: opencode/pi are NOT declared subagents-limited — both have a genuine native dispatch primitive" {
  local m
  m="$(manifest_opencode)"
  jq -e '.platform_limited | index("subagents") == null' "$m" >/dev/null \
    || fail "opencode: subagents wrongly declared — .opencode/agent/*.md is a genuine native dispatch primitive (opencode.sh)"
  grep -q "OpenCode natively discovers dispatchable subagents" "$REPO_ROOT/adapters/opencode.sh"

  m="$(manifest_pi)"
  jq -e '.platform_limited | index("subagents") == null' "$m" >/dev/null \
    || fail "pi: subagents wrongly declared — mb_dispatch_subagent is a genuine opt-in dispatch tool (pi.sh)"
}

# ═══════════════════════════════════════════════════════════════
# (3) lifecycle-hooks — declared on windsurf/cline/kilo/codex; genuinely
# absent means no session-start-class hook (CC's SessionStart/PreCompact/
# Stop set) is wired — only isolated per-tool/per-prompt hooks or none.
# ═══════════════════════════════════════════════════════════════

@test "honesty negative: lifecycle-hooks is declared limited (with a reason) and no session-start-class hook exists" {
  local adapter
  for adapter in windsurf cline kilo codex; do
    local m
    m="$(manifest_$adapter)"
    [ -f "$m" ]
    jq -e '.platform_limited | index("lifecycle-hooks") != null' "$m" >/dev/null \
      || fail "$adapter: platform_limited does not declare lifecycle-hooks"
    jq -e '.platform_limited_notes["lifecycle-hooks"] | length > 0' "$m" >/dev/null \
      || fail "$adapter: platform_limited_notes has no reason for lifecycle-hooks"
  done

  # Structural proof: none of these adapters wire a CC session-start-class
  # event. Windsurf/Cline expose only user-prompt-submit-class and
  # per-tool-class events; Kilo has no native hooks API at all (its own
  # header comment); Codex wires exactly one experimental prompt hook.
  refute_grep -qE 'EVENT_BINDINGS.*sessionStart|"sessionStart:' "$REPO_ROOT/adapters/windsurf.sh"
  refute_grep -qE '"sessionStart' "$REPO_ROOT/adapters/cline.sh"
  refute_grep -q "hooks.json\|HOOKS_JSON" "$REPO_ROOT/adapters/kilo.sh"
  local hook_count
  hook_count=$(grep -c "userpromptsubmit\|hooks\.json" "$REPO_ROOT/adapters/codex.sh" || true)
  [ "$hook_count" -ge 1 ]
}

@test "honesty negative: cursor/opencode are NOT declared lifecycle-hooks-limited — both wire a session-start-class hook" {
  local m
  m="$(manifest_cursor)"
  jq -e '.platform_limited | index("lifecycle-hooks") == null' "$m" >/dev/null
  grep -q '"sessionStart:mb-session-start-context.sh"' "$REPO_ROOT/adapters/cursor.sh"

  m="$(manifest_opencode)"
  jq -e '.platform_limited | index("lifecycle-hooks") == null' "$m" >/dev/null
  grep -q "session.created\|session\.idle" "$REPO_ROOT/adapters/opencode.sh"
}

# ═══════════════════════════════════════════════════════════════
# (4) session-memory — declared on windsurf/cline/kilo/codex; genuinely
# absent means capture is a one-line progress.md stub, never a CC v2-schema
# session/*.md file. Runtime-proven, not just grepped (mirrors
# test_cross_agent_runtime_parity.bats's own methodology).
# ═══════════════════════════════════════════════════════════════

@test "honesty negative: session-memory is declared limited (with a reason) and capture is a progress.md stub, not session/*.md" {
  local adapter
  for adapter in windsurf cline kilo codex; do
    local m
    m="$(manifest_$adapter)"
    [ -f "$m" ]
    jq -e '.platform_limited | index("session-memory") != null' "$m" >/dev/null \
      || fail "$adapter: platform_limited does not declare session-memory"
    jq -e '.platform_limited_notes["session-memory"] | length > 0' "$m" >/dev/null \
      || fail "$adapter: platform_limited_notes has no reason for session-memory"
  done

  # Runtime proof for the git-hooks-fallback tier (kilo/codex): a real
  # commit only ever produces the progress.md stub, never session/*.md.
  local project
  project="$(mktemp -d -p "$WORKDIR")"
  (cd "$project" && git init -q && git config user.email t@t && git config user.name t)
  mkdir -p "$project/.memory-bank"
  echo '# Progress' > "$project/.memory-bank/progress.md"
  bash "$REPO_ROOT/adapters/git-hooks-fallback.sh" install "$project" >/dev/null
  (cd "$project" && MB_AUTO_CAPTURE=auto bash -c 'echo x > a.txt && git add a.txt && git commit -q -m first')
  grep -q "Auto-capture" "$project/.memory-bank/progress.md"
  [ ! -d "$project/.memory-bank/session" ] || [ -z "$(ls -A "$project/.memory-bank/session" 2>/dev/null)" ]
}

@test "honesty negative: windsurf/cline runtime capture never creates session/*.md (progress.md stub only)" {
  local adapter script
  for adapter in windsurf cline; do
    local project payload sid
    project="$(mktemp -d -p "$WORKDIR")"
    mkdir -p "$project/.memory-bank"
    echo '# Progress' > "$project/.memory-bank/progress.md"
    sid="stub-${adapter}-sid"
    if [ "$adapter" = "windsurf" ]; then
      bash "$REPO_ROOT/adapters/windsurf.sh" install "$project" >/dev/null 2>&1
      payload="$(jq -n --arg cwd "$project" --arg sid "$sid" '{workspaceRoot: $cwd, sessionId: $sid}')"
      script="$project/.windsurf/hooks/after-response.sh"
    else
      bash "$REPO_ROOT/adapters/cline.sh" install "$project" >/dev/null 2>&1
      payload="$(jq -n --arg cwd "$project" --arg sid "$sid" '{workspaceRoot: $cwd, sessionId: $sid}')"
      script="$project/.clinerules/hooks/after-tool.sh"
    fi
    [ -f "$script" ]
    run env MB_AUTO_CAPTURE=auto bash -c "printf '%s' \"\$1\" | \"\$2\"" _ "$payload" "$script"
    [ "$status" -eq 0 ]
    grep -q "Auto-capture" "$project/.memory-bank/progress.md"
    [ ! -d "$project/.memory-bank/session" ] || [ -z "$(ls -A "$project/.memory-bank/session" 2>/dev/null)" ]
  done
}

@test "honesty negative: cursor/opencode are NOT declared session-memory-limited — both produce genuine CC v2-schema captures" {
  local m
  m="$(manifest_cursor)"
  jq -e '.platform_limited | index("session-memory") == null' "$m" >/dev/null
  # Real proof lives in test_cursor_adapter.bats's REQ-021 tests (stop+sessionEnd
  # end-to-end creates a real session/*.md); re-asserting the wiring here.
  grep -q '"stop:mb-session-turn.sh"' "$REPO_ROOT/adapters/cursor.sh"

  # adapter-parity T7 Codex-review fix (BLOCKER): manifest_opencode() alone
  # installs the BASE (declined) plugin variant, whose chat.message handler
  # is a deliberate no-op (MB_OC_PARITY_EXTENDED=false — see
  # test_opencode_adapter.bats's "base (non-extended) plugin's chat.message
  # hook is a no-op" test). Grepping for the string "chat.message" only
  # proves a gated handler EXISTS in the source, not that the manifest
  # state under evaluation genuinely supports session-memory. Install with
  # MB_OC_PARITY_ACCEPTED=1 (the actual "session-memory NOT limited" state,
  # set by install.sh's accept path — AGR-013) and prove capture by RUNNING
  # the extended plugin's chat.message handler, asserting a real CC
  # v2-schema session/*.md file is created — not a source-grep proxy.
  local oc_project
  oc_project="$(mktemp -d -p "$WORKDIR")"
  MB_OC_PARITY_ACCEPTED=1 bash "$REPO_ROOT/adapters/opencode.sh" install "$oc_project" >/dev/null 2>&1
  m="$oc_project/.opencode/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.platform_limited | index("session-memory") == null' "$m" >/dev/null

  command -v node >/dev/null || skip "node required for the opencode runtime session-memory proof"
  mkdir -p "$oc_project/.memory-bank"
  local plugin_mjs="$oc_project/mb-plugin-honesty.mjs"
  cp "$oc_project/.opencode/plugins/memory-bank.js" "$plugin_mjs"
  run env MB_SESSION_CAPTURE=on node -e "
    import('file://$plugin_mjs').then(async (mod) => {
      const plugin = await mod.default({ directory: '$oc_project' });
      const out = { message: { id: 'm1', sessionID: 'honesty-sess' }, parts: [{ type: 'text', text: 'honesty check' }] };
      await plugin['chat.message']({ sessionID: 'honesty-sess' }, out);
    }).catch((e) => { console.error(e); process.exitCode = 1; });
  "
  [ "$status" -eq 0 ]

  local sfile
  sfile=$(ls "$oc_project/.memory-bank/session/"*.md 2>/dev/null | head -1)
  [ -n "$sfile" ] \
    || fail "opencode: MB_OC_PARITY_ACCEPTED=1 chat.message did not create a real session/*.md file — session-memory would then be genuinely limited, not falsely claimed as unlimited"
  grep -q "^session_id: honesty-sess$" "$sfile"
  grep -q "^agent: opencode$" "$sfile"
  grep -q "^summary_schema: v2$" "$sfile"
}

# ═══════════════════════════════════════════════════════════════
# (5) update-notify — declared on windsurf/cline/kilo only; genuinely absent
# means no transport anywhere in the adapter renders the notice.
# ═══════════════════════════════════════════════════════════════

@test "honesty negative: update-notify is declared limited (with a reason) and genuinely never wired, on windsurf/cline/kilo" {
  local adapter
  for adapter in windsurf cline kilo; do
    local m
    m="$(manifest_$adapter)"
    [ -f "$m" ]
    jq -e '.platform_limited | index("update-notify") != null' "$m" >/dev/null \
      || fail "$adapter: platform_limited does not declare update-notify"
    jq -e '.platform_limited_notes["update-notify"] | length > 0' "$m" >/dev/null \
      || fail "$adapter: platform_limited_notes has no reason for update-notify"
    { _absent_from_code "$REPO_ROOT/adapters/$adapter.sh" "mb-update-notify.sh" \
      && _absent_from_code "$REPO_ROOT/adapters/$adapter.sh" "mb-version-check.sh"; } \
      || fail "$adapter: adapter source references an update-notify transport — not actually absent"
  done
}

@test "honesty negative: codex is NOT declared update-notify-limited — T6 genuinely renders it" {
  local m
  m="$(manifest_codex)"
  jq -e '.platform_limited | index("update-notify") == null' "$m" >/dev/null
  grep -q "mb-update-notify.sh" "$REPO_ROOT/adapters/codex.sh"
}

# ═══════════════════════════════════════════════════════════════
# (6) role-routing — declared on pi (both manifests) + opencode; genuinely
# means /mb work's dispatch (commands/work.md 5a) never branches per host,
# only ever calling the Claude Code Task tool (backlog I-121/I-122).
# ═══════════════════════════════════════════════════════════════

@test "honesty negative: role-routing is declared limited (with a reason) on pi + opencode, and /mb work never routes per-host" {
  local m
  m="$(manifest_opencode)"
  jq -e '.platform_limited | index("role-routing") != null' "$m" >/dev/null
  jq -e '.platform_limited_notes["role-routing"] | length > 0' "$m" >/dev/null

  m="$(manifest_pi)"
  jq -e '.platform_limited | index("role-routing") != null' "$m" >/dev/null
  jq -e '.platform_limited_notes["role-routing"] | length > 0' "$m" >/dev/null

  m="$(manifest_pi_global_extensions)"
  [ -f "$m" ]
  jq -e '.platform_limited == ["role-routing"]' "$m" >/dev/null

  # adapter-parity T7 Codex-review fix: the SECOND OpenCode manifest
  # (global scope) must declare the SAME two limits as the project-scope
  # manifest above — same adapter source file, same genuine ceilings.
  m="$(manifest_opencode_global_extensions)"
  [ -f "$m" ]
  jq -e '.platform_limited == ["statusline","role-routing"]' "$m" >/dev/null
  jq -e '.platform_limited_notes["role-routing"] | length > 0' "$m" >/dev/null
  jq -e '.platform_limited_notes.statusline | length > 0' "$m" >/dev/null
  # Structural proof for its statusline claim: same shared adapter source
  # file as manifest_opencode() (adapters/opencode.sh) — the absence check
  # already run in test (1) above covers this manifest's own claim too, but
  # is re-asserted here so this pairing carries its own genuine evidence
  # rather than resting on another test's side effect.
  _absent_from_code "$REPO_ROOT/adapters/opencode.sh" "mb-statusline.py" \
    || fail "opencode (global manifest): adapter source references mb-statusline.py — statusline is not actually absent"

  # Structural proof: commands/work.md's implement step dispatches
  # exclusively via the Claude Code Task tool — no per-role headless
  # dispatch call to any non-CC host exists in the executor.
  grep -q "Dispatch via \`Task\`" "$REPO_ROOT/commands/work.md"
  ! grep -Eq -- '--agent (pi|opencode) --role' "$REPO_ROOT/commands/work.md"
}

# ═══════════════════════════════════════════════════════════════
# (7) META-TEST (REQ-017 enforcement): every declared value is in the closed
# vocabulary AND has a matching negative test registered above — a manifest
# limit with no corresponding assertion fails the suite, so it can never
# silently drift out of sync with what is actually tested.
# ═══════════════════════════════════════════════════════════════

CLOSED_VOCAB=(statusline subagents lifecycle-hooks session-memory update-notify role-routing)

# (client:capability) pairs asserted as genuinely-absent-with-a-reason above.
TESTED_PAIRS=(
  "cursor:statusline" "cursor:subagents"
  "windsurf:statusline" "windsurf:subagents" "windsurf:lifecycle-hooks" "windsurf:session-memory" "windsurf:update-notify"
  "cline:statusline" "cline:subagents" "cline:lifecycle-hooks" "cline:session-memory" "cline:update-notify"
  "kilo:statusline" "kilo:subagents" "kilo:lifecycle-hooks" "kilo:session-memory" "kilo:update-notify"
  "opencode:statusline" "opencode:role-routing"
  "pi:statusline" "pi:role-routing"
  "codex:statusline" "codex:subagents" "codex:lifecycle-hooks" "codex:session-memory"
  "opencode_global_extensions:statusline" "opencode_global_extensions:role-routing"
)

_in_array() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

@test "honesty meta-test: every declared platform_limited value is in the closed vocabulary" {
  local fn client
  for fn in manifest_cursor manifest_windsurf manifest_cline manifest_kilo manifest_opencode manifest_pi manifest_codex manifest_opencode_global_extensions; do
    client="${fn#manifest_}"
    local m item
    m="$("$fn")"
    [ -f "$m" ]
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      _in_array "$item" "${CLOSED_VOCAB[@]}" \
        || fail "$client: '$item' is not in the closed vocabulary (${CLOSED_VOCAB[*]}) — design.md drift"
    done < <(jq -r '.platform_limited[]?' "$m")
  done
}

@test "honesty meta-test: every declared platform_limited value has a matching negative test (REQ-017)" {
  local fn client
  for fn in manifest_cursor manifest_windsurf manifest_cline manifest_kilo manifest_opencode manifest_pi manifest_codex manifest_opencode_global_extensions; do
    client="${fn#manifest_}"
    local m item
    m="$("$fn")"
    [ -f "$m" ]
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      _in_array "${client}:${item}" "${TESTED_PAIRS[@]}" \
        || fail "$client: '$item' is declared in platform_limited but has no matching negative test (REQ-017) — register it in TESTED_PAIRS and add the assertion above"
    done < <(jq -r '.platform_limited[]?' "$m")
  done
}
