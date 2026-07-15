#!/usr/bin/env bats
# Tests for the adapter-parity extension offer (install.sh, T2).
#
# Contract (design.md "Extension offer contract"):
#   Input:  client list + interactivity (TTY?) + `--with-extensions[=pi,opencode]`
#           flag / `MB_WITH_EXTENSIONS` env.
#   Behavior:
#     - TTY without flag       → one prompt per host family present (default N).
#     - flag/env present       → install without prompting (REQ-005).
#     - no TTY and no flag     → skip silently (REQ-002 default, NFR-001).
#   Output: manifest (top-level .installed-manifest.json written by install.sh)
#           records `extensions_installed: [...]` — empty when declined/skipped.
#   No pi/opencode in --clients → the offer is never shown at all.
#
# T2 ships the offer PLUMBING only: `mb_install_host_extensions <host>` is a
# logging-only stub (real installers land in T3/pi, T5/opencode) — it never
# writes a file, so accept vs decline is only observable via stdout + the
# manifest field, not via new files on disk.
#
# Isolation (mirrors test_install_ships_research_tooling.bats, LESSON L64):
# install.sh writes its manifest to "$SOURCE_SKILL_DIR/.installed-manifest.json"
# — install from a TMP copy of the repo + a sandboxed $HOME so nothing under
# the real repo or the real $HOME is ever mutated.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  command -v jq >/dev/null || skip "jq required"
  command -v rsync >/dev/null || skip "rsync required"
  unset MB_WITH_EXTENSIONS MB_CLIENTS MB_LANGUAGE

  FAKE_HOME="$(mktemp -d)"
  PROJECT="$(mktemp -d)"

  SKILL_SRC="$(mktemp -d)/skill"
  mkdir -p "$SKILL_SRC"
  # --exclude of volatile dirs: a concurrently-running semantic-search indexer
  # (.memsearch/.index.pid) or a calibration run (tests/calibration/results/*.json,
  # written every few seconds by a parallel session) can create/remove files
  # mid-scan, making rsync's "file vanished" (status 23) a spurious flake
  # unrelated to anything under test here.
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='.memsearch' \
    --exclude='/tests/calibration/results' \
    --exclude='node_modules' \
    "$REPO_ROOT/" "$SKILL_SRC/"

  INSTALL="$SKILL_SRC/install.sh"
  MANIFEST="$SKILL_SRC/.installed-manifest.json"
}

teardown() {
  [ -n "${FAKE_HOME:-}" ] && [ -d "$FAKE_HOME" ] && rm -rf "$FAKE_HOME"
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
  if [ -n "${SKILL_SRC:-}" ]; then
    rm -rf "$(dirname "$SKILL_SRC")"
  fi
  for d in "${EXTRA_TMP_DIRS[@]:-}"; do
    if [ -n "$d" ] && [ -d "$d" ]; then
      rm -rf "$d"
    fi
  done
  true
}

run_install() {
  local raw
  raw=$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" "$@" </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# Help text documents the flag
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: --help documents --with-extensions" {
  run_install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--with-extensions"* ]]
}

