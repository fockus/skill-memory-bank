#!/usr/bin/env bats
# Security: path traversal must not escape the active Memory Bank.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME:-$(dirname "$BATS_TEST_FILENAME")}/../.." && pwd)"
  SCRIPTS="$REPO_ROOT/scripts"
  SANDBOX="$(mktemp -d)"
  BANK="$SANDBOX/bank"
  mkdir -p "$BANK/plans" "$BANK/pipelines" "$BANK/notes"
  printf '# Test\n' > "$BANK/plans/foo.md"
  cat > "$BANK/roadmap.md" <<EOF
# Roadmap
<!-- mb-active-plans -->
- [test](plans/foo.md)
<!-- /mb-active-plans -->
EOF
  cp "$REPO_ROOT/references/pipeline.default.yaml" "$BANK/pipeline.yaml"
  printf 'name: governed\n' > "$BANK/pipelines/governed.yaml"
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

@test "work_resolve: rejects dotdot active plan link" {
  cat > "$BANK/roadmap.md" <<'EOF'
# Roadmap
<!-- mb-active-plans -->
- [evil](../../../../etc/passwd)
<!-- /mb-active-plans -->
EOF
  run bash "$SCRIPTS/mb-work-resolve.sh" --mb "$BANK"
  [ "$status" -ne 0 ]
  [[ "$output" != /etc/passwd ]]
  [[ "$output" != /private/etc/passwd ]]
}

@test "work_resolve: accepts canonical plan under bank" {
  run bash "$SCRIPTS/mb-work-resolve.sh" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/plans/foo.md" ]]
}

@test "pipeline: rejects dotdot MB_PIPELINE name" {
  evil="$SANDBOX/evil.yaml"
  printf 'name: evil\n' > "$evil"
  run env MB_PIPELINE='../../evil' bash "$SCRIPTS/mb-pipeline.sh" path "$BANK"
  [ "$status" -ne 0 ]
  [[ ! "$output" == *"$evil"* ]]
}

@test "pipeline: rejects dotdot name from mb-config" {
  evil="$SANDBOX/evil2.yaml"
  printf 'name: evil2\n' > "$evil"
  printf 'pipeline=../../evil2\n' > "$BANK/.mb-config"
  run bash "$SCRIPTS/mb-pipeline.sh" path "$BANK"
  [ "$status" -ne 0 ]
  [[ ! "$output" == *"$evil"* ]]
}

@test "pipeline: accepts valid pipeline name" {
  run env MB_PIPELINE=governed bash "$SCRIPTS/mb-pipeline.sh" path "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/pipelines/governed.yaml" ]]
}

@test "context: skips symlinked status outside bank" {
  secret="$SANDBOX/secret-status.txt"
  printf 'TOP-SECRET-SSH-CONFIG\n' > "$secret"
  ln -sf "$secret" "$BANK/status.md"
  printf '# ok\n' > "$BANK/roadmap.md"
  printf '# ok\n' > "$BANK/checklist.md"
  printf '# ok\n' > "$BANK/research.md"
  run bash "$SCRIPTS/mb-context.sh" "$BANK"
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"TOP-SECRET-SSH-CONFIG"* ]]
  [[ "$output$stderr" == *"skip"* || "$output$stderr" == *"symlink"* ]]
}

@test "search: rejects dotdot index path" {
  hostname="$(cat /etc/hostname 2>/dev/null || echo localhost)"
  mkdir -p "$BANK/.index"
  python3 - "$BANK/index.json" <<'PYIN'
import json, sys
data = {"notes": [{"path": "../../../../etc/hostname", "tags": ["xtra"]}]}
with open(sys.argv[1], "w") as fh:
    json.dump(data, fh)
PYIN
  run bash "$SCRIPTS/mb-search.sh" --tag xtra "$BANK"
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"$hostname"* ]]
}
