#!/usr/bin/env bats
# drive-autopilot Task 5 — the /mb drive, /mb goal and /mb mb command contract
# (REQ-020, REQ-041, REQ-033, REQ-046, REQ-050, REQ-029, REQ-052, REQ-055).
#
# Name convention: every @test starts with `drive_cmd: ` (Eval red anchor).
# Prompt clauses go through the discuss_contract harness (assert_clause +
# assert_clause_load_bearing), never a bare grep.

bats_require_minimum_version 1.5.0

load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$MB_DISCUSS_REPO_ROOT"
  DOC="$REPO_ROOT/commands/drive.md"
  GOAL_MD="$REPO_ROOT/commands/goal.md"
  ROUTER_DOC="$REPO_ROOT/commands/mb.md"

  local plan="2\\. Planning phase" act="4\\. Executing an action" hosts="7\\. Hosts"
  local res="8\\. Resume and several drives"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("plan-tier|mb_section|$plan|trivial to standard: ./mb plan <type> <topic> --tier <tier>.|/mb plan|s/trivial to standard: /large or extra: /|REQ-020")
  MB_DISCUSS_CLAUSES+=("plan-sdd|mb_section|$plan|large or extra: ./mb sdd <topic> --auto., then its plan wrapper|/mb sdd|s/ --auto., then/., then/|REQ-020")
  MB_DISCUSS_CLAUSES+=("plan-batch|mb_section|$plan|approval of every large or extra spec in one batch|approval|s/in one batch/one at a time/|REQ-020")
  MB_DISCUSS_CLAUSES+=("plan-qa|mb_section|$plan|qa/README.md. is absent, ask the user for the QA target|QA target|s/ask the user for the QA target/leave the QA target unset/|REQ-020")
  MB_DISCUSS_CLAUSES+=("work-slots|mb_section|$act|always export .MB_WORK_PARALLEL=1.|MB_WORK_PARALLEL|s/always export .MB_WORK_PARALLEL=1./leave MB_WORK_PARALLEL unset/|REQ-055")
  MB_DISCUSS_CLAUSES+=("work-claim|mb_section|$act|the plan path as the positional .<source>. of .mb-work-state.sh init.|mb-work-state.sh init|s/the plan path as the positional/a category as the positional/|REQ-055")
  MB_DISCUSS_CLAUSES+=("work-takeover|mb_section|$act|never pass .--takeover.|--takeover|s/never pass/always pass/|REQ-055")
  MB_DISCUSS_CLAUSES+=("work-exit4|mb_section|$act|exit 4 .*--outcome owned-elsewhere|exit 4|s/--outcome owned-elsewhere/--outcome ok/|REQ-055")
  MB_DISCUSS_CLAUSES+=("team-nogoal|mb_section|$act|team init drive-<run8> --no-goal|team init|s/team init drive-<run8> --no-goal/team init drive-<run8> --goal G/|REQ-041")
  MB_DISCUSS_CLAUSES+=("team-source|mb_section|$act|track add <id> --source <plan> --files <csv>|track add|s/track add <id> --source <plan> /track add <id> /|REQ-041")
  MB_DISCUSS_CLAUSES+=("team-approval|mb_section|$act|the planning approval stands for .team plan.|team plan|s/stands for/does not replace/|REQ-041")
  MB_DISCUSS_CLAUSES+=("host-serial|mb_section|$hosts|.--host-serial. .* one dispatch at a time|--host-serial|s/one dispatch at a time/several dispatches at once/|REQ-033")
  MB_DISCUSS_CLAUSES+=("resume-several|mb_section|$res|several live runs and no id, .resume. lists them|several live runs|s/lists them/picks the newest/|REQ-029")
  MB_DISCUSS_CLAUSES+=("second-goal|mb_section|$res|a second drive takes .--goal <path>.|--goal|s/a second drive takes/a second drive ignores/|REQ-052")
}

