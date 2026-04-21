# Default tags vocabulary

Controlled vocabulary for frontmatter `tags` in `notes/*.md`. Used by `mb-tags-normalize.sh` to detect unknown tags and merge synonyms.

The user may copy this file into `.memory-bank/tags-vocabulary.md` and customize it for the project (add domain-specific tags, remove unused ones).

## Conventions

- Kebab-case only: `refactor`, `db-migration`, `perf-critical`
- Lowercase, no spaces
- Prefer singular nouns where applicable: `bug`, not `bugs`
- Keep tags short: `api`, not `api-endpoint`

## Core tags

- arch          # architectural decision / pattern
- auth          # authentication / authorization
- bug           # bug or bug fix
- ci            # continuous integration
- doc           # documentation
- db            # database
- deploy        # deployment / release
- experiment    # experiment / research
- feature       # new feature
- infra         # infrastructure
- lesson        # extracted lesson (mirrors lessons.md as a tag)
- migration     # migration (schema / framework / version)
- monitoring    # observability / alerts
- perf          # performance optimization
- pii           # privacy / personal data handling
- pattern       # reusable pattern
- refactor      # refactoring
- security      # security issue / hardening
- test          # tests (unit / integration / e2e)

## Process tags

- debug         # debugging session
- review        # code review findings
- post-mortem   # incident analysis
- adr           # architectural decision record
- spike         # exploratory spike

## Workflow tags

- blocked       # blocked by external dependency
- todo          # requires action
- wip           # work in progress
- imported      # imported from JSONL (auto-tag)
- discussion    # architectural discussion (auto-tag)
