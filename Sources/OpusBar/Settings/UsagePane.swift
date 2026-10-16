import Charts
import OpusBarCore
import OpusBarWire
import SwiftUI

/// What the pane covers: both agents, or one.
enum UsageScope: Hashable, CaseIterable, Identifiable {
    case overview, agent(AgentKind)

    static var allCases: [UsageScope] { [.overview] + AgentKind.allCases.map { .agent($0) } }

    var id: String {
        switch self {
        case .overview: "overview"
        case .agent(let agent): agent.rawValue
        }
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .agent(let agent): agent.displayName
        }
    }

    var agent: AgentKind? {
        if case .agent(let agent) = self { return agent }
        return nil
    }
}

/// Usage and Spend: tokens and API value from the agents' own logs on this Mac, over 24 hours to 90 days,
/// for both agents or one. Every row is a grid of equal columns on one 8 pt gap, so edges line up down the pane.
@MainActor
struct UsagePane: View {
    let usage: UsageModel
    let store: SessionStore
    @State private var range: UsageRange = {
        #if DEBUG
        // `--usage-range <day|week|month|quarter>` opens that range, for screenshots.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--usage-range"), i + 1 < args.count, let range = UsageRange(rawValue: args[i + 1]) {
            return range
        }
        #endif
        return .day
    }()
    @State private var scope: UsageScope = {
        #if DEBUG
        // `--usage-agent <claude|codex>` opens that agent, for screenshots.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--usage-agent"), i + 1 < args.count, let agent = AgentKind(rawValue: args[i + 1]) {
            return .agent(agent)
        }
        #endif
        return .overview
    }()

    @State private var scopeOpen = false

    static let gap: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            PaneTitle(title: "Usage and Spend",
                      lead: "What your Claude Code and Codex replies would cost at API list prices, read from their logs on this Mac.")
            HStack(spacing: 12) {
                SegmentedPicker(options: UsageRange.allCases, selection: $range, size: 12) { $0.label }
                Spacer(minLength: 0)
                ScopeButton(selection: scope, open: $scopeOpen)
            }
            .padding(.bottom, 8)
            if let summary {
                if summary.total.replies == 0 {
                    Tile {
                        TileHeading(title: emptyTitle, subtitle: "Replies show up here as your agents work.")
                    }
                } else {
                    content(summary)
                }
            } else {
                Tile {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        TileHeading(title: "Reading your logs…", subtitle: "The first read covers 90 days and runs once per launch.")
                    }
                }
            }
            Text("API value is what the same tokens cost at Anthropic's and OpenAI's list prices: about what an API key pays, while subscription plans pay a flat price instead. Nothing leaves your Mac.")
                .font(Theme.font(12, .regular)).opacity(0.5).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }
        .animation(.easeOut(duration: 0.16), value: scope)
        // The scope panel drops from the button's right edge inside the pane, so it never leaves the window;
        // a click anywhere else closes it.
        .overlayPreferenceValue(ScopeAnchor.self) { anchor in
            GeometryReader { proxy in
                if scopeOpen, let anchor {
                    let button = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { scopeOpen = false }
                        ScopePanel(selection: $scope, open: $scopeOpen) { scope in
                            scope.agent.map { usage.agentSummaries[$0]?[range] } ?? usage.summaries[range]
                        }
                        .offset(x: button.maxX - ScopePanel.width, y: button.maxY + 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.14), value: scopeOpen)
    }

    private var summary: UsageSummary? {
        guard let agent = scope.agent else { return usage.summaries[range] }
        return usage.agentSummaries[agent]?[range]
    }

    private var emptyTitle: String {
        scope.agent.map { "No \($0.displayName) replies in this range" } ?? "No usage in this range"
    }

    @ViewBuilder
    private func content(_ summary: UsageSummary) -> some View {
        StatGrid(stats: stats(summary))
        if summary.total.unpriced > 0 {
            Text("\(summary.total.unpriced.formatted()) \(summary.total.unpriced == 1 ? "reply" : "replies") from models without a known price, not in the API value.")
                .font(Theme.font(11, .regular)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
        }
        EqualRow {
            TrendTile(summary: summary, agent: scope.agent)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            TokenMixTile(tokens: summary.total.tokens, showsHitRate: scope == .overview)
                .frame(width: 196)
        }
        if scope == .overview {
            EqualRow {
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    AgentCard(agent: agent, summary: usage.agentSummaries[agent]?[range], total: summary.total) {
                        scope = .agent(agent)
                    }
                }
            }
        }
        EqualRow {
            ShareList(title: "By model", shares: summary.byModel)
            ShareList(title: "By project", shares: summary.byProject)
        }
        if summary.hasSeveralAccounts {
            ShareList(title: "By account", shares: AccountSignIn.named(
                summary.byAccount, accounts: AccountSignIn.merging(usage.signIns, remembered: store.signInByAccount)))
        }
    }

    private func stats(_ summary: UsageSummary) -> [Stat] {
        let total = summary.total
        let cost = Stat(symbol: "dollarsign.circle", value: UsageFormat.cost(total.cost), label: "API value")
        let sessions = Stat(symbol: "rectangle.stack", value: summary.sessions.formatted(), label: "Sessions")
        let hitRate = total.tokens.cacheHitRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–"
        let hits = Stat(symbol: "arrow.triangle.2.circlepath", value: hitRate, label: "Cache hits")
        guard scope.agent != nil else {
            return [cost, Stat(symbol: "number", value: UsageFormat.tokens(total.tokens.total), label: "Tokens"), sessions,
                    Stat(symbol: "calendar", value: activeDays(summary), label: "Active days")]
        }
        return [
            Stat(symbol: "arrow.up.right", value: UsageFormat.tokens(total.tokens.input), label: "Input"),
            Stat(symbol: "arrow.down.left", value: UsageFormat.tokens(total.tokens.output), label: "Output"),
            Stat(symbol: "square.stack.3d.up", value: UsageFormat.tokens(total.tokens.cacheRead), label: "Cache read"),
            Stat(symbol: "square.and.arrow.down", value: UsageFormat.tokens(total.tokens.cacheWrite), label: "Cache write"),
            hits,
            sessions,
            Stat(symbol: "text.bubble", value: total.replies.formatted(), label: "Replies"),
            cost,
        ]
    }

    private func activeDays(_ summary: UsageSummary) -> String {
        guard let days = summary.range.days else { return summary.activeDays.formatted() }
        return "\(summary.activeDays) / \(days)"
    }
}

