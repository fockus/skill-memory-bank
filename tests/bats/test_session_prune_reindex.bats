#!/usr/bin/env bats
# Stage 4 — mb-session-prune.sh: after --apply removes contentless stubs, fire a
# best-effort, backgrounded `mb-semantic.py prune` to drop index blocks whose source
# disappeared. Never blocks, never fails the prune (fail-open, exit 0 always).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-session-prune.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/session"
  _stub() {  # contentless
    cat > "$MB/session/$1" <<EOF
---
session_id: $1
summarized: false
---

## Live log
- 10:00 — User: "" · tools: (none) · files: (none) · ok
EOF
  }
  _stub "2026-06-10_1000_aaaaaaaa.md"
}
teardown() { rm -rf "$TMP"; }

@test "--apply with a stub invokes the semantic prune trigger" {
  run bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reindex=1"* ]]
}

@test "dry-run never triggers the semantic prune" {
  run bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reindex=0"* ]]
  [ -f "$MB/session/2026-06-10_1000_aaaaaaaa.md" ]
}

@test "--apply still exits 0 and skips the trigger when python3 is unavailable" {
  # Simple dir-stripping (like the jq technique in test_mb_pre_compact.bats) is
  # unreliable here: on this host python3 lives alongside dirname/basename/mkdir
  # in /usr/bin, so removing that whole dir from PATH breaks the script itself,
  # not just the python lookup. Instead: build a symlink farm of every OTHER
  # executable currently reachable on PATH (first-match-wins, mirroring real PATH
  # resolution order) and explicitly skip anything named python/python3*.
  local sanebin d f b
  sanebin="$TMP/sanebin"
  mkdir -p "$sanebin"
  (IFS=':'; for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -x "$f" ] || continue
      b="$(basename "$f")"
      case "$b" in python|python3|python3.*|python2*) continue ;; esac
      [ -e "$sanebin/$b" ] && continue
      ln -s "$f" "$sanebin/$b" 2>/dev/null || true
    done
  done)
  run env PATH="$sanebin" bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reindex=0"* ]]
}
