# Calibration examples — typescript

TypeScript/JavaScript-specific skill-baseline examples (reviewer-2.0,
design.md §4). One block per reviewer category
(`logic`/`code_rules`/`security`/`scalability`/`tests`).

---
example_id: TS-LOGIC-001
stack: typescript
category: logic
severity: major
---

### Bad

```typescript
function sortScores(scores: number[]): number[] {
  return scores.sort();
}
```

### Good

```typescript
function sortScores(scores: number[]): number[] {
  return [...scores].sort((a, b) => a - b);
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "logic",
  "message": "Array.prototype.sort() with no comparator sorts numbers lexicographically (e.g. [10, 2, 33] -> [10, 2, 33] ordered as strings), not numerically. It also mutates the input array in place.",
  "fix": "Pass a numeric comparator (a, b) => a - b to sort(), and copy the array first with [...scores] if the caller must not observe mutation."
}
```
---

---
example_id: TS-CODE-001
stack: typescript
category: code_rules
severity: major
---

### Bad

```typescript
function parseConfig(raw: any): any {
  return JSON.parse(raw);
}
```

### Good

```typescript
interface Config {
  apiUrl: string;
  timeoutMs: number;
}

function parseConfig(raw: string): Config {
  const parsed: unknown = JSON.parse(raw);
  if (!isConfig(parsed)) {
    throw new Error("invalid config shape");
  }
  return parsed;
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "code_rules",
  "message": "Both the parameter and return type are `any`, defeating TypeScript's type checking end-to-end -- callers get zero compile-time safety and malformed JSON is never validated.",
  "fix": "Declare an explicit Config interface, type the input as string, parse into `unknown`, and narrow with a type guard (or a schema validator like zod) before returning."
}
```
---

---
example_id: TS-SEC-001
stack: typescript
category: security
severity: blocker
---

### Bad

```typescript
function renderUserBio(bio: string): void {
  document.getElementById("bio")!.innerHTML = bio;
}
```

### Good

```typescript
function renderUserBio(bio: string): void {
  document.getElementById("bio")!.textContent = bio;
}
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "security",
  "message": "Unsanitized, user-controlled `bio` is assigned via innerHTML, letting an attacker inject arbitrary markup/script -- a stored XSS vector.",
  "fix": "Render as text via textContent, or sanitize with a vetted library (e.g. DOMPurify.sanitize(bio)) before assigning to innerHTML."
}
```
---

---
example_id: TS-SCALE-001
stack: typescript
category: scalability
severity: major
---

### Bad

```typescript
async function fetchAllUsers(ids: string[]): Promise<User[]> {
  const users: User[] = [];
  for (const id of ids) {
    const user = await fetchUser(id);
    users.push(user);
  }
  return users;
}
```

### Good

```typescript
async function fetchAllUsers(ids: string[]): Promise<User[]> {
  return Promise.all(ids.map((id) => fetchUser(id)));
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "scalability",
  "message": "Sequential `await` inside the for-loop fetches one user at a time; total latency grows linearly with ids.length instead of running requests concurrently.",
  "fix": "Fan out with Promise.all(ids.map(fetchUser)) (or a bounded-concurrency helper for very large id lists) so requests overlap."
}
```
---

---
example_id: TS-TESTS-001
stack: typescript
category: tests
severity: blocker
---

### Bad

```typescript
it.skip("applies bulk discount over 50 units", () => {
  expect(calculateDiscount(order(50))).toBeCloseTo(0.15);
});
```

### Good

```typescript
it("applies bulk discount over 50 units", () => {
  expect(calculateDiscount(order(50))).toBeCloseTo(0.15);
});
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "tests",
  "message": "it.skip disables the bulk-discount test instead of fixing the underlying assertion failure.",
  "fix": "Root-cause the failure in calculateDiscount (or the test's expectation) and remove .skip before merging."
}
```
---
