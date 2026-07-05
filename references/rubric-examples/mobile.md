# Calibration examples — mobile

iOS (Swift) and Android (Kotlin) skill-baseline examples (reviewer-2.0,
design.md §4). One block per reviewer category
(`logic`/`code_rules`/`security`/`scalability`/`tests`).

---
example_id: MOB-LOGIC-001
stack: mobile
category: logic
severity: major
---

### Bad

```swift
func priceLabel(for product: Product?) -> String {
    return "$\(product!.price)"
}
```

### Good

```swift
func priceLabel(for product: Product?) -> String {
    guard let product = product else { return "—" }
    return "$\(product.price)"
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "logic",
  "message": "Force-unwrapping `product` (product!) crashes the app whenever the product is nil (e.g. removed mid-fetch) instead of handling absence gracefully.",
  "fix": "Use optional binding (guard let / if let) or nil-coalescing to provide a fallback instead of force-unwrapping."
}
```
---

---
example_id: MOB-CODE-001
stack: mobile
category: code_rules
severity: major
---

### Bad

```swift
class ProfileViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        URLSession.shared.dataTask(with: profileURL) { data, _, _ in
            let user = try? JSONDecoder().decode(User.self, from: data!)
            UserDefaults.standard.set(user?.name, forKey: "cachedName")
            DispatchQueue.main.async {
                self.nameLabel.text = user?.name
            }
        }.resume()
    }
}
```

### Good

```swift
class ProfileViewController: UIViewController {
    private let viewModel: ProfileViewModel
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            await viewModel.load()
            nameLabel.text = viewModel.displayName
        }
    }
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "code_rules",
  "message": "ProfileViewController performs networking, JSON decoding, and persistence directly in viewDidLoad -- it violates the UDF/Clean layering (View -> ViewModel -> UseCase -> Repository) and cannot be unit-tested without hitting the network.",
  "fix": "Extract fetching + decoding + caching into a ViewModel backed by a Repository; the ViewController should only bind to published state."
}
```
---

---
example_id: MOB-SEC-001
stack: mobile
category: security
severity: blocker
---

### Bad

```swift
func saveAuthToken(_ token: String) {
    UserDefaults.standard.set(token, forKey: "auth_token")
}
```

### Good

```swift
func saveAuthToken(_ token: String) throws {
    try KeychainStore.set(token, service: "auth_token", accessibility: .whenUnlockedThisDeviceOnly)
}
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "security",
  "message": "Storing the auth token in UserDefaults keeps it in plaintext and includes it in unencrypted device/iCloud backups -- a credential-exposure risk.",
  "fix": "Store the token in the Keychain (kSecClassGenericPassword) with an appropriate accessibility level instead of UserDefaults."
}
```
---

---
example_id: MOB-SCALE-001
stack: mobile
category: scalability
severity: major
---

### Bad

```kotlin
class OrderListViewModel(private val repository: OrderRepository) : ViewModel() {
    val orders = MutableStateFlow<List<Order>>(emptyList())

    fun loadOrders() {
        viewModelScope.launch {
            orders.value = repository.fetchAllOrders() // loads entire history, no paging
        }
    }
}
```

### Good

```kotlin
class OrderListViewModel(private val repository: OrderRepository) : ViewModel() {
    val orders: Flow<PagingData<Order>> = Pager(PagingConfig(pageSize = 20)) {
        OrderPagingSource(repository)
    }.flow.cachedIn(viewModelScope)
}
```

### Expected verdict fragment

```json
{
  "severity": "major",
  "category": "scalability",
  "message": "fetchAllOrders() loads the user's entire order history in a single call with no paging or limit -- as history grows this bloats memory and network payload every time the screen opens.",
  "fix": "Page results with Paging 3 (PagingSource/Pager) instead of loading the full history in one shot."
}
```
---

---
example_id: MOB-TESTS-001
stack: mobile
category: tests
severity: blocker
---

### Bad

```kotlin
@Test
@Ignore("flaky on CI, revisit")
fun `applies bulk discount over 50 units`() {
    assertEquals(0.15, calculateDiscount(orderOf(50)), 0.0001)
}
```

### Good

```kotlin
@Test
fun `applies bulk discount over 50 units`() {
    assertEquals(0.15, calculateDiscount(orderOf(50)), 0.0001)
}
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "tests",
  "message": "@Ignore disables the bulk-discount test instead of fixing the flakiness it was written to catch.",
  "fix": "Root-cause the flake (likely shared test fixture or rounding) and remove @Ignore before merging."
}
```
---
