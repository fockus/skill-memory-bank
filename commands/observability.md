---
description: Add structured logging, metrics, and tracing to a module
allowed-tools: [Read, Glob, Grep, Bash, Write]
---

# Observability: $ARGUMENTS

## 1. Analyze the current state

```bash
# Logging
grep -rn "log\.\|logger\.\|logging\.\|fmt\.Print\|console\.log\|print(" \
  --include="*.go" --include="*.py" --include="*.ts" . | head -30

# Metrics
grep -rn "prometheus\|metrics\|statsd\|datadog" . | head -20

# Tracing
grep -rn "opentelemetry\|jaeger\|zipkin\|trace\.\|span\." . | head -20

# Current dependencies
grep -E "zerolog|zap|slog|logrus|structlog|pino" go.mod package.json requirements.txt 2>/dev/null
```

## 2. Structured Logging

### Go (`zerolog` / `slog`)
- Replace `fmt.Println` / `log.Println` with a structured logger
- Required fields: `timestamp`, `level`, `message`, `request_id`, `error` (if present)
- Levels: `DEBUG` (dev), `INFO` (business events), `WARN` (recoverable), `ERROR` (failures)
- Use JSON format for production

### Python (`structlog`)
- Replace `print()` / `logging.info()` with a structured logger
- Use JSON for production and colored output for local development

### Requirements
- Logs must NOT contain PII or secrets
- Every log entry must include a correlation ID (`request_id` / `trace_id`)
- Error logs must include a stack trace

## 3. Metrics (Prometheus)

Add metrics:
- `http_requests_total` — counter by method, path, status
- `http_request_duration_seconds` — histogram by method, path
- Business metrics: registrations, orders, payments (counter)
- Go runtime: goroutines, memory (automatic via `promhttp`)

Requirements:
- Bounded cardinality (NEVER use `user_id` / `email` as labels)
- Middleware/interceptor approach (not inline inside handlers)

## 4. Tracing (OpenTelemetry)

Add spans:
- HTTP handler (automatically via middleware)
- DB queries
- External API calls
- Key business operations

Requirements:
- Context propagation across the full stack
- Production sampling (not 100%)
- Trace ID in logs for correlation

## 5. Verification

- No PII/secrets in logs
- Metrics have bounded cardinality
- Traces use sampling
- Everything is wired through middleware (not inline in business logic)
- Tests do not break because observability was added

If `./.memory-bank/` exists, add a note in `notes/`.
