#!/usr/bin/env bash
# mb-subinvoke-resolve.sh — resolve the per-agent shell sub-invoke command
# TEMPLATE for the active agent (dynamic-flow Task 12, REQ-DF-082/051/052).
#
# This is the precedent-mirroring sibling of mb-reviewer-resolve.sh: it picks a
# per-agent value (there: the reviewer agent name; here: the sub-invoke command
# template) for the active agent. `mb-fanout.sh` uses it to bake `--cmd` when the
# operator did not supply one, so a fan-out works on every supported agent.
#
# ─── SECURITY SEAM (consistent with mb-fanout.sh) ───────────────────────────
#   The resolved template is a per-agent sub-invoke command run by mb-fanout via
#   `bash -c "<template>"`. The branch PROMPT reaches the template EXCLUSIVELY
#   through the exported env var MB_FANOUT_PROMPT — the template contains the
#   literal token `$MB_FANOUT_PROMPT`, NEVER an interpolated prompt string. A
#   prompt is therefore never `eval`'d nor string-spliced into shell code. This
#   resolver only ever PRINTS the template verbatim (single-quoted heredoc), so a
#   prompt cannot leak in even if MB_FANOUT_PROMPT is set in this process.
# ────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   mb-subinvoke-resolve.sh [--agent <name>] [-h|--help]
#
#   --agent <name>  : the active agent (claude-code | codex | pi | opencode).
#                     Default: $MB_AGENT, else claude-code (the codebase-wide
#                     default, mirroring ${MB_AGENT:-claude-code}).
#
# Resolution order (first hit wins):
#   1. MB_SUBINVOKE_CMD env override — an operator/baked template ALWAYS wins, so
#      `mb-fanout --cmd` and a baked env stay authoritative (even for an agent the
#      table does not know).
#   2. Built-in table for the active agent:
#        codex       → codex exec --model "${MB_SUBINVOKE_MODEL:-gpt-5.5}" \
#                        --sandbox read-only "$MB_FANOUT_PROMPT"
#        claude-code → env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1 \
#                        claude -p "$MB_FANOUT_PROMPT" --model \
#                        "${MB_SUBINVOKE_MODEL:-sonnet}" --strict-mcp-config \
#                        --no-session-persistence --no-chrome  (anti-recursion env)
#        pi          → pi -p --no-session --model \
#                        "${MB_SUBINVOKE_MODEL:-openai-codex/gpt-5.5}" \
#                        "$MB_FANOUT_PROMPT"
#        opencode    → opencode run --model \
#                        "${MB_SUBINVOKE_MODEL:-opencode/gpt-5.2}" "$MB_FANOUT_PROMPT"
#   3. No override and no table hit → exit non-zero with a stderr WARN naming the
#      missing sub-invoke (REQ-DF-052 fail-loud: never silently fall to serial).
#
# All four supported agents (claude-code, codex, pi, opencode) have a builtin
# table entry; a genuinely unsupported/unknown --agent still fails loud (above).
#
# Output: the resolved command template on stdout; exit 0 on success.
#
# Exit codes:
#   0 — a template was resolved (override or table hit).
#   1 — argument error.
#   2 — no sub-invoke command resolvable for the active agent (REQ-DF-052).
#
# Portability: bash 3.2 safe (no associative arrays, no `${v^^}`); set -euo
# pipefail; the templates are emitted from single-quoted heredocs so $-tokens in
# them are printed literally (the prompt is never expanded here).

set -euo pipefail

AGENT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      sed -n '2,47p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --agent)
      [ "$#" -ge 2 ] || { printf '[mb-subinvoke-resolve] --agent needs a value\n' >&2; exit 1; }
      AGENT="$2"; shift 2
      ;;
    --agent=*) AGENT="${1#--agent=}"; shift ;;
    --)
      shift
      ;;
    -*)
      printf '[mb-subinvoke-resolve] unknown flag: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      printf '[mb-subinvoke-resolve] unexpected argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# Default the active agent the same way the rest of the codebase does
# (${MB_AGENT:-claude-code}); an explicit --agent overrides the env.
if [ -z "$AGENT" ]; then
  AGENT="${MB_AGENT:-claude-code}"
fi

# 1. Operator / baked override ALWAYS wins (authoritative for any agent).
if [ -n "${MB_SUBINVOKE_CMD:-}" ]; then
  printf '%s\n' "$MB_SUBINVOKE_CMD"
  exit 0
fi

