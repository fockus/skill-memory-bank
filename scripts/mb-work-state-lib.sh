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
#   eval_declaration ...          classifies a task's Eval declaration
#   eval_declared_cmd ...         echoes the declared Eval command, if any
#   eval_state_field <state> <k>  reads one scalar from the state JSON
#   cmd_list                      `list` subcommand body (JSON array of runs)
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

# ── declaration binding (review [2]) ──────────────────────────────────────
# The Eval a task DECLARES is the only command this gate may run. Without this
# binding a caller could hand the helper an unrelated toggle-script that prints
# the anchor and exits 1, then exits 0 once an external marker flipped — both
# transitions "proven" while the declared Eval never ran.
#
# `eval_declared_cmd <bank> <source> <item_no>` echoes the declared Eval command
# for that task, or nothing when it cannot be resolved.
eval_declared_cmd() {
  eval_declaration "$1" "$2" "$3" "$4" "${5:-}" | sed -n '2p'
}

# The declared red ANCHORS (`exit:` / `output~:`) for the same task, printed as
# `<exit>\x1f<output_re>`. The gate must bind these too: checking only the
# command let a caller pass its own --output-re/--expected-exit and certify an
# unrelated foreign failure as this task's genuine red (review [10]).
eval_declared_anchors() {
  eval_declaration "$1" "$2" "$3" "$4" "${5:-}" | sed -n '3p'
}

# `eval_declaration <bank> <source_path> <source_topic> <item_no>` classifies the
# task's Eval declaration. First line is the verdict, the rest is the command:
#
#   CMD      — a real, non-waived Eval is declared (command follows)
#   WAIVED   — the task exists and declares `Eval: none` (explicit waiver)
#   NOITEM   — the declaration file resolved but has no such task → fail closed
#   NOFILE   — no declaration surface at all (plain plan stage / ad-hoc source)
#
# The distinction matters for the `done` gate (review [11]): NOITEM means the
# binding is broken and must never certify, while NOFILE means there is genuinely
# nothing to gate. Resolution prefers the explicit source_path/source_topic
# recorded by `init`; the bare category is NOT a usable locator (review [9]).
eval_declaration() {
  local bank="$1" source_path="$2" source_topic="$3" item_no="$4" legacy="${5:-}"
  MB_SD="$SCRIPT_DIR" BANK="$bank" SRC_PATH="$source_path" SRC_TOPIC="$source_topic" \
    SRC_LEGACY="$legacy" ITEM_NO="$item_no" python3 - <<'PY'
import os, pathlib, sys
sys.path.insert(0, os.environ["MB_SD"])
bank = pathlib.Path(os.environ["BANK"])
candidates = []
sp = os.environ.get("SRC_PATH", "").strip()
st = os.environ.get("SRC_TOPIC", "").strip()
if sp:
    p = pathlib.Path(sp)
    candidates.append(p if p.suffix == ".md" else p / "tasks.md")
if st:
    candidates.append(bank / "specs" / st / "tasks.md")
    candidates.append(pathlib.Path(st) / "tasks.md")
# Legacy positional `init <topic> <n>` callers (pre source_topic). Harmless as a
# fallback: a real topic resolves, while the bare CATEGORY ("spec"/"plan") does
# not exist as `<bank>/specs/spec/tasks.md` and still fails closed — which is
# the whole point of review [9].
sl = os.environ.get("SRC_LEGACY", "").strip()
if sl and sl not in ("spec", "plan"):
    p = pathlib.Path(sl)
    candidates.append(p if p.suffix == ".md" else bank / "specs" / sl / "tasks.md")
    candidates.append(p / "tasks.md")
for p in candidates:
    if not p.is_file():
        continue
    try:
        import mb_work_items as w
        items = list(w.parse_work_items(p))
    except Exception:
        continue
    for it in items:
        if it.kind == "task" and str(it.item_no) == os.environ["ITEM_NO"]:
            ev = it.eval or {}
            cmd = ev.get("cmd") or ""
            if cmd and cmd != "none":
                ex = ev.get("exit")
                ore = ev.get("output_re") or ""
                # line 1 verdict, line 2 command, line 3 anchors (review [10]).
                sys.stdout.write(
                    "CMD\n" + cmd + "\n"
                    + ("" if ex is None else str(ex)) + "\x1f" + ore + "\n"
                )
            else:
                sys.stdout.write("WAIVED\n")
            sys.exit(0)
    sys.stdout.write("NOITEM\n")
    sys.exit(0)
sys.stdout.write("NOFILE\n")
PY
}

# Reads one top-level scalar from the state JSON; empty when absent/unreadable.
eval_state_field() {
  STATE="$1" FIELD="$2" python3 -c 'import json,os
try:
    print(json.load(open(os.environ["STATE"])).get(os.environ["FIELD"], "") or "")
except Exception:
    print("")' 2>/dev/null || true
}

# ── list (alias: status --all) ───────────────────────────────────────────
# Enumerates every live run's state — the singleton (if present) plus every
# <bank>/.work-state/*.json slot — as a JSON array. Fail-safe: a corrupt slot
# is silently skipped, never crashes the listing.
cmd_list() {
  parse_common_flags "$@"
  local bank
  bank=$(mb_resolve_path "$PARSED_MB")
  BANK="$bank" python3 - <<'PY'
import glob
import json
import os

bank = os.environ["BANK"]
paths = []
singleton = os.path.join(bank, ".work-state.json")
if os.path.isfile(singleton):
    paths.append(singleton)
paths.extend(sorted(glob.glob(os.path.join(bank, ".work-state", "*.json"))))

entries = []
for p in paths:
    try:
        with open(p, encoding="utf-8") as fh:
            entries.append(json.load(fh))
    except Exception:
        continue
print(json.dumps(entries))
PY
}
