## ADDED Requirements

### Requirement: Change Metadata
The system SHALL store and validate per-change metadata in `.openspec.yaml` files.

#### Scenario: Metadata file created with new change
- **WHEN** user runs `openspec new change add-feature`
- **THEN** the system creates `.openspec.yaml` in the change directory

### Requirement: Metadata Schema Version
The system SHALL record a schema version field inside every `.openspec.yaml` file.

## MODIFIED Requirements

### Requirement: Change Status Field
The system SHALL persist the change status as one of draft, active, or archived, replacing the previous free-text status field.

#### Scenario: Status transitions on archive
- **WHEN** a change is archived via `openspec archive`
- **THEN** the system SHALL set its status field to archived

## REMOVED Requirements

### Requirement: Legacy Status Comment
**Reason**: Superseded by the structured status field; free-text comments were never validated and drifted from reality.

## RENAMED Requirements
- FROM: `### Requirement: Change Owner`
- TO: `### Requirement: Change Author`