// MARK: Controls

/// Where the scope button sits, so the pane can drop its panel from it.
private struct ScopeAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// The scope as a button: the chosen scope's mark and name, a chevron that flips while its panel is open.
private struct ScopeButton: View {
    let selection: UsageScope
    @Binding var open: Bool
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                ScopeMark(scope: selection, size: 20)
                Text(selection.title).font(Theme.font(12, .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.5)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.leading, 5).padding(.trailing, 11)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(hovering || open ? Theme.pill : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.ink.opacity(open ? 0.22 : 0.1), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: open)
        .anchorPreference(key: ScopeAnchor.self, value: .bounds) { $0 }
        .accessibilityLabel("Show: \(selection.title)")
        .accessibilityHint(open ? "Closes the list" : "Opens the list")
    }
}

/// The scopes as rich rows: each one's mark, name and figures for the range, a check on the chosen one.
/// Escape closes it.
private struct ScopePanel: View {
    static let width: CGFloat = 260

    @Binding var selection: UsageScope
    @Binding var open: Bool
    /// A scope's summary for the current range, for each row's figures.
    let summary: (UsageScope) -> UsageSummary?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(UsageScope.allCases) { scope in
                ScopeRow(scope: scope, summary: summary(scope), selected: scope == selection) {
                    selection = scope
                    open = false
                }
            }
        }
        .padding(6)
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.ink.opacity(0.1), lineWidth: 1))
        .onExitCommand { open = false }
    }
}

