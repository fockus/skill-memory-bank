#!/usr/bin/env bats
# Tests for profile integration in scripts/mb-rules-check.sh (Stage 4).
#
# Covers:
#   4.1 - profile loading via --profile flag
#   4.2 - stack-aware deterministic checks (go/python/typescript)
#   4.3 - architecture-aware advisory hints (fsd import direction)
#   4.4 - strictness-aware exit code
#   4.5 - JSON output extension with profile block
#
# All tests are self-contained: each creates its own temp dir and fixture files.

# shellcheck disable=SC2317

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CHECK="$REPO_ROOT/scripts/mb-rules-check.sh"
  FIXTURES="$REPO_ROOT/tests/fixtures/rules-profiles"
  command -v jq >/dev/null || skip "jq required"

  TMPROOT="$(mktemp -d)"
  # The architecture list is resolved user → project (mb-profile.sh quality);
  # an empty HOME keeps the developer's own user profile out of the run.
  mkdir -p "$TMPROOT/home"
  export HOME="$TMPROOT/home"
  cd "$TMPROOT" || return 1
}

teardown() {
  if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then rm -rf "$TMPROOT"; fi
}

# ─── Case 1: baseline mode emits profile block with sources=baseline ──────────

@test "rules-check: baseline mode emits profile block with sources=baseline" {
  # No --profile given → falls back to built-in baseline
  run bash "$CHECK" --files "" --out json
  [ "$status" -eq 0 ]
  # profile block must exist in the output
  echo "$output" | jq -e '.profile | type == "object"'
  # all sources must be "baseline" when no profile file is provided
  echo "$output" | jq -e '.profile.sources | to_entries | all(.value == "baseline")'
  echo "$output" | jq -e '.profile.strictness == "warn"'
}

# ─── Case 2: go profile triggers context-propagation on a handler ─────────────

@test "rules-check: go profile triggers context-propagation rule on changed handler" {
  mkdir -p src
  # A handler that lacks ctx context.Context parameter
  cat > src/handler.go <<'EOF'
package main

import "net/http"

func Handle(w http.ResponseWriter, r *http.Request) {
    w.Write([]byte("ok"))
}
EOF

  cat > "$TMPROOT/profile-go.json" <<'EOF'
{
  "schema_version": 1,
  "scope": "project",
  "role": "backend",
  "stack": "go",
  "architecture": "microservices",
  "delivery": "contract-first",
  "strictness": "warn"
}
EOF

  run bash "$CHECK" \
    --files "src/handler.go" \
    --diff-files "src/handler.go" \
    --profile "$TMPROOT/profile-go.json" \
    --out json
  [ "$status" -eq 0 ]
  # Must have at least one context-propagation violation
  echo "$output" | jq -e '
    [.violations[] | select(.rule_id == "stack.go.context-propagation")] | length >= 1
  '
  # Source must be a profile dimension (not baseline)
  echo "$output" | jq -e '
    [.violations[] | select(.rule_id == "stack.go.context-propagation")][0].profile_source != null
  '
}

# ─── Case 3: python profile flags missing type hints ──────────────────────────

@test "rules-check: python profile flags missing type hints on changed def" {
  mkdir -p src
  # Python function without type hints
  cat > src/service.py <<'EOF'
def calculate_total(items, discount):
    return sum(item["price"] for item in items) * (1 - discount)


def greet(name):
    return f"Hello, {name}"
EOF

  cat > "$TMPROOT/profile-python.json" <<'EOF'
{
  "schema_version": 1,
  "scope": "project",
  "role": "backend",
  "stack": "python",
  "architecture": "modular-monolith",
  "delivery": "tdd",
  "strictness": "warn"
}
EOF

  run bash "$CHECK" \
    --files "src/service.py" \
    --diff-files "src/service.py" \
    --profile "$TMPROOT/profile-python.json" \
    --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    [.violations[] | select(.rule_id == "stack.python.type-hints")] | length >= 1
  '
}

# ─── Case 4: typescript profile flags any usage ───────────────────────────────

