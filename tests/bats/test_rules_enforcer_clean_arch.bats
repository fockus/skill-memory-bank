#!/usr/bin/env bats
# Tests for Clean Architecture direction check in scripts/mb-rules-check.sh.
#
# Rule: any file under a `domain/` path segment that imports from an
# `infrastructure/` path segment violates dependency direction.
#
# Heuristic (language-agnostic, regex on source text):
#   - Python:  `^\s*(from|import)\s+.*infrastructure`
#   - JS/TS:   `(import|require).*['"].*infrastructure`
#   - Go:      `"[^"]*/infrastructure[^"]*"`
# Hit → severity=CRITICAL, rule=clean_arch/direction.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CHECK="$REPO_ROOT/scripts/mb-rules-check.sh"
  command -v jq >/dev/null || skip "jq required"

  TMPROOT="$(mktemp -d)"
  cd "$TMPROOT"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "clean_arch: domain python file importing from infrastructure → CRITICAL" {
  mkdir -p src/domain src/infrastructure
  cat > src/domain/user.py <<'PY'
from src.infrastructure.db import Session

class User:
    pass
PY
  cat > src/infrastructure/db.py <<'PY'
class Session: ...
PY
  run bash "$CHECK" --files "src/domain/user.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "clean_arch/direction")) | length) == 1'
  echo "$output" | jq -e '(.violations | map(select(.rule == "clean_arch/direction"))[0].severity) == "CRITICAL"'
  echo "$output" | jq -e '(.violations | map(select(.rule == "clean_arch/direction"))[0].file) == "src/domain/user.py"'
}

@test "clean_arch: domain file WITHOUT infra import → no violation" {
  mkdir -p src/domain
  cat > src/domain/order.py <<'PY'
from dataclasses import dataclass

@dataclass
class Order:
    id: int
PY
  run bash "$CHECK" --files "src/domain/order.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "clean_arch/direction")) | length) == 0'
}

@test "clean_arch: infra file importing from domain → no violation (allowed direction)" {
  mkdir -p src/domain src/infrastructure
  cat > src/domain/entity.py <<'PY'
class Entity: pass
PY
  cat > src/infrastructure/repo.py <<'PY'
from src.domain.entity import Entity
PY
  run bash "$CHECK" --files "src/infrastructure/repo.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "clean_arch/direction")) | length) == 0'
}

@test "clean_arch: TypeScript domain importing from infrastructure → CRITICAL" {
  mkdir -p src/domain src/infrastructure
  cat > src/domain/user.ts <<'TS'
import { Db } from '../infrastructure/db';
export class User {}
TS
  run bash "$CHECK" --files "src/domain/user.ts" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "clean_arch/direction")) | length) == 1'
}

@test "clean_arch: Go domain importing from infrastructure → CRITICAL" {
  mkdir -p internal/domain internal/infrastructure
  cat > internal/domain/user.go <<'GO'
package domain

import (
    "project/internal/infrastructure/db"
)
GO
  run bash "$CHECK" --files "internal/domain/user.go" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "clean_arch/direction")) | length) == 1'
}