private struct ScopeRow: View {
    let scope: UsageScope
    let summary: UsageSummary?
    let selected: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                ScopeMark(scope: scope, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.title).font(Theme.font(13, .semibold))
                    Text(detail).font(Theme.font(11, .regular)).monospacedDigit().opacity(0.6).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.green)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.ink.opacity(hovering ? 0.08 : selected ? 0.04 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var detail: String {
        guard let summary else { return "Reading…" }
        guard summary.total.replies > 0 else { return "No replies in this range" }
        return "\(UsageFormat.cost(summary.total.cost)) · \(UsageFormat.tokens(summary.total.tokens.total)) tokens"
    }
}

/// The agent's logo on a tint of its color, or a chart glyph for both.
private struct ScopeMark: View {
    let scope: UsageScope
    let size: CGFloat

    var body: some View {
        Group {
            if let agent = scope.agent {
                AgentLogo(agent: agent, size: size * 0.58)
            } else {
                Image(systemName: "square.grid.2x2").font(.system(size: size * 0.42, weight: .semibold)).opacity(0.8)
            }
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(scope.agent.map { Theme.agent($0).opacity(0.16) } ?? Theme.ink.opacity(0.08)))
    }
}

// MARK: Layout

/// Side-by-side tiles at one shared height, so their bottoms line up whatever each holds.
private struct EqualRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: UsagePane.gap) { content }
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The tile surface for this pane: 12 pt in, so four across still fit their figures.
private struct PaneTile<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).fill(Theme.surface))
    }
}

/// Title and an optional subline, in the pane's type.
private struct SectionHeading<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(13, .semibold)).kerning(-0.2)
                if let subtitle {
                    Text(subtitle).font(Theme.font(11, .regular)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: Stats

private struct Stat: Identifiable {
    let symbol: String
    let value: String
    let label: String
    var id: String { label }
}

/// Four equal columns; a second row for the per-agent view's eight figures.
private struct StatGrid: View {
    let stats: [Stat]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: UsagePane.gap, alignment: .topLeading), count: 4)
        LazyVGrid(columns: columns, alignment: .leading, spacing: UsagePane.gap) {
            ForEach(stats) { StatTile(stat: $0) }
        }
    }
}

private struct StatTile: View {
    let stat: Stat

    var body: some View {
        PaneTile(padding: 12) {
            Image(systemName: stat.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.ink.opacity(0.07)))
                .opacity(0.8)
                .padding(.bottom, 10)
            Text(stat.value)
                .font(Theme.font(19, .semibold)).kerning(-0.5).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(stat.label).font(Theme.font(11, .regular)).opacity(0.6).lineLimit(1).padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Trend

/// API value per bar: stacked by agent in the overview, one agent's color otherwise. A hover readout per bar.
private struct TrendTile: View {
    let summary: UsageSummary
    let agent: AgentKind?
    @State private var hovered: Date?

    private var agents: [AgentKind] {
        if let agent { return [agent] }
        return AgentKind.allCases.filter { agent in summary.trend.contains { ($0.byAgent[agent]?.replies ?? 0) > 0 } }
    }

    var body: some View {
        PaneTile {
            SectionHeading(title: summary.range == .day ? "By hour" : "By day",
                           subtitle: summary.range == .day ? "API value per hour." : "API value per day.") {
                if agents.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(agents, id: \.self) { agent in
                            HStack(spacing: 4) {
                                AgentLogo(agent: agent, size: 11)
                                Text(agent.displayName).font(Theme.font(11, .medium)).opacity(0.7)
                            }
                        }
                    }
                }
            }
            chart.frame(height: 148).padding(.top, 14)
        }
    }

    private var unit: Calendar.Component { summary.range == .day ? .hour : .day }

