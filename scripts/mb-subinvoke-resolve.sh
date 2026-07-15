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
#   mb-subinvoke-resolve.sh [--agent <name>] [--role <role>] [-h|--help]
#
#   --agent <name>  : the active agent (claude-code | codex | pi | opencode).
#                     Default: $MB_AGENT, else claude-code (the codebase-wide
#                     default, mirroring ${MB_AGENT:-claude-code}).
#   --role <role>   : adapter-parity Task 4 (REQ-008/009) — pi ONLY. Scopes
#                     the emitted `pi` template to the named role's
#                     agents/<role>.md `tools:` frontmatter (--tools) and
#                     prompt body (--append-system-prompt <tmpfile>), the D-09
#                     guaranteed-floor Pi dispatch mechanism (design.md
#                     "Subagent dispatch"). Omitted (default) → the
#                     pre-existing unscoped pi/codex/claude-code/opencode
#                     templates, byte-identical to before Task 4. Ignored for
#                     every agent other than pi (they already have native/CLI
#                     dispatch and do not need role scoping here). An unknown
#                     role, or a role name outside the `[A-Za-z0-9_-]+`
#                     grammar, fails loud (WARN, non-zero) — never a silently
#                     unscoped fallback.
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

# Resolves adapters/../agents/<role>.md for the --role scoping below (Task 4).
# Not used at all when --role is omitted, so this never affects existing
# callers' output.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AGENT=""
ROLE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      sed -n '2,71p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --agent)
      [ "$#" -ge 2 ] || { printf '[mb-subinvoke-resolve] --agent needs a value\n' >&2; exit 1; }
      AGENT="$2"; shift 2
      ;;
    --agent=*) AGENT="${1#--agent=}"; shift ;;
    --role)
      [ "$#" -ge 2 ] || { printf '[mb-subinvoke-resolve] --role needs a value\n' >&2; exit 1; }
      ROLE="$2"; shift 2
      ;;
    --role=*) ROLE="${1#--role=}"; shift ;;
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

    if [ -n "$ROLE" ]; then
      # adapter-parity Task 4 (REQ-008/009): role-scoped dispatch is the D-09
      # guaranteed-floor Pi mechanism — --tools/--append-system-prompt are
      # LOAD-BEARING for latency + cost (design.md's measured finding: an
      # unscoped run took 5 turns/~$0.02 to answer "pong"), so a --role
      # request must NEVER fall back to the unscoped template below.
      case "$ROLE" in
        *[!A-Za-z0-9_-]*|"")
          printf '[mb-subinvoke-resolve] WARN: invalid --role %s (allowed: letters, digits, _ -)\n' "$ROLE" >&2
          exit 2
          ;;
      esac
      _role_file="$SKILL_DIR/agents/$ROLE.md"
      if [ ! -f "$_role_file" ]; then
        printf '[mb-subinvoke-resolve] WARN: no agent definition for role %s (expected %s)\n' "$ROLE" "$_role_file" >&2
        exit 2
      fi
      # `tools:` frontmatter line -> comma list, no spaces (Pi's --tools takes
      # a bare CSV, same convention the reference subagent extension uses).
      _role_tools="$(awk -F': *' '/^tools:/{print $2; exit}' "$_role_file" | tr -d '[:space:]')"
      case "$_role_tools" in
        *[!A-Za-z0-9,_-]*)
          printf '[mb-subinvoke-resolve] WARN: role %s has a malformed tools: frontmatter line\n' "$ROLE" >&2
          exit 2
          ;;
      esac
      # Codex review MAJOR #4: agents/*.md `tools:` uses Claude-Code-style
      # capitalized names (Bash, Read, Write, Edit, Grep, Glob, SendMessage);
      # Pi's own --tools allowlist is an EXACT, case-sensitive match against
      # its built-in tool names — verified against the installed
      # @earendil-works/pi-coding-agent SDK (docs/usage.md: "Built-in tools:
      # read, bash, edit, write, grep, find, ls"; the SDK's own
      # createBashToolDefinition()/createReadToolDefinition()/etc. factories
      # confirm those exact lowercase `.name` values, and
      # core/agent-session.js's isAllowedTool is a plain
      # allowedToolNames.has(name) Set lookup). Passing the CC names through
      # verbatim matches ZERO registered Pi tools, silently leaving the
      # dispatched subagent with NO tools at all. Translate to Pi's names;
      # "Glob" maps to Pi's closest built-in ("find"); "SendMessage" has no
      # Pi equivalent (no cross-agent messaging in a headless subprocess) and
      # is DROPPED rather than passed through unmatched — same table as
      # adapters/pi_subagent_dispatch_core.mjs's translateToolsToPi() (keep
      # both in sync if Pi's built-in tool set ever changes).
      _role_tools_pi=""
      if [ -n "$_role_tools" ]; then
        _old_ifs="$IFS"
        IFS=','
        for _t in $_role_tools; do
          IFS="$_old_ifs"
          case "$(printf '%s' "$_t" | tr '[:upper:]' '[:lower:]')" in
            bash) _pi_name="bash" ;;
            read) _pi_name="read" ;;
            write) _pi_name="write" ;;
            edit) _pi_name="edit" ;;
            grep) _pi_name="grep" ;;
            glob|find) _pi_name="find" ;;
            ls) _pi_name="ls" ;;
            *) _pi_name="" ;;
          esac
          if [ -n "$_pi_name" ]; then
            case ",$_role_tools_pi," in
              *",$_pi_name,"*) ;; # already present, dedupe
              *) _role_tools_pi="${_role_tools_pi:+$_role_tools_pi,}$_pi_name" ;;
            esac
          fi
          IFS=','
        done
        IFS="$_old_ifs"
      fi
      # Prompt body = everything after the SECOND `---` frontmatter delimiter,
      # written to a fresh tmpfile so --append-system-prompt can reference it;
      # the file is consumed moments later by mb-fanout's `bash -c "$tmpl"`.
      #
      # CALLER CLEANUP CONTRACT: this tmpfile is created EAGERLY at resolve
      # time (mb-fanout always executes the returned template immediately
      # after resolving it, so the trailing `rm -f` below closes the loop in
      # production) — a caller that resolves the template and does NOT run
      # it (dry-run inspection, a test asserting only on the string) is
      # responsible for removing the path it can extract from the
      # `--append-system-prompt` argument itself; it is not auto-cleaned in
      # that case. tests/bats/test_pi_agents_dispatch.bats does this for
      # every resolve-only assertion.
      _role_prompt_file="$(mktemp)"
      awk 'BEGIN{d=0} /^---[ \t]*$/{d++; next} d>=2{print}' "$_role_file" > "$_role_prompt_file"
      # printf %q (not a manual double-quote) shell-escapes the tmpfile path
      # so it round-trips safely through bash -c even in the (unlikely, but
      # not impossible on every platform) case TMPDIR/mktemp produces a path
      # with a space or shell-special character.
      _role_prompt_file_q="$(printf '%q' "$_role_prompt_file")"
      # shellcheck disable=SC2016  # $MB_FANOUT_PROMPT MUST stay literal — the seam:
      # it is expanded later by mb-fanout's `bash -c` with the prompt in the env,
      # never spliced in here. Only the trusted model/tools (%s) and the
      # already-%q-escaped tmpfile path are interpolated — tools came from our
      # own repo-bundled agents/*.md (validated + translated above), the
      # tmpfile path is our own mktemp output.
      #
      # `; _ec=$?; rm -f <tmpfile>; exit $_ec` cleans up the tmpfile AFTER pi
      # exits without masking pi's own exit code (mb-fanout reads the
      # template's exit status for pass/fail) — a bare trailing `rm` would
      # have silently turned every failed dispatch into a reported success.
      if [ -n "$_role_tools_pi" ]; then
        printf 'pi --mode json -p --no-session --model "%s" --tools "%s" --append-system-prompt %s "$MB_FANOUT_PROMPT"; _ec=$?; rm -f %s; exit $_ec\n' \
          "$SUB_MODEL" "$_role_tools_pi" "$_role_prompt_file_q" "$_role_prompt_file_q"
      else
        printf 'pi --mode json -p --no-session --model "%s" --append-system-prompt %s "$MB_FANOUT_PROMPT"; _ec=$?; rm -f %s; exit $_ec\n' \
          "$SUB_MODEL" "$_role_prompt_file_q" "$_role_prompt_file_q"
      fi
      exit 0
    fi

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
