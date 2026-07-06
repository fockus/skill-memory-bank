#!/usr/bin/env bash
# mb-conflicts.sh — /mb conflicts: surface pairs of memory entries that have high
# lexical overlap AND opposing/replacement assertions as conflict candidates,
# using ZERO LLM calls in the default pass.
#
# Usage: mb-conflicts.sh [mb_path] [--judge] [--threshold N]
#   mb_path      optional explicit Memory Bank path (default: resolver)
#   --judge      confirm/reject each candidate via ONE Sonnet `claude -p` call and
#                print a suggested `[SUPERSEDED: YYYY-MM-DD -> <ref>]` marker line.
#                PRINT-ONLY — the script NEVER writes to any bank file.
#   --threshold  Jaccard token-overlap threshold for candidacy (default 0.3).
#
# Contract: REQ-022/023 — $0 Jaccard+marker pairs; --judge Sonnet confirm (PRINT-ONLY).
# Anti-recursion: CLAUDECODE unset + MB_CAPTURE_SUBPROCESS=1 (see mb-recap.sh).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

CLAUDE="${CLAUDE:-claude}"
SONNET_MODEL="${SONNET_MODEL:-sonnet}"

# ── Parse args ───────────────────────────────────────────────────────────────
MB_ARG=""
JUDGE=0
THRESHOLD="0.3"
# Cap on judge (Sonnet) calls — bounds O(n^2) cost on large banks.
MAX_CANDIDATES="${MB_CONFLICTS_MAX_CANDIDATES:-10}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --judge) JUDGE=1; shift ;;
    --threshold)
      THRESHOLD="${2:-}"
      [ -n "$THRESHOLD" ] || { echo "mb-conflicts: --threshold needs a value" >&2; exit 64; }
      shift 2 ;;
    --threshold=*) THRESHOLD="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0 ;;
    -*) echo "mb-conflicts: unknown option '$1'" >&2; exit 64 ;;
    *)
      if [ -z "$MB_ARG" ]; then MB_ARG="$1"; else
        echo "mb-conflicts: unexpected argument '$1'" >&2; exit 64
      fi
      shift ;;
  esac
done

# Fail-closed: reject non-finite or out-of-range thresholds before any work.
_mb_conflicts_validate_threshold() {
  MB_THRESHOLD="$THRESHOLD" python3 -c 'import math,os,sys
try: t=float(os.environ["MB_THRESHOLD"])
except ValueError: sys.exit(64)
sys.exit(64 if not math.isfinite(t) or t<0.0 or t>1.0 else 0)' 2>/dev/null
}
_mb_conflicts_validate_threshold || {
  echo "mb-conflicts: invalid --threshold '"'"'$THRESHOLD'"'"' (need finite number in [0,1])" >&2
  exit 64
}

MB_PATH="$(mb_resolve_path "$MB_ARG")"

# ── $0 deterministic pass (Python, stdlib only) ──────────────────────────────
# Emits one tab-separated line per candidate pair:
#   <jaccard>\t<labelA>\t<labelB>\t<marker>\t<dateA>\t<dateB>\t<b64bodyA>\t<b64bodyB>
# Dates are YYYY-MM-DD or empty when unknown. Bodies are base64 (line-safe so
# the bash judge loop can recover the real text). No LLM, no writes. Unicode-aware
# tokenization for en+ru markers.
CANDIDATES_TSV="$(
  MB_PATH="$MB_PATH" MB_THRESHOLD="$THRESHOLD" python3 - <<'PY'
import base64
import os
import re
import sys
from pathlib import Path

mb = Path(os.environ["MB_PATH"])
threshold = float(os.environ.get("MB_THRESHOLD", "0.3"))

# Negation / replacement markers (en + ru). A pair is a conflict candidate only
# when at least one side asserts a replacement/negation of the other.
MARKERS = [
    "no longer", "not ", "instead", "replaced", "replaces", "moved to",
    "deprecated", "superseded", "supersedes", "rather than", "switched to",
    "вместо", "перешли", "перешёл", "перешел", "больше не", "заменили",
    "заменён", "заменен", "устарело", "устарел", "вместо этого",
]

