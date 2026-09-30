import Charts
import OpusBarCore
import OpusBarWire
import SwiftUI

/// Usage and Spend: tokens and API value from the agents' own logs on this Mac. The last 24 hours is
/// free; longer ranges and the daily bars are Pro (gated only through `UsageRange.isAvailable`).
@MainActor
struct UsagePane: View {
    let usage: UsageModel
    let entitlements: Entitlements
    let openLicense: () -> Void
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneTitle(title: "Usage and Spend",
                      lead: "What your Claude Code and Codex replies would cost at API list prices, read from their logs on this Mac.")
            HStack {
                ChipPicker(options: UsageRange.allCases, selection: $range) { range in
                    range.isAvailable(isPro: entitlements.isPro) ? range.label : range.label + " · Pro"
                }
                Spacer()
            }
            .padding(.bottom, 4)
            if !range.isAvailable(isPro: entitlements.isPro) {
                UnlockTile(range: range, openLicense: openLicense)
            } else if let summary = usage.summaries[range] {
                if summary.total.replies == 0 {
                    Tile { TileHeading(title: "No usage in this range", subtitle: "Replies show up here as your agents work.") }
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
            Text("API value is what the same tokens cost at Anthropic's and OpenAI's list prices. Subscription plans pay a flat price instead. Nothing leaves your Mac.")
                .font(Theme.font(12, .regular)).opacity(0.5).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
    }

    @ViewBuilder
    private func content(_ summary: UsageSummary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Tile(fill: Theme.green, onColor: true, stretches: true) {
                Text("API value").font(Theme.font(12, .medium)).opacity(0.72)
                Text(UsageFormat.cost(summary.total.cost)).font(Theme.font(34, .medium)).kerning(-1.2)
                    .monospacedDigit().contentTransition(.numericText())
                Text(repliesLine(summary.total)).font(Theme.font(12, .regular)).opacity(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Tile(stretches: true) {
                Text("Tokens").font(Theme.font(12, .medium)).opacity(0.72)
                Text(UsageFormat.tokens(summary.total.tokens.total)).font(Theme.font(34, .medium)).kerning(-1.2)
                    .monospacedDigit().contentTransition(.numericText())
                TokenBreakdown(tokens: summary.total.tokens)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        if !summary.days.isEmpty {
            Tile {
                TileHeading(title: "By day", subtitle: "API value per day, in your time zone.")
                DailyBars(days: summary.days).frame(height: 160).padding(.top, 8)
            }
        }
        HStack(alignment: .top, spacing: 8) {
            ShareList(title: "By agent", shares: summary.byAgent)
            ShareList(title: "By model", shares: summary.byModel)
        }
        .fixedSize(horizontal: false, vertical: true)
        if summary.hasSeveralAccounts {
            ShareList(title: "By account", shares: summary.byAccount)
        }
        ShareList(title: "By project", shares: summary.byProject)
    }

    private func repliesLine(_ totals: UsageTotals) -> String {
        let replies = totals.replies == 1 ? "1 reply" : "\(totals.replies.formatted()) replies"
        guard totals.unpriced > 0 else { return replies }
        return replies + " · \(totals.unpriced.formatted()) from models without a known price, not in the total"
    }
}

/// Free, on a Pro range: what the range adds and the way to Pro.
private struct UnlockTile: View {
    let range: UsageRange
    let openLicense: () -> Void

    var body: some View {
        Tile {
            HStack(alignment: .center, spacing: 16) {
                TileHeading(title: "\(range.label) is Pro",
                            subtitle: "Pro shows 7, 30 and 90 days with daily bars, for a one-time \(Entitlements.proPrice). The last 24 hours stays free.")
                Spacer(minLength: 0)
                Button("Unlock…", action: openLicense)
                    .buttonStyle(.borderedProminent).tint(Theme.green).foregroundStyle(Theme.onColor)
            }
        }
    }
}

/// Where the tokens went: new input, cache writes, cache reads, output, and the cache hit rate.
private struct TokenBreakdown: View {
    let tokens: UsageTokens

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            row("Input", tokens.input)
            row("Output", tokens.output)
            row("Cache read", tokens.cacheRead)
            row("Cache write", tokens.cacheWrite)
            if let rate = tokens.cacheHitRate {
                GridRow {
                    Text("Cache hits").opacity(0.72)
                    Text(rate.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                }
            }
        }
        .font(Theme.font(12, .regular))
        .padding(.top, 2)
    }

    private func row(_ label: String, _ count: Int) -> some View {
        GridRow {
            Text(label).opacity(0.72)
            Text(UsageFormat.tokens(count)).monospacedDigit()
        }
    }
}

/// One series of daily API value. Single hue, rounded tops on the baseline, recessive axes, and a hover
/// readout per day (dataviz: one series needs no legend; the tile title names it).
private struct DailyBars: View {
    let days: [UsageDay]
    @State private var hovered: Date?

    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("Day", day.start, unit: .day), y: .value("API value", day.totals.cost), width: .ratio(0.7))
                .cornerRadius(4, style: .continuous)
                .foregroundStyle(hovered == nil || hovered == day.start ? Theme.green : Theme.green.opacity(0.45))
            if hovered == day.start {
                RuleMark(x: .value("Day", day.start, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        DayReadout(day: day)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: stride)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
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
                            hovered = date.map { Calendar.current.startOfDay(for: $0) }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .accessibilityLabel("API value per day")
    }

    /// About eight labels whatever the range.
    private var stride: Int { max(1, days.count / 8) }
}

private struct DayReadout: View {
    let day: UsageDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(Theme.font(11, .semibold))
            Text("\(UsageFormat.cost(day.totals.cost)) · \(UsageFormat.tokens(day.totals.tokens.total)) tokens")
                .font(Theme.font(11, .regular)).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface).shadow(color: .black.opacity(0.12), radius: 4, y: 1))
        .foregroundStyle(Theme.ink)
    }
}

/// A ranked list: name, a thin bar for its share, API value and tokens.
private struct ShareList: View {
    let title: String
    let shares: [UsageShare]

    var body: some View {
        Tile(stretches: true) {
            TileHeading(title: title)
            let top = shares.map(weight).max() ?? 0
            VStack(spacing: 8) {
                ForEach(shares) { share in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(share.name).font(Theme.font(12, .medium)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(share.totals.cost > 0 ? UsageFormat.cost(share.totals.cost) : "–")
                                .font(Theme.font(12, .medium)).monospacedDigit()
                            Text(UsageFormat.tokens(share.totals.tokens.total))
                                .font(Theme.font(11, .regular)).monospacedDigit().opacity(0.6)
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                        GeometryReader { geometry in
                            Capsule().fill(Theme.ink.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.green)
                                        .frame(width: top > 0 ? max(3, geometry.size.width * weight(share) / top) : 0)
                                }
                        }
                        .frame(height: 4)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 6)
        }
    }

    /// API value, or tokens when nothing in the list has a price, so bars never compare dollars with tokens.
    private func weight(_ share: UsageShare) -> Double {
        shares.contains { $0.totals.cost > 0 } ? share.totals.cost : Double(share.totals.tokens.total)
    }
}
