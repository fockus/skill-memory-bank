---
description: Add structured logging, metrics, and tracing to a module
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
argument-hint: <module-path>
---

# Observability: $ARGUMENTS

## 0. Stack detection

```bash
eval "$(bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh)"
# Uses: stack to pick the right library set
```

If `stack=unknown`, ask the user which stack the target module uses.

## 1. Current state

```bash
# Logging
grep -rn "log\.\|logger\.\|logging\.\|fmt\.Print\|console\.log\|print(\|tracing::\|Serilog" \
  --include="*.go" --include="*.py" --include="*.ts" --include="*.js" \
  --include="*.rs" --include="*.java" --include="*.kt" --include="*.cs" . | head -30

# Metrics
grep -rn "prometheus\|metrics\|statsd\|datadog\|micrometer\|System\.Diagnostics\.Metrics" . | head -20

# Tracing
grep -rn "opentelemetry\|OpenTelemetry\|jaeger\|zipkin\|trace\.\|span\.\|tracing::" . | head -20
```

## 2. Structured logging (per stack)

### Go — `zerolog` / `slog` (stdlib)
- Replace `fmt.Println` / `log.Println` with a structured logger
- Fields: `timestamp`, `level`, `message`, `request_id`, `error`
- JSON format for production; console for dev

### Python — `structlog` or `logging` with `python-json-logger`
- Replace `print()` / `logging.info()` with structured logs
- JSON for production, colored output for local

### Node.js / TypeScript — `pino` (fast) or `winston`
- Use `pino-pretty` for local dev; JSON in production

### Rust — `tracing` crate + `tracing-subscriber`
- Replace `println!` / `eprintln!` with `tracing::info!` / `warn!` / `error!`
- `tracing-subscriber` with `fmt` layer for dev, `json` layer for prod

### Java / Kotlin — `SLF4J` + Logback / Log4j2 JSON encoder
- Use `MDC` for request-scoped context (`request_id`, `trace_id`)

### .NET — `Microsoft.Extensions.Logging` + Serilog
- `Serilog.Sinks.Console` + `Serilog.Formatting.Compact` for JSON

### Requirements across all stacks
- Logs must NOT contain PII or secrets
- Every log entry includes a correlation ID (`request_id` / `trace_id`)
- Error logs include a stack trace

## 3. Metrics (Prometheus / OpenTelemetry)

Expose:
- `http_requests_total` — counter labeled by `method`, `path`, `status`
- `http_request_duration_seconds` — histogram by `method`, `path`
- Business metrics: registrations, orders, payments (counters)
- Runtime metrics: per-stack (Go `promhttp`, Python `prometheus-client`, JVM `micrometer-registry-prometheus`, .NET `System.Diagnostics.Metrics`)

Requirements:
- **Bounded cardinality** — NEVER use `user_id` / `email` / full URL path as a label. Normalize `/users/123` → `/users/:id`.
- Middleware / interceptor approach — not inline in handlers.

## 4. Tracing (OpenTelemetry)

Spans at:
- HTTP handler (middleware)
- DB queries (via driver instrumentation if available)
- External API calls
- Key business operations

Requirements:
- Context propagation across the full stack (W3C Trace Context headers)
- Sampling in production (e.g., 1-10%, not 100%)
- `trace_id` in log lines for log-trace correlation

## 5. Verification

- No PII or secrets in sampled log output
- Metric cardinality is bounded (`/users/:id`, not `/users/123`)
- Traces are sampled
- Observability is wired through middleware, not business logic
- Existing tests still pass after the changes

If `./.memory-bank/` exists, add a note (`mb-note.sh "observability-<module>"`).
