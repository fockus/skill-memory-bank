# Calibration examples — backend

Backend-architecture skill-baseline examples (reviewer-2.0, design.md §4):
Clean Architecture layering, concurrency/idempotency, and API authorization
concerns that cut across languages. One block per reviewer category
(`logic`/`code_rules`/`security`/`scalability`/`tests`).

---
example_id: BACK-LOGIC-001
stack: backend
category: logic
severity: major
---

### Bad

```python
def reserve_inventory(sku, qty):
    stock = db.get_stock(sku)
    if stock >= qty:
        db.set_stock(sku, stock - qty)
        return True
    return False
```

### Good

```python
def reserve_inventory(sku, qty):
    updated = db.execute(
        "UPDATE stock SET qty = qty - ? WHERE sku = ? AND qty >= ?",
        (qty, sku, qty),
    )
    return updated.rowcount == 1
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "logic",
  "message": "Read-then-write on `stock` with no transaction/lock is a classic TOCTOU race: two concurrent reservations can both read the same stock value and both succeed, oversubscribing inventory.",
  "fix": "Use an atomic conditional update (UPDATE stock SET qty = qty - ? WHERE sku = ? AND qty >= ?) inside a transaction instead of separate read/write calls."
}
```
---

---
example_id: BACK-CODE-001
stack: backend
category: code_rules
severity: blocker
---

### Bad

```python
# domain/order.py
from infrastructure.postgres import PostgresConnection

class Order:
    def __init__(self, order_id: str, customer_id: str, total_cents: int):
        self.order_id = order_id
        self.customer_id = customer_id
        self.total_cents = total_cents

    def save(self):
        conn = PostgresConnection()
        conn.execute(
            "INSERT INTO orders (id, customer_id, total_cents) VALUES (%s, %s, %s)",
            (self.order_id, self.customer_id, self.total_cents),
        )
```

### Good

```python
# domain/order.py
class Order:
    def __init__(self, order_id: str, customer_id: str, total_cents: int):
        self.order_id = order_id
        self.customer_id = customer_id
        self.total_cents = total_cents

# application/order_repository.py (port)
class OrderRepository(Protocol):
    def save(self, order: Order) -> None: ...

# infrastructure/postgres_order_repository.py (adapter)
class PostgresOrderRepository:
    def __init__(self, conn):
        self._conn = conn

    def save(self, order: Order) -> None:
        self._conn.execute(
            "INSERT INTO orders (id, customer_id, total_cents) VALUES (%s, %s, %s)",
            (order.order_id, order.customer_id, order.total_cents),
        )
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "code_rules",
  "message": "The `Order` domain entity imports infrastructure.postgres directly, violating the Clean Architecture dependency rule (Infrastructure -> Application -> Domain must never point inward-out from Domain).",
  "fix": "Define an OrderRepository port in the domain/application layer, implement it in infrastructure, and inject it -- keep the domain entity free of external dependencies."
}
```
---

---
example_id: BACK-SEC-001
stack: backend
category: security
severity: blocker
---

### Bad

```python
@app.get("/api/invoices/{invoice_id}")
def get_invoice(invoice_id: str):
    return db.get_invoice(invoice_id)
```

### Good

```python
@app.get("/api/invoices/{invoice_id}")
def get_invoice(invoice_id: str, current_user: User = Depends(get_current_user)):
    invoice = db.get_invoice(invoice_id)
    if invoice is None or invoice.owner_id != current_user.id:
        raise HTTPException(status_code=404)
    return invoice
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "security",
  "message": "No check that the caller owns/has access to `invoice_id` -- any authenticated caller can read any invoice by guessing or incrementing IDs (Insecure Direct Object Reference).",
  "fix": "Verify invoice.owner_id matches the authenticated current_user (or an equivalent authorization check) before returning the record, and return 404 (not 403) on mismatch to avoid leaking existence."
}
```
---

---
example_id: BACK-SCALE-001
stack: backend
category: scalability
severity: major
---

### Bad

```python
@app.post("/api/reports/generate")
def generate_report(request):
    data = build_full_export(request.account_id)  # takes minutes, CPU heavy
    return {"report": data}
```

### Good

```python
@app.post("/api/reports/generate")
def generate_report(request):
    job_id = report_queue.enqueue(build_full_export, request.account_id)
    return JSONResponse({"job_id": job_id}, status_code=202)
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "scalability",
  "message": "Generating the full export synchronously inside the request/response cycle blocks a worker for minutes and caps throughput at a handful of concurrent requests.",
  "fix": "Enqueue the job on a task queue (e.g. Celery/SQS/RQ), return 202 with a job id, and let the client poll or subscribe for completion."
}
```
---

---
example_id: BACK-TESTS-001
stack: backend
category: tests
severity: blocker
---

### Bad

```python
@pytest.mark.skip(reason="depends on infra team fixing staging DB")
def test_order_total_includes_tax():
    assert calculate_total(order_with_tax()) == Decimal("108.00")
```

### Good

```python
def test_order_total_includes_tax():
    assert calculate_total(order_with_tax()) == Decimal("108.00")
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "tests",
  "message": "pytest.mark.skip hides a real business-logic assertion (tax calculation) behind an unrelated infra excuse instead of isolating the dependency.",
  "fix": "Isolate the staging-DB dependency (fixture/fake repository) so the tax-calculation assertion runs deterministically, then remove the skip."
}
```
---
