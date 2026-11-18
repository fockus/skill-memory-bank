# Requirements: gadgets

> Imported from OpenSpec change `gadgets` — see design.md for Why/What Changes.
> Deterministic skeleton (T2) — REQ-IDs assigned in document order; `--normalize` (T6) fills text slots.

## Requirements (EARS)

### Requirement 1: Gadget Store 1

<!-- openspec: cap=gadgets; kind=added -->
<!-- openspec-req: Gadget Store 1 -->
- **REQ-001** (ubiquitous): The system SHALL store gadgets.

<!-- mb-scenario:1 -->
### Scenario: Store and find
**Covers:** REQ-001

- GIVEN an empty store
- WHEN a gadget is stored
- THEN a search by its name finds it
<!-- /mb-scenario:1 -->

### Requirement 2: Gadget Store 2

<!-- openspec: cap=gadgets; kind=added -->
<!-- openspec-req: Gadget Store 2 -->
- **REQ-002** (event-driven): When a gadget is deleted, the system SHALL archive it.

<!-- mb-scenario:2 -->
### Scenario: (none provided)
**Covers:** REQ-002

- WHEN not specified
- THEN not specified
<!-- /mb-scenario:2 -->

### Requirement 3: Gadget Search

<!-- openspec: cap=gadgets; kind=added -->
<!-- openspec-req: Gadget Search -->
- **REQ-003** (ubiquitous): The system SHALL search gadgets by name.

<!-- mb-scenario:3 -->
### Scenario: Store and find
**Covers:** REQ-003

- GIVEN an empty store
- WHEN a gadget is stored
- THEN a search by its name finds it
<!-- /mb-scenario:3 -->
