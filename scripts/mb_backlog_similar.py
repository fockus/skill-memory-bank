#!/usr/bin/env python3
"""Out-of-scope similarity lookup for mb-idea.sh (design.md C3, REQ-008).

Usage: mb_backlog_similar.py <backlog.md> <title>

Compares the candidate title ONLY against titles of entries under
``## Out of scope``. Normalisation: casefold, every non-alphanumeric char to a
space, keep unique tokens of length >= 4. ``score = |a & b| / min(|a|, |b|)``;
an empty token set scores 0. A score >= 0.5 is a match; the smallest numeric
I-NNN wins. Prints ``<I-NNN> <score>`` for the winner, nothing otherwise.
Local tokenisation only — no LLM, no network.
"""

import re
import sys

from mb_backlog_state_engine import parse_backlog, read_text

THRESHOLD = 0.5


def tokens(text):
    return {t for t in re.sub(r"[\W_]+", " ", text.casefold()).split() if len(t) >= 4}


def score(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / min(len(a), len(b))


def best_match(backlog_text, title):
    _, entries = parse_backlog(backlog_text)
    cand = tokens(title)
    hits = []
    for e in entries:
        if e["section"] != "Out of scope":
            continue
        s = score(cand, tokens(e["title"]))
        if s >= THRESHOLD:
            hits.append((e["num"], e["id"], s))
    if not hits:
        return None
    _, entry_id, s = min(hits)
    return entry_id, s


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: mb_backlog_similar.py <backlog.md> <title>\n")
        return 2
    found = best_match(read_text(argv[0]), argv[1])
    if found:
        print(f"{found[0]} {found[1]:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