# 2. Built-in per-agent table. The templates carry the prompt ONLY via the
#    literal $MB_FANOUT_PROMPT token — never an interpolated value. Each is
#    emitted from a single-quoted heredoc so the $-tokens print verbatim.
SUB_MODEL="${MB_SUBINVOKE_MODEL:-}"
# The model id is interpolated into the emitted template (run LATER by mb-fanout
# via `bash -c "$CMD"`), so a non-model value must NEVER reach that template as
# live shell. Validate against a conservative model-id grammar (letters, digits,
# and . _ / -); anything else — spaces, $, (), backticks, quotes — is a config
# error rejected HERE, before emission, so command substitution can never fire.
# The built-in defaults (gpt-5.5 / sonnet) are safe constants and bypass this.
if [ -n "$SUB_MODEL" ]; then
  case "$SUB_MODEL" in
    *[!A-Za-z0-9._/-]*)
      printf '[mb-subinvoke-resolve] invalid MB_SUBINVOKE_MODEL %s (allowed: letters, digits, . _ / -)\n' "$SUB_MODEL" >&2
      exit 1
      ;;
  esac
fi
case "$AGENT" in
  codex)
    # `codex exec` headless run; read-only sandbox is the safe default for a
    # fan-out branch (REQ-DF-082). The model defaults to gpt-5.5 when unset.
    # printf with a %s for the (trusted) model keeps the model interpolated while
    # the literal $MB_FANOUT_PROMPT token is printed verbatim (never expanded).
    [ -n "$SUB_MODEL" ] || SUB_MODEL="gpt-5.5"
    # shellcheck disable=SC2016  # $MB_FANOUT_PROMPT MUST stay literal — the seam:
    # it is expanded later by mb-fanout's `bash -c` with the prompt in the env,
    # never spliced in here. Only the trusted model (%s) is interpolated.
    printf 'codex exec --model "%s" --sandbox read-only "$MB_FANOUT_PROMPT"\n' "$SUB_MODEL"
    exit 0
    ;;
  claude-code)
    # Claude Code headless (`claude -p`) sub-invoke — the documented background /
    # Task-equivalent CLI form (REQ-DF-082). Anti-recursion + non-interactive
    # flags mirror scripts/mb-conflicts.sh / mb-recap.sh. The model defaults to
    # `sonnet` when unset.
    [ -n "$SUB_MODEL" ] || SUB_MODEL="sonnet"
    # `env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1` is the ANTI-RECURSION preamble —
    # without it a claude-code fan-out branch re-enters Claude Code hooks / session
    # capture. This is byte-for-byte the guard scripts/mb-recap.sh and
    # scripts/mb-conflicts.sh use when they shell out to `claude -p`.
    # shellcheck disable=SC2016  # $MB_FANOUT_PROMPT MUST stay literal — the seam:
    # expanded later by mb-fanout's `bash -c` with the prompt in the env, never
    # spliced in here. Only the trusted model (%s) is interpolated.
    printf 'env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1 claude -p "$MB_FANOUT_PROMPT" --model "%s" --strict-mcp-config --no-session-persistence --no-chrome\n' "$SUB_MODEL"
    exit 0
    ;;
  pi)
    # Pi headless (`pi -p --no-session`) sub-invoke (B7/CDX-2). `--no-session`
    # keeps a fan-out branch from persisting/resuming a shared Pi session. The
    # model defaults to a provider/id form Pi accepts verbatim when unset.
    [ -n "$SUB_MODEL" ] || SUB_MODEL="openai-codex/gpt-5.5"
    # shellcheck disable=SC2016  # $MB_FANOUT_PROMPT MUST stay literal — the seam:
    # it is expanded later by mb-fanout's `bash -c` with the prompt in the env,
    # never spliced in here. Only the trusted model (%s) is interpolated.
    printf 'pi -p --no-session --model "%s" "$MB_FANOUT_PROMPT"\n' "$SUB_MODEL"
    exit 0
    ;;
  opencode)
    # OpenCode headless (`opencode run`) sub-invoke (B7/CDX-2). The model
    # defaults to an opencode/id form when unset.
    [ -n "$SUB_MODEL" ] || SUB_MODEL="opencode/gpt-5.2"
    # shellcheck disable=SC2016  # $MB_FANOUT_PROMPT MUST stay literal — the seam:
    # it is expanded later by mb-fanout's `bash -c` with the prompt in the env,
    # never spliced in here. Only the trusted model (%s) is interpolated.
    printf 'opencode run --model "%s" "$MB_FANOUT_PROMPT"\n' "$SUB_MODEL"
    exit 0
    ;;
  *)
    # 3. No override + unknown/unsupported agent → fail loud (REQ-DF-052). Never
    #    print a usable template, so a caller cannot silently fall to serial.
    printf '[mb-subinvoke-resolve] WARN: no sub-invoke command for agent %s — set MB_SUBINVOKE_CMD or pass --cmd (REQ-DF-052)\n' \
      "$AGENT" >&2
    exit 2
    ;;
esac
