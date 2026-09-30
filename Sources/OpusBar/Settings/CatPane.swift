import OpusBarCore
import SwiftUI

/// The cat's own pane: its coat, what it does in each state, and how it sits in the menu bar.
@MainActor
struct CatPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneTitle(title: "Cat", lead: "Dress up the cat. It changes everywhere at once: menu bar, session cards and here.")
            Tile {
                TileHeading(title: "Coat")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(CatCoat.allCases, id: \.self) { coat in
                        CoatCard(coat: coat, selected: preferences.coat == coat) { preferences.coat = coat }
                    }
                }
                .padding(.top, 6)
            }
            Tile {
                HStack {
                    TileHeading(title: "Poses", subtitle: "What the cat does in each state.")
                    Spacer()
                    Button("Reset to Defaults") { preferences.poses = .defaults }
                        .disabled(preferences.poses == .defaults)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.states, id: \.self) { state in
                        PoseRow(state: state, poses: $preferences.poses)
                    }
                }
                .padding(.top, 6)
            }
            Tile {
                TileHeading(title: "Menu bar")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        label("Size")
                        ChipPicker(options: MenuBarCatSize.allCases, selection: $preferences.menuBar.size) { $0.label }
                    }
                    GridRow {
                        label("With no sessions")
                        ChipPicker(options: EmptyMenuBarCat.allCases, selection: $preferences.menuBar.empty) { $0.label }
                    }
                    GridRow {
                        label("Pace")
                        ChipPicker(options: CatPace.allCases, selection: $preferences.menuBar.pace) { $0.label }
                    }
                    GridRow {
                        label("Badge")
                        Toggle("Show the count or ✓ on the cat", isOn: $preferences.menuBar.showsBadge)
                            .toggleStyle(.switch).tint(Theme.green).font(Theme.font(12, .regular))
                    }
                }
                .padding(.top, 6)
                Text("Pace only affects the menu bar cat, and even Normal stays at 4 frames a second or less. With Reduce Motion on, the cat always holds still.")
                    .font(Theme.font(11, .regular)).opacity(0.6).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            .id("menuBar") // `--scroll menuBar`
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.font(12, .regular)).opacity(0.72)
    }

    /// Loudest first, like the menu.
    private static let states: [SessionState] = [.needsAttention, .error, .working, .thinking, .done, .idle]
}

/// One state: its name, then each pose it may use, previewed live in that state's colour.
private struct PoseRow: View {
    let state: SessionState
    @Binding var poses: CatPoses

    var body: some View {
        HStack(spacing: 12) {
            Text(state.label).font(Theme.font(13, .medium)).frame(width: 90, alignment: .leading)
            ForEach(CatPoses.choices(for: state), id: \.self) { pose in
                let on = poses.pose(for: state) == pose
                Button { poses.set(pose, for: state) } label: {
                    HStack(spacing: 8) {
                        CatView(state: state, points: 32)
                            .environment(\.catPoses, Self.only(pose, for: state))
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12).fill(state.tileColor))
                        Text(pose.label).font(Theme.font(12, on ? .semibold : .regular)).lineLimit(1).fixedSize()
                    }
                    .padding(6)
                    .padding(.trailing, 6)
                    .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(on ? Theme.surface : Theme.canvas))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(on ? Theme.ink : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(state.label): \(pose.label)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private static func only(_ pose: CatPose, for state: SessionState) -> CatPoses {
        var poses = CatPoses()
        poses.set(pose, for: state)
        return poses
    }
}

/// One coat to pick: the cat trotting in that coat, its name, and a ring when it's the one worn.
private struct CoatCard: View {
    let coat: CatCoat
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 8) {
                // Sits still unless picked: 21 trotting cats at once would be a lot.
                CatView(state: selected ? .working : .idle, points: 32)
                    .environment(\.catCoat, coat)
                    .environment(\.catPoses, .defaults)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileLight.opacity(0.9)))
                Text(coat.label).font(Theme.font(12, selected ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(selected ? Theme.surface : Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(selected ? Theme.ink : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(coat.label) coat")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