# Lightweight stopwords (en + ru) so overlap reflects topical *subject*, not glue
# or the replacement markers themselves. Marker/glue words (instead, moved,
# switched, replaced…) are excluded so a paraphrased "X moved to Y instead of Z"
# overlaps its predecessor on the shared subject (X/Z), not on the verb of change.
STOP = {
    "the", "a", "an", "to", "of", "for", "and", "or", "in", "on", "at", "is",
    "are", "was", "were", "be", "with", "by", "from", "as", "it", "this", "that",
    "we", "now", "use", "uses", "used", "service", "than", "rather",
    "instead", "moved", "switched", "replaced", "replaces", "supersedes",
    "superseded", "deprecated", "longer",
    "и", "в", "на", "с", "по", "для", "не", "что", "это", "к", "о", "из",
    "вместо", "перешли", "перешёл", "перешел", "заменили", "заменён", "заменен",
}

WORD_RE = re.compile(r"[0-9A-Za-zЀ-ӿ]+", re.UNICODE)
FM_RE = re.compile(r"\A---\n.*?\n---\n", re.DOTALL)
DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")


def strip_frontmatter(text: str) -> str:
    return FM_RE.sub("", text, count=1)


def tokenize(text: str) -> set:
    toks = set()
    for m in WORD_RE.finditer(text.lower()):
        w = m.group(0)
        if len(w) < 3 or w in STOP:
            continue
        if w.isdigit():
            continue  # drop pure-numeric noise (dates, counts) — never topical
        toks.add(w)
    return toks


def find_marker(text: str):
    low = text.lower()
    for mk in MARKERS:
        if mk in low:
            return mk.strip()
    return None


def jaccard(a: set, b: set) -> float:
    if not a or not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0


def date_from_frontmatter(raw: str):
    """First YYYY-MM-DD found inside a leading --- frontmatter block, if any."""
    m = FM_RE.match(raw)
    if not m:
        return ""
    fm = m.group(0)
    d = DATE_RE.search(fm)
    return d.group(1) if d else ""


def date_from_name(name: str):
    """First YYYY-MM-DD in a (file) name, e.g. 2026-06-10_ledger.md."""
    d = DATE_RE.search(name)
    return d.group(1) if d else ""


def date_from_heading(heading: str):
    d = DATE_RE.search(heading)
    return d.group(1) if d else ""


# _BT is the backtick, built with chr(96) rather than a literal char. Reason:
# bash 3.2 (macOS CI) scans backtick pairs even inside a quoted <<'PY' heredoc
# and aborts parsing if the body has an ODD backtick count. Keeping literal
# backticks out of this line (and every line backtick-balanced) keeps it parseable.
_BT = chr(96)
FENCE_RE = re.compile(r"^\s*(" + _BT + r"{3,}|~{3,})(.*)$")
H2_RE = re.compile(r"^## ")


def split_progress_entries(ptext: str):
    """Top-level ``## `` entry blocks of progress.md, file order (newest-first) kept.

    Fence-aware AND depth-aware: a ``## `` line opens a new entry ONLY when it is a
    real level-2 heading OUTSIDE any fenced code block. Fences follow CommonMark — a
    run of >=3 backticks or tildes opens a block, which closes ONLY on a later line
    whose fence is the SAME character and at least as long, with nothing but
    whitespace after it. So a ``~~~`` line inside a backtick fence, or a 3-backtick
    example inside a 4-backtick fence, is body text (NOT a fence toggle), and a
    ``## `` line inside any such block stays in the parent entry rather than becoming
    a fake undated one. ``### `` subsections also stay inside their parent. The
    leading title/preamble (anything before the first real ``## ``) is dropped.
    """
    blocks: list[str] = []
    cur: list[str] = []
    fence_char = ""  # "" → not inside a fence; else the opener's char (backtick or tilde)
    fence_len = 0
    for ln in ptext.splitlines(keepends=True):
        m = FENCE_RE.match(ln)
        if m:
            run, rest = m.group(1), m.group(2)
            if not fence_char:
                fence_char, fence_len = run[0], len(run)  # open a new fence
            elif run[0] == fence_char and len(run) >= fence_len and not rest.strip():
                fence_char, fence_len = "", 0  # valid close (same char, >=len, bare)
            # else: a fence-looking line that is NOT a valid closer → body text.
            cur.append(ln)
            continue
        if not fence_char and H2_RE.match(ln):
            if cur:
                blocks.append("".join(cur))
            cur = [ln]
        else:
            cur.append(ln)
    if cur:
        blocks.append("".join(cur))
    return [b for b in blocks if H2_RE.match(b)]


# entries: (label, body, date)  — date is "" when undatable.
entries = []

