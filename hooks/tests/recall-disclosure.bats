#!/usr/bin/env bats
# Task 9 — progressive disclosure + age + fusion in `/mb recall`.
# Covers spec scenarios 6 (compact index, no bodies, superseded last) and
# 7 (unknown --expand id → non-zero + message), plus --expand / --full / token budget.
#
# Hermetic: an isolated tmp Memory Bank WITHOUT a .venv, so the recall hook resolves
# `python3` from PATH. A stubbed `python3` in PATH feeds deterministic semantic JSON;
# the real `python3` (for the recall-index bridge) is reached via PY_REAL so the stub
# only intercepts the semantic CLI call (which runs `mb-semantic.py`).

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-recall.sh"
  SEMHOOK="$BIN/mb-semantic-recall.sh"
  PY_REAL="$(command -v python3)"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session" "$MB/notes"

  # Ten indexed-style entries; one superseded. Distinct stems so ids are stable.
  printf '## session\n- "auth tokens rotate hourly" — kamal proxy host\n' \
    > "$MB/session/2026-06-01_1000_aaaa.md"
  printf '# auth token storage\nstore auth tokens in the keyring, not plaintext\n' \
    > "$MB/notes/2026-06-02_token-store.md"
  printf '# legacy auth tokens [SUPERSEDED: 2026-06-05 -> notes/token-store.md#auth]\nold auth tokens lived in env vars\n' \
    > "$MB/notes/2026-05-01_old-tokens.md"
  i=3
  while [ "$i" -le 9 ]; do
    printf '# note %s\nauth tokens topic filler line %s\n' "$i" "$i" \
      > "$MB/notes/2026-06-0${i}_filler${i}.md"
    i=$((i + 1))
  done
}
teardown() { rm -rf "$TMP"; }

# Build a PATH stub directory whose `python3` returns the given semantic JSON for a
# `search` subcommand and otherwise delegates to the real interpreter (so the
# recall-index bridge still works). Echoes the stub dir.
_make_semantic_stub() {
  local json="$1" stub="$TMP/stub"
  mkdir -p "$stub"
  cat > "$stub/python3" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "search" ]; then
    printf '%s\n' '$json'
    exit 0
  fi
done
exec "$PY_REAL" "\$@"
EOF
  chmod +x "$stub/python3"
  printf '%s' "$stub"
}

# -- Scenario 6 ------------------------------------------------------------------

@test "scenario 6: recall default = compact index, one line per hit with id+age+summary (REQ-016, REQ-019)" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' auth tokens"
  [ "$status" -eq 0 ]
  # Every emitted hit line carries the ' · ' field separator (id · age · summary · source).
  echo "$output" | grep -q ' · '
  # Age token like 1d / 12h / 3w / 2mo present.
  echo "$output" | grep -Eq '[0-9]+(s|m|h|d|w|mo|y)\b'
}

@test "scenario 6: compact output is one line per entry, NO full multi-line bodies (REQ-016)" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' auth tokens"
  [ "$status" -eq 0 ]
  # The token-store note has a heading line AND a body line; in compact mode only a
  # single summary line per entry is emitted — both lines must never appear together
  # (that would mean the full chunk body was dumped).
  heading="$(echo "$output" | grep -c 'auth token storage' || true)"
  body="$(echo "$output" | grep -c 'store auth tokens in the keyring' || true)"
  [ "$((heading + body))" -le 1 ]
  # Every emitted hit is exactly one compact line carrying the field separator.
  hit_count="$(echo "$output" | grep -c ' · ' || true)"
  line_count="$(echo "$output" | grep -c '.' || true)"
  [ "$hit_count" -eq "$line_count" ]
}

@test "scenario 6: superseded hit ranks below all clean hits and carries the label (REQ-019)" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' auth tokens"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'superseded'
  # Line number of the superseded marker must be greater than every clean hit line.
  sup_line="$(echo "$output" | grep -n 'superseded' | head -1 | cut -d: -f1)"
  clean_max="$(echo "$output" | grep -n ' · ' | grep -v 'superseded' | tail -1 | cut -d: -f1)"
  [ -n "$sup_line" ] && [ -n "$clean_max" ]
  [ "$sup_line" -gt "$clean_max" ]
}

# -- token budget ---------------------------------------------------------------

@test "token budget: each compact line is < 200 chars" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' auth tokens"
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [ "${#line}" -lt 200 ]
  done < <(echo "$output" | grep ' · ')
}

