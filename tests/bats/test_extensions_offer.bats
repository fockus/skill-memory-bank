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

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  command -v jq >/dev/null || skip "jq required"
  command -v rsync >/dev/null || skip "rsync required"
  # MB_MANIFEST_PATH: the manifest must land in the SKILL_SRC copy (asserted below).
  unset MB_WITH_EXTENSIONS MB_CLIENTS MB_LANGUAGE MB_MANIFEST_PATH CODEX_HOME

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
  grep -qF 'export default createMemoryBankPlugin({ extended: true });' \
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
  refute_grep -q '__MB_' "$FAKE_HOME/.config/opencode/agent/mb-developer.md"
  grep -qF 'export default createMemoryBankPlugin({ extended: true });' \
    "$PROJECT/.opencode/plugins/memory-bank.js"
  # No stray un-designed .opencode/extensions dir — OpenCode's global
  # artifact is the agent roster, not a project-local extensions/ dir.
  [ ! -d "$PROJECT/.opencode/extensions" ]
}

# A global-role refusal must not enable a fresh project plugin or overwrite its blocker.
@test "extensions-offer: a failed opencode global-agents install refuses without enabling a fresh plugin" {
  mkdir -p "$FAKE_HOME/.config/opencode"
  printf 'User agent blocker\n' > "$FAKE_HOME/.config/opencode/agent"
  snapshot "$FAKE_HOME/.config/opencode/agent" "$BATS_TEST_TMPDIR/blocker.before"

  run_install --clients opencode --project-root "$PROJECT" --non-interactive --with-extensions=opencode
  [ "$status" -ne 0 ]
  [[ "$output" == *"global agents install failed"* ]]
  [ -f "$FAKE_HOME/.config/opencode/agent" ]
  assert_unchanged "$FAKE_HOME/.config/opencode/agent" "$BATS_TEST_TMPDIR/blocker.before"
  # extensions_installed must NOT record opencode on a failed install.
  [ -f "$MANIFEST" ]
  jq -e '.extensions_installed == []' "$MANIFEST" >/dev/null
  jq -e '.adapters_failed == ["opencode"]' "$MANIFEST" >/dev/null
  refute_file "$PROJECT/.opencode/plugins/memory-bank.js"
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

# NFR-001: equivalent ways to skip extensions produce identical installations.
# Compare the current installer against itself, independent of unrelated HEAD changes.
_nfr001_assert_exact_tree_delta() {
  local old_dir="$1" new_dir="$2" old_list new_list rel of nf
  old_list="$(cd "$old_dir" && find . \( -type f -o -type l \) | sort)"
  new_list="$(cd "$new_dir" && find . \( -type f -o -type l \) | sort)"
  if [ "$old_list" != "$new_list" ]; then
    diff <(printf '%s\n' "$old_list") <(printf '%s\n' "$new_list") >&2 || true
    return 1
  fi
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    of="$old_dir/$rel"
    nf="$new_dir/$rel"
    if [ -L "$of" ] || [ -L "$nf" ]; then
      [ -L "$of" ] && [ -L "$nf" ] && [ "$(readlink "$of")" = "$(readlink "$nf")" ] || return 1
    elif ! cmp -s "$of" "$nf"; then
      case "$(basename "$rel")" in
        *manifest*.json)
          diff <(jq -S 'del(.installed_at)' "$of") <(jq -S 'del(.installed_at)' "$nf") || return 1
          ;;
        *)
          echo "unexpected filesystem delta: $rel" >&2
          diff "$of" "$nf" >&2 || true
          return 1
          ;;
      esac
    fi
  done <<< "$old_list"
}

_nfr001_compare_declined_installs() {
  local clients="$1" old_home_snap old_project_snap old_stdout new_stdout
  shift
  old_home_snap="$(mktemp -d)"
  old_project_snap="$(mktemp -d)"
  EXTRA_TMP_DIRS=("$old_home_snap" "$old_project_snap")

  # No flag and no TTY is the baseline silent skip.
  old_stdout="$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" \
    --clients "$clients" --project-root "$PROJECT" --language en </dev/null 2>&1)" \
    || { printf '%s\n' "$old_stdout" >&2; return 1; }
  jq -e '.extensions_installed == []' "$MANIFEST" >/dev/null
  rsync -a "$FAKE_HOME/" "$old_home_snap/"
  rsync -a "$PROJECT/" "$old_project_snap/"

  # Keep absolute paths identical so no output or instruction normalization is needed.
  rm -rf "$FAKE_HOME" "$PROJECT"
  mkdir -p "$FAKE_HOME" "$PROJECT"
  new_stdout="$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 bash "$INSTALL" \
    --clients "$clients" --project-root "$PROJECT" --language en "$@" </dev/null 2>&1)" \
    || { printf '%s\n' "$new_stdout" >&2; return 1; }
  jq -e '.extensions_installed == []' "$MANIFEST" >/dev/null
  if [ "$old_stdout" != "$new_stdout" ]; then
    diff <(printf '%s\n' "$old_stdout") <(printf '%s\n' "$new_stdout") >&2 || true
    return 1
  fi
  _nfr001_assert_exact_tree_delta "$old_home_snap" "$FAKE_HOME"
  _nfr001_assert_exact_tree_delta "$old_project_snap" "$PROJECT"
}

@test "extensions-offer: explicit non-interactive skip matches implicit declined install (NFR-001)" {
  _nfr001_compare_declined_installs pi,opencode --non-interactive
  [ ! -f "$FAKE_HOME/.pi/agent/extensions/memory-bank-session.ts" ]
  [ ! -f "$FAKE_HOME/.config/opencode/agent/mb-developer.md" ]
  grep -qF 'export default createMemoryBankPlugin({ extended: false });' "$PROJECT/.opencode/plugins/memory-bank.js"
}

@test "extensions-offer: codex-only declined install ignores unrelated extension opt-in (NFR-001)" {
  _nfr001_compare_declined_installs codex --non-interactive --with-extensions=pi,opencode
  [ ! -f "$FAKE_HOME/.pi/agent/extensions/memory-bank-session.ts" ]
  [ ! -f "$FAKE_HOME/.config/opencode/agent/mb-developer.md" ]
  run grep -q 'Host parity extensions' "$PROJECT/AGENTS.md"
  [ "$status" -eq 1 ]
}
