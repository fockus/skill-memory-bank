# Calibration examples — common (cross-stack)

Skill-baseline, stack-agnostic examples for `mb-reviewer` few-shot
calibration (reviewer-2.0, design.md §4). Each block is delimited by `---`
lines with YAML front-matter, a `### Bad` snippet, and an
`### Expected verdict fragment` JSON fragment. Only the `Bad` snippet and
verdict fragment are ever injected into a reviewer payload — this file may
also carry a documentation-only `### Good` section per block, which the
loader reads but never injects.

---
example_id: COMMON-SEC-001
stack: common
category: security
severity: blocker
---

### Bad

```text
DB_PASSWORD = "s3cr3t-prod-pw"
API_KEY = "sk-live-4f9a2b7c1d"

def connect():
    return db_connect(password=DB_PASSWORD)
```

### Good

```text
DB_PASSWORD = os.environ["DB_PASSWORD"]
API_KEY = os.environ["API_KEY"]

def connect():
    return db_connect(password=DB_PASSWORD)
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "security",
  "message": "Hard-coded credentials (DB_PASSWORD, API_KEY) committed to source.",
  "fix": "Move secrets to environment variables / a secret manager; rotate the leaked values."
}
```
---

---
example_id: COMMON-CODE-001
stack: common
category: code_rules
severity: major
---

### Bad

```text
def process_order(order):
    # TODO: handle partial refunds properly, for now just approximate
    total = order.amount * 0.9  # ...
    return total
```

### Good

```text
def process_order(order):
    return calculate_refund(order.amount, order.refund_policy)
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "code_rules",
  "message": "TODO placeholder + approximated logic (`...`) shipped as production code.",
  "fix": "Implement calculate_refund fully before merging; remove the TODO and the approximation comment."
}
```
---

---
example_id: COMMON-SCALE-001
stack: common
category: scalability
severity: major
---

### Bad

```text
orders = fetch_all_orders()
for order in orders:
    customer = db.query("SELECT * FROM customers WHERE id = ?", order.customer_id)
    order.customer_name = customer.name
```

### Good

```text
orders = fetch_all_orders()
customer_ids = [o.customer_id for o in orders]
customers = db.query_many("SELECT * FROM customers WHERE id IN (?)", customer_ids)
by_id = {c.id: c for c in customers}
for order in orders:
    order.customer_name = by_id[order.customer_id].name
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "scalability",
  "message": "N+1 query: one customer lookup per order inside the loop.",
  "fix": "Batch-fetch customers once with an IN (...) query and join in memory."
}
```
---

---
example_id: COMMON-TESTS-001
stack: common
category: tests
severity: blocker
---

### Bad

```text
describe.skip("refund calculation", () => {
  it("applies partial refund policy", () => {
    expect(calculateRefund(100, "partial")).toBe(90);
  });
});
```

### Good

```text
describe("refund calculation", () => {
  it("applies partial refund policy", () => {
    expect(calculateRefund(100, "partial")).toBe(90);
  });
});
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "tests",
  "message": "describe.skip disables the entire refund-calculation suite instead of fixing/removing it.",
  "fix": "Re-enable the suite (drop .skip) and make the underlying assertions pass, or delete the suite if truly obsolete."
}
```
---

---
example_id: COMMON-LOGIC-001
stack: common
category: logic
severity: major
---

### Bad

```text
def days_until_expiry(expiry_date, today):
    return (expiry_date - today).days

# requirement: "an item expiring TODAY must be reported as expired (0 days
# remaining should be treated as expired, not valid)"
def is_expired(expiry_date, today):
    return days_until_expiry(expiry_date, today) < 0
```

### Good

```text
def is_expired(expiry_date, today):
    return days_until_expiry(expiry_date, today) <= 0
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "logic",
  "message": "Off-by-one: an item expiring today (0 days remaining) is not treated as expired, contradicting the stated requirement.",
  "fix": "Use <= 0 instead of < 0 so the expiry-day edge case is covered, and add a test asserting it."
}
```
---
