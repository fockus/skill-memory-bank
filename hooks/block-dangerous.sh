#!/bin/bash
# PreToolUse hook: blocks dangerous Bash commands
# Exit 2 = hard block

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for hook" >&2; exit 2; }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0

# BLOCK: destructive commands (exit 2)
if echo "$COMMAND" | grep -qEi \
  'rm\s+-rf\s+/($|\s)|rm\s+-rf\s+~|rm\s+-rf\s+/\*|rm\s+-rf\s+\.\s*$'; then
  echo "BLOCKED: rm -rf on the root/home directory" >&2
  exit 2
fi

if echo "$COMMAND" | grep -qEi 'DROP\s+(TABLE|DATABASE)'; then
  echo "BLOCKED: DROP TABLE/DATABASE" >&2
  exit 2
fi

if echo "$COMMAND" | grep -qEi 'git\s+push\s+.*--force\s+.*(main|master)'; then
  echo "BLOCKED: force push to main/master" >&2
  exit 2
fi

if echo "$COMMAND" | grep -qEi 'git\s+reset\s+--hard\s+(origin|HEAD~|HEAD\^)'; then
  echo "BLOCKED: git reset --hard (destructive)" >&2
  exit 2
fi

if echo "$COMMAND" | grep -qEi '>\s*/dev/sd|dd\s+if=/dev/zero|mkfs\.'; then
  echo "BLOCKED: disk-destructive command" >&2
  exit 2
fi

if echo "$COMMAND" | grep -qEi ':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:'; then
  echo "BLOCKED: fork bomb" >&2
  exit 2
fi

# BLOCK: chmod/chown recursive on system dirs
if echo "$COMMAND" | grep -qEi 'chmod\s+-R\s+.*\s+/(etc|usr|bin|sbin|var|System)'; then
  echo "BLOCKED: recursive chmod on system directory" >&2
  exit 2
fi

if echo "$COMMAND" | grep -qEi 'chown\s+-R\s+.*\s+/(etc|usr|bin|var|System)'; then
  echo "BLOCKED: recursive chown on system directory" >&2
  exit 2
fi

# BLOCK: killing all processes
if echo "$COMMAND" | grep -qEi 'kill\s+-9\s+-1|killall\s+-9'; then
  echo "BLOCKED: killing all processes" >&2
  exit 2
fi

# BLOCK: curl/wget pipe to shell without review
if echo "$COMMAND" | grep -qEi 'curl\s+.*\|\s*(bash|sh|zsh)|wget\s+.*\|\s*(bash|sh|zsh)'; then
  echo "BLOCKED: piping remote script to shell — review script first" >&2
  exit 2
fi

# BLOCK: modifying protected config files
if echo "$COMMAND" | grep -qEi '>\s*~/.ssh/|>\s*~/.gnupg/|>\s*~/.aws/credentials'; then
  echo "BLOCKED: writing to protected config directory" >&2
  exit 2
fi

# BLOCK: git hooks bypass (override via MB_ALLOW_NO_VERIFY=1 for one-off needs)
if echo "$COMMAND" | grep -qEi 'git\s+(commit|push)\s+.*--no-verify'; then
  if [ "${MB_ALLOW_NO_VERIFY:-0}" = "1" ]; then
    echo "WARNING: --no-verify allowed by MB_ALLOW_NO_VERIFY=1 (bypass safety hooks)" >&2
  else
    echo "BLOCKED: --no-verify bypasses safety hooks" >&2
    echo "         override (one-off): MB_ALLOW_NO_VERIFY=1 git commit --no-verify ..." >&2
    exit 2
  fi
fi

# WARN: risky commands (do not block, only emit feedback)
if echo "$COMMAND" | grep -qEi 'rm\s+-rf'; then
  echo "WARNING: rm -rf detected — verify target path" >&2
fi

if echo "$COMMAND" | grep -qEi 'git\s+push\s+.*--force'; then
  echo "WARNING: force push detected — verify branch" >&2
fi

if echo "$COMMAND" | grep -qEi 'git\s+clean\s+-[fd]'; then
  echo "WARNING: git clean — removes untracked files" >&2
fi

if echo "$COMMAND" | grep -qEi 'git\s+branch\s+-D'; then
  echo "WARNING: force-deleting branch — verify it's merged" >&2
fi

if echo "$COMMAND" | grep -qEi 'docker\s+(rm|rmi)\s+.*-f|docker\s+system\s+prune'; then
  echo "WARNING: docker destructive operation" >&2
fi

if echo "$COMMAND" | grep -qEi 'npm\s+publish|pip\s+.*upload|cargo\s+publish'; then
  echo "WARNING: publishing package — verify version and registry" >&2
fi

exit 0
