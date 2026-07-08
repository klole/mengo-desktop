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
            if let logo = Brand.logo {
                logo.resizable().scaledToFit().frame(width: 56, height: 56)
            }
            Text("Sign in to Mengo").font(Theme.title).foregroundStyle(Theme.primaryText)
            content
            if let err = account.lastError {
                Text(err).font(Theme.caption).foregroundStyle(Theme.stopped).multilineTextAlignment(.center)
            }
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
            Text("Hosted Mengo accounts are optional in this OSS preview. Sign in if you have an account, or continue locally to try Memory and Flow on this Mac.")
                .font(Theme.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder).focused($emailFocused)
                .onSubmit { if emailLooksValid { Task { await account.sendMagicLink(email: email) } } }
            Button("Email me a link") { Task { await account.sendMagicLink(email: email) } }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(!emailLooksValid)
            Button("Continue in local preview") { account.startLocalPreview(plan: .pro) }
                .buttonStyle(.bordered)
            Text("Local preview stores recordings and generated skills on this Mac. Hosted billing and account management are disabled.")
                .font(Theme.caption).foregroundStyle(Theme.mutedText).multilineTextAlignment(.center)
        case .awaitingLink(let sent):
            Text("Check your inbox").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Text("We sent a sign-in link to \(sent). Click it on this Mac to finish signing in.")
                .font(Theme.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            HStack {
                Button("Resend") { Task { await account.sendMagicLink(email: sent) } }.buttonStyle(.bordered)
                Button("Use a different email") {
                    email = ""
                    account.resetToSignedOut()
                }
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
