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

# ── source containment (r3 review [2]) ────────────────────────────────────
# `init spec 1 --source-path <anywhere>` and `--source-topic ../../fake` were
# accepted and stored verbatim, so the eval gate could be bound to a tasks.md
# the bank does not own — a file whose declaration can change under the gate at
# will. For source=spec there is exactly ONE legal locator:
# `<bank>/specs/<safe-topic>/tasks.md`.
#
# `resolve_spec_source <bank> <topic> <path>` echoes that canonical path on
# success, or nothing (rc 1) when the locator is not contained.
resolve_spec_source() {
  BANK="$1" TOPIC="$2" SRCPATH="$3" python3 - <<'PY'
import os, pathlib, sys

bank = os.environ["BANK"]
topic = os.environ.get("TOPIC", "").strip()
srcpath = os.environ.get("SRCPATH", "").strip()

# The topic is a single safe path segment: no separators, no dot segments, no
# leading dot, no traversal. Checked BEFORE it is ever joined onto a path.
if (
    not topic
    or "/" in topic
    or "\\" in topic
    or topic.startswith(".")
    or topic in (".", "..")
    or not all(c.isalnum() or c in "._-" for c in topic)
):
    sys.exit(1)

try:
    bank_real = pathlib.Path(os.path.realpath(bank))
    specs_real = pathlib.Path(os.path.realpath(bank_real / "specs"))
except OSError:
    sys.exit(1)

canonical = bank_real / "specs" / topic / "tasks.md"
if not canonical.is_file():
    sys.exit(1)

# realpath AFTER resolution: a symlinked spec dir pointing outside the bank
# resolves away from <bank>/specs and is refused here.
real = pathlib.Path(os.path.realpath(canonical))
if not (real == specs_real or specs_real in real.parents):
    sys.exit(1)

# An explicit --source-path is allowed only when it names the same file.
if srcpath:
    try:
        if pathlib.Path(os.path.realpath(srcpath)) != real:
            sys.exit(1)
    except OSError:
        sys.exit(1)

sys.stdout.write(str(canonical))
PY
}

# `init_spec_locator <bank> <topic> <path>` echoes `<topic>\x1f<canonical path>`
# for a contained spec locator, or fails (rc 1). Accepts either a topic or a
# bare --source-path naming a spec inside the bank; both are re-checked through
# resolve_spec_source, so only <bank>/specs/<safe-topic>/tasks.md survives.
init_spec_locator() {
  local bank="$1" topic="$2" path="$3" canonical="" derived
  if [ -n "$topic" ]; then
    canonical=$(resolve_spec_source "$bank" "$topic" "$path" 2>/dev/null || true)
  elif [ -n "$path" ]; then
    derived=$(basename "$(dirname "$path")")
    canonical=$(resolve_spec_source "$bank" "$derived" "$path" 2>/dev/null || true)
    [ -n "$canonical" ] && topic="$derived"
  fi
  [ -n "$canonical" ] || return 1
  printf '%s\037%s' "$topic" "$canonical"
}

# ── declaration binding (r3 review [1]) ───────────────────────────────────
# Echoes the signed JSON object binding this task's whole declaration surface
# (verdict + command + red anchors) as observed at `init`. `done` re-derives it
# and requires equality, so the gate can no longer be re-decided by editing
# tasks.md between the two.
eval_bind_declaration() {
  local bank="$1" source_path="$2" source_topic="$3" item_no="$4" legacy="${5:-}"
  local decl verdict cmd anchors
  decl=$(eval_declaration "$bank" "$source_path" "$source_topic" "$item_no" "$legacy")
  verdict=$(printf '%s\n' "$decl" | sed -n '1p')
  cmd=$(printf '%s\n' "$decl" | sed -n '2p')
  anchors=$(printf '%s\n' "$decl" | sed -n '3p')
  MB_SD="$SCRIPT_DIR" V="$verdict" C="$cmd" A="$anchors" python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["MB_SD"])
import mb_work_eval_proof as proof
d = {"verdict": os.environ["V"], "cmd": os.environ["C"], "anchors": os.environ["A"]}
d["sig"] = proof.sign_decl(d)
sys.stdout.write(json.dumps(d))
PY
}

