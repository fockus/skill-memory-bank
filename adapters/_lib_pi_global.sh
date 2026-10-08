# shellcheck shell=bash
# adapters/_lib_pi_global.sh — Pi global provisioning helpers (sourced by pi.sh).
#
# Extracted from adapters/pi.sh to keep that adapter under the file-size / SRP
# threshold. These functions install the Pi global AGENTS.md managed section and
# register the memory-bank skill in ~/.pi/agent/settings.json without clobbering
# user content.
#
# Expects the sourcing script to have defined these globals beforehand (they are
# resolved at call time): PI_START_MARKER, PI_END_MARKER, PI_AGENT_DIR, SKILL_DIR —
# and to have sourced _lib_agents_md.sh (mb_emit_rules_file, mb_upsert_marked_block).
# install.sh and adapters/pi.sh both use this file, so the Pi section has one source.
#
# Usage (from pi.sh):
#   # shellcheck source=./_lib_pi_global.sh
#   . "$(dirname "$0")/_lib_pi_global.sh"

# Short host header + the compact rules core. The Key rules block above it is
# written by install.sh Step 5.5 (mb-rules.sh sync --scope=user); detailed rules
# stay in the skill's rules/RULES.md (AGR-063, AGR-066).
pi_global_agents_section() {
  cat <<EOF
$PI_START_MARKER

# Memory Bank — Pi Global Entry Point

Pi loads this file at startup and injects it into the agent prompt. Skill: \`~/.pi/agent/skills/memory-bank/SKILL.md\`; prompt templates (\`/mb\`, \`/start\`, \`/done\`, …): \`~/.pi/agent/prompts/\`.

### \`/mb work\` gate

The gate applies when the request refers to an existing plan or spec in the bank (implement, fix, continue, resume, go by it). Without one, size the task (SKILL.md § Task routing): trivial and small tasks are done inline. When it applies:
1. Workflow: \`mb-workflow.sh\` on \`<bank>/pipeline.yaml\`; target: \`mb-work-resolve.sh\` + \`mb-work-plan.sh\`. Spec tasks \`<!-- mb-task:N -->\` are the source of truth; a wrapper plan without \`linked_spec\`/\`mb-stage\` is fixed before coding.
2. Run the resolved steps exactly; claim completion only after the configured gates or an explicit user override.
3. Dispatch roles by name: \`mb_dispatch_subagent(role=<agent>, task=…)\`; \`model\`/\`thinking\` only when the JSON line sets them.

Planned work runs inline only when the user asks to skip \`/mb work\`; the tier's tests and verification still apply.

EOF
  mb_emit_rules_file "$SKILL_DIR/rules/CLAUDE-GLOBAL.md" \
    | sed 's#~/.claude/RULES.md#~/.pi/agent/skills/memory-bank/rules/RULES.md#g; s#~/.claude/skills/memory-bank#~/.pi/agent/skills/memory-bank#g'
  cat <<EOF

$PI_END_MARKER
EOF
}

# Prints created|refreshed|merged (mb_upsert_marked_block in _lib_agents_md.sh).
install_pi_global_agents() {
  local section
  section="$(mktemp)"
  pi_global_agents_section > "$section"
  mb_upsert_marked_block "$PI_AGENT_DIR/AGENTS.md" "$PI_START_MARKER" "$PI_END_MARKER" "$section"
  rm -f "$section"
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

# Native managed runtime (AGR-057/088): request the pinned Tintin package with its
# extension filtered out, so Pi's own package manager installs it while ordinary
# sessions never load it; only <agentDir>/bin/mb-pi composes it. Additive: an
# existing entry for the package (any form) is the user's and is left alone.
# $1 = add|remove|check; add prints added|created|preexisting. $2=1 on remove:
# the file was created by add, so drop it once nothing else remains. Invalid
# settings refuse without a write.
PI_TINTIN_PACKAGE="npm:@tintinweb/pi-subagents@0.19.0"

pi_settings_tintin() {
  SETTINGS_FILE="$PI_AGENT_DIR/settings.json" ACTION="$1" CREATED="${2:-0}" SOURCE="$PI_TINTIN_PACKAGE" \
    "${MB_PYTHON:-python3}" <<'PYEOF'
import json
import os
import sys
from pathlib import Path

path = Path(os.environ["SETTINGS_FILE"])
action, source = os.environ["ACTION"], os.environ["SOURCE"]
entry = {"source": source, "extensions": []}
name = source.rsplit("@", 1)[0]

data = {}
if path.exists():
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        sys.exit(f"[pi-adapter] invalid Pi settings.json, refusing to modify: {exc}")
if not isinstance(data, dict) or not isinstance(data.get("packages", []), list):
    sys.exit("[pi-adapter] Pi settings.json root/packages has an unexpected shape, refusing to modify")
packages = data.get("packages", [])

def is_tintin(item):
    src = item if isinstance(item, str) else (item or {}).get("source", "")
    return src == name or src.startswith(name + "@")

if action == "check":
    sys.exit(0)
if action == "add":
    if any(is_tintin(item) for item in packages):
        print("preexisting")
        sys.exit(0)
    created = not path.exists()
    data["packages"] = [*packages, entry]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print("created" if created else "added")
elif action == "remove" and entry in packages:
    data["packages"] = [item for item in packages if item != entry]
    if data == {"packages": []} and os.environ["CREATED"] == "1":
        path.unlink()
    else:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PYEOF
}
