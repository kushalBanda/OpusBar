import Foundation

/// ISO 8601 times as the agents write them ("2026-09-30T10:00:00.000Z"), read without a formatter:
/// a first scan parses hundreds of thousands of them. Anything else goes through ISO8601DateFormatter.
public enum UsageTimestamp {
    public static func parse(_ text: String) -> Date? {
        if let date = fast(Array(text.utf8)) { return date }
        return lock.withLock { fractional.date(from: text) ?? whole.date(from: text) }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private nonisolated(unsafe) static let whole = ISO8601DateFormatter()

    /// `YYYY-MM-DDTHH:MM:SS[.fraction](Z|±HH:MM)`; nil for any other shape or an impossible date.
    static func fast(_ b: [UInt8]) -> Date? {
        guard b.count >= 20, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"), b[10] == UInt8(ascii: "T"),
              b[13] == UInt8(ascii: ":"), b[16] == UInt8(ascii: ":")
        else { return nil }
        func digits(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(b[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = digits(0..<4), let month = digits(5..<7), let day = digits(8..<10),
              let hour = digits(11..<13), let minute = digits(14..<16), let second = digits(17..<19),
              (1...12).contains(month), (1...daysIn(month, year)).contains(day), hour < 24, minute < 60, second < 61
        else { return nil }
        var index = 19
        var fraction = 0.0
        if b[index] == UInt8(ascii: ".") {
            var scale = 0.1
            index += 1
            while index < b.count, (48...57).contains(b[index]) {
                fraction += Double(b[index] - 48) * scale
                scale /= 10
                index += 1
            }
        }
        guard index < b.count else { return nil }
        var offset = 0
        if b[index] == UInt8(ascii: "Z") {
            guard index == b.count - 1 else { return nil }
        } else if b[index] == UInt8(ascii: "+") || b[index] == UInt8(ascii: "-"), b.count == index + 6,
                  b[index + 3] == UInt8(ascii: ":"), let hours = digits(index + 1..<index + 3),
                  let minutes = digits(index + 4..<index + 6) {
            offset = (hours * 3600 + minutes * 60) * (b[index] == UInt8(ascii: "+") ? 1 : -1)
        } else {
            return nil
        }
        let seconds = daysSinceEpoch(year: year, month: month, day: day) * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    private static func daysIn(_ month: Int, _ year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days from 1970-01-01 to a proleptic Gregorian date (the civil-from-days inverse, valid for any year).
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
