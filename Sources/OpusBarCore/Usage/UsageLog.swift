import Darwin
import Foundation
import OpusBarWire

/// How far reading one log file has got. Used by one reader at a time: the store's queue, or the one
/// parallel worker that owns its file during a refresh.
final class UsageLogCursor: @unchecked Sendable {
    let path: String
    let agent: AgentKind
    var offset: UInt64 = 0
    /// The file's inode; a new one means the file was replaced and is read again from its start.
    var identity: UInt64 = 0
    /// The unfinished last line, completed by the next read.
    var pending = Data()
    /// Inside a line longer than the limit: skip up to its end.
    var discarding = false
    /// What earlier lines of a Codex rollout said (session, folder, model, tier, last total).
    var codex = CodexUsageParser.State()

    init(path: String, agent: AgentKind) {
        self.path = path
        self.agent = agent
    }
}

enum UsageLogReader {
    static let chunkSize = 4 << 20

    /// Hands over each complete line appended since the last call. A replaced or shorter file starts over;
    /// the ledger's keys make a second reading of the same replies harmless.
    static func readAppended(_ cursor: UsageLogCursor, maxLineBytes: Int, line: (Data) -> Void) {
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let size = UInt64(max(0, info.st_size))
        let identity = UInt64(info.st_ino)
        if identity != cursor.identity || size < cursor.offset {
            cursor.identity = identity
            cursor.offset = 0
            cursor.pending = Data()
            cursor.discarding = false
            cursor.codex = CodexUsageParser.State()
        }
        guard size > cursor.offset, let handle = FileHandle(forReadingAtPath: cursor.path) else { return }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: cursor.offset) } catch { return }
        while cursor.offset < size {
            // A first read can cover hundreds of megabytes: each chunk is released before the next.
            let more: Bool = autoreleasepool {
                guard let chunk = try? handle.read(upToCount: Int(min(UInt64(chunkSize), size - cursor.offset))),
                      !chunk.isEmpty
                else { return false }
                cursor.offset += UInt64(chunk.count)
                split(chunk, cursor: cursor, maxLineBytes: maxLineBytes, line: line)
                return true
            }
            guard more else { break }
        }
    }

    private static func split(_ chunk: Data, cursor: UsageLogCursor, maxLineBytes: Int, line: (Data) -> Void) {
        var buffer = cursor.pending
        let carried = buffer.count
        buffer.append(chunk)
        var start = 0
        var ranges: [Range<Int>] = []
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            // What was carried over holds no line break, so the search starts after it.
            var position = carried
            while position < raw.count, let found = memchr(base + position, 0x0A, raw.count - position) {
                let end = base.distance(to: UnsafeRawPointer(found))
                ranges.append(start..<end)
                start = end + 1
                position = start
            }
        }
        for range in ranges {
            if cursor.discarding {
                cursor.discarding = false
                continue
            }
            if !range.isEmpty, range.count <= maxLineBytes { line(buffer.subdata(in: range)) }
        }
        if cursor.discarding || buffer.count - start > maxLineBytes {
            // Keeping the rest of an oversized line would only grow a buffer that is never delivered.
            cursor.pending = Data()
            cursor.discarding = true
        } else {
            cursor.pending = start < buffer.count ? buffer.subdata(in: start..<buffer.count) : Data()
        }
    }

    /// `.jsonl` files below `roots` modified at or after `since`. A reply is written before its file's
    /// modification time, so a file untouched since then holds nothing newer.
    static func logs(under roots: [URL], changedSince since: Date) -> [String] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        var found: [(String, Date)] = []
        var seen = Set<String>()
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= since,
                      seen.insert(canonical(url.path)).inserted
                else { continue }
                found.append((url.path, modified))
            }
        }
        // Oldest first, so a reply logged twice keeps its earliest copy's position.
        return found.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// The path the file system reports (FSEvents gives real paths; roots may sit behind a symlink).
    static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
