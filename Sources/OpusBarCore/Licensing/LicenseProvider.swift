import Foundation

/// What the store says about a key.
public enum LicenseCheck: Equatable, Sendable {
    case valid
    /// Unknown, revoked (refunded), disabled or expired.
    case invalid
}

/// Asks a store whether a license key is good. Throws only when the store couldn't be reached
/// or answered something unexpected; a definite "no" is `.invalid`.
public protocol LicenseProvider: Sendable {
    func check(key: String) async throws -> LicenseCheck
}

/// Where OpusBar Pro is sold (ADR 14). Neither value is a secret.
public struct PolarStore: Equatable, Sendable {
    public var apiBase: URL
    public var organizationId: String
    /// Hosted checkout page for OpusBar Pro; the Buy button opens it in the browser.
    public var checkoutURL: URL?

    public init(apiBase: URL, organizationId: String, checkoutURL: URL?) {
        self.apiBase = apiBase
        self.organizationId = organizationId
        self.checkoutURL = checkoutURL
    }

    public static let liveAPI = URL(string: "https://api.polar.sh")!
    public static let sandboxAPI = URL(string: "https://sandbox-api.polar.sh")!

    /// Filled in once the owner's Polar product exists.
    public static let live = PolarStore(apiBase: liveAPI, organizationId: "", checkoutURL: nil)

    public var isConfigured: Bool { !organizationId.isEmpty }
}

/// Polar's customer-portal validate endpoint: no token, so nothing secret ships in the app.
/// Only the key and the organization id are sent.
public struct PolarLicenseProvider: LicenseProvider {
    public enum Failure: Error, Equatable {
        case notConfigured
        case unexpectedStatus(Int)
    }

    public let store: PolarStore
    let session: URLSession

    public init(store: PolarStore, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    public func check(key: String) async throws -> LicenseCheck {
        guard store.isConfigured else { throw Failure.notConfigured }
        var request = URLRequest(url: store.apiBase.appending(path: "v1/customer-portal/license-keys/validate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(["key": key, "organization_id": store.organizationId])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            struct Body: Decodable { let status: String; let expires_at: Date? }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let text = try decoder.singleValueContainer().decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: text) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: text) { return date }
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            let body = try decoder.decode(Body.self, from: data)
            if let expires = body.expires_at, expires < Date() { return .invalid }
            return body.status == "granted" ? .valid : .invalid
        // 404: not found, revoked, disabled or expired. 422: not even shaped like a key.
        case 404, 422: return .invalid
        default: throw Failure.unexpectedStatus(status)
        }
    }
}
