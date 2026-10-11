# team_fixture.bash — a temp git project (path with spaces) holding a bank, for mb-team.sh tests.
# Sets REPO TEAM PROJ BANK; `team` runs mb-team.sh from the project root with --mb.

team_fixture_setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEAM="$REPO/scripts/mb-team.sh"
  PROJ="$BATS_TEST_TMPDIR/proj with space"
  BANK="$PROJ/.memory-bank"
  export MB_LOCK_DIR="$BATS_TEST_TMPDIR/locks"
  mkdir -p "$BANK" "$PROJ/a" "$PROJ/b" "$PROJ/shared"
  local f
  for f in status.md checklist.md roadmap.md; do printf '# %s\n' "$f" >"$BANK/$f"; done
  printf '# Progress\n' >"$BANK/progress.md"
  printf '# Coordination board\n' >"$BANK/COORDINATION.md"
  cat >"$BANK/pipeline.yaml" <<'YAML'
team:
  resources:
    build:
      kind: mutex
      scope: bank
  checkpoint:
    dir: ../backups-out
    max_untracked_mb: 1
YAML
  printf '.memory-bank/\nbackups-out/\n' >"$PROJ/.gitignore"
  echo base >"$PROJ/a/x.txt"; echo base >"$PROJ/b/y.txt"; echo base >"$PROJ/shared/z.txt"
  git -C "$PROJ" init -q . && git -C "$PROJ" config user.email t@t && git -C "$PROJ" config user.name t
  git -C "$PROJ" add -A && git -C "$PROJ" commit -qm init
}

team() { (cd "$PROJ" && bash "$TEAM" --mb "$BANK" "$@"); }

# Replace every `<!-- fill: … -->` hint of the brief, as the orchestrator does.
team_fill_brief() {
  python3 - "$BANK/reports/$1/brief.md" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"<!--\s*fill:.*?-->", "- filled by the orchestrator", s))
PY
}

# Two tracks owning a/** and b/**; shared/** is owned by both when $1 = coowned.
team_two_tracks() {
  team init demo --no-goal --tree "$PROJ" >/dev/null
  local extra=""; [ "${1:-}" = coowned ] && extra=",shared/**"
  team track add A --task "change a" --dod "a/x.txt changed" --files "a/**$extra" --size small >/dev/null
  team track add B --task "change b" --dod "b/y.txt changed" --files "b/**$extra" --size small >/dev/null
}

# Mark a track returned with a report.
team_return() {
  local id="$1" st="${2:-DONE}"
  printf 'STATUS: %s\n\n## Files\n- %s\n\n## Questions\n- ask about %s\n\n## Follow-ups\n- idea from %s\n' \
    "$st" "$id" "$id" "$id" >"$BANK/reports/demo/$id.md"
  team track set "$id" --status dispatched >/dev/null
  team track set "$id" --status returned >/dev/null
}
