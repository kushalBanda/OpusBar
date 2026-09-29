import Foundation

/// Card timer text: the two largest units, so it stays short at any age ("42s", "3m 05s", "2h 14m", "5d 1h").
public enum ElapsedFormat {
    public static func short(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds >= 86_400 { return "\(seconds / 86_400)d \(seconds % 86_400 / 3600)h" }
        if seconds >= 3600 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds)s"
    }
}