clause() {
  run assert_clause "$1" "$2"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run assert_clause_load_bearing "$1" "$2"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# Every fenced code block of a markdown file, fence lines dropped.
fences() {
  awk '/^[ \t]*```/ { inside = !inside; next } inside { print }' "$1"
}

# The bash block right after the `<!-- mb-drive:start -->` marker.
start_fence() {
  awk '
    /<!-- mb-drive:start -->/ { want = 1; next }
    want && /^```bash$/       { inside = 1; want = 0; next }
    inside && /^```$/         { exit }
    inside                    { print }
  ' "$DOC"
}

# ---- planning phase ----------------------------------------------------------

@test "drive_cmd: planning routes trivial to standard items through /mb plan --tier" {
  clause "$DOC" plan-tier
}

@test "drive_cmd: planning writes large or extra items as --auto specs with a wrapper" {
  clause "$DOC" plan-sdd
}

@test "drive_cmd: planning collects every spec approval in one batch" {
  clause "$DOC" plan-batch
}

@test "drive_cmd: planning asks for the QA target when qa/README.md is absent" {
  clause "$DOC" plan-qa
}

# ---- execution ---------------------------------------------------------------

@test "drive_cmd: the action table equals the actions mb_drive_decide.py prints" {
  local doc code
  # First word of every action cell of the execution-loop table.
  doc="$(mb_section "$DOC" '3\. Execution loop' | grep -oE '^\| `[a-z_]+' | sed 's/^| `//' | sort -u)"
  # `firewall` is the status-only stand-in for rule 15; `next` never prints it.
  code="$(grep -oE 'return \(?f?"[a-z_]+' "$REPO_ROOT/scripts/mb_drive_decide.py" \
    | sed -E 's/.*"//' | grep -vx firewall | sort -u)"
  [ -n "$code" ]
  [ "$doc" = "$code" ] || { diff <(echo "$doc") <(echo "$code"); return 1; }
}

@test "drive_cmd: work under drive runs in per-run slots" {
  clause "$DOC" work-slots
}

@test "drive_cmd: work under drive claims the plan path" {
  clause "$DOC" work-claim
}

@test "drive_cmd: work under drive never takes over a claim" {
  clause "$DOC" work-takeover
  clause "$DOC" work-exit4
}

@test "drive_cmd: team under drive starts with --no-goal and one --source track per plan" {
  clause "$DOC" team-nogoal
  clause "$DOC" team-source
  clause "$DOC" team-approval
}

@test "drive_cmd: drive adds no review, judge or verify of its own" {
  run grep -Eic 'review|judge' "$DOC"
  [ "$output" -eq 1 ]
  grep -Ei 'review|judge' "$DOC" | grep -q 'no verify, review or judge of its own'
}

# ---- hosts, resume, several drives -------------------------------------------

@test "drive_cmd: --host-serial is documented for a one-dispatch host" {
  clause "$DOC" host-serial
}

@test "drive_cmd: resume with several live runs lists them" {
  clause "$DOC" resume-several
}

@test "drive_cmd: a second drive takes --goal" {
  clause "$DOC" second-goal
}

# ---- paths and the scripts ---------------------------------------------------

@test "drive_cmd: no drive, goal or mb fence uses dirname \$0 or a fixed bank" {
  local f
  for f in "$DOC" "$GOAL_MD" "$ROUTER_DOC"; do
    if fences "$f" | grep -nF -e 'dirname "$0"' -e 'BANK=".memory-bank"'; then
      echo "fence in $f resolves the bundle or the bank by hand" >&2
      return 1
    fi
  done
}

@test "drive_cmd: the start fence resolves the bundle and the bank through the shared resolver" {
  local fence
  fence="$(start_fence)"
  [[ "$fence" == *'SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"'* ]] || false
  [[ "$fence" == *'BANK="$(mb_resolve_path "${BANK:-}")"'* ]] || false
  [[ "$fence" == *'mb-drive.sh" start'* ]]
}

@test "drive_cmd: every flag of the drive.md usage line is accepted by mb-drive.sh" {
  local usage flag bank="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$bank"
  usage="$(grep -E '^/mb drive ' "$DOC" | head -1)"
  [ -n "$usage" ]
  for flag in $(printf '%s\n' "$usage" | grep -oE -- '--[a-z-]+' | sort -u); do
    case "$flag" in
      --resume) run bash "$REPO_ROOT/scripts/mb-drive.sh" resume --bank "$bank" ;;
      --goal) run bash "$REPO_ROOT/scripts/mb-drive.sh" start --bank "$bank" --goal missing.md ;;
      --budget) run bash "$REPO_ROOT/scripts/mb-drive.sh" start --bank "$bank" --budget 1000 ;;
      *) run bash "$REPO_ROOT/scripts/mb-drive.sh" start --bank "$bank" "$flag" ;;
    esac
    # exit 2 = usage error (unknown flag); 1 = a refusal on the empty bank.
    [ "$status" -ne 2 ] || { echo "mb-drive.sh refuses $flag: $output" >&2; return 1; }
    [[ "$output" != *"unrecognized arguments"* ]] || false
  done
}

@test "drive_cmd: the mb.md drive row and the AGENTS.md line carry only the new flags" {
  local row line
  row="$(grep -E '^\| `drive' "$ROUTER_DOC")"
  line="$(grep -F '/mb drive' "$REPO_ROOT/adapters/_lib_agents_md.sh")"
  local text word
  for text in "$row" "$line" "$(mb_section "$ROUTER_DOC" drive)"; do
    for word in --route --max-cycles "--phase P" implement repair; do
      [[ "$text" != *"$word"* ]] || { echo "old drive surface: $word" >&2; return 1; }
    done
  done
  [[ "$row" == *"--goal"* ]] || false
  [[ "$row" == *"--resume"* ]] || false
  [[ "$line" == *"mb-drive.sh next"* ]] || false
  [[ "$line" == *"returned"* ]] || false
}

@test "drive_cmd: the preflight script and stop arm are gone with no caller left" {
  [ ! -e "$REPO_ROOT/scripts/mb-drive-preflight.sh" ]
  run git -C "$REPO_ROOT" grep -lF 'mb-drive-preflight' -- . ':!.memory-bank' ':!CHANGELOG.md' \
    ':!tests/bats/test_drive_command_contract.bats'
  [ -z "$output" ] || { echo "$output"; return 1; }
  run bash "$REPO_ROOT/scripts/mb-drive-stop.sh" arm --bank "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  run grep -nF '.drive-state.json' "$REPO_ROOT/scripts/mb-work-slots.sh"
  [ "$status" -eq 1 ]
}

@test "drive_cmd: the start fence passes shellcheck" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  local f="$BATS_TEST_TMPDIR/fence.sh"
  { echo '#!/usr/bin/env bash'; start_fence; } > "$f"
  [ "$(wc -l < "$f")" -gt 3 ]
  run shellcheck --severity=warning --shell=bash "$f"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
