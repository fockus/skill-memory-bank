---
description: Manage API contracts — OpenAPI, gRPC, GraphQL, breaking-change detection
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
argument-hint: <generate|check|test>
---

# API Contract: $ARGUMENTS

## 0. Validate arguments

If `$ARGUMENTS` is empty, stop and ask the user which action to perform (`generate`, `check`, `test`).

## 1. Stack detection

```bash
eval "$(bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh)"
```

If `stack=unknown`, ask the user for the framework / language in use.

## 2. Detect the API type

```bash
# OpenAPI / Swagger
find . -name "*.yaml" -o -name "*.yml" 2>/dev/null | xargs grep -l "openapi\|swagger" 2>/dev/null
find . -name "openapi*" -o -name "swagger*" 2>/dev/null

# gRPC / Protobuf
find . -name "*.proto" 2>/dev/null

# GraphQL
find . -name "*.graphql" -o -name "*.gql" 2>/dev/null

# Handler detection across frameworks:
# Go  (gin / echo / chi / net/http)
grep -rn "func.*Handler\|func.*http\.\|r\.GET\|r\.POST\|e\.GET\|e\.POST\|http\.HandleFunc" --include="*.go" . | head -30

# Node.js — Express / Fastify / Nest
grep -rn "app\.\(get\|post\|put\|delete\|patch\)\|router\.\(get\|post\)\|@Get\|@Post" --include="*.ts" --include="*.js" . | head -30

# Python — FastAPI / Flask / Django
grep -rn "@app\.\(get\|post\|put\|delete\)\|@router\.\(get\|post\)\|@app\.route\|path(" --include="*.py" . | head -30

# Java / Kotlin — Spring
grep -rn "@GetMapping\|@PostMapping\|@PutMapping\|@DeleteMapping\|@RequestMapping" --include="*.java" --include="*.kt" . | head -30

# .NET
grep -rn "\[HttpGet\]\|\[HttpPost\]\|\[HttpPut\]\|\[HttpDelete\]\|MapGet\|MapPost" --include="*.cs" . | head -30

# Rust — Axum / Actix / Rocket
grep -rn "\.route(\|#\[get\|#\[post\|#\[put\|#\[delete" --include="*.rs" . | head -30

# Ruby — Rails
grep -rn "resources \|get \|post \|put \|delete " --include="routes.rb" . | head -30
```

## 3. Action

### `generate` — specification generation

- Study all detected endpoints / handlers / routes
- Generate an OpenAPI 3.1 (or 3.0) specification — paths, schemas, request / response bodies, error codes, auth
- For gRPC, emit / update `.proto` files
- For GraphQL, emit / update the schema SDL

### `check` — breaking-change detection

Compare the current specification with the last committed version. Breaking changes:

- Removed endpoints
- Changed field types
- New required fields without defaults
- Removed response fields
- Changed HTTP methods / status codes
- GraphQL: removed fields, narrowed types

Tools:

```bash
# OpenAPI diff
npx @stoplight/spectral-cli lint openapi.yaml 2>/dev/null
npx openapi-diff old.yaml new.yaml 2>/dev/null

# Protobuf
buf breaking --against '.git#branch=main' 2>/dev/null

# GraphQL
npx graphql-inspector diff old.graphql new.graphql 2>/dev/null
```

### `test` — contract tests

Generate tests from the spec and verify conformance + error responses + edge cases. Recommended runners:

- **Python**: [Schemathesis](https://schemathesis.readthedocs.io/) — property-based, OpenAPI-driven
- **Any stack**: [Pact](https://pact.io/) — consumer-driven contract tests, multi-language brokers
- **Go**: native `httptest` + Schemathesis CLI
- **gRPC**: `buf curl` + generated client stubs

```bash
# Schemathesis example:
schemathesis run --checks all openapi.yaml --base-url http://localhost:8080
```

## 4. Validation

```bash
npx @stoplight/spectral-cli lint openapi.yaml 2>/dev/null  # OpenAPI
buf lint 2>/dev/null                                       # Protobuf
npx graphql-schema-linter *.graphql 2>/dev/null            # GraphQL
```

## 5. Output

Save or update the specification in `./docs/api/` or `./api/` (respect existing conventions). If `./.memory-bank/` exists, add a note (`mb-note.sh "api-contract-<action>"`).
