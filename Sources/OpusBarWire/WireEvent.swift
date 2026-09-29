import Foundation

/// One hook event as sent over the socket: a single JSON line.
public struct WireEvent: Codable, Equatable, Sendable {
    public static let version = 1
    public static let maxLineBytes = 64 * 1024

    public var v: Int
    /// Unix milliseconds, captured when the hook process started.
    public var ts: Int64
    /// The agent process (the hook's parent).
    public var pid: Int32?
    public var term: TermInfo?
    /// Which agent sent it. Nil means Claude Code; an unknown name from a newer hook also decodes as nil.
    public var agent: AgentKind?
    public var e: SlimEvent

    public init(v: Int = WireEvent.version, ts: Int64, pid: Int32? = nil, term: TermInfo? = nil,
                agent: AgentKind? = nil, e: SlimEvent) {
        self.v = v
        self.ts = ts
        self.pid = pid
        self.term = term
        self.agent = agent
        self.e = e
    }

    private enum CodingKeys: String, CodingKey { case v, ts, pid, term, agent, e }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        ts = try c.decode(Int64.self, forKey: .ts)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        term = try c.decodeIfPresent(TermInfo.self, forKey: .term)
        agent = (try? c.decodeIfPresent(String.self, forKey: .agent)).flatMap { $0.flatMap(AgentKind.init(rawValue:)) }
        e = try c.decode(SlimEvent.self, forKey: .e)
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
