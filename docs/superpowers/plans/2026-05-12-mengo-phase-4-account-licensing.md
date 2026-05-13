# Mengo Desktop Phase 4 — Account & Licensing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a mandatory Mengo account (magic-link sign-in, hard wall, offline-tolerant once in), Free/Pro entitlement gating (≤3 saved flows), a Settings pane (synthesis-runtime picker — Claude Code default + Codex wired, Cowork/custom-MCP shown-but-disabled; launch-at-login; start-recording-on-launch; logs/data), the sidebar reorg (Settings pinned bottom, Purchase + free-flow counter above it for Free users), and the `mengo://` deep-link scheme.

**Architecture:** Three new `@Observable @MainActor` stores join `RecorderController` and `FlowController`: `AccountStore` (sign-in state + cached entitlement, talks HTTPS to `mengo.ai`, session token in Keychain, account metadata in a JSON cache), `SettingsStore` (UserDefaults: `synthesisRuntime`, `startRecordingOnLaunch`; `openAtLogin` mirrors `SMAppService`), and `SynthesisRuntime` (enum + per-runtime command/preflight builders). `MengoDesktopApp` shows `SignInView` until `account.state == .signedIn`, then the normal layout. `FlowController.synthesize()` dispatches on `settings.synthesisRuntime`; `FlowController.save()` checks `account` for the flow limit.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, XCTest, `Security.framework` (Keychain), `ServiceManagement` (`SMAppService`), `URLSession` (HTTPS to mengo.ai), the `codex` CLI (`codex exec`). Spec: [`docs/superpowers/specs/2026-05-12-mengo-phase-4-account-licensing-design.md`](../specs/2026-05-12-mengo-phase-4-account-licensing-design.md).

**Conventions in this repo (read before starting):**
- Stores are `@Observable @MainActor final class`, deps injected via `init` for tests, with a `static func live(...)` production initializer and an `AppDelegate.sharedX` weak bridge. See `RecorderController.swift` / `FlowController.swift`.
- Panes are SwiftUI `struct ...: View` taking the store(s) as `let` props; dark/orange palette via `Theme.*`; free-content panes wrap their body in a `ScrollView` (see `MemoryPane`, and the post-Phase-3 fix to `FlowPane`/`LibraryPane`) so the window stays freely resizable.
- Tests: `XCTest`, `@testable import MengoDesktop`, `@MainActor final class XTests: XCTestCase`. Stubs are local `struct`s conforming to the dep protocol. Temp dirs via `NSTemporaryDirectory()`.
- `Log.line(_:)` for logging; `Log.directory` is `~/Library/Logs/MengoDesktop/`.
- Commit after every task. Run `swift build` + `swift test` before each commit; both must be green.

---

## File Structure

**New files:**
| File | Responsibility |
|---|---|
| `Sources/MengoDesktop/KeychainStore.swift` | `protocol SecretStore` + `KeychainStore` (real `SecItem*`) + `InMemorySecretStore` (test stub). Stores only the session token. |
| `Sources/MengoDesktop/MengoURL.swift` | Pure `mengo://` deep-link parser → `enum MengoLink`. |
| `Sources/MengoDesktop/MengoAPIClient.swift` | `protocol MengoAPI` + `MengoAPIClient` (HTTPS to `mengo.ai`) + the request/response `Codable` types + the `Account`/`Plan` model. |
| `Sources/MengoDesktop/AccountStore.swift` | `@Observable @MainActor` — `AccountState` machine, sign-in, refresh, sign-out, web-handoff URL, persistence, dev escape hatch. |
| `Sources/MengoDesktop/SignInView.swift` | The hard-wall sign-in screen. |
| `Sources/MengoDesktop/SynthesisRuntime.swift` | `enum SynthesisRuntime` + per-runtime invocation/preflight builders + `RuntimeInvocation`/`FinalStatusSource`. |
| `Sources/MengoDesktop/SettingsStore.swift` | `@Observable @MainActor` — UserDefaults-backed settings + `SMAppService` login-item mirror. |
| `Sources/MengoDesktop/SettingsPane.swift` | The Settings pane (Account / Synthesis model / Startup / Logs & data). |

**New test files:** `Tests/MengoDesktopTests/{KeychainStoreTests,MengoURLTests,MengoAPIClientTests,AccountStoreTests,SynthesisRuntimeTests,SettingsStoreTests}.swift`. Extend `Tests/MengoDesktopTests/FlowControllerTests.swift`.

**Modified files:** `Sources/MengoDesktop/{FlowController,MengoDesktopApp,MainWindowView,MenuBarContent}.swift`; `Resources/MengoDesktopInfo.plist`; `docs/manual-smoke-tests/` (new checklist).

**Internal sequencing:** Part A (account / sign-in / hard wall / Keychain / `mengo://`) → Part B (Settings + runtime + Codex + startup + logs) → Part C (gating + sidebar + purchase + counter) → finalize.

---

## Part A — Account, sign-in, hard wall, Keychain, `mengo://`

### Task A1: `KeychainStore` + `SecretStore` protocol + in-memory stub

**Files:**
- Create: `Sources/MengoDesktop/KeychainStore.swift`
- Test: `Tests/MengoDesktopTests/KeychainStoreTests.swift`

- [ ] **Step 1: Write the failing test** (`KeychainStoreTests.swift`)

```swift
import XCTest
@testable import MengoDesktop

final class KeychainStoreTests: XCTestCase {
    func test_inMemorySecretStore_roundTrips() {
        let s = InMemorySecretStore()
        XCTAssertNil(s.get("k"))
        s.set("v1", for: "k")
        XCTAssertEqual(s.get("k"), "v1")
        s.set("v2", for: "k")
        XCTAssertEqual(s.get("k"), "v2")
        s.delete("k")
        XCTAssertNil(s.get("k"))
    }
}
```

- [ ] **Step 2: Run test, expect FAIL** — `swift test --filter KeychainStoreTests` → "cannot find 'InMemorySecretStore'".

- [ ] **Step 3: Implement** (`KeychainStore.swift`)

```swift
import Foundation
import Security

/// Abstracts secret storage so `AccountStore` tests don't touch the real Keychain.
protocol SecretStore: Sendable {
    func set(_ value: String, for key: String)
    func get(_ key: String) -> String?
    func delete(_ key: String)
}

/// macOS Keychain (`kSecClassGenericPassword`, service `ai.mengo.desktop`).
/// Used in production to hold the Mengo session token (key `mengo.sessionToken`).
struct KeychainStore: SecretStore {
    private let service = "ai.mengo.desktop"

    func set(_ value: String, for key: String) {
        delete(key)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory `SecretStore` for tests.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func set(_ value: String, for key: String) { storage[key] = value }
    func get(_ key: String) -> String? { storage[key] }
    func delete(_ key: String) { storage[key] = nil }
}

enum SecretKeys { static let sessionToken = "mengo.sessionToken" }
```

- [ ] **Step 4: Run test, expect PASS** — `swift test --filter KeychainStoreTests`.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "MengoDesktop: KeychainStore + SecretStore protocol (TDD)"`

---

### Task A2: `MengoURL` deep-link parser

**Files:**
- Create: `Sources/MengoDesktop/MengoURL.swift`
- Test: `Tests/MengoDesktopTests/MengoURLTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MengoDesktop

final class MengoURLTests: XCTestCase {
    func test_parsesAuthLink() {
        XCTAssertEqual(MengoURL.parse(URL(string: "mengo://auth?token=abc123")!), .auth(token: "abc123"))
    }
    func test_parsesRefreshLink() {
        XCTAssertEqual(MengoURL.parse(URL(string: "mengo://refresh")!), .refresh)
    }
    func test_rejectsBadLinks() {
        XCTAssertNil(MengoURL.parse(URL(string: "mengo://auth")!))            // no token
        XCTAssertNil(MengoURL.parse(URL(string: "mengo://something")!))
        XCTAssertNil(MengoURL.parse(URL(string: "https://mengo.ai/auth?token=x")!))
    }
}
```

- [ ] **Step 2: Run test, expect FAIL**.
- [ ] **Step 3: Implement** (`MengoURL.swift`)

```swift
import Foundation

/// A deep link the app handles via the registered `mengo://` URL scheme.
enum MengoLink: Equatable {
    case auth(token: String)   // mengo://auth?token=<one-time>  — the magic link
    case refresh               // mengo://refresh — re-validate entitlements now (web fires this after a purchase)
}

