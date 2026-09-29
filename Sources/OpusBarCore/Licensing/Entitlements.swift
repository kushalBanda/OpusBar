import Foundation
import Observation

/// What this copy of OpusBar may do. Features ask only `isPro`; how a key gets checked lives
/// behind it (ADRs 10, 13, 14).
@MainActor @Observable
public final class Entitlements {
    /// One-time price, shown wherever Pro is offered. Set in the store too (ADR 14).
    public static let proPrice = "$6.99"

    public private(set) var isPro: Bool

    public init(isPro: Bool = false) {
        self.isPro = isPro
    }

    /// The line a Free user sees where a Pro feature would be.
    public static func hint(for feature: String) -> String {
        "\(feature) is Pro · one-time \(proPrice)"
    }
}
