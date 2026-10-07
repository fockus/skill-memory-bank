#!/usr/bin/env bash
# mb-adr-migrate.sh — move ADRs from backlog.md into the ADR registry adr.md (AGR-062).
#
# Usage: mb-adr-migrate.sh [--dry-run|--apply] [mb_path]     (default: --dry-run)
#
# Moves VERBATIM, never rewrites (AGR-043 — data is moved, not deleted):
#   - every `### ADR-NNN …` block: from its heading up to the next `### ` / `## `
#     heading or EOF (`#### ` sub-headings stay inside the block);
#   - every `- ADR-NNN: …` line plus its indented continuation lines.
# Records land in adr.md sorted by ID (merged with records already there); a
# `## ADR` / `## Architectural decisions` section left empty is dropped together
# with a `---` divider right above it. Prose references (`решение ADR-009`) stay.
#
# --apply writes backlog.md.bak first, then adr.md and backlog.md. Re-running is a
# no-op. An ID found twice (both files, or twice in backlog.md) aborts, no writes.
#
# Exit: 0 OK / nothing to migrate, 1 bad usage or bank missing, 2 duplicate ADR ID.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MODE="dry-run"
MB_ARG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    -*) echo "Usage: mb-adr-migrate.sh [--dry-run|--apply] [mb_path]" >&2; exit 1 ;;
    *) MB_ARG="$arg" ;;
  esac
done

MB_PATH=$(mb_resolve_path "$MB_ARG")
[ -d "$MB_PATH" ] || { echo "[error] memory bank not found: $MB_PATH" >&2; exit 1; }

"${MB_PYTHON:-python3}" - "$MB_PATH" "$MODE" <<'PY'
import os
import re
import shutil
import sys
import tempfile

bank, mode = sys.argv[1], sys.argv[2]
backlog_path = os.path.join(bank, "backlog.md")
adr_path = os.path.join(bank, "adr.md")
HEADER = "# Architecture Decision Records\n"

REC_START = re.compile(r"^(?:### |- )ADR-(\d+)\b")
BLOCK_HEAD = re.compile(r"^### ADR-(\d+)\b")
BULLET_HEAD = re.compile(r"^- ADR-(\d+):")
ANY_HEADING = re.compile(r"^#{2,3} ")
ADR_SECTION = re.compile(r"^## (ADR|Architectural decisions)\b.*$", re.IGNORECASE)


def read(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_atomic(path, text):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".adr-migrate.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    if os.path.exists(path):
        shutil.copymode(path, tmp)
    else:
        os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def trim(lines):
    """Record body without trailing blank lines — the verbatim payload."""
    while lines and not lines[-1].strip():
        lines = lines[:-1]
    return "".join(lines).rstrip("\n") + "\n"


def split_backlog(text):
    """Return (kept_lines, records[(id, text)])."""
    lines = text.splitlines(keepends=True)
    kept, records, i = [], [], 0
    while i < len(lines):
        line = lines[i]
        m = BLOCK_HEAD.match(line)
        if m:
            j = i + 1
            while j < len(lines) and not ANY_HEADING.match(lines[j]):
                j += 1
        else:
            m = BULLET_HEAD.match(line)
            if not m:
                kept.append(line)
                i += 1
                continue
            j = i + 1
            while j < len(lines) and lines[j][:1] in (" ", "\t") and lines[j].strip():
                j += 1
        records.append((int(m.group(1)), trim(lines[i:j])))
        # Blank lines after a record belonged to it as separators.
        while j < len(lines) and not lines[j].strip():
            j += 1
        i = j
    return kept, records


def drop_empty_adr_sections(lines):
    out, i = [], 0
    while i < len(lines):
        if ADR_SECTION.match(lines[i].rstrip("\n")):
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            if j == len(lines) or lines[j].startswith("## ") or lines[j].startswith("# "):
                while out and not out[-1].strip():
                    out.pop()
                if out and out[-1].strip() == "---":
                    out.pop()
                    while out and not out[-1].strip():
                        out.pop()
                if j < len(lines):
                    out.append("\n")
                i = j
                continue
        out.append(lines[i])
        i += 1
    return "".join(out).rstrip("\n") + "\n"


def split_registry(text):
    """Return (preamble, records[(id, text)]) of an existing adr.md."""
    lines = text.splitlines(keepends=True)
    starts = [n for n, line in enumerate(lines) if REC_START.match(line)]
    if not starts:
        return trim(lines) if lines else HEADER, []
    bounds = starts + [len(lines)]
    recs = [
        (int(REC_START.match(lines[a]).group(1)), trim(lines[a:b]))
        for a, b in zip(bounds, bounds[1:])
    ]
    return trim(lines[: starts[0]]), recs


backlog = read(backlog_path)
if backlog is None:
    print("nothing to migrate: no backlog.md")
    sys.exit(0)
kept, moved = split_backlog(backlog)
if not moved:
    print("nothing to migrate: no ADR records in backlog.md")
    sys.exit(0)

registry = read(adr_path)
preamble, existing = split_registry(registry) if registry else (HEADER, [])

seen = {}
for rid, _ in existing + moved:
    seen[rid] = seen.get(rid, 0) + 1
dupes = sorted(rid for rid, n in seen.items() if n > 1)
if dupes:
    names = ", ".join("ADR-%03d" % d for d in dupes)
    print(f"[error] duplicate ADR id(s): {names} — resolve by hand, nothing written", file=sys.stderr)
    sys.exit(2)

moved_bytes = sum(len(t.encode("utf-8")) for _, t in moved)
for rid, t in sorted(moved):
    print(f"{'move' if mode == 'apply' else 'would move'} ADR-{rid:03d} ({len(t.encode('utf-8'))} bytes)")
print(f"records={len(moved)} bytes={moved_bytes}")

if mode != "apply":
    print("dry-run: nothing written (use --apply)")
    sys.exit(0)

records = sorted(existing + moved)
new_registry = preamble + "".join("\n" + t for _, t in records)
new_backlog = drop_empty_adr_sections(kept)

shutil.copy2(backlog_path, backlog_path + ".bak")
write_atomic(adr_path, new_registry)
write_atomic(backlog_path, new_backlog)
print(f"applied: adr.md now holds {len(records)} record(s); backup {backlog_path}.bak")
PY
