import Foundation

/// One hook event as sent over the socket: a single JSON line.
public struct WireEvent: Codable, Equatable, Sendable {
    public static let version = 1
    public static let maxLineBytes = 64 * 1024

    public var v: Int
    /// Unix milliseconds, captured when the hook process started.
    public var ts: Int64
    /// The Claude Code process (the hook's parent).
    public var pid: Int32?
    public var term: TermInfo?
    public var e: SlimEvent

    public init(v: Int = WireEvent.version, ts: Int64, pid: Int32? = nil, term: TermInfo? = nil, e: SlimEvent) {
        self.v = v
        self.ts = ts
        self.pid = pid
        self.term = term
        self.e = e
    }

    public enum DecodeError: Error, Equatable {
        case tooLarge(Int)
        case unsupportedVersion(Int)
    }

    /// JSON followed by a newline.
    public func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) throws -> WireEvent {
        guard line.count <= maxLineBytes else { throw DecodeError.tooLarge(line.count) }
        var body = line
        while let last = body.last, last == 0x0A || last == 0x0D { body.removeLast() }
        let event = try JSONDecoder().decode(WireEvent.self, from: body)
        guard event.v == version else { throw DecodeError.unsupportedVersion(event.v) }
        return event
    }
}