# ═══════════════════════════════════════════════════════════════
# No pi/opencode in --clients → offer never shown, manifest field empty
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: clients without pi/opencode never offers extensions" {
  run_install --clients claude-code --project-root "$PROJECT" --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" != *"parity extension"* ]]
  [ -f "$MANIFEST" ]
  jq -e '.extensions_installed == []' "$MANIFEST" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# No TTY + no flag → silent skip (REQ-002 default), manifest honest
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: no TTY and no flag skips silently, manifest extensions_installed=[]" {
  run_install --clients pi,opencode --project-root "$PROJECT" --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" != *"Install pi parity extensions"* ]]
  [[ "$output" != *"Install opencode parity extensions"* ]]
  [ -f "$MANIFEST" ]
  jq -e '.extensions_installed == []' "$MANIFEST" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# --with-extensions bare flag → both offered hosts accepted, hook invoked
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: bare --with-extensions accepts every offered host" {
  run_install --clients pi,opencode --project-root "$PROJECT" --non-interactive --with-extensions
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi parity extensions"* ]]
  [[ "$output" == *"opencode parity extensions"* ]]
  # pi: T3 landed — real files land in the global Pi extensions dir.
  [ -f "$FAKE_HOME/.pi/agent/extensions/memory-bank-session.ts" ]
  [ -f "$FAKE_HOME/.pi/agent/extensions/memory-bank-graph-rag.ts" ]
  # opencode: T5 landed — global agent roster lands under
  # ~/.config/opencode/agent/, and this project's plugin.js is the
  # EXTENDED variant (session-start context injection + per-turn capture).
  [ -f "$FAKE_HOME/.config/opencode/agent/mb-developer.md" ]
  grep -q "^const MB_OC_PARITY_EXTENDED = true;" \
    "$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$MANIFEST" ]
  jq -e '.extensions_installed == ["pi", "opencode"]' "$MANIFEST" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# --with-extensions=<host> scopes to the named host only
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: --with-extensions=pi scopes to pi only" {
  run_install --clients pi,opencode --project-root "$PROJECT" --non-interactive --with-extensions=pi
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi parity extensions"* ]]
  [[ "$output" != *"opencode parity extensions"* ]]
  [ -f "$FAKE_HOME/.pi/agent/extensions/memory-bank-session.ts" ]
  [ ! -d "$PROJECT/.opencode/extensions" ]
  jq -e '.extensions_installed == ["pi"]' "$MANIFEST" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# MB_WITH_EXTENSIONS env — same contract as the flag
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: MB_WITH_EXTENSIONS=pi,opencode env accepts both, no flag needed" {
  local raw
  raw=$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 MB_WITH_EXTENSIONS="pi,opencode" \
        bash "$INSTALL" --clients pi,opencode --project-root "$PROJECT" --non-interactive \
        </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi parity extensions"* ]]
  [[ "$output" == *"opencode parity extensions"* ]]
  jq -e '.extensions_installed == ["pi", "opencode"]' "$MANIFEST" >/dev/null
}

@test "extensions-offer: MB_WITH_EXTENSIONS=pi (single host) leaves opencode declined" {
  local raw
  raw=$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 MB_WITH_EXTENSIONS="pi" \
        bash "$INSTALL" --clients pi,opencode --project-root "$PROJECT" --non-interactive \
        </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi parity extensions"* ]]
  [[ "$output" != *"opencode parity extensions"* ]]
  jq -e '.extensions_installed == ["pi"]' "$MANIFEST" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# --with-extensions never shown/consulted when host not in --clients
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: --with-extensions=pi is a no-op when pi is not in --clients" {
  run_install --clients opencode --project-root "$PROJECT" --non-interactive --with-extensions=pi
  [ "$status" -eq 0 ]
  [[ "$output" != *"pi parity extensions"* ]]
  [[ "$output" != *"opencode parity extensions"* ]]
  jq -e '.extensions_installed == []' "$MANIFEST" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# mb_install_host_extensions: both pi (T3) and opencode (T5) are real
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: accepted pi AND opencode both install real extension artifacts" {
  run_install --clients pi,opencode --project-root "$PROJECT" --non-interactive --with-extensions
  [ "$status" -eq 0 ]
  # T3 landed — pi's real target now exists, placeholder-free.
  local session_ext="$FAKE_HOME/.pi/agent/extensions/memory-bank-session.ts"
  local graph_ext="$FAKE_HOME/.pi/agent/extensions/memory-bank-graph-rag.ts"
  [ -f "$session_ext" ]
  [ -f "$graph_ext" ]
  ! grep -q '__MB_' "$session_ext"
  ! grep -q '__MB_' "$graph_ext"
  # T5 landed — opencode's real targets: global agent roster + this
  # project's plugin.js upgraded to the extended (session-start injection +
  # per-turn capture) variant.
  [ -f "$FAKE_HOME/.config/opencode/agent/mb-developer.md" ]
  ! grep -q '__MB_' "$FAKE_HOME/.config/opencode/agent/mb-developer.md"
  grep -q "^const MB_OC_PARITY_EXTENDED = true;" \
    "$PROJECT/.opencode/plugins/memory-bank.js"
  # No stray un-designed .opencode/extensions dir — OpenCode's global
  # artifact is the agent roster, not a project-local extensions/ dir.
  [ ! -d "$PROJECT/.opencode/extensions" ]
}

