
# Project Rules — skill-memory-bank

This file specializes the global rules from `~/.claude/RULES.md` for this repository. The global rules remain mandatory. If a rule conflicts, the stricter rule wins.

## Project Identity

- This repository implements the Memory Bank skill: shell scripts, Python helpers, hooks, agent prompts, adapters, commands, docs, and tests for `.memory-bank/` workflows.
- The project is infrastructure code. Preserve deterministic behavior, portability, and cross-agent compatibility over clever abstractions.
- Public behavior is defined by scripts in `scripts/`, hooks in `hooks/`, command docs in `commands/`, adapters in `adapters/`, and tests in `tests/`.

## Required Workflow

- Start every substantive task by reading `status.md`, `checklist.md`, `roadmap.md`, and `research.md`.
- Use the active plan in `.memory-bank/plans/` as source of truth. Do not add off-plan implementation work unless the user explicitly changes scope.
- Update `checklist.md` immediately when a plan stage is completed.
- Before closing planned work, run `/mb verify` and satisfy all CRITICAL findings.
- Keep `progress.md` append-only. Never rewrite historical entries.

## Protected Paths

- Do not edit `.env`, secret files, GitHub workflow files, Docker, Kubernetes, Terraform, or release automation without an explicit user request.
- Treat `install.sh`, adapter install paths, hook registration, and package metadata as release-sensitive. Changes require tests that prove idempotency and uninstall safety.
- Do not remove or rewrite user Memory Bank content outside the specific task scope.

## Architecture Rules

- Shell dispatchers should stay small and deterministic. Shared shell behavior belongs in `_lib.sh` or a narrowly named helper script.
- Python modules should contain parseable, testable logic. Keep CLI argument parsing separate from core functions when behavior grows.
- Hooks must fail open unless the rule is explicitly a blocking guard. Blocking hooks must return clear exit codes and actionable stderr.
- Adapters must be host-specific at the boundary and share common logic through `adapters/_framework.sh` where possible.
- Commands and agent prompts are product contracts. Keep command docs aligned with scripts and tests.
- Cross-agent support must not assume Claude Code only. Preserve OpenCode, Codex, Cursor, Pi, Windsurf, Cline, and Kilo semantics when touching shared install or adapter logic.

## TDD And Tests

- New logic requires tests first. Prefer focused contract tests before implementation.
- Shell behavior is covered by bats tests under `tests/bats/` or `tests/e2e/`.
- Python behavior is covered by pytest tests under `tests/pytest/`.
- Adapter or hook changes require tests for the exact generated path, permissions, idempotency, and failure mode.
- Documentation-only changes must still run the relevant doc or registration tests when they affect command text, skill metadata, agent prompts, or user-facing contracts.
- Do not mark a stage done until the plan DoD command or the closest available focused test has run green.

## Verification Commands

- Preferred full verification: `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json`.
- Focused shell verification: `PATH="$PWD/.venv/bin:$PATH" bats <test files>`.
- Focused Python verification: `PATH="$PWD/.venv/bin:$PATH" pytest <test files>`.
- Rules verification: `bash scripts/mb-rules-check.sh` with the relevant baseline or changed-file scope.
- If a command cannot run in the local environment, record the exact reason and the narrower checks that were run instead.

## Coding Standards

- Keep scripts POSIX-conscious where practical, but use bash intentionally when the existing script does.
- Quote shell variables unless word splitting is required and documented by the surrounding code.
- Prefer explicit case branches and simple helper functions over dense shell expressions.
- Use atomic writes for generated Memory Bank files when a script rewrites user data.
- Preserve existing file permissions for hooks and executable scripts. New executable scripts must be tested for executable bit expectations.
- Avoid placeholder text in production docs and prompts. If a generated scaffold intentionally contains fill-in hints, tests must assert that the hint belongs only to the scaffold output.

## Memory Bank Data Rules

- Core files are lowercase: `status.md`, `roadmap.md`, `checklist.md`, `backlog.md`, `research.md`, `progress.md`, `lessons.md`.
- `roadmap.md`, `status.md`, and `checklist.md` must remain consistent with active and done plans.
- Plan stages use `<!-- mb-stage:N -->` markers. Keep markers stable because scripts parse them.
- Active plan blocks use `<!-- mb-active-plans -->` markers. Do not reintroduce singular legacy markers except in migration fixtures.
- Keep archived or legacy uppercase names only inside explicit migration tests and historical references.

## Documentation Rules

- Update docs when changing command behavior, hook behavior, adapter contracts, CLI flags, or public output.
- User-facing examples must be copy-paste ready and must not mention unavailable commands.
- Keep generated docs and skill descriptions consistent across `SKILL.md`, `commands/`, `CLAUDE.md`, and adapter guidance.

## Release And Compatibility

- Default behavior must remain backward compatible unless the active plan explicitly permits a breaking change.
- New flags, environment variables, or config keys must be opt-in by default unless the plan says otherwise.
- Cross-platform behavior matters: macOS and Linux differences in casing, permissions, `stat`, `date`, and TAP output must be tested or handled explicitly.
- CI baseline is a gate for feature waves. Do not start feature-wave implementation while the active CI baseline plan has open blocking DoD.

