# shellcheck shell=bash
# Shared profile loading and output helpers for mb-rules-check.sh.

load_profile() {
  local py_args=()
  if [[ -n "$PROFILE_PATH" && -f "$PROFILE_PATH" ]]; then
    py_args=("--project=$PROFILE_PATH")
  fi

  PROFILE_JSON="$(PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}" \
    "$(mb_resolve_python "$REPO_ROOT")" -m memory_bank_skill.rules_profile resolve \
    "${py_args[@]+"${py_args[@]}"}" 2>/dev/null)" || true

  if [[ -z "$PROFILE_JSON" ]]; then
    PROFILE_JSON='{"role":"backend","stack":"generic","architecture":"clean","delivery":"tdd","strictness":"warn","sources":{"role":"baseline","stack":"baseline","architecture":"baseline","delivery":"baseline","strictness":"baseline"},"immutable_rules":["no-placeholders","protected-files","destructive-confirm","fail-fast","verification-before-completion","explicit-storage-choice"],"prompt_summary":"# Active Rule Profile\nrole=backend  stack=generic  architecture=clean\ndelivery=tdd  strictness=warn\n\n## Sources\n  All: baseline\n\n## Immutable Baseline (non-overridable)\n  All safety rules active\n\n## Guidance\nFollow clean architecture with tdd delivery.\nStrictness: warn."}'
  fi
}

# Effective quality settings from the one resolver (user → project, AGR-076/077):
#   ARCH_NAMES    selected architectures, space-separated. An architecture nobody
#                 chose (source `default`) falls back to the rules-profile label, so
#                 the default list never switches extra architecture checks on.
#   QUALITY_TDD   on|off|small+ (small+ counts as on for the checks)
#   QUALITY_SOLID on|off
# An unreadable/invalid profile leaves both switches on (today's behaviour).
load_quality() {
  local out arch="" tdd="" solid=""
  out="$(bash "$SCRIPT_DIR/mb-profile.sh" quality --json --project="${PROFILE_PATH:-/dev/null}" 2>/dev/null | \
    python3 -c 'import sys,json; d=json.load(sys.stdin); q=d["quality"]
print(" ".join(d["architecture"]["names"]) if d["sources"]["architecture"] != "default" else "")
print(q["tdd"]); print(q["principles"]["solid"])' 2>/dev/null)" || true
  { IFS= read -r arch; IFS= read -r tdd; IFS= read -r solid; } <<< "$out" || true
  ARCH_NAMES="$arch"
  # shellcheck disable=SC2034  # both read by mb_rules_check_baseline.sh
  QUALITY_TDD="${tdd:-on}" QUALITY_SOLID="${solid:-on}"
  [[ -n "$ARCH_NAMES" ]] || ARCH_NAMES="$(profile_field architecture | tr '+' ' ')"
}

# Severity the architecture preset gives <rule_id> (block→CRITICAL, warn→WARNING,
# advisory→INFO); <fallback> when the preset or the rule is absent.
preset_severity() {
  local rule_id="$1" fallback="$2" name="${1#architecture.}"
  name="${name%%.*}"
  python3 - "$REPO_ROOT/references/rules-presets/architecture/$name.json" "$rule_id" "$fallback" 2>/dev/null <<'PY' \
    || printf '%s\n' "$fallback"
import json, sys
path, rule_id, fallback = sys.argv[1:]
levels = {"block": "CRITICAL", "warn": "WARNING", "advisory": "INFO"}
with open(path, encoding="utf-8") as fh:
    rules = json.load(fh).get("rules", [])
print(next((levels[r["severity"]] for r in rules if r.get("rule_id") == rule_id), fallback))
PY
}

profile_field() {
  local field="$1"
  printf '%s' "$PROFILE_JSON" | \
    python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('${field}',''))" \
    2>/dev/null || true
}

profile_source_for() {
  local dim="$1"
  printf '%s' "$PROFILE_JSON" | \
    python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('sources',{}).get('${dim}','baseline'))" \
    2>/dev/null || printf 'baseline'
}

emit_json() {
  local profile_json
  profile_json="$(python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
out = {
  'role': d.get('role','backend'),
  'stack': d.get('stack','generic'),
  'architecture': d.get('architecture','clean'),
  'delivery': d.get('delivery','tdd'),
  'strictness': d.get('strictness','warn'),
  'sources': d.get('sources',{}),
  'prompt_summary': d.get('prompt_summary',''),
}
print(json.dumps(out))
" <<< "$PROFILE_JSON" 2>/dev/null)" || \
    profile_json='{"role":"backend","stack":"generic","architecture":"clean","delivery":"tdd","strictness":"warn","sources":{},"prompt_summary":""}'

  printf '{"violations":['
  local i
  for i in "${!VIOLATIONS[@]}"; do
    (( i > 0 )) && printf ','
    printf '%s' "${VIOLATIONS[$i]}"
  done
  printf '],"profile":%s,"stats":{"files_scanned":%d,"checks_run":%d,"duration_ms":%d}}\n' \
    "$profile_json" "${#FILES[@]}" "$CHECKS_RUN" "$DURATION"
}

emit_human() {
  if (( ${#VIOLATIONS[@]} == 0 )); then
    printf 'rules-check: 0 violations (%d files, %d checks, %dms)\n' \
      "${#FILES[@]}" "$CHECKS_RUN" "$DURATION"
    return
  fi
  printf 'rules-check: %d violation(s)\n' "${#VIOLATIONS[@]}"
  local v rule sev file line rationale
  for v in "${VIOLATIONS[@]+"${VIOLATIONS[@]}"}"; do
    rule="$(printf '%s' "$v" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["rule"])')"
    sev="$(printf '%s' "$v" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["severity"])')"
    file="$(printf '%s' "$v" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["file"])')"
    line="$(printf '%s' "$v" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["line"])')"
    rationale="$(printf '%s' "$v" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["rationale"])')"
    printf '  [%s] %s — %s:%s — %s\n' "$sev" "$rule" "$file" "$line" "$rationale"
  done
}