@test "token budget: a long multibyte summary is trimmed to < 200 CHARACTERS" {
  # A note whose body line is far longer than the budget, with multibyte text so
  # byte-length != char-length (regression: the guard must count characters).
  long="$(printf 'аутентификация токенов очень длинная строка %.0s' {1..30})"
  printf '# long unicode note\n%s\n' "$long" \
    > "$MB/notes/2026-06-09_longunicode.md"
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' аутентификация"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'longunicode'
  # Assert character length (not bytes) of every compact line is strictly < 200.
  echo "$output" | grep ' · ' | python3 -c '
import sys
for line in sys.stdin:
    assert len(line.rstrip("\n")) < 200, "compact line >= 200 chars"
'
}

@test "token budget: a pathologically long SOURCE path still yields a line < 200 chars (blocker 5)" {
  # A note nested under a very long directory path: the final assembled compact line
  # (id · age · summary · source) must stay < 200 chars even when the source alone is huge.
  # Many short nested segments → a source PATH whose relative length ALONE exceeds the
  # 200-char budget, so trimming the summary to "…" cannot save the line: the guard
  # MUST also truncate the displayed source. (No single segment over the 255-byte FS limit.)
  deep="$MB/notes"
  for _ in $(seq 1 60); do deep="$deep/segm"; done
  mkdir -p "$deep"
  printf '# deep note\nauth tokens deep path entry\n' > "$deep/2026-06-09_deep.md"
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' 'auth tokens deep path'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'deep'
  # Every compact line — including the pathological one — is strictly < 200 chars.
  echo "$output" | grep ' · ' | python3 -c '
import sys
for line in sys.stdin:
    assert len(line.rstrip("\n")) < 200, "compact line >= 200 chars: %r" % line
'
}

# -- --expand happy path (REQ-017) ----------------------------------------------

@test "--expand <id>: prints the full chunk body and source path (REQ-017)" {
  # Discover a real id from the compact listing first.
  list="$(CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=off bash "$HOOK" auth tokens)"
  id="$(echo "$list" | grep '2026-06-02_token-store' | head -1 | sed -E 's/^[[:space:]]*([^ ]+) · .*/\1/')"
  [ -n "$id" ]
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' --expand '$id' auth tokens"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'store auth tokens in the keyring, not plaintext'
  echo "$output" | grep -q 'token-store.md'
}

# -- per-chunk dedup (blocker 1): two semantic chunks from one file ---------------

@test "per-chunk: two semantic chunks from one file → two rows, both --expand ids work (REQ-017)" {
  # One source file, TWO distinct semantic chunks (different anchors). The compact
  # index must keep BOTH as separate rows and BOTH ids must --expand to their own body.
  stub="$(_make_semantic_stub '[{"score":0.92,"source":"notes/2026-06-02_token-store.md","kind":"note","text":"chunk alpha about auth tokens","anchor":"p0"},{"score":0.90,"source":"notes/2026-06-02_token-store.md","kind":"note","text":"chunk beta about auth tokens rotation","anchor":"p1"}]')"
  list="$(env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" auth tokens)"
  # Two distinct compact rows, one per chunk anchor: a human-readable 'token-store' slug
  # PLUS a short stable hash, ending in the chunk anchor (:p0 / :p1).
  echo "$list" | grep -Eq 'token-store-[0-9a-f]+:p0 · '
  echo "$list" | grep -Eq 'token-store-[0-9a-f]+:p1 · '
  # Derive the FULL ids from the listing (stem carries the date prefix).
  id0="$(echo "$list" | grep ':p0 · ' | head -1 | sed -E 's/^[[:space:]]*([^ ]+) · .*/\1/')"
  id1="$(echo "$list" | grep ':p1 · ' | head -1 | sed -E 's/^[[:space:]]*([^ ]+) · .*/\1/')"
  [ -n "$id0" ] && [ -n "$id1" ] && [ "$id0" != "$id1" ]
  # Each chunk id expands to ITS OWN body (no collapse / overwrite).
  run env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" --expand "$id0" auth tokens
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'chunk alpha about auth tokens'
  run env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" --expand "$id1" auth tokens
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'chunk beta about auth tokens rotation'
}

# -- id uniqueness across sources (round-2 blocker 1): same stem+anchor, two files -

