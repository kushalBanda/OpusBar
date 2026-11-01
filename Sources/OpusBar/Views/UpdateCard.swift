import OpusBarCore
import SwiftUI

/// Shown in the menu while a newer release is on offer: the cat and the version. "Update and Relaunch"
/// installs it (at once when it is already downloaded); what changed shows on the card after the update.
/// "Later" hides this card until the next version; the footer row stays as the way back.
@MainActor
struct UpdateCard: View {
    let updater: Updater
    let release: UpdateRelease
    let later: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CatView(state: .needsAttention)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileLight))
            VStack(alignment: .leading, spacing: 6) {
                Text("OpusBar \(release.version.description) is out").font(Theme.font(13, .semibold))
                if case .failed(let message) = updater.state {
                    Text(message).font(Theme.font(11, .regular)).fixedSize(horizontal: false, vertical: true)
                }
                buttons
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(Theme.onColor)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.blue))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 8) {
            switch updater.state {
            case .installing:
                Button("Installing…") {}.buttonStyle(.borderedProminent).tint(Theme.onColor).disabled(true)
            case .failed:
                Button("Try Again") { updater.install() }.buttonStyle(.borderedProminent).tint(Theme.onColor)
                Button("Download from GitHub") { updater.openReleasePage() }.buttonStyle(.borderless).foregroundStyle(Theme.onColor)
            default:
                Button("Update and Relaunch") { updater.install() }.buttonStyle(.borderedProminent).tint(Theme.onColor)
            }
            Button("Later", action: later).buttonStyle(.borderless).foregroundStyle(Theme.onColor)
        }
    }
}
