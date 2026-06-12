# Memory Bank — metadata protocol

Detailed description of YAML frontmatter for `notes/` and the `index.json` structure.

---

## Frontmatter format

All notes in `notes/` are created with YAML frontmatter for semantic search and targeted recall.

```yaml
---
type: lesson | note | decision | pattern
tags: []
related_features: []
sprint: null
importance: high | medium | low
created: YYYY-MM-DD
---
```

### Rules

1. **All new `notes/` files** receive YAML frontmatter on creation (generated automatically by MB Manager).
2. **Tags** are extracted by the LLM from note content: 3-7 key technical terms, lowercase, singular.
3. **Importance**:
  - `high` — patterns, decisions, critical architectural insights
  - `medium` — general notes, knowledge
  - `low` — minor observations, one-off fixes
4. **Template**: `references/templates.md`.
5. **Old notes** (without frontmatter) still work — `index.json` treats them with defaults: `type: note`, `tags: []`.

---

## Index protocol

Memory Bank uses `index.json` for fast lookup without reading every file.

### Format: `{mb_path}/index.json`

```json
{
  "notes": [
    {
      "path": "notes/2026-03-29_14-30_topic.md",
      "type": "pattern",
      "tags": ["sqlite-vec", "embedding"],
      "importance": "high",
      "summary": "Local semantic search pattern via sqlite-vec",
      "has_private": false,
      "archived": false
    },
    {
      "path": "notes/archive/2025-11-10_old_experiment.md",
      "type": "note",
      "tags": ["cleanup"],
      "importance": "low",
      "summary": "Archived 2026-04-20 — compressed summary below",
      "has_private": false,
      "archived": true
    }
  ],
  "lessons": [
    {
      "id": "L-001",
      "title": "Avoid mocking more than 5 dependencies"
    }
  ],
  "generated_at": "2026-04-19T12:00:00Z"
}
```

`**archived: bool**` — `true` if the file lives under `notes/archive/` (moved there through `mb-compact.sh --apply`). Default `mb-search` excludes archived items; opt in through `mb-search --include-archived <query>`.

### Regeneration

- Rebuilt during `/mb done` (MB Manager `action: actualize` → calls `scripts/mb-index-json.py`)
- Also rebuilt automatically by `mb-search --tag <tag>` if missing
- Manually: `python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py <mb_path>`

### Usage

Agent reads `index.json` → filters by `tags` / `importance` → reads only relevant files.

### Fallback

- `PyYAML` not installed → `mb-index-json.py` uses a simple fallback parser (understands `key: value` and `key: [a, b]`)
- `index.json` missing → `mb-search` falls back to grep; `mb-search --tag` returns an error with a hint

---

## Key Memory Bank rules

1. **Core files = project truth.** `status.md`, `roadmap.md`, `checklist.md` must always stay current.
2. `**progress.md` = APPEND-ONLY.** Never delete or edit old entries.
3. **Monotonic numbering**: H-NNN (hypotheses), EXP-NNN (experiments), ADR-NNN (decisions), L-NNN (lessons).
4. `**notes/` = knowledge, not chronology.** 5-15 lines. Conclusions, patterns, reusable solutions.
5. **Checklist**: ✅ = done, ⬜ = not done. Update every session.
6. **Do not paste logs, stack traces, or large code blocks.** Only distilled notes.
7. **ML experiments**: hypothesis (SMART) → baseline → one change → run → result (p-value, Cohen's d).
8. **Architectural decisions** → ADR in `backlog.md` (context → decision → alternatives → consequences).
9. **Supersede convention**: when a fact is invalidated, append the new entry and
   mark the old one in place with `[SUPERSEDED: YYYY-MM-DD -> <ref>]` — never edit
   or delete the old fact's substance.

---

## Supersede convention

When a note, lesson, or progress/session entry is invalidated by a newer fact,
**do not edit or delete it in place** (the append-only / knowledge-trail invariant).
Instead:

1. **Append** the new fact to its proper home (`notes/`, `lessons.md`, etc.).
2. **Mark the old entry** by inserting a `[SUPERSEDED: YYYY-MM-DD -> <ref>]` tag on it.

```text
[SUPERSEDED: YYYY-MM-DD -> notes/<file>#<heading>]
```

- `YYYY-MM-DD` — the date the fact was superseded (a valid calendar date).
- `<ref>` — a pointer to the **superseding** entry: a path under the bank, optionally
  with a `#<heading>` anchor (e.g. `notes/2026-06-12_ledger.md#decision`).
- Scope: `notes/`, `lessons.md`, `progress.md`, `session/`.

**Validation.** `scripts/mb-drift.sh` (checker `supersedes`) scans the bank and warns on:

- **malformed** markers — a missing `-> <ref>` arrow or a date that is not a valid
  `YYYY-MM-DD` literal;
- **dangling** markers — a `<ref>` whose target file (anchor stripped) does not exist.

Valid markers and a bank with zero markers stay silent (no warning).