# Codex review fix (major #1): a failed install-global-agents used to leave
# MB_OC_PARITY_ACCEPTED=1 exported anyway (it was set BEFORE the success
# check) — Step 8's unconditional plugin write then still upgraded to the
# EXTENDED variant despite opencode never being recorded in
# extensions_installed[]. Force the failure SURGICALLY: pre-create
# ~/.config/opencode as a real DIRECTORY (so install.sh's own unrelated,
# pre-existing install_opencode_global_agents step — which also does
# `mkdir -p "$HOME/.config/opencode"` for the global AGENTS.md — keeps
# working) but put a REGULAR FILE at .../opencode/agent, the exact path
# adapters/opencode.sh install-global-agents needs as a directory. Per the
# documented "never fatal" extension-offer contract
# (mb_install_host_extensions's own header comment: "Non-zero → offer
# accepted but installation failed; the host is NOT recorded, install
# continues"), the overall install.sh run still exits 0 — only the
# opencode-specific artifacts must reflect the failure honestly.
@test "extensions-offer: a failed opencode global-agents install leaves the plugin at the BASE variant (not extended)" {
  mkdir -p "$FAKE_HOME/.config/opencode"
  : > "$FAKE_HOME/.config/opencode/agent"  # regular file where a dir is expected

  run_install --clients opencode --project-root "$PROJECT" --non-interactive --with-extensions=opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"global agents install failed"* ]]
  # extensions_installed must NOT record opencode on a failed install.
  [ -f "$MANIFEST" ]
  jq -e '.extensions_installed == []' "$MANIFEST" >/dev/null
  # The project's plugin.js must stay the BASE variant — the dishonest-state
  # bug this test guards against.
  [ -f "$PROJECT/.opencode/plugins/memory-bank.js" ]
  grep -q "^const MB_OC_PARITY_EXTENDED = false;" \
    "$PROJECT/.opencode/plugins/memory-bank.js"
}

# ═══════════════════════════════════════════════════════════════
# AGENTS.md managed block carries the session-start nudge (REQ-020/D-08)
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: AGENTS.md managed block includes the session-start extension nudge" {
  run_install --clients opencode --project-root "$PROJECT" --non-interactive
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q -- "--with-extensions" "$PROJECT/AGENTS.md"
  grep -qi "once per session" "$PROJECT/AGENTS.md"
}

@test "extensions-offer: pi-only install AGENTS.md also carries the nudge" {
  run_install --clients pi --project-root "$PROJECT" --non-interactive
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q -- "--with-extensions" "$PROJECT/AGENTS.md"
}

# ═══════════════════════════════════════════════════════════════
# REQ-020 is literally scoped to "a pi or opencode host" — codex shares the
# AGENTS.md format but has no parity-extensions target, so a codex-only
# install must not advertise a flag that does nothing for it.
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: codex-only install AGENTS.md has NO host-parity nudge" {
  run_install --clients codex --project-root "$PROJECT" --non-interactive
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  [[ "$(cat "$PROJECT/AGENTS.md")" != *"--with-extensions"* ]]
  [[ "$(cat "$PROJECT/AGENTS.md")" != *"Host parity extensions"* ]]
}

@test "extensions-offer: codex + pi in the same project keeps the nudge (shared AGENTS.md, any owner order)" {
  run_install --clients codex,pi --project-root "$PROJECT" --non-interactive
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q -- "--with-extensions" "$PROJECT/AGENTS.md"
}

