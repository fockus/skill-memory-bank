## Why

Change metadata is currently untracked, making it impossible to detect drift
between OpenSpec changes and their Memory Bank imports.

## What Changes

- Add a `.openspec.yaml` metadata file to every new change.
- Track the change status (draft, active, archived) inside that file.
