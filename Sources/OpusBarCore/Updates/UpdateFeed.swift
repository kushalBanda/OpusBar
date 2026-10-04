import CryptoKit
import Foundation

/// A release version, "0.2.0" or "v0.2.0": numbers compared left to right, missing ones count as 0.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// A published release that can replace this app: its version, the zip, the zip's signature, the page.
public struct UpdateRelease: Equatable, Sendable {
    public var version: AppVersion
    public var zip: URL
    public var signature: URL
    public var page: URL
    /// The release description (GitHub markdown); the changelog section for this version.
    public var notes: String = ""
}

/// Where updates come from: the latest GitHub release of the OpusBar repository (ADR 23). Builds aren't
/// notarized, so a download is trusted only when its Ed25519 signature checks out against the key built
/// into the app; the private key never leaves the owner's Mac.
public enum UpdateFeed {
    public static let repository = "kushalBanda/OpusBar"
    public static var latestURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }
    /// Base64 raw Ed25519 public key (`scripts/update-key.swift generate`).
    public static let publicKey = "orEPTnOmo9Ik7EVRjbOr45FKRbpPPRTkIbsWKEM1JPE="

    /// The release in GitHub's "latest release" JSON, if it carries a versioned zip and its signature.
    /// Drafts and prereleases never count. Asset links must be https; `allowHTTP` is for a local test feed.
    public static func release(fromGitHub data: Data, allowHTTP: Bool = false) -> UpdateRelease? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String, let version = AppVersion(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }
        func asset(_ name: String) -> URL? {
            assets.first { $0["name"] as? String == name }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
                .flatMap { $0.scheme == "https" || (allowHTTP && $0.scheme == "http") ? $0 : nil }
        }
        let name = "OpusBar-\(version).zip"
        guard let zip = asset(name), let signature = asset(name + ".sig") else { return nil }
        return UpdateRelease(version: version, zip: zip, signature: signature, page: page, notes: json["body"] as? String ?? "")
    }

    /// A newer release than `current`, or nil.
    public static func newer(_ release: UpdateRelease?, than current: AppVersion) -> UpdateRelease? {
        guard let release, current < release.version else { return nil }
        return release
    }

    /// True when `signature` (base64, as in the `.sig` asset) signs `data` under `publicKey`.
    public static func verify(_ data: Data, signature: String, publicKey: String = publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signatureData = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return key.isValidSignature(signatureData, for: data)
    }
}
