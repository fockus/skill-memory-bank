#!/usr/bin/env bats
# scripts/mb-roadmap-sync.sh — Group MEMBER ORDERING: intra-group ICE order,
# blockers, aggregate progress, block placement, and the warning-vs-hard-error
# split for malformed ordering fields (design.md C2; REQ-003/013).
#
# Split out of test_mb_roadmap_sync_group.bats to keep both files under the
# 400-line project gate (finding 11).
#
# Red-anchor: every test name starts with `roadmap_sync_group: `.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-roadmap-sync.sh"
  GROUP="grp"

  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK/plans" "$BANK/specs" "$BANK/context"

  printf -- '# Roadmap\n\nIntro that must stay byte-identical.\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\nTrailing that must stay byte-identical.\n' > "$BANK/roadmap.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# mkspec <topic> <group> <ice-value|""> <blocked_by-csv|""> <confirmed|""> <status> <checked> <total> <created-dd>
mkspec() {
  local topic="$1" group="$2" ice="$3" blk="$4" conf="$5" status="$6" checked="${7:-0}" total="${8:-0}" dd="${9:-1}"
  local d="$BANK/specs/$topic"
  mkdir -p "$d"
  {
    printf '%s\n' '---'
    printf 'topic: %s\n' "$topic"
    printf 'group: %s\n' "$group"
    [ -n "$ice" ] && printf 'ice: %s\n' "$ice"
    [ -n "$conf" ] && printf 'ice_confirmed: %s\n' "$conf"
    printf 'blocked_by: [%s]\n' "$blk"
    printf 'status: %s\n' "$status"
    printf '%s\n' '---'
    printf '# Requirements: %s\n' "$topic"
  } > "$d/requirements.md"
  printf -- '---\ntopic: %s\ncreated: 2026-01-%02d\n---\n# ctx\n' "$topic" "$dd" > "$BANK/context/$topic.md"
  local i box
  : > "$d/tasks.md"
  printf '# Tasks\n\n' >> "$d/tasks.md"
  i=1
  while [ "$i" -le "$total" ]; do
    if [ "$i" -le "$checked" ]; then box="x"; else box=" "; fi
    printf -- '<!-- mb-task:%s -->\n## Task %s\n\n**DoD:**\n- [%s] item\n<!-- /mb-task:%s -->\n\n' "$i" "$i" "$box" "$i" >> "$d/tasks.md"
    i=$((i + 1))
  done
}

group_block() {  # lines from `## Group:` region inside the fence
  awk '/<!-- \/mb-roadmap-auto -->/{f=0} f; /## Linked Specs/{f=1}' "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# Group render + intra-group order + blockers + aggregate (REQ-003)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: group members ordered by ICE with blockers respected" {
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" ""  true ready 1 1 1  # 504
  mkspec b "$GROUP" "{impact: 8, confidence: 9, ease: 6}" "a" true ready 0 1 2  # 432, blocked by a
  mkspec c "$GROUP" "{impact: 10, confidence: 8, ease: 5}" "" true ready 0 1 3  # 400
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  group_block > "$TMPROOT/g.txt"
  grep -q "## Group: $GROUP" "$TMPROOT/g.txt"
  # blocked member b emits after its blocker a; c (400, unblocked) precedes b
  order=$(grep -oE '^(a|b|c) — ' "$TMPROOT/g.txt" | awk '{print $1}' | tr '\n' ' ')
  [ "$order" = "a c b " ]
  # blocker is shown on b's line
  grep -qE '^b — .* blocked_by=a$' "$TMPROOT/g.txt"
  grep -qE '^a — .* blocked_by=none$' "$TMPROOT/g.txt"
}

@test "roadmap_sync_group: aggregate group progress is the floor mean of members" {
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 1 1 1  # 100%
  mkspec b "$GROUP" "{impact: 8, confidence: 9, ease: 6}" "" true ready 0 1 2  # 0%
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # mean(100,0)=50
  grep -qE 'progress=50%' <(group_block)
}

@test "roadmap_sync_group: group blocks sit after Linked Specs, before fence, slugs C-locale asc (load-bearing)" {
  # Load-bearing (R3-007): the spec-dir scan order is the REVERSE of the C-locale
  # slug order — dir `aaa` → group `zeta`, dir `zzz` → group `alpha`. So the scan
  # inserts zeta BEFORE alpha; only `sorted(groups.keys())` flips the emitted
  # order to alpha,zeta. Dropping the sort would emit zeta,alpha and fail here.
  mkspec aaa zeta  "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  mkspec zzz alpha "{impact: 8, confidence: 9, ease: 6}" "" true ready 0 1 2
  outside_before=$(awk 'BEGIN{p=1} /<!-- mb-roadmap-auto -->/{p=0} p; /<!-- \/mb-roadmap-auto -->/{p=1}' "$BANK/roadmap.md")
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # exact header form, alpha before zeta despite reversed scan order
  ga=$(grep -n '^## Group: alpha$' "$BANK/roadmap.md" | head -1 | cut -d: -f1)
  gz=$(grep -n '^## Group: zeta$' "$BANK/roadmap.md" | head -1 | cut -d: -f1)
  ls=$(grep -n '^## Linked Specs (active)$' "$BANK/roadmap.md" | head -1 | cut -d: -f1)
  fc=$(grep -n '^<!-- /mb-roadmap-auto -->$' "$BANK/roadmap.md" | head -1 | cut -d: -f1)
  [ -n "$ga" ] && [ -n "$gz" ] && [ -n "$ls" ] && [ -n "$fc" ]
  [ "$ls" -lt "$ga" ]; [ "$ga" -lt "$gz" ]; [ "$gz" -lt "$fc" ]
  # EXACTLY one blank line separates the two group blocks (byte-level, R3-007).
  [ -z "$(sed -n "$((gz - 1))p" "$BANK/roadmap.md")" ]   # separator line is blank
  [ -n "$(sed -n "$((gz - 2))p" "$BANK/roadmap.md")" ]   # and only one blank (prev is content)
  # content outside the fence untouched
  outside_after=$(awk 'BEGIN{p=1} /<!-- mb-roadmap-auto -->/{p=0} p; /<!-- \/mb-roadmap-auto -->/{p=1}' "$BANK/roadmap.md")
  [ "$outside_before" = "$outside_after" ]
}

# ═══════════════════════════════════════════════════════════════
# Malformed member ordering fields — warning vs hard error (design C2)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: malformed pin fails exit 3 (not silent normalization)" {
  mkdir -p "$BANK/specs/s1"
  printf -- '---\ntopic: s1\ngroup: grp\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\nblocked_by: []\npin: nope\nstatus: ready\n---\n# R\n' > "$BANK/specs/s1/requirements.md"
  printf -- '# Tasks\n' > "$BANK/specs/s1/tasks.md"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"invalid_pin"* ]]
}

