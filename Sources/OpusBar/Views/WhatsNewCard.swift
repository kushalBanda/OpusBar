import OpusBarCore
import SwiftUI

/// Shown once in the menu after an update: the cat, the new version, and its few headline changes,
/// which settle in one after the other (all at once with Reduce Motion). "Got it" clears it.
struct WhatsNewCard: View {
    let note: WhatsNew
    let fullNotes: () -> Void
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CatView(state: .done)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileLight))
            VStack(alignment: .leading, spacing: 6) {
                Text("Updated to \(note.version)").font(Theme.font(13, .semibold))
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(note.highlights.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("+").font(Theme.font(11, .semibold)).opacity(0.6)
                            Text(line).font(Theme.font(11, .regular)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(index < revealed ? 1 : 0)
                        .offset(y: index < revealed ? 0 : 4)
                    }
                }
                HStack(spacing: 8) {
                    Button("Got it", action: dismiss).buttonStyle(.borderedProminent).tint(Theme.onColor)
                    Button("Full notes", action: fullNotes).buttonStyle(.borderless).foregroundStyle(Theme.onColor)
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .foregroundStyle(Theme.onColor)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.green))
        .accessibilityElement(children: .contain)
        .task {
            guard !reduceMotion else { revealed = note.highlights.count; return }
            for step in 1...max(note.highlights.count, 1) {
                try? await Task.sleep(for: .milliseconds(step == 1 ? 250 : 110))
                withAnimation(.easeOut(duration: 0.28)) { revealed = step }
            }
        }
    }
}
