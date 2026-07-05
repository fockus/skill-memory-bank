# Calibration examples — go

Go-specific skill-baseline examples (reviewer-2.0, design.md §4).

---
example_id: GO-CODE-001
stack: go
category: code_rules
severity: blocker
---

### Bad

```go
func LoadConfig(path string) *Config {
	data, _ := os.ReadFile(path)
	var cfg Config
	json.Unmarshal(data, &cfg)
	return &cfg
}
```

### Good

```go
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config %s: %w", path, err)
	}
	return &cfg, nil
}
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "code_rules",
  "message": "Both os.ReadFile and json.Unmarshal errors are discarded with `_`; a missing/corrupt config file silently returns a zero-value Config.",
  "fix": "Return (*Config, error), wrap each error with fmt.Errorf(\"...: %w\", err), and let the caller decide how to fail."
}
```
---

---
example_id: GO-SCALE-001
stack: go
category: scalability
severity: major
---

### Bad

```go
func FanOutJobs(jobs []Job) {
	for _, j := range jobs {
		go process(j) // no wait, no bound on concurrency
	}
}
```

### Good

```go
func FanOutJobs(ctx context.Context, jobs []Job) error {
	sem := make(chan struct{}, 8)
	var wg sync.WaitGroup
	var firstErr error
	var mu sync.Mutex
	for _, j := range jobs {
		wg.Add(1)
		sem <- struct{}{}
		go func(job Job) {
			defer wg.Done()
			defer func() { <-sem }()
			if err := process(job); err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
			}
		}(j)
	}
	wg.Wait()
	return firstErr
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "scalability",
  "message": "Unbounded goroutine fan-out with no WaitGroup: goroutines leak silently on error and concurrency is not bounded, risking resource exhaustion under load.",
  "fix": "Bound concurrency with a semaphore channel (or worker pool), join with sync.WaitGroup, and propagate the first error back to the caller."
}
```
---

---
example_id: GO-LOGIC-001
stack: go
category: logic
severity: major
---

### Bad

```go
func FirstMatch(items []string, target string) int {
	for i, v := range items {
		if v == target {
			return i
		}
	}
	return 0 // requirement: "-1 when not found"
}
```

### Good

```go
func FirstMatch(items []string, target string) int {
	for i, v := range items {
		if v == target {
			return i
		}
	}
	return -1
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "logic",
  "message": "Not-found case returns 0, which is indistinguishable from a match at index 0 — contradicts the requirement's documented -1 sentinel.",
  "fix": "Return -1 on no match, and add a test asserting the not-found path explicitly."
}
```
---

---
example_id: GO-TESTS-001
stack: go
category: tests
severity: blocker
---

### Bad

```go
func TestApplyDiscount(t *testing.T) {
	t.Skip("investigate rounding mismatch later")
	got := ApplyDiscount(10000, 0.15)
	want := 8500
	if got != want {
		t.Fatalf("got %d, want %d", got, want)
	}
}
```

### Good

```go
func TestApplyDiscount(t *testing.T) {
	got := ApplyDiscount(10000, 0.15)
	want := 8500
	if got != want {
		t.Fatalf("got %d, want %d", got, want)
	}
}
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "tests",
  "message": "t.Skip disables the discount-rounding test instead of fixing the rounding mismatch it was written to catch.",
  "fix": "Fix ApplyDiscount's rounding (or the test's expectation) and remove t.Skip before merging."
}
```
---
