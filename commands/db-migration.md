---
description: Create and manage DB migrations (golang-migrate, Alembic, Prisma)
allowed-tools: [Read, Glob, Grep, Bash, Write]
---

# Database Migration: $ARGUMENTS

## 1. Detect the tooling

```bash
# golang-migrate
ls migrations/ db/migrations/ 2>/dev/null
grep -r "golang-migrate\|goose\|atlas" go.mod 2>/dev/null

# Alembic (Python)
ls alembic/ 2>/dev/null; cat alembic.ini 2>/dev/null

# Prisma (Node.js)
cat prisma/schema.prisma 2>/dev/null

# SQL files
find . -name "*.sql" -path "*/migrat*" 2>/dev/null | head -20
```

## 2. Create the migration

### File naming format
`YYYYMMDDHHMMSS_<description>.up.sql` / `.down.sql`

### Requirements
- Every migration must have both `up` and `down`
- `down` must fully roll back `up`
- Destructive operations (`DROP TABLE`, `DROP COLUMN`) require confirmation
- Data migrations must be separated from schema migrations
- Create indexes `CONCURRENTLY` when supported

### Analysis
1. Read the existing migrations and understand the current schema
2. Determine what must change (`$ARGUMENTS`)
3. Check for conflicts with recent migrations
4. Show the change plan and ask for confirmation

## 3. Generation

Generate both `up` and `down` migrations. Verify:
- Idempotency: `IF NOT EXISTS`, `IF EXISTS`
- Backward compatibility: old code still works with the new schema
- Rollback safety: `down` does not lose data without warning

## 4. Testing

```bash
# Apply up
migrate -path migrations -database "$DATABASE_URL" up

# Verify the schema
# Apply down
migrate -path migrations -database "$DATABASE_URL" down 1

# Apply up again (idempotency)
migrate -path migrations -database "$DATABASE_URL" up
```

## 5. Memory Bank

If `./.memory-bank/` exists, add a note in `notes/` describing the schema changes.