@test "rules-check: typescript profile flags any usage in changed .ts file" {
  mkdir -p src
  # TypeScript file with `any` type
  cat > src/api.ts <<'EOF'
function processData(data: any): any {
  return data;
}

const handler = (req: any, res: any) => {
  res.json(req.body);
};
EOF

  cat > "$TMPROOT/profile-ts.json" <<'EOF'
{
  "schema_version": 1,
  "scope": "project",
  "role": "frontend",
  "stack": "typescript",
  "architecture": "fsd",
  "delivery": "sdd",
  "strictness": "warn"
}
EOF

  run bash "$CHECK" \
    --files "src/api.ts" \
    --diff-files "src/api.ts" \
    --profile "$TMPROOT/profile-ts.json" \
    --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    [.violations[] | select(.rule_id == "stack.typescript.no-any")] | length >= 1
  '
}

# ─── Case 5: strictness=block exits non-zero on CRITICAL ──────────────────────

@test "rules-check: strictness=block exits non-zero on CRITICAL" {
  # solid/srp is CRITICAL when this change pushes files over the threshold (--base)
  mkdir -p src
  git init -q . && git config user.email t@t.t && git config user.name t
  git commit -q --allow-empty -m base
  base="$(git rev-parse HEAD)"
  for name in alpha beta gamma; do
    python3 -c "
for i in range(350):
    print(f'line_{i} = {i}')
" > "src/${name}.py"
  done

  cat > "$TMPROOT/profile-block.json" <<'EOF'
{
  "schema_version": 1,
  "scope": "project",
  "role": "backend",
  "stack": "python",
  "architecture": "modular-monolith",
  "delivery": "tdd",
  "strictness": "block"
}
EOF

  run bash "$CHECK" \
    --files "src/alpha.py,src/beta.py,src/gamma.py" \
    --profile "$TMPROOT/profile-block.json" \
    --base "$base" \
    --out json
  # Must exit non-zero because of CRITICAL violations
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '
    [.violations[] | select(.severity == "CRITICAL")] | length >= 1
  '
}

# ─── Case 6: strictness=advisory exits 0 even with violations ─────────────────

@test "rules-check: strictness=advisory exits 0 even with violations" {
  mkdir -p src
  # A handler without context — should fire advisory go check
  cat > src/handler.go <<'EOF'
package main

import "net/http"

func Handle(w http.ResponseWriter, r *http.Request) {
    w.Write([]byte("ok"))
}
EOF

  cat > "$TMPROOT/profile-advisory.json" <<'EOF'
{
  "schema_version": 1,
  "scope": "project",
  "role": "backend",
  "stack": "go",
  "architecture": "microservices",
  "delivery": "contract-first",
  "strictness": "advisory"
}
EOF

  run bash "$CHECK" \
    --files "src/handler.go" \
    --diff-files "src/handler.go" \
    --profile "$TMPROOT/profile-advisory.json" \
    --out json
  # strictness=advisory → always exit 0
  [ "$status" -eq 0 ]
}

# ─── Case 7: fsd architecture flags upward import in entities/ ────────────────

@test "rules-check: fsd architecture flags upward import in entities/" {
  mkdir -p "src/entities/user"
  # An entity module that imports from features (upward = bad in FSD)
  cat > "src/entities/user/model.ts" <<'EOF'
import { UserForm } from "../../features/user-form/ui";
import { SomeWidget } from "../../widgets/header";

export interface User {
  id: string;
  name: string;
}
EOF

  cat > "$TMPROOT/profile-fsd.json" <<'EOF'
{
  "schema_version": 1,
  "scope": "project",
  "role": "frontend",
  "stack": "typescript",
  "architecture": "fsd",
  "delivery": "sdd",
  "strictness": "warn"
}
EOF

  run bash "$CHECK" \
    --files "src/entities/user/model.ts" \
    --diff-files "src/entities/user/model.ts" \
    --profile "$TMPROOT/profile-fsd.json" \
    --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    [.violations[] | select(.rule_id == "architecture.fsd.import-direction")] | length >= 1
  '
}

# ─── Case 8: profile summary stays under 4 KB ─────────────────────────────────

@test "rules-check: profile summary stays under 4 KB in JSON output" {
  run bash "$CHECK" --files "" --profile "$FIXTURES/backend-go.json" --out json
  [ "$status" -eq 0 ]
  # Extract prompt_summary and check its byte length
  local summary_len
  summary_len="$(echo "$output" | jq -r '.profile.prompt_summary' | wc -c | tr -d ' ')"
  # Must be under 4096 bytes (4 KB)
  [ "$summary_len" -lt 4096 ]
}

