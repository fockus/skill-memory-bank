#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PLAN="$REPO_ROOT/scripts/mb-work-plan.sh"
  FIXTURE_MB="$REPO_ROOT/tests/bats/fixtures/wrapper-bank/.memory-bank"
}

@test "work-plan wrapper: tasks with trailing comment limits range" {
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-comment.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 1'
  echo "$output" | grep -q '"item_no": 2'
  ! echo "$output" | grep -q '"item_no": 3'
}

@test "work-plan wrapper: double-quoted linked_spec resolves" {
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-quoted-double.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 1'
}

@test "work-plan wrapper: single-quoted linked_spec resolves" {
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-quoted-single.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 1'
}

@test "work-plan wrapper: no tasks key runs all spec tasks" {
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-all.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 5'
}

# ─── linked_spec containment (r3 review [2], production path) ──────────────
#
# `os.path.join(mb_root, linked_spec, "tasks.md")` DISCARDS mb_root entirely
# when linked_spec is absolute, so a wrapper plan could bind the eval gate to a
# tasks.md the bank does not own — the same class the init locator fix closed,
# reachable through the documented production path instead of a CLI flag.

_wrapper_with_linked_spec() {   # <bank> <linked_spec value>
  mkdir -p "$1/plans"
  printf -- '---\nlinked_spec: %s\n---\n\n# Wrapper\n' "$2" > "$1/plans/w.md"
}

@test "work-plan wrapper: an ABSOLUTE linked_spec is refused" {
  local tmp; tmp="$(mktemp -d)"
  local bank="$tmp/.memory-bank"; mkdir -p "$bank/specs/demo"
  local out="$tmp/outside/specs/evil"; mkdir -p "$out"
  printf '# Tasks\n\n<!-- mb-task:1 -->\n## T\n**Eval:** none\n<!-- /mb-task:1 -->\n' > "$out/tasks.md"
  _wrapper_with_linked_spec "$bank" "$out"
  run bash "$PLAN" --target "$bank/plans/w.md" --mb "$bank" --dry-run
  [ "$status" -ne 0 ] || { echo "absolute linked_spec accepted: $output"; false; }
  rm -rf "$tmp"
}

@test "work-plan wrapper: a TRAVERSING linked_spec is refused" {
  local tmp; tmp="$(mktemp -d)"
  local bank="$tmp/.memory-bank"; mkdir -p "$bank/specs/demo"
  local out="$tmp/outside"; mkdir -p "$out"
  printf '# Tasks\n\n<!-- mb-task:1 -->\n## T\n**Eval:** none\n<!-- /mb-task:1 -->\n' > "$out/tasks.md"
  _wrapper_with_linked_spec "$bank" "../outside"
  run bash "$PLAN" --target "$bank/plans/w.md" --mb "$bank" --dry-run
  [ "$status" -ne 0 ] || { echo "traversing linked_spec accepted: $output"; false; }
  rm -rf "$tmp"
}

@test "work-plan wrapper: a SYMLINKED spec dir escaping the bank is refused" {
  local tmp; tmp="$(mktemp -d)"
  local bank="$tmp/.memory-bank"; mkdir -p "$bank/specs"
  local out="$tmp/outside"; mkdir -p "$out"
  printf '# Tasks\n\n<!-- mb-task:1 -->\n## T\n**Eval:** none\n<!-- /mb-task:1 -->\n' > "$out/tasks.md"
  ln -s "$out" "$bank/specs/evil"
  _wrapper_with_linked_spec "$bank" "specs/evil"
  run bash "$PLAN" --target "$bank/plans/w.md" --mb "$bank" --dry-run
  [ "$status" -ne 0 ] || { echo "symlink-escaping linked_spec accepted: $output"; false; }
  rm -rf "$tmp"
}

@test "work-plan wrapper: an ordinary contained linked_spec still resolves" {
  # The containment must not break the documented happy path.
  run bash "$PLAN" --target "$FIXTURE_MB/plans/wrapper-all.md" --mb "$FIXTURE_MB" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"item_no": 5'
}
