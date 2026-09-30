import Foundation
import OpusBarWire

let environment = ProcessInfo.processInfo.environment
let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
if arguments.first == StatusLineRelay.argument {
    exit(StatusLineRelay.run(stdin: .standardInput, arguments: arguments, paths: .current(environment: environment), now: Date()))
}
exit(HookForwarder.run(
    stdin: .standardInput,
    arguments: arguments,
    environment: environment,
    parentPID: getppid(),
    nowMs: { Int64(Date().timeIntervalSince1970 * 1000) },
    paths: .current(environment: environment)
))
