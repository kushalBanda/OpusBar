import Darwin
import Foundation

public enum UnixSocketAddress {
    /// nil when the path does not fit in `sun_path`.
    public static func make(path: String) -> sockaddr_un? {
        let bytes = Array(path.utf8)
        var addr = sockaddr_un()
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }
}

public enum SocketClient {
    /// Connects, writes the whole payload and closes. Never blocks longer than about `timeoutMs`
    /// for the connect and again for the write. Returns false on any failure.
    public static func send(_ payload: Data, toSocketAt path: String, timeoutMs: Int32) -> Bool {
        guard var addr = UnixSocketAddress.make(path: path) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN else { return false }
            guard waitWritable(fd, timeoutMs: timeoutMs) else { return false }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { return false }
        }

        return payload.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var sent = 0
            while sent < buffer.count {
                let n = write(fd, base + sent, buffer.count - sent)
                if n > 0 {
                    sent += n
                } else if n < 0, errno == EAGAIN || errno == EINTR {
                    guard waitWritable(fd, timeoutMs: timeoutMs) else { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }

    private static func waitWritable(_ fd: Int32, timeoutMs: Int32) -> Bool {
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        return poll(&descriptor, 1, timeoutMs) == 1
    }
}
