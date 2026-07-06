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

# adapter_contract_require_artifacts <manifest_path>
#
# C5 (CDX-8): adapter_contract_require_functions only proves the adapter
# DECLARES install_*/uninstall_* functions — a "broken parity" adapter
# (functions present, install() writes nothing) still passes that check,
# giving false-green suites. This verifies the artifact side of the
# contract: after install runs, (a) the manifest itself must exist and be
# valid JSON, and (b) every path the manifest's `files[]` CLAIMS to have
# installed (commands/prompts, rules, hooks, agents — whatever the adapter
# actually writes) must exist on disk.
#
# Platform-limited hosts (e.g. Codex without statusline) are not special-
# cased here: an adapter that never claims an artifact in `files[]` for a
# feature it doesn't support has nothing to fail — the honest-degradation
# contract is "don't claim what you didn't install", not "the checker must
# know every host's limitations". A manifest MAY additionally record a
# `platform_limited` array (documented, not silently omitted) for
# human/doc traceability; this function does not require it but never
# fails because of its presence.
adapter_contract_require_artifacts() {
  local manifest_path="$1"

  if [ -z "$manifest_path" ] || [ ! -f "$manifest_path" ]; then
    echo "adapter contract: manifest not found: $manifest_path" >&2
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "adapter contract: jq required to verify artifacts" >&2
    return 1
  fi

  if ! jq empty "$manifest_path" >/dev/null 2>&1; then
    echo "adapter contract: manifest is not valid JSON: $manifest_path" >&2
    return 1
  fi

  local missing=0
  local artifact
  while IFS= read -r artifact; do
    [ -z "$artifact" ] && continue
    if [ ! -e "$artifact" ]; then
      echo "adapter contract: manifest declares an artifact that does not exist on disk: $artifact" >&2
      missing=1
    fi
  done < <(jq -r '.files[]? // empty' "$manifest_path")

  [ "$missing" -eq 0 ]
}