# ── bound-vs-live declaration verdict (r3 review [1]) ─────────────────────
# Echoes the BOUND verdict when the live declaration still matches what `init`
# captured, or one of UNBOUND / DECLTAMPERED / DECLCHANGED. `done` must decide
# on this and never on a fresh read of the mutable tasks.md.
eval_bound_verdict() {
  local state="$1" bank="$2" item_no="$3" source_="$4" live_decl
  live_decl=$(eval_declaration "$bank" "$(eval_state_field "$state" source_path)" \
    "$(eval_state_field "$state" source_topic)" "$item_no" "$source_")
  STATE="$state" MB_SD="$SCRIPT_DIR" LIVE="$live_decl" python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["MB_SD"])
import mb_work_eval_proof as proof

data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
bound = data.get("decl")
if not isinstance(bound, dict) or not bound:
    # Pre-binding state (older run): fail closed rather than silently trusting
    # the live file, which is the exact hole this binding closes.
    print("UNBOUND"); sys.exit(0)
if not proof.verify_decl(bound):
    print("DECLTAMPERED"); sys.exit(0)

lines = (os.environ.get("LIVE") or "").split("\n")
live = {
    "verdict": lines[0] if len(lines) > 0 else "",
    "cmd": lines[1] if len(lines) > 1 else "",
    "anchors": lines[2] if len(lines) > 2 else "",
}
if any(live[k] != bound.get(k, "") for k in ("verdict", "cmd", "anchors")):
    print("DECLCHANGED"); sys.exit(0)
print(bound.get("verdict", ""))
PY
}

# `eval_reconcile_anchors <ore> <exit> <declared_ore> <declared_exit>` echoes
# `<ore>\x1f<exit>\x1f<red_anchor>` or fails (rc 1) echoing a reason token.
#
# Declared anchors are authoritative in BOTH directions (r3 [3]): a declared
# anchor is the default so the caller need not retype it, and an anchor the
# declaration does NOT carry is refused — `--output-re .*` on an anchorless task
# used to be accepted and recorded as the anchor the red was judged against.
# With neither anchor declared, red is a non-zero exit alone (red_anchor=none).
eval_reconcile_anchors() {
  local ore="$1" exp="$2" dore="$3" dexp="$4" anchor="declared"
  if [ -n "$dore" ]; then
    if [ -n "$ore" ] && [ "$ore" != "$dore" ]; then printf 'ORE_MISMATCH'; return 1; fi
    ore="$dore"
  elif [ -n "$ore" ]; then
    printf 'ORE_UNDECLARED'; return 1
  fi
  if [ -n "$dexp" ]; then
    if [ -n "$exp" ] && [ "$exp" != "$dexp" ]; then printf 'EXIT_MISMATCH'; return 1; fi
    exp="$dexp"
  elif [ -n "$exp" ]; then
    printf 'EXIT_UNDECLARED'; return 1
  fi
  [ -z "$ore" ] && [ -z "$exp" ] && anchor="none"
  printf '%s\037%s\037%s' "$ore" "$exp" "$anchor"
}

# `write_init_state <tmp> <run_id> <source> <item_no> <heading> <source_path>
# <source_topic> <decl_json> <max_cycles> <baseline_ref>` writes the fresh
# run-state JSON. Extracted from cmd_init so the CLI dispatcher stays small and
# every zone file keeps its 400-line budget.
write_init_state() {
  TMP="$1" RUN_ID="$2" SOURCE="$3" ITEM_NO="$4" HEADING="$5" \
    SOURCE_PATH="$6" SOURCE_TOPIC="$7" DECL_JSON="$8" \
    MAX_CYCLES="$9" BASELINE_REF="${10}" python3 - <<'PY'
import json, os, datetime
state = {
    "run_id": os.environ["RUN_ID"],
    "source": os.environ["SOURCE"],  # category; the locator fields follow ([9])
    "source_path": os.environ.get("SOURCE_PATH", ""),
    "source_topic": os.environ.get("SOURCE_TOPIC", ""),
    "item_no": int(os.environ["ITEM_NO"]),
    "heading": os.environ.get("HEADING", ""),
    "cycle": 0,
    "max_cycles": int(os.environ["MAX_CYCLES"]),
    "steps": [],
    "phase": "in-progress",
    "baseline_ref": os.environ.get("BASELINE_REF", ""),
    "updated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
# The declaration surface bound at init (r3 review [1]).
try:
    state["decl"] = json.loads(os.environ.get("DECL_JSON") or "{}")
except ValueError:
    state["decl"] = {}
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(state) + "\n")
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