# ─── Case 9: architecture list (AGR-076) — every selected preset applies ─────

fsd_entity_fixture() {
  mkdir -p "src/entities/user"
  printf 'import { UserForm } from "../../features/user-form/ui";\n' > "src/entities/user/model.ts"
  printf '{"schema_version":1,"scope":"project","role":"frontend","stack":"typescript","architecture":%s,"delivery":"tdd","strictness":"warn"}\n' \
    "$1" > "$TMPROOT/profile.json"
}

@test "rules-check: architecture [clean, fsd] runs the fsd check with the preset severity" {
  fsd_entity_fixture '["clean","fsd"]'
  run bash "$CHECK" --files "src/entities/user/model.ts" --profile "$TMPROOT/profile.json" --out json
  [ "$status" -eq 0 ]
  # fsd.json gives import-direction severity "block" → CRITICAL
  echo "$output" | jq -e '
    [.violations[] | select(.rule_id == "architecture.fsd.import-direction")] | length >= 1 and all(.severity == "CRITICAL")
  '
}

@test "rules-check: architecture clean alone does not run the fsd check" {
  fsd_entity_fixture '"clean"'
  run bash "$CHECK" --files "src/entities/user/model.ts" --profile "$TMPROOT/profile.json" --out json
  [ "$status" -eq 0 ]
  refute_substring "$output" "architecture.fsd.import-direction"
}

@test "rules-check: an architecture nobody set never turns the fsd check on" {
  # No --profile, empty HOME: the resolver default (whatever list it ships)
  # must not change today's baseline behaviour.
  fsd_entity_fixture '"clean"'
  run bash "$CHECK" --files "src/entities/user/model.ts" --out json
  [ "$status" -eq 0 ]
  refute_substring "$output" "architecture.fsd.import-direction"
}

# ─── Case 10: quality switches (AGR-077) — tdd / solid off skip their checks ─

# src/big.py: >300 lines (solid/srp) and no co-changed test (tdd/delta).
quality_fixture() {
  mkdir -p src
  python3 -c "
for i in range(350):
    print(f'line_{i} = {i}')
" > src/big.py
  printf '{"schema_version":1,"scope":"project","quality":%s}\n' "$1" > "$TMPROOT/profile.json"
}

run_quality_check() {
  run bash "$CHECK" --files "src/big.py" --diff-files "src/big.py" \
    --profile "$TMPROOT/profile.json" --out json
}

@test "rules-check: quality.tdd off skips tdd/delta and reports it as INFO" {
  quality_fixture '{"tdd":"off"}'
  run_quality_check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "tdd/delta" and .severity != "INFO")] | length == 0'
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "tdd/delta" and .severity == "INFO")] | length == 1'
  assert_substring "$output" "quality.tdd is off"
  # the other baseline checks still run
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "solid/srp" and .severity == "WARNING")] | length == 1'
}

@test "rules-check: quality.principles.solid off skips solid/srp and reports it as INFO" {
  quality_fixture '{"principles":{"solid":"off"}}'
  run_quality_check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "solid/srp" and .severity != "INFO")] | length == 0'
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "solid/srp" and .severity == "INFO")] | length == 1'
  assert_substring "$output" "quality.principles.solid is off"
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "tdd/delta" and .severity == "CRITICAL")] | length == 1'
}

@test "rules-check: quality.tdd small+ keeps tdd/delta CRITICAL" {
  quality_fixture '{"tdd":"small+","principles":{"solid":"on"}}'
  run_quality_check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "tdd/delta" and .severity == "CRITICAL")] | length == 1'
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "solid/srp" and .severity == "WARNING")] | length == 1'
  refute_substring "$output" "is off in the rules profile"
}

@test "rules-check: without --profile the project bank's rules-profile.json is the project layer" {
  quality_fixture '{"tdd":"off"}'
  mkdir -p .memory-bank
  printf '# Status\n' > .memory-bank/status.md
  cp "$TMPROOT/profile.json" .memory-bank/rules-profile.json
  run bash "$CHECK" --files "src/big.py" --diff-files "src/big.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "tdd/delta" and .severity == "INFO")] | length == 1'
  assert_substring "$output" "quality.tdd is off"
}
