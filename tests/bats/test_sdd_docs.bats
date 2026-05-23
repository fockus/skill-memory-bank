#!/usr/bin/env bats
# Doc contract: unified SDD-flow docs across SKILL.md / commands / templates.

setup() {
  REPO="$BATS_TEST_DIRNAME/../.."
}

@test "SKILL.md mentions executable spec tasks" {
  grep -E "spec.*tasks\.md|tasks\.md.*executable|mb-task" "$REPO/SKILL.md"
}

@test "commands/sdd.md references mb-spec-validate.sh" {
  grep -q "mb-spec-validate" "$REPO/commands/sdd.md"
}

@test "references/templates.md contains plan-as-wrapper section" {
  grep -qi "plan as execution wrapper\|linked_spec" "$REPO/references/templates.md"
}

@test "no doc claims tasks.md is scaffold-only" {
  ! grep -rE "tasks\.md is (a |an )?(scaffold|human.only|placeholder).+only" "$REPO/SKILL.md" "$REPO/commands/" "$REPO/references/"
}
