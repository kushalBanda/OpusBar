import Foundation
import Observation

/// What this copy of OpusBar may do. Features ask only `isPro` (ADRs 10, 13, 14).
/// A key is checked with the store once, when it's entered; after that Pro works offline for good.
@MainActor @Observable
public final class Entitlements {
    /// One-time price, shown wherever Pro is offered. Set in the store too (ADR 14).
    public static let proPrice = "$6.99"

    public enum ActivationError: Error, Equatable {
        case empty
        case invalid
        case unreachable
        case notConfigured

        public var message: String {
            switch self {
            case .empty: "Paste the key from your receipt email."
            case .invalid: "That key isn't valid. Check it against your receipt email, or it may have been refunded."
            case .unreachable: "Couldn't reach Polar to check the key. Check your connection and try again."
            case .notConfigured: "This build can't check keys yet."
            }
        }
    }

    public private(set) var isPro: Bool
    public private(set) var license: StoredLicense?
    /// Where Buy Pro goes; nil hides the button.
    public let checkoutURL: URL?

    @ObservationIgnored private let provider: LicenseProvider?
    @ObservationIgnored private let cache: LicenseCache?
    @ObservationIgnored private let now: () -> Date

    public init(provider: LicenseProvider, cache: LicenseCache, checkoutURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.checkoutURL = checkoutURL
        self.cache = cache
        self.now = now
        let stored = cache.load()
        license = stored
        isPro = stored != nil
    }

    /// Fixed plan, no store: previews and the DEBUG `--pro` flag.
    public init(isPro: Bool = false) {
        provider = nil
        cache = nil
        now = Date.init
        checkoutURL = nil
        license = nil
        self.isPro = isPro
    }

    /// Checks the key with the store and unlocks Pro when it's good. Returns what went wrong, if anything.
    @discardableResult
    public func activate(key rawKey: String) async -> ActivationError? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .empty }
        guard let provider, let cache else { return .notConfigured }
        let result: LicenseCheck
        do {
            result = try await provider.check(key: key)
        } catch PolarLicenseProvider.Failure.notConfigured {
            return .notConfigured
        } catch {
            return .unreachable
        }
        guard result == .valid else { return .invalid }
        let stored = StoredLicense(key: key, checkedAt: now())
        // Pro even if the Keychain write fails; the user is asked again next launch.
        try? cache.save(stored)
        license = stored
        isPro = true
        return nil
    }

    /// Forgets the key on this Mac (to move it elsewhere or give it away). The key stays valid.
    public func deactivate() {
        cache?.clear()
        license = nil
        isPro = false
    }

    /// The key as shown in Settings: enough to recognize it, not enough to copy it off a screenshot.
    public static func masked(_ key: String) -> String {
        key.count <= 4 ? key : "•••• " + key.suffix(4)
    }

    /// The line a Free user sees where a Pro feature would be.
    public static func hint(for feature: String) -> String {
        "\(feature) is Pro · one-time \(proPrice)"
    }
}
