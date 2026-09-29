import AppKit
import OpusBarCore
import OpusBarWire
import SwiftUI

/// Agents pane: one tile per hooks file (each Claude profile, Codex), colored by status, with Connect/Disconnect.
/// Install and uninstall run only on the user's click.
@MainActor
struct AgentsSettingsView: View {
    @Bindable var model: AgentHooksModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                PaneTitle(title: "Agents", lead: "How OpusBar hears from your coding agents.")
                Spacer()
                Button("Refresh") { model.refresh() }
            }
            section(.claude,
                    blurb: "Adds a few hooks to each profile's settings.json so sessions report their state. Your own hooks stay, and the file is backed up first.") {
                Button("Add Profile Folder…") { model.addClaudeFolder() }
            }
            section(.codex,
                    blurb: "Adds OpusBar to hooks.json. Codex asks you to review new hooks: approve them in Codex with /hooks. Running sessions pick them up on restart.") {
                EmptyView()
            }
            if let error = model.lastError {
                Text(error).font(Theme.font(12, .regular)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
            }
            Tile {
                TileHeading(title: "pi and OMP",
                            subtitle: "Running sessions show up automatically. Live states for them come in a later update.")
            }
            .padding(.top, 12)
            Text("If OpusBar isn't running, the hook exits instantly and your agent carries on as normal.")
                .font(Theme.font(12, .regular)).opacity(0.5).padding(.top, 8)
        }
    }

    @ViewBuilder
    private func section(_ agent: AgentKind, blurb: String, @ViewBuilder footer: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TileHeading(title: agent.displayName, subtitle: blurb)
                .padding(.top, 12)
            let rows = model.rows(for: agent)
            if rows.isEmpty {
                Tile {
                    Text(agent == .codex ? "Codex not found (~/.codex doesn't exist)." : "No Claude profile folder found.")
                        .font(Theme.font(12, .regular)).opacity(0.72)
                }
            }
            ForEach(rows) { TargetTile(row: $0, model: model) }
            footer()
        }
    }
}

@MainActor
private struct TargetTile: View {
    let row: AgentHooksModel.Row
    let model: AgentHooksModel

    var body: some View {
        Tile(fill: fill, onColor: true) {
            HStack(alignment: .top, spacing: 14) {
                CatView(state: catState, points: 32)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileLight))
                VStack(alignment: .leading, spacing: 4) {
                    TileHeading(title: title, subtitle: subtitle)
                    Text(displayPath)
                        .font(.system(size: 11).monospaced())
                        .opacity(0.72)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if case .installed = row.status {
                        FlowPills(items: row.target.events.map(\.rawValue)).padding(.top, 6)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) { actions }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch row.status {
        case .installed:
            Button("Disconnect") { model.uninstall(row.target) }
            Button("Show Backups") { showBackups() }.buttonStyle(.link).foregroundStyle(Theme.onColor)
        case .notInstalled, .partial:
            Button("Connect") { model.install(row.target) }.buttonStyle(.borderedProminent).tint(Theme.onColor)
        case .unreadable:
            Button("Try Again") { model.refresh() }
            Button("Open File") { NSWorkspace.shared.open(row.target.fileURL) }
        }
        if row.target.claudeOrigin == .userAdded {
            Button("Forget Folder") { model.removeClaudeFolder(row.target) }
                .buttonStyle(.link).foregroundStyle(Theme.onColor)
        }
    }

    private var fill: Color {
        switch row.status {
        case .installed: Theme.green
        case .notInstalled, .partial: Theme.pink
        case .unreadable: Theme.red
        }
    }

    private var catState: SessionState {
        switch row.status {
        case .installed: .idle
        case .notInstalled, .partial: .needsAttention
        case .unreadable: .error
        }
    }

    private var title: String {
        let name = row.target.agent.displayName
        switch row.status {
        case .installed: return "Connected to \(name)"
        case .notInstalled: return "Not connected yet"
        case .partial: return "Partly connected"
        case .unreadable: return "Couldn't read \(row.target.fileURL.lastPathComponent)"
        }
    }

    private var subtitle: String {
        let origin: String = switch row.target.claudeOrigin {
        case .environment: " From CLAUDE_CONFIG_DIR."
        case .userAdded: " Folder you added."
        default: ""
        }
        switch row.status {
        case .installed:
            return "Sessions report their state live.\(origin)"
        case .notInstalled:
            return "Sessions still show up, without live states.\(origin)"
        case .partial(let missing):
            return "\(missing.count) event(s) missing. Connect again to repair.\(origin)"
        case .unreadable(let reason):
            return "It isn't valid JSON (\(reason)), so OpusBar left it untouched. Fix the file, then try again."
        }
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = row.target.fileURL.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func showBackups() {
        let dir = model.backupsDirectory(for: row.target)
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([row.target.fileURL])
        }
    }
}

/// Event name pills that wrap onto new lines.
private struct FlowPills: View {
    let items: [String]

    var body: some View {
        WrapLayout(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text(item).font(Theme.font(10, .regular))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.tileLight.opacity(0.55)))
            }
        }
    }
}

/// Left-to-right layout that wraps to the next line when a row is full.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
