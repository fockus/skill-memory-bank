## Context

Changes previously had no structured metadata; drift detection relied on
manual inspection of `tasks.md` checkboxes.

## Decisions

Store metadata as YAML rather than JSON for human readability.

## Risks

- Existing changes without `.openspec.yaml` need a one-time backfill.
