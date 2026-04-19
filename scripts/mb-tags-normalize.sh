#!/usr/bin/env bash
# mb-tags-normalize.sh — Levenshtein-based tag synonym detection + merge.
#
# Usage: mb-tags-normalize.sh [--dry-run|--apply] [--auto-merge] [mb_path]
#
# Loads vocabulary (priority):
#   1. <mb>/tags-vocabulary.md (user-editable)
#   2. <skill>/references/tags-vocabulary.md (default template)
#
# Detects:
#   - Unknown tags (not in vocabulary AND no close synonym)
#   - Synonyms: distance ≤ 2 → propose merge to vocabulary form (preferred)
#     or shorter variant. --auto-merge applies only distance ≤ 1.
#
# Safety:
#   --dry-run (default): reasoning on stdout, 0 file writes
#   --apply --auto-merge: rewrite frontmatter tags in affected notes
#   --apply без --auto-merge: interactive mode (требует stdin — при closed stdin skip)
#
# Exit: 0 clean; 1 error; 2 unknown tags detected (drift signal for mb-doctor).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MODE="dry-run"
AUTO_MERGE=0
MB_ARG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run)    MODE="dry-run" ;;
    --apply)      MODE="apply" ;;
    --auto-merge) AUTO_MERGE=1 ;;
    --*)
      echo "[error] unknown flag: $arg" >&2
      echo "Usage: mb-tags-normalize.sh [--dry-run|--apply] [--auto-merge] [mb_path]" >&2
      exit 1 ;;
    *) MB_ARG="$arg" ;;
  esac
done

MB_PATH_RAW=$(mb_resolve_path "$MB_ARG")
if [ ! -d "$MB_PATH_RAW" ]; then
  echo "[error] .memory-bank not found at: $MB_PATH_RAW" >&2
  exit 1
fi
MB_PATH=$(cd "$MB_PATH_RAW" && pwd)

# Vocabulary resolution: bank's > default
VOCAB_BANK="$MB_PATH/tags-vocabulary.md"
VOCAB_DEFAULT="$(dirname "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")")/references/tags-vocabulary.md"
# Fallback: if readlink unsupported, try skill root relative to this script.
if [ ! -f "$VOCAB_DEFAULT" ]; then
  VOCAB_DEFAULT="$(cd "$(dirname "$0")/.." && pwd)/references/tags-vocabulary.md"
fi

VOCAB_FILE=""
if [ -f "$VOCAB_BANK" ]; then
  VOCAB_FILE="$VOCAB_BANK"
elif [ -f "$VOCAB_DEFAULT" ]; then
  VOCAB_FILE="$VOCAB_DEFAULT"
fi

# Main работа делается в Python для Levenshtein. Bash отвечает за arg parsing + dispatch.
MODE="$MODE" AUTO_MERGE="$AUTO_MERGE" MB="$MB_PATH" VOCAB="$VOCAB_FILE" python3 - <<'PYEOF'
import os
import re
import sys
from pathlib import Path

mb = Path(os.environ["MB"])
mode = os.environ["MODE"]
auto_merge = os.environ["AUTO_MERGE"] == "1"
vocab_file = os.environ.get("VOCAB") or ""

# ═══ Load vocabulary ═══
vocab: set[str] = set()
if vocab_file and Path(vocab_file).exists():
    for line in Path(vocab_file).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Match "- tag" or "tag"
        m = re.match(r"^\s*-?\s*([a-z0-9][a-z0-9-]*)\s*(?:#.*)?$", line)
        if m:
            vocab.add(m.group(1))

# ═══ Kebab-case normalize helpers (match mb-index-json.py) ═══
def kebab_case(s: str) -> str:
    s = str(s).strip().strip('"\'')
    # camelCase → kebab
    s = re.sub(r"(.)([A-Z][a-z]+)", r"\1-\2", s)
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", s)
    return s.lower()

# ═══ Parse frontmatter tags ═══
FM_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)
TAGS_LINE_RE = re.compile(r"^tags:\s*(.*)$", re.MULTILINE)

def parse_tags(text: str) -> list[str]:
    m = FM_RE.match(text)
    if not m:
        return []
    raw = m.group(1)
    tm = TAGS_LINE_RE.search(raw)
    if not tm:
        return []
    val = tm.group(1).strip()
    if val.startswith("[") and val.endswith("]"):
        inner = val[1:-1].strip()
        if not inner:
            return []
        return [kebab_case(x) for x in inner.split(",")]
    return [kebab_case(val)]