@test "id uniqueness: notes/foo.md + session/foo.md sharing anchor p0 → distinct rows, each --expand returns its own body (REQ-017)" {
  # Two DIFFERENT source files share the SAME basename stem 'foo' AND the SAME anchor 'p0'.
  # The old id scheme (stem:anchor) produced 'foo:p0' for BOTH → one collapsed row and
  # --expand returning only the first body. Ids must be unique per (full source, anchor).
  printf '# foo note\nNOTEBODYALPHA about auth tokens in notes\n' > "$MB/notes/foo.md"
  printf '# foo session\nSESSIONBODYBETA about auth tokens in session\n' > "$MB/session/foo.md"
  stub="$(_make_semantic_stub '[{"score":0.92,"source":"notes/foo.md","kind":"note","text":"NOTEBODYALPHA about auth tokens in notes","anchor":"p0"},{"score":0.90,"source":"session/foo.md","kind":"session","text":"SESSIONBODYBETA about auth tokens in session","anchor":"p0"}]')"
  list="$(env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" auth tokens)"
  # Exactly TWO compact rows whose id ends in ':p0' (one per source), and they are DISTINCT.
  ids="$(echo "$list" | grep ':p0 · ' | sed -E 's/^[[:space:]]*([^ ]+) · .*/\1/')"
  count="$(echo "$ids" | grep -c ':p0' || true)"
  [ "$count" -eq 2 ]
  id_notes="$(echo "$ids" | sed -n '1p')"
  id_sess="$(echo "$ids" | sed -n '2p')"
  [ -n "$id_notes" ] && [ -n "$id_sess" ] && [ "$id_notes" != "$id_sess" ]
  # Each id --expands to ITS OWN body and source (no collapse onto the first).
  run env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" --expand "$id_notes" auth tokens
  [ "$status" -eq 0 ]
  body_notes="$output"
  run env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" --expand "$id_sess" auth tokens
  [ "$status" -eq 0 ]
  body_sess="$output"
  # Whichever id maps to which source, the two expansions must be DIFFERENT and each must
  # carry exactly one of the two distinct body markers (not both, not the same one twice).
  [ "$body_notes" != "$body_sess" ]
  echo "$body_notes$body_sess" | grep -q 'NOTEBODYALPHA'
  echo "$body_notes$body_sess" | grep -q 'SESSIONBODYBETA'
}

# -- id + line length under pathological stem AND anchor (round-2 blocker 2) -------

@test "id bound: pathologically long basename AND long anchor → line < 200 chars, id still expandable (REQ-016, REQ-017)" {
  # A note whose basename stem is enormous, combined with a very long semantic anchor.
  # The old scheme embedded the full stem + full anchor into the id, so the compact line
  # could exceed 200 chars even after trimming summary/source. The generated id must be
  # bounded (slug capped, stable hash kept) AND the line must stay < 200 — while --expand
  # of that id still resolves.
  longstem="$(printf 'x%.0s' {1..160})"
  longanchor="$(printf 'p%.0s' {1..120})"
  printf '# big\nLONGIDBODY auth tokens pathological id entry\n' > "$MB/notes/${longstem}.md"
  stub="$(_make_semantic_stub '[{"score":0.93,"source":"notes/'"$longstem"'.md","kind":"note","text":"LONGIDBODY auth tokens pathological id entry","anchor":"'"$longanchor"'"}]')"
  list="$(env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" auth tokens)"
  # EVERY compact line — including the pathological one — is strictly < 200 CHARACTERS.
  echo "$list" | grep ' · ' | python3 -c '
import sys
for line in sys.stdin:
    assert len(line.rstrip("\n")) < 200, "compact line >= 200 chars: %r" % line
'
  # Recover the bounded id of the PATHOLOGICAL row (its slug starts with the long 'x'
  # stem) — the fixture notes from setup() also match, so we must NOT just take head -1.
  # With the huge source path its summary collapses to '…', so we read the id field
  # directly, not the summary text — the id must still round-trip through --expand below.
  id="$(echo "$list" | grep -E '^[[:space:]]*xxxx[0-9a-z-]*:p+ · ' | head -1 | sed -E 's/^[[:space:]]*([^ ]+) · .*/\1/')"
  [ -n "$id" ]
  # The id itself must be bounded (well under the line budget) — not the full 160+120 stem.
  [ "${#id}" -lt 80 ]
  run env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" --expand "$id" auth tokens
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'LONGIDBODY auth tokens pathological id entry'
}

# -- superseded marker shape (blocker 2): real marker only, not a mention ---------

@test "superseded: a chunk MENTIONING the marker syntax is NOT labeled (blocker 2)" {
  # A live note whose body merely DISCUSSES the '[SUPERSEDED' syntax (no real marker)
  # must NOT be tagged ⊘ nor sorted last.
  printf '# how to supersede a fact\nappend the new fact then write a [SUPERSEDED ...] marker on the old one\n' \
    > "$MB/notes/2026-06-08_supersede-howto.md"
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' supersede"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'supersede-howto'
  # The howto row must NOT carry the superseded label.
  howto_line="$(echo "$output" | grep 'supersede-howto')"
  [[ "$howto_line" != *"superseded"* ]]
}

