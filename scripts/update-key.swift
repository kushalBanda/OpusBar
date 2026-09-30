// Ed25519 key for signing OpusBar update zips (ADR 23). The private key stays on this Mac.
//   swift scripts/update-key.swift generate [key-file]   makes the key (once), prints the public key
//   swift scripts/update-key.swift public   [key-file]   prints the public key
//   swift scripts/update-key.swift sign <file> [key-file] prints the base64 signature of <file>
// Default key file: ~/.config/opusbar/update-signing.key (mode 600). Back it up: losing it means
// shipping a new public key, which installed copies won't trust.
import CryptoKit
import Foundation

let args = CommandLine.arguments.dropFirst()
let defaultKey = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/opusbar/update-signing.key").path

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func load(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("No signing key at \(path). Run: swift scripts/update-key.swift generate") }
    return key
}

switch args.first {
case "generate":
    let path = args.dropFirst().first ?? defaultKey
    if FileManager.default.fileExists(atPath: path) { fail("\(path) exists; not replacing it.") }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                   attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(load(args.dropFirst().first ?? defaultKey).publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard let file = args.dropFirst().first, let data = FileManager.default.contents(atPath: file) else { fail("sign <file> [key-file]") }
    let key = load(args.dropFirst(2).first ?? defaultKey)
    print(try key.signature(for: data).base64EncodedString())
default:
    fail("usage: update-key.swift generate|public|sign <file> [key-file]")
}