# notes/*.md — one entry per file. Date: filename prefix, else frontmatter.
notes_dir = mb / "notes"
if notes_dir.is_dir():
    for p in sorted(notes_dir.glob("*.md")):
        if not p.is_file():
            continue
        try:
            raw = p.read_text(errors="replace")
        except OSError:
            continue
        rel = os.path.relpath(p, mb)
        d = date_from_name(p.name) or date_from_frontmatter(raw)
        entries.append((rel, strip_frontmatter(raw), d))

# lessons.md — one entry for the whole file (no reliable per-file date).
lessons = mb / "lessons.md"
if lessons.is_file():
    try:
        entries.append(("lessons.md", lessons.read_text(errors="replace"), ""))
    except OSError:
        pass

# progress.md — APPEND-ONLY and NEWEST-FIRST by convention: the first TOP-LEVEL
# "## " heading after the title is the most recent entry. Real entries nest "### "
# subsections (Done / Files changed / Follow-up …) inside each dated "## YYYY-MM-DD"
# block, AND may embed fenced code snippets that themselves contain "## " lines. We
# split on TOP-LEVEL "## " headings ONLY, fence-aware: nested "### " content and any
# "## " inside a triple-backtick / ~~~ fence stay in the parent body, and the parent heading's
# date applies to the whole entry. This keeps the newest-10 window counting WHOLE
# dated entries, never subsection/snippet fragments (which carry no date and would
# otherwise flood the window and produce spurious "ordering unknown").
progress = mb / "progress.md"
if progress.is_file():
    try:
        ptext = progress.read_text(errors="replace")
    except OSError:
        ptext = ""
    # Newest-first: the earliest blocks in file order are the newest entries.
    recent = [b for b in split_progress_entries(ptext) if b.strip()][:10]
    for i, b in enumerate(recent):
        first = b.strip().splitlines()[0] if b.strip() else f"entry-{i}"
        head = re.sub(r"^##\s*", "", first).strip()
        label = "progress.md#" + head[:60]
        entries.append((label, b, date_from_heading(head)))

if len(entries) < 2:
    sys.exit(0)

# Precompute token sets + markers.
prepared = [
    (label, tokenize(body), find_marker(body), body, date)
    for (label, body, date) in entries
]

seen = set()
for i in range(len(prepared)):
    li, ti, mi, bi, di = prepared[i]
    for j in range(i + 1, len(prepared)):
        lj, tj, mj, bj, dj = prepared[j]
        marker = mi or mj
        if marker is None:
            continue  # no opposing/replacement assertion → not a conflict
        score = jaccard(ti, tj)
        if score <= threshold:
            continue
        key = (li, lj)
        if key in seen:
            continue
        seen.add(key)
        eb_a = base64.b64encode(bi.encode("utf-8")).decode("ascii")
        eb_b = base64.b64encode(bj.encode("utf-8")).decode("ascii")
        # Emit "-" for an unknown date so NO field is ever empty: tab is an IFS
        # whitespace char, so empty fields would be collapsed by bash `read`.
        print(
            f"{score:.3f}\t{li}\t{lj}\t{marker}\t{di or '-'}\t{dj or '-'}\t{eb_a}\t{eb_b}"
        )
PY
)"

# ── Print the $0 candidate pairs (human-readable) ────────────────────────────
if [ -z "$CANDIDATES_TSV" ]; then
  # <2 entries, or no overlapping+opposing pair: empty output, exit 0.
  exit 0
fi

echo "Conflict candidates (lexical overlap + opposing assertion, \$0 pass):"
while IFS=$'\t' read -r score a b marker _da _db _eba _ebb; do
  [ -n "$score" ] || continue
  printf '  - [overlap %s | marker "%s"]\n      %s\n      %s\n' "$score" "$marker" "$a" "$b"
done <<< "$CANDIDATES_TSV"

# ── $0 pass ends here unless --judge ─────────────────────────────────────────
if [ "$JUDGE" -eq 0 ]; then
  exit 0
fi

# ── --judge: one Sonnet call per candidate (PRINT-ONLY) ──────────────────────
echo ""
if ! command -v "$CLAUDE" >/dev/null 2>&1; then
  echo "mb-conflicts: --judge needs the 'claude' CLI, which is not installed or not on PATH." >&2
  echo "             The \$0 candidates above are still valid; install Claude Code" >&2
  echo "             (https://claude.com/claude-code) or set CLAUDE=<path> to run the judge." >&2
  exit 0
fi