@test "superseded: a real [SUPERSEDED: date -> ref] marker IS labeled and sorts last (REQ-019)" {
  # The fixture old-tokens note carries a real marker; it must be labeled and last.
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' auth tokens"
  [ "$status" -eq 0 ]
  sup_line="$(echo "$output" | grep 'old-tokens')"
  [[ "$sup_line" == *"superseded"* ]]
}

# -- Scenario 7: unknown --expand id (REQ-018) ----------------------------------

@test "scenario 7: --expand of an unknown id exits non-zero and names the id on stderr (REQ-018)" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' --expand zz99 auth tokens 2>&1"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'zz99'
}

# -- --full legacy escape hatch -------------------------------------------------

@test "--full: keeps legacy full output (bodies present)" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' --full auth tokens"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'store auth tokens in the keyring, not plaintext'
}

# -- fusion (REQ-001 in the recall path) ----------------------------------------

@test "fusion: semantic + lexical hits are fused (semantic-only hit appears in compact index)" {
  stub="$(_make_semantic_stub '[{"score":0.91,"source":"session/2026-06-01_1000_aaaa.md","kind":"session","text":"auth tokens rotate hourly via kamal proxy","anchor":"p0"}]')"
  run env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" auth tokens
  [ "$status" -eq 0 ]
  # The semantic-only session hit must surface in the fused compact index.
  echo "$output" | grep -q '2026-06-01_1000_aaaa'
  echo "$output" | grep -q ' · '
}

@test "fail-open: no semantic backend → lexical-only compact index, exit 0 (REQ-002)" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' MB_SEMANTIC=off bash '$HOOK' auth tokens"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '2026-06-02_token-store'
}

# -- injection hook emits the compact form (REQ-016 token saving) ---------------

@test "injection: mb-semantic-recall.sh emits the COMPACT form, not full chunk bodies" {
  long='auth tokens rotate hourly via kamal proxy host with a very long body that should be summarised down to a single short line and never injected verbatim into the prompt context window at all'
  stub="$(_make_semantic_stub '[{"score":0.93,"source":"session/2026-06-01_1000_aaaa.md","kind":"session","text":"'"$long"'","anchor":"p0"}]')"
  run env PATH="$stub:$PATH" MB_SEMANTIC=auto bash "$SEMHOOK" <<< '{"prompt":"auth tokens","cwd":"'"$PROJ"'"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Relevant Memory"* ]]
  # Compact: the id + ' · ' separator present; the full long body absent.
  [[ "$output" == *" · "* ]]
  [[ "$output" != *"summarised down to a single short line"* ]]
}

# -- id collision resolution: same capped slug + anchor, distinct sources ---------

@test "id-collision: two sources colliding on slug+hash6 → distinct ids, both expandable (REQ-017)" {
  # Adversarial pair (reproduced in review): both stems share the same 24-char capped
  # slug AND collide on the 6-hex sha1 prefix for anchor p0. Ids must still be unique
  # within the hit set — the hash field lengthens until every id differs.
  stub="$(_make_semantic_stub '[{"score":0.92,"source":"notes/xxxxxxxxxxxxxxxxxxxxxxxx1309.md","kind":"note","text":"COLLIDERBODYONE auth tokens","anchor":"p0"},{"score":0.90,"source":"notes/xxxxxxxxxxxxxxxxxxxxxxxx6756.md","kind":"note","text":"COLLIDERBODYTWO auth tokens","anchor":"p0"}]')"
  list="$(env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" auth tokens)"
  # Isolate the two collider rows by their shared 24-char slug — the fixture's lexical
  # channel also matches "auth tokens" and adds unrelated rows we must not count here.
  ids="$(echo "$list" | grep ' · ' | sed -E 's/^[[:space:]]*([^ ]+) · .*/\1/' | grep '^xxxxxxxxxxxxxxxxxxxxxxxx-' | sort)"
  [ "$(echo "$ids" | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(echo "$ids" | sort -u | wc -l | tr -d ' ')" -eq 2 ]
  id_a="$(echo "$ids" | sed -n 1p)"; id_b="$(echo "$ids" | sed -n 2p)"
  run env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" --expand "$id_a" auth tokens
  [ "$status" -eq 0 ]
  body_a="$output"
  run env PATH="$stub:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" --expand "$id_b" auth tokens
  [ "$status" -eq 0 ]
  body_b="$output"
  # Each id expands to ITS OWN body — together they cover both collider bodies.
  printf '%s\n%s\n' "$body_a" "$body_b" | grep -q 'COLLIDERBODYONE'
  printf '%s\n%s\n' "$body_a" "$body_b" | grep -q 'COLLIDERBODYTWO'
  [ "$body_a" != "$body_b" ]
}