enum MengoURL {
    static func parse(_ url: URL) -> MengoLink? {
        guard url.scheme == "mengo" else { return nil }
        switch url.host {
        case "auth":
            guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty else { return nil }
            return .auth(token: token)
        case "refresh":
            return .refresh
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run test, expect PASS**.
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: MengoURL deep-link parser (TDD)"`

---

### Task A3: `MengoAPIClient` + the account model + JSON decoders

**Files:**
- Create: `Sources/MengoDesktop/MengoAPIClient.swift`
- Test: `Tests/MengoDesktopTests/MengoAPIClientTests.swift`

- [ ] **Step 1: Write the failing test** (decoders only — the live `URLSession` path isn't unit-tested)

```swift
import XCTest
@testable import MengoDesktop

final class MengoAPIClientTests: XCTestCase {
    func test_decodesExchangeResponse_free() throws {
        let data = Data(#"{"sessionToken":"sess_abc","account":{"email":"a@b.com","plan":"free","flowLimit":3}}"#.utf8)
        let r = try MengoAPIClient.decodeExchange(data)
        XCTAssertEqual(r.sessionToken, "sess_abc")
        XCTAssertEqual(r.account.email, "a@b.com")
        XCTAssertEqual(r.account.plan, .free)
        XCTAssertEqual(r.account.flowLimit, 3)
    }
    func test_decodesAccount_proHasNilLimit() throws {
        let acct = try MengoAPIClient.decodeAccount(Data(#"{"email":"p@b.com","plan":"pro","flowLimit":null}"#.utf8))
        XCTAssertEqual(acct.plan, .pro)
        XCTAssertNil(acct.flowLimit)
    }
    func test_decodesAccount_missingFlowLimitTreatedAsNil() throws {
        let acct = try MengoAPIClient.decodeAccount(Data(#"{"email":"p@b.com","plan":"pro"}"#.utf8))
        XCTAssertNil(acct.flowLimit)
    }
}
```

- [ ] **Step 2: Run test, expect FAIL**.
- [ ] **Step 3: Implement** (`MengoAPIClient.swift`)

```swift
import Foundation

enum Plan: String, Codable, Equatable { case free, pro }

/// The user's Mengo account snapshot. `flowLimit == nil` ⇒ unlimited (Pro).
struct Account: Codable, Equatable {
    let email: String
    let plan: Plan
    let flowLimit: Int?       // decoded; nil if absent or null
    var validatedAt: Date = .init()   // set locally on each successful fetch; not from the server

    private enum CodingKeys: String, CodingKey { case email, plan, flowLimit, validatedAt }
    init(email: String, plan: Plan, flowLimit: Int?, validatedAt: Date = .init()) {
        self.email = email; self.plan = plan; self.flowLimit = flowLimit; self.validatedAt = validatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decode(String.self, forKey: .email)
        plan = try c.decode(Plan.self, forKey: .plan)
        flowLimit = try c.decodeIfPresent(Int.self, forKey: .flowLimit) ?? nil
        validatedAt = try c.decodeIfPresent(Date.self, forKey: .validatedAt) ?? Date()
    }
}

struct ExchangeResponse: Decodable { let sessionToken: String; let account: Account }

/// HTTPS operations against `mengo.ai`. (The website owner builds these endpoints.)
protocol MengoAPI: Sendable {
    func requestLink(email: String) async throws
    func exchange(token: String) async throws -> ExchangeResponse
    func me(sessionToken: String) async throws -> Account
    func webHandoff(sessionToken: String) async throws -> String
}

enum MengoAPIError: Error, LocalizedError, Equatable {
    case unauthorized, notReachable, badStatus(Int), badBody
    var errorDescription: String? {
        switch self {
        case .unauthorized:    return "your session has expired — sign in again"
        case .notReachable:    return "couldn't reach mengo.ai — check your connection"
        case .badStatus(let c):return "mengo.ai returned HTTP \(c)"
        case .badBody:         return "mengo.ai sent an unexpected response"
        }
    }
}

struct MengoAPIClient: MengoAPI {
    var baseURL = URL(string: "https://mengo.ai")!
    var urlSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    func requestLink(email: String) async throws {
        _ = try await postJSON("/api/auth/request-link", body: ["email": email], bearer: nil)
    }
    func exchange(token: String) async throws -> ExchangeResponse {
        let data = try await postJSON("/api/auth/exchange", body: ["token": token], bearer: nil)
        return try Self.decodeExchange(data)
    }
    func me(sessionToken: String) async throws -> Account {
        let data = try await get("/api/me", bearer: sessionToken)
        return try Self.decodeAccount(data)
    }
    func webHandoff(sessionToken: String) async throws -> String {
        let data = try await postJSON("/api/auth/web-handoff", body: [:], bearer: sessionToken)
        guard let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["handoffCode"] as? String
        else { throw MengoAPIError.badBody }
        return code
    }

    // MARK: pure decoders (tested)
    static func decodeExchange(_ data: Data) throws -> ExchangeResponse {
        do { return try JSONDecoder().decode(ExchangeResponse.self, from: data) } catch { throw MengoAPIError.badBody }
    }
    static func decodeAccount(_ data: Data) throws -> Account {
        do { return try JSONDecoder().decode(Account.self, from: data) } catch { throw MengoAPIError.badBody }
    }

    // MARK: transport
    private func get(_ path: String, bearer: String?) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return try await send(req)
    }
    private func postJSON(_ path: String, body: [String: Any], bearer: String?) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }
    private func send(_ req: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do { (data, response) = try await urlSession.data(for: req) }
        catch { throw MengoAPIError.notReachable }
        guard let http = response as? HTTPURLResponse else { throw MengoAPIError.notReachable }
        if http.statusCode == 401 { throw MengoAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw MengoAPIError.badStatus(http.statusCode) }
        return data
    }
}
```

- [ ] **Step 4: Run test, expect PASS**.
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: MengoAPIClient + Account model (TDD on decoders)"`

---

### Task A4: `AccountStore` — state machine, sign-in, refresh, sign-out, persistence, dev hatch

**Files:**
- Create: `Sources/MengoDesktop/AccountStore.swift`
- Test: `Tests/MengoDesktopTests/AccountStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MengoDesktop

@MainActor
final class AccountStoreTests: XCTestCase {
    final class StubAPI: MengoAPI, @unchecked Sendable {
        var meResult: Result<Account, Error> = .success(Account(email: "a@b.com", plan: .free, flowLimit: 3))
        var exchangeResult: Result<ExchangeResponse, Error> = .success(.init(sessionToken: "sess", account: Account(email: "a@b.com", plan: .free, flowLimit: 3)))
        var requestLinkError: Error?
        func requestLink(email: String) async throws { if let e = requestLinkError { throw e } }
        func exchange(token: String) async throws -> ExchangeResponse { try exchangeResult.get() }
        func me(sessionToken: String) async throws -> Account { try meResult.get() }
        func webHandoff(sessionToken: String) async throws -> String { "code123" }
    }
    private func cacheURL() -> URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("acct-\(UUID()).json") }
    private func make(api: StubAPI = StubAPI(), secrets: SecretStore = InMemorySecretStore(), cache: URL? = nil, env: [String:String] = [:]) -> AccountStore {
        AccountStore(api: api, secrets: secrets, cacheURL: cache ?? cacheURL(), now: { Date(timeIntervalSince1970: 1_700_000_000) }, env: env)
    }

    func test_init_noCachedSession_isSignedOut() {
        XCTAssertEqual(make().state, .signedOut)
    }
    func test_devEnvVar_signsInSyntheticPro() {
        let s = make(env: ["MENGO_DEV_ACCOUNT": "pro"])
        guard case .signedIn(let a) = s.state else { return XCTFail() }
        XCTAssertEqual(a.plan, .pro); XCTAssertNil(a.flowLimit)
    }
    func test_sendMagicLink_movesToAwaitingLink() async {
        let s = make()
        await s.sendMagicLink(email: "x@y.com")
        XCTAssertEqual(s.state, .awaitingLink(email: "x@y.com"))
    }
    func test_sendMagicLink_networkFail_staysSignedOut_setsError() async {
        let api = StubAPI(); api.requestLinkError = MengoAPIError.notReachable
        let s = make(api: api)
        await s.sendMagicLink(email: "x@y.com")
        XCTAssertEqual(s.state, .signedOut)
        XCTAssertNotNil(s.lastError)
    }
    func test_handleAuthDeepLink_signsIn_storesToken_andCache() async {
        let secrets = InMemorySecretStore(); let cache = cacheURL()
        let s = make(secrets: secrets, cache: cache)
        await s.handleAuthDeepLink(token: "t")
        guard case .signedIn(let a) = s.state else { return XCTFail() }
        XCTAssertEqual(a.email, "a@b.com")
        XCTAssertEqual(secrets.get(SecretKeys.sessionToken), "sess")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }
    func test_init_withCachedSession_isSignedInFromCache() async {
        let secrets = InMemorySecretStore(); secrets.set("sess", for: SecretKeys.sessionToken)
        let cache = cacheURL()
        try? JSONEncoder().encode(Account(email: "c@b.com", plan: .pro, flowLimit: nil)).write(to: cache)
        let s = make(secrets: secrets, cache: cache)
        guard case .signedIn(let a) = s.state else { return XCTFail() }
        XCTAssertEqual(a.email, "c@b.com"); XCTAssertEqual(a.plan, .pro)
    }
    func test_refresh_networkFail_keepsCachedSignedIn() async {
        let secrets = InMemorySecretStore(); secrets.set("sess", for: SecretKeys.sessionToken)
        let cache = cacheURL()
        try? JSONEncoder().encode(Account(email: "c@b.com", plan: .pro, flowLimit: nil)).write(to: cache)
        let api = StubAPI(); api.meResult = .failure(MengoAPIError.notReachable)
        let s = make(api: api, secrets: secrets, cache: cache)
        await s.refresh()
        guard case .signedIn(let a) = s.state else { return XCTFail("should stay signed in offline") }
        XCTAssertEqual(a.plan, .pro)
    }
    func test_refresh_unauthorized_signsOut_wipesKeychain() async {
        let secrets = InMemorySecretStore(); secrets.set("sess", for: SecretKeys.sessionToken)
        let cache = cacheURL()
        try? JSONEncoder().encode(Account(email: "c@b.com", plan: .pro, flowLimit: nil)).write(to: cache)
        let api = StubAPI(); api.meResult = .failure(MengoAPIError.unauthorized)
        let s = make(api: api, secrets: secrets, cache: cache)
        await s.refresh()
        XCTAssertEqual(s.state, .signedOut)
        XCTAssertNil(secrets.get(SecretKeys.sessionToken))
    }
    func test_refresh_updatesPlan() async {
        let secrets = InMemorySecretStore(); secrets.set("sess", for: SecretKeys.sessionToken)
        let cache = cacheURL()
        try? JSONEncoder().encode(Account(email: "c@b.com", plan: .free, flowLimit: 3)).write(to: cache)
        let api = StubAPI(); api.meResult = .success(Account(email: "c@b.com", plan: .pro, flowLimit: nil))
        let s = make(api: api, secrets: secrets, cache: cache)
        await s.refresh()
        XCTAssertTrue(s.isPro)
    }
    func test_signOut_clearsEverything() async {
        let secrets = InMemorySecretStore(); let cache = cacheURL()
        let s = make(secrets: secrets, cache: cache)
        await s.handleAuthDeepLink(token: "t")
        s.signOut()
        XCTAssertEqual(s.state, .signedOut)
        XCTAssertNil(secrets.get(SecretKeys.sessionToken))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }
    func test_isPro_and_flowLimit_helpers() async {
        let s = make()
        XCTAssertFalse(s.isPro); XCTAssertNil(s.flowLimit)            // signed out
        await s.handleAuthDeepLink(token: "t")                        // → free, limit 3
        XCTAssertFalse(s.isPro); XCTAssertEqual(s.flowLimit, 3)
    }
}
```

- [ ] **Step 2: Run test, expect FAIL** (`AccountStore` undefined).
- [ ] **Step 3: Implement** (`AccountStore.swift`)

```swift
import Foundation
import Observation
import AppKit

enum AccountState: Equatable {
    case signedOut
    case awaitingLink(email: String)
    case verifying
    case signedIn(Account)
}

/// Owns the Mengo account: magic-link sign-in, cached entitlement, hard wall.
/// HTTPS to `mengo.ai`; session token in the Keychain; account metadata cached
/// in `~/Library/Application Support/MengoDesktop/account.json` so launches work offline.
@Observable
@MainActor
final class AccountStore {
    private(set) var state: AccountState = .signedOut
    private(set) var lastError: String?

    @ObservationIgnored private let api: MengoAPI
    @ObservationIgnored private let secrets: SecretStore
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let now: () -> Date

    init(api: MengoAPI = MengoAPIClient(),
         secrets: SecretStore = KeychainStore(),
         cacheURL: URL = AccountStore.defaultCacheURL(),
         now: @escaping () -> Date = Date.init,
         env: [String: String] = ProcessInfo.processInfo.environment) {
        self.api = api; self.secrets = secrets; self.cacheURL = cacheURL; self.now = now

        if let dev = env["MENGO_DEV_ACCOUNT"]?.lowercased(), dev == "pro" || dev == "free" {
            let plan: Plan = (dev == "pro") ? .pro : .free
            state = .signedIn(Account(email: "dev@mengo.local", plan: plan, flowLimit: plan == .pro ? nil : 3, validatedAt: now()))
        } else if secrets.get(SecretKeys.sessionToken) != nil, let cached = loadCachedAccount() {
            state = .signedIn(cached)
            Task { await refresh() }
        } else {
            state = .signedOut
        }
        AppDelegate.sharedAccount = self
    }

    static func defaultCacheURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MengoDesktop", isDirectory: true)
            .appendingPathComponent("account.json")
    }

    var isPro: Bool { if case .signedIn(let a) = state { return a.plan == .pro }; return false }
    var flowLimit: Int? { if case .signedIn(let a) = state { return a.flowLimit }; return nil }
    var account: Account? { if case .signedIn(let a) = state { return a }; return nil }
    var sessionToken: String? { secrets.get(SecretKeys.sessionToken) }

    func sendMagicLink(email: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = nil
        do { try await api.requestLink(email: email); state = .awaitingLink(email: email) }
        catch { lastError = (error as? LocalizedError)?.errorDescription ?? "Couldn't send the sign-in link." ; state = .signedOut }
    }

    func handleAuthDeepLink(token: String) async {
        lastError = nil
        state = .verifying
        do {
            let r = try await api.exchange(token: token)
            secrets.set(r.sessionToken, for: SecretKeys.sessionToken)
            let acct = Account(email: r.account.email, plan: r.account.plan, flowLimit: r.account.flowLimit, validatedAt: now())
            saveCachedAccount(acct)
            state = .signedIn(acct)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "That sign-in link didn't work."
            state = .signedOut
        }
    }

    func refresh() async {
        guard let token = secrets.get(SecretKeys.sessionToken) else { return }
        do {
            let fresh = try await api.me(sessionToken: token)
            let acct = Account(email: fresh.email, plan: fresh.plan, flowLimit: fresh.flowLimit, validatedAt: now())
            saveCachedAccount(acct)
            state = .signedIn(acct)
        } catch MengoAPIError.unauthorized {
            secrets.delete(SecretKeys.sessionToken); try? FileManager.default.removeItem(at: cacheURL)
            state = .signedOut
        } catch {
            // Offline / transient — keep the cached signed-in state. Nothing breaks.
        }
    }

    func signOut() {
        if let token = secrets.get(SecretKeys.sessionToken) { Task { try? await api.webHandoff(sessionToken: token) } } // best-effort; replace with /api/auth/signout when it exists — no-op if it fails
        secrets.delete(SecretKeys.sessionToken)
        try? FileManager.default.removeItem(at: cacheURL)
        state = .signedOut
    }

    /// URL that opens `mengo.ai<path>` already-signed-in (via a one-time handoff code).
    /// Falls back to the bare URL if the handoff call fails.
    func webURL(path: String) async -> URL {
        let base = URL(string: "https://mengo.ai")!.appendingPathComponent(path)
        guard let token = secrets.get(SecretKeys.sessionToken),
              let code = try? await api.webHandoff(sessionToken: token),
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        comps.queryItems = [.init(name: "handoff", value: code)]
        return comps.url ?? base
    }

    // MARK: cache
    private func loadCachedAccount() -> Account? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }
    private func saveCachedAccount(_ a: Account) {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(a).write(to: cacheURL, options: .atomic)
    }
}
```

> Note: `signOut()`'s best-effort server call is a placeholder for a future `POST /api/auth/signout`; if you'd rather not call `webHandoff` there, just drop that line — the local wipe is what matters. (Decide during execution; the test only checks the local wipe.)

- [ ] **Step 4: Run test, expect PASS** — `swift test --filter AccountStoreTests`.
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: AccountStore — magic-link sign-in, entitlement cache, offline-tolerant (TDD)"`

---

### Task A5: `SignInView` — the hard-wall screen

**Files:**
- Create: `Sources/MengoDesktop/SignInView.swift`

(No unit test — covered by the manual checklist. Build must compile.)

- [ ] **Step 1: Implement** (`SignInView.swift`)

```swift
import SwiftUI

/// The hard wall shown by `MengoDesktopApp` until `account.state == .signedIn`.
struct SignInView: View {
    let account: AccountStore
    @State private var email = ""
    @FocusState private var emailFocused: Bool

    private var emailLooksValid: Bool {
        let t = email.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".") && !t.hasSuffix("@")
    }

    var body: some View {
        VStack(spacing: 18) {
            if let logo = Brand.logo { logo.resizable().scaledToFit().frame(width: 56, height: 56) }
            Text("Sign in to Mengo").font(Theme.title).foregroundStyle(Theme.primaryText)
            content
            if let err = account.lastError { Text(err).font(Theme.caption).foregroundStyle(Theme.stopped).multilineTextAlignment(.center) }
        }
        .padding(40)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
        .onAppear { emailFocused = true }
    }

    @ViewBuilder private var content: some View {
        switch account.state {
        case .signedOut:
            Text("Mengo Desktop needs a free Mengo account. Enter your email and we'll send you a sign-in link.")
                .font(Theme.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder).focused($emailFocused)
                .onSubmit { if emailLooksValid { Task { await account.sendMagicLink(email: email) } } }
            Button("Email me a link") { Task { await account.sendMagicLink(email: email) } }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(!emailLooksValid)
        case .awaitingLink(let sent):
            Text("Check your inbox").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Text("We sent a sign-in link to \(sent). Click it on this Mac to finish signing in.")
                .font(Theme.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            HStack {
                Button("Resend") { Task { await account.sendMagicLink(email: sent) } }.buttonStyle(.bordered)
                Button("Use a different email") { email = ""; Task { /* drop back */ await MainActor.run { } } }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
        case .verifying:
            ProgressView().controlSize(.large)
            Text("Signing you in…").font(Theme.body).foregroundStyle(Theme.secondaryText)
        case .signedIn:
            EmptyView()   // MengoDesktopApp swaps in MainWindowView; this branch shouldn't render
        }
    }
}
```

> Note: "Use a different email" needs `AccountStore` to expose a way back to `.signedOut` from `.awaitingLink`. Add `func resetToSignedOut() { if case .awaitingLink = state { state = .signedOut; lastError = nil } }` to `AccountStore` (and a one-line test: from `.awaitingLink` → `.signedOut`). Wire the button to `account.resetToSignedOut()`.

- [ ] **Step 2: Add `AccountStore.resetToSignedOut()` + a test** (`AccountStoreTests`):

```swift
func test_resetToSignedOut_fromAwaitingLink() async {
    let s = make(); await s.sendMagicLink(email: "x@y.com")
    s.resetToSignedOut(); XCTAssertEqual(s.state, .signedOut)
}
```

```swift
// in AccountStore:
func resetToSignedOut() { if case .awaitingLink = state { state = .signedOut; lastError = nil } }
```

Wire `SignInView`'s "Use a different email" → `{ email = ""; account.resetToSignedOut() }`.

- [ ] **Step 3: `swift build` — must compile.**
- [ ] **Step 4: Commit** — `git commit -am "MengoDesktop: SignInView (the hard-wall sign-in screen)"`

---

### Task A6: Register `mengo://`, wire the hard wall + deep links into `MengoDesktopApp`

**Files:**
- Modify: `Resources/MengoDesktopInfo.plist`
- Modify: `Sources/MengoDesktop/MengoDesktopApp.swift`

- [ ] **Step 1: Add the URL scheme to `MengoDesktopInfo.plist`** — inside the top-level `<dict>`, add:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>ai.mengo.desktop</string>
    <key>CFBundleURLSchemes</key>
    <array><string>mengo</string></array>
  </dict>
</array>
```

- [ ] **Step 2: Modify `MengoDesktopApp.swift`** — (a) add `@State private var account = AccountStore()` (constructed in `init()` like the others — `let acct = AccountStore.live(...)` is unnecessary; the default `init()` is fine, but build it in `init()` and store via `_account = State(initialValue:)` so `AppDelegate.sharedAccount` is set before `applicationDidFinishLaunching`); (b) the `Window` body becomes:

```swift
Window("Mengo Desktop", id: "main") {
    Group {
        if case .signedIn = account.state {
            MainWindowView(appState: appState, recorder: recorder, account: account, settings: settings, flow: flow)
        } else {
            SignInView(account: account)
        }
    }
    .onOpenURL { url in
        guard let link = MengoURL.parse(url) else { Log.line("ignored deep link: \(url)"); return }
        Task { @MainActor in
            switch link {
            case .auth(let token): await account.handleAuthDeepLink(token: token)
            case .refresh:         await account.refresh()
            }
        }
    }
}
```

(c) `applicationDidFinishLaunching` (in `AppDelegate`): replace the unconditional `Task { await AppDelegate.sharedRecorder?.start() }` with — start the recorder only if signed in **and** `settings.startRecordingOnLaunch`; otherwise don't. Since `AppDelegate` doesn't hold `settings`, add `static weak var sharedSettings: SettingsStore?` (set in `SettingsStore.init`) and gate on `AppDelegate.sharedAccount?.state` being `.signedIn` and `AppDelegate.sharedSettings?.startRecordingOnLaunch != false`. Also: when the app transitions to `.signedIn` (after `handleAuthDeepLink`), start the recorder if `startRecordingOnLaunch` — add a `didSet`/observation hook, or simplest: in `handleAuthDeepLink`, after `state = .signedIn`, call `AppDelegate.startRecorderIfWanted()` (a static helper on `AppDelegate` that checks `sharedSettings?.startRecordingOnLaunch` and calls `sharedRecorder?.start()` if not already running). Keep `applicationWillTerminate` as-is. (`SettingsStore` is created in `MengoDesktopApp.init()` — see Task B5; for A6, add the `@State private var settings = SettingsStore()` placeholder so the wiring compiles, and SettingsStore itself lands in B2.)

> Sequencing note: A6 references `SettingsStore` and `MainWindowView(... account: settings:)` which land in Part B. If executing strictly in order, in A6 add a minimal `SettingsStore` stub (just `var startRecordingOnLaunch = true`) and the `account:` param to `MainWindowView` (ignored for now), then flesh both out in B2/B5. Alternatively reorder: do B2 (`SettingsStore`) before A6. **Recommended: do B1 + B2 right after A4, then A5, A6, A7** — i.e. interleave so the wiring in A6 is against the real `SettingsStore`. The task numbers below are the logical grouping, not a hard execution order.

- [ ] **Step 3: `swift build` + `swift test` — green.**
- [ ] **Step 4: Manual check** — `swift run MengoDesktop` (or build the `.app`): with no cached session and no `MENGO_DEV_ACCOUNT`, the sign-in screen shows; with `MENGO_DEV_ACCOUNT=pro swift run MengoDesktop`, the app opens to Memory. (Quit any already-running instance first — port 3030 / hotkeys.)
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: mengo:// URL scheme + hard-wall sign-in wiring + deep-link routing"`

---

### Task A7: Signed-out menu-bar state

**Files:**
- Modify: `Sources/MengoDesktop/MenuBarContent.swift`

- [ ] **Step 1: Implement** — `MenuBarContent` takes `account: AccountStore`. At the top of `body`: if `account.state` is not `.signedIn`, render only:

```swift
Text("Mengo").font(.headline)
Divider()
Button("Sign in to Mengo Desktop…") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
Divider()
Button("Quit Mengo Desktop") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
```

Otherwise render the existing content. (Pass `account` from `MengoDesktopApp`.) Also add — when signed in and `!account.isPro` — an `Button("Upgrade to Mengo Pro…") { Task { NSWorkspace.shared.open(await account.webURL(path: "/upgrade")) } }` just above the "Settings…" item (this is also covered in Task C3; doing it here is fine, or defer to C3 — don't do it twice).

- [ ] **Step 2: `swift build` — compile.**
- [ ] **Step 3: Commit** — `git commit -am "MengoDesktop: menu bar shows only 'Sign in…' when signed out"`

---

## Part B — Settings pane, SettingsStore, runtime abstraction, Codex, startup, logs

### Task B1: `SynthesisRuntime` — enum + invocation builders + preflight helpers

**Files:**
- Create: `Sources/MengoDesktop/SynthesisRuntime.swift`
- Test: `Tests/MengoDesktopTests/SynthesisRuntimeTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MengoDesktop

final class SynthesisRuntimeTests: XCTestCase {
    func test_availability_and_names() {
        XCTAssertTrue(SynthesisRuntime.claudeCode.isAvailable)
        XCTAssertTrue(SynthesisRuntime.codex.isAvailable)
        XCTAssertFalse(SynthesisRuntime.cowork.isAvailable)
        XCTAssertFalse(SynthesisRuntime.customMCP.isAvailable)
        XCTAssertEqual(SynthesisRuntime.claudeCode.displayName, "Claude Code")
        XCTAssertNotNil(SynthesisRuntime.cowork.comingSoonNote)
        XCTAssertNil(SynthesisRuntime.claudeCode.comingSoonNote)
        XCTAssertEqual(SynthesisRuntime.allCases.count, 4)
    }
    func test_claudeCodeInvocation() {
        let exe = URL(fileURLWithPath: "/usr/local/bin/claude")
        let skills = URL(fileURLWithPath: "/Users/x/.claude/skills")
        let inv = SynthesisRuntime.claudeCode.invocation(executable: exe, skillsDir: skills, prompt: "PROMPT", lastMessageFile: URL(fileURLWithPath: "/tmp/x.txt"))
        XCTAssertEqual(inv.executable, exe)
        XCTAssertEqual(inv.arguments, ["--dangerously-skip-permissions", "--add-dir", skills.path, "-p", "PROMPT"])
        if case .lastStdoutLine = inv.finalStatusSource {} else { XCTFail("expected lastStdoutLine") }
    }
    func test_codexInvocation() {
        let exe = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let skills = URL(fileURLWithPath: "/Users/x/.claude/skills")
        let last = URL(fileURLWithPath: "/tmp/last.txt")
        let inv = SynthesisRuntime.codex.invocation(executable: exe, skillsDir: skills, prompt: "PROMPT", lastMessageFile: last)
        XCTAssertEqual(inv.arguments, ["exec", "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check",
                                       "--add-dir", skills.path, "-o", last.path, "PROMPT"])
        if case .file(let u) = inv.finalStatusSource { XCTAssertEqual(u, last) } else { XCTFail("expected .file") }
    }
    func test_preflight_mcpListCheck() {
        XCTAssertTrue(SynthesisRuntime.claudeCode.mcpListLacksScreenpipe(in: "no mcps here"))
        XCTAssertFalse(SynthesisRuntime.claudeCode.mcpListLacksScreenpipe(in: "screenpipe   npx -y screenpipe-mcp"))
        XCTAssertEqual(SynthesisRuntime.codex.mcpAddCommand, "codex mcp add screenpipe -- npx -y screenpipe-mcp")
        XCTAssertEqual(SynthesisRuntime.claudeCode.mcpAddCommand, "claude mcp add screenpipe -s user -- npx -y screenpipe-mcp")
    }
}
```

- [ ] **Step 2: Run test, expect FAIL.**
- [ ] **Step 3: Implement** (`SynthesisRuntime.swift`)

```swift
import Foundation

/// Which CLI Mengo Flow uses to turn a recording into a skill.
enum SynthesisRuntime: String, Codable, CaseIterable, Identifiable {
    case claudeCode, codex, cowork, customMCP
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .cowork:     return "Claude Cowork"
        case .customMCP:  return "Bring your own LLM (MCP)"
        }
    }
    var isAvailable: Bool { self == .claudeCode || self == .codex }
    var comingSoonNote: String? {
        switch self {
        case .cowork:    return "Coming soon."
        case .customMCP: return "Coming soon — point Mengo at your own model via an MCP server."
        default:         return nil
        }
    }

    /// Where the final `{"status":...}` JSON line is read from after the subprocess exits.
    enum FinalStatusSource { case lastStdoutLine; case file(URL) }
    struct Invocation { let executable: URL; let arguments: [String]; let finalStatusSource: FinalStatusSource }

    /// Builds the spawn for this runtime. `lastMessageFile` is only used by `.codex` (`-o`).
    func invocation(executable: URL, skillsDir: URL, prompt: String, lastMessageFile: URL) -> Invocation {
        switch self {
        case .claudeCode:
            return .init(executable: executable,
                         arguments: ["--dangerously-skip-permissions", "--add-dir", skillsDir.path, "-p", prompt],
                         finalStatusSource: .lastStdoutLine)
        case .codex:
            return .init(executable: executable,
                         arguments: ["exec", "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check",
                                     "--add-dir", skillsDir.path, "-o", lastMessageFile.path, prompt],
                         finalStatusSource: .file(lastMessageFile))
        case .cowork, .customMCP:
            // Not reachable in practice (the picker disables these); fall back to Claude Code's shape.
            return SynthesisRuntime.claudeCode.invocation(executable: executable, skillsDir: skillsDir, prompt: prompt, lastMessageFile: lastMessageFile)
        }
    }

    var versionArguments: [String] { self == .codex ? ["--version"] : ["--version"] }
    var mcpListArguments: [String] { self == .codex ? ["mcp", "list"] : ["mcp", "list"] }
    func mcpListLacksScreenpipe(in output: String) -> Bool { !output.lowercased().contains("screenpipe") }
    var mcpAddCommand: String {
        switch self {
        case .codex: return "codex mcp add screenpipe -- npx -y screenpipe-mcp"
        default:     return "claude mcp add screenpipe -s user -- npx -y screenpipe-mcp"
        }
    }

    /// Where to look for this runtime's executable (mirrors `FlowController.findClaude()`).
    var executableSearchPaths: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .codex:
            return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex", "\(home)/bin/codex"]
        default:
            return ["/usr/local/bin/claude", "/opt/homebrew/bin/claude",
                    "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude", "\(home)/.local/bin/claude"]
        }
    }
    func findExecutable() -> URL? {
        for p in executableSearchPaths where FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }
}
```

- [ ] **Step 4: Run test, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: SynthesisRuntime — runtime enum + per-runtime invocation/preflight builders (TDD)"`

---

### Task B2: `SettingsStore`

**Files:**
- Create: `Sources/MengoDesktop/SettingsStore.swift`
- Test: `Tests/MengoDesktopTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MengoDesktop

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "settings-\(UUID().uuidString)")! }
    final class StubLoginItem: LoginItemControlling, @unchecked Sendable {
        var enabled = false; var failOnRegister = false
        func register() throws { if failOnRegister { throw NSError(domain: "x", code: 1) }; enabled = true }
        func unregister() throws { enabled = false }
        var isEnabled: Bool { enabled }
    }
    func test_defaults() {
        let s = SettingsStore(defaults: defaults(), loginItem: StubLoginItem())
        XCTAssertEqual(s.synthesisRuntime, .claudeCode)
        XCTAssertTrue(s.startRecordingOnLaunch)
        XCTAssertFalse(s.openAtLogin)
    }
    func test_persistsRuntimeAndStartFlag() {
        let d = defaults()
        let s1 = SettingsStore(defaults: d, loginItem: StubLoginItem())
        s1.synthesisRuntime = .codex; s1.startRecordingOnLaunch = false
        let s2 = SettingsStore(defaults: d, loginItem: StubLoginItem())
        XCTAssertEqual(s2.synthesisRuntime, .codex)
        XCTAssertFalse(s2.startRecordingOnLaunch)
    }
    func test_openAtLogin_togglesBackend() {
        let li = StubLoginItem()
        let s = SettingsStore(defaults: defaults(), loginItem: li)
        s.openAtLogin = true; XCTAssertTrue(li.isEnabled); XCTAssertTrue(s.openAtLogin)
        s.openAtLogin = false; XCTAssertFalse(li.isEnabled)
    }
    func test_openAtLogin_registerFailure_setsErrorAndReverts() {
        let li = StubLoginItem(); li.failOnRegister = true
        let s = SettingsStore(defaults: defaults(), loginItem: li)
        s.openAtLogin = true
        XCTAssertFalse(s.openAtLogin); XCTAssertNotNil(s.loginItemError)
    }
}
```

- [ ] **Step 2: Run test, expect FAIL.**
- [ ] **Step 3: Implement** (`SettingsStore.swift`)

```swift
import Foundation
import Observation
import ServiceManagement

/// The "open at login" backend, abstracted for tests.
protocol LoginItemControlling: Sendable {
    func register() throws
    func unregister() throws
    var isEnabled: Bool { get }
}
struct SMLoginItem: LoginItemControlling {
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
}

@Observable
@MainActor
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginItem: LoginItemControlling
    private(set) var loginItemError: String?

    private enum Keys { static let runtime = "synthesisRuntime"; static let startRec = "startRecordingOnLaunch" }

    init(defaults: UserDefaults = .standard, loginItem: LoginItemControlling = SMLoginItem()) {
        self.defaults = defaults; self.loginItem = loginItem
        AppDelegate.sharedSettings = self
    }

    var synthesisRuntime: SynthesisRuntime {
        get { (defaults.string(forKey: Keys.runtime)).flatMap(SynthesisRuntime.init(rawValue:)) ?? .claudeCode }
        set { defaults.set(newValue.rawValue, forKey: Keys.runtime) }
    }
    var startRecordingOnLaunch: Bool {
        get { defaults.object(forKey: Keys.startRec) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.startRec) }
    }
    var openAtLogin: Bool {
        get { loginItem.isEnabled }
        set {
            loginItemError = nil
            do { try newValue ? loginItem.register() : loginItem.unregister() }
            catch { loginItemError = "Couldn't \(newValue ? "enable" : "disable") launch-at-login — move Mengo Desktop to your Applications folder and try again." }
        }
    }
}
```

> Note: `synthesisRuntime` / `startRecordingOnLaunch` are computed over `UserDefaults` — `@Observable` won't auto-track those (no stored property). For the Settings UI to react, either (a) mirror them into `@ObservationIgnored` stored backing vars that the setters also update, or (b) keep them as plain stored `var`s loaded in `init` and `didSet { defaults.set(...) }`. **Use (b)** — simpler and observable. Rewrite: `var synthesisRuntime: SynthesisRuntime { didSet { defaults.set(synthesisRuntime.rawValue, forKey: Keys.runtime) } }` initialised in `init` from defaults; same for `startRecordingOnLaunch`. `openAtLogin` stays a computed mirror of `loginItem` (toggling it is rare and the Settings view can read `loginItem.isEnabled` fresh; if the toggle needs to animate, add a `@ObservationIgnored private var openAtLoginCache` updated in the setter and returned by the getter). Update the tests to match if the persistence semantics change (they shouldn't — set then re-init still reads the persisted value).

- [ ] **Step 4: Run test, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: SettingsStore — runtime/start-recording/open-at-login (TDD)"`

---

### Task B3: `FlowController` — runtime-aware synthesis + `findCodex` + generalized preflight

**Files:**
- Modify: `Sources/MengoDesktop/FlowController.swift`
- Test: `Tests/MengoDesktopTests/FlowControllerTests.swift`

- [ ] **Step 1: Extend the tests** — add to `FlowControllerTests`:
  - Give `makeController` an optional `settings: SettingsStore` param (default a fresh `SettingsStore(defaults: UserDefaults(suiteName: "fc-\(UUID())")!, loginItem: ...)` with `.claudeCode`) and an `account: AccountStore?` param (default a stub signed-in Pro account — so existing tests are unaffected by gating). Pass them into `FlowController.init`.
  - New test `test_synthesize_codexRuntime_issuesCodexCommand`: set `settings.synthesisRuntime = .codex`, point `claudeExecutable`/the codex executable at `/bin/echo`-ish stubs (or just assert via a recording `SynthesisRunning` stub that captures `command`/`arguments` — extend `StubSynthesis` to record the last call) — after `start()`+`stop()`, assert `stub.lastArguments?.first == "exec"` and the command path ends in `codex`. (The Claude tests already cover the `.claudeCode` path; they must still pass unchanged.)
  - `test_preflight_runtimeNotFound`: with `settings.synthesisRuntime = .codex` and no codex executable discovered (inject `codexExecutable: nil`), `preflight()` returns `.runtimeNotFound(.codex)`.

```swift
// example shape for the recording stub:
final class RecordingSynthesis: SynthesisRunning, @unchecked Sendable {
    var result: SynthesisResult = .failure(message: "stub")
    private(set) var lastCommand: URL?; private(set) var lastArguments: [String]?
    func run(command: URL, arguments: [String], environment: [String:String]?, logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult {
        lastCommand = command; lastArguments = arguments; return result
    }
}
```

- [ ] **Step 2: Run new tests, expect FAIL.**
- [ ] **Step 3: Implement** in `FlowController.swift`:
  - `enum PreflightFailure: Equatable { case screenpipeNotRunning, audioPaused, runtimeNotFound(SynthesisRuntime), runtimeMCPNotConfigured(SynthesisRuntime) }` (replacing `claudeNotFound`/`claudeMCPNotConfigured`).
  - Inject `private let settings: SettingsStore` and `private weak var account: AccountStore?`; thread both through `init` and `live(...)`. Replace the stored `claudeExecutable: URL?` with on-demand discovery: `private func runtimeExecutable(for r: SynthesisRuntime) -> URL? { r.findExecutable() }` (still injectable for tests via a closure: `private let executableOverride: (SynthesisRuntime) -> URL?`, default `{ $0.findExecutable() }`).
  - `preflight()` — same screenpipe/audio checks, then: `let r = settings.synthesisRuntime; guard let exe = runtimeExecutable(for: r) else { return .runtimeNotFound(r) }; if !r.isAvailable { return .runtimeNotFound(r) }; if await mcpListLacksScreenpipe(executable: exe, runtime: r) { return .runtimeMCPNotConfigured(r) }; return nil`. Generalize `mcpListLacksScreenpipe` to take the executable + runtime and run `<exe> mcp list`.
  - `synthesize(manifestURL:)` — replace the hardcoded `claude` build:
    ```swift
    let r = settings.synthesisRuntime
    guard let exe = runtimeExecutable(for: r), r.isAvailable else { flowState = .error("\(r.displayName) CLI not found."); return }
    let logURL = Log.synthesisLogURL(id: UUID().uuidString)
    let lastMsg = Log.directory.appendingPathComponent("codex-last-\(UUID().uuidString).txt")
    let prompt = synthesisPrompt.replacingOccurrences(of: "$MANIFEST_PATH", with: manifestURL.path)
    var env = ProcessInfo.processInfo.environment
    env["SCREENPIPE_API_KEY"] = screenpipeToken
    let home = NSHomeDirectory()
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(home)/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
    let inv = r.invocation(executable: exe, skillsDir: outputDir, prompt: prompt, lastMessageFile: lastMsg)
    do {
        let result = try await synthesis.run(command: inv.executable, arguments: inv.arguments, environment: env, logFile: logURL, timeoutSeconds: 300)
        // ... handle .success/.failure exactly as today ...
    } catch { ... }
    ```
    For Codex, the `SynthesisRunner` already tees stdout/stderr to `logFile` and returns a `SynthesisResult` parsed from the last stdout line — but Codex's machine-readable result is in `lastMsg` (via `-o`). **Decision:** keep the `SynthesisRunner` contract (parse last stdout line) and have the synthesis prompt instruct the agent to *also print* the `{"status":...}` line to stdout as its final message (which `codex exec` does — its last assistant message goes to stdout *and* to `-o`). So in practice `SynthesisRunner.run` works for both runtimes without change; the `-o` file is belt-and-suspenders (you may parse it as a fallback if the stdout parse fails — optional, note it). If `codex exec` does NOT echo the final message to stdout in your CLI version, then in `synthesize()` branch on `inv.finalStatusSource`: for `.file(let u)`, after the process exits, read `u` and parse it with `SynthesisRunner.parseLastStatusLine(_:)` (already a pure function). Implement the `.file` branch.
  - The default preflight alert (`presentDefaultPreflightAlert`) — update the `.runtimeNotFound` / `.runtimeMCPNotConfigured` cases to name the runtime and show `runtime.mcpAddCommand` (with the [Copy] button) / the install hint.
  - `live(...)` builds `executableOverride: { $0.findExecutable() }`.

- [ ] **Step 4: Run all `FlowControllerTests`, expect PASS** (existing Claude tests unchanged + the new Codex/preflight ones green).
- [ ] **Step 5: `swift test` (full suite) — green.**
- [ ] **Step 6: Commit** — `git commit -am "MengoDesktop: runtime-aware synthesis — Codex via codex exec, generalized preflight (TDD)"`

---

### Task B4: `SettingsPane`

**Files:**
- Create: `Sources/MengoDesktop/SettingsPane.swift`

(No unit test — manual checklist. Build must compile.)

- [ ] **Step 1: Implement** (`SettingsPane.swift`) — `struct SettingsPane: View { let account: AccountStore; let settings: SettingsStore; let recorder: RecorderController; let flow: FlowController; @State private var refreshing = false; ... }`. Body: a `ScrollView` (so the window stays resizable) containing a left-aligned `VStack(spacing: 22)` with `.padding(28)`, dark/orange palette like the other panes, with these sections (each: a `Theme.headline` title, then content):

  1. **Account** —
     - If `account.account` is set: `Text(a.email)`, a plan badge (`a.plan == .pro ? "Pro" : "Free"` styled — orange capsule for Pro, grey for Free). If Free: a `Text("\(flow.library.filter(\.exists).count) of \(account.flowLimit ?? 3) flows used")` line + a `Button("Upgrade to Pro") { Task { NSWorkspace.shared.open(await account.webURL(path: "/upgrade")) } }` (`.borderedProminent`, `.tint(Theme.accent)`). If Pro: a `Button("Manage account") { Task { NSWorkspace.shared.open(await account.webURL(path: "/account")) } }` (`.bordered`).
     - A `Button("Refresh now") { refreshing = true; Task { await account.refresh(); refreshing = false } }` (`.bordered`, shows a small `ProgressView` while `refreshing`).
     - A `Button("Sign out") { account.signOut() }` (`.plain`, `.foregroundStyle(Theme.stopped)`).
  2. **Synthesis model** — a vertical radio list over `SynthesisRuntime.allCases`: each row is a `Button` (or `Toggle`-as-radio) showing `runtime.displayName`; selected one gets a filled circle / orange highlight; disabled rows (`!runtime.isAvailable`) are greyed and show `runtime.comingSoonNote` as a caption and are non-tappable; tapping an available row sets `settings.synthesisRuntime = runtime`. Below the list: `Text("Mengo Flow uses this to turn recordings into reusable skills. Claude Code and Codex are configured automatically, and the screenpipe MCP is wired into whichever you pick.").font(Theme.caption).foregroundStyle(Theme.mutedText)`.
  3. **Startup** — `Toggle("Open Mengo Desktop at login", isOn: Binding(get: { settings.openAtLogin }, set: { settings.openAtLogin = $0 }))`; `Toggle("Start recording when Mengo opens", isOn: Binding(get: { settings.startRecordingOnLaunch }, set: { settings.startRecordingOnLaunch = $0 }))`. If `settings.loginItemError != nil`, show it as a `Theme.stopped` caption under the first toggle. Style toggles to fit the dark palette (`.toggleStyle(.switch)`, `.tint(Theme.accent)`).
  4. **Logs & data** — four `Button`s (`.plain`, `Theme.accent`, with SF Symbols): "Open recorder log" → `NSWorkspace.shared.open(recorder.recorderLogURL)`; "Open Flow log" → `NSWorkspace.shared.open(Log.directory.appendingPathComponent("flow.log"))` — wait: `Log.fileURL` is `app.log`, and Flow logs go there too via the redirected stdout; use `Log.fileURL` and label it "Open app log". (There's no separate `flow.log` in V2 — it folded into `app.log`. Label accordingly: "Open Mengo log".) ; "Reveal recordings folder" → `NSWorkspace.shared.open(recorder.dataFolderURL)`; "Reveal Mengo data folder" → `NSWorkspace.shared.open(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MengoDesktop"))`.

  Match `MemoryPane`'s structure: `ScrollView { VStack(alignment: .leading, spacing: 22) { ...sections... }.padding(28).frame(maxWidth: .infinity, alignment: .leading) }.background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))`.

- [ ] **Step 2: `swift build` — compile.**
- [ ] **Step 3: Commit** — `git commit -am "MengoDesktop: SettingsPane — account, synthesis model, startup, logs"`

---

### Task B5: Wire `SettingsStore` + `SettingsPane` into the app

**Files:**
- Modify: `Sources/MengoDesktop/MengoDesktopApp.swift`, `Sources/MengoDesktop/MainWindowView.swift`

- [ ] **Step 1:** In `MengoDesktopApp.init()`: `let st = SettingsStore()` then `_settings = State(initialValue: st)` (after `Log.bootstrap()` so `AppDelegate.sharedSettings` is set early). Build `FlowController.live(recorder: rec, hud: h, account: acct, settings: st, notify: …)` (extend `live`'s signature). Pass `settings` (and `account`) into `MainWindowView` and `MenuBarContent`.
- [ ] **Step 2:** In `MainWindowView`, add `let account: AccountStore` and `let settings: SettingsStore` props; in the `detail:` switch add `case .settings: SettingsPane(account: account, settings: settings, recorder: recorder, flow: flow)` and remove `.settings` from the `default: ComingSoonPane` fallthrough.
- [ ] **Step 3:** Confirm the recorder-start gating from A6 now uses the real `settings.startRecordingOnLaunch`.
- [ ] **Step 4: `swift build` + `swift test` — green. Manual:** `MENGO_DEV_ACCOUNT=free swift run MengoDesktop` → Settings tab shows the four sections; toggling "Start recording when Mengo opens" off, quit, relaunch → recorder idle; picking Codex in the model picker then recording a real task synthesizes via `codex exec`.
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: wire SettingsStore + SettingsPane (replaces the .settings placeholder)"`

---

## Part C — Gating, sidebar reorg, purchase, free-flow counter

### Task C1: Flow-limit gate in `FlowController.save()`

**Files:**
- Modify: `Sources/MengoDesktop/FlowController.swift`
- Test: `Tests/MengoDesktopTests/FlowControllerTests.swift`

- [ ] **Step 1: Extend the tests:**
  - Add a `StubAccount` test double or reuse `AccountStore` with `MENGO_DEV_ACCOUNT` not viable in-process (env) — instead, since `FlowController` only needs `isPro` + `flowLimit` + the upgrade-URL action, **inject those as a small value/closure** rather than the whole `AccountStore`: `init(... entitlement: () -> (isPro: Bool, flowLimit: Int?) , onFlowLimitReached: @MainActor () -> Void, ...)`. (Or pass `weak var account: AccountStore?` and read `account?.isPro ?? false` — but then tests need a real `AccountStore`; `AccountStore` with a stub API + `MENGO_DEV_ACCOUNT="free"` env is awkward in-process. Cleanest: `FlowController` takes `entitlement: @MainActor () -> Entitlement` where `struct Entitlement { let isPro: Bool; let flowLimit: Int? }`; `live(...)` passes `{ Entitlement(isPro: account.isPro, flowLimit: account.flowLimit) }`.)
  - `test_save_blockedAtFreeLimit`: controller with `entitlement = { Entitlement(isPro: false, flowLimit: 3) }`; pre-populate the `FlowLibrary` with 3 existing flows (create 3 temp dirs + `library.add(...)`); drive `start()` → `stop()` (success) → `.reviewing`; `save(name:"x", ...)` → assert the library still has 3 entries (not 4), `flowState` is still `.reviewing`, and `onFlowLimitReached` was called.
  - `test_save_allowedUnderLimit`: 2 existing flows, free, limit 3 → `save` adds the 3rd, `.idle`.
  - `test_save_allowedWhenPro`: 5 existing flows, `isPro: true` → `save` adds the 6th.
  - Existing `test_save_renamesSlugDir_andUpdatesLibrary` etc. must still pass — they use the default `entitlement = { Entitlement(isPro: true, flowLimit: nil) }`.

- [ ] **Step 2: Run new tests, expect FAIL.**
- [ ] **Step 3: Implement** — in `FlowController`:
  - `struct Entitlement { let isPro: Bool; let flowLimit: Int? }`; `init` gains `entitlement: @escaping @MainActor () -> Entitlement = { Entitlement(isPro: true, flowLimit: nil) }` and `onFlowLimitReached: @escaping @MainActor () -> Void = { FlowController.presentDefaultFlowLimitAlert() }`. Store both.
  - In `save(name:description:parameters:)`, right after `guard case .reviewing(let dir) = flowState else { return }`:
    ```swift
    let ent = entitlement()
    if !ent.isPro, let limit = ent.flowLimit {
        let kept = libraryStore.load().filter { FileManager.default.fileExists(atPath: $0.path.path) }.count
        // `dir` is the *current* skill dir; it's not yet a saved/renamed entry, so it doesn't count toward `kept`.
        if kept >= limit { onFlowLimitReached(); return }
    }
    ```
    (then the existing rename + library-update logic.)
  - `presentDefaultFlowLimitAlert()` — NSAlert: "You've used all 3 free flows", "Upgrade to Mengo Pro for unlimited flows, or delete one from the Library to make room." Buttons: "Upgrade…" (→ `Task { NSWorkspace.shared.open(await AppDelegate.sharedAccount?.webURL(path: "/upgrade") ?? URL(string: "https://mengo.ai/upgrade")!) }`), "OK". (Static so it can be the default; it reaches the account via `AppDelegate.sharedAccount`.)
  - `live(...)` passes `entitlement: { Entitlement(isPro: account.isPro, flowLimit: account.flowLimit) }`.

- [ ] **Step 4: Run all `FlowControllerTests`, expect PASS.**
- [ ] **Step 5: `swift test` — green. Commit** — `git commit -am "MengoDesktop: gate Save behind the ≤3 free-flow limit (TDD)"`

---

### Task C2: Sidebar reorg — Settings pinned bottom, Purchase + counter above (Free only)

**Files:**
- Modify: `Sources/MengoDesktop/MainWindowView.swift`

- [ ] **Step 1: Implement** — in `MainWindowView`'s `NavigationSplitView` sidebar `VStack`, replace the single `ForEach(SidebarSection.allCases) { sidebarRow($0) }` with:
  ```swift
  VStack(spacing: 0) {
      wordmark
      ScrollView {
          VStack(spacing: 2) {
              ForEach(SidebarSection.allCases.filter { $0 != .settings }) { sidebarRow($0) }
          }
          .padding(.horizontal, 8).padding(.top, 4)
      }
      Spacer(minLength: 8)
      VStack(spacing: 8) {
          if !account.isPro {
              Button { Task { NSWorkspace.shared.open(await account.webURL(path: "/upgrade")) } } label: {
                  Label("Purchase Mengo Pro", systemImage: "sparkles").frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent).tint(Theme.accent)
              Text("\(flow.library.filter(\.exists).count) of \(account.flowLimit ?? 3) free flows used")
                  .font(Theme.caption).foregroundStyle(Theme.mutedText)
          }
          sidebarRow(.settings)
      }
      .padding(.horizontal, 8).padding(.bottom, 10)
  }
  .background(Theme.windowBackground)
  .frame(minWidth: 200)
  ```
  (`MainWindowView` already has `account` + `flow` from B5/A6; if not, add them.)

- [ ] **Step 2: `swift build` — compile. Manual:** `MENGO_DEV_ACCOUNT=free swift run MengoDesktop` → Settings is at the bottom, the Purchase button + "N of 3 free flows used" sit above it; `MENGO_DEV_ACCOUNT=pro` → no Purchase block, Settings still at the bottom.
- [ ] **Step 3: Commit** — `git commit -am "MengoDesktop: pin Settings to the sidebar bottom; Purchase + free-flow counter above it for Free users"`

---

### Task C3: Menu-bar "Upgrade to Mengo Pro…" for Free users

**Files:**
- Modify: `Sources/MengoDesktop/MenuBarContent.swift`

- [ ] **Step 1: Implement** — (if not already done in A7) when signed in and `!account.isPro`, add `Button("Upgrade to Mengo Pro…") { Task { NSWorkspace.shared.open(await account.webURL(path: "/upgrade")) } }` just above the "Settings…" item in the bottom group.
- [ ] **Step 2: `swift build` — compile. Commit** — `git commit -am "MengoDesktop: menu-bar 'Upgrade to Mengo Pro…' item for Free users"`

---

### Task C4: Manual smoke checklist

**Files:**
- Create: `docs/manual-smoke-tests/mengo-phase-4-account-licensing.md`

- [ ] **Step 1: Write the checklist** — adapt the "Manual smoke checklist" section verbatim from the spec ([`2026-05-12-mengo-phase-4-account-licensing-design.md`](../specs/2026-05-12-mengo-phase-4-account-licensing-design.md)), formatted as a `- [ ]` checklist with a "Build & tests (scriptable)" block (`swift build`, `swift test`, `./build-mengo.sh` + `codesign --verify`) and the app-behaviour blocks (sign-in hard wall + `MENGO_DEV_ACCOUNT`; Free gating + counter + sidebar; Settings → model picker + Codex; Settings → startup toggles; Settings → logs; sign out; deep links; build registers `mengo://`). Note that the mengo.ai endpoints / Stripe are out of scope and the account paths use `MENGO_DEV_ACCOUNT` until the website ships.
- [ ] **Step 2: Commit** — `git commit -am "MengoDesktop: Phase 4 manual smoke checklist"`

---

## Finalize

- [ ] **`swift build` + `swift test` — full suite green.**
- [ ] **`./build-mengo.sh`** — produces `MengoDesktop.app` that codesigns cleanly; `open "mengo://refresh"` while it's running reaches the app (no crash); `MENGO_DEV_ACCOUNT=pro open MengoDesktop.app`-equivalent path works (set the env, then `open` — or launch the binary directly with the env var).
- [ ] **Walk the manual smoke checklist** (`docs/manual-smoke-tests/mengo-phase-4-account-licensing.md`) — at minimum: sign-in hard wall, `MENGO_DEV_ACCOUNT=free` gating + counter + sidebar layout, Settings model picker (Codex synthesis), startup toggles, logs buttons, sign out.
- [ ] **Update memory** — `~/.claude/projects/-Users-kylebell-screenpipe/memory/project_mengo_desktop_v2.md`: Phase 4 (account & licensing) shipped; key facts (magic-link sign-in / hard wall / offline-tolerant; `MENGO_DEV_ACCOUNT` dev hatch; Codex runtime wired; Stripe + mengo.ai endpoints are the website owner's job — contract documented in the Phase 4 spec).
- [ ] **Finish the branch** — invoke `superpowers:finishing-a-development-branch` (merge to `main` or open a PR per the user's preference).

---

## Self-Review

- **Spec coverage:** Account/sign-in (magic-link, hard wall, offline-tolerant) → A1–A6, AccountStore tests. Keychain → A1. `mengo://` scheme + deep links → A2, A6. Free/Pro gating (≤3 flows, Save block, upgrade alert) → C1. Sidebar reorg + Purchase + counter → C2. Settings pane (account / synthesis model / startup / logs) → B4, B5. Runtime selector + Codex working + Cowork/custom disabled → B1, B3, B4. Startup options → B2, B5, A6. Logs → B4. Menu-bar signed-out + Upgrade item → A7, C3. mengo.ai contract → documented in the spec; nothing to build here. Smoke checklist → C4. **No gaps.**
- **Placeholders:** The `synthesisRuntime`/`startRecordingOnLaunch` storage approach has a "use option (b)" note rather than committed code in B2 — acceptable (it's a clearly-specified choice with the rewrite spelled out), but the executor should commit to option (b) and update the snippet. The `signOut()` server call is flagged as a placeholder for a future endpoint with an explicit "drop this line if you prefer" — acceptable. The B3 `synthesize()` body is given as a guided diff against the existing method rather than the full rewritten method — acceptable given the existing method is short and in-repo; the executor should produce the full method. No "TBD"/"TODO".
- **Type consistency:** `Account`/`Plan` (A3) used by `AccountStore` (A4), `SettingsPane` (B4), `FlowController.Entitlement` (C1). `SecretStore`/`SecretKeys.sessionToken` (A1) used by `AccountStore` (A4). `MengoLink`/`MengoURL.parse` (A2) used by `MengoDesktopApp` (A6). `SynthesisRuntime` (B1) used by `SettingsStore` (B2), `FlowController` (B3), `SettingsPane` (B4). `PreflightFailure` renamed cases (`runtimeNotFound`/`runtimeMCPNotConfigured`) — used consistently in B3 + the alert. `AppDelegate.sharedAccount` (A4) / `sharedSettings` (B2) — referenced in A6, A7, C1, C3. `SettingsStore.openAtLogin`/`startRecordingOnLaunch`/`synthesisRuntime`/`loginItemError` — consistent across B2, B4, A6. `FlowController.live(...)` signature grows `account:`/`settings:` — consistent in A6, B5, C1. **Consistent.**
