#!/usr/bin/env bash
# adapters/_contract.sh — minimal adapter contract checks.

adapter_contract_require_functions() {
  local fn
  for fn in "$@"; do
    if ! declare -F "$fn" >/dev/null 2>&1; then
      echo "missing required adapter function: $fn" >&2
      return 1
    fi
  done
  return 0
}
