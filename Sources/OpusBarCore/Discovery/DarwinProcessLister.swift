import Darwin
import Foundation
import OpusBarWire

/// Lists processes in-process through libproc and sysctl. Never spawns `ps`, never reads another
/// process's environment: only argv is parsed out of `KERN_PROCARGS2`.
public protocol ProcessListing: Sendable {
    func processes() -> [AgentProcess]
    func workingDirectory(pid: Int32) -> String?
}

public struct DarwinProcessLister: ProcessListing {
    /// Larger argument buffers are skipped; agent command lines are short.
    static let maxProcArgsBytes = 256 * 1024

    public init() {}

    public func processes() -> [AgentProcess] {
        Self.allPIDs().compactMap { pid in
            guard let info = Self.bsdInfo(pid: pid) else { return nil }
            let path = Self.executablePath(pid: pid) ?? ""
            return AgentProcess(pid: pid, ppid: info.ppid, startedAt: info.startedAt, executablePath: path,
                                arguments: Self.arguments(pid: pid) ?? [], tty: info.tty)
        }
    }

    public func workingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
        }
    }

    static func allPIDs() -> [Int32] {
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(needed) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return count > 0 ? pids.prefix(Int(count)).filter { $0 > 0 } : []
    }

    static func bsdInfo(pid: Int32) -> (ppid: Int32, startedAt: Date, tty: String?)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let start = TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        return (Int32(bitPattern: info.pbi_ppid), Date(timeIntervalSince1970: start), ttyName(info.e_tdev))
    }

    /// `e_tdev` is NODEV (all ones) when there's no controlling terminal.
    static func ttyName(_ device: UInt32) -> String? {
        guard device != UInt32.max, device != 0, let name = devname(dev_t(bitPattern: device), S_IFCHR) else { return nil }
        let text = String(cString: name)
        return text.isEmpty || text == "??" ? nil : text
    }

    static func executablePath(pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let count = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard count > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(count)).prefix { $0 != 0 }, as: UTF8.self)
    }

    static func arguments(pid: Int32) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0,
              size >= MemoryLayout<Int32>.size, size <= maxProcArgsBytes
        else { return nil }
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
        guard result == 0 else { return nil }
        return parseArguments(procArgs2: data.prefix(size))
    }

    /// `KERN_PROCARGS2` layout: argc (Int32), exec path, NUL padding, argc NUL-terminated strings, then the
    /// environment. Stops after argc strings, so the environment is never read.
    static func parseArguments(procArgs2 data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let argc = Int(bytes.withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) })
        guard argc >= 0, argc <= bytes.count else { return nil }
        var offset = 4
        guard let pathEnd = bytes[offset...].firstIndex(of: 0) else { return nil }
        offset = pathEnd + 1
        while offset < bytes.count, bytes[offset] == 0 { offset += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0) else { return nil }
            arguments.append(String(decoding: bytes[offset..<end], as: UTF8.self))
            offset = end + 1
        }
        return arguments
    }
}
