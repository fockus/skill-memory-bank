---
type: project
name: <project-name>
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

<!--
Slow-changing, non-negotiable project facts read at flow start (REQ-DF-002).
This is the stable backdrop a Dynamic Flow loads BEFORE picking a route — the
constraints that must hold regardless of which goal is active. Keep it small
(~30-80 lines); fast-moving status lives in status.md, code structure in
codebase/, decisions in backlog.md / ADRs. Do NOT duplicate those here —
reference them.
-->

## Mission

<1-2 sentences: what this project is for.>

## Domain

<one line: the problem space.>

## Stack

See codebase/STACK.md.
- <any stack fact the codebase scan would not surface (internal forks, pinned
  versions for compliance) — otherwise leave the reference above only>

## Non-negotiable constraints

- <hard constraint the flow must never violate, e.g. "must run offline",
  "all I/O through the repository layer", "no new third-party runtime deps">

## Team coding conventions

See codebase/CONVENTIONS.md.
- <any team-specific rule not yet captured in CONVENTIONS.md>

## Architecture notes

- <key architectural decision not yet recorded as an ADR>

## Out of scope

- <what this project explicitly does NOT do>
