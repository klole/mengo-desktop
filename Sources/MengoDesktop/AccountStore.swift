import Foundation
import Observation
import AppKit

enum AccountState: Equatable {
    case signedOut
    case awaitingLink(email: String)
    case verifying
    case signedIn(Account)
}

/// Owns the Mengo account: local preview mode, magic-link sign-in, cached entitlement.
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
    @ObservationIgnored private let logAccountState: Bool

    init(api: MengoAPI = MengoAPIClient(),
         secrets: SecretStore = KeychainStore(),
         cacheURL: URL = AccountStore.defaultCacheURL(),
         now: @escaping () -> Date = Date.init,
         env: [String: String] = ProcessInfo.processInfo.environment) {
        self.api = api; self.secrets = secrets; self.cacheURL = cacheURL; self.now = now
        self.logAccountState = env["MENGO_LOG_ACCOUNT_STATE"] == "1"

        let preview = env["MENGO_PREVIEW_ACCOUNT"]?.lowercased() ?? env["MENGO_DEV_ACCOUNT"]?.lowercased()
        let disableCachedAccount = env["MENGO_DISABLE_CACHED_ACCOUNT"] == "1"
        if let preview, preview == "pro" || preview == "free" {
            startLocalPreview(plan: preview == "pro" ? .pro : .free)
        } else if !disableCachedAccount, secrets.get(SecretKeys.sessionToken) != nil, let cached = loadCachedAccount() {
            state = .signedIn(cached)
            logState("cached \(cached.plan.rawValue)")
            Task { await refresh() }
        } else {
            state = .signedOut
            logState("signed-out")
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
    var isLocalPreview: Bool {
        guard case .signedIn(let account) = state else { return false }
        return secrets.get(SecretKeys.sessionToken) == nil && account.email.hasSuffix("@preview.mengo.local")
    }

    func startLocalPreview(plan: Plan = .pro) {
        secrets.delete(SecretKeys.sessionToken)
        try? FileManager.default.removeItem(at: cacheURL)
        state = .signedIn(Account(email: "local@preview.mengo.local",
                                  plan: plan,
                                  flowLimit: plan == .pro ? nil : 3,
                                  validatedAt: now()))
        lastError = nil
        logState("local-preview \(plan.rawValue)")
    }

    private func logState(_ value: String) {
        guard logAccountState else { return }
        Log.line("account state: \(value)")
    }

    func sendMagicLink(email: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = nil
        do { try await api.requestLink(email: email); state = .awaitingLink(email: email) }
        catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Couldn't send the sign-in link."
            state = .signedOut
        }
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
        secrets.delete(SecretKeys.sessionToken)
        try? FileManager.default.removeItem(at: cacheURL)
        state = .signedOut
    }

    func resetToSignedOut() {
        if case .awaitingLink = state { state = .signedOut; lastError = nil }
    }

    /// URL that opens `mengo.ai<path>` already-signed-in (via a one-time handoff code).
    /// Falls back to the bare URL if the handoff call fails.
    func webURL(path: String) async -> URL {
        let base = URL(string: "https://mengo.ai")!.appendingPathComponent(path)
        if isLocalPreview { return base }
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