# Cap judge calls to bound O(n^2) Sonnet cost on large banks. Count candidates,
# print a truncation notice when the cap bites, then judge only the first N.
TOTAL_CANDIDATES="$(printf '%s\n' "$CANDIDATES_TSV" | grep -c .)"
if [ "$TOTAL_CANDIDATES" -gt "$MAX_CANDIDATES" ]; then
  echo "Note: $TOTAL_CANDIDATES candidate pairs found; truncating judge to the first $MAX_CANDIDATES (cap MB_CONFLICTS_MAX_CANDIDATES=$MAX_CANDIDATES)."
fi

TODAY="$(date +%Y-%m-%d)"
echo "Judge verdicts (one Sonnet call per candidate, capped at $MAX_CANDIDATES; suggestions are PRINT-ONLY, nothing is written):"

judged=0
while IFS=$'\t' read -r score a b marker da db eba ebb; do
  [ -n "$score" ] || continue
  if [ "$judged" -ge "$MAX_CANDIDATES" ]; then
    break
  fi
  judged=$((judged + 1))

  # Recover the real entry bodies carried from the deterministic pass (base64,
  # so progress.md entries reach the judge as their actual text — not a stub).
  BODY_A="$(printf '%s' "$eba" | python3 -c 'import base64,sys;r=sys.stdin.read();sys.stdout.write("" if not r else base64.b64decode(r).decode())' 2>/dev/null || true)"
  BODY_B="$(printf '%s' "$ebb" | python3 -c 'import base64,sys;r=sys.stdin.read();sys.stdout.write("" if not r else base64.b64decode(r).decode())' 2>/dev/null || true)"
  if { [ -n "$eba" ] && [ -z "$BODY_A" ]; } || { [ -n "$ebb" ] && [ -z "$BODY_B" ]; }; then
    echo "  - NO VERDICT (body decode failed): $a / $b"
    continue
  fi

  PROMPT="You judge whether two Memory Bank entries genuinely CONFLICT — i.e. the second asserts something that contradicts or replaces a fact in the first (not merely related, not complementary). Reply with EXACTLY one word on the first line: CONFIRMED or REJECTED. No other text.

ENTRY A ($a):
$BODY_A

ENTRY B ($b):
$BODY_B"

  VERDICT="$(printf '%s' "$PROMPT" | env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1 "$CLAUDE" -p \
    --model "$SONNET_MODEL" --strict-mcp-config --no-session-persistence --no-chrome 2>/dev/null || true)"

  # Normalize fail-open: extract the first confirmed/rejected token. A transient
  # model error (empty or non-conforming output) makes grep exit non-zero, which
  # under `set -euo pipefail` would otherwise ABORT the whole --judge run; the
  # `|| true` degrades that to an empty $V so the loop keeps going.
  V="$(printf '%s' "$VERDICT" | tr '[:upper:]' '[:lower:]' | grep -Eo 'confirmed|rejected' | head -n1 || true)"

  if [ -z "$V" ]; then
    # No usable verdict (empty / unparseable judge output). Degrade gracefully:
    # report the candidate as unjudged and continue to the next one. Never abort
    # the run on a single bad verdict.
    echo "  - NO VERDICT (judge returned empty/unparseable output — candidate unknown):"
    echo "      $a"
    echo "      $b"
  elif [ "$V" = "confirmed" ]; then
    echo "  - CONFIRMED conflict:"
    echo "      $a"
    echo "      $b"
    # Suggested supersede marker (format: references/metadata.md). Mark the OLDER
    # entry in place, pointing at the NEWER one. Determine old/new from available
    # dates (frontmatter / date-prefixed filename / progress heading). When the
    # ordering CANNOT be determined, do NOT guess a target. PRINTED ONLY.
    older=""; newer=""
    if [ "$da" != "-" ] && [ "$db" != "-" ] && [ "$da" != "$db" ]; then
      if [ "$da" \< "$db" ]; then older="$a"; newer="$b"; else older="$b"; newer="$a"; fi
    fi
    if [ -n "$older" ]; then
      echo "      suggested marker for the older entry ($older):"
      echo "        [SUPERSEDED: $TODAY -> $newer]"
    else
      echo "      ordering unknown (no comparable dates) — cannot determine which entry"
      echo "      supersedes which; review manually before marking either as [SUPERSEDED]."
    fi
  else
    echo "  - REJECTED (not a real conflict):"
    echo "      $a"
    echo "      $b"
  fi
done <<< "$CANDIDATES_TSV"

exit 0
