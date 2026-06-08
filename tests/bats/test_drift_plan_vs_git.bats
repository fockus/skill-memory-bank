#!/usr/bin/env bats
# mb-drift.sh check #14: plan_vs_git — cross-checks MB plan claims against git reality.
#
# Catches the drift class that bit deep-search-v2: a plan whose YAML frontmatter says
# `status: queued|in_progress` while its declared target files already have commits dated
# AFTER the plan — i.e. the work shipped but the plan/roadmap/checklist still says "not done".
# This is the fail-loud guardrail for Memory Bank itself: drift becomes an exit≠0 failure,
# not a silent state a fresh agent would read as "work not started".

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-drift.sh"
  TMP="$(mktemp -d)"; DIR="$TMP"; MB="$DIR/.memory-bank"
  mkdir -p "$MB/plans/done" "$DIR/src"
  for c in status roadmap checklist research backlog progress lessons; do
    printf '# %s\n' "$c" > "$MB/$c.md"
  done
  git -C "$DIR" init -q
  git -C "$DIR" config user.email t@t.t
  git -C "$DIR" config user.name t
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

# _commit <relpath> <content> <iso-date>
_commit() {
  local rel="$1" content="$2" date="$3"
  mkdir -p "$DIR/$(dirname "$rel")"
  printf '%s\n' "$content" > "$DIR/$rel"
  git -C "$DIR" add "$rel"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$DIR" commit -qm "add $rel"
}

@test "queued plan, declared file committed AFTER plan date -> plan_vs_git warn" {
  _commit "src/feature.py" "code" "2026-06-08T12:00:00"
  printf -- '---\ntype: feature\nstatus: queued\n---\n# p\n\n**Files:**\n- Create: `src/feature.py`\n' \
    > "$MB/plans/2026-06-01_feature_p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_vs_git=warn'
}

@test "queued plan, declared file present but UNCOMMITTED -> ok" {
  printf 'code\n' > "$DIR/src/feature.py"   # exists, untracked
  printf -- '---\ntype: feature\nstatus: queued\n---\n# p\n\n- Create: `src/feature.py`\n' \
    > "$MB/plans/2026-06-01_feature_p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_vs_git=ok'
}

@test "queued plan, file committed BEFORE plan date (modify target) -> ok" {
  _commit "src/existing.py" "old" "2026-01-01T00:00:00"
  printf -- '---\ntype: feature\nstatus: queued\n---\n# p\n\n- Modify: `src/existing.py`\n' \
    > "$MB/plans/2026-06-01_feature_p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_vs_git=ok'
}

@test "in_progress plan, declared file committed AFTER plan date -> warn" {
  _commit "src/wip.py" "code" "2026-06-09T09:00:00"
  printf -- '---\ntype: feature\nstatus: in_progress\n---\n# p\n\n- Create: `src/wip.py`\n' \
    > "$MB/plans/2026-06-01_feature_p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_vs_git=warn'
}

@test "done plan not flagged even if files committed after date" {
  _commit "src/done.py" "code" "2026-06-08T12:00:00"
  printf -- '---\ntype: feature\nstatus: done\n---\n# p\n\n- Create: `src/done.py`\n' \
    > "$MB/plans/2026-06-01_feature_p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_vs_git=ok'
}

@test "non-git project dir -> plan_vs_git skip" {
  rm -rf "$DIR/.git"
  printf -- '---\ntype: feature\nstatus: queued\n---\n# p\n\n- Create: `src/x.py`\n' \
    > "$MB/plans/2026-06-01_feature_p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_vs_git=skip'
}

@test "no active plans -> plan_vs_git ok" {
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_vs_git=ok'
}
