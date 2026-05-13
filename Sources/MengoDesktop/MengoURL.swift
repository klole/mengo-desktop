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
