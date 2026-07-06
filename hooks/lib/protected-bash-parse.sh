# shellcheck shell=bash
# protected-bash-parse.sh — extract write targets from a Bash command string.

extract_write_targets() {
  local cmd="${1:-}"
  [ -n "$cmd" ] || return 0
  python3 - "$cmd" <<'PY'
import re, sys

cmd = sys.argv[1]
targets = set()

def add(raw: str) -> None:
    t = raw.strip().strip('"\'')
    if not t or t in {"|", ">&", "/dev/null", "/dev/stderr", "/dev/stdout"}:
        return
    if t.startswith("-") and not t.startswith("./"):
        return
    targets.add(t)

for m in re.finditer(r"(?<![0-9])(>>?)\s+(?![&0-9])([^\s|;&]+)", cmd):
    add(m.group(2))

for m in re.finditer(r"\btee\b(?:\s+-[^\s]+)*\s+([^\s|;&]+)", cmd):
    add(m.group(1))

for m in re.finditer(r"\bsed\s+-i(?:\s+\S+)?\s+(\S+)", cmd):
    add(m.group(1))

for m in re.finditer(r"\b(?:cp|mv|install|truncate)\s+(?:[^\s|;&]+\s+)+([^\s|;&]+)", cmd):
    add(m.group(1))

for m in re.finditer(r"\bdd\b[^|;&]*\bof=([^\s|;&]+)", cmd):
    add(m.group(1))

print("\n".join(sorted(targets)))
PY
}
