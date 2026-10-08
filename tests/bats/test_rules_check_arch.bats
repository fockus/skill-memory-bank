#!/usr/bin/env bats
# Mechanical architecture checks beyond fsd (I-252): each preset whose rule is an
# import-direction constraint carries a `check` block in its json and is scanned
# only when the rules profile selects that architecture.

# shellcheck disable=SC2317

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CHECK="$REPO_ROOT/scripts/mb-rules-check.sh"
  PRESETS="$REPO_ROOT/references/rules-presets/architecture"
  command -v jq >/dev/null || skip "jq required"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/home"
  export HOME="$TMPROOT/home"
  cd "$TMPROOT" || return 1
}

teardown() {
  if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then rm -rf "$TMPROOT"; fi
}

# put <path> <content> — create a fixture file with its directories.
put() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

# check_with <architecture-json> <files-csv> — run the checker under that profile.
check_with() {
  printf '{"schema_version":1,"scope":"project","architecture":%s,"strictness":"warn"}\n' "$1" \
    > "$TMPROOT/profile.json"
  run bash "$CHECK" --files "$2" --profile "$TMPROOT/profile.json" --out json
  [ "$status" -eq 0 ]
}

count_rule() {
  echo "$output" | jq "[.violations[] | select(.rule_id == \"$1\")] | length"
}

# ─── clean: full layer direction (domain ← application ← infrastructure) ─────

@test "arch clean: domain importing application or the interfaces layer is CRITICAL" {
  put src/domain/order.py 'from src.application.services import OrderService'
  put src/domain/user.ts 'import { Page } from "../ui/page";'
  check_with '"clean"' "src/domain/order.py,src/domain/user.ts"
  [ "$(count_rule architecture.clean.layer-direction)" -eq 2 ]
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "architecture.clean.layer-direction")] | all(.severity == "CRITICAL")'
  assert_substring "$output" "code under domain/ must not import application/"
}

@test "arch clean: application importing infrastructure is CRITICAL" {
  put src/application/place_order.py 'from src.infrastructure.db import OrderRepo'
  put src/usecases/pay.go 'package usecases

import (
	"github.com/acme/shop/infra/stripe"
)'
  check_with '"clean"' "src/application/place_order.py,src/usecases/pay.go"
  [ "$(count_rule architecture.clean.layer-direction)" -eq 2 ]
  echo "$output" | jq -e '.violations[] | select(.file == "src/usecases/pay.go") | .line == 4'
}

@test "arch clean: inward imports, look-alike names and a foreign layout are clean" {
  put src/domain/order.py 'from src.domain.money import Money
from app.api_client import Client
import fastapi'
  put src/application/place_order.py 'from src.domain.order import Order'
  put src/infrastructure/db.py 'from src.application.ports import OrderRepo'
  put src/interfaces/http.py 'from src.application.place_order import PlaceOrder'
  put src/api/domain/dto.py 'from src.api.application.x import Y'
  check_with '"clean"' "src/domain/order.py,src/application/place_order.py,src/infrastructure/db.py,src/interfaces/http.py,src/api/domain/dto.py"
  [ "$(count_rule architecture.clean.layer-direction)" -eq 0 ]
}

@test "arch clean: domain -> infrastructure stays a single clean_arch/direction finding" {
  put src/domain/order.py 'from src.infrastructure.db import Repo'
  check_with '"clean"' "src/domain/order.py"
  [ "$(count_rule clean_arch/direction)" -eq 1 ]
  [ "$(count_rule architecture.clean.layer-direction)" -eq 0 ]
}

@test "arch clean: not run when the architecture is not selected" {
  put src/domain/order.py 'from src.application.services import OrderService'
  put src/application/place_order.py 'from src.infrastructure.db import OrderRepo'
  check_with '["hexagonal"]' "src/domain/order.py,src/application/place_order.py"
  refute_substring "$output" "architecture.clean"
}

@test "arch clean: zero external deps in domain is marked as unchecked guidance" {
  jq -e '.unchecked_guidance | any(test("0 external deps"))' "$PRESETS/clean.json"
}

# ─── modular-monolith: no import of another module's internals ───────────────

mm_layout() {
  put src/modules/orders/index.ts 'export * from "./internal/db";'
  put src/modules/orders/internal/db.ts 'export const db = 1;'
  put src/modules/shared/clock.ts 'export const now = 1;'
}

