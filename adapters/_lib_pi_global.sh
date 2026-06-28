# adapters/_lib_pi_global.sh — Pi global provisioning helpers (sourced by pi.sh).
#
# Extracted from adapters/pi.sh to keep that adapter under the file-size / SRP
# threshold. These functions install the Pi global AGENTS.md managed section and
# register the memory-bank skill in ~/.pi/agent/settings.json without clobbering
# user content.
#
# Expects the sourcing script to have defined these globals beforehand (they are
# resolved at call time): PI_START_MARKER, PI_END_MARKER, PI_AGENT_DIR, SKILL_DIR.
#
# Usage (from pi.sh):
#   # shellcheck source=./_lib_pi_global.sh
#   . "$(dirname "$0")/_lib_pi_global.sh"

pi_global_agents_section() {
  cat <<EOF
$PI_START_MARKER

# Memory Bank — Pi Global Entry Point

Global Memory Bank skill is registered at:
- \`~/.pi/agent/skills/memory-bank/SKILL.md\`

Pi loads this file at startup and injects it into the agent prompt. Treat the section below as always-on Memory Bank guidance.

Bundled resources available to Pi:
- Slash prompt templates: \`~/.pi/agent/prompts/\` (for \`/mb\`, \`/start\`, \`/done\`, \`/plan\`, etc.)
- Skill resources: \`~/.pi/agent/skills/memory-bank/{commands,agents,hooks,scripts,references,rules}/\`

Recommended workflow:
- If \`./.memory-bank/\` exists, Memory Bank is active: read \`status.md\`, \`checklist.md\`, \`roadmap.md\`, and \`research.md\` at session start.
- Use \`/mb start\` to restore project context and \`/mb done\` to save progress.
- Before implementation, prefer \`/mb plan <feature|fix|refactor|experiment> <topic>\` and follow TDD.
- Detailed rules live at \`~/.pi/agent/skills/memory-bank/rules/RULES.md\`.

### Mandatory \`/mb work\` execution gate

When Memory Bank is ACTIVE and the user asks to implement, fix, continue, resume, "do the next step", "go by the plan", or work from an existing plan/spec, **do not implement manually first**. Before editing production code or restoring paused WIP, resolve the Memory Bank work item and workflow:

1. Resolve the effective workflow from \`<bank>/pipeline.yaml\` via \`mb-workflow.sh\` (default may be project-specific, e.g. governed execution).
2. Resolve the target/range via \`mb-work-resolve.sh\` and \`mb-work-plan.sh\`; spec tasks with \`<!-- mb-task:N -->\` are executable source of truth.
3. If a wrapper plan points to a spec, ensure \`linked_spec\` is present; if no executable \`mb-stage\`/\`mb-task\` exists, stop and repair the plan/spec before implementation.
4. Follow the resolved workflow steps exactly (\`implement\`, \`verify\`, \`review\`, \`judge\`, \`fix\`, \`done\`). If \`review\`/\`judge\` are configured, do not claim completion before those gates or an explicit user-approved workflow override.
5. Dispatch agents with the exact \`model\` and \`thinking\` from the JSON line / \`pipeline.yaml\`; never rely on fuzzy model aliases or agent frontmatter defaults.
6. Manual inline work is allowed only for trivial non-plan tasks or when the user explicitly says to skip \`/mb work\`; still apply TDD and verification.

This gate exists to prevent the agent from rationalizing around Memory Bank after compaction, stash restores, or mid-session pivots.

## Core Memory Bank rules

EOF
  sed 's#~/.claude/RULES.md#~/.pi/agent/skills/memory-bank/rules/RULES.md#g; s#~/.claude/skills/memory-bank#~/.pi/agent/skills/memory-bank#g' "$SKILL_DIR/rules/CLAUDE-GLOBAL.md"
  cat <<EOF

$PI_END_MARKER
EOF
}

install_pi_global_agents() {
  local agents_file="$PI_AGENT_DIR/AGENTS.md"
  local tmp section_tmp
  mkdir -p "$PI_AGENT_DIR"
  section_tmp="$(mktemp)"
  pi_global_agents_section > "$section_tmp"

  if [ -f "$agents_file" ] && grep -q "$PI_START_MARKER" "$agents_file" 2>/dev/null; then
    tmp="$agents_file.tmp"
    awk -v s="$PI_START_MARKER" -v e="$PI_END_MARKER" '
      BEGIN { inside=0 }
      index($0, s) { inside=1; next }
      index($0, e) { inside=0; next }
      !inside { print }
    ' "$agents_file" > "$tmp"
    {
      if grep -q '[^[:space:]]' "$tmp"; then
        awk 'NF { last=NR } { lines[NR]=$0 } END { for (i=1; i<=last; i++) print lines[i] }' "$tmp"
        printf '\n\n'
      fi
      cat "$section_tmp"
    } > "$agents_file"
    rm -f "$tmp" "$section_tmp"
    return 0
  fi

  if [ -f "$agents_file" ]; then
    {
      printf '\n'
      cat "$section_tmp"
    } >> "$agents_file"
    rm -f "$section_tmp"
    return 0
  fi

  mv "$section_tmp" "$agents_file"
}

install_pi_settings_skill() {
  local settings_file="$PI_AGENT_DIR/settings.json"
  mkdir -p "$PI_AGENT_DIR"

  SETTINGS_FILE="$settings_file" "${MB_PYTHON:-python3}" <<'PYEOF'
import json
import os
from pathlib import Path

path = Path(os.environ["SETTINGS_FILE"])
skill = "~/.pi/agent/skills/memory-bank"

if path.exists():
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid Pi settings.json, refusing to overwrite: {exc}")
    if not isinstance(data, dict):
        raise SystemExit("invalid Pi settings.json: root must be an object")
else:
    data = {}

raw_skills = data.get("skills", [])
if raw_skills is None:
    raw_skills = []
if not isinstance(raw_skills, list):
    raise SystemExit("invalid Pi settings.json: skills must be an array")

skills = []
for item in [skill, *raw_skills]:
    if item not in skills:
        skills.append(item)

data["skills"] = skills
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PYEOF
}
