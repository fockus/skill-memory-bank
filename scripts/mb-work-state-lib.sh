# shellcheck shell=bash
# mb-work-state-lib.sh — sourced, self-contained helpers for mb-work-state.sh
# that shell out to external tooling (pipeline YAML, uuid). They live here so
# the CLI dispatcher stays small and every file is ≤400 lines. Not an
# executable entry point. Source it from mb-work-state.sh:
#   # shellcheck source=mb-work-state-lib.sh
#   source "$SCRIPT_DIR/mb-work-state-lib.sh"
#
# Public functions:
#   resolve_max_cycles <mb_arg>   echoes the loop budget (see below)
#   gen_run_id                    echoes a fresh uuid4 hex, writes nothing
#
# Reads the global SCRIPT_DIR, set by the sourcing script before this file is
# sourced.

PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

# max_cycles resolves from the pipeline's
# workflows.governed-execution.loop.max_cycles, falling back to 2 (PyYAML-
# optional, same pattern as scripts/mb-work-budget.sh). Fail-safe: any
# missing/corrupt pipeline, or a missing PyYAML, degrades to 2 — never a
# non-zero exit from this file.
resolve_max_cycles() {
  # $1 = mb_arg → echoes an integer
  local mb_arg="$1"
  local pipeline_path
  pipeline_path=$(bash "$PIPELINE" path "$mb_arg" 2>/dev/null || true)
  if [ -z "$pipeline_path" ]; then
    pipeline_path="$SCRIPT_DIR/../references/pipeline.default.yaml"
  fi
  PIPELINE_YAML="$pipeline_path" python3 - <<'PY'
import os
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    loop = (((cfg.get("workflows") or {}).get("governed-execution") or {}).get("loop") or {})
    print(int(loop.get("max_cycles", 2)))
except Exception:
    print(2)
PY
}

gen_run_id() {
  python3 -c 'import uuid; print(uuid.uuid4().hex)'
}