@test "arch modular-monolith: import of another module's internals is CRITICAL" {
  mm_layout
  put src/modules/billing/pay.ts 'import { db } from "../orders/internal/db";'
  put app/modules/billing/charge.py 'from app.modules.orders.internal.repo import Repo'
  mkdir -p app/modules/orders/internal
  check_with '["modular-monolith"]' "src/modules/billing/pay.ts,app/modules/billing/charge.py"
  [ "$(count_rule architecture.modular-monolith.no-cross-module-internals)" -eq 2 ]
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "architecture.modular-monolith.no-cross-module-internals")]
    | all(.severity == "CRITICAL")'
  echo "$output" | jq -e '.violations[] | select(.file == "src/modules/billing/pay.ts") | .line == 1'
}

@test "arch modular-monolith: public entry, shared module and own internals are clean" {
  mm_layout
  put src/modules/billing/pay.ts 'import { db } from "../orders";
import { x } from "../orders/index";
import { now } from "../shared/clock";
import { own } from "./internal/own";
import { y } from "../../lib/orders/internal/z";'
  check_with '["modular-monolith"]' "src/modules/billing/pay.ts"
  [ "$(count_rule architecture.modular-monolith.no-cross-module-internals)" -eq 0 ]
}

@test "arch modular-monolith: not run when the architecture is not selected" {
  mm_layout
  put src/modules/billing/pay.ts 'import { db } from "../orders/internal/db";'
  check_with '"clean"' "src/modules/billing/pay.ts"
  refute_substring "$output" "modular-monolith"
}

# ─── hexagonal: the core does not import adapters ────────────────────────────

@test "arch hexagonal: core importing an adapter is CRITICAL" {
  put src/core/orders.py 'from src.adapters.postgres import OrderRepo'
  put src/core/pay.ts 'import { Stripe } from "../infra/stripe";'
  check_with '["hexagonal"]' "src/core/orders.py,src/core/pay.ts"
  [ "$(count_rule architecture.hexagonal.ports-in-domain)" -eq 2 ]
  echo "$output" | jq -e '[.violations[] | select(.rule_id == "architecture.hexagonal.ports-in-domain")] | all(.severity == "CRITICAL")'
}

@test "arch hexagonal: core importing ports and adapters importing core are clean" {
  put src/core/orders.py 'from src.core.ports import OrderRepo'
  put src/adapters/postgres.py 'from src.core.ports import OrderRepo'
  check_with '["hexagonal"]' "src/core/orders.py,src/adapters/postgres.py"
  [ "$(count_rule architecture.hexagonal.ports-in-domain)" -eq 0 ]
}

@test "arch hexagonal: domain -> infrastructure stays a single clean_arch/direction finding" {
  put src/domain/orders.py 'from src.infrastructure.db import Repo'
  check_with '["hexagonal"]' "src/domain/orders.py"
  [ "$(count_rule clean_arch/direction)" -eq 1 ]
  [ "$(count_rule architecture.hexagonal.ports-in-domain)" -eq 0 ]
}

@test "arch hexagonal: not run when the architecture is not selected" {
  put src/core/orders.py 'from src.adapters.postgres import OrderRepo'
  check_with '"clean"' "src/core/orders.py"
  refute_substring "$output" "hexagonal"
}

# ─── microservices: no code imports across service directories ──────────────

ms_layout() {
  mkdir -p services/orders/store services/orders/contracts services/shared/log
}

@test "arch microservices: importing another service's code is CRITICAL" {
  ms_layout
  put services/billing/main.go 'package main

import (
	"github.com/acme/shop/services/orders/store"
)'
  check_with '["microservices"]' "services/billing/main.go"
  [ "$(count_rule architecture.microservices.service-ownership)" -eq 1 ]
  echo "$output" | jq -e '.violations[] | select(.rule_id == "architecture.microservices.service-ownership")
    | .severity == "CRITICAL" and .line == 4'
}

@test "arch microservices: contracts, shared libs and own code are clean" {
  ms_layout
  put services/billing/main.go 'package main

import (
	pb "github.com/acme/shop/services/orders/contracts"
	"github.com/acme/shop/services/shared/log"
	"github.com/acme/shop/services/billing/store"
)'
  check_with '["microservices"]' "services/billing/main.go"
  [ "$(count_rule architecture.microservices.service-ownership)" -eq 0 ]
}

@test "arch microservices: not run when the architecture is not selected" {
  ms_layout
  put services/billing/main.go 'import "github.com/acme/shop/services/orders/store"'
  check_with '"clean"' "services/billing/main.go"
  refute_substring "$output" "microservices"
}

# ─── ddd: a bounded context does not import another context's domain ────────

@test "arch ddd: importing another context's domain model is a WARNING" {
  mkdir -p src/domain/orders
  put src/domain/billing/invoice.py 'from src.domain.orders.order import Order'
  check_with '["ddd"]' "src/domain/billing/invoice.py"
  [ "$(count_rule architecture.ddd.bounded-contexts)" -eq 1 ]
  echo "$output" | jq -e '.violations[] | select(.rule_id == "architecture.ddd.bounded-contexts") | .severity == "WARNING"'
}

