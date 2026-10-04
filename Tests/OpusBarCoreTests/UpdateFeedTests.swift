import CryptoKit
@testable import OpusBarCore
import XCTest

final class UpdateFeedTests: XCTestCase {
    private func release(tag: String = "v0.2.0", assets: [String]? = nil, draft: Bool = false, prerelease: Bool = false) -> Data {
        let names = assets ?? ["OpusBar-0.2.0.zip", "OpusBar-0.2.0.zip.sig", "OpusBar-0.2.0.dmg"]
        let list = names.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/kushalBanda/OpusBar/releases/download/\#(tag)/\#($0)"}"# }
        return Data(#"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(prerelease),"html_url":"https://github.com/kushalBanda/OpusBar/releases/tag/\#(tag)","assets":[\#(list.joined(separator: ","))]}"#.utf8)
    }

    func testVersionsCompareByNumber() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.9.0")), try XCTUnwrap(AppVersion("v0.10.0")))
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertNil(AppVersion("1.0-beta"))
        XCTAssertNil(AppVersion(""))
        XCTAssertEqual(AppVersion("v1.2.3")?.description, "1.2.3")
    }

    func testReleaseNeedsZipAndSignature() throws {
        let found = try XCTUnwrap(UpdateFeed.release(fromGitHub: release()))
        XCTAssertEqual(found.version.description, "0.2.0")
        XCTAssertEqual(found.zip.lastPathComponent, "OpusBar-0.2.0.zip")
        XCTAssertEqual(found.signature.lastPathComponent, "OpusBar-0.2.0.zip.sig")
        XCTAssertNil(UpdateFeed.release(fromGitHub: release(assets: ["OpusBar-0.2.0.zip"])), "unsigned zip is never offered")
        XCTAssertNil(UpdateFeed.release(fromGitHub: release(draft: true)))
        XCTAssertNil(UpdateFeed.release(fromGitHub: release(prerelease: true)))
        XCTAssertNil(UpdateFeed.release(fromGitHub: Data("not json".utf8)))
    }

    func testOnlyNewerIsOffered() throws {
        let found = UpdateFeed.release(fromGitHub: release())
        XCTAssertNotNil(UpdateFeed.newer(found, than: try XCTUnwrap(AppVersion("0.1.0"))))
        XCTAssertNil(UpdateFeed.newer(found, than: try XCTUnwrap(AppVersion("0.2.0"))))
        XCTAssertNil(UpdateFeed.newer(found, than: try XCTUnwrap(AppVersion("0.3"))))
    }

    func testSignatureChecksOutOnlyForTheSignedBytesAndKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let zip = Data("zip bytes".utf8)
        let signature = try key.signature(for: zip).base64EncodedString()
        XCTAssertTrue(UpdateFeed.verify(zip, signature: signature + "\n", publicKey: publicKey))
        XCTAssertFalse(UpdateFeed.verify(Data("tampered".utf8), signature: signature, publicKey: publicKey))
        XCTAssertFalse(UpdateFeed.verify(zip, signature: signature, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
        XCTAssertFalse(UpdateFeed.verify(zip, signature: "garbage", publicKey: publicKey))
        XCTAssertNotNil(Data(base64Encoded: UpdateFeed.publicKey).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) },
                        "the built-in key is a real Ed25519 key")
    }
}

final class ReleaseNotesTests: XCTestCase {
    func testBulletsBecomePlainHighlights() {
        let body = "- **Logos** replace the `dots`.\n* See [notes](https://x.y) here\nplain line\n- \n- Third\n- Fourth\n- Fifth"
        XCTAssertEqual(ReleaseNotes.highlights(from: body),
                       ["Logos replace the dots.", "See notes here", "Third", "Fourth"])
        XCTAssertEqual(ReleaseNotes.highlights(from: body, limit: 1), ["Logos replace the dots."])
    }

    func testNoBulletsFallsBack() {
        XCTAssertEqual(ReleaseNotes.highlights(from: ""), [ReleaseNotes.fallback])
        XCTAssertEqual(ReleaseNotes.highlights(from: "OpusBar 0.2.0"), [ReleaseNotes.fallback])
    }

    func testFeedCarriesTheReleaseBody() throws {
        let json = #"{"tag_name":"v0.2.0","body":"- One","html_url":"https://github.com/x/y","assets":[{"name":"OpusBar-0.2.0.zip","browser_download_url":"https://x/z.zip"},{"name":"OpusBar-0.2.0.zip.sig","browser_download_url":"https://x/z.sig"}]}"#
        XCTAssertEqual(try XCTUnwrap(UpdateFeed.release(fromGitHub: Data(json.utf8))).notes, "- One")
    }

    @MainActor
    func testWhatsNewPersists() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "whatsnew-\(UUID().uuidString)"))
        let first = Preferences(defaults: defaults)
        XCTAssertTrue(first.installUpdatesAutomatically)
        XCTAssertNil(first.whatsNew)
        first.whatsNew = WhatsNew(version: "0.2.0", highlights: ["One"])
        XCTAssertEqual(Preferences(defaults: defaults).whatsNew, WhatsNew(version: "0.2.0", highlights: ["One"]))
        first.whatsNew = nil
        XCTAssertNil(Preferences(defaults: defaults).whatsNew)
    }
}
