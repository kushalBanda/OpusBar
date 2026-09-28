import Darwin
import Foundation
import OpusBarWire

/// Listens on a Unix domain socket and emits one `WireEvent` per connection.
/// All socket work happens on a private serial queue; `onEvent` is called on that queue.
public final class SocketServer: @unchecked Sendable {
    public enum StartError: Error, Equatable {
        case pathTooLong
        case socket(Int32)
        case bind(Int32)
        case listen(Int32)
    }

    private let path: String
    private let onEvent: @Sendable (WireEvent) -> Void
    private let queue = DispatchQueue(label: "OpusBar.SocketServer")
    private var source: DispatchSourceRead?
    private var listenFD: Int32 = -1

    public init(path: String, onEvent: @escaping @Sendable (WireEvent) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    deinit { stop() }

    /// Creates the parent directory (0700), removes a stale socket file, binds (0600) and listens.
    public func start() throws {
        guard var addr = UnixSocketAddress.make(path: path) else { throw StartError.pathTooLong }
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.socket(errno) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw StartError.bind(code)
        }
        chmod(path, 0o600)
        guard listen(fd, 64) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw StartError.listen(code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        listenFD = fd
        self.source = source
        source.resume()
    }

    /// Stops listening and removes the socket file.
    public func stop() {
        guard let source else { return }
        source.cancel()
        self.source = nil
        listenFD = -1
        unlink(path)
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            if let event = readEvent(from: client) { onEvent(event) }
            close(client)
        }
    }

    /// Reads one line (capped at `WireEvent.maxLineBytes`) with a short receive timeout.
    private func readEvent(from fd: Int32) -> WireEvent? {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count <= WireEvent.maxLineBytes {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            buffer.append(contentsOf: chunk[0..<n])
            if chunk[0..<n].contains(0x0A) { break }
        }
        let line = buffer.firstIndex(of: 0x0A).map { buffer[..<$0] } ?? buffer[...]
        return try? WireEvent.decode(line: Data(line))
    }
}
