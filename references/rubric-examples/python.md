# Calibration examples — python

Python-specific skill-baseline examples (reviewer-2.0, design.md §4). The
first block (`PY-SRP-001`) is the worked example from design.md §4 "File
format", reproduced verbatim as the calibration seed.

---
example_id: PY-SRP-001
stack: python
category: code_rules
severity: blocker
---

### Bad

```python
class UserService:
    def __init__(self, db): self.db = db
    def create(self, ...): ...
    def list(self, ...): ...
    def update(self, ...): ...
    def delete(self, ...): ...
    def send_welcome_email(self, ...): ...   # different responsibility
    def export_to_csv(self, ...): ...        # different responsibility
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "code_rules",
  "message": "UserService aggregates persistence, notification, and export — 3 distinct responsibilities.",
  "fix": "Extract send_welcome_email/export_to_csv into UserNotifier/UserExporter. Keep UserService as orchestrator if needed."
}
```
---

---
example_id: PY-LOGIC-001
stack: python
category: logic
severity: blocker
---

### Bad

```python
def add_item(cart, item, tags=[]):
    tags.append("cart-item")
    cart.append({"item": item, "tags": tags})
    return cart
```

### Good

```python
def add_item(cart, item, tags=None):
    tags = list(tags) if tags is not None else []
    tags.append("cart-item")
    cart.append({"item": item, "tags": tags})
    return cart
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "logic",
  "message": "Mutable default argument `tags=[]` is shared and mutated across every call, leaking state between unrelated cart items.",
  "fix": "Default to None and build a fresh list per call (`tags = list(tags) if tags is not None else []`)."
}
```
---

---
example_id: PY-SEC-001
stack: python
category: security
severity: blocker
---

### Bad

```python
def find_user(conn, username):
    query = "SELECT * FROM users WHERE username = '" + username + "'"
    return conn.execute(query).fetchone()
```

### Good

```python
def find_user(conn, username):
    return conn.execute(
        "SELECT * FROM users WHERE username = ?", (username,)
    ).fetchone()
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "security",
  "message": "Raw SQL string concatenation with an unsanitized `username` is a SQL-injection vector.",
  "fix": "Use parameterized queries (placeholders + a params tuple) instead of string concatenation."
}
```
---

---
example_id: PY-SCALE-001
stack: python
category: scalability
severity: major
---

### Bad

```python
async def handler(request):
    data = requests.get("https://api.internal/inventory").json()  # blocking I/O
    return web.json_response(data)
```

### Good

```python
async def handler(request):
    async with aiohttp.ClientSession() as session:
        async with session.get("https://api.internal/inventory") as resp:
            data = await resp.json()
    return web.json_response(data)
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "scalability",
  "message": "Blocking `requests.get` inside an `async def` handler stalls the event loop for every concurrent request.",
  "fix": "Use an async HTTP client (aiohttp/httpx.AsyncClient) so the coroutine actually yields during I/O."
}
```
---

---
example_id: PY-TESTS-001
stack: python
category: tests
severity: blocker
---

### Bad

```python
@pytest.mark.skip(reason="flaky, fix later")
def test_discount_applies_to_bulk_orders():
    assert calculate_discount(order_of(50)) == pytest.approx(0.15)
```

### Good

```python
def test_discount_applies_to_bulk_orders():
    assert calculate_discount(order_of(50)) == pytest.approx(0.15)
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "tests",
  "message": "pytest.mark.skip disables the bulk-discount test instead of fixing the underlying flakiness.",
  "fix": "Root-cause the flake (likely shared fixture state) and re-enable the test; do not merge with skip markers on business-logic tests."
}
```
---
