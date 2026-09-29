import Foundation
import OpusBarWire

let environment = ProcessInfo.processInfo.environment
exit(HookForwarder.run(
    stdin: .standardInput,
    arguments: Array(ProcessInfo.processInfo.arguments.dropFirst()),
    environment: environment,
    parentPID: getppid(),
    nowMs: { Int64(Date().timeIntervalSince1970 * 1000) },
    paths: .current(environment: environment)
))