# ═══════════════════════════════════════════════════════════════
# Unknown --with-extensions/MB_WITH_EXTENSIONS host values are a closed-set
# violation (almost certainly a typo), not a silent no-op.
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: unknown --with-extensions host value is rejected, not silently ignored" {
  # Snapshot MANIFEST before the run rather than asserting outright absence:
  # SKILL_SRC is an rsync copy of the WHOLE repo (setup(), above), so a
  # gitignored .installed-manifest.json left over from an unrelated manual
  # `bash install.sh` elsewhere in the working tree can legitimately already
  # exist pre-run. The real contract is "this rejected run wrote nothing" —
  # proven by byte-identity, not by requiring a clean starting state.
  local manifest_before=""
  [ -f "$MANIFEST" ] && manifest_before="$(cat "$MANIFEST")"

  run_install --clients pi --project-root "$PROJECT" --non-interactive --with-extensions=pie
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown --with-extensions host"* ]]

  if [ -f "$MANIFEST" ]; then
    [ "$(cat "$MANIFEST")" = "$manifest_before" ]
  else
    [ -z "$manifest_before" ]
  fi
}

@test "extensions-offer: --with-extensions='open code' (internal whitespace) is rejected, not silently normalized to opencode" {
  run_install --clients pi --project-root "$PROJECT" --non-interactive "--with-extensions=open code"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown --with-extensions host"* ]]
}

@test "extensions-offer: --with-extensions=' pi ' (leading/trailing whitespace only) is still accepted" {
  run_install --clients pi --project-root "$PROJECT" --non-interactive "--with-extensions= pi "
  [ "$status" -eq 0 ]
  [[ "$output" == *"pi parity extensions"* ]]
}

@test "extensions-offer: unknown MB_WITH_EXTENSIONS host value is rejected via env too" {
  local raw
  raw=$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 MB_WITH_EXTENSIONS="pie" \
        bash "$INSTALL" --clients pi --project-root "$PROJECT" --non-interactive \
        </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown --with-extensions host"* ]]
}

# ═══════════════════════════════════════════════════════════════
# NFR-001 regression fixture: declined path stays byte-identical to the
# pre-task install.sh + adapters/_lib_agents_md.sh (the only two files this
# task touches for the install flow). Every other file in the working tree
# may already carry unrelated concurrent WIP — reusing identical absolute
# paths for BOTH runs (same SKILL_SRC/HOME/PROJECT path, repopulated between
# runs, never regenerated) isolates the diff to exactly this task's delta,
# AND means stdout needs no volatile-path normalization: nothing in either
# run's stdout can legitimately differ, so it is compared byte-for-byte
# with a plain `=`.
#
# Filesystem diff keeps two — and only two — EXACT deltas, verified per file
# (not a regex-class exclusion that would wave through any other change to a
# same-named file):
#   - AGENTS.md: gains EXACTLY the host-parity nudge block (checked by
#     reconstructing the expected post-fix content from the pre-fix content
#     and requiring a byte match — not "any AGENTS.md diff").
#   - *manifest*.json: may differ ONLY in `installed_at` / `extensions_installed`
#     (checked via `jq -S 'del(...)'` equality — not "any manifest diff").
# Any file present in only one tree, or differing in any other way, fails.
# ═══════════════════════════════════════════════════════════════

# Reconstructs the expected post-fix AGENTS.md from a pre-fix one by
# inserting the EXACT host-parity nudge block _agents_md_section emits —
# single source of truth so the NFR-001 assertion below is "this diff IS the
# nudge block", not "this diff merely mentions AGENTS.md".
_nfr001_insert_nudge_block() {
  awk '
    /^## Dynamic-flow firewall \(completion gate\)$/ && !done {
      print "## Host parity extensions (Pi/OpenCode)"
      print ""
      print "On a bare Pi or OpenCode host (no parity extensions installed yet), suggest running `install.sh --with-extensions=pi,opencode` once per session, then stay silent once installed."
      print ""
      done = 1
    }
    { print }
  ' "$1"
}

