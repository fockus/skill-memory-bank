# Memory Bank for Hermes

The `memory-bank` plugin runs this skill unchanged inside Hermes Agent. Install it with symlinks, so that updating the skill also updates Hermes.

```bash
SKILL=~/Apps/skill-memory-bank   # this checkout
mkdir -p ~/.hermes/external-skills/memory-bank ~/.hermes/external-skills/mb
for f in SKILL.md LICENSE references docs scripts commands agents rules templates flow-templates hooks; do ln -sfn "$SKILL/$f" ~/.hermes/external-skills/memory-bank/$f; done
ln -sfn "$SKILL/commands/mb.md" ~/.hermes/external-skills/mb/SKILL.md   # gives /mb <command>
ln -sfn "$SKILL/hermes/memory-bank" ~/.hermes/plugins/memory-bank
hermes config set skills.external_dirs '["~/.hermes/external-skills"]'
hermes plugins enable memory-bank && hermes gateway restart
```

Hermes's skill scan does not descend into symlinked folders, so each skill folder is a real directory that holds symlinks.

Which bank a session uses (first match wins):

| Kind | Bank |
|---|---|
| folder | the nearest `.memory-bank/` at or above the session's working directory, also used by other agents |
| project | `$HERMES_HOME/projects/<slug>/.memory-bank` for a Hermes project folder that has no bank of its own |
| general | `$HERMES_HOME/.memory-bank`: one bank per profile (bot), shared by all of its other sessions |

Hermes creates a project or general bank the first time a session needs it. It never creates `.memory-bank/` inside your folders; for that, run `/mb init` there. Each new session gets the bank's context in its system prompt. Terminal commands get `MB_PATH` and `MB_SKILLS_ROOT`. After compaction and when a session ends, the plugin refreshes the handoff capsule.
