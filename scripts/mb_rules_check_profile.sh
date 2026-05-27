# shellcheck shell=bash
# Shared profile loading and output helpers for mb-rules-check.sh.

load_profile() {
  local py_args=()
  if [[ -n "$PROFILE_PATH" && -f "$PROFILE_PATH" ]]; then
    py_args=("--project=$PROFILE_PATH")
  fi

  PROFILE_JSON="$(PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m memory_bank_skill.rules_profile resolve \
    "${py_args[@]+"${py_args[@]}"}" 2>/dev/null)" || true

  if [[ -z "$PROFILE_JSON" ]]; then
    PROFILE_JSON='{"role":"backend","stack":"generic","architecture":"clean","delivery":"tdd","strictness":"warn","sources":{"role":"baseline","stack":"baseline","architecture":"baseline","delivery":"baseline","strictness":"baseline"},"immutable_rules":["no-placeholders","protected-files","destructive-confirm","fail-fast","dry-kiss-yagni","verification-before-completion","explicit-storage-choice"],"prompt_summary":"# Active Rule Profile\nrole=backend  stack=generic  architecture=clean\ndelivery=tdd  strictness=warn\n\n## Sources\n  All: baseline\n\n## Immutable Baseline (non-overridable)\n  All safety rules active\n\n## Guidance\nFollow clean architecture with tdd delivery.\nStrictness: warn."}'
  fi
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