# ═══ Collect all notes + their tags ═══
note_tags: dict[Path, list[str]] = {}
notes_dir = mb / "notes"
if notes_dir.is_dir():
    for note in sorted(notes_dir.rglob("*.md")):
        # Skip archive subdir
        try:
            rel_parts = note.relative_to(notes_dir).parts
        except ValueError:
            continue
        if rel_parts and rel_parts[0] == "archive":
            continue
        try:
            text = note.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        tags = parse_tags(text)
        if tags:
            note_tags[note] = tags

all_tags: set[str] = set()
for tags in note_tags.values():
    all_tags.update(tags)

if not all_tags:
    print("tags_total=0")
    print("unknown=0")
    print("synonyms=0")
    sys.exit(0)

# ═══ Levenshtein distance ═══
def lev(a: str, b: str) -> int:
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            ins = cur[j - 1] + 1
            dele = prev[j] + 1
            sub = prev[j - 1] + (0 if ca == cb else 1)
            cur.append(min(ins, dele, sub))
        prev = cur
    return prev[-1]

# ═══ Detect unknown + synonyms ═══
# Sort by frequency so "popular" wins canonical tie-breaks.
tag_counts: dict[str, int] = {}
for tags in note_tags.values():
    for t in tags:
        tag_counts[t] = tag_counts.get(t, 0) + 1

unknown: list[str] = []
merges: dict[str, str] = {}  # from → to
for tag in sorted(all_tags):
    if tag in vocab:
        continue
    # Find closest in vocab
    best_candidate = None
    best_dist = 99
    for v in vocab:
        d = lev(tag, v)
        if d < best_dist:
            best_dist = d
            best_candidate = v
    # Also try closest among other actual tags (for non-vocab clusters)
    for other in all_tags:
        if other == tag:
            continue
        d = lev(tag, other)
        if d < best_dist:
            best_dist = d
            best_candidate = other
    if best_candidate is not None and best_dist <= 2:
        # Preferred: vocab form; else shorter
        canonical = best_candidate if best_candidate in vocab else \
                    (best_candidate if tag_counts.get(best_candidate, 0) >= tag_counts.get(tag, 0) else tag)
        if canonical != tag:
            merges[tag] = (canonical, best_dist)  # type: ignore
            continue
    # Otherwise truly unknown
    unknown.append(tag)

print(f"tags_total={len(all_tags)}")
print(f"vocab_size={len(vocab)}")
print(f"unknown={len(unknown)}")
print(f"synonyms={len(merges)}")

if merges:
    print("\n# Synonym merges proposed:")
    for src, (dst, d) in sorted(merges.items()):
        print(f"  {src} → {dst} (distance={d})")

if unknown:
    print("\n# Unknown tags (not in vocabulary, no close synonym):")
    for t in sorted(unknown):
        print(f"  - {t} (used in {tag_counts[t]} note(s))")

# ═══ Apply merges if requested ═══
if mode == "apply" and auto_merge and merges:
    # Build rename map limited to distance ≤ 1
    rename_map = {src: dst for src, (dst, d) in merges.items() if d <= 1}
    if not rename_map:
        print("\n[info] no distance ≤ 1 merges to apply (--auto-merge requires distance ≤ 1)")
        sys.exit(0 if not unknown else 2)
    applied = 0
    for note_path, tags in note_tags.items():
        if not any(t in rename_map for t in tags):
            continue
        new_tags = [rename_map.get(t, t) for t in tags]
        # Dedup preserving order
        seen = set()
        deduped = []
        for t in new_tags:
            if t not in seen:
                seen.add(t)
                deduped.append(t)
        new_val = "[" + ", ".join(deduped) + "]"
        text = note_path.read_text(encoding="utf-8")
        new_text = TAGS_LINE_RE.sub(f"tags: {new_val}", text, count=1)
        if new_text != text:
            note_path.write_text(new_text, encoding="utf-8")
            applied += 1
    print(f"\n[apply] rewrote tags in {applied} note(s)")

sys.exit(2 if unknown else 0)
PYEOF