# $1 = old snapshot dir, $2 = new (live) dir. Every relative path must exist
# in both, byte-identical, EXCEPT the two named deltas above — verified
# individually per differing file, not filtered out by a broad pattern.
_nfr001_assert_exact_tree_delta() {
  local old_dir="$1" new_dir="$2"
  local old_list new_list
  old_list="$(cd "$old_dir" && find . -type f | sort)"
  new_list="$(cd "$new_dir" && find . -type f | sort)"
  if [ "$old_list" != "$new_list" ]; then
    echo "file set changed under $old_dir vs $new_dir:" >&2
    diff <(printf '%s\n' "$old_list") <(printf '%s\n' "$new_list") >&2 || true
    return 1
  fi

  local rel of nf base tmp_expected
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    of="$old_dir/$rel"
    nf="$new_dir/$rel"
    cmp -s "$of" "$nf" && continue   # byte-identical — nothing to verify

    base="$(basename "$rel")"
    case "$base" in
      *manifest*.json)
        if ! diff -q <(jq -S 'del(.installed_at, .extensions_installed)' "$of") \
                      <(jq -S 'del(.installed_at, .extensions_installed)' "$nf") >/dev/null 2>&1; then
          echo "manifest content differs beyond installed_at/extensions_installed: $rel" >&2
          diff <(jq -S 'del(.installed_at, .extensions_installed)' "$of") \
               <(jq -S 'del(.installed_at, .extensions_installed)' "$nf") >&2 || true
          return 1
        fi
        ;;
      AGENTS.md)
        tmp_expected="$(mktemp)"
        _nfr001_insert_nudge_block "$of" > "$tmp_expected"
        if ! diff -q "$tmp_expected" "$nf" >/dev/null 2>&1; then
          echo "AGENTS.md delta is not EXACTLY the host-parity nudge block: $rel" >&2
          diff "$tmp_expected" "$nf" >&2 || true
          rm -f "$tmp_expected"
          return 1
        fi
        rm -f "$tmp_expected"
        ;;
      *)
        echo "unexpected filesystem delta outside the two named NFR-001 exceptions: $rel" >&2
        diff "$of" "$nf" >&2 || true
        return 1
        ;;
    esac
  done <<< "$old_list"

  return 0
}

@test "extensions-offer: declined install is byte-identical to the pre-task install.sh (NFR-001)" {
  git -C "$REPO_ROOT" cat-file -e HEAD:install.sh 2>/dev/null || skip "no git HEAD to diff against"
  git -C "$REPO_ROOT" cat-file -e HEAD:adapters/_lib_agents_md.sh 2>/dev/null || skip "no git HEAD to diff against"

  local old_home_snap old_project_snap old_stdout new_stdout
  old_home_snap="$(mktemp -d)"
  old_project_snap="$(mktemp -d)"
  EXTRA_TMP_DIRS=("$old_home_snap" "$old_project_snap")

  # --- OLD run: pre-task install.sh + _lib_agents_md.sh, everything else as-is ---
  git -C "$REPO_ROOT" show HEAD:install.sh > "$SKILL_SRC/install.sh"
  git -C "$REPO_ROOT" show HEAD:adapters/_lib_agents_md.sh > "$SKILL_SRC/adapters/_lib_agents_md.sh"
  chmod +x "$SKILL_SRC/install.sh"

  old_stdout="$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" \
    --clients pi,opencode --project-root "$PROJECT" --non-interactive </dev/null 2>&1)"
  [ "$?" -eq 0 ]

  rsync -a "$FAKE_HOME/" "$old_home_snap/"
  rsync -a "$PROJECT/" "$old_project_snap/"

  # Reset HOME/PROJECT (SKILL_SRC/HOME/PROJECT paths stay the SAME absolute
  # strings across both runs — only their contents are reset), restore the
  # working-tree (post-task) install.sh/_lib_agents_md.sh.
  rm -rf "$FAKE_HOME" "$PROJECT"
  mkdir -p "$FAKE_HOME" "$PROJECT"
  rsync -a "$REPO_ROOT/install.sh" "$SKILL_SRC/install.sh"
  rsync -a "$REPO_ROOT/adapters/_lib_agents_md.sh" "$SKILL_SRC/adapters/_lib_agents_md.sh"

  # --- NEW run: post-task install.sh + _lib_agents_md.sh, declined path ---
  new_stdout="$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" \
    --clients pi,opencode --project-root "$PROJECT" --non-interactive </dev/null 2>&1)"
  [ "$?" -eq 0 ]

  # Same absolute paths both runs → exact compare, no normalization needed.
  if [ "$old_stdout" != "$new_stdout" ]; then
    diff <(printf '%s\n' "$old_stdout") <(printf '%s\n' "$new_stdout") >&2 || true
    echo "stdout diverged on the declined path — NFR-001 violated" >&2
    return 1
  fi

  _nfr001_assert_exact_tree_delta "$old_home_snap" "$FAKE_HOME"
  _nfr001_assert_exact_tree_delta "$old_project_snap" "$PROJECT"

  # NOTE: this fixture uses HEAD:install.sh / HEAD:_lib_agents_md.sh as the
  # "old" baseline. Once adapter-parity (T2) is COMMITTED, HEAD already carries
  # the offer machinery, so the OLD and NEW declined-path outputs are identical
  # by design — the test now guards "a later task (T3+) must not change the
  # DECLINED path vs the last committed version", verified by the exact-tree-
  # delta above (any drift → fail). We deliberately do NOT assert "the nudge
  # delta happened" here (that was only meaningful against a pre-nudge
  # baseline): nudge PRESENCE is covered by the dedicated tests
  # "AGENTS.md managed block includes the nudge" / "pi-only ... carries the
  # nudge" / "codex + pi ... keeps the nudge".
}

