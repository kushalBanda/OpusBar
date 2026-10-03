import OpusBarCore
import OpusBarWire
import SwiftUI

/// Which half of the dropdown shows.
enum DropdownTab: String, CaseIterable {
    case sessions, usage

    var title: String {
        switch self {
        case .sessions: "Sessions"
        case .usage: "Usage"
        }
    }
}

/// The Usage tab, laid out like vorssaint's agent page: a card per account's plan limits, then the
/// range's API value over a trend stacked by agent, then the top models and projects. The full breakdown
/// stays in Settings > Usage. Scrolls past `maxHeight`, so the menu never runs off the screen.
@MainActor
struct UsageDropdownView: View {
    let usage: UsageModel
    let maxHeight: CGFloat
    @State private var range: UsageRange = .day

    var body: some View {
        FittedScroll(maxHeight: maxHeight) {
            // Countdowns and pace move with the clock; once a minute is enough for both.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(now: context.date)
            }
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if usage.limits.isEmpty {
                UsageCard {
                    CardHeader(title: "Plan limits", symbol: "gauge.with.dots.needle.33percent")
                    Text("None yet. Claude Code saves each account's limits when it checks them; Codex writes its own as it works.")
                        .font(Theme.font(11, .regular)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(usage.limits) { limits in
                LimitsCard(limits: limits, showsAccount: usage.limits.filter { $0.agent == limits.agent }.count > 1, now: now)
            }
            SegmentedPicker(options: UsageRange.allCases, selection: $range, size: 11) { $0.label }
                .padding(.top, 4)
            if let summary = usage.summaries[range] {
                SpendCard(summary: summary)
                if summary.hasSeveralAccounts {
                    ShareCard(title: "Accounts", symbol: "person.2", shares: summary.byAccount.map(\.shortName),
                              byCost: summary.total.unpriced == 0, limit: 6)
                }
                if summary.total.replies > 0 {
                    HStack(alignment: .top, spacing: 8) {
                        ShareCard(title: "Models", symbol: "cpu", shares: summary.byModel, byCost: summary.total.unpriced == 0)
                        ShareCard(title: "Projects", symbol: "folder", shares: summary.byProject, byCost: summary.total.unpriced == 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                UsageCard {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading your logs…").font(Theme.font(12, .regular)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: Cards

/// The surface every card sits on: a quiet fill, no border, so the numbers carry the hierarchy.
private struct UsageCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) { content }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
}

private struct CardHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint) }
            Text(title).font(Theme.font(11, .semibold)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, symbol: String? = nil, tint: Color = .secondary) {
        self.init(title: title, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// One account: its session and the longer window that binds first, each with what is left, a meter with
/// the even-pace mark, and when it renews.
private struct LimitsCard: View {
    let limits: UsageLimits
    let showsAccount: Bool
    let now: Date

    var body: some View {
        UsageCard {
            HStack(spacing: 6) {
                AgentLogo(agent: limits.agent, size: 13)
                Text(limits.agent.displayName).font(Theme.font(12, .semibold))
                // The name before the @ tells accounts apart in the room a card has; the tooltip has it all.
                if showsAccount, let label = limits.label {
                    Text(label.split(separator: "@").first.map(String.init) ?? label)
                        .font(Theme.font(11, .regular)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        .help(label)
                }
                Spacer(minLength: 6)
                // An old reading is still the latest known; say how old once it could have missed use.
                if now.timeIntervalSince(limits.observedAt) > 600 {
                    Text("updated \(limits.observedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                        .font(Theme.font(10, .regular)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            ForEach(limits.shown(at: now)) { window in
                LimitRow(agent: limits.agent, window: window, now: now)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LimitRow: View {
    let agent: AgentKind
    let window: UsageLimitWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.label).font(Theme.font(11, .medium)).lineLimit(1)
                if let resets = window.resetsAt {
                    Label(UsageFormat.countdown(to: resets, now: now), systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon).imageScale(.small)
                        .font(Theme.font(10, .regular)).foregroundStyle(.secondary).lineLimit(1)
                        .help("Resets \(UsageFormat.resetTime(resets, now: now))")
                }
                Spacer(minLength: 4)
                Text("\(UsageFormat.percent(window.remainingFraction)) left")
                    .font(Theme.font(12, .semibold)).monospacedDigit()
                    .foregroundStyle(level ?? Theme.ink)
                    .contentTransition(.numericText())
            }
            Meter(value: window.remainingFraction, pace: window.elapsed(at: now).map { 1 - $0 },
                  tint: level ?? Theme.agent(agent))
        }
    }

    /// Orange from 80 % spent, red from 95 %.
    private var level: Color? {
        if window.usedFraction >= 0.95 { return Theme.red }
        if window.usedFraction >= 0.8 { return .orange }
        return nil
    }
}

/// What is left on a faint track, and a tick where an even pace would be: left of it, spending ahead.
private struct Meter: View {
    let value: Double
    let pace: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.1))
                Capsule().fill(tint).frame(width: value > 0 ? max(4, width * min(1, value)) : 0)
                if let pace {
                    Rectangle().fill(Theme.ink.opacity(0.55)).frame(width: 1.5, height: 8)
                        .offset(x: min(width - 1.5, max(0, width * pace - 0.75)))
                }
            }
        }
        .frame(height: 5)
    }
}

/// The range's API value, tokens and replies, over a trend stacked by agent. Hovering a bar shows its own
/// figures in the header, like vorssaint's trend card.
private struct SpendCard: View {
    let summary: UsageSummary
    @State private var hovered: Date?

    var body: some View {
        let bars = summary.trend
        let pointed = hovered.flatMap { date in bars.first { $0.start == date } }
        let shown = pointed?.totals ?? summary.total
        let agents = AgentKind.allCases.filter { agent in bars.contains { ($0.byAgent[agent]?.replies ?? 0) > 0 } }
        UsageCard {
            CardHeader(title: pointed.map { label($0.start, long: true) } ?? "API value", symbol: "dollarsign.circle") {
                if agents.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(agents, id: \.self) { agent in
                            HStack(spacing: 3) {
                                AgentLogo(agent: agent, size: 11)
                                Text(agent.displayName).font(Theme.font(10, .medium)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(UsageFormat.cost(shown.cost)).font(Theme.font(24, .semibold)).kerning(-0.6).monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(UsageFormat.tokens(shown.tokens.total)) tokens · \(shown.replies.formatted()) \(shown.replies == 1 ? "reply" : "replies")")
                    .font(Theme.font(11, .regular)).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
            if summary.total.replies == 0 {
                Text("No usage in this range yet.").font(Theme.font(11, .regular)).foregroundStyle(.secondary)
            } else {
                TrendBars(bars: bars, agents: agents.isEmpty ? AgentKind.allCases : agents,
                          byCost: summary.total.unpriced == 0, hovered: $hovered)
                    .frame(height: 56)
                axis(bars)
            }
        }
    }

    private func label(_ date: Date, long: Bool) -> String {
        switch summary.range {
        case .day: return long ? date.formatted(.dateTime.hour().minute()) : date.formatted(.dateTime.hour())
        case .week: return long ? date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
            : date.formatted(.dateTime.weekday(.narrow))
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// Every bar a letter over a week; the ends and the middle otherwise.
    private func axis(_ bars: [UsageDay]) -> some View {
        HStack(spacing: 0) {
            if summary.range == .week {
                ForEach(bars) { Text(label($0.start, long: false)).frame(maxWidth: .infinity) }
            } else if let first = bars.first, let last = bars.last {
                Text(label(first.start, long: false))
                Spacer(minLength: 4)
                Text(label(bars[bars.count / 2].start, long: false))
                Spacer(minLength: 4)
                Text(summary.range == .day ? "Now" : label(last.start, long: false))
            }
        }
        .font(Theme.font(9, .medium)).foregroundStyle(.tertiary).lineLimit(1)
    }
}

/// Bars stacked by agent on a shared baseline, rounded ends, a 2 pt gap; an empty bucket is a faint dash.
/// Dollars when every reply has a price, tokens otherwise, so dollars never stack on tokens.
private struct TrendBars: View {
    let bars: [UsageDay]
    let agents: [AgentKind]
    let byCost: Bool
    @Binding var hovered: Date?

    var body: some View {
        let values = bars.map { bar in agents.map { weight(bar.byAgent[$0]) } }
        let peak = max(values.map { $0.reduce(0, +) }.max() ?? 0, .leastNonzeroMagnitude)
        GeometryReader { geometry in
            let count = CGFloat(max(1, bars.count))
            let gap: CGFloat = count > 24 ? 1.5 : 2
            let width = max(1, (geometry.size.width - gap * (count - 1)) / count)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                    let parts = values[index]
                    let active = hovered == nil || hovered == bar.start
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if parts.reduce(0, +) <= 0 {
                            Capsule().fill(Theme.ink.opacity(0.1)).frame(height: 2)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(agents.indices.reversed(), id: \.self) { slot in
                                    if parts[slot] > 0 {
                                        Rectangle().fill(Theme.agent(agents[slot]).opacity(active ? 1 : 0.45))
                                            .frame(height: max(1, geometry.size.height * parts[slot] / peak))
                                    }
                                }
                            }
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: min(3, width / 2), topTrailingRadius: min(3, width / 2),
                                                              style: .continuous))
                        }
                    }
                    .frame(width: width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hovered = bar.start } else if hovered == bar.start { hovered = nil }
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(byCost ? "API value over time" : "Tokens over time")
    }

    private func weight(_ totals: UsageTotals?) -> Double {
        guard let totals else { return 0 }
        return byCost ? totals.cost : Double(totals.tokens.total)
    }
}

/// The top three, each with a short bar in its agent's color and its value, like vorssaint's share cards.
private struct ShareCard: View {
    let title: String
    let symbol: String
    let shares: [UsageShare]
    let byCost: Bool
    var limit = 3

    var body: some View {
        let shown = Array(shares.prefix(limit))
        let weight: (UsageShare) -> Double = { byCost ? $0.totals.cost : Double($0.totals.tokens.total) }
        let peak = max(shown.map(weight).max() ?? 0, .leastNonzeroMagnitude)
        UsageCard {
            CardHeader(title: title, symbol: symbol)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { share in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(share.name).font(Theme.font(11, .medium)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(byCost ? UsageFormat.cost(share.totals.cost) : UsageFormat.tokens(share.totals.tokens.total))
                                .font(Theme.font(10, .medium)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        GeometryReader { geometry in
                            Capsule().fill(share.agent.map(Theme.agent) ?? Theme.ink.opacity(0.5))
                                .frame(width: max(3, geometry.size.width * weight(share) / peak))
                        }
                        .frame(height: 3)
                    }
                    .help("\(share.name) · \(UsageFormat.cost(share.totals.cost)) · \(UsageFormat.tokens(share.totals.tokens.total)) tokens")
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private extension UsageShare {
    /// An email without its domain: both accounts often share one, and the card is narrow.
    var shortName: UsageShare {
        var copy = self
        copy.name = name.split(separator: "@").first.map(String.init) ?? name
        return copy
    }
}

/// Content at its own height up to `maxHeight`, then a scroll view with a visible scroller, so there is
/// always a cue that more is below. Measured directly: preferences don't reliably leave a ScrollView here.
struct FittedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        let visible = height > 0 ? min(height, maxHeight) : maxHeight
        let scrolls = height > maxHeight + 0.5
        ScrollView(.vertical) {
            content.background(GeometryReader { proxy in
                Color.clear
                    .onAppear { measure(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, new in measure(new) }
            })
        }
        .scrollIndicators(scrolls ? .visible : .never)
        .scrollDisabled(!scrolls)
        .frame(height: visible)
    }

    private func measure(_ new: CGFloat) {
        if abs(new - height) > 0.5 { height = new }
    }
}