    private var chart: some View {
        Chart {
            ForEach(summary.trend) { bar in
                ForEach(agents, id: \.self) { agent in
                    BarMark(x: .value("Time", bar.start, unit: unit),
                            y: .value("API value", bar.byAgent[agent]?.cost ?? 0), width: .ratio(0.72))
                        .foregroundStyle(Theme.agent(agent).opacity(hovered == nil || hovered == bar.start ? 1 : 0.4))
                        .cornerRadius(agent == agents.last ? 3 : 0, style: .continuous)
                }
                if hovered == bar.start {
                    RuleMark(x: .value("Time", bar.start, unit: unit))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Readout(bar: bar, hourly: summary.range == .day)
                        }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: unit, count: stride)) { _ in
                AxisValueLabel(format: summary.range == .day ? .dateTime.hour() : .dateTime.day().month(.abbreviated),
                               centered: true)
                    .font(Theme.font(10, .regular))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.ink.opacity(0.08))
                AxisValueLabel {
                    if let dollars = value.as(Double.self) {
                        // Ticks are round numbers: cents only below a dollar.
                        Text(dollars, format: .currency(code: "USD").precision(.fractionLength(dollars < 1 && dollars > 0 ? 2 : 0)))
                            .font(Theme.font(10, .regular))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let x = point.x - (proxy.plotFrame.map { geometry[$0].origin.x } ?? 0)
                            let date: Date? = proxy.value(atX: x)
                            hovered = date.flatMap { Calendar.current.dateInterval(of: unit, for: $0)?.start }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .accessibilityLabel(summary.range == .day ? "API value per hour" : "API value per day")
    }

    /// About six labels whatever the range.
    private var stride: Int { max(1, summary.trend.count / 6) }
}

private struct Readout: View {
    let bar: UsageDay
    let hourly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hourly ? bar.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
                 : bar.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(Theme.font(11, .semibold))
            Text("\(UsageFormat.cost(bar.totals.cost)) · \(UsageFormat.tokens(bar.totals.tokens.total)) tokens")
                .font(Theme.font(11, .regular)).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.canvas).shadow(color: .black.opacity(0.14), radius: 4, y: 1))
        .foregroundStyle(Theme.ink)
    }
}

// MARK: Token mix

private enum TokenKind: CaseIterable {
    case input, output, cacheRead, cacheWrite

    var label: String {
        switch self {
        case .input: "Input"
        case .output: "Output"
        case .cacheRead: "Cache read"
        case .cacheWrite: "Cache write"
        }
    }

    /// Validated as a categorical set on both surfaces (CVD-safe; light mode relies on the labelled legend).
    var color: Color {
        switch self {
        case .input: Theme.series(light: 0x2A78D6, dark: 0x3987E5)
        case .output: Theme.series(light: 0x1BAF7A, dark: 0x199E70)
        case .cacheRead: Theme.series(light: 0xEDA100, dark: 0xC98500)
        case .cacheWrite: Theme.series(light: 0xE87BA4, dark: 0xD55181)
        }
    }

    func count(_ tokens: UsageTokens) -> Int {
        switch self {
        case .input: tokens.input
        case .output: tokens.output
        case .cacheRead: tokens.cacheRead
        case .cacheWrite: tokens.cacheWrite
        }
    }
}

/// Where the tokens went: one bar split by kind, 2 pt gaps, then each kind with its count and share.
private struct TokenMixTile: View {
    let tokens: UsageTokens
    /// The per-agent view has its own cache hits tile.
    var showsHitRate = false