# ═══════════════════════════════════════════════════════════════
# Codex-only variant of the NFR-001 fixture: after the REQ-020 scoping fix,
# a codex-only project's AGENTS.md carries no nudge at all — so unlike the
# pi/opencode case above, it is byte-identical to the pre-task output too,
# not merely excluded from the diff.
# ═══════════════════════════════════════════════════════════════

@test "extensions-offer: codex-only declined install's project AGENTS.md is byte-identical (NFR-001)" {
  git -C "$REPO_ROOT" cat-file -e HEAD:install.sh 2>/dev/null || skip "no git HEAD to diff against"
  git -C "$REPO_ROOT" cat-file -e HEAD:adapters/_lib_agents_md.sh 2>/dev/null || skip "no git HEAD to diff against"
  git -C "$REPO_ROOT" cat-file -e HEAD:adapters/codex.sh 2>/dev/null || skip "no git HEAD to diff against"

  local snap_dir old_agents_md new_agents_md old_stdout new_stdout
  snap_dir="$(mktemp -d)"
  EXTRA_TMP_DIRS=("$snap_dir")
  old_agents_md="$snap_dir/old-AGENTS.md"
  new_agents_md="$snap_dir/new-AGENTS.md"

  git -C "$REPO_ROOT" show HEAD:install.sh > "$SKILL_SRC/install.sh"
  git -C "$REPO_ROOT" show HEAD:adapters/_lib_agents_md.sh > "$SKILL_SRC/adapters/_lib_agents_md.sh"
  git -C "$REPO_ROOT" show HEAD:adapters/codex.sh > "$SKILL_SRC/adapters/codex.sh"
  chmod +x "$SKILL_SRC/install.sh"

  old_stdout="$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" \
    --clients codex --project-root "$PROJECT" --non-interactive </dev/null 2>&1)"
  [ "$?" -eq 0 ]
  cp "$PROJECT/AGENTS.md" "$old_agents_md"

  rm -rf "$FAKE_HOME" "$PROJECT"
  mkdir -p "$FAKE_HOME" "$PROJECT"
  rsync -a "$REPO_ROOT/install.sh" "$SKILL_SRC/install.sh"
  rsync -a "$REPO_ROOT/adapters/_lib_agents_md.sh" "$SKILL_SRC/adapters/_lib_agents_md.sh"
  rsync -a "$REPO_ROOT/adapters/codex.sh" "$SKILL_SRC/adapters/codex.sh"

  new_stdout="$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" \
    --clients codex --project-root "$PROJECT" --non-interactive </dev/null 2>&1)"
  [ "$?" -eq 0 ]
  cp "$PROJECT/AGENTS.md" "$new_agents_md"

  # Same absolute paths both runs → exact compare, no normalization needed.
  [ "$old_stdout" = "$new_stdout" ]

  diff -q "$old_agents_md" "$new_agents_md"
}
