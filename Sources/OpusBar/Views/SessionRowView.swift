import OpusBarCore
import SwiftUI

/// One session card. Needs-you and error cards fill yellow or red so they read from across the room.
struct SessionRowView: View {
    let session: Session
    let now: Date

    /// Charcoal text on brand fills (AA on yellow and red).
    private static let onColor = Color(red: 0.173, green: 0.18, blue: 0.165)
    private static let tileLight = Color(red: 1.0, green: 0.992, blue: 0.969)

    private var isLoud: Bool { session.state == .needsAttention || session.state == .error }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CatView(state: session.state)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(isLoud ? Self.tileLight : session.state.tileColor))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName).font(.body.weight(.semibold)).lineLimit(1)
                    if let branch = session.branch {
                        Text(branch).font(.caption).foregroundStyle(secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(detailLine).font(.caption).foregroundStyle(secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Self.elapsed(from: session.stateSince, to: now))
                .font(.caption.monospacedDigit())
                .foregroundStyle(secondary)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(isLoud ? AnyShapeStyle(Self.onColor) : AnyShapeStyle(.primary))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(isLoud ? session.state.tileColor : Color.primary.opacity(0.05)))
        .help("\(session.cwd)\nSubagents: \(session.subagents)")
        .accessibilityElement(children: .combine)
    }

    private var secondary: AnyShapeStyle {
        isLoud ? AnyShapeStyle(Self.onColor.opacity(0.72)) : AnyShapeStyle(.secondary)
    }

    private var detailLine: String {
        let extras = [session.detail, session.subagents > 0 ? "\(session.subagents) subagent\(session.subagents == 1 ? "" : "s")" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
        return extras.isEmpty ? session.state.label : "\(session.state.label) · \(extras)"
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds >= 3600 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds)s"
    }
}