    var body: some View {
        let total = max(1, tokens.total)
        let kinds = TokenKind.allCases
        PaneTile {
            SectionHeading(title: "Token mix", subtitle: "\(UsageFormat.tokens(tokens.total)) in all.")
            GeometryReader { geometry in
                let shown = kinds.filter { $0.count(tokens) > 0 }
                let room = geometry.size.width - CGFloat(max(0, shown.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(shown, id: \.self) { kind in
                        Rectangle().fill(kind.color)
                            .frame(width: max(2, room * CGFloat(kind.count(tokens)) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .padding(.top, 14)
            VStack(spacing: 8) {
                ForEach(kinds, id: \.self) { kind in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).fill(kind.color).frame(width: 8, height: 8)
                        Text(kind.label).font(Theme.font(11, .medium))
                        Spacer(minLength: 4)
                        Text(UsageFormat.tokens(kind.count(tokens))).font(Theme.font(11, .medium)).monospacedDigit()
                        Text(share(kind.count(tokens), of: total))
                            .font(Theme.font(11, .regular)).monospacedDigit().opacity(0.55)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
            if showsHitRate, let rate = tokens.cacheHitRate {
                Divider().padding(.vertical, 10)
                HStack {
                    Text("Cache hits").font(Theme.font(11, .medium)).opacity(0.6)
                    Spacer(minLength: 4)
                    Text(rate.formatted(.percent.precision(.fractionLength(0)))).font(Theme.font(11, .semibold)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func share(_ count: Int, of total: Int) -> String {
        let fraction = Double(count) / Double(total)
        if count > 0 && fraction < 0.01 { return "<1%" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: Agents

/// One agent in the overview: its top model, figures and share of the API value. Opens that agent's view.
private struct AgentCard: View {
    let agent: AgentKind
    let summary: UsageSummary?
    let total: UsageTotals
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let totals = summary?.total ?? UsageTotals()
        let fraction = total.cost > 0 ? totals.cost / total.cost
            : Double(totals.tokens.total) / Double(max(1, total.tokens.total))
        Button(action: open) {
            PaneTile {
                HStack(spacing: 8) {
                    AgentLogo(agent: agent, size: 16)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.agent(agent).opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.displayName).font(Theme.font(13, .semibold))
                        Text(summary?.byModel.first?.name ?? "No replies in this range")
                            .font(Theme.font(11, .regular)).opacity(0.6).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        .opacity(hovering ? 0.7 : 0.3)
                }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                    GridRow {
                        figure(UsageFormat.cost(totals.cost))
                        figure(UsageFormat.tokens(totals.tokens.total))
                        figure(totals.replies > 0 ? (summary?.sessions ?? 0).formatted() : "0")
                    }
                    GridRow {
                        caption("API value")
                        caption("Tokens")
                        caption("Sessions")
                    }
                }
                .padding(.top, 14)
                GeometryReader { geometry in
                    Capsule().fill(Theme.ink.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.agent(agent))
                                .frame(width: fraction > 0 ? max(4, geometry.size.width * fraction) : 0)
                        }
                }
                .frame(height: 4)
                .padding(.top, 12)
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .strokeBorder(Theme.ink.opacity(hovering ? 0.16 : 0), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel("\(agent.displayName), \(UsageFormat.cost(totals.cost)), \(UsageFormat.tokens(totals.tokens.total)) tokens")
        .accessibilityHint("Shows \(agent.displayName) only")
    }

    private func figure(_ text: String) -> some View {
        Text(text).font(Theme.font(14, .semibold)).monospacedDigit().lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(Theme.font(11, .regular)).opacity(0.6).lineLimit(1)
    }
}

// MARK: Breakdowns

/// A ranked list: name, a thin bar for its share, API value and tokens.
private struct ShareList: View {
    let title: String
    let shares: [UsageShare]

    var body: some View {
        PaneTile {
            SectionHeading(title: title)
            let top = shares.map(weight).max() ?? 0
            VStack(spacing: 10) {
                ForEach(shares) { share in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(share.name).font(Theme.font(12, .medium)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(share.totals.cost > 0 ? UsageFormat.cost(share.totals.cost) : "–")
                                .font(Theme.font(12, .medium)).monospacedDigit()
                            Text(UsageFormat.tokens(share.totals.tokens.total))
                                .font(Theme.font(11, .regular)).monospacedDigit().opacity(0.6)
                                .frame(width: 46, alignment: .trailing)
                        }
                        GeometryReader { geometry in
                            Capsule().fill(Theme.ink.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(share.agent.map(Theme.agent) ?? Theme.ink.opacity(0.45))
                                        .frame(width: top > 0 ? max(3, geometry.size.width * weight(share) / top) : 0)
                                }
                        }
                        .frame(height: 4)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 14)
        }
    }

    /// API value, or tokens when nothing in the list has a price, so bars never compare dollars with tokens.
    private func weight(_ share: UsageShare) -> Double {
        shares.contains { $0.totals.cost > 0 } ? share.totals.cost : Double(share.totals.tokens.total)
    }
}
