import SwiftUI

/// The placeholder shown in the main window's detail column for every
/// sidebar section in Phase 1: a large glyph, the section name, which phase
/// fills it in, and a one-line blurb. Later phases swap real panes in.
struct ComingSoonPane: View {
    let section: SidebarSection

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)

            Text(section.displayName)
                .font(Theme.title)
                .foregroundStyle(Theme.primaryText)

            Text("Coming in Phase \(section.phase)")
                .font(Theme.headline)
                .foregroundStyle(Theme.secondaryText)

            Text(section.comingSoonBlurb)
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paneBackground)
    }
}
