# Requirements: add-metadata-tracking

> Imported from OpenSpec change `add-metadata-tracking` — see design.md for Why/What Changes.
> Deterministic skeleton (T2) — REQ-IDs assigned in document order; `--normalize` (T6) fills text slots.

## Requirements (EARS)

### Requirement 1: Change Metadata

<!-- openspec-req: Change Metadata -->
- **REQ-001** (ubiquitous): The system SHALL store and validate per-change metadata in `.openspec.yaml` files.

<!-- mb-scenario:1 -->
### Scenario: Metadata file created with new change
**Covers:** REQ-001

- WHEN user runs `openspec new change add-feature`
- THEN the system creates `.openspec.yaml` in the change directory
<!-- /mb-scenario:1 -->

### Requirement 2: Metadata Schema Version

<!-- openspec-req: Metadata Schema Version -->
- **REQ-002** (ubiquitous): The system SHALL record a schema version field inside every `.openspec.yaml` file.

<!-- mb-scenario:2 -->
### Scenario: (none provided)
**Covers:** REQ-002

- WHEN not specified
- THEN not specified
<!-- /mb-scenario:2 -->

### Requirement 3: Change Status Field

<!-- openspec-req: Change Status Field -->
- **REQ-003** (ubiquitous): The system SHALL persist the change status as one of draft, active, or archived, replacing the previous free-text status field.

<!-- mb-scenario:3 -->
### Scenario: Status transitions on archive
**Covers:** REQ-003

- WHEN a change is archived via `openspec archive`
- THEN the system SHALL set its status field to archived
<!-- /mb-scenario:3 -->