@test "roadmap_sync_group: malformed blocked_by fails exit 3" {
  mkdir -p "$BANK/specs/s1"
  printf -- '---\ntopic: s1\ngroup: grp\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\nblocked_by: not-a-list\nstatus: ready\n---\n# R\n' > "$BANK/specs/s1/requirements.md"
  printf -- '# Tasks\n' > "$BANK/specs/s1/tasks.md"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"invalid_blocked_by"* ]]
}

@test "roadmap_sync_group: malformed created fails exit 3" {
  mkdir -p "$BANK/specs/s1" "$BANK/context"
  printf -- '---\ntopic: s1\ngroup: grp\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\nblocked_by: []\nstatus: ready\n---\n# R\n' > "$BANK/specs/s1/requirements.md"
  printf -- '# Tasks\n' > "$BANK/specs/s1/tasks.md"
  printf -- '---\ntopic: s1\ncreated: nonsense\n---\n# ctx\n' > "$BANK/context/s1.md"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"invalid_created"* ]]
}

@test "roadmap_sync_group: invalid ICE warns and degrades to legacy tail (no exit 3)" {
  mkdir -p "$BANK/specs/s1" "$BANK/context"
  printf -- '---\ntopic: s1\ngroup: grp\nice: 432\nblocked_by: []\nstatus: ready\n---\n# R\n' > "$BANK/specs/s1/requirements.md"
  printf -- '# Tasks\n' > "$BANK/specs/s1/tasks.md"
  printf -- '---\ntopic: s1\ncreated: 2026-01-01\n---\n# ctx\n' > "$BANK/context/s1.md"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"invalid ice"* ]]
  grep -qE 's1 — ice=invalid — ' "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# Shared ordering fixture through the S4 consumer (R2-003-R3)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: shared svp_group_ordering.json fixture yields its expected order via the S4 render" {
  local fixture="$REPO_ROOT/tests/fixtures/svp_group_ordering.json"
  [ -f "$fixture" ]
  # materialize each canonical case as its own group of specs
  python3 - "$fixture" "$BANK" <<'PY'
import json, os, sys
fixture, bank = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(bank, "context"), exist_ok=True)
for c in json.load(open(fixture))["cases"]:
    grp = c["name"].replace("_", "-")
    for m in c["members"]:
        topic = m["topic"]
        d = os.path.join(bank, "specs", topic)
        os.makedirs(d, exist_ok=True)
        fm = ["---", f"topic: {topic}", f"group: {grp}"]
        if m.get("ice") is not None:
            fm.append(f"ice: {m['ice']}")
        fm.append("ice_confirmed: true")
        fm.append("blocked_by: [%s]" % ", ".join(m.get("blocked_by") or []))
        if m.get("pin") is not None:
            fm.append(f"pin: {m['pin']}")
        fm += ["status: ready", "---", f"# {topic}"]
        open(os.path.join(d, "requirements.md"), "w").write("\n".join(fm) + "\n")
        open(os.path.join(d, "tasks.md"), "w").write("# Tasks\n")
        if m.get("created"):
            open(os.path.join(bank, "context", topic + ".md"), "w").write(
                f"---\ntopic: {topic}\ncreated: {m['created']}\n---\n# ctx\n")
PY
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # each group's rendered member order must equal the fixture's expected order
  python3 - "$fixture" "$BANK/roadmap.md" <<'PY'
import json, re, sys
fixture, roadmap = sys.argv[1], sys.argv[2]
lines = open(roadmap, encoding="utf-8").read().split("\n")
for c in json.load(open(fixture))["cases"]:
    grp = c["name"].replace("_", "-")
    order, inside = [], False
    for ln in lines:
        if ln == f"## Group: {grp}":
            inside = True
            continue
        if inside:
            if ln.startswith("## ") or ln.startswith("<!-- "):
                break
            mo = re.match(r"^([a-z0-9][a-z0-9-]*) ", ln)
            if mo and " ice=" in ln:
                order.append(mo.group(1))
    assert order == c["expected_order"], f"{c['name']}: got {order} want {c['expected_order']}"
print("OK")
PY
}
