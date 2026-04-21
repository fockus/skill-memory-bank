---
description: Create and manage DB migrations across 8+ tools
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
argument-hint: <migration-description>
---

# Database Migration: $ARGUMENTS

## 0. Validate arguments

If `$ARGUMENTS` is empty, stop and ask the user what the migration should change.

## 1. Stack detection

```bash
eval "$(bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh)"
# Uses: stack to narrow the tooling search
```

## 2. Detect the migration tool

```bash
# golang-migrate / goose / Atlas (Go)
ls migrations/ db/migrations/ 2>/dev/null
grep -r "golang-migrate\|pressly/goose\|ariga/atlas" go.mod 2>/dev/null

# Alembic (Python)
ls alembic/ 2>/dev/null; cat alembic.ini 2>/dev/null

# Prisma (Node.js)
ls prisma/schema.prisma 2>/dev/null

# Sequelize / Knex (Node.js)
ls sequelize/ migrations/ knexfile.js knexfile.ts 2>/dev/null
grep -l "sequelize\|knex" package.json 2>/dev/null

# Diesel (Rust)
ls diesel.toml 2>/dev/null
grep -l "diesel" Cargo.toml 2>/dev/null

# SQLx (Rust)
ls migrations/ 2>/dev/null
grep -l "sqlx" Cargo.toml 2>/dev/null

# Flyway (Java/JVM)
ls flyway.conf db/migration/ src/main/resources/db/migration/ 2>/dev/null

# Liquibase (Java/JVM)
ls liquibase.properties changelog*.xml db/changelog/ 2>/dev/null

# Entity Framework Core (.NET)
ls Migrations/ 2>/dev/null
grep -l "EntityFrameworkCore" *.csproj 2>/dev/null

# Plain SQL files
find . -name "*.sql" -path "*/migrat*" 2>/dev/null | head -20
```

If none of the above matches, ask the user which migration tool the project uses before writing anything.

## 3. Universal requirements

Every migration must follow these rules, regardless of tool:

- Both `up` and `down` (or equivalent `forward` / `rollback`). `down` must fully reverse `up`.
- Destructive operations (`DROP TABLE`, `DROP COLUMN`, `TRUNCATE`, `DELETE FROM` without `WHERE`) **require explicit `y/N` confirmation before the file is written** — not just before it is applied. Default = No.
- Schema migrations and data migrations must be in separate files.
- Index creation uses `CONCURRENTLY` on PostgreSQL when the tool supports it (golang-migrate `-disable-create-hash-comments`, Alembic with `op.create_index(..., postgresql_concurrently=True)`, etc.).
- Idempotent wrappers (`IF NOT EXISTS`, `IF EXISTS`) on DDL where the dialect supports them.
- Backward compatibility: the previous application version must still function against the new schema for the duration of a rolling deploy.

## 4. Analysis before writing

1. Read the N most recent migrations to understand the current schema and conventions (file naming, column styles, comment habits).
2. Determine exactly what `$ARGUMENTS` asks to change.
3. Check for conflicts with pending / unmerged migrations.
4. Show the change plan to the user and ask for confirmation before writing files.

## 5. Generation

Use the conventional filename format for the detected tool (for example `YYYYMMDDHHMMSS_<description>.up.sql` + `.down.sql` for golang-migrate; `<revision>_<slug>.py` for Alembic; auto-named for Prisma). Generate both directions; verify mentally that `down` restores the pre-`up` state.

## 6. Testing

Before applying to any real database, run the tool-native dry-run or preview (for example `atlas migrate lint`, `alembic upgrade --sql head`, `prisma migrate diff`). Then exercise the full round-trip on a disposable database / container:

```bash
# Example for golang-migrate:
migrate -path migrations -database "$DATABASE_URL" up
migrate -path migrations -database "$DATABASE_URL" down 1
migrate -path migrations -database "$DATABASE_URL" up
```

Confirm `up → down → up` leaves the schema identical.

## 7. Memory Bank

If `./.memory-bank/` exists, add a note (`bash ~/.claude/skills/memory-bank/scripts/mb-note.sh "migration-<slug>"`) describing the schema change, why it was needed, and any rollback gotchas.
