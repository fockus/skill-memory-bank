# /mb init — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Contents

- [init [--minimal|--full] [--storage=local|global] [--agent=NAME] [--lang=XX]](#init---minimal--full---storagelocalglobal---agentname---langxx)
- [Step 1: Create the structure](#step-1-create-the-structure)
- [Step 1.5: Offer to populate `codebase/` (`--full` only)](#step-15-offer-to-populate-codebase---full-only)
- [Step 2: Copy RULES (`--full` only)](#step-2-copy-rules---full-only)
- [Step 3: Auto-detect the stack (`--full` only)](#step-3-auto-detect-the-stack---full-only)
- [Step 4: Generate `CLAUDE.md` (`--full` only)](#step-4-generate-claudemd---full-only)
- [Step 5: `.planning/` symlink (`--full` only, optional)](#step-5-planning-symlink---full-only-optional)
- [Step 5.5: Optional profile setup (`--full` only)](#step-55-optional-profile-setup---full-only)
- [Step 6: Summary](#step-6-summary)


## Router entries

- `init [--minimal\|--full]` — Initialize Memory Bank. `--full` (default): add RULES + CLAUDE.md with stack autodetect. `--minimal`: structure only

### init [--minimal|--full] [--storage=local|global] [--agent=NAME] [--lang=XX]

Initialize Memory Bank in a new project.

**Modes** (first word after `init`):

- `--minimal` — only `.memory-bank/` structure + core files. For advanced users who will write `CLAUDE.md` themselves.
- `--full` (default, if no flag is provided) — `.memory-bank/` + `RULES.md` copy + stack auto-detect + `CLAUDE.md` generation + optional `.planning/` symlink prompt.

**Storage (`--storage`)** — since Sprint 1 / global-storage, Memory Bank supports two storage layouts. Default is local (backward compatible).

- `--storage=local` (default) — bank lives at `<project>/.memory-bank/`. **Team-shared** layout: the directory is committable so the whole team shares status / plans / checklist / progress. Use this for any project where Memory Bank state is part of the codebase contract.
- `--storage=global` — bank lives under the chosen agent config directory (`$HOME/.claude/memory-bank/projects/<id>/` for Claude Code, `$HOME/.pi/agent/memory-bank/projects/<id>/` for Pi, etc.) and is registered in `<agent_config>/memory-bank/registry.json`. **Repository stays clean** — no `.memory-bank/` appears in the project tree. Use this for personal storage in a third-party repo, where committing Memory Bank state would create noise for other contributors.

When `--storage=global` is requested, the agent must also resolve `--agent=NAME` (one of `claude-code`, `cursor`, `codex`, `opencode`, `pi`, `windsurf`, `cline`, `kilo`). Default in non-interactive runs comes from `$MB_AGENT` or `claude-code`.

**Interactive prompt** (when stdin is a TTY and `--storage` is not given):

```
Where should this project's Memory Bank live?
  1. local  — .memory-bank/ inside the project (team-shared, default)
  2. global — personal storage under the agent config dir (repo stays clean)
(1/2, default = 1)
```

**Non-interactive shell equivalents** (CI, dotfile bootstrap, scripts):

```bash
# Local mode (team-shared):
bash "$SKILL_DIR"/scripts/mb-init-bank.sh --storage=local --lang=ru

# Global mode (personal, repo stays clean):
bash "$SKILL_DIR"/scripts/mb-init-bank.sh --storage=global --agent=pi \
                             --project-root "$PWD" --lang=ru
```

Safety contract: existing local `.memory-bank/` refuses an implicit local→global switch. The script exits non-zero with migration guidance unless `--force` is provided (and even with `--force` no data is moved — `--force` only allows a parallel global bank).

**Locale (`--lang`)** — since v3.1.1 Memory Bank ships localized template bundles:

- `--lang=en` (default) — English templates
- `--lang=ru` — full Russian translation
- `--lang=es`, `--lang=zh` — scaffolds (EN copy + `TODO(i18n-<lang>)` banner; community translations welcome via PR, see `docs/i18n.md`)

Locale resolution (highest → lowest): `--lang` flag → `MB_LANG` env → `.memory-bank/.mb-config` (`lang=XX`) → auto-detect from existing bank content → `en`.

The agent should invoke `scripts/mb-init-bank.sh --lang=<resolved> --storage=<resolved> [--agent=<resolved>]` to copy the correct `templates/locales/<lang>/.memory-bank/` bundle and wire the storage layout. Canonical anchors (`<!-- mb-active-plans -->`, `## Ideas`, `## ADR`) stay English across every locale — every `mb-*` script depends on them.

> **Rules-only mode reminder.** A project may deliberately have *neither* local nor global Memory Bank (`[MEMORY BANK: ABSENT]`). In that case `/mb` lifecycle commands stay inactive, but the **engineering rules baseline still applies**: TDD, SOLID, Clean Architecture / FSD, DRY/KISS/YAGNI, Testing Trophy, protected files, no placeholders. Skipping `/mb init` is a valid user choice — never auto-initialize on first response.

---

#### Step 1: Create the structure

```bash
mkdir -p .memory-bank/{experiments,plans/done,notes,reports,codebase}
```

Core files (templates — `${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/references/templates.md`):

- `status.md` — project header, "Current phase: Start"
- `roadmap.md` — "Current focus: define", `## Active plan` section with markers `<!-- mb-active-plan -->` / `<!-- /mb-active-plan -->` (for auto-sync)
- `checklist.md` — empty checklist
- `research.md` — header + empty hypothesis table
- `backlog.md` — header + empty `## Ideas` section
- `adr.md` — header only (ADR registry, filled by `/mb adr`)
- `progress.md` — header
- `lessons.md` — header

**If `--minimal` — stop here.** Report `[MEMORY BANK: INITIALIZED]` + a hint to run `/mb start`.

---

#### Step 1.5: Offer to populate `codebase/` (`--full` only)

Before continuing to RULES and stack detection, ask the user whether the skill should seed `.memory-bank/codebase/` now via the `mb-codebase-mapper` subagent:

```
Populate .memory-bank/codebase/ with STACK / ARCHITECTURE / CONVENTIONS / CONCERNS?
This launches the `mb-codebase-mapper` subagent (sonnet) with focus=all.
Default: skip — you can run `/mb map` anytime later.
(y/N)
```

If the answer is `y`, run the subagent exactly as documented in `$SKILL_DIR/references/mb/map.md` (`### map [focus]`) with `focus: all`. If the answer is `N` or empty, skip and continue to Step 2 — never auto-invoke the mapper. The folder stays empty; `/mb start` will suggest `/mb map` on the next session if still empty.

---

#### Step 2: Copy RULES (`--full` only)

```bash
cp ~/.claude/RULES.md .memory-bank/RULES.md
# If it already exists — compare via diff and ask the user before overwriting
```

---

#### Step 3: Auto-detect the stack (`--full` only)

Run `mb-metrics.sh` to detect the stack, then enrich it with more detailed information:

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-metrics.sh
# → stack, test_cmd, lint_cmd, src_count
```

Augment with framework information (grep imports/deps):

- Python: FastAPI, Django, Flask (pyproject.toml + imports)
- Node: Next.js, Express, Nest (package.json deps)
- Go: gin, echo, fiber (go.mod)
- Frontend: React/Vue/Angular/Svelte + FSD layers (check `src/app/`, `src/pages/`, `src/features/`, `src/entities/`, `src/shared/`)

Store the results: `{LANGUAGE}`, `{LANGUAGE_VERSION}`, `{FRAMEWORKS}`, `{PACKAGE_MANAGER}`, `{BUILD_CMD}`, `{TEST_CMD}`, `{LINT_CMD}`, `{RUN_CMD}`, plus the project layout for `{ARCHITECTURE_DETAILS}`.

---

#### Step 4: Generate `CLAUDE.md` (`--full` only)

Use the template from `${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/references/claude-md-template.md`. Fill in `{LANGUAGE}`, `{FRAMEWORKS}`, `{PACKAGE_MANAGER}`, project structure, and key dependencies. Fill `{BUILD_CMD}`, `{TEST_CMD}`, `{LINT_CMD}`, `{RUN_CMD}` from detected tooling (`package.json` scripts, `pyproject.toml` / tox / nox, `Makefile` / `justfile` targets, `go`/`cargo` defaults); drop a line rather than guess a command.

Required sections in generated `CLAUDE.md`:

- **Project** — name and description
- **Commands** — build / test / lint / run commands of this project
- **Stack & conventions** — 3–5 facts not derivable from code + pointer to `codebase/STACK.md` / `CONVENTIONS.md`
- **Architecture** — this project's layout (backend: Clean Architecture layers; frontend: FSD slices)
- **Project rules** — pointer to the project's `RULES.md` (repo root, else `.memory-bank/RULES.md`, AGR-066) + only this project's overrides; do not restate the global rules
- **Memory Bank** — session pipeline, `/mb verify` before `/mb done`, coordination board, key files

**Show the user the draft before writing it.** Ask: "Write CLAUDE.md? Anything to add or change?"

After writing, add the managed Key rules block (only this project's differences from the user-level rules, AGR-083) on top of `CLAUDE.md`:

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-rules.sh sync --scope=project
```

---

#### Step 5: `.planning/` symlink (`--full` only, optional)

If `.planning/` already exists (from GSD or other tools) and `.memory-bank/.planning/` does not exist:

```
I suggest moving `.planning/` inside `.memory-bank/`:
  mv .planning .memory-bank/.planning
  ln -s .memory-bank/.planning .planning

This keeps project artifacts in one directory.
The symlink preserves GSD compatibility.

Do this? (y/n)
```

If `y` — execute it. If `n` — leave everything as-is.

---

#### Step 5.5: Optional profile setup (`--full` only)

After the symlink step, offer to configure a project rule profile:

```
Would you like to configure a rule profile for this project now?
  This personalizes stack/architecture/delivery rules on top of the immutable baseline.
  Skipping keeps the immutable baseline active — you can run `/mb profile init` anytime.
  (y/N)
```

If the answer is `y`, run:

```bash
mb-profile.sh init --scope=project [--role=...] [--stack=...] [--architecture=...] [--delivery=...]
```

Do **not** make profile setup mandatory. Skipping a profile keeps the immutable safety baseline active without any reduction in safety guarantees.

If the user prefers a user-global profile (so it applies across all projects, even without Memory Bank):

```bash
mb-profile.sh init --scope=user --role=<role> --stack=<stack>
```

**Note:** `--profile-skip` documents that skipping is intentional. `--profile-auto` (future flag) would apply stack auto-detection as an advisory recommendation before user confirmation.

---

#### Step 6: Summary

Print:

- Created files: `.memory-bank/` + `CLAUDE.md` (if `--full`)
- Detected stack: `{language}`, `{framework}`, `{tools}`
- Report: `[MEMORY BANK: ACTIVE]`
- Suggest the next steps:
  - `/mb start` — load context in subsequent sessions
  - `/mb map` — populate `.memory-bank/codebase/` (STACK / ARCHITECTURE / CONVENTIONS / CONCERNS) if skipped in Step 1.5
  - `/mb profile init --scope=project` — personalize rule profile (if skipped in Step 5.5)
  - (if the project needs planning) `/mb plan feature "<topic>"`
