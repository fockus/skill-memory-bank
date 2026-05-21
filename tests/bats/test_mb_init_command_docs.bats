#!/usr/bin/env bats
# Tests for commands/mb.md `init` section — Sprint 1 / Stage 4 global-storage UX.
#
# Contract: the `init` section must explain both storage modes side-by-side,
# show non-interactive examples for scripts/CLI, and clarify that the default
# remains local + project-shared while global mode keeps the repository clean.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  MB_MD="$REPO_ROOT/commands/mb.md"
  [ -f "$MB_MD" ] || skip "commands/mb.md missing"
}

@test "mb init docs: both storage modes named in the routing table or section" {
  run grep -E '(\-\-storage[ =](local|global)|storage_mode=(local|global))' "$MB_MD"
  [ "$status" -eq 0 ]
}

@test "mb init docs: non-interactive shell example for local mode" {
  run grep -E 'mb-init-bank\.sh.*--storage[= ]local' "$MB_MD"
  [ "$status" -eq 0 ]
}

@test "mb init docs: non-interactive shell example for global mode with --agent" {
  run grep -E 'mb-init-bank\.sh.*--storage[= ]global.*--agent' "$MB_MD"
  [ "$status" -eq 0 ]
}

@test "mb init docs: repository cleanliness language for global mode" {
  run grep -iE '(keep .*repo.*clean|repository.*clean|stays clean|repo stays clean|без следов|чист.*репоз)' "$MB_MD"
  [ "$status" -eq 0 ]
}

@test "mb init docs: team-shared language for local mode" {
  run grep -iE '(team[- ]shared|share.*team|committed?.*team|public bank|общ.*команд)' "$MB_MD"
  [ "$status" -eq 0 ]
}

@test "mb init docs: default behavior remains local + non-interactive safe" {
  run grep -iE '(default.*local|local.*default)' "$MB_MD"
  [ "$status" -eq 0 ]
}
