import Foundation

/// Short figures for usage strips and tiles.
public enum UsageFormat {
    /// "$0.00", "$12.35", "$1,235" (no cents from $1,000).
    public static func cost(_ dollars: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.roundingMode = .halfUp
        formatter.maximumFractionDigits = dollars >= 1_000 ? 0 : 2
        formatter.minimumFractionDigits = dollars >= 1_000 ? 0 : 2
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    /// "950", "12.4K", "3.3M", "2B".
    public static func tokens(_ count: Int) -> String {
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]
        let value = Double(count)
        guard let (size, suffix) = units.first(where: { value >= $0.0 }) else { return "\(count)" }
        let scaled = (value / size * 10).rounded() / 10
        let text = scaled == scaled.rounded() ? String(Int(scaled)) : String(format: "%.1f", scaled)
        return text + suffix
    }
}

public extension UsageFormat {
    /// Readable model names built from the id itself, so a model no list knows yet still reads well:
    /// "claude-opus-5-5" reads "Opus 5.5", "gpt-5.2-codex" reads "GPT-5.2 Codex".
    static func modelName(_ model: String) -> String {
        let id = UsagePriceList.normalized(model)
        guard !id.isEmpty else { return "Unknown model" }
        if id.hasPrefix("claude-") {
            // Snapshot dates add nothing to a name.
            let parts = id.dropFirst(7).split(separator: "-").map(String.init)
                .filter { !($0.count >= 6 && $0.allSatisfy(\.isNumber)) && $0 != "latest" }
            let words = parts.filter { !$0.allSatisfy(\.isNumber) }
            let version = parts.filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
            let name = ([words.first?.capitalized ?? "", version] + words.dropFirst().map(\.capitalized)).filter { !$0.isEmpty }
            return name.isEmpty ? id : name.joined(separator: " ")
        }
        guard id.hasPrefix("gpt-") else { return id }
        let parts = id.dropFirst(4).split(separator: "-").map(String.init)
            .filter { !($0.count >= 6 && $0.allSatisfy(\.isNumber)) && $0 != "latest" }
        guard let first = parts.first else { return "GPT" }
        return (["GPT-" + first] + parts.dropFirst().map(\.capitalized)).joined(separator: " ")
    }

    /// "65%", rounded, clamped to 0...100.
    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// When a plan window renews: "15:00" today, "Fri 15:00" this week, "12 Oct" later.
    static func resetTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if date.timeIntervalSince(now) < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Time left until a reset: "45m", "3h 12m", "2d 4h".
    static func countdown(to date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m" }
        let hours = minutes / 60
        return hours % 24 == 0 ? "\(hours / 24)d" : "\(hours / 24)d \(hours % 24)h"
    }
}
