# /mb tags — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `tags [--apply] [--auto-merge]` — Normalize frontmatter tags: detect synonyms via Levenshtein ≤2 against a closed vocabulary and propose merges. `--auto-merge` only applies distance ≤1. Vocabulary is in `.memory-bank/tags-vocabulary.md` (fallback: `references/tags-vocabulary.md`). `mb-index-json.py` auto-normalizes to kebab-case
