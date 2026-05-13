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
    func test_resetToSignedOut_fromAwaitingLink() async {
        let s = make(); await s.sendMagicLink(email: "x@y.com")
        s.resetToSignedOut(); XCTAssertEqual(s.state, .signedOut)
    }
}
