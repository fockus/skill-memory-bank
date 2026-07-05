# Calibration examples — frontend

React/Vue/Svelte UI-specific skill-baseline examples (reviewer-2.0,
design.md §4). One block per reviewer category
(`logic`/`code_rules`/`security`/`scalability`/`tests`).

---
example_id: FE-LOGIC-001
stack: frontend
category: logic
severity: major
---

### Bad

```jsx
function SearchBox({ query }) {
  const [results, setResults] = useState([]);
  useEffect(() => {
    fetchResults(query).then(setResults);
  }, []); // missing `query` dependency
  return <ResultsList results={results} />;
}
```

### Good

```jsx
function SearchBox({ query }) {
  const [results, setResults] = useState([]);
  useEffect(() => {
    let cancelled = false;
    fetchResults(query).then((r) => {
      if (!cancelled) setResults(r);
    });
    return () => {
      cancelled = true;
    };
  }, [query]);
  return <ResultsList results={results} />;
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "logic",
  "message": "The effect's dependency array omits `query`, so the search only ever runs once with the initial query -- a stale closure that never refreshes results when the prop changes.",
  "fix": "Add `query` to the dependency array and guard against out-of-order responses (cancellation flag or AbortController) for rapidly changing queries."
}
```
---

---
example_id: FE-CODE-001
stack: frontend
category: code_rules
severity: major
---

### Bad

```jsx
function TodoList({ todos }) {
  return (
    <ul>
      {todos.map((todo, index) => (
        <li key={index}>{todo.text}</li>
      ))}
    </ul>
  );
}
```

### Good

```jsx
function TodoList({ todos }) {
  return (
    <ul>
      {todos.map((todo) => (
        <li key={todo.id}>{todo.text}</li>
      ))}
    </ul>
  );
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "code_rules",
  "message": "Using the array index as the React `key` breaks reconciliation identity when todos are reordered, inserted, or removed -- items can retain stale local state or re-render with the wrong content.",
  "fix": "Key list items by a stable identifier from the data itself (todo.id) instead of the array index."
}
```
---

---
example_id: FE-SEC-001
stack: frontend
category: security
severity: blocker
---

### Bad

```jsx
function CommentBody({ html }) {
  return <div dangerouslySetInnerHTML={{ __html: html }} />;
}
```

### Good

```jsx
import DOMPurify from "dompurify";

function CommentBody({ html }) {
  return <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(html) }} />;
}
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "security",
  "message": "Raw, user-supplied `html` is injected via dangerouslySetInnerHTML with no sanitization -- a stored XSS vector for anyone who can submit a comment.",
  "fix": "Sanitize with a vetted library (DOMPurify.sanitize(html)) before injecting, or render the comment as plain text if rich markup isn't required."
}
```
---

---
example_id: FE-SCALE-001
stack: frontend
category: scalability
severity: major
---

### Bad

```jsx
function ProductGrid({ products }) {
  // products can exceed 10,000 rows
  return (
    <div className="grid">
      {products.map((p) => (
        <ProductCard key={p.id} product={p} />
      ))}
    </div>
  );
}
```

### Good

```jsx
import { FixedSizeList } from "react-window";

function ProductGrid({ products }) {
  return (
    <FixedSizeList height={800} itemCount={products.length} itemSize={120} width="100%">
      {({ index, style }) => (
        <div style={style}>
          <ProductCard product={products[index]} />
        </div>
      )}
    </FixedSizeList>
  );
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "scalability",
  "message": "Mapping the entire products array (which can exceed 10k rows) straight into the DOM mounts every row up front, with no windowing -- render time and memory degrade badly as the list grows.",
  "fix": "Virtualize the list (e.g. react-window/react-virtual) so only the visible rows are mounted at any time."
}
```
---

---
example_id: FE-TESTS-001
stack: frontend
category: tests
severity: blocker
---

### Bad

```jsx
describe.skip("checkout form validation", () => {
  it("shows an error when the card number is invalid", () => {
    render(<CheckoutForm />);
    fireEvent.change(screen.getByLabelText("Card number"), { target: { value: "123" } });
    expect(screen.getByText("Invalid card number")).toBeInTheDocument();
  });
});
```

### Good

```jsx
describe("checkout form validation", () => {
  it("shows an error when the card number is invalid", () => {
    render(<CheckoutForm />);
    fireEvent.change(screen.getByLabelText("Card number"), { target: { value: "123" } });
    expect(screen.getByText("Invalid card number")).toBeInTheDocument();
  });
});
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "tests",
  "message": "describe.skip disables the entire checkout-validation suite instead of fixing the failing assertion it guards.",
  "fix": "Re-enable the suite (drop .skip) and fix CheckoutForm's validation so the assertion passes, or delete the suite if it is truly obsolete."
}
```
---
