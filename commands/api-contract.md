---
description: Manage API contracts — OpenAPI, gRPC, breaking-change detection
allowed-tools: [Read, Glob, Grep, Bash, Write]
---

# API Contract: $ARGUMENTS

## 1. Detect the API type

```bash
# OpenAPI / Swagger
find . -name "*.yaml" -o -name "*.yml" | xargs grep -l "openapi\|swagger" 2>/dev/null
find . -name "openapi*" -o -name "swagger*" 2>/dev/null

# gRPC / Protobuf
find . -name "*.proto" 2>/dev/null

# GraphQL
find . -name "*.graphql" -o -name "*.gql" 2>/dev/null

# Go handlers
grep -rn "func.*Handler\|func.*http\.\|r\.GET\|r\.POST\|r\.PUT\|r\.DELETE" --include="*.go" . | head -30
```

## 2. Action

Depending on `$ARGUMENTS`:

### `generate` — specification generation
- Study all endpoints / handlers / routes
- Generate an OpenAPI 3.0 specification
- Include: paths, schemas, request/response bodies, error codes, auth

### `check` — breaking change detection
- Compare the current specification with the latest committed one
- Breaking changes:
  - Removed endpoints
  - Changed field types
  - New required fields (without defaults)
  - Removed response fields
  - Changed HTTP methods / status codes

### `test` — contract tests
- Generate tests from the specification
- Verify that the API conforms to the contract
- Verify error responses and edge cases

## 3. Validation

```bash
# OpenAPI lint (if installed)
npx @stoplight/spectral-cli lint openapi.yaml 2>/dev/null

# Protobuf lint
buf lint 2>/dev/null

# Contract tests
go test ./api/... -run TestContract 2>/dev/null
```

## 4. Result

Save or update the specification in `./docs/api/` or `./api/`.
If `./.memory-bank/` exists, add a note in `notes/`.
