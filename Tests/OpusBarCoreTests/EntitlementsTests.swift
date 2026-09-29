import Foundation
import XCTest
@testable import OpusBarCore

private final class MemoryCache: LicenseCache, @unchecked Sendable {
    var stored: StoredLicense?
    init(_ stored: StoredLicense? = nil) { self.stored = stored }
    func load() -> StoredLicense? { stored }
    func save(_ license: StoredLicense) throws { stored = license }
    func clear() { stored = nil }
}

private struct FixedProvider: LicenseProvider {
    var result: Result<LicenseCheck, Error>
    func check(key: String) async throws -> LicenseCheck { try result.get() }
}

@MainActor
final class EntitlementsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testFreeUntilALicenseSaysOtherwise() {
        XCTAssertFalse(Entitlements(provider: FixedProvider(result: .success(.valid)), cache: MemoryCache()).isPro)
    }

    func testStoredLicenseIsProAtLaunchWithoutAskingTheStore() {
        let offline = FixedProvider(result: .failure(URLError(.notConnectedToInternet)))
        let entitlements = Entitlements(provider: offline, cache: MemoryCache(StoredLicense(key: "K", checkedAt: t0)))
        XCTAssertTrue(entitlements.isPro)
    }

    func testValidKeyUnlocksAndIsSavedTrimmed() async {
        let cache = MemoryCache()
        let entitlements = Entitlements(provider: FixedProvider(result: .success(.valid)), cache: cache, now: { self.t0 })
        let error = await entitlements.activate(key: "  ABCD-1234\n")
        XCTAssertNil(error)
        XCTAssertTrue(entitlements.isPro)
        XCTAssertEqual(cache.stored, StoredLicense(key: "ABCD-1234", checkedAt: t0))
    }

    func testInvalidOrUnreachableStaysFreeAndSavesNothing() async {
        for (result, expected) in [(Result<LicenseCheck, Error>.success(.invalid), Entitlements.ActivationError.invalid),
                                   (.failure(URLError(.timedOut)), .unreachable),
                                   (.failure(PolarLicenseProvider.Failure.notConfigured), .notConfigured)] {
            let cache = MemoryCache()
            let entitlements = Entitlements(provider: FixedProvider(result: result), cache: cache)
            let error = await entitlements.activate(key: "K")
            XCTAssertEqual(error, expected)
            XCTAssertFalse(entitlements.isPro)
            XCTAssertNil(cache.stored)
        }
    }

    func testEmptyKeyNeverReachesTheStore() async {
        let entitlements = Entitlements(provider: FixedProvider(result: .success(.valid)), cache: MemoryCache())
        let error = await entitlements.activate(key: "   ")
        XCTAssertEqual(error, .empty)
        XCTAssertFalse(entitlements.isPro)
    }

    func testDeactivateForgetsTheKey() {
        let cache = MemoryCache(StoredLicense(key: "K", checkedAt: t0))
        let entitlements = Entitlements(provider: FixedProvider(result: .success(.valid)), cache: cache)
        entitlements.deactivate()
        XCTAssertFalse(entitlements.isPro)
        XCTAssertNil(cache.stored)
    }

    func testMaskedShowsOnlyTheLastFour() {
        XCTAssertEqual(Entitlements.masked("OPUSBAR-1111-2222-ABCD"), "•••• ABCD")
    }

    func testHintNamesFeatureAndPrice() {
        XCTAssertEqual(Entitlements.hint(for: "Usage and Spend"), "Usage and Spend is Pro · one-time $6.99")
    }
}

/// Serves canned responses and records the request, so the provider runs without the network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (status: Int, body: String) = (200, "{}")
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            return data
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: Self.response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PolarLicenseProviderTests: XCTestCase {
    private func provider(orgId: String = "org-1") -> PolarLicenseProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return PolarLicenseProvider(store: PolarStore(apiBase: PolarStore.sandboxAPI, organizationId: orgId, checkoutURL: nil),
                                    session: URLSession(configuration: configuration))
    }

    func testSendsOnlyKeyAndOrganizationToValidate() async throws {
        StubURLProtocol.response = (200, #"{"status":"granted","expires_at":null}"#)
        let result = try await provider().check(key: "KEY-1")
        XCTAssertEqual(result, .valid)
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString, "https://sandbox-api.polar.sh/v1/customer-portal/license-keys/validate")
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertNil(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
        let body = try JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: String]
        XCTAssertEqual(body, ["key": "KEY-1", "organization_id": "org-1"])
    }

    func testNotFoundRevokedOrMalformedIsInvalid() async throws {
        for status in [404, 422] {
            StubURLProtocol.response = (status, #"{"detail":"x"}"#)
            let result = try await provider().check(key: "K")
            XCTAssertEqual(result, .invalid, "\(status)")
        }
        StubURLProtocol.response = (200, #"{"status":"revoked"}"#)
        let revoked = try await provider().check(key: "K")
        XCTAssertEqual(revoked, .invalid)
    }

    func testExpiredKeyIsInvalid() async throws {
        StubURLProtocol.response = (200, #"{"status":"granted","expires_at":"2020-01-01T00:00:00.000Z"}"#)
        let result = try await provider().check(key: "K")
        XCTAssertEqual(result, .invalid)
    }

    func testServerTroubleThrowsInsteadOfSayingInvalid() async {
        StubURLProtocol.response = (503, "")
        do { _ = try await provider().check(key: "K"); XCTFail("expected a throw") }
        catch { XCTAssertEqual(error as? PolarLicenseProvider.Failure, .unexpectedStatus(503)) }
    }

    func testUnconfiguredStoreNeverCallsOut() async {
        StubURLProtocol.lastRequest = nil
        do { _ = try await provider(orgId: "").check(key: "K"); XCTFail("expected a throw") }
        catch { XCTAssertEqual(error as? PolarLicenseProvider.Failure, .notConfigured) }
        XCTAssertNil(StubURLProtocol.lastRequest)
    }
}