@test "arch ddd: shared kernel, own context and a flat domain are clean" {
  mkdir -p src/domain/shared
  put src/domain/billing/invoice.py 'from src.domain.shared.money import Money
from src.domain.billing.line import Line'
  put src/domain/user.py 'x = 1'
  put src/domain/order.py 'from src.domain.user import User'
  check_with '["ddd"]' "src/domain/billing/invoice.py,src/domain/order.py"
  [ "$(count_rule architecture.ddd.bounded-contexts)" -eq 0 ]
}

@test "arch ddd: not run when the architecture is not selected" {
  mkdir -p src/domain/orders
  put src/domain/billing/invoice.py 'from src.domain.orders.order import Order'
  check_with '"clean"' "src/domain/billing/invoice.py"
  refute_substring "$output" "ddd"
}

# ─── mobile-udf: use cases do not import the UI layer ────────────────────────

@test "arch mobile-udf: a use case importing the UI layer is CRITICAL" {
  put app/src/main/java/com/acme/usecase/LoadOrders.kt 'package com.acme.usecase

import com.acme.ui.OrdersScreen'
  check_with '["mobile-udf"]' "app/src/main/java/com/acme/usecase/LoadOrders.kt"
  [ "$(count_rule architecture.mobile-udf.layer-contracts)" -eq 1 ]
  echo "$output" | jq -e '.violations[] | select(.rule_id == "architecture.mobile-udf.layer-contracts") | .severity == "CRITICAL" and .line == 3'
}

@test "arch mobile-udf: a use case importing the repository is clean" {
  put app/src/main/java/com/acme/usecase/LoadOrders.kt 'package com.acme.usecase

import com.acme.repository.OrdersRepository'
  check_with '["mobile-udf"]' "app/src/main/java/com/acme/usecase/LoadOrders.kt"
  [ "$(count_rule architecture.mobile-udf.layer-contracts)" -eq 0 ]
}

@test "arch mobile-udf: not run when the architecture is not selected" {
  put app/src/main/java/com/acme/usecase/LoadOrders.kt 'import com.acme.ui.OrdersScreen'
  check_with '"clean"' "app/src/main/java/com/acme/usecase/LoadOrders.kt"
  refute_substring "$output" "mobile-udf"
}

# ─── guidance-only presets and the preset convention ─────────────────────────

@test "arch: every preset declares mechanical; a check block only on mechanical ones" {
  local f
  for f in "$PRESETS"/*.json; do
    jq -e '(.mechanical | type == "boolean") and ((has("check") | not) or .mechanical)' "$f" >/dev/null \
      || { echo "bad preset: $f"; return 1; }
  done
  jq -e '.mechanical == false' "$PRESETS/event-driven.json"
}

@test "arch: a guidance-only architecture emits nothing and runs no extra check" {
  put src/modules/billing/pay.ts 'import { db } from "../orders/internal/db";'
  mkdir -p src/modules/orders/internal
  check_with '"clean"' "src/modules/billing/pay.ts"
  local base_checks
  base_checks="$(echo "$output" | jq '.stats.checks_run')"
  check_with '["event-driven"]' "src/modules/billing/pay.ts"
  refute_substring "$output" "event-driven."
  [ "$(echo "$output" | jq '.stats.checks_run')" -eq "$base_checks" ]
  [ "$(echo "$output" | jq '.violations | length')" -eq 0 ]
}

# ─── no profile → output byte-identical to the pre-I-252 checker ─────────────

@test "arch: without a profile the output is byte-identical to before" {
  put src/modules/billing/pay.ts 'import { db } from "../orders/internal/db";'
  mkdir -p src/modules/orders/internal src/adapters src/domain/orders services/b
  put src/core/svc.py 'from src.adapters.db import Repo'
  put services/a/main.go 'import "github.com/x/repo/services/b/store"'
  put src/domain/billing/invoice.py 'from src.domain.orders.order import Order'
  put src/usecase/Load.kt 'import com.x.ui.Screen'
  local files=src/modules/billing/pay.ts,src/core/svc.py,services/a/main.go,src/domain/billing/invoice.py,src/usecase/Load.kt
  { bash "$CHECK" --files "$files" --out json; bash "$CHECK" --files "$files" --out human; } \
    | sed -E 's/"duration_ms":[0-9]+/"duration_ms":0/; s/[0-9]+ms\)/0ms)/' > actual.txt
  cmp actual.txt "$REPO_ROOT/tests/fixtures/rules-check-arch/no-profile.golden"
}
