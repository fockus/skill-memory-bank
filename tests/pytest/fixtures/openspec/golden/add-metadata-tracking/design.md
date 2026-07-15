# Design: add-metadata-tracking

## Why

Change metadata is currently untracked, making it impossible to detect drift
between OpenSpec changes and their Memory Bank imports.

## What Changes

- Add a `.openspec.yaml` metadata file to every new change.
- Track the change status (draft, active, archived) inside that file.

## OpenSpec Design Notes

### Context

Changes previously had no structured metadata; drift detection relied on
manual inspection of `tasks.md` checkboxes.

### Decisions

Store metadata as YAML rather than JSON for human readability.

### Risks

- Existing changes without `.openspec.yaml` need a one-time backfill.

## Removed scope

### Legacy Status Comment

**Reason:** Superseded by the structured status field; free-text comments were never validated and drifted from reality.

## Deferred renames (re-import required)

- `Change Owner` -> `Change Author` — anchor move handled on re-import (T5).
